import Testing
@testable import MixerCore

struct CommandLineOptionsTests {
    @Test func noArgumentsShowsHelp() throws {
        #expect(try CommandLineOptions.parse([]) == .help)
    }

    @Test func parsesList() throws {
        #expect(try CommandLineOptions.parse(["list"]) == .list)
    }

    @Test func parsesWatch() throws {
        #expect(try CommandLineOptions.parse(["watch"]) == .watch(durationSeconds: nil))
        #expect(try CommandLineOptions.parse(["watch", "--duration", "5"]) == .watch(durationSeconds: 5))
    }

    @Test func parsesRouteWithEveryFlag() throws {
        let command = try CommandLineOptions.parse([
            "route", "--app", "discord", "--to", "A50 Game", "--volume", "40", "--meter", "--duration", "5",
        ])
        #expect(command == .route(RouteOptions(
            app: "discord", device: "A50 Game", volumePercent: 40, showMeter: true, durationSeconds: 5
        )))
    }

    @Test func routeDefaultsToFullVolumeOnDefaultDevice() throws {
        let command = try CommandLineOptions.parse(["route", "--app", "spotify"])
        #expect(command == .route(RouteOptions(
            app: "spotify", device: nil, volumePercent: 100, showMeter: false, durationSeconds: nil
        )))
    }

    @Test func routeRequiresApp() {
        #expect(throws: UsageError.self) { try CommandLineOptions.parse(["route", "--to", "TV"]) }
    }

    @Test func rejectsVolumeOutsideRange() {
        #expect(throws: UsageError.self) { try CommandLineOptions.parse(["route", "--app", "x", "--volume", "150"]) }
        #expect(throws: UsageError.self) { try CommandLineOptions.parse(["route", "--app", "x", "--volume", "loud"]) }
    }

    @Test func rejectsFlagWithoutValue() {
        #expect(throws: UsageError.self) { try CommandLineOptions.parse(["route", "--app"]) }
    }

    @Test func rejectsUnknownCommandAndFlag() {
        #expect(throws: UsageError.self) { try CommandLineOptions.parse(["mix"]) }
        #expect(throws: UsageError.self) { try CommandLineOptions.parse(["route", "--app", "x", "--bogus"]) }
    }

    @Test func parsesToneWithDefaults() throws {
        #expect(try CommandLineOptions.parse(["tone"]) == .tone(ToneOptions(
            device: nil, levelDecibels: -24, frequencyHertz: 440, delaySeconds: 0, durationSeconds: 10
        )))
    }

    @Test func rejectsPositiveToneLevel() {
        #expect(throws: UsageError.self) { try CommandLineOptions.parse(["tone", "--level", "3"]) }
    }
}
