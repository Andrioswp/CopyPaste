import AppKit
import FlutterMacOS

/// Glue between the Flutter UI and the AppKit services.
final class HostBridge: NSObject, FlutterStreamHandler {
    private let history: ClipboardHistory
    private let panel: PanelController
    private let hotkeys: HotKeyManager
    private let status: StatusItemController

    private var eventSink: FlutterEventSink?

    init(
        history: ClipboardHistory,
        panel: PanelController,
        hotkeys: HotKeyManager,
        status: StatusItemController
    ) {
        self.history = history
        self.panel = panel
        self.hotkeys = hotkeys
        self.status = status
        super.init()
        panel.glassStyle = AppPrefs.glassStyle
    }

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        pushHistory()
        pushSettings()
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    // MARK: - Emitting

    func emit(_ payload: [String: Any]) {
        guard let sink = eventSink else { return }
        sink(payload)
    }

    func pushHistory() {
        emit(["type": "history", "items": history.snapshot()])
    }

    func pushSettings() {
        emit(["type": "settings", "settings": settingsPayload()])
    }

    func onPanelShown(flipped: Bool) {
        pushHistory()
        // `flipped` means the panel had to open above the cursor (the input
        // field is below it), so the UI puts the newest entry at the bottom.
        emit(["type": "shown", "flipped": flipped])
    }

    func openSettings() {
        emit(["type": "openSettings"])
    }

    func notify(_ text: String) {
        emit(["type": "notice", "text": text])
    }

    private func settingsPayload() -> [String: Any] {
        return [
            "hotkey": AppPrefs.hotkey.dict,
            "autoPaste": AppPrefs.autoPaste,
            "launchAtLogin": LoginItem.isEnabled,
            "maxItems": AppPrefs.maxItems,
            "glassStyle": AppPrefs.glassStyle,
            "appearance": AppPrefs.appearance,
            "accessibility": accessibilityTrusted(prompt: false),
            "accent": systemAccentHex(),
            "dark": isDarkAppearance(),
            "version": bundleVersion(),
        ]
    }

    // MARK: - Method channel

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        if call.method != "setHeight", call.method != "ready" {
            debugLog("ui → \(call.method) \(args)")
        }

        switch call.method {
        case "ready":
            result([
                "items": history.snapshot(),
                "settings": settingsPayload(),
            ])

        case "hide":
            panel.hide()
            result(nil)

        case "paste":
            guard let id = args["id"] as? String, let item = history.item(with: id) else {
                result(false)
                return
            }
            let autoPaste = args["autoPaste"] as? Bool ?? AppPrefs.autoPaste
            performPaste(item, autoPaste: autoPaste)
            result(true)

        case "copy":
            guard let id = args["id"] as? String, let item = history.item(with: id) else {
                result(false)
                return
            }
            history.writeToPasteboard(item)
            notify("Скопировано в буфер обмена")
            result(true)

        case "pin":
            guard let id = args["id"] as? String else {
                result(false)
                return
            }
            let pinned = args["pinned"] as? Bool ?? false
            result(history.setPinned(id: id, pinned: pinned))

        case "delete":
            guard let id = args["id"] as? String else {
                result(false)
                return
            }
            result(history.remove(id: id))

        case "clear":
            let keepPinned = args["keepPinned"] as? Bool ?? true
            history.clear(keepPinned: keepPinned)
            notify("История очищена")
            result(true)

        case "reveal":
            guard let id = args["id"] as? String, let item = history.item(with: id) else {
                result(false)
                return
            }
            revealInFinder(item)
            result(true)

        case "setSetting":
            applySetting(key: args["key"] as? String ?? "", value: args["value"])
            result(true)

        case "beginHotkeyCapture":
            hotkeys.beginCapture()
            result(nil)

        case "cancelHotkeyCapture":
            hotkeys.cancelCapture()
            result(nil)

        case "setHeight":
            if let height = args["height"] as? Double {
                panel.setCardHeight(CGFloat(height))
            }
            result(nil)

        case "setPeekVisible":
            panel.setPeekVisible(args["visible"] as? Bool ?? false)
            result(nil)

        case "requestAccessibility":
            _ = accessibilityTrusted(prompt: true)
            openAccessibilitySettings()
            pushSettings()
            result(true)

        case "quit":
            NSApp.terminate(nil)
            result(nil)

        case "log":
            debugLog("ui: \(args["message"] as? String ?? "")")
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Actions

    private func applySetting(key: String, value: Any?) {
        switch key {
        case "autoPaste":
            UserDefaults.standard.set(value as? Bool ?? true, forKey: PrefKey.autoPaste)
        case "launchAtLogin":
            let enabled = value as? Bool ?? false
            if !LoginItem.set(enabled) {
                notify("Не удалось изменить автозапуск")
            }
            status.launchAtLogin = LoginItem.isEnabled
        case "maxItems":
            if let count = value as? Int {
                history.applyMaxItems(count)
            }
        case "glassStyle":
            if let style = value as? String {
                UserDefaults.standard.set(style, forKey: PrefKey.glassStyle)
                panel.glassStyle = style
            }
        case "appearance":
            if let appearance = value as? String {
                UserDefaults.standard.set(appearance, forKey: PrefKey.appearance)
                panel.applyAppearance()
            }
        case "hotkeyReset":
            hotkeys.activate(.standard)
        default:
            break
        }
        pushSettings()
    }

    private func performPaste(_ item: ClipItem, autoPaste: Bool) {
        history.writeToPasteboard(item)
        let target = panel.previousApp
        let trusted = accessibilityTrusted(prompt: false)
        debugLog(
            "paste — item=\(item.kind.rawValue) autoPaste=\(autoPaste) trusted=\(trusted) " +
            "target=\(target?.localizedName ?? "nil")(\(target?.processIdentifier ?? -1))"
        )

        guard autoPaste else {
            notify("Скопировано — вставь сочетанием ⌘V")
            panel.hideAfter(0.7)
            return
        }
        guard trusted else {
            notify("Элемент скопирован. Для автовставки разреши «Универсальный доступ»")
            _ = accessibilityTrusted(prompt: true)
            openAccessibilitySettings()
            panel.hideAfter(2.2)
            return
        }

        panel.hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let target, target.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                if #available(macOS 14.0, *) {
                    _ = target.activate()
                } else {
                    target.activate(options: [.activateIgnoringOtherApps])
                }
            } else {
                debugLog("no valid paste target, ⌘V would go nowhere")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                postCommandV()
                debugLog("posted ⌘V")
            }
        }
    }

    private func revealInFinder(_ item: ClipItem) {
        var urls: [URL] = []
        if !item.files.isEmpty {
            urls = item.files.map { URL(fileURLWithPath: $0) }
        } else if let blob = item.blob {
            urls = [history.blobsDir.appendingPathComponent(blob)]
        }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}
