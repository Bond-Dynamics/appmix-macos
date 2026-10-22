import Observation
import os
import ServiceManagement

/// Launch at login through macOS's own login-item service. The state shown is always re-read from
/// the system, so a change made in System Settings > General > Login Items shows up here too.
@MainActor
@Observable
final class LoginItemModel {
    enum State: Equatable {
        case enabled
        case disabled
        /// Registered, but the user must allow it in System Settings > Login Items.
        case needsApproval
    }

    private static let log = Logger(subsystem: "local.appmix", category: "login-item")

    private(set) var state: State = .disabled
    private(set) var error: String?

    init() { refresh() }

    var isOn: Bool { state == .enabled || state == .needsApproval }

    /// A never-registered app can report `.notFound`. Treat it as off and let `register()` try:
    /// if that fails, `setEnabled` shows the system's error instead of hiding the option.
    func refresh() {
        let status = SMAppService.mainApp.status
        state = switch status {
        case .enabled: .enabled
        case .requiresApproval: .needsApproval
        default: .disabled
        }
        Self.log.info("Login item status: \(String(describing: self.state), privacy: .public) (raw \(status.rawValue))")
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            error = nil
        } catch {
            self.error = "Could not \(enabled ? "turn on" : "turn off") launch at login: \(error.localizedDescription)"
            Self.log.error("\(self.error ?? "", privacy: .public)")
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
