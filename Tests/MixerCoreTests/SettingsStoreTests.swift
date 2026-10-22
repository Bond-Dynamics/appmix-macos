import CoreAudio
import Foundation
import Testing
@testable import MixerCore

@MainActor
struct UserDefaultsSettingsStoreTests {
    private func withScratchDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "appmix.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        body(defaults)
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func roundTripsSettings() {
        withScratchDefaults { defaults in
            let saved = [
                "com.spotify.client": AppSettings(volumePercent: 40, isMuted: false, outputUID: "a50-voice"),
                "com.hnc.Discord": AppSettings(volumePercent: 100, isMuted: true, outputUID: nil),
            ]
            UserDefaultsSettingsStore(defaults: defaults).save(saved)
            #expect(UserDefaultsSettingsStore(defaults: defaults).load() == saved)
        }
    }

    @Test func emptyWhenNothingSaved() {
        withScratchDefaults { defaults in
            #expect(UserDefaultsSettingsStore(defaults: defaults).load().isEmpty)
        }
    }

    @Test func corruptDataLoadsAsEmptyInsteadOfCrashing() {
        withScratchDefaults { defaults in
            defaults.set(Data("not json".utf8), forKey: UserDefaultsSettingsStore.key)
            #expect(UserDefaultsSettingsStore(defaults: defaults).load().isEmpty)
        }
    }
}

@MainActor
private final class MemoryStore: SettingsStore {
    var stored: [String: AppSettings]
    private(set) var saveCount = 0
    init(_ stored: [String: AppSettings] = [:]) { self.stored = stored }
    func load() -> [String: AppSettings] { stored }
    func save(_ settings: [String: AppSettings]) {
        stored = settings
        saveCount += 1
    }
}

@MainActor
private final class CountingFactory: RouteFactory {
    final class Handle: RouteHandle { func stop() {} }
    private(set) var devices: [String] = []
    func makeRoute(processes: [AudioProcess], output: AudioOutputDevice, controls: LiveControls) throws -> RouteHandle {
        devices.append(output.uid)
        return Handle()
    }
}

@MainActor
struct PersistedMixerTests {
    private let key = "com.spotify.client"
    private let voice = AudioOutputDevice(id: 2, uid: "a50-voice", name: "A50 Voice", outputChannels: 2, inputStreamCount: 0)

    private func snapshot(playing: Bool) -> AudioSnapshot {
        AudioSnapshot(
            processes: [AudioProcess(objectID: 12, pid: 12, bundleID: key, name: "Spotify", isPlaying: playing, isRecording: false)],
            devices: [voice], defaultOutputUID: "a50-voice"
        )
    }

    @Test func restoredAppIsRoutedAndShownEvenBeforeItPlays() {
        let factory = CountingFactory()
        let store = MemoryStore([key: AppSettings(volumePercent: 30, isMuted: false, outputUID: "a50-voice")])
        let mixer = MixerController(factory: factory, store: store, ownPID: 1)
        mixer.update(snapshot(playing: false))
        #expect(factory.devices == ["a50-voice"])
        #expect(mixer.settings(for: key).volumePercent == 30)
        #expect(mixer.apps.map(\.key) == [key])
    }

    @Test func everyChangeIsSaved() {
        let store = MemoryStore()
        let mixer = MixerController(factory: CountingFactory(), store: store, ownPID: 1)
        mixer.update(snapshot(playing: true))
        mixer.setVolume(55, for: key)
        mixer.setMuted(true, for: key)
        #expect(store.saveCount == 2)
        #expect(store.stored[key] == AppSettings(volumePercent: 55, isMuted: true, outputUID: nil))
    }

    @Test func resetForgetsTheApp() {
        let store = MemoryStore([key: AppSettings(volumePercent: 30, isMuted: false, outputUID: nil)])
        let mixer = MixerController(factory: CountingFactory(), store: store, ownPID: 1)
        mixer.reset(key)
        #expect(store.stored.isEmpty)
    }

    @Test func movingBackToDefaultsAlsoForgets() {
        let store = MemoryStore()
        let mixer = MixerController(factory: CountingFactory(), store: store, ownPID: 1)
        mixer.update(snapshot(playing: true))
        mixer.setVolume(50, for: key)
        mixer.setVolume(100, for: key)
        #expect(store.stored.isEmpty)
    }
}
