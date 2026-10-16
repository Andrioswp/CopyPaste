import AppKit
import Carbon.HIToolbox

/// Global shortcut handling.
///
/// Plain modifier combinations go through Carbon's `RegisterEventHotKey`, which
/// needs no special permission. Combinations that include Fn (the Globe key)
/// cannot be expressed as a Carbon hotkey, so they are observed with global and
/// local event monitors, which do require the accessibility permission.
final class HotKeyManager {
    var onTrigger: (() -> Void)?
    var onCapture: ((HotkeySpec?) -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var captureMonitor: Any?

    private var capturing = false
    private var fnCandidate = false
    private var fnPressedAt: TimeInterval = 0
    private var fnKeyPressed = false
    private var lastTriggerAt: TimeInterval = 0

    private(set) var spec: HotkeySpec = .standard

    // MARK: - Activation

    func activate(_ newSpec: HotkeySpec) {
        spec = newSpec
        AppPrefs.store(hotkey: newSpec)
        unregister()
        if newSpec.fn || newSpec.fnOnly {
            installMonitorBasedHotkey()
        } else {
            registerCarbonHotKey(newSpec)
        }
    }

    private func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    // MARK: - Carbon hot key

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { (
            _ callRef: EventHandlerCallRef?,
            _ event: EventRef?,
            _ userData: UnsafeMutableRawPointer?
        ) -> OSStatus in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.fire()
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    private func registerCarbonHotKey(_ spec: HotkeySpec) {
        installEventHandlerIfNeeded()
        guard spec.keyCode > 0 else { return }
        let hotKeyID = EventHotKeyID(signature: OSType(0x43504C50), id: 1) // 'CPLP'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(spec.keyCode),
            UInt32(spec.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
        } else {
            NSLog("CopyPaste: RegisterEventHotKey failed with status \(status)")
        }
    }

    // MARK: - Fn based hot keys

    private func installMonitorBasedHotkey() {
        let mask: NSEvent.EventTypeMask = [.keyDown, .flagsChanged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleMonitorEvent(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleMonitorEvent(event)
            return event
        }
    }

    private func handleMonitorEvent(_ event: NSEvent) {
        guard !capturing else { return }

        if spec.fnOnly {
            switch event.type {
            case .flagsChanged:
                let flags = event.modifierFlags
                let otherModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
                let fnOnly = flags.contains(.function) &&
                    flags.intersection(otherModifiers).isEmpty
                if fnOnly {
                    fnCandidate = true
                    fnPressedAt = Date().timeIntervalSince1970
                    fnKeyPressed = false
                } else if fnCandidate {
                    let duration = Date().timeIntervalSince1970 - fnPressedAt
                    if duration < 0.6 && !fnKeyPressed {
                        fire()
                    }
                    fnCandidate = false
                }
            case .keyDown:
                if fnCandidate {
                    fnCandidate = false
                    fnKeyPressed = true
                }
            default:
                break
            }
            return
        }

        guard event.type == .keyDown else { return }
        guard Int(event.keyCode) == spec.keyCode else { return }
        guard event.modifierFlags.contains(.function) else { return }
        guard modifiersMatch(event.modifierFlags) else { return }
        fire()
    }

    private func modifiersMatch(_ flags: NSEvent.ModifierFlags) -> Bool {
        var required: NSEvent.ModifierFlags = []
        if spec.modifiers & 256 != 0 { required.insert(.command) }
        if spec.modifiers & 512 != 0 { required.insert(.shift) }
        if spec.modifiers & 2048 != 0 { required.insert(.option) }
        if spec.modifiers & 4096 != 0 { required.insert(.control) }
        let relevant: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        return flags.intersection(relevant) == required
    }

    private func fire() {
        let now = Date().timeIntervalSince1970
        guard now - lastTriggerAt > 0.25 else { return }
        lastTriggerAt = now
        debugLog("hotkey fired")
        DispatchQueue.main.async { [weak self] in
            self?.onTrigger?()
        }
    }

    // MARK: - Shortcut recording

    func beginCapture() {
        guard !capturing else { return }
        capturing = true
        fnCandidate = false
        fnKeyPressed = false
        captureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
            [weak self] event in
            guard let self, self.capturing else { return event }
            return self.handleCaptureEvent(event) ? nil : event
        }
    }

    func cancelCapture() {
        guard capturing else { return }
        endCapture()
        onCapture?(nil)
    }

    private func handleCaptureEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        let fn = flags.contains(.function)
        let relevant: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

        if event.type == .flagsChanged {
            if fn && flags.intersection(relevant).isEmpty && !specContainsFnKeyPress() {
                fnCandidate = true
                fnPressedAt = Date().timeIntervalSince1970
                return true
            }
            if fnCandidate && !fn {
                let duration = Date().timeIntervalSince1970 - fnPressedAt
                fnCandidate = false
                if duration < 0.8 && !fnKeyPressed {
                    finishCapture(HotkeySpec(keyCode: 0, modifiers: 0, fn: true, fnOnly: true))
                }
                fnKeyPressed = false
                return true
            }
            return true
        }

        guard event.type == .keyDown else { return true }
        let code = Int(event.keyCode)
        fnKeyPressed = fnCandidate || fnKeyPressed

        if code == 53 && flags.intersection(relevant).isEmpty && !fn {
            cancelCapture()
            return true
        }
        if isModifierKeyCode(code) {
            return true
        }

        var modifiers = 0
        if flags.contains(.command) { modifiers |= 256 }
        if flags.contains(.shift) { modifiers |= 512 }
        if flags.contains(.option) { modifiers |= 2048 }
        if flags.contains(.control) { modifiers |= 4096 }

        // A bare letter would hijack normal typing; require a modifier or Fn.
        guard modifiers != 0 || fn else { return true }

        finishCapture(HotkeySpec(keyCode: code, modifiers: modifiers, fn: fn, fnOnly: false))
        return true
    }

    private func specContainsFnKeyPress() -> Bool {
        return fnKeyPressed
    }

    private func isModifierKeyCode(_ code: Int) -> Bool {
        return (54...63).contains(code)
    }

    private func finishCapture(_ newSpec: HotkeySpec) {
        endCapture()
        activate(newSpec)
        onCapture?(newSpec)
    }

    private func endCapture() {
        capturing = false
        if let monitor = captureMonitor {
            NSEvent.removeMonitor(monitor)
            captureMonitor = nil
        }
        fnCandidate = false
        fnKeyPressed = false
    }
}
