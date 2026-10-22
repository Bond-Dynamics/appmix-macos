import os

/// One output device as the panel shows it.
public struct DeviceVolumeRow: Equatable, Sendable, Identifiable {
    public let uid: String
    public let name: String
    public let isDefault: Bool
    public let volume: DeviceVolume
    public let error: String?

    public var id: String { uid }
}

/// Holds every output device's volume and mute from the latest snapshot and changes them through
/// `control`. Changes show straight away; the next snapshot replaces them with what the device reports.
@MainActor
public final class DeviceMixer {
    private static let log = Logger(subsystem: "local.appmix", category: "devices")

    private let control: DeviceVolumeControl
    private var devices: [AudioOutputDevice] = []
    private var defaultOutputUID = ""
    private var volumes: [String: DeviceVolume] = [:]
    private var errors: [String: String] = [:]
    /// Devices whose slider is being dragged: their shown volume is the user's, not the last reading,
    /// which always lags a moving thumb.
    private var editing: Set<String> = []

    public init(control: DeviceVolumeControl) {
        self.control = control
    }

    /// The default output first, then by name.
    public var rows: [DeviceVolumeRow] {
        devices
            .map { device in
                DeviceVolumeRow(
                    uid: device.uid, name: device.name, isDefault: device.uid == defaultOutputUID,
                    volume: volumes[device.uid] ?? .fixed, error: errors[device.uid]
                )
            }
            .sorted { ($0.isDefault ? 0 : 1, $0.name.lowercased()) < ($1.isDefault ? 0 : 1, $1.name.lowercased()) }
    }

    public func update(_ snapshot: AudioSnapshot) {
        devices = snapshot.devices
        defaultOutputUID = snapshot.defaultOutputUID
        let present = Set(snapshot.devices.map(\.uid))
        volumes = snapshot.deviceVolumes.reduce(into: [:]) { result, entry in
            let dragged = editing.contains(entry.key) ? volumes[entry.key]?.percent : nil
            result[entry.key] = dragged.map { entry.value.with(percent: $0) } ?? entry.value
        }
        errors = errors.filter { present.contains($0.key) }
        editing = editing.intersection(present)
    }

    public func beginEditing(_ uid: String) { editing.insert(uid) }
    public func endEditing(_ uid: String) { editing.remove(uid) }

    public func setVolume(_ percent: Double, for uid: String) {
        let clamped = min(max(percent, 0), 100)
        change(uid, can: \.canSetVolume, action: "change the volume") { control, device, current in
            try control.setVolume(clamped, of: device)
            return current.with(percent: clamped)
        }
    }

    public func setMuted(_ muted: Bool, for uid: String) {
        change(uid, can: \.canSetMute, action: muted ? "mute" : "unmute") { control, device, current in
            try control.setMuted(muted, of: device)
            return current.with(isMuted: muted)
        }
    }

    /// A caption for an app sent to `uid` when that device can't be heard. Nil for an app that
    /// follows the default output: macOS already shows the default's volume.
    public func warning(forOutputUID uid: String?) -> String? {
        guard let uid, let device = devices.first(where: { $0.uid == uid }),
              let volume = volumes[uid], volume.isSilent else { return nil }
        return volume.isMuted == true ? "\(device.name) is muted" : "\(device.name) is at 0%"
    }

    private func change(
        _ uid: String, can allowed: KeyPath<DeviceVolume, Bool>, action: String,
        _ write: (DeviceVolumeControl, AudioOutputDevice, DeviceVolume) throws -> DeviceVolume
    ) {
        guard let device = devices.first(where: { $0.uid == uid }),
              let current = volumes[uid], current[keyPath: allowed] else { return }
        do {
            volumes[uid] = try write(control, device, current)
            errors[uid] = nil
        } catch {
            errors[uid] = "Could not \(action): \(error)"
            Self.log.error("Could not \(action, privacy: .public) \(device.name, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}
