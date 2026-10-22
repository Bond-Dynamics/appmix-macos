import CoreAudio
import Foundation

/// Taps a set of processes (muting them at the source) and plays their audio on one output device.
///
/// Pipeline: process tap → private aggregate device (output device as clock + tap as input stream)
/// → IOProc that copies the tap stream to the output streams with live gain.
/// The tap and aggregate are private to this process, so Core Audio removes them if it dies.
/// Call `start` and `stop` from one queue (the CLI uses main); the audio thread touches only `controls`.
public final class TapRoute: @unchecked Sendable {
    /// Our aggregates are visible to this process; the device list filters them out by this prefix.
    static let aggregateUIDPrefix = "appmix-route-"

    public let processes: [AudioProcess]
    public let output: AudioOutputDevice
    public let controls: LiveControls

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private let ioQueue = DispatchQueue(label: "appmix.route.io", qos: .userInteractive)

    public init(processes: [AudioProcess], output: AudioOutputDevice, controls: LiveControls) {
        self.processes = processes
        self.output = output
        self.controls = controls
    }

    deinit { stop() }

    public func start() throws {
        do {
            let tapUUID = try createTap()
            try createAggregate(tapUUID: tapUUID)
            try startIO()
        } catch {
            stop()
            throw error
        }
    }

    /// Tears down in reverse order. Safe to call more than once.
    public func stop() {
        if let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            self.ioProcID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    public func tapFormat() throws -> AudioStreamBasicDescription {
        try CoreAudioProperty.scalar(tapID, kAudioTapPropertyFormat, as: AudioStreamBasicDescription.self)
    }

    private func createTap() throws -> UUID {
        let description = CATapDescription(stereoMixdownOfProcesses: processes.map(\.objectID))
        let uuid = UUID()
        description.uuid = uuid
        description.name = "appmix tap"
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        try check(AudioHardwareCreateProcessTap(description, &tapID), "create process tap")
        return uuid
    }

    private func createAggregate(tapUUID: UUID) throws {
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "appmix route",
            kAudioAggregateDeviceUIDKey: Self.aggregateUIDPrefix + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: output.uid,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output.uid]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tapUUID.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        try check(
            AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID),
            "create aggregate device on '\(output.name)'"
        )
    }

    private func startIO() throws {
        let controls = controls
        // The aggregate lists the output device's own input streams first, then the tap's.
        let tapStreamIndex = output.inputStreamCount
        try check(
            AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, ioQueue) { _, inputData, _, outputData, _ in
                let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
                let outputs = UnsafeMutableAudioBufferListPointer(outputData)
                let gain = controls.effectiveGain
                let tap = tapStreamIndex < inputs.count ? inputs[tapStreamIndex] : nil
                let inputPeak = tap.map { SampleMixing.peak(Self.samples($0)) } ?? 0
                let outputPeak = outputs.reduce(Float(0)) { peak, buffer in
                    max(peak, Self.render(tap, into: buffer, gain: gain))
                }
                controls.record(inputPeak: inputPeak, outputPeak: outputPeak)
            },
            "create IOProc"
        )
        try check(AudioDeviceStart(aggregateID, ioProcID), "start audio on '\(output.name)'")
    }

    private static func samples(_ buffer: AudioBuffer) -> UnsafeBufferPointer<Float> {
        UnsafeBufferPointer(
            start: buffer.mData?.assumingMemoryBound(to: Float.self),
            count: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        )
    }

    private static func render(_ tap: AudioBuffer?, into buffer: AudioBuffer, gain: Float) -> Float {
        let destination = UnsafeMutableBufferPointer(
            start: buffer.mData?.assumingMemoryBound(to: Float.self),
            count: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        )
        guard let tap else {
            destination.update(repeating: 0)
            return 0
        }
        return SampleMixing.render(
            input: samples(tap), inputChannels: Int(tap.mNumberChannels),
            output: destination, outputChannels: Int(buffer.mNumberChannels), gain: gain
        )
    }
}
