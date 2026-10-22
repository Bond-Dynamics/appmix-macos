import CoreAudio

public struct AudioOutputDevice: Equatable, Sendable {
    public let id: AudioObjectID
    public let uid: String
    public let name: String
    public let outputChannels: Int
    /// Input streams this device brings into an aggregate ahead of the tap's stream.
    public let inputStreamCount: Int
}

public enum AudioDeviceCatalog {
    public static func outputs() throws -> [AudioOutputDevice] {
        let ids = try CoreAudioProperty.array(
            AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices, as: AudioObjectID.self
        )
        return ids.compactMap { try? device($0) }
            .filter { $0.outputChannels > 0 && !$0.uid.hasPrefix(TapRoute.aggregateUIDPrefix) }
    }

    public static func defaultOutput() throws -> AudioOutputDevice {
        let id = try CoreAudioProperty.scalar(
            AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, as: AudioObjectID.self
        )
        return try device(id)
    }

    /// The device named by `query`, or the system default output when `query` is nil.
    public static func resolve(_ query: String?) throws -> AudioOutputDevice {
        guard let query else { return try defaultOutput() }
        return try DeviceQuery.select(query, from: outputs())
    }

    static func device(_ id: AudioObjectID) throws -> AudioOutputDevice {
        AudioOutputDevice(
            id: id,
            uid: try CoreAudioProperty.string(id, kAudioDevicePropertyDeviceUID),
            name: try CoreAudioProperty.string(id, kAudioObjectPropertyName),
            outputChannels: try channelCount(id, scope: kAudioObjectPropertyScopeOutput),
            inputStreamCount: (try? CoreAudioProperty.array(
                id, kAudioDevicePropertyStreams, as: AudioStreamID.self, scope: kAudioObjectPropertyScopeInput
            ).count) ?? 0
        )
    }

    static func sampleRate(_ id: AudioObjectID) throws -> Double {
        try CoreAudioProperty.scalar(id, kAudioDevicePropertyNominalSampleRate, as: Float64.self)
    }

    private static func channelCount(_ id: AudioObjectID, scope: AudioObjectPropertyScope) throws -> Int {
        var raw = try CoreAudioProperty.bytes(id, kAudioDevicePropertyStreamConfiguration, scope: scope)
        return raw.withUnsafeMutableBytes { buffer in
            let list = UnsafeMutableAudioBufferListPointer(buffer.baseAddress!.assumingMemoryBound(to: AudioBufferList.self))
            return list.reduce(0) { $0 + Int($1.mNumberChannels) }
        }
    }
}

public enum DeviceQuery {
    public enum SelectionError: Error, Equatable, CustomStringConvertible {
        case notFound(String)
        case ambiguous(String, [String])

        public var description: String {
            switch self {
            case .notFound(let query): "No output device matches '\(query)'. Run 'appmix list' to see them."
            case .ambiguous(let query, let names): "'\(query)' matches several devices: \(names.joined(separator: ", "))."
            }
        }
    }

    /// Exact UID or name first, then a unique partial name match.
    public static func select(_ query: String, from devices: [AudioOutputDevice]) throws -> AudioOutputDevice {
        if let exact = devices.first(where: { $0.uid == query || $0.name.caseInsensitiveCompare(query) == .orderedSame }) {
            return exact
        }
        let partial = devices.filter { $0.name.localizedCaseInsensitiveContains(query) }
        switch partial.count {
        case 0: throw SelectionError.notFound(query)
        case 1: return partial[0]
        default: throw SelectionError.ambiguous(query, partial.map(\.name))
        }
    }
}
