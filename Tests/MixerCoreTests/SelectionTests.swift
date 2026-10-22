import Testing
@testable import MixerCore

struct ProcessQueryTests {
    private let processes = [
        AudioProcess(objectID: 10, pid: 3318, bundleID: "com.hnc.Discord.helper.Renderer", name: "Discord Helper", isPlaying: true, isRecording: true),
        AudioProcess(objectID: 11, pid: 3300, bundleID: "com.hnc.Discord", name: "Discord", isPlaying: false, isRecording: false),
        AudioProcess(objectID: 12, pid: 900, bundleID: "com.spotify.client", name: "Spotify", isPlaying: true, isRecording: false),
        AudioProcess(objectID: 13, pid: 4242, bundleID: "", name: "afplay", isPlaying: true, isRecording: false),
    ]

    @Test func numericQueryMatchesExactPid() {
        #expect(ProcessQuery.parse("900").select(from: processes).map(\.objectID) == [12])
    }

    @Test func textQueryMatchesEveryProcessOfAnAppCaseInsensitively() {
        #expect(ProcessQuery.parse("discord").select(from: processes).map(\.objectID) == [10, 11])
    }

    @Test func textQueryFallsBackToProcessNameWhenBundleIsEmpty() {
        #expect(ProcessQuery.parse("AFPLAY").select(from: processes).map(\.objectID) == [13])
    }

    @Test func unknownQueryMatchesNothing() {
        #expect(ProcessQuery.parse("zoom").select(from: processes).isEmpty)
    }
}

struct DeviceQueryTests {
    private let devices = [
        AudioOutputDevice(id: 1, uid: "a50-game", name: "A50 Game", outputChannels: 2, inputStreamCount: 0),
        AudioOutputDevice(id: 2, uid: "a50-voice", name: "A50 Voice", outputChannels: 2, inputStreamCount: 0),
        AudioOutputDevice(id: 3, uid: "BuiltInSpeakerDevice", name: "MacBook Pro Speakers", outputChannels: 2, inputStreamCount: 0),
    ]

    @Test func exactNameWins() throws {
        #expect(try DeviceQuery.select("a50 game", from: devices).id == 1)
    }

    @Test func uniquePartialNameMatches() throws {
        #expect(try DeviceQuery.select("speakers", from: devices).id == 3)
    }

    @Test func uidMatches() throws {
        #expect(try DeviceQuery.select("a50-voice", from: devices).id == 2)
    }

    @Test func ambiguousPartialNameThrows() {
        #expect(throws: DeviceQuery.SelectionError.ambiguous("a50", ["A50 Game", "A50 Voice"])) {
            try DeviceQuery.select("a50", from: devices)
        }
    }

    @Test func missingDeviceThrows() {
        #expect(throws: DeviceQuery.SelectionError.notFound("TV")) { try DeviceQuery.select("TV", from: devices) }
    }
}
