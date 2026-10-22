import Foundation
import os

/// Where per-app settings live between launches.
@MainActor
public protocol SettingsStore {
    func load() -> [String: AppSettings]
    func save(_ settings: [String: AppSettings])
}

/// Keeps nothing: for callers that should not remember (and the default in tests).
public struct EphemeralSettingsStore: SettingsStore {
    public init() {}
    public func load() -> [String: AppSettings] { [:] }
    public func save(_ settings: [String: AppSettings]) {}
}

/// JSON in the app's preferences, keyed by app key (bundle ID).
public struct UserDefaultsSettingsStore: SettingsStore {
    static let key = "appSettings.v1"
    private static let log = Logger(subsystem: "local.appmix", category: "settings")

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Unreadable data is logged and treated as "nothing saved", so a bad file never blocks launch.
    public func load() -> [String: AppSettings] {
        guard let data = defaults.data(forKey: Self.key) else { return [:] }
        do {
            return try JSONDecoder().decode([String: AppSettings].self, from: data)
        } catch {
            Self.log.error("Saved settings are unreadable, starting fresh: \(String(describing: error), privacy: .public)")
            return [:]
        }
    }

    public func save(_ settings: [String: AppSettings]) {
        do {
            defaults.set(try JSONEncoder().encode(settings), forKey: Self.key)
        } catch {
            Self.log.error("Could not save settings: \(String(describing: error), privacy: .public)")
        }
    }
}
