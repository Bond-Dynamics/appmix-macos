import AppKit

/// Display name and icon for an app key, looked up once and cached.
@MainActor
enum AppIdentity {
    private struct Identity {
        let name: String
        let icon: NSImage
    }

    private static let unbundledPrefix = "process:"
    private static let iconSize = NSSize(width: 20, height: 20)
    /// Keys whose bundle has no useful name of its own.
    private static let nameOverrides = ["com.apple.WebKit.GPU": "Web audio (Safari, Mail, web views)"]
    private static var cache: [String: Identity] = [:]

    static func name(key: String, pid: pid_t) -> String { identity(key: key, pid: pid).name }
    static func icon(key: String, pid: pid_t) -> NSImage { identity(key: key, pid: pid).icon }

    private static func identity(key: String, pid: pid_t) -> Identity {
        if let cached = cache[key] { return cached }
        let identity = lookUp(key: key, pid: pid)
        cache[key] = identity
        return identity
    }

    /// The installed app bundle names the app best ("Discord", not "Discord Helper (Renderer)");
    /// fall back to the running process, then to the key itself.
    private static func lookUp(key: String, pid: pid_t) -> Identity {
        let running = NSRunningApplication(processIdentifier: pid)
        let bundleURL = key.hasPrefix(unbundledPrefix) ? nil : NSWorkspace.shared.urlForApplication(withBundleIdentifier: key)
        let name = nameOverrides[key]
            ?? bundleURL.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            ?? running?.localizedName
            ?? fallbackName(key)
        let icon = bundleURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? running?.icon
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
            ?? NSImage()
        icon.size = iconSize
        return Identity(name: name, icon: icon)
    }

    private static func fallbackName(_ key: String) -> String {
        key.hasPrefix(unbundledPrefix)
            ? String(key.dropFirst(unbundledPrefix.count))
            : String(key.split(separator: ".").last ?? Substring(key))
    }
}
