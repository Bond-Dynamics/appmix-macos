import CoreAudio
import Foundation
import os

extension AudioSnapshot {
    /// Reads processes, output devices and the default output. Several hundred ms of IPC: keep it off the main thread.
    public static func current() throws -> AudioSnapshot {
        let devices = try AudioDeviceCatalog.outputs()
        return AudioSnapshot(
            processes: try AudioProcessCatalog.all(),
            devices: devices,
            defaultOutputUID: try AudioDeviceCatalog.defaultOutput().uid,
            deviceVolumes: CoreAudioDeviceVolume.volumes(of: devices)
        )
    }
}

/// Watches Core Audio and delivers a fresh snapshot whenever apps, devices, the default output,
/// any app's playing state, or any output device's volume or mute change. Event-driven, no polling. Events are coalesced so a burst
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
    /// Volume keys, the menu bar and hardware knobs change these; only volumes are re-read for them.
    private static let deviceProperties: [(AudioObjectPropertySelector, AudioObjectPropertyScope)] =
        (CoreAudioDeviceVolume.volumeSelectors + [CoreAudioDeviceVolume.muteSelector]).map { ($0, kAudioObjectPropertyScopeOutput) }
    private static let log = Logger(subsystem: "local.appmix", category: "monitor")

    /// A volume-only change skips the slow process and device reads.
    private enum Refresh: Comparable {
        case volumes
        case everything
    }

    private let queue = DispatchQueue(label: "appmix.monitor")
    private let onChange: @Sendable (AudioSnapshot) -> Void
    // Everything below is touched only on `queue`.
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var processListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var deviceListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var pendingRefresh: Refresh?
    private var lastSnapshot: AudioSnapshot?
    private var stopped = false

    public init(onChange: @escaping @Sendable (AudioSnapshot) -> Void) {
        self.onChange = onChange
    }

    public func start() {
        queue.async { [weak self] in
            guard let self else { return }
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleRefresh(.everything) }
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
            stopped = true
            processListeners.forEach { unwatch($0.key, $0.value, Self.processProperties) }
            deviceListeners.forEach { unwatch($0.key, $0.value, Self.deviceProperties) }
            systemListener = nil
            processListeners = [:]
            deviceListeners = [:]
        }
    }

    private func scheduleRefresh(_ kind: Refresh) {
        if let pendingRefresh {
            self.pendingRefresh = max(pendingRefresh, kind)
            return
        }
        pendingRefresh = kind
        queue.asyncAfter(deadline: .now() + Self.coalesceDelay) {
            let kind = self.pendingRefresh ?? .everything
            self.pendingRefresh = nil
            // A refresh queued before `stop()` would otherwise add the listeners back.
            guard !self.stopped else { return }
            kind == .everything ? self.refresh() : self.refreshVolumes()
        }
    }

    private func refresh() {
        do {
            let snapshot = try AudioSnapshot.current()
            watchPlayingState(of: snapshot.processes.map(\.objectID))
            watchVolume(of: snapshot.devices.map(\.id))
            deliver(snapshot)
        } catch {
            Self.log.error("Audio snapshot failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func refreshVolumes() {
        guard let lastSnapshot else { return refresh() }
        deliver(lastSnapshot.with(deviceVolumes: CoreAudioDeviceVolume.volumes(of: lastSnapshot.devices)))
    }

    private func deliver(_ snapshot: AudioSnapshot) {
        lastSnapshot = snapshot
        onChange(snapshot)
    }

    /// Listens to each process's "is playing" flag, adding and dropping listeners as processes come and go.
    private func watchPlayingState(of objects: [AudioObjectID]) {
        processListeners = watch(objects, Self.processProperties, kind: .everything, replacing: processListeners)
    }

    /// Listens to each output device's volume and mute.
    private func watchVolume(of devices: [AudioObjectID]) {
        deviceListeners = watch(devices, Self.deviceProperties, kind: .volumes, replacing: deviceListeners)
    }

    /// Adds listeners for new objects and drops those for objects that are gone. Only properties an object
    /// has are watched, so a fixed-volume device gets no listener and logs no error.
    private func watch(
        _ objects: [AudioObjectID], _ properties: [(AudioObjectPropertySelector, AudioObjectPropertyScope)],
        kind: Refresh, replacing existing: [AudioObjectID: AudioObjectPropertyListenerBlock]
    ) -> [AudioObjectID: AudioObjectPropertyListenerBlock] {
        let current = Set(objects)
        existing.filter { !current.contains($0.key) }.forEach { unwatch($0.key, $0.value, properties) }
        let added = current.subtracting(existing.keys).map { object in
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleRefresh(kind) }
            properties
                .filter { CoreAudioProperty.has(object, $0.0, scope: $0.1) }
                .forEach { add(listener, to: object, $0.0, $0.1) }
            return (object, listener)
        }
        return existing.filter { current.contains($0.key) }.merging(added) { old, _ in old }
    }

    private func unwatch(
        _ object: AudioObjectID, _ listener: @escaping AudioObjectPropertyListenerBlock,
        _ properties: [(AudioObjectPropertySelector, AudioObjectPropertyScope)]
    ) {
        properties.forEach { remove(listener, from: object, $0.0, $0.1) }
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

    /// Removal can fail for a process that already exited, or a property the object never had;
    /// both are expected and harmless.
    private func remove(
        _ listener: @escaping AudioObjectPropertyListenerBlock, from object: AudioObjectID,
        _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope
    ) {
        var address = CoreAudioProperty.address(selector, scope: scope)
        AudioObjectRemovePropertyListenerBlock(object, &address, queue, listener)
    }
}
