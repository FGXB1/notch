import Foundation
import Testing
@testable import CalendarKit

struct MeetingLinkTests {
    @Test func findsZoomInNotesAndIgnoresHelpLinks() {
        let notes = """
        Join Zoom Meeting
        https://support.zoom.us/hc/en-us/articles/201362193
        https://us02web.zoom.us/j/85123456789?pwd=abcDEF.1
        """
        let link = MeetingLink.detect(in: [nil, nil, notes])
        #expect(link?.service == .zoom)
        #expect(link?.url.absoluteString == "https://us02web.zoom.us/j/85123456789?pwd=abcDEF.1")
    }

    @Test func prefersEarlierFields() {
        let link = MeetingLink.detect(in: ["https://meet.google.com/abc-defg-hij", nil,
                                           "https://zoom.us/j/1"])
        #expect(link?.service == .meet)
    }

    @Test func teamsJoinLinkButNotMeetingOptions() {
        let notes = """
        Microsoft Teams meeting
        Join: https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%22Tid%22%7d
        Meeting options: https://teams.microsoft.com/meetingOptions/?organizerId=1
        """
        #expect(MeetingLink.detect(in: [notes])?.service == .teams)
        #expect(MeetingLink.detect(in: ["https://teams.microsoft.com/meetingOptions/?organizerId=1"]) == nil)
    }

    @Test func otherServices() {
        #expect(MeetingLink.detect(in: ["https://acme.webex.com/meet/jane"])?.service == .webex)
        #expect(MeetingLink.detect(in: ["https://help.webex.com/article/1"]) == nil)
        #expect(MeetingLink.detect(in: ["https://facetime.apple.com/join#v=1&p=abc"])?.service == .facetime)
        #expect(MeetingLink.detect(in: ["Lunch at https://example.com/menu"]) == nil)
    }

    @Test func unwrapsSafeLinksAndHTML() {
        let wrapped = "https://nam12.safelinks.protection.outlook.com/?url=https%3A%2F%2Fzoom.us%2Fj%2F42%3Fpwd%3Dx&data=1"
        #expect(MeetingLink.detect(in: [wrapped])?.url.absoluteString == "https://zoom.us/j/42?pwd=x")

        let html = #"<a href="https://zoom.us/j/42?pwd=x&amp;from=addon">Join</a>"#
        #expect(MeetingLink.detect(in: [html])?.url.absoluteString == "https://zoom.us/j/42?pwd=x&from=addon")
    }

    @Test func trailingPunctuationIsNotPartOfTheLink() {
        #expect(MeetingLink.detect(in: ["Join at https://meet.google.com/abc-defg-hij."])?.url.absoluteString
            == "https://meet.google.com/abc-defg-hij")
    }

    @Test func nativeURLs() {
        let zoom = MeetingLink(service: .zoom, url: URL(string: "https://us02web.zoom.us/j/851?pwd=abc")!)
        #expect(zoom.nativeURL?.absoluteString == "zoommtg://us02web.zoom.us/join?action=join&confno=851&pwd=abc")

        let vanity = MeetingLink(service: .zoom, url: URL(string: "https://zoom.us/my/jane")!)
        #expect(vanity.nativeURL == nil)

        let teams = MeetingLink(service: .teams,
                                url: URL(string: "https://teams.microsoft.com/l/meetup-join/19%3am%40t/0?context=%7b%7d")!)
        #expect(teams.nativeURL?.absoluteString == "msteams:/l/meetup-join/19%3am%40t/0?context=%7b%7d")
    }

    @Test func callLocationsAreNotPlaces() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        func event(location: String) -> CalendarEvent {
            CalendarEvent(id: "e", title: "E", start: start, end: start + 60, location: location)
        }
        #expect(event(location: "Microsoft Teams Meeting").physicalLocation == nil)
        #expect(event(location: "https://zoom.us/j/1").physicalLocation == nil)
        #expect(event(location: "Room 4B").physicalLocation == "Room 4B")
        #expect(event(location: "Room 4B").geocodableAddress == nil)
        #expect(event(location: "1 Apple Park Way, Cupertino").hasTravelDestination)
    }
}
