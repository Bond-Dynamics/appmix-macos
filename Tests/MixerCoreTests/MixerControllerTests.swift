import Testing
import CoreAudio
@testable import MixerCore

@MainActor
private final class FakeRouteFactory: RouteFactory {
    final class Handle: RouteHandle {
        let deviceUID: String
        let objectIDs: [AudioObjectID]
        let controls: LiveControls
        private(set) var stopped = false
        init(deviceUID: String, objectIDs: [AudioObjectID], controls: LiveControls) {
            self.deviceUID = deviceUID
            self.objectIDs = objectIDs
            self.controls = controls
        }
        func stop() { stopped = true }
    }

    private(set) var made: [Handle] = []
    var failure: Error?

    func makeRoute(processes: [AudioProcess], output: AudioOutputDevice, controls: LiveControls) throws -> RouteHandle {
        if let failure { throw failure }
        let handle = Handle(deviceUID: output.uid, objectIDs: processes.map(\.objectID).sorted(), controls: controls)
        made.append(handle)
        return handle
    }
}

private struct BoomError: Error, CustomStringConvertible { var description: String { "boom" } }

private let game = AudioOutputDevice(id: 1, uid: "a50-game", name: "A50 Game", outputChannels: 2, inputStreamCount: 0)
private let voice = AudioOutputDevice(id: 2, uid: "a50-voice", name: "A50 Voice", outputChannels: 2, inputStreamCount: 0)
private let spotifyKey = "com.spotify.client"

private func spotify(_ ids: [AudioObjectID] = [12], playing: Bool = true) -> [AudioProcess] {
    ids.map { AudioProcess(objectID: $0, pid: pid_t($0), bundleID: spotifyKey, name: "Spotify", isPlaying: playing, isRecording: false) }
}

private func snapshot(_ processes: [AudioProcess], devices: [AudioOutputDevice] = [game, voice], defaultUID: String = "a50-game") -> AudioSnapshot {
    AudioSnapshot(processes: processes, devices: devices, defaultOutputUID: defaultUID)
}

@MainActor
struct MixerControllerTests {
    private let factory = FakeRouteFactory()
    private var controller: MixerController { MixerController(factory: factory, ownPID: 1) }

    @Test func listsPlayingAppsWithoutTappingThem() {
        let mixer = controller
        mixer.update(snapshot(spotify()))
        #expect(mixer.apps.map(\.key) == [spotifyKey])
        #expect(factory.made.isEmpty)
    }

    @Test func hidesItselfAndSilentUntouchedApps() {
        let mixer = controller
        let own = AudioProcess(objectID: 5, pid: 1, bundleID: "local.appmix", name: "AppMix", isPlaying: true, isRecording: false)
        mixer.update(snapshot(spotify(playing: false) + [own]))
        #expect(mixer.apps.isEmpty)
    }

    @Test func firstVolumeChangeTapsThenLaterChangesReuseTheRoute() {
        let mixer = controller
        mixer.update(snapshot(spotify()))
        mixer.setVolume(40, for: spotifyKey)
        mixer.setVolume(20, for: spotifyKey)
        #expect(factory.made.count == 1)
        #expect(factory.made[0].deviceUID == "a50-game")
        #expect(factory.made[0].controls.volumePercent == 20)
        #expect(mixer.isRouted(spotifyKey))
    }

    @Test func muteGoesThroughLiveControls() {
        let mixer = controller
        mixer.update(snapshot(spotify()))
        mixer.setMuted(true, for: spotifyKey)
        #expect(factory.made.count == 1)
        #expect(factory.made[0].controls.isMuted)
    }

    @Test func changingOutputRebuildsTheRoute() {
        let mixer = controller
        mixer.update(snapshot(spotify()))
        mixer.setVolume(50, for: spotifyKey)
        mixer.setOutput("a50-voice", for: spotifyKey)
        #expect(factory.made.count == 2)
        #expect(factory.made[0].stopped)
        #expect(factory.made[1].deviceUID == "a50-voice")
        #expect(factory.made[1].controls.volumePercent == 50)
    }

