import Testing
@testable import MixerCore

struct SampleMixingTests {
    private func render(_ input: [Float], inputChannels: Int, outputCount: Int, outputChannels: Int, gain: Float) -> ([Float], Float) {
        var output = [Float](repeating: 99, count: outputCount)
        let peak = input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                SampleMixing.render(
                    input: source, inputChannels: inputChannels,
                    output: destination, outputChannels: outputChannels, gain: gain
                )
            }
        }
        return (output, peak)
    }

    @Test func appliesGainStereoToStereo() {
        let (output, peak) = render([0.2, -0.8, 0.4, 0.6], inputChannels: 2, outputCount: 4, outputChannels: 2, gain: 0.5)
        #expect(output == [0.1, -0.4, 0.2, 0.3])
        #expect(peak == 0.4)
    }

    @Test func duplicatesMonoIntoStereo() {
        let (output, _) = render([0.5, 0.25], inputChannels: 1, outputCount: 4, outputChannels: 2, gain: 1)
        #expect(output == [0.5, 0.5, 0.25, 0.25])
    }

    @Test func zeroFillsWhenOutputIsLongerThanInput() {
        let (output, _) = render([0.5, 0.5], inputChannels: 2, outputCount: 6, outputChannels: 2, gain: 1)
        #expect(output == [0.5, 0.5, 0, 0, 0, 0])
    }

    @Test func peakOfEmptyIsZero() {
        #expect([Float]().withUnsafeBufferPointer(SampleMixing.peak) == 0)
    }

    @Test func volumeCurveIsSquared() {
        #expect(SampleMixing.gain(fromPercent: 0) == 0)
        #expect(SampleMixing.gain(fromPercent: 50) == 0.25)
        #expect(SampleMixing.gain(fromPercent: 100) == 1)
    }

    @Test func convertsBetweenAmplitudeAndDecibels() {
        #expect(SampleMixing.decibels(1) == 0)
        #expect(SampleMixing.decibels(0) == -.infinity)
        #expect(abs(SampleMixing.amplitude(fromDecibels: -20) - 0.1) < 0.000_1)
    }
}

struct LiveControlsTests {
    @Test func muteSilencesWithoutForgettingVolume() {
        let controls = LiveControls(volumePercent: 50)
        controls.setMuted(true)
        #expect(controls.effectiveGain == 0)
        controls.setMuted(false)
        #expect(controls.effectiveGain == 0.25)
    }

    @Test func peaksAccumulateUntilTaken() {
        let controls = LiveControls(volumePercent: 100)
        controls.record(inputPeak: 0.3, outputPeak: 0.2)
        controls.record(inputPeak: 0.1, outputPeak: 0.5)
        let first = controls.takeMeter()
        #expect(first.inputPeak == 0.3)
        #expect(first.outputPeak == 0.5)
        #expect(first.callbacks == 2)
        let second = controls.takeMeter()
        #expect(second.inputPeak == 0 && second.callbacks == 0)
    }
}
