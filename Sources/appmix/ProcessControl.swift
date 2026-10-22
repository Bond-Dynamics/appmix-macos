import Foundation
import MixerCore

/// Ctrl-C and SIGTERM run the clean teardown instead of killing the process mid-route.
enum Signals {
    nonisolated(unsafe) private static var sources: [DispatchSourceSignal] = []

    static func onTerminate(_ handler: @escaping @Sendable () -> Void) {
        sources = [SIGINT, SIGTERM].map { number in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler(handler: handler)
            source.resume()
            return source
        }
    }
}

/// Reads volume / mute / quit commands from stdin on a background thread.
enum StdinControls {
    static func start(controls: LiveControls, onQuit: @escaping @Sendable () -> Void) {
        Thread.detachNewThread {
            while let line = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() {
                switch line {
                case "q", "quit":
                    onQuit()
                    return
                case "m", "mute":
                    controls.setMuted(!controls.isMuted)
                    print(controls.isMuted ? "Muted." : "Unmuted at \(Int(controls.volumePercent))%.")
                case let text where Double(text) != nil:
                    controls.setVolume(percent: Double(text)!)
                    print("Volume \(Int(controls.volumePercent))%.")
                case "":
                    continue
                default:
                    print("Type 0-100, m, or q.")
                }
            }
        }
    }
}

enum ToneCommand {
    static func run(_ options: ToneOptions) throws {
        let device = try AudioDeviceCatalog.resolve(options.device)
        let tone = ToneGenerator(device: device, options: options)
        try tone.start()
        print(String(
            format: "Tone %.0f Hz at %.0f dBFS on %@ (pid %d), after %.1fs silence, for %.1fs.",
            options.frequencyHertz, options.levelDecibels, device.name, getpid(), options.delaySeconds, options.durationSeconds
        ))
        let finish: @Sendable () -> Void = {
            DispatchQueue.main.async {
                tone.stop()
                exit(0)
            }
        }
        Signals.onTerminate(finish)
        DispatchQueue.main.asyncAfter(deadline: .now() + options.delaySeconds + options.durationSeconds, execute: finish)
        dispatchMain()
    }
}
