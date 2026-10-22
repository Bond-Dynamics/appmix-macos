import Foundation

/// Real-time-safe sample math: no allocation, no locks.
public enum SampleMixing {
    /// Copies interleaved `input` into interleaved `output`, scaled by `gain`.
    /// Output channel `c` reads input channel `c % inputChannels`, so mono feeds every output channel.
    /// Frames the input does not cover are zeroed. Returns the peak absolute value written.
    public static func render(
        input: UnsafeBufferPointer<Float>, inputChannels: Int,
        output: UnsafeMutableBufferPointer<Float>, outputChannels: Int,
        gain: Float
    ) -> Float {
        guard inputChannels > 0, outputChannels > 0 else {
            output.update(repeating: 0)
            return 0
        }
        let frames = min(input.count / inputChannels, output.count / outputChannels)
        var peak: Float = 0
        for frame in 0..<frames {
            for channel in 0..<outputChannels {
                let sample = input[frame * inputChannels + channel % inputChannels] * gain
                output[frame * outputChannels + channel] = sample
                peak = max(peak, abs(sample))
            }
        }
        let written = frames * outputChannels
        if written < output.count {
            UnsafeMutableBufferPointer(rebasing: output[written...]).update(repeating: 0)
        }
        return peak
    }

    public static func peak(_ samples: UnsafeBufferPointer<Float>) -> Float {
        samples.reduce(0) { max($0, abs($1)) }
    }

    /// Slider percent to linear gain. Squared so the slider feels even to the ear (50% ≈ -12 dB).
    public static func gain(fromPercent percent: Double) -> Float {
        let fraction = min(max(percent, 0), 100) / 100
        return Float(fraction * fraction)
    }

    public static func decibels(_ amplitude: Float) -> Float {
        amplitude > 0 ? 20 * log10(amplitude) : -.infinity
    }

    public static func amplitude(fromDecibels decibels: Double) -> Float {
        Float(pow(10, decibels / 20))
    }
}
