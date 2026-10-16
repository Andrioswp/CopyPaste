import AppKit
import ApplicationServices
import ServiceManagement

// MARK: - Preferences

enum PrefKey {
    static let keyCode = "hotkey.keyCode"
    static let modifiers = "hotkey.modifiers"
    static let fn = "hotkey.fn"
    static let fnOnly = "hotkey.fnOnly"
    static let autoPaste = "autoPaste"
    static let maxItems = "maxItems"
    static let glassStyle = "glassStyle"
    static let appearance = "appearance"
}

struct HotkeySpec {
    var keyCode: Int
    var modifiers: Int
    var fn: Bool
    var fnOnly: Bool

    static let standard = HotkeySpec(keyCode: 9, modifiers: 768, fn: false, fnOnly: false)

    var dict: [String: Any] {
        return [
            "keyCode": keyCode,
            "modifiers": modifiers,
            "fn": fn,
            "fnOnly": fnOnly,
        ]
    }

    var needsAccessibility: Bool { fn || fnOnly }
}

enum AppPrefs {
    static func register() {
        UserDefaults.standard.register(defaults: [
            PrefKey.keyCode: HotkeySpec.standard.keyCode,
            PrefKey.modifiers: HotkeySpec.standard.modifiers,
            PrefKey.fn: false,
            PrefKey.fnOnly: false,
            PrefKey.autoPaste: true,
            PrefKey.maxItems: 500,
            PrefKey.glassStyle: "auto",
            PrefKey.appearance: "system",
        ])
    }

    static var hotkey: HotkeySpec {
        let defaults = UserDefaults.standard
        return HotkeySpec(
            keyCode: defaults.integer(forKey: PrefKey.keyCode),
            modifiers: defaults.integer(forKey: PrefKey.modifiers),
            fn: defaults.bool(forKey: PrefKey.fn),
            fnOnly: defaults.bool(forKey: PrefKey.fnOnly)
        )
    }

    static func store(hotkey: HotkeySpec) {
        let defaults = UserDefaults.standard
        defaults.set(hotkey.keyCode, forKey: PrefKey.keyCode)
        defaults.set(hotkey.modifiers, forKey: PrefKey.modifiers)
        defaults.set(hotkey.fn, forKey: PrefKey.fn)
        defaults.set(hotkey.fnOnly, forKey: PrefKey.fnOnly)
    }

    static var autoPaste: Bool { UserDefaults.standard.bool(forKey: PrefKey.autoPaste) }
    static var maxItems: Int { max(20, UserDefaults.standard.integer(forKey: PrefKey.maxItems)) }
    static var glassStyle: String { UserDefaults.standard.string(forKey: PrefKey.glassStyle) ?? "auto" }

    /// "system", "light" or "dark" — an explicit override for the panel.
    static var appearance: String { UserDefaults.standard.string(forKey: PrefKey.appearance) ?? "system" }
}

// MARK: - Accessibility / synthetic paste

func accessibilityTrusted(prompt: Bool) -> Bool {
    let option = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    return AXIsProcessTrustedWithOptions([option: prompt] as CFDictionary)
}

/// Posts ⌘V into the frontmost application.
func postCommandV() {
    guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
    let key: CGKeyCode = 9 // 'v'
    let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
    let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
    down?.flags = .maskCommand
    up?.flags = .maskCommand
    down?.post(tap: .cgAnnotatedSessionEventTap)
    up?.post(tap: .cgAnnotatedSessionEventTap)
}

func openAccessibilitySettings() {
    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    if let url { NSWorkspace.shared.open(url) }
}

// MARK: - Login item

enum LoginItem {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    try SMAppService.mainApp.unregister()
                }
                return true
            } catch {
                NSLog("CopyPaste: login item error: \(error.localizedDescription)")
                return false
            }
        }
        return false
    }
}

// MARK: - Misc helpers

