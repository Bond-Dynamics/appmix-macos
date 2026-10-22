import CoreAudio
import Darwin
import os

public protocol RouteHandle: AnyObject {
    func stop()
}

/// Makes live routes. Swapped for a fake in tests.
@MainActor
public protocol RouteFactory {
    func makeRoute(processes: [AudioProcess], output: AudioOutputDevice, controls: LiveControls) throws -> RouteHandle
}

public struct AudioSnapshot: Equatable, Sendable {
    public let processes: [AudioProcess]
    public let devices: [AudioOutputDevice]
    public let defaultOutputUID: String

    public init(processes: [AudioProcess], devices: [AudioOutputDevice], defaultOutputUID: String) {
        self.processes = processes
        self.devices = devices
        self.defaultOutputUID = defaultOutputUID
    }
}

/// Holds each app's settings and keeps exactly the routes those settings call for.
/// Settings outlive the app's processes and are saved to `store`, so a relaunched app,
/// or AppMix itself after a restart, gets the same route back.
@MainActor
public final class MixerController {
    private struct ActiveRoute {
        let target: RouteTarget
        let handle: RouteHandle
        let controls: LiveControls
    }

    private static let log = Logger(subsystem: "local.appmix", category: "mixer")

    private let factory: RouteFactory
    private let store: SettingsStore
    private let ownPID: pid_t
    public private(set) var snapshot = AudioSnapshot(processes: [], devices: [], defaultOutputUID: "")
    private var appsByKey: [String: AudioApp] = [:]
    private var settingsByKey: [String: AppSettings] = [:]
    private var routes: [String: ActiveRoute] = [:]
    private var errors: [String: String] = [:]

    /// Whether a silent app is still worth a row (a Dock app, not a background service). Injected because
    /// that is an AppKit question; the default shows no idle apps.
    private let isUserFacing: @MainActor (AudioApp) -> Bool

    /// Show user-facing apps that are connected to audio but silent, as the Windows mixer does.
    public var showIdleApps = false

    public init(
        factory: RouteFactory,
        store: SettingsStore = EphemeralSettingsStore(),
        ownPID: pid_t = getpid(),
        isUserFacing: @escaping @MainActor (AudioApp) -> Bool = { _ in false }
    ) {
        self.factory = factory
        self.store = store
        self.ownPID = ownPID
        self.isUserFacing = isUserFacing
        settingsByKey = store.load().filter { $0.value.needsTap }
    }

    /// Apps worth showing: playing now, ones the user has changed, and (with `showIdleApps`) silent
    /// user-facing apps.
    public var apps: [AudioApp] {
        appsByKey.values
            .filter { $0.isPlaying || settingsByKey[$0.key] != nil || (showIdleApps && isUserFacing($0)) }
            .sorted { $0.key < $1.key }
    }

    public func settings(for key: String) -> AppSettings { settingsByKey[key] ?? .passthrough }
    public func isRouted(_ key: String) -> Bool { routes[key] != nil }
    public func error(for key: String) -> String? { errors[key] }

    /// Peaks since the last call, for routed apps only.
    public func takeMeter(for key: String) -> MeterReading? { routes[key]?.controls.takeMeter() }

    public func update(_ newSnapshot: AudioSnapshot) {
        snapshot = newSnapshot
        let grouped = AppGrouping.group(newSnapshot.processes.filter { $0.pid != ownPID })
        appsByKey = Dictionary(uniqueKeysWithValues: grouped.map { ($0.key, $0) })
        Set(routes.keys).union(settingsByKey.keys).forEach(reconcile)
    }

    public func setVolume(_ percent: Double, for key: String) {
        change(key) { $0.volumePercent = min(max(percent, 0), 100) }
    }

    public func setMuted(_ muted: Bool, for key: String) {
        change(key) { $0.isMuted = muted }
    }

    public func setOutput(_ uid: String?, for key: String) {
        change(key) { $0.outputUID = uid }
    }

    public func reset(_ key: String) {
        settingsByKey[key] = nil
        store.save(settingsByKey)
        reconcile(key)
    }

    public func stopAll() {
        routes.values.forEach { $0.handle.stop() }
        routes = [:]
    }

    private func change(_ key: String, _ edit: (inout AppSettings) -> Void) {
        var settings = self.settings(for: key)
        edit(&settings)
        settingsByKey[key] = settings.needsTap ? settings : nil
        store.save(settingsByKey)
        reconcile(key)
    }

    /// Brings one app's route in line with its settings: live update, rebuild, start, or stop.
    private func reconcile(_ key: String) {
        let settings = self.settings(for: key)
        let desired = appsByKey[key].flatMap {
            RoutePlanner.target(
                for: $0, settings: settings,
                defaultOutputUID: snapshot.defaultOutputUID,
                availableUIDs: Set(snapshot.devices.map(\.uid))
            )
        }
        if let current = routes[key], current.target == desired {
            current.controls.setVolume(percent: settings.volumePercent)
            current.controls.setMuted(settings.isMuted)
            return
        }
        routes.removeValue(forKey: key)?.handle.stop()
        errors[key] = nil
        guard let desired, let app = appsByKey[key] else { return }
        start(app, target: desired, settings: settings)
    }

    private func start(_ app: AudioApp, target: RouteTarget, settings: AppSettings) {
        guard let device = snapshot.devices.first(where: { $0.uid == target.deviceUID }) else {
            errors[app.key] = "Output device is not available."
            return
        }
        let controls = LiveControls(volumePercent: settings.volumePercent)
        controls.setMuted(settings.isMuted)
        do {
            let handle = try factory.makeRoute(processes: app.processes, output: device, controls: controls)
            routes[app.key] = ActiveRoute(target: target, handle: handle, controls: controls)
            Self.log.info("Routed \(app.key, privacy: .public) to \(device.name, privacy: .public)")
        } catch {
            errors[app.key] = String(describing: error)
            Self.log.error("Could not route \(app.key, privacy: .public) to \(device.name, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}

/// The real factory: a process tap per app.
public struct TapRouteFactory: RouteFactory {
    public init() {}

    public func makeRoute(processes: [AudioProcess], output: AudioOutputDevice, controls: LiveControls) throws -> RouteHandle {
        let route = TapRoute(processes: processes, output: output, controls: controls)
        try route.start()
        return route
    }
}

extension TapRoute: RouteHandle {}