    @Test func resetRemovesTheTap() {
        let mixer = controller
        mixer.update(snapshot(spotify()))
        mixer.setOutput("a50-voice", for: spotifyKey)
        mixer.reset(spotifyKey)
        #expect(factory.made[0].stopped)
        #expect(!mixer.isRouted(spotifyKey))
        #expect(mixer.settings(for: spotifyKey) == .passthrough)
    }

    @Test func newHelperProcessRebuildsWithEveryProcess() {
        let mixer = controller
        mixer.update(snapshot(spotify([12])))
        mixer.setVolume(30, for: spotifyKey)
        mixer.update(snapshot(spotify([12, 13])))
        #expect(factory.made.count == 2)
        #expect(factory.made[1].objectIDs == [12, 13])
    }

    @Test func unrelatedRefreshKeepsTheRoute() {
        let mixer = controller
        mixer.update(snapshot(spotify()))
        mixer.setVolume(30, for: spotifyKey)
        mixer.update(snapshot(spotify()))
        #expect(factory.made.count == 1)
        #expect(!factory.made[0].stopped)
    }

    @Test func quitAppStopsRouteButKeepsSettingsForRelaunch() {
        let mixer = controller
        mixer.update(snapshot(spotify([12])))
        mixer.setOutput("a50-voice", for: spotifyKey)
        mixer.update(snapshot([]))
        #expect(factory.made[0].stopped)
        mixer.update(snapshot(spotify([40])))
        #expect(factory.made.count == 2)
        #expect(factory.made[1].deviceUID == "a50-voice")
    }

    @Test func pausedTouchedAppStaysVisible() {
        let mixer = controller
        mixer.update(snapshot(spotify()))
        mixer.setVolume(30, for: spotifyKey)
        mixer.update(snapshot(spotify(playing: false)))
        #expect(mixer.apps.map(\.key) == [spotifyKey])
    }

    @Test func unpluggedOutputFallsBackToDefault() {
        let mixer = controller
        mixer.update(snapshot(spotify()))
        mixer.setOutput("a50-voice", for: spotifyKey)
        mixer.update(snapshot(spotify(), devices: [game]))
        #expect(factory.made.last?.deviceUID == "a50-game")
        #expect(mixer.settings(for: spotifyKey).outputUID == "a50-voice")
    }

    @Test func routeFailureIsReportedNotSwallowed() {
        let mixer = controller
        factory.failure = BoomError()
        mixer.update(snapshot(spotify()))
        mixer.setVolume(30, for: spotifyKey)
        #expect(!mixer.isRouted(spotifyKey))
        #expect(mixer.error(for: spotifyKey) == "boom")
    }
}

@MainActor
struct IdleAppVisibilityTests {
    private let daemon = AudioProcess(objectID: 30, pid: 30, bundleID: "com.apple.systemsoundserverd", name: "systemsoundserverd", isPlaying: false, isRecording: false)

    private func mixer(showIdle: Bool) -> MixerController {
        let mixer = MixerController(factory: FakeRouteFactory(), ownPID: 1, isUserFacing: { $0.key == spotifyKey })
        mixer.showIdleApps = showIdle
        mixer.update(snapshot(spotify(playing: false) + [daemon]))
        return mixer
    }

    @Test func idleRegularAppIsShown() {
        #expect(mixer(showIdle: true).apps.map(\.key) == [spotifyKey])
    }

    @Test func idleBackgroundProcessStaysHidden() {
        #expect(!mixer(showIdle: true).apps.contains { $0.key == "com.apple.systemsoundserverd" })
    }

    @Test func toggleOffRestoresPlayingOnly() {
        #expect(mixer(showIdle: false).apps.isEmpty)
    }

    @Test func idleAppCanBeSetUpBeforeItPlays() {
        let factory = FakeRouteFactory()
        let mixer = MixerController(factory: factory, ownPID: 1, isUserFacing: { _ in true })
        mixer.update(snapshot(spotify(playing: false)))
        mixer.setVolume(30, for: spotifyKey)
        #expect(factory.made.count == 1)
        #expect(factory.made[0].controls.volumePercent == 30)
    }
}
