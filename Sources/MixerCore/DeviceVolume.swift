import CoreAudio

/// An output device's own volume and mute, as macOS stores them per device. `nil` means the device
/// has no such control (many HDMI, TV and USB headset outputs have a fixed volume).
public struct DeviceVolume: Equatable, Sendable {
    public static let fixed = DeviceVolume(percent: nil, isMuted: nil, canSetVolume: false, canSetMute: false)

    public let percent: Double?
    public let isMuted: Bool?
    public let canSetVolume: Bool
    public let canSetMute: Bool

    public init(percent: Double?, isMuted: Bool?, canSetVolume: Bool, canSetMute: Bool) {
        self.percent = percent
        self.isMuted = isMuted
        self.canSetVolume = canSetVolume
        self.canSetMute = canSetMute
    }

    /// Nothing comes out: muted, or a volume that shows as 0%.
    public var isSilent: Bool { isMuted == true || percent.map { $0.rounded() == 0 } == true }

    func with(percent: Double) -> DeviceVolume {
        DeviceVolume(percent: percent, isMuted: isMuted, canSetVolume: canSetVolume, canSetMute: canSetMute)
    }

    func with(isMuted: Bool) -> DeviceVolume {
        DeviceVolume(percent: percent, isMuted: isMuted, canSetVolume: canSetVolume, canSetMute: canSetMute)
    }
}

/// Reads and changes device volume. Swapped for a fake in tests so they never touch real devices.
public protocol DeviceVolumeControl: Sendable {
    func volume(of device: AudioOutputDevice) -> DeviceVolume
    func setVolume(_ percent: Double, of device: AudioOutputDevice) throws
    func setMuted(_ muted: Bool, of device: AudioOutputDevice) throws
}
