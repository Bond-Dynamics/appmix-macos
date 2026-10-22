import Testing
import CoreAudio
@testable import MixerCore

private func process(_ id: AudioObjectID, _ bundle: String, name: String = "x", pid: pid_t? = nil, playing: Bool = false) -> AudioProcess {
    AudioProcess(objectID: id, pid: pid ?? pid_t(id), bundleID: bundle, name: name, isPlaying: playing, isRecording: false)
}

struct AppGroupingTests {
    @Test func helperProcessesJoinTheirApp() {
        #expect(AppGrouping.key(for: process(1, "com.hnc.Discord.helper.Renderer")) == "com.hnc.Discord")
        #expect(AppGrouping.key(for: process(2, "com.google.Chrome.helper")) == "com.google.Chrome")
        #expect(AppGrouping.key(for: process(3, "com.spotify.client")) == "com.spotify.client")
    }

    @Test func helperPrefixIsCaseInsensitiveAndNeverTheWholeId() {
        #expect(AppGrouping.key(for: process(1, "com.example.App.Helper (GPU)")) == "com.example.App")
        #expect(AppGrouping.key(for: process(2, "helper.tool")) == "helper.tool")
    }

    @Test func processWithoutBundleIdIsKeyedByName() {
        #expect(AppGrouping.key(for: process(1, "", name: "afplay")) == "process:afplay")
    }

    @Test func groupsAppsAndMarksPlayingIfAnyProcessPlays() {
        let apps = AppGrouping.group([
            process(10, "com.hnc.Discord", pid: 3241),
            process(11, "com.hnc.Discord.helper.Renderer", pid: 3318, playing: true),
            process(12, "com.spotify.client"),
        ])
        #expect(apps.map(\.key) == ["com.hnc.Discord", "com.spotify.client"])
        #expect(apps[0].processes.map(\.objectID) == [10, 11])
        #expect(apps[0].isPlaying)
        #expect(apps[0].mainPID == 3241)
        #expect(!apps[1].isPlaying)
    }

    @Test func mainPidFallsBackToFirstProcess() {
        let apps = AppGrouping.group([process(20, "com.example.App.helper", pid: 77)])
        #expect(apps[0].mainPID == 77)
    }
}

struct RoutePlannerTests {
    private let app = AudioApp(key: "com.spotify.client", processes: [process(12, "com.spotify.client"), process(9, "com.spotify.client.helper")])
    private let devices: Set<String> = ["a50-game", "a50-voice"]

    @Test func untouchedAppIsNotTapped() {
        #expect(RoutePlanner.target(for: app, settings: .passthrough, defaultOutputUID: "a50-game", availableUIDs: devices) == nil)
    }

    @Test func volumeChangeRoutesToDefaultOutput() {
        let settings = AppSettings(volumePercent: 40, isMuted: false, outputUID: nil)
        #expect(RoutePlanner.target(for: app, settings: settings, defaultOutputUID: "a50-game", availableUIDs: devices)
            == RouteTarget(deviceUID: "a50-game", processObjectIDs: [9, 12]))
    }

    @Test func chosenOutputWins() {
        let settings = AppSettings(volumePercent: 100, isMuted: false, outputUID: "a50-voice")
        #expect(RoutePlanner.target(for: app, settings: settings, defaultOutputUID: "a50-game", availableUIDs: devices)?.deviceUID == "a50-voice")
    }

    @Test func missingChosenOutputFallsBackToDefault() {
        let settings = AppSettings(volumePercent: 100, isMuted: false, outputUID: "lg-tv")
        #expect(RoutePlanner.target(for: app, settings: settings, defaultOutputUID: "a50-game", availableUIDs: devices)?.deviceUID == "a50-game")
    }
}
