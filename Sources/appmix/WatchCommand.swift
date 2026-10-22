import Foundation
import MixerCore

/// Runs the menu bar app's monitor and grouping and prints each change, for checking them live.
enum WatchCommand {
    static func run(durationSeconds: Double?) {
        let started = Date()
        let monitor = SystemAudioMonitor { snapshot in
            let playing = AppGrouping.group(snapshot.processes)
                .filter(\.isPlaying)
                .map { "\($0.key) (\($0.processes.count) proc)" }
            print(String(format: "%6.2fs  playing: %@", Date().timeIntervalSince(started),
                         playing.isEmpty ? "nothing" : playing.joined(separator: ", ")))
        }
        monitor.start()
        Signals.onTerminate { exit(0) }
        if let durationSeconds {
            DispatchQueue.main.asyncAfter(deadline: .now() + durationSeconds) { exit(0) }
        }
        dispatchMain()
    }
}
