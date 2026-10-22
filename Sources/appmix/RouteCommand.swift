import Foundation
import MixerCore

struct NoMatchingAppError: Error, CustomStringConvertible {
    let query: String
    var description: String { "No app matches '\(query)'. Run 'appmix list' to see what Core Audio knows about." }
}

enum RouteCommand {
    private static let meterInterval = 0.5
    /// If the tap has delivered only silence this long while a tapped app reports playing, warn about permission.
    private static let silenceWarningSeconds = 3.0

    static func run(_ options: RouteOptions) throws {
        let processes = ProcessQuery.parse(options.app).select(from: try AudioProcessCatalog.all())
        guard !processes.isEmpty else { throw NoMatchingAppError(query: options.app) }
        let output = try AudioDeviceCatalog.resolve(options.device)
        let controls = LiveControls(volumePercent: options.volumePercent)
        let route = TapRoute(processes: processes, output: output, controls: controls)

        try route.start()
        printBanner(route, options: options)

        let session = RouteSession(route: route, showMeter: options.showMeter)
        Signals.onTerminate { session.finish() }
        StdinControls.start(controls: controls, onQuit: { session.finish() })
        DispatchQueue.main.asyncAfter(deadline: .now() + meterInterval) { session.tick(interval: meterInterval) }
        if let duration = options.durationSeconds {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { session.finish() }
        }
        dispatchMain()
    }

    private static func printBanner(_ route: TapRoute, options: RouteOptions) {
        let apps = route.processes.map { "\($0.label) (pid \($0.pid))" }.joined(separator: ", ")
        let format = (try? route.tapFormat()).map { "\(Int($0.mSampleRate)) Hz, \($0.mChannelsPerFrame) ch" } ?? "unknown"
        print("Routing \(apps)")
        print("     to \(route.output.name) at \(Int(options.volumePercent))%   (tap format: \(format))")
        print("Type 0-100 + Enter for volume, m to mute/unmute, q to quit.")
    }

    /// Owns the meter loop and the single teardown path. Main-queue only.
    final class RouteSession: @unchecked Sendable {
        private let route: TapRoute
        private let showMeter: Bool
        private let startedAt = Date()
        private var silentSeconds = 0.0
        private var warnedSilence = false
        private var maxInputPeak: Float = 0
        private var maxOutputPeak: Float = 0
        private var totalCallbacks = 0

        init(route: TapRoute, showMeter: Bool) {
            self.route = route
            self.showMeter = showMeter
        }

        func tick(interval: Double) {
            let reading = route.controls.takeMeter()
            let elapsed = Date().timeIntervalSince(startedAt)
            maxInputPeak = max(maxInputPeak, reading.inputPeak)
            maxOutputPeak = max(maxOutputPeak, reading.outputPeak)
            totalCallbacks += reading.callbacks
            if showMeter { print(MeterFormat.line(reading, elapsed: elapsed, controls: route.controls)) }
            warnIfSilent(reading, interval: interval)
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) { self.tick(interval: interval) }
        }

        func finish() {
            DispatchQueue.main.async {
                self.route.stop()
                print(String(
                    format: "Stopped. %d I/O callbacks, peak in %@ dBFS, peak out %@ dBFS.",
                    self.totalCallbacks, MeterFormat.db(self.maxInputPeak), MeterFormat.db(self.maxOutputPeak)
                ))
                exit(0)
            }
        }

        private func warnIfSilent(_ reading: MeterReading, interval: Double) {
            silentSeconds = reading.inputPeak == 0 ? silentSeconds + interval : 0
            guard !warnedSilence, silentSeconds >= RouteCommand.silenceWarningSeconds, anyTappedAppPlaying() else { return }
            warnedSilence = true
            fputs("""
            Warning: the app reports it is playing, but the tap has delivered only silence.
            Grant audio capture in System Settings > Privacy & Security > Screen & System Audio Recording
            ("System Audio Recording Only") for AppMix (or the terminal you ran appmix from), then run it again.\n
            """, stderr)
        }

        private func anyTappedAppPlaying() -> Bool {
            let tapped = Set(route.processes.map(\.objectID))
            return ((try? AudioProcessCatalog.all()) ?? []).contains { tapped.contains($0.objectID) && $0.isPlaying }
        }
    }
}

enum MeterFormat {
    static func db(_ amplitude: Float) -> String {
        amplitude > 0 ? String(format: "%.1f", SampleMixing.decibels(amplitude)) : "-inf"
    }

    static func line(_ reading: MeterReading, elapsed: Double, controls: LiveControls) -> String {
        let state = controls.isMuted ? "muted" : "\(Int(controls.volumePercent))%"
        return String(
            format: "%6.1fs  in %6@ dBFS  out %6@ dBFS  vol %@  (%d callbacks)",
            elapsed, db(reading.inputPeak), db(reading.outputPeak), state, reading.callbacks
        )
    }
}
