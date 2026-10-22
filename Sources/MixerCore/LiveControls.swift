import Synchronization

public struct MeterReading: Equatable, Sendable {
    public let inputPeak: Float
    public let outputPeak: Float
    public let callbacks: Int
}

/// State shared between the control thread (volume, mute) and the audio I/O thread (meters).
/// Lock-free so the audio thread never blocks.
public final class LiveControls: Sendable {
    private let volumeBits: Atomic<UInt64>
    private let muted = Atomic<Bool>(false)
    private let inputPeakBits = Atomic<UInt32>(0)
    private let outputPeakBits = Atomic<UInt32>(0)
    private let callbacks = Atomic<Int>(0)

    public init(volumePercent: Double) {
        volumeBits = Atomic(volumePercent.bitPattern)
    }

    public var volumePercent: Double { Double(bitPattern: volumeBits.load(ordering: .relaxed)) }
    public var isMuted: Bool { muted.load(ordering: .relaxed) }

    public var effectiveGain: Float {
        isMuted ? 0 : SampleMixing.gain(fromPercent: volumePercent)
    }

    public func setVolume(percent: Double) {
        volumeBits.store(min(max(percent, 0), 100).bitPattern, ordering: .relaxed)
    }

    public func setMuted(_ value: Bool) {
        muted.store(value, ordering: .relaxed)
    }

    /// Called from the audio thread once per I/O cycle.
    public func record(inputPeak: Float, outputPeak: Float) {
        Self.raise(inputPeakBits, to: inputPeak)
        Self.raise(outputPeakBits, to: outputPeak)
        callbacks.add(1, ordering: .relaxed)
    }

    /// Returns the peaks and callback count since the last call, then resets them.
    public func takeMeter() -> MeterReading {
        MeterReading(
            inputPeak: Float(bitPattern: inputPeakBits.exchange(0, ordering: .relaxed)),
            outputPeak: Float(bitPattern: outputPeakBits.exchange(0, ordering: .relaxed)),
            callbacks: callbacks.exchange(0, ordering: .relaxed)
        )
    }

    private static func raise(_ bits: borrowing Atomic<UInt32>, to value: Float) {
        var current = bits.load(ordering: .relaxed)
        while value > Float(bitPattern: current) {
            let (exchanged, original) = bits.compareExchange(
                expected: current, desired: value.bitPattern, ordering: .relaxed
            )
            if exchanged { return }
            current = original
        }
    }
}
