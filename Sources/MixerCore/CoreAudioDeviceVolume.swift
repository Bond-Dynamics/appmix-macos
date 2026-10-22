import AudioToolbox
import CoreAudio
import os

/// The real control. Volume prefers the "virtual main volume" that the menu bar and volume keys use,
/// which also covers devices that only have per-channel volume, then the device's own main volume.
public struct CoreAudioDeviceVolume: DeviceVolumeControl {
    static let volumeSelectors = [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyVolumeScalar]
    static let muteSelector = kAudioDevicePropertyMute
    private static let scope = kAudioObjectPropertyScopeOutput
    private static let log = Logger(subsystem: "local.appmix", category: "devices")

    public init() {}

    /// A control that exists but can't be read right now (a waking or reconfiguring device) is shown
    /// as unknown and not settable, rather than as a made-up value.
    public func volume(of device: AudioOutputDevice) -> DeviceVolume {
        let volume = Self.volumeSelector(on: device.id).flatMap { selector in
            Self.read(device, selector, as: Float32.self).map { (Double($0) * 100, selector) }
        }
        let hasMute = CoreAudioProperty.has(device.id, Self.muteSelector, scope: Self.scope)
        let isMuted = hasMute ? Self.read(device, Self.muteSelector, as: UInt32.self).map { $0 != 0 } : nil
        return DeviceVolume(
            percent: volume?.0,
            isMuted: isMuted,
            canSetVolume: volume.map { CoreAudioProperty.isSettable(device.id, $0.1, scope: Self.scope) } ?? false,
            canSetMute: isMuted != nil && CoreAudioProperty.isSettable(device.id, Self.muteSelector, scope: Self.scope)
        )
    }

    public func setVolume(_ percent: Double, of device: AudioOutputDevice) throws {
        guard let selector = Self.volumeSelector(on: device.id) else {
            throw CoreAudioError(operation: "set volume on \(device.name): no volume control", status: kAudioHardwareUnknownPropertyError)
        }
        try CoreAudioProperty.set(device.id, selector, Float32(min(max(percent, 0), 100) / 100), scope: Self.scope)
    }

    public func setMuted(_ muted: Bool, of device: AudioOutputDevice) throws {
        try CoreAudioProperty.set(device.id, Self.muteSelector, UInt32(muted ? 1 : 0), scope: Self.scope)
    }

    /// Every device's volume, keyed by UID, for a snapshot.
    static func volumes(of devices: [AudioOutputDevice]) -> [String: DeviceVolume] {
        let control = CoreAudioDeviceVolume()
        return Dictionary(devices.map { ($0.uid, control.volume(of: $0)) }, uniquingKeysWith: { first, _ in first })
    }

    private static func read<T>(_ device: AudioOutputDevice, _ selector: AudioObjectPropertySelector, as type: T.Type) -> T? {
        do {
            return try CoreAudioProperty.scalar(device.id, selector, as: type, scope: scope)
        } catch {
            log.error("Could not read \(device.name, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private static func volumeSelector(on device: AudioObjectID) -> AudioObjectPropertySelector? {
        volumeSelectors.first { CoreAudioProperty.has(device, $0, scope: scope) }
    }
}