func systemAccentHex() -> Int {
    guard let rgb = NSColor.controlAccentColor.usingColorSpace(.sRGB) else { return 0x0A84FF }
    let r = Int(round(rgb.redComponent * 255)) & 0xFF
    let g = Int(round(rgb.greenComponent * 255)) & 0xFF
    let b = Int(round(rgb.blueComponent * 255)) & 0xFF
    return (r << 16) | (g << 8) | b
}

func isDarkAppearance() -> Bool {
    switch AppPrefs.appearance {
    case "light":
        return false
    case "dark":
        return true
    default:
        break
    }
    // `NSApp.effectiveAppearance` is unreliable for an accessory app that has
    // never been activated, so ask the system preference directly.
    if let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") {
        return style.lowercased() == "dark"
    }
    let match = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
    return match == .darkAqua
}

func bundleVersion() -> String {
    let info = Bundle.main.infoDictionary
    let short = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    return short
}

// MARK: - Diagnostics

private let debugTimestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
}()

/// Appends a line to `~/Library/Application Support/CopyPaste/debug.log`.
/// The panel is hard to inspect from the outside, so the app keeps a small
/// trace of what the native side actually received.
func debugLog(_ message: String) {
    NSLog("CopyPaste: %@", message)
    guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        return
    }
    let directory = base.appendingPathComponent("CopyPaste", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("debug.log")
    let line = "[\(debugTimestampFormatter.string(from: Date()))] \(message)\n"

    if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
       let size = attributes[.size] as? Int, size > 512_000 {
        try? FileManager.default.removeItem(at: url)
    }
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        try? line.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - App icons

/// Resolves and caches 64×64 PNGs of source-app icons for the Flutter panel.
final class AppIconCache {
    static let shared = AppIconCache()

    private let fileManager = FileManager.default
    private let iconsDir: URL
    private var memory: [String: String] = [:]

    private init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        iconsDir = base
            .appendingPathComponent("CopyPaste", isDirectory: true)
            .appendingPathComponent("icons", isDirectory: true)
        try? fileManager.createDirectory(at: iconsDir, withIntermediateDirectories: true)
    }

    /// Returns a filesystem path to a PNG icon, or nil when the app cannot be found.
    func path(bundleId: String, name: String) -> String? {
        let key = !bundleId.isEmpty ? bundleId : name
        guard !key.isEmpty else { return nil }
        if let cached = memory[key] { return cached }

        let file = iconsDir.appendingPathComponent("\(Self.safeFileName(key)).png")
        if fileManager.fileExists(atPath: file.path) {
            memory[key] = file.path
            return file.path
        }

        guard let appURL = Self.applicationURL(bundleId: bundleId, name: name) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 64, height: 64)
        guard let tiff = icon.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        do {
            try png.write(to: file, options: .atomic)
        } catch {
            return nil
        }
        memory[key] = file.path
        return file.path
    }

    private static func safeFileName(_ key: String) -> String {
        key.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }

    private static func applicationURL(bundleId: String, name: String) -> URL? {
        if !bundleId.isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return url
        }
        if name.isEmpty { return nil }

        for app in NSWorkspace.shared.runningApplications {
            if app.localizedName == name, let url = app.bundleURL {
                return url
            }
        }

        let roots = [
            "/Applications",
            "/System/Applications",
            NSHomeDirectory() + "/Applications",
        ]
        for root in roots {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: root) else {
                continue
            }
            for item in contents where item.hasSuffix(".app") {
                let url = URL(fileURLWithPath: root).appendingPathComponent(item)
                if matches(appURL: url, name: name) {
                    return url
                }
            }
        }
        return nil
    }

    private static func matches(appURL: URL, name: String) -> Bool {
        let folderName = appURL.deletingPathExtension().lastPathComponent
        if folderName.caseInsensitiveCompare(name) == .orderedSame {
            return true
        }
        guard let bundle = Bundle(url: appURL) else { return false }
        let display = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        if let display, display.caseInsensitiveCompare(name) == .orderedSame {
            return true
        }
        if let bundleName, bundleName.caseInsensitiveCompare(name) == .orderedSame {
            return true
        }
        return false
    }
}
