import Accelerate

/// Turns the latest audio samples into a few log-spaced band levels (0...1) for the wing equalizer:
/// Hann window → FFT → mean power per band → dB → shared automatic gain → attack/release smoothing.
/// One instance per stream; not thread-safe (it lives on the tap's queue).
final class SpectrumAnalyzer {
    let fftSize: Int
    let bands: [Range<Int>]

    /// dB between an empty bar and a full one.
    static let range: Float = 40
    /// The gain never lifts anything quieter than this to full scale (keeps hiss and fades down).
    static let quietestCeiling: Float = -48
    /// How fast the gain recovers after a loud passage, in dB per analysis (~100 per second).
    static let ceilingFall: Float = 0.05
    /// Treble carries less energy than bass; lift each band a little so all four bars move.
    static let tiltPerBand: Float = 5
    static let attack: Float = 0.6
    static let release: Float = 0.15

    private let fft: vDSP.FFT<DSPSplitComplex>
    private let window: [Float]
    private var windowed: [Float]
    private var real: [Float]
    private var imaginary: [Float]
    private var power: [Float]
    private var bandDecibels: [Float]
    private var smoothed: [Float]
    private var ceiling = SpectrumAnalyzer.quietestCeiling

    init?(sampleRate: Double, fftSize: Int = 1024, bandCount: Int = 4, lowFrequency: Double = 60,
          highFrequency: Double = 12_000) {
        guard fftSize > 0, fftSize & (fftSize - 1) == 0,
              let fft = vDSP.FFT(log2n: vDSP_Length(fftSize.trailingZeroBitCount), radix: .radix2,
                                 ofType: DSPSplitComplex.self) else { return nil }
        self.fftSize = fftSize
        self.fft = fft
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: fftSize, isHalfWindow: false)
        bands = Self.bandBins(sampleRate: sampleRate, fftSize: fftSize, bandCount: bandCount, low: lowFrequency,
                              high: highFrequency)
        windowed = [Float](repeating: 0, count: fftSize)
        real = [Float](repeating: 0, count: fftSize / 2)
        imaginary = [Float](repeating: 0, count: fftSize / 2)
        power = [Float](repeating: 0, count: fftSize / 2)
        bandDecibels = [Float](repeating: 0, count: bandCount)
        smoothed = [Float](repeating: 0, count: bandCount)
    }

    /// FFT bins for `bandCount` bands spaced evenly in log frequency between `low` and `high`.
    static func bandBins(sampleRate: Double, fftSize: Int, bandCount: Int, low: Double, high: Double) -> [Range<Int>] {
        let binWidth = sampleRate / Double(fftSize)
        let lastBin = fftSize / 2
        var lower = max(1, Int(low / binWidth))
        return (1...bandCount).map { index in
            let edge = low * pow(high / low, Double(index) / Double(bandCount))
            let upper = min(lastBin, max(lower + 1, Int((edge / binWidth).rounded(.up))))
            defer { lower = upper }
            return lower..<upper
        }
    }

    /// `samples`: the most recent `fftSize` mono samples. Returns the smoothed band levels.
    func analyze(_ samples: UnsafeBufferPointer<Float>) -> [Float] {
        precondition(samples.count == fftSize)
        vDSP.multiply(samples, window, result: &windowed)

        let half = fftSize / 2
        real.withUnsafeMutableBufferPointer { realBuffer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                var split = DSPSplitComplex(realp: realBuffer.baseAddress!, imagp: imaginaryBuffer.baseAddress!)
                windowed.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                let input = split
                fft.forward(input: input, output: &split)
                vDSP.squareMagnitudes(split, result: &power)
            }
        }

        // Roughly dBFS: undo the FFT's N² power scaling.
        let normalization = 1 / Float(fftSize * fftSize)
        var loudest = -Float.infinity
        for (index, bins) in bands.enumerated() {
            var sum: Float = 0
            for bin in bins { sum += power[bin] }
            let decibels = 10 * log10(sum / Float(bins.count) * normalization + 1e-12) + Float(index) * Self.tiltPerBand
            bandDecibels[index] = decibels
            loudest = max(loudest, decibels)
        }

        // One gain for all bands, so their relative heights stay meaningful.
        ceiling = max(loudest, max(ceiling - Self.ceilingFall, Self.quietestCeiling))
        let floor = ceiling - Self.range
        for index in smoothed.indices {
            let target = min(1, max(0, (bandDecibels[index] - floor) / Self.range))
            let rate = target > smoothed[index] ? Self.attack : Self.release
            smoothed[index] += (target - smoothed[index]) * rate
        }
        return smoothed
    }

    func analyze(_ samples: [Float]) -> [Float] {
        samples.withUnsafeBufferPointer { analyze($0) }
    }
}
