import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
    private var history: ClipboardHistory?
    private var panel: PanelController?
    private var hotkeys: HotKeyManager?
    private var status: StatusItemController?
    private var bridge: HostBridge?
    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?

    override func applicationDidFinishLaunching(_ notification: Notification) {
        AppPrefs.register()
        NSApp.setActivationPolicy(.accessory)
        debugLog(
            "launch — appearance=\(AppPrefs.appearance) dark=\(isDarkAppearance()) " +
            "glass=\(AppPrefs.glassStyle) trusted=\(accessibilityTrusted(prompt: false)) " +
            "hotkey=\(AppPrefs.hotkey.keyCode)/\(AppPrefs.hotkey.modifiers) fn=\(AppPrefs.hotkey.fn)"
        )

        // The Flutter surface renders inside the glass panel, so it must not
        // paint an opaque background of its own (`FlutterViewController`'s
        // backgroundColor is forwarded to the underlying FlutterView).
        let controller = FlutterViewController()
        controller.backgroundColor = .clear
        RegisterGeneratedPlugins(registry: controller)

        let clipboard = ClipboardHistory()
        let panelController = PanelController(flutterViewController: controller)
        let hotKeyManager = HotKeyManager()
        let statusController = StatusItemController()
        let hostBridge = HostBridge(
            history: clipboard,
            panel: panelController,
            hotkeys: hotKeyManager,
            status: statusController
        )

        let messenger = controller.engine.binaryMessenger
        let methods = FlutterMethodChannel(name: "copypaste/host", binaryMessenger: messenger)
        methods.setMethodCallHandler { call, result in
            hostBridge.handle(call, result: result)
        }
        let events = FlutterEventChannel(name: "copypaste/events", binaryMessenger: messenger)
        events.setStreamHandler(hostBridge)

        clipboard.onChange = { hostBridge.pushHistory() }
        panelController.onShown = {
            hostBridge.onPanelShown(flipped: panelController.isFlipped)
        }
        panelController.onAppearanceChange = { hostBridge.pushSettings() }

        hotKeyManager.onTrigger = { panelController.toggle() }
        hotKeyManager.onCapture = { spec in
            var payload: [String: Any] = ["type": "hotkeyCapture"]
            if let spec {
                payload["spec"] = spec.dict
            }
            hostBridge.emit(payload)
            hostBridge.pushSettings()
        }

        statusController.onOpen = { panelController.toggle() }
        statusController.onSettings = {
            panelController.show()
            hostBridge.openSettings()
        }
        statusController.onClear = { clipboard.clear(keepPinned: true) }
        statusController.onToggleLogin = {
            _ = LoginItem.set(!LoginItem.isEnabled)
            statusController.launchAtLogin = LoginItem.isEnabled
            hostBridge.pushSettings()
        }
        statusController.onQuit = { NSApp.terminate(nil) }
        statusController.launchAtLogin = LoginItem.isEnabled

        hotKeyManager.activate(AppPrefs.hotkey)
        clipboard.start()

        // CopyPaste is a menu-bar agent: the placeholder window declared in
        // MainMenu.xib must never stay on screen. It used to be ordered in
        // after `awakeFromNib`, which showed up as an empty dark window.
        for window in NSApp.windows where window !== panelController.panel {
            window.orderOut(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let livePanel = self?.panel?.panel else { return }
            for window in NSApp.windows where window !== livePanel {
                window.orderOut(nil)
            }
        }

        // Without the accessibility permission the automatic ⌘V paste cannot be
        // synthesised, so ask for it once through the system prompt.
        // Without the accessibility permission the automatic ⌘V paste cannot be
        // synthesised. Every rebuild of an ad-hoc signed app invalidates the
        // permission, so keep asking until it is granted.
        if AppPrefs.autoPaste, !accessibilityTrusted(prompt: false) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if !accessibilityTrusted(prompt: true) {
                    debugLog("accessibility still not granted")
                }
            }
        }

        // Development affordance: show the panel right away so the UI can be
        // inspected (or screenshotted) without pressing the hot key.
        if ProcessInfo.processInfo.environment["COPYPASTE_SHOW_PANEL"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                panelController.show()
            }
        }

        // Development self-test: click into the freshly shown panel and see
        // whether the event reaches Dart.
        if ProcessInfo.processInfo.environment["COPYPASTE_SELFTEST"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                panelController.show()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    panelController.performSelfTestClick()
                }
            }
        }

        history = clipboard
        panel = panelController
        hotkeys = hotKeyManager
        status = statusController
        bridge = hostBridge
        methodChannel = methods
        eventChannel = events

        super.applicationDidFinishLaunching(notification)
    }

    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    override func applicationWillTerminate(_ notification: Notification) {
        history?.stop()
    }
}
