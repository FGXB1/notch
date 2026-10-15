import Foundation
import Testing
@testable import AudioTap

struct SpectrumAnalyzerTests {
    private let sampleRate = 48_000.0

    private func sine(_ frequency: Double, amplitude: Float = 0.5, count: Int = 1024) -> [Float] {
        (0..<count).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / sampleRate)) }
    }

    /// Feeds the same window repeatedly so the smoothing settles.
    private func settledLevels(_ samples: [Float]) -> [Float] {
        let analyzer = SpectrumAnalyzer(sampleRate: sampleRate)!
        var levels: [Float] = []
        for _ in 0..<40 { levels = analyzer.analyze(samples) }
        return levels
    }

    @Test func bandsAreContiguousAndLogSpaced() {
        let bands = SpectrumAnalyzer.bandBins(sampleRate: sampleRate, fftSize: 1024, bandCount: 4, low: 60, high: 12_000)
        #expect(bands.count == 4)
        for (lower, upper) in zip(bands, bands.dropFirst()) {
            #expect(lower.upperBound == upper.lowerBound)
        }
        // Each band is wider than the last.
        #expect(bands.map(\.count) == bands.map(\.count).sorted())
        #expect(bands.last!.upperBound <= 512)
    }

    @Test func silenceStaysEmpty() {
        let levels = settledLevels([Float](repeating: 0, count: 1024))
        #expect(levels.allSatisfy { $0 == 0 })
    }

    @Test func toneLightsItsOwnBand() {
        // Bands: 60–225 Hz, 225–850 Hz, 850 Hz–3.2 kHz, 3.2–12 kHz.
        for (frequency, band) in [(110.0, 0), (500.0, 1), (2_000.0, 2), (6_000.0, 3)] {
            let levels = settledLevels(sine(frequency))
            #expect(levels.firstIndex(of: levels.max()!) == band, "\(frequency) Hz → \(levels)")
        }
    }

    @Test func levelsStayInRange() {
        let noise = (0..<1024).map { _ in Float.random(in: -1...1) }
        let levels = settledLevels(noise)
        #expect(levels.allSatisfy { (0...1).contains($0) })
    }

    @Test func quietSignalsAreNotBlownUpToFullScale() {
        // -80 dBFS hiss: below the quietest level the automatic gain will lift.
        let levels = settledLevels(sine(500, amplitude: 0.0001))
        #expect(levels.max()! < 0.5)
    }
}
