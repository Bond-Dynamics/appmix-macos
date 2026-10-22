import AppKit
import MixerCore
import Observation
import os

struct AppRowModel: Identifiable, Equatable {
    let id: String
    let name: String
    let mainPID: pid_t
    let isPlaying: Bool
    let settings: AppSettings
    let isRouted: Bool
    let error: String?
    /// Set when the app's chosen output is muted or at 0%, so the app would be silent.
    let outputWarning: String?
}

/// Bridges the controller to SwiftUI: snapshots arrive from the monitor, edits go to the controller,
/// and rows are rebuilt after each so the panel always shows the controller's real state.
@MainActor
@Observable
final class MixerViewModel {
    private static let meterInterval = 0.1
    private static let showIdleAppsKey = "showIdleApps"
    private static let log = Logger(subsystem: "local.appmix", category: "panel")
    /// Opens Privacy & Security at Screen & System Audio Recording.
    private static let permissionSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    private(set) var rows: [AppRowModel] = []
    private(set) var deviceRows: [DeviceVolumeRow] = []
    private(set) var devices: [AudioOutputDevice] = []
    private(set) var defaultOutputName = ""
    /// Linear output peak per routed app, refreshed while the panel is open.
    private(set) var levels: [String: Float] = [:]
    /// Keep a row for silent Dock apps too, like the Windows mixer. Remembered across launches.
    private(set) var showIdleApps: Bool

    @ObservationIgnored private let userFacing: UserFacingApps
    @ObservationIgnored private let controller: MixerController
    @ObservationIgnored private let deviceMixer = DeviceMixer(control: CoreAudioDeviceVolume())
    @ObservationIgnored private var monitor: SystemAudioMonitor?
    @ObservationIgnored private var meterTimer: Timer?

    init() {
        let userFacing = UserFacingApps()
        self.userFacing = userFacing
        controller = MixerController(
            factory: TapRouteFactory(), store: UserDefaultsSettingsStore(),
            isUserFacing: { userFacing.contains($0) }
        )
        showIdleApps = UserDefaults.standard.object(forKey: Self.showIdleAppsKey) as? Bool ?? true
        controller.showIdleApps = showIdleApps
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

    func setDeviceVolume(_ percent: Double, for uid: String) { edit { deviceMixer.setVolume(percent, for: uid) } }
    func setDeviceMuted(_ muted: Bool, for uid: String) { edit { deviceMixer.setMuted(muted, for: uid) } }
    func setDeviceEditing(_ isEditing: Bool, for uid: String) {
        isEditing ? deviceMixer.beginEditing(uid) : deviceMixer.endEditing(uid)
    }

    func setShowIdleApps(_ show: Bool) {
        showIdleApps = show
        UserDefaults.standard.set(show, forKey: Self.showIdleAppsKey)
        edit { controller.showIdleApps = show }
    }

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

    /// A volume-only snapshot (volume keys, a knob, a device slider) skips the app reconcile, which could
    /// otherwise retry a failed route on every key press.
    private func apply(_ snapshot: AudioSnapshot) {
        let volumesOnly = snapshot.differsOnlyInVolumes(from: controller.snapshot)
        if !volumesOnly {
            userFacing.refresh(from: snapshot.processes)
            controller.update(snapshot)
        }
        deviceMixer.update(snapshot)
        let previousDevices = deviceRows
        rebuildRows()
        if deviceRows != previousDevices {
            Self.log.info("Devices: \(Self.describe(self.deviceRows), privacy: .public)")
        }
        guard !volumesOnly else { return }
        let names = rows.map { "\($0.name)\($0.isPlaying ? "" : " (not playing)")" }.joined(separator: ", ")
        Self.log.info("Rows (show idle \(self.showIdleApps, privacy: .public)): \(names, privacy: .public)")
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

    private static func describe(_ rows: [DeviceVolumeRow]) -> String {
        rows.map { row in
            let volume = row.volume.percent.map { "\(Int($0.rounded()))%\(row.volume.canSetVolume ? "" : " read-only")" } ?? "fixed"
            let muted = row.volume.isMuted == true ? " muted" : ""
            return "\(row.name) \(volume)\(muted)\(row.isDefault ? " (default)" : "")"
        }
        .joined(separator: ", ")
    }

    private func rebuildRows() {
        let snapshot = controller.snapshot
        devices = snapshot.devices
        deviceRows = deviceMixer.rows
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
                    error: controller.error(for: app.key),
                    outputWarning: deviceMixer.warning(forOutputUID: controller.settings(for: app.key).outputUID)
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
