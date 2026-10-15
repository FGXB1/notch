import AudioToolbox
import CoreAudio
import Darwin
import Foundation
import NotchCore
import Synchronization

/// Captures what the Mac is playing (every process but Notch) through a Core Audio process tap and
/// reduces it to band levels. Setup: tap → private aggregate device wrapping it → IOProc on our own
/// queue → `SpectrumAnalyzer`. Needs "System Audio Recording" permission (asked on first start); without
/// it the tap delivers silence, which `levels()` reports as nil so the UI falls back to procedural bars.
///
/// All CoreAudio state is confined to `queue`; `levels()` is safe from any thread.
final class SystemAudioTap: @unchecked Sendable {
    private struct Snapshot {
        var levels: [Float]
        var isRunning = false
        /// Host time of the last non-silent buffer.
        var lastSoundAt: UInt64 = 0
    }

    static let bandCount = 4
    /// Silence longer than this (or no permission) hands the bars back to the procedural animation.
    private static let silenceTimeout: Double = 2.5

    private let queue = DispatchQueue(label: "dev.ishan.notch.audio-tap", qos: .userInitiated)
    private let snapshot = Mutex(Snapshot(levels: [Float](repeating: 0, count: SystemAudioTap.bandCount)))

    // Confined to `queue`.
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var analyzer: SpectrumAnalyzer?
    private var isInterleaved = true
    private var channelCount = 2
    private var history: [Float] = []
    private var historyIndex = 0
    private var window: [Float] = []
    private var defaultOutputListener: AudioObjectPropertyListenerBlock?

    func start() {
        queue.async { self.startOnQueue() }
    }

    func stop() {
        queue.async { self.stopOnQueue() }
    }

    /// Latest band levels, or nil when not capturing or nothing audible has arrived recently.
    func levels() -> [Float]? {
        let now = mach_absolute_time()
        return snapshot.withLock { state in
            guard state.isRunning, state.lastSoundAt > 0,
                  Self.seconds(from: state.lastSoundAt, to: now) < Self.silenceTimeout else { return nil }
            return state.levels
        }
    }

    // MARK: Setup

    private func startOnQueue() {
        guard tapID == kAudioObjectUnknown else { return }

        let excluded = Self.processObject(for: getpid()).map { [$0] } ?? []
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
        description.uuid = UUID()
        description.name = "Notch Waveform"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr else {
            Log.media.error("Audio tap failed: \(status)")
            return
        }
        tapID = tap

        guard let format = Self.format(of: tap), format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32,
              let analyzer = SpectrumAnalyzer(sampleRate: format.mSampleRate, bandCount: Self.bandCount) else {
            Log.media.error("Audio tap has an unexpected format")
            stopOnQueue()
            return
        }
        self.analyzer = analyzer
        isInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        channelCount = max(1, Int(format.mChannelsPerFrame))
        history = [Float](repeating: 0, count: analyzer.fftSize)
        window = [Float](repeating: 0, count: analyzer.fftSize)
        historyIndex = 0

        let outputUID = Self.defaultOutputUID() ?? ""
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Notch Waveform",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                              kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device)
        guard status == noErr else {
            Log.media.error("Aggregate device failed: \(status)")
            stopOnQueue()
            return
        }
        aggregateID = device

        status = AudioDeviceCreateIOProcIDWithBlock(&procID, device, queue) { [weak self] _, input, _, _, _ in
            self?.process(input)
        }
        guard status == noErr, let procID else {
            Log.media.error("Audio IOProc failed: \(status)")
            stopOnQueue()
            return
        }
        status = AudioDeviceStart(device, procID)
        guard status == noErr else {
            Log.media.error("Audio tap start failed: \(status)")
            stopOnQueue()
            return
        }

        snapshot.withLock { $0.isRunning = true }
        listenForOutputChanges()
        Log.media.info("Audio tap started (\(Int(format.mSampleRate)) Hz, \(self.channelCount) ch)")
    }

    private func stopOnQueue() {
        if let listener = defaultOutputListener {
            var address = Self.defaultOutputAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
            defaultOutputListener = nil
        }
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        analyzer = nil
        snapshot.withLock { state in
            state.isRunning = false
            state.lastSoundAt = 0
            state.levels = [Float](repeating: 0, count: Self.bandCount)
        }
    }

    /// The aggregate device is built around the output device; rebuild it when the output changes.
    private func listenForOutputChanges() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.tapID != kAudioObjectUnknown else { return }
            self.stopOnQueue()
            self.startOnQueue()
        }
        var address = Self.defaultOutputAddress
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
        defaultOutputListener = listener
    }

    // MARK: Audio

    private func process(_ input: UnsafePointer<AudioBufferList>) {
        guard let analyzer else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first, let firstData = first.mData else { return }

        let floatSize = MemoryLayout<Float>.size
        var loudest: Float = 0
        if isInterleaved || buffers.count < 2 {
            let channels = max(1, Int(first.mNumberChannels))
            let frames = Int(first.mDataByteSize) / (floatSize * channels)
            let samples = firstData.assumingMemoryBound(to: Float.self)
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<channels { sum += samples[frame * channels + channel] }
                append(sum / Float(channels), loudest: &loudest)
            }
        } else {
            let frames = Int(first.mDataByteSize) / floatSize
            let left = firstData.assumingMemoryBound(to: Float.self)
            let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) ?? left
            for frame in 0..<frames {
                append((left[frame] + right[frame]) / 2, loudest: &loudest)
            }
        }

        // Unroll the ring so the newest sample is last.
        let size = history.count
        let tail = size - historyIndex
        window.withUnsafeMutableBufferPointer { destination in
            history.withUnsafeBufferPointer { source in
                destination.baseAddress!.update(from: source.baseAddress! + historyIndex, count: tail)
                (destination.baseAddress! + tail).update(from: source.baseAddress!, count: historyIndex)
            }
        }
        let levels = window.withUnsafeBufferPointer { analyzer.analyze($0) }
        let isAudible = loudest > 1e-4
        let now = mach_absolute_time()
        snapshot.withLock { state in
            state.levels = levels
            if isAudible { state.lastSoundAt = now }
        }
    }

    private func append(_ sample: Float, loudest: inout Float) {
        history[historyIndex] = sample
        historyIndex = (historyIndex + 1) % history.count
        loudest = max(loudest, abs(sample))
    }

    // MARK: CoreAudio helpers

    private static var defaultOutputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                   mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func processObject(for pid: pid_t) -> AudioObjectID? {
        var pid = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    private static func format(of tap: AudioObjectID) -> AudioStreamBasicDescription? {
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format) == noErr ? format : nil
    }

    private static func defaultOutputUID() -> String? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = defaultOutputAddress
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr
        else { return nil }
        var uid: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var uidAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
                                                    mScope: kAudioObjectPropertyScopeGlobal,
                                                    mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &uidSize, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }

    private static func seconds(from start: UInt64, to end: UInt64) -> Double {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(end &- start) * Double(timebase.numer) / Double(timebase.denom) / 1e9
    }
}
