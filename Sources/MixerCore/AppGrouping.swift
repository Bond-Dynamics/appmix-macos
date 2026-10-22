import CoreAudio

/// One app as the user sees it: its main process plus helpers (Discord, Chrome and Electron apps
/// play audio from helper processes).
public struct AudioApp: Equatable, Sendable {
    public let key: String
    public let processes: [AudioProcess]

    public init(key: String, processes: [AudioProcess]) {
        self.key = key
        self.processes = processes
    }

    public var isPlaying: Bool { processes.contains(where: \.isPlaying) }

    /// The process whose bundle ID is the app's own, for looking up its name and icon.
    public var mainPID: pid_t {
        (processes.first { $0.bundleID == key } ?? processes[0]).pid
    }
}

public enum AppGrouping {
    private static let helperMarker = "helper"
    private static let unbundledPrefix = "process:"

    /// `com.hnc.Discord.helper.Renderer` → `com.hnc.Discord`: cut at the first component starting with "helper".
    public static func key(for process: AudioProcess) -> String {
        guard !process.bundleID.isEmpty else { return unbundledPrefix + process.name }
        let components = process.bundleID.split(separator: ".", omittingEmptySubsequences: false)
        let cut = components.indices.dropFirst().first { components[$0].lowercased().hasPrefix(helperMarker) }
        return cut.map { components[..<$0].joined(separator: ".") } ?? process.bundleID
    }

    /// False for keys of processes without a bundle ID (`process:<name>`).
    public static func isBundleKey(_ key: String) -> Bool { !key.hasPrefix(unbundledPrefix) }

    public static func group(_ processes: [AudioProcess]) -> [AudioApp] {
        Dictionary(grouping: processes, by: key(for:))
            .map { AudioApp(key: $0.key, processes: $0.value.sorted { $0.objectID < $1.objectID }) }
            .sorted { $0.key < $1.key }
    }
}
