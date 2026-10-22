import Testing
import CoreAudio
@testable import MixerCore

private final class FakeDeviceVolumeControl: DeviceVolumeControl, @unchecked Sendable {
    enum Write: Equatable {
        case volume(AudioObjectID, Double)
        case mute(AudioObjectID, Bool)
    }

    private(set) var writes: [Write] = []
    var failure: Error?

    func volume(of device: AudioOutputDevice) -> DeviceVolume { .fixed }

    func setVolume(_ percent: Double, of device: AudioOutputDevice) throws {
        if let failure { throw failure }
        writes.append(.volume(device.id, percent))
    }

    func setMuted(_ muted: Bool, of device: AudioOutputDevice) throws {
        if let failure { throw failure }
        writes.append(.mute(device.id, muted))
    }
}

private struct DeniedError: Error, CustomStringConvertible { var description: String { "denied" } }

private let speakers = AudioOutputDevice(id: 1, uid: "speakers", name: "MacBook Pro Speakers", outputChannels: 2, inputStreamCount: 0)
private let voice = AudioOutputDevice(id: 2, uid: "a50-voice", name: "A50 Voice", outputChannels: 2, inputStreamCount: 0)
private let tv = AudioOutputDevice(id: 3, uid: "lg-tv", name: "LG TV", outputChannels: 2, inputStreamCount: 0)

private func adjustable(_ percent: Double, muted: Bool = false) -> DeviceVolume {
    DeviceVolume(percent: percent, isMuted: muted, canSetVolume: true, canSetMute: true)
}

private func snapshot(_ volumes: [String: DeviceVolume], defaultUID: String = "speakers") -> AudioSnapshot {
    AudioSnapshot(processes: [], devices: [tv, voice, speakers], defaultOutputUID: defaultUID, deviceVolumes: volumes)
}

@MainActor
struct DeviceMixerTests {
    private let control = FakeDeviceVolumeControl()

    private func mixer(_ volumes: [String: DeviceVolume] = [:], defaultUID: String = "speakers") -> DeviceMixer {
        let mixer = DeviceMixer(control: control)
        mixer.update(snapshot(volumes, defaultUID: defaultUID))
        return mixer
    }

    @Test func listsTheDefaultOutputFirstThenByName() {
        let rows = mixer([:]).rows
        #expect(rows.map(\.uid) == ["speakers", "a50-voice", "lg-tv"])
        #expect(rows.map(\.isDefault) == [true, false, false])
    }

    @Test func aDeviceWithoutAReadingIsFixed() {
        let rows = mixer(["speakers": adjustable(44)]).rows
        #expect(rows[0].volume == adjustable(44))
        #expect(rows[1].volume == .fixed)
        #expect(!DeviceVolume.fixed.canSetVolume && !DeviceVolume.fixed.canSetMute)
    }

    @Test func volumeWritesAreClampedAndShownStraightAway() {
        let mixer = mixer(["speakers": adjustable(44)])
        mixer.setVolume(130, for: "speakers")
        mixer.setVolume(-5, for: "speakers")
        #expect(control.writes == [.volume(1, 100), .volume(1, 0)])
        #expect(mixer.rows[0].volume.percent == 0)
    }

    @Test func muteWritesReachTheDevice() {
        let mixer = mixer(["speakers": adjustable(44)])
        mixer.setMuted(true, for: "speakers")
        #expect(control.writes == [.mute(1, true)])
        #expect(mixer.rows[0].volume.isMuted == true)
    }

    @Test func writesToAFixedDeviceAreRefused() {
        let readOnly = DeviceVolume(percent: 80, isMuted: false, canSetVolume: false, canSetMute: false)
        let mixer = mixer(["lg-tv": readOnly])
        mixer.setVolume(20, for: "lg-tv")
        mixer.setMuted(true, for: "lg-tv")
        mixer.setVolume(20, for: "a50-voice")
        mixer.setVolume(20, for: "unplugged")
        #expect(control.writes.isEmpty)
        #expect(mixer.rows.first { $0.uid == "lg-tv" }?.volume == readOnly)
    }

    @Test func aFailedWriteKeepsTheDeviceValueAndShowsAnError() {
        let mixer = mixer(["speakers": adjustable(44)])
        control.failure = DeniedError()
        mixer.setVolume(10, for: "speakers")
        #expect(mixer.rows[0].volume.percent == 44)
        #expect(mixer.rows[0].error == "Could not change the volume: denied")
        control.failure = nil
        mixer.setVolume(10, for: "speakers")
        #expect(mixer.rows[0].error == nil)
    }

    @Test func aNewSnapshotReplacesTheShownValue() {
        let mixer = mixer(["speakers": adjustable(44)])
        mixer.setVolume(10, for: "speakers")
        mixer.update(snapshot(["speakers": adjustable(60)]))
        #expect(mixer.rows[0].volume.percent == 60)
    }

    @Test func whileDraggingTheUsersValueWinsOverSnapshots() {
        let mixer = mixer(["speakers": adjustable(44)])
        mixer.beginEditing("speakers")
        mixer.setVolume(70, for: "speakers")
        mixer.update(snapshot(["speakers": adjustable(52, muted: true)]))
        #expect(mixer.rows[0].volume == adjustable(70, muted: true))
        mixer.endEditing("speakers")
        mixer.update(snapshot(["speakers": adjustable(69)]))
        #expect(mixer.rows[0].volume.percent == 69)
    }

    @Test func errorsAreDroppedWhenTheDeviceGoes() {
        let mixer = mixer(["speakers": adjustable(44)])
        control.failure = DeniedError()
        mixer.setMuted(true, for: "speakers")
        #expect(mixer.rows[0].error != nil)
        mixer.update(AudioSnapshot(processes: [], devices: [voice], defaultOutputUID: "a50-voice"))
        mixer.update(snapshot(["speakers": adjustable(44)]))
        #expect(mixer.rows[0].error == nil)
    }

    @Test func warnsWhenTheChosenOutputIsMutedOrAtZero() {
        let mixer = mixer([
            "a50-voice": adjustable(70, muted: true),
            "lg-tv": adjustable(0.3),
            "speakers": adjustable(44),
        ])
        #expect(mixer.warning(forOutputUID: "a50-voice") == "A50 Voice is muted")
        #expect(mixer.warning(forOutputUID: "lg-tv") == "LG TV is at 0%")
        #expect(mixer.warning(forOutputUID: "speakers") == nil)
    }

    @Test func noWarningWhenFollowingTheDefaultOrTheDeviceIsUnknown() {
        let mixer = mixer(["speakers": adjustable(0, muted: true)])
        #expect(mixer.warning(forOutputUID: nil) == nil)
        #expect(mixer.warning(forOutputUID: "a50-voice") == nil)
        #expect(mixer.warning(forOutputUID: "unplugged") == nil)
    }

    @Test func aSnapshotKnowsWhenOnlyVolumesChanged() {
        let before = snapshot(["speakers": adjustable(44)])
        #expect(snapshot(["speakers": adjustable(60, muted: true)]).differsOnlyInVolumes(from: before))
        #expect(!snapshot(["speakers": adjustable(44)], defaultUID: "a50-voice").differsOnlyInVolumes(from: before))
    }

    @Test func silentNeedsAKnownMuteOrZeroVolume() {
        #expect(adjustable(0).isSilent)
        #expect(adjustable(50, muted: true).isSilent)
        #expect(!adjustable(1).isSilent)
        #expect(!DeviceVolume.fixed.isSilent)
    }
}
