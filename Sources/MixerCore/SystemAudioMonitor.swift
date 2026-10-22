import CoreAudio
import Foundation
import os

extension AudioSnapshot {
    /// Reads processes, output devices and the default output. Several hundred ms of IPC: keep it off the main thread.
    public static func current() throws -> AudioSnapshot {
        AudioSnapshot(
            processes: try AudioProcessCatalog.all(),
            devices: try AudioDeviceCatalog.outputs(),
            defaultOutputUID: try AudioDeviceCatalog.defaultOutput().uid
        )
    }
}

/// Watches Core Audio and delivers a fresh snapshot whenever apps, devices, the default output,
/// or any app's playing state change. Event-driven, no polling. Events are coalesced so a burst
/// (an app opening five helpers) costs one refresh.
public final class SystemAudioMonitor: @unchecked Sendable {
    private static let coalesceDelay = 0.15
    private static let systemSelectors = [
        kAudioHardwarePropertyProcessObjectList,
        kAudioHardwarePropertyDevices,
        kAudioHardwarePropertyDefaultOutputDevice,
    ]
    /// `kAudioProcessPropertyIsRunningOutput` is the value we want but it never notifies (checked on
    /// macOS 27), so watch the two process properties that do change when an app starts or stops playing.
    private static let processProperties: [(AudioObjectPropertySelector, AudioObjectPropertyScope)] = [
        (kAudioProcessPropertyIsRunning, kAudioObjectPropertyScopeGlobal),
        (kAudioProcessPropertyDevices, kAudioObjectPropertyScopeOutput),
    ]
    private static let log = Logger(subsystem: "local.appmix", category: "monitor")

    private let queue = DispatchQueue(label: "appmix.monitor")
    private let onChange: @Sendable (AudioSnapshot) -> Void
    // Everything below is touched only on `queue`.
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var processListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var refreshPending = false

    public init(onChange: @escaping @Sendable (AudioSnapshot) -> Void) {
        self.onChange = onChange
    }

    public func start() {
        queue.async { [weak self] in
            guard let self else { return }
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleRefresh() }
            Self.systemSelectors.forEach { self.add(listener, to: AudioObjectID(kAudioObjectSystemObject), $0, kAudioObjectPropertyScopeGlobal) }
            systemListener = listener
            refresh()
        }
    }

    public func stop() {
        queue.sync {
            if let systemListener {
                Self.systemSelectors.forEach { self.remove(systemListener, from: AudioObjectID(kAudioObjectSystemObject), $0, kAudioObjectPropertyScopeGlobal) }
            }
            processListeners.forEach { unwatch($0.key, $0.value) }
            systemListener = nil
            processListeners = [:]
        }
    }

    private func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        queue.asyncAfter(deadline: .now() + Self.coalesceDelay) {
            self.refreshPending = false
            self.refresh()
        }
    }

    private func refresh() {
        do {
            let snapshot = try AudioSnapshot.current()
            watchPlayingState(of: snapshot.processes.map(\.objectID))
            onChange(snapshot)
        } catch {
            Self.log.error("Audio snapshot failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Listens to each process's "is playing" flag, adding and dropping listeners as processes come and go.
    private func watchPlayingState(of objects: [AudioObjectID]) {
        let current = Set(objects)
        processListeners.filter { !current.contains($0.key) }.forEach {
            unwatch($0.key, $0.value)
            processListeners[$0.key] = nil
        }
        current.subtracting(processListeners.keys).forEach { object in
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleRefresh() }
            Self.processProperties.forEach { add(listener, to: object, $0.0, $0.1) }
            processListeners[object] = listener
        }
    }

    private func unwatch(_ object: AudioObjectID, _ listener: @escaping AudioObjectPropertyListenerBlock) {
        Self.processProperties.forEach { remove(listener, from: object, $0.0, $0.1) }
    }

    private func add(
        _ listener: @escaping AudioObjectPropertyListenerBlock, to object: AudioObjectID,
        _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope
    ) {
        var address = CoreAudioProperty.address(selector, scope: scope)
        let status = AudioObjectAddPropertyListenerBlock(object, &address, queue, listener)
        if status != noErr {
            Self.log.error("Listen to '\(selector)' on \(object) failed: \(status)")
        }
    }

    /// Removal can fail for a process that already exited; that is expected and harmless.
    private func remove(
        _ listener: @escaping AudioObjectPropertyListenerBlock, from object: AudioObjectID,
        _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope
    ) {
        var address = CoreAudioProperty.address(selector, scope: scope)
        AudioObjectRemovePropertyListenerBlock(object, &address, queue, listener)
    }
}
