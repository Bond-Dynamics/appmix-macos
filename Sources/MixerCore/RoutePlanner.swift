import CoreAudio

/// What the user chose for one app. `outputUID == nil` means "follow the system default output".
public struct AppSettings: Equatable, Sendable, Codable {
    public static let passthrough = AppSettings(volumePercent: 100, isMuted: false, outputUID: nil)

    public var volumePercent: Double
    public var isMuted: Bool
    public var outputUID: String?

    public init(volumePercent: Double, isMuted: Bool, outputUID: String?) {
        self.volumePercent = volumePercent
        self.isMuted = isMuted
        self.outputUID = outputUID
    }

    /// Untouched apps play directly, with no tap and no added latency.
    public var needsTap: Bool { self != .passthrough }
}

/// Everything that forces a route to be rebuilt when it changes. Volume and mute are not here:
/// they change live without a rebuild.
public struct RouteTarget: Equatable, Sendable {
    public let deviceUID: String
    public let processObjectIDs: [AudioObjectID]
}

public enum RoutePlanner {
    /// The route an app should have, or nil to leave it untouched.
    public static func target(
        for app: AudioApp, settings: AppSettings, defaultOutputUID: String, availableUIDs: Set<String>
    ) -> RouteTarget? {
        guard settings.needsTap else { return nil }
        let chosen = settings.outputUID.flatMap { availableUIDs.contains($0) ? $0 : nil }
        return RouteTarget(
            deviceUID: chosen ?? defaultOutputUID,
            processObjectIDs: app.processes.map(\.objectID).sorted()
        )
    }
}
