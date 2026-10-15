import Foundation
import Testing
@testable import MediaKit

struct AdapterStreamTests {
    private func message(_ json: String) -> AdapterMessage {
        AdapterMessage.parse(Data(json.utf8))!
    }

    private let full = """
    {"type":"data","diff":false,"payload":{"bundleIdentifier":"com.spotify.client","title":"Song","artist":"Band",\
    "album":"","playing":true,"durationMicros":200000000,"elapsedTimeMicros":10000000,\
    "timestampEpochMicros":1700000000000000,"playbackRate":1,"artworkData":"AAAA","processIdentifier":42}}
    """

    @Test func fullPayloadDecodesIntoNowPlaying() throws {
        var stream = AdapterStream()
        stream.apply(message(full))
        let item = try #require(stream.nowPlaying)
        #expect(item.title == "Song")
        #expect(item.artist == "Band")
        #expect(item.album == nil) // empty strings are treated as missing
        #expect(item.duration == 200)
        #expect(item.elapsedTime == 10)
        #expect(item.timestamp == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(item.processIdentifier == 42)
        #expect(item.isPlaying)
        #expect(stream.artworkBase64 == "AAAA")
    }

    @Test func diffsMergeAndNullRemovesKeys() throws {
        var stream = AdapterStream()
        stream.apply(message(full))
        stream.apply(message(#"{"type":"data","diff":true,"payload":{"playing":false,"artworkData":null}}"#))
        let item = try #require(stream.nowPlaying)
        #expect(item.isPlaying == false)
        #expect(item.title == "Song")
        #expect(stream.artworkBase64 == nil)
    }

    @Test func emptyFullPayloadMeansNothingIsPlaying() {
        var stream = AdapterStream()
        stream.apply(message(full))
        stream.apply(message(#"{"type":"data","diff":false,"payload":{}}"#))
        #expect(stream.nowPlaying == nil)
    }

    @Test func malformedLinesAreIgnored() {
        #expect(AdapterMessage.parse(Data("not json".utf8)) == nil)
        #expect(AdapterMessage.parse(Data(#"{"type":"error","payload":{}}"#.utf8)) == nil)
    }

    @Test func booleansAreNotConfusedWithNumbers() {
        let parsed = message(#"{"type":"data","diff":true,"payload":{"playing":true,"playbackRate":1}}"#)
        #expect(parsed.payload["playing"] == .bool(true))
        #expect(parsed.payload["playbackRate"] == .number(1))
    }
}

struct NowPlayingTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func elapsedExtrapolatesOnlyWhilePlaying() {
        var item = NowPlaying(bundleIdentifier: "x", title: "t", duration: 100, elapsedTime: 10, timestamp: t0,
                              playbackRate: 1, isPlaying: true)
        #expect(item.elapsed(at: t0.addingTimeInterval(5)) == 15)
        item.playbackRate = 2
        #expect(item.elapsed(at: t0.addingTimeInterval(5)) == 20)
        item.isPlaying = false
        #expect(item.elapsed(at: t0.addingTimeInterval(5)) == 10)
    }

    @Test func elapsedIsClampedToDuration() {
        let item = NowPlaying(bundleIdentifier: "x", title: "t", duration: 100, elapsedTime: 95, timestamp: t0,
                              isPlaying: true)
        #expect(item.elapsed(at: t0.addingTimeInterval(60)) == 100)
        #expect(item.progress(at: t0.addingTimeInterval(60)) == 1)
    }

    @Test func pausingDoesNotChangeTrackIdentity() {
        var item = NowPlaying(bundleIdentifier: "x", title: "t", artist: "a", isPlaying: true)
        let identity = item.trackIdentity
        item.isPlaying = false
        item.elapsedTime = 30
        #expect(item.trackIdentity == identity)
    }
}
