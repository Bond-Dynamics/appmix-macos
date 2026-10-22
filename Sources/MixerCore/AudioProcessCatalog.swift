import CoreAudio
import Darwin

public struct AudioProcess: Equatable, Sendable {
    public let objectID: AudioObjectID
    public let pid: pid_t
    public let bundleID: String
    public let name: String
    public let isPlaying: Bool
    public let isRecording: Bool

    public var label: String { bundleID.isEmpty ? name : bundleID }
}

public enum AudioProcessCatalog {
    /// Every process Core Audio currently tracks, playing ones first.
    public static func all() throws -> [AudioProcess] {
        let objects = try CoreAudioProperty.array(
            AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList, as: AudioObjectID.self
        )
        return objects
            .compactMap { try? process(for: $0) }
            .sorted { ($0.isPlaying ? 0 : 1, $0.label) < ($1.isPlaying ? 0 : 1, $1.label) }
    }

    private static func process(for object: AudioObjectID) throws -> AudioProcess {
        let pid = try CoreAudioProperty.scalar(object, kAudioProcessPropertyPID, as: pid_t.self)
        return AudioProcess(
            objectID: object,
            pid: pid,
            bundleID: (try? CoreAudioProperty.string(object, kAudioProcessPropertyBundleID)) ?? "",
            name: executableName(pid),
            isPlaying: (try? CoreAudioProperty.scalar(object, kAudioProcessPropertyIsRunningOutput, as: UInt32.self)) ?? 0 != 0,
            isRecording: (try? CoreAudioProperty.scalar(object, kAudioProcessPropertyIsRunningInput, as: UInt32.self)) ?? 0 != 0
        )
    }

    private static func executableName(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXCOMLEN) * 2 + 1)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "pid \(pid)" }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

/// What the user typed after `--app`: a pid, or text matched against bundle ID and process name.
public enum ProcessQuery: Equatable, Sendable {
    case pid(pid_t)
    case text(String)

    public static func parse(_ query: String) -> ProcessQuery {
        Int32(query).map(ProcessQuery.pid) ?? .text(query)
    }

    /// Every matching process. Text matches all of an app's helpers (Discord, Chrome) so they are tapped together.
    public func select(from processes: [AudioProcess]) -> [AudioProcess] {
        switch self {
        case .pid(let pid):
            return processes.filter { $0.pid == pid }
        case .text(let text):
            return processes.filter {
                $0.bundleID.localizedCaseInsensitiveContains(text) || $0.name.localizedCaseInsensitiveContains(text)
            }
        }
    }
}
