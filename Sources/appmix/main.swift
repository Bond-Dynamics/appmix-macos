import Foundation
import MixerCore

setvbuf(stdout, nil, _IOLBF, 0)

do {
    switch try CommandLineOptions.parse(Array(CommandLine.arguments.dropFirst())) {
    case .help:
        print(CommandLineOptions.usage)
    case .list:
        try ListCommand.run()
    case .watch(let duration):
        WatchCommand.run(durationSeconds: duration)
    case .route(let options):
        try RouteCommand.run(options)
    case .tone(let options):
        try ToneCommand.run(options)
    }
} catch let error as UsageError {
    fputs("\(error)\n\n\(CommandLineOptions.usage)\n", stderr)
    exit(64)
} catch {
    fputs("appmix: \(error)\n", stderr)
    exit(1)
}
