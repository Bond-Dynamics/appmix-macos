import AppKit
import Combine
import Observation
import Sparkle
import os

/// Sparkle's updater for the panel (BOND-224). AppMix lives in the menu bar with no Dock icon, so a
/// scheduled check that finds an update doesn't pop a window over whatever the user is doing: the
/// panel shows "Update to …" instead, and Sparkle's window opens when the user asks.
@MainActor
@Observable
final class UpdaterModel: NSObject {
    private static let log = Logger(subsystem: "local.appmix", category: "updates")

    /// False when not running from a bundle with a feed (`swift run`), or if Sparkle failed to start.
    private(set) var isAvailable = false
    private(set) var automaticallyChecks = false
    /// False while Sparkle is busy (checking or downloading in the background), when a check can't start.
    private(set) var canCheck = false
    /// A newer version a scheduled check found that the user hasn't looked at yet.
    private(set) var pendingVersion: String?

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: AnyCancellable?

    override init() {
        super.init()
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
            Self.log.info("Not running from AppMix.app with a feed; updates are off")
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        do {
            try controller.updater.start()
            self.controller = controller
            isAvailable = true
            automaticallyChecks = controller.updater.automaticallyChecksForUpdates
            canCheckObservation = controller.updater.publisher(for: \.canCheckForUpdates)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] value in MainActor.assumeIsolated { self?.canCheck = value } }
            Self.log.info("Updater started, feed \(controller.updater.feedURL?.absoluteString ?? "none", privacy: .public)")
        } catch {
            Self.log.error("Updater did not start: \(String(describing: error), privacy: .public)")
        }
    }

    func checkForUpdates() {
        // A menu bar app has to come forward, or Sparkle's window opens behind the frontmost app.
        NSApplication.shared.activate()
        controller?.checkForUpdates(nil)
    }

    func setAutomaticallyChecks(_ on: Bool) {
        controller?.updater.automaticallyChecksForUpdates = on
        automaticallyChecks = controller?.updater.automaticallyChecksForUpdates ?? false
    }

    fileprivate func noteScheduledUpdate(_ version: String?) {
        pendingVersion = version
        if let version {
            Self.log.info("Update \(version, privacy: .public) is available")
        }
    }
}

/// Sparkle calls its user driver's delegate on the main thread but doesn't mark the protocol
/// `@MainActor`. `@preconcurrency` keeps that a checked runtime assumption; an isolated conformance
/// would say it statically but needs Swift 6.2, and CI builds with 6.1.
extension UpdaterModel: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Let Sparkle show a scheduled update only when it would come up in front anyway (just after launch).
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate && !state.userInitiated {
            noteScheduledUpdate(update.displayVersionString)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        noteScheduledUpdate(nil)
    }

    func standardUserDriverWillFinishUpdateSession() {
        noteScheduledUpdate(nil)
    }
}
