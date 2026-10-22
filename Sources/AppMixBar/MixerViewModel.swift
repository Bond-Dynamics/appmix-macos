import AppKit
import MixerCore
import Observation

struct AppRowModel: Identifiable, Equatable {
    let id: String
    let name: String
    let mainPID: pid_t
    let isPlaying: Bool
    let settings: AppSettings
    let isRouted: Bool
    let error: String?
}

/// Bridges the controller to SwiftUI: snapshots arrive from the monitor, edits go to the controller,
/// and rows are rebuilt after each so the panel always shows the controller's real state.
@MainActor
@Observable
final class MixerViewModel {
    private static let meterInterval = 0.1
    /// Opens Privacy & Security at Screen & System Audio Recording.
    private static let permissionSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    private(set) var rows: [AppRowModel] = []
    private(set) var devices: [AudioOutputDevice] = []
    private(set) var defaultOutputName = ""
    /// Linear output peak per routed app, refreshed while the panel is open.
    private(set) var levels: [String: Float] = [:]

    @ObservationIgnored private let controller = MixerController(factory: TapRouteFactory(), store: UserDefaultsSettingsStore())
    @ObservationIgnored private var monitor: SystemAudioMonitor?
    @ObservationIgnored private var meterTimer: Timer?

    init() {
        let monitor = SystemAudioMonitor { [weak self] snapshot in
            Task { @MainActor in self?.apply(snapshot) }
        }
        self.monitor = monitor
        monitor.start()
    }

    func setVolume(_ percent: Double, for key: String) { edit { controller.setVolume(percent, for: key) } }
    func setMuted(_ muted: Bool, for key: String) { edit { controller.setMuted(muted, for: key) } }
    func setOutput(_ uid: String?, for key: String) { edit { controller.setOutput(uid, for: key) } }
    func reset(_ key: String) { edit { controller.reset(key) } }

    func icon(for row: AppRowModel) -> NSImage { AppIdentity.icon(key: row.id, pid: row.mainPID) }

    func startMeters() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: Self.meterInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.readMeters() }
        }
    }

    func stopMeters() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    func openPermissionSettings() {
        NSWorkspace.shared.open(Self.permissionSettingsURL)
    }

    func quit() {
        monitor?.stop()
        controller.stopAll()
        NSApplication.shared.terminate(nil)
    }

    private func apply(_ snapshot: AudioSnapshot) {
        controller.update(snapshot)
        rebuildRows()
    }

    private func edit(_ change: () -> Void) {
        change()
        rebuildRows()
    }

    private func readMeters() {
        levels = Dictionary(uniqueKeysWithValues: rows.filter(\.isRouted).compactMap { row in
            controller.takeMeter(for: row.id).map { (row.id, $0.outputPeak) }
        })
    }

    private func rebuildRows() {
        let snapshot = controller.snapshot
        devices = snapshot.devices
        defaultOutputName = snapshot.devices.first { $0.uid == snapshot.defaultOutputUID }?.name ?? "none"
        rows = controller.apps
            .map { app in
                AppRowModel(
                    id: app.key,
                    name: AppIdentity.name(key: app.key, pid: app.mainPID),
                    mainPID: app.mainPID,
                    isPlaying: app.isPlaying,
                    settings: controller.settings(for: app.key),
                    isRouted: controller.isRouted(app.key),
                    error: controller.error(for: app.key)
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
