public struct UsageError: Error, Equatable, CustomStringConvertible {
    public let description: String
}

public struct RouteOptions: Equatable, Sendable {
    public static let defaultVolumePercent = 100.0

    public let app: String
    public let device: String?
    public let volumePercent: Double
    public let showMeter: Bool
    public let durationSeconds: Double?
}

public struct ToneOptions: Equatable, Sendable {
    public static let defaultLevelDecibels = -24.0
    public static let defaultFrequencyHertz = 440.0
    public static let defaultDurationSeconds = 10.0

    public let device: String?
    public let levelDecibels: Double
    public let frequencyHertz: Double
    public let delaySeconds: Double
    public let durationSeconds: Double
}

public enum Command: Equatable, Sendable {
    case help
    case list
    case watch(durationSeconds: Double?)
    case route(RouteOptions)
    case tone(ToneOptions)
}

public enum CommandLineOptions {
    public static let usage = """
    appmix: route one app's audio to an output device at its own volume.

      appmix list
          Apps known to Core Audio (playing ones first) and output devices.

      appmix watch [--duration <s>]
          Print the playing apps every time Core Audio reports a change (what the menu bar app sees).

      appmix route --app <name|bundle-id|pid> [--to <device>] [--volume 0-100] [--meter] [--duration <s>]
          Mute the app at its source and play it on <device> (default: system output).
          While running, type a number 0-100 to change volume, m to mute/unmute, q to quit.

      appmix tone [--to <device>] [--level <dBFS>] [--frequency <Hz>] [--delay <s>] [--duration <s>]
          Play a test sine tone, useful as a source to route.
    """

    public static func parse(_ arguments: [String]) throws -> Command {
        guard let name = arguments.first else { return .help }
        let flags = try parseFlags(Array(arguments.dropFirst()))
        switch name {
        case "help", "--help", "-h": return .help
        case "list": return .list
        case "watch": return .watch(durationSeconds: try number(flags, "--duration", in: 0.1...86_400))
        case "route": return .route(try routeOptions(flags))
        case "tone": return .tone(try toneOptions(flags))
        default: throw UsageError(description: "Unknown command '\(name)'.")
        }
    }

    private static let valueFlags: Set<String> = ["--app", "--to", "--volume", "--duration", "--level", "--frequency", "--delay"]
    private static let switchFlags: Set<String> = ["--meter"]

    private static func parseFlags(_ arguments: [String]) throws -> [String: String] {
        var remaining = arguments[...]
        var flags: [String: String] = [:]
        while let flag = remaining.popFirst() {
            if switchFlags.contains(flag) {
                flags[flag] = "true"
            } else if valueFlags.contains(flag) {
                guard let value = remaining.popFirst(), !value.hasPrefix("--") else {
                    throw UsageError(description: "\(flag) needs a value.")
                }
                flags[flag] = value
            } else {
                throw UsageError(description: "Unknown option '\(flag)'.")
            }
        }
        return flags
    }

    private static func routeOptions(_ flags: [String: String]) throws -> RouteOptions {
        guard let app = flags["--app"] else { throw UsageError(description: "route needs --app.") }
        return RouteOptions(
            app: app,
            device: flags["--to"],
            volumePercent: try number(flags, "--volume", in: 0...100) ?? RouteOptions.defaultVolumePercent,
            showMeter: flags["--meter"] != nil,
            durationSeconds: try number(flags, "--duration", in: 0.1...86_400)
        )
    }

    private static func toneOptions(_ flags: [String: String]) throws -> ToneOptions {
        ToneOptions(
            device: flags["--to"],
            levelDecibels: try number(flags, "--level", in: -96...0) ?? ToneOptions.defaultLevelDecibels,
            frequencyHertz: try number(flags, "--frequency", in: 20...20_000) ?? ToneOptions.defaultFrequencyHertz,
            delaySeconds: try number(flags, "--delay", in: 0...3_600) ?? 0,
            durationSeconds: try number(flags, "--duration", in: 0.1...86_400) ?? ToneOptions.defaultDurationSeconds
        )
    }

    private static func number(_ flags: [String: String], _ flag: String, in range: ClosedRange<Double>) throws -> Double? {
        guard let text = flags[flag] else { return nil }
        guard let value = Double(text), range.contains(value) else {
            throw UsageError(description: "\(flag) must be a number from \(range.lowerBound) to \(range.upperBound).")
        }
        return value
    }
}
