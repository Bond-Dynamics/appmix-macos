import AppKit
import MixerCore

/// Which audio apps are "real" apps (they appear in the Dock), so they keep a row while silent.
/// Background services such as systemsoundserverd or WebKit helpers are not regular apps.
/// Refreshed once per Core Audio snapshot, so slider drags never touch AppKit.
@MainActor
final class UserFacingApps {
    private var keys: Set<String> = []

    func refresh(from processes: [AudioProcess]) {
        keys = Set(AppGrouping.group(processes).filter(Self.isRegularApp).map(\.key))
    }

    func contains(_ app: AudioApp) -> Bool { keys.contains(app.key) }

    /// By bundle ID first (finds the main app even when only a helper process uses audio),
    /// then by the processes themselves (unbundled apps).
    private static func isRegularApp(_ app: AudioApp) -> Bool {
        let byBundle = AppGrouping.isBundleKey(app.key)
            && NSRunningApplication.runningApplications(withBundleIdentifier: app.key).contains { $0.activationPolicy == .regular }
        return byBundle || app.processes.contains { NSRunningApplication(processIdentifier: $0.pid)?.activationPolicy == .regular }
    }
}
