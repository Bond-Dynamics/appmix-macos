import CoreAudio
import Foundation

/// Plays a sine tone on an output device: a known, quiet source to route while testing.
/// Call `start` and `stop` from one queue (the CLI uses main); the audio thread touches only the oscillator.
public final class ToneGenerator: @unchecked Sendable {
    public let device: AudioOutputDevice
    private let options: ToneOptions
    private var ioProcID: AudioDeviceIOProcID?
    private let ioQueue = DispatchQueue(label: "appmix.tone.io", qos: .userInteractive)

    public init(device: AudioOutputDevice, options: ToneOptions) {
        self.device = device
        self.options = options
    }

    deinit { stop() }

    public func start() throws {
        let sampleRate = try AudioDeviceCatalog.sampleRate(device.id)
        let oscillator = Oscillator(
            frequency: options.frequencyHertz,
            sampleRate: sampleRate,
            amplitude: SampleMixing.amplitude(fromDecibels: options.levelDecibels),
            silentFrames: Int(options.delaySeconds * sampleRate)
        )
        try check(
            AudioDeviceCreateIOProcIDWithBlock(&ioProcID, device.id, ioQueue) { _, _, _, outputData, _ in
                UnsafeMutableAudioBufferListPointer(outputData).forEach(oscillator.fill)
                oscillator.advance()
            },
            "create tone IOProc"
        )
        try check(AudioDeviceStart(device.id, ioProcID), "start tone on '\(device.name)'")
    }

    public func stop() {
        guard let ioProcID else { return }
        AudioDeviceStop(device.id, ioProcID)
        AudioDeviceDestroyIOProcID(device.id, ioProcID)
        self.ioProcID = nil
    }
}

/// Sine state with an optional silent lead-in. Only touched on the tone's serial I/O queue.
private final class Oscillator: @unchecked Sendable {
    private let phaseStep: Double
    private let amplitude: Float
    private var phase = 0.0
    private var framesThisCycle = 0
    private var silentFramesLeft: Int

    init(frequency: Double, sampleRate: Double, amplitude: Float, silentFrames: Int) {
        phaseStep = 2 * .pi * frequency / sampleRate
        self.amplitude = amplitude
        silentFramesLeft = silentFrames
    }

    /// Writes the same waveform into every channel of an interleaved buffer.
    func fill(_ buffer: AudioBuffer) {
        let channels = max(Int(buffer.mNumberChannels), 1)
        let samples = UnsafeMutableBufferPointer(
            start: buffer.mData?.assumingMemoryBound(to: Float.self),
            count: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        )
        let frames = samples.count / channels
        framesThisCycle = max(framesThisCycle, frames)
        guard silentFramesLeft <= 0 else {
            samples.update(repeating: 0)
            return
        }
        for frame in 0..<frames {
            let value = amplitude * Float(sin(phase + Double(frame) * phaseStep))
            for channel in 0..<channels { samples[frame * channels + channel] = value }
        }
    }

    /// Moves the phase on by one I/O cycle, after every buffer has been filled from the same start.
    func advance() {
        if silentFramesLeft > 0 {
            silentFramesLeft -= framesThisCycle
            framesThisCycle = 0
            return
        }
        phase = (phase + Double(framesThisCycle) * phaseStep).truncatingRemainder(dividingBy: 2 * .pi)
        framesThisCycle = 0
    }
}
