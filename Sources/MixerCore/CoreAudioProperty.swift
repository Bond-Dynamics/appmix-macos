import CoreAudio

public struct CoreAudioError: Error, CustomStringConvertible {
    public let operation: String
    public let status: OSStatus

    public var description: String {
        let bytes = withUnsafeBytes(of: UInt32(bitPattern: status).bigEndian, Array.init)
        let code = bytes.allSatisfy { (0x20...0x7E).contains($0) } ? " '\(String(decoding: bytes, as: UTF8.self))'" : ""
        return "\(operation) failed (OSStatus \(status)\(code))"
    }
}

func check(_ status: OSStatus, _ operation: @autoclosure () -> String) throws {
    guard status == noErr else { throw CoreAudioError(operation: operation(), status: status) }
}

/// Typed reads of Core Audio object properties.
enum CoreAudioProperty {
    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func bytes(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) throws -> [UInt8] {
        var addr = address(selector, scope: scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size), "size of '\(selector)' on \(object)")
        var data = [UInt8](repeating: 0, count: Int(size))
        try check(
            data.withUnsafeMutableBytes { AudioObjectGetPropertyData(object, &addr, 0, nil, &size, $0.baseAddress!) },
            "read '\(selector)' on \(object)"
        )
        return Array(data.prefix(Int(size)))
    }

    static func array<T>(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector, as: T.Type,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) throws -> [T] {
        let raw = try bytes(object, selector, scope: scope)
        return raw.withUnsafeBytes { buffer in
            (0..<raw.count / MemoryLayout<T>.stride).map {
                buffer.loadUnaligned(fromByteOffset: $0 * MemoryLayout<T>.stride, as: T.self)
            }
        }
    }

    static func scalar<T>(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector, as type: T.Type,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) throws -> T {
        guard let value = try array(object, selector, as: type, scope: scope).first else {
            throw CoreAudioError(operation: "read '\(selector)' on \(object): empty", status: kAudioHardwareBadPropertySizeError)
        }
        return value
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var addr = address(selector)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        try check(AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value), "read string '\(selector)' on \(object)")
        return (value?.takeRetainedValue() as String?) ?? ""
    }
}
