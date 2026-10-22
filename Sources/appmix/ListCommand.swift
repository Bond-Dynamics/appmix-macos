import MixerCore

enum ListCommand {
    static func run() throws {
        let processes = try AudioProcessCatalog.all()
        let defaultUID = try AudioDeviceCatalog.defaultOutput().uid

        print("Apps (\(processes.filter(\.isPlaying).count) playing):")
        processes.forEach { process in
            let state = [process.isPlaying ? "playing" : nil, process.isRecording ? "recording" : nil]
                .compactMap { $0 }.joined(separator: ", ")
            let pid = "pid \(process.pid)".padding(toLength: 11, withPad: " ", startingAt: 0)
            print("  \(pid) \(process.label)\(state.isEmpty ? "" : "  [\(state)]")")
        }

        print("\nOutput devices:")
        try AudioDeviceCatalog.outputs().forEach { device in
            let marker = device.uid == defaultUID ? "  (default)" : ""
            print("  \(device.name)  [\(device.outputChannels) ch]\(marker)")
        }
    }
}
