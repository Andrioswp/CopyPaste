import AppKit
import FlutterMacOS

/// The window is larger than the visible card so the Flutter-drawn drop shadow
/// has room to fade out instead of being clipped by the window edge.
let cardMargin: CGFloat = 48
let cardRadius: CGFloat = 22
let cardWidth: CGFloat = 400

final class PanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Invisible strip over the panel header; dragging it moves the panel.
final class DragHandleView: NSView {
    weak var targetWindow: NSWindow?
    var onMoved: ((NSPoint) -> Void)?

    override func mouseDown(with event: NSEvent) {
        // Nothing to prepare: deltas are relative to the window itself.
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = targetWindow else { return }
        var origin = window.frame.origin
        origin.x += event.deltaX
        origin.y -= event.deltaY
        window.setFrameOrigin(origin)
        onMoved?(origin)
    }

    // No cursor override on purpose: the panel is dragged by its header, and a
    // grabbing-hand cursor there was distracting. The default arrow is used.
}

/// Container view controller used as the panel's `contentViewController`.
///
/// The Flutter view has to live inside a controller that is part of the
/// window's controller hierarchy: when it was merely added as a subview,
/// AppKit never delivered appearance callbacks and the Flutter engine ignored
/// pointer input entirely — clicks and wheel scrolling did nothing.
final class PanelHostController: NSViewController {
    let glassContainer = NSView()
    private let child: NSViewController

    init(child: NSViewController) {
        self.child = child
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let container = NSView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: cardWidth + cardMargin * 2,
                height: 440 + cardMargin * 2
            )
        )
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(child)

        // Keep the glass behind the Flutter card only — peek expands the
        // window to the right and must not stretch the blur under it.
        glassContainer.frame = NSRect(
            x: cardMargin,
            y: cardMargin,
            width: cardWidth,
            height: view.bounds.height - cardMargin * 2
        )
        glassContainer.wantsLayer = true
        glassContainer.layer?.cornerRadius = cardRadius
        glassContainer.layer?.masksToBounds = true
        glassContainer.autoresizingMask = [.height]
        view.addSubview(glassContainer)

        child.view.frame = view.bounds
        child.view.autoresizingMask = [.width, .height]
        view.addSubview(child.view)
    }

    // The Flutter engine handles mouse buttons in `FlutterViewController`,
    // which is reached through the responder chain. AppKit normally inserts the
    // controller there once it is a proper child, but forwarding explicitly
    // guarantees that a click is never silently dropped.
    override func mouseDown(with event: NSEvent) {
        debugLog("host controller forwarded mouseDown")
        child.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        child.mouseUp(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        child.mouseDragged(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        debugLog("host controller forwarded rightMouseDown")
        child.rightMouseDown(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        child.rightMouseUp(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        child.otherMouseDown(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        child.otherMouseUp(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        debugLog("host controller forwarded scrollWheel dy=\(event.scrollingDeltaY)")
        child.scrollWheel(with: event)
    }
}

/// A borderless, non-activating panel that hosts the Flutter surface on top of
/// a native glass backdrop and follows the mouse cursor.
final class PanelController {
    let panel: PanelWindow
    private let root: NSView
    private let glassContainer: NSView
    private var glassView: NSView?
    private let flutterView: NSView
    private let hostController: PanelHostController

    private var cardHeight: CGFloat = 440
    /// Extra width on the right for the Flutter hover-preview card.
    private var peekExtra: CGFloat = 0
    private var anchorTop: CGFloat = 0
    private var placeAbove = false

    /// True when the panel had to be placed above the cursor, i.e. the input
    /// field it serves sits below the panel.
    var isFlipped: Bool { placeAbove }
    private var lastHiddenAt: TimeInterval = -10
    private var shownAt: TimeInterval = -10
    private var hideTimer: Timer?
    private var activationTimer: Timer?
    private var globalClickMonitor: Any?
    private var dragHandle: DragHandleView?
    private(set) var isVisible = false
    private(set) var previousApp: NSRunningApplication?

    var onShown: (() -> Void)?
    var onHidden: (() -> Void)?
    var onAppearanceChange: (() -> Void)?

    var glassStyle: String = "auto" {
        didSet {
            if oldValue != glassStyle { rebuildGlass() }
        }
    }

    init(flutterViewController: FlutterViewController) {
        self.flutterView = flutterViewController.view

        let frame = NSRect(
            x: 0,
            y: 0,
            width: cardWidth + cardMargin * 2,
            height: cardHeight + cardMargin * 2
        )
        panel = PanelWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = false
        panel.acceptsMouseMovedEvents = true

        hostController = PanelHostController(child: flutterViewController)
        root = hostController.view          // builds the container hierarchy
        glassContainer = hostController.glassContainer
        panel.contentViewController = hostController

        // Header strip for dragging the panel (the right side stays free for
        // the header buttons, which must keep receiving clicks).
        let handleHeight: CGFloat = 40
        let handle = DragHandleView(
            frame: NSRect(
                x: cardMargin + 8,
                y: frame.height - cardMargin - handleHeight + 6,
                width: max(60, frame.width - cardMargin * 2 - 128),
                height: handleHeight
            )
        )
        handle.targetWindow = panel
        handle.autoresizingMask = [.width, .minYMargin]
        handle.onMoved = { [weak self] _ in
            guard let self else { return }
            // Keep the panel where the user put it when the content resizes.
            self.anchorTop = self.panel.frame.maxY - cardMargin
            self.placeAbove = false
        }
        dragHandle = handle
        root.addSubview(handle)

        rebuildGlass()
        applyAppearance()

        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, self.isVisible else { return }
            // A click in another app (or on the desktop) dismisses the panel.
            if !self.panel.frame.contains(NSEvent.mouseLocation) {
                debugLog("click outside the panel → hide")
                self.hide()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let age = Date().timeIntervalSince1970 - self.shownAt
            if age < 1.2 {
                // Right after showing, AppKit can hand key status back to the
                // previously active app for a moment. Hiding here made the
                // panel flash and vanish, so grab focus again instead.
                debugLog("early resignKey after \(Int(age * 1000))ms → re-asserting key")
                self.ensureKey(after: 0.05)
                return
            }
            // An accessory app loses activation quickly; closing the panel on
            // the first resign made it unusable, so give focus a chance to come
            // back before dismissing.
            self.scheduleHideUnlessKeyReturns()
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.cancelPendingHide()
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self?.applyAppearance()
            }
        }

        // Diagnostics: proves whether a click reaches our window at all, which
        // separates "the UI ignored it" from "AppKit never delivered it".
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] event in
            guard let self else { return event }
            let inPanel = event.window === self.panel
            let hit = self.panel.contentView?.hitTest(event.locationInWindow)
            debugLog(
                "mouse down at \(Int(event.locationInWindow.x)),\(Int(event.locationInWindow.y)) " +
                "window=\(inPanel ? "panel" : "other") key=\(self.panel.isKeyWindow) " +
                "active=\(NSApp.isActive) hit=\(type(of: hit ?? NSView()))"
            )
            return event
        }
    }

    // MARK: - Appearance

    /// Forces the window into the system's light/dark appearance so the glass
    /// material matches the rest of macOS instead of falling back to a dark
    /// vibrant look.
    func applyAppearance() {
        let dark = isDarkAppearance()
        panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        onAppearanceChange?()
    }

    // MARK: - Glass backdrop

    private func rebuildGlass() {
        glassView?.removeFromSuperview()
        glassView = nil
        glassContainer.layer?.cornerRadius = cardRadius
        glassContainer.layer?.masksToBounds = true

        if glassStyle != "vibrancy", #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cardRadius
            glass.style = .regular
            // Interactive glass reacts to every pointer movement and leaves
            // stale highlights behind the Flutter surface, so it stays off:
            // the UI itself provides all interaction feedback.
            if #available(macOS 27.0, *) {
                glass.effectIsInteractive = false
            }
            glass.frame = glassContainer.bounds
            glass.autoresizingMask = [.width, .height]
            glassContainer.addSubview(glass)
            glassView = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .underWindowBackground
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.frame = glassContainer.bounds
            effect.autoresizingMask = [.width, .height]
            glassContainer.addSubview(effect)
            glassView = effect
        }
    }

    // MARK: - Placement

    private func screenForMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    private func positionAtMouse() {
        let mouse = NSEvent.mouseLocation
        let size = panel.frame.size
        let cardH = size.height - cardMargin * 2
        var topEdge = mouse.y - 14
        placeAbove = false

        let screen = screenForMouse()
        if let visible = screen?.visibleFrame, topEdge - cardH < visible.minY + 8 {
            topEdge = mouse.y + 14 + cardH
            placeAbove = true
        }

        var x = mouse.x - size.width / 2
        var y = topEdge - (size.height - cardMargin)

        if let visible = screen?.visibleFrame {
            x = min(max(x, visible.minX + 6), visible.maxX - size.width - 6)
            y = min(max(y, visible.minY + 6), visible.maxY - size.height - 6)
        }

        anchorTop = topEdge
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        layoutDragHandle()
    }

    /// In the mirrored layout the header sits at the bottom of the card, so the
    /// drag strip moves there as well.
    private func layoutDragHandle() {
        guard let handle = dragHandle else { return }
        let handleHeight: CGFloat = 40
        let width = max(60, panel.frame.width - cardMargin * 2 - 128)
        let x = cardMargin + 8
        if placeAbove {
            handle.frame = NSRect(x: x, y: cardMargin + 4, width: width, height: handleHeight)
            handle.autoresizingMask = [.width, .maxYMargin]
        } else {
            handle.frame = NSRect(
                x: x,
                y: panel.frame.height - cardMargin - handleHeight + 6,
                width: width,
                height: handleHeight
            )
            handle.autoresizingMask = [.width, .minYMargin]
        }
    }

    // MARK: - Visibility

    func show() {
        guard !isVisible else { return }
        // Remember which app to paste into. Our own process must be ignored:
        // after the first show the app is active, and pasting "into ourselves"
        // would silently do nothing.
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        applyAppearance()
        positionAtMouse()
        panel.alphaValue = 1
        // An accessory (menu-bar only) app must activate itself explicitly,
        // otherwise the panel never gains keyboard focus and clicks land in a
        // window that cannot handle them.
        activateApp()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(flutterView)
        isVisible = true
        shownAt = Date().timeIntervalSince1970
        debugLog(
            "panel shown at \(Int(panel.frame.origin.x)),\(Int(panel.frame.origin.y)) " +
            "key=\(panel.isKeyWindow) active=\(NSApp.isActive)"
        )
        onShown?()
        startActivationKeepAlive()
        // Activation settles asynchronously, so retry a few times.
        ensureKey(after: 0.05)
        ensureKey(after: 0.3)
        ensureKey(after: 0.9)
    }

    /// Re-activates the app and re-claims key status for the panel.
    private func ensureKey(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isVisible, !self.panel.isKeyWindow else { return }
            activateApp()
            self.panel.makeKeyAndOrderFront(nil)
            self.panel.orderFrontRegardless()
            self.panel.makeKey()
            self.panel.makeFirstResponder(self.flutterView)
            debugLog("re-asserted key → \(self.panel.isKeyWindow) (active=\(NSApp.isActive))")
        }
    }

    /// `NSApp.activate()` (macOS 14+) is a "polite" request that an accessory
    /// app can be refused; the older call still forces activation, which the
    /// panel needs in order to keep keyboard focus.
    private func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
    }

    /// While the panel is open, macOS keeps deactivating a menu-bar-only app.
    /// An inactive app's window swallows the click that activates it, which is
    /// what made the buttons feel dead — so activation is re-asserted.
    private func startActivationKeepAlive() {
        activationTimer?.invalidate()
        activationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] _ in
            guard let self, self.isVisible else { return }
            if !NSApp.isActive || !self.panel.isKeyWindow {
                debugLog(
                    "keep-alive: active=\(NSApp.isActive) key=\(self.panel.isKeyWindow) → re-activating"
                )
                self.activateApp()
                self.panel.makeKeyAndOrderFront(nil)
                self.panel.makeKey()
                self.panel.makeFirstResponder(self.flutterView)
            }
        }
    }

    private func stopActivationKeepAlive() {
        activationTimer?.invalidate()
        activationTimer = nil
    }

    private func scheduleHideUnlessKeyReturns() {
        guard hideTimer == nil else { return }
        debugLog("resignKey → hiding in 6s unless focus returns")
        hideTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.hideTimer = nil
            guard self.isVisible else { return }
            if self.panel.isKeyWindow {
                debugLog("focus returned, panel stays open")
                return
            }
            // Reading the list with the cursor over the panel is not a reason
            // to close it, even if the accessory app is not active.
            if self.panel.frame.contains(NSEvent.mouseLocation) {
                debugLog("cursor is over the panel, staying open")
                self.scheduleHideUnlessKeyReturns()
                return
            }
            debugLog("focus did not return → hide")
            self.hide()
        }
    }

    private func cancelPendingHide() {
        guard hideTimer != nil else { return }
        hideTimer?.invalidate()
        hideTimer = nil
        debugLog("panel is key again, pending hide cancelled")
    }

    /// Development self-test: sends a synthetic click through the normal window
    /// dispatch path. If Flutter logs the pointer event, input delivery works
    /// end to end without a human having to click.
    func performSelfTestClick() {
        let point = NSPoint(x: cardMargin + cardWidth / 2, y: panel.frame.height / 2)
        // `NSEvent.mouseEvent(with:location:)` expects screen coordinates.
        let screenPoint = panel.convertPoint(toScreen: point)
        guard let down = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: screenPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ), let up = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: screenPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime + 0.05,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 0
        ) else {
            debugLog("self-test: could not build a synthetic event")
            return
        }
        debugLog("self-test: sending synthetic click at \(Int(point.x)),\(Int(point.y))")
        NSApp.sendEvent(down)
        NSApp.sendEvent(up)
        debugLog("self-test: synthetic click dispatched")
    }

    func hide() {
        guard isVisible else { return }
        debugLog("panel hidden")
        cancelPendingHide()
        stopActivationKeepAlive()
        if peekExtra > 0 {
            peekExtra = 0
            applyFrameSize(animated: false)
        }
        panel.orderOut(nil)
        isVisible = false
        lastHiddenAt = Date().timeIntervalSince1970
        onHidden?()
        // Hand focus back to whatever the user was working in.
        if NSApp.isActive, let previousApp, !previousApp.isTerminated,
           previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            if #available(macOS 14.0, *) {
                _ = previousApp.activate()
            } else {
                previousApp.activate(options: [])
            }
        }
    }

    func toggle() {
        if isVisible {
            hide()
            return
        }
        if Date().timeIntervalSince1970 - lastHiddenAt < 0.25 { return }
        show()
    }

    /// Hides the panel a moment later, so the user can read the confirmation
    /// message that was just sent to the UI.
    func hideAfter(_ delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.hide()
        }
    }

    // MARK: - Content driven sizing

    /// Shows or hides the right-side gutter used by the hover preview card.
    /// Never animate: animated resizes stutter the list under the cursor.
    func setPeekVisible(_ visible: Bool, animated: Bool = false) {
        // 12 gap + 300 card — keep in sync with PanelMetrics.peekGap/peekWidth.
        let extra: CGFloat = visible ? 312 : 0
        guard abs(extra - peekExtra) > 0.5 else { return }
        peekExtra = extra
        debugLog("peek \(visible ? "open" : "close") extra=\(Int(extra))")
        applyFrameSize(animated: false)
    }

    func setCardHeight(_ height: CGFloat, animated: Bool = true) {
        let clamped = max(160, min(height, 900))
        guard abs(clamped - cardHeight) > 0.5 else { return }
        cardHeight = clamped
        debugLog("resize card to \(Int(clamped))")
        applyFrameSize(animated: animated)
    }

    private func applyFrameSize(animated: Bool) {
        let newSize = NSSize(
            width: cardWidth + cardMargin * 2 + peekExtra,
            height: cardHeight + cardMargin * 2
        )
        var frame = panel.frame
        // Grow/shrink from the right so the glass card stays put.
        frame.origin.y = anchorTop - (newSize.height - cardMargin)
        frame.size = newSize

        if let visible = (panel.screen ?? screenForMouse())?.visibleFrame {
            frame.origin.y = min(max(frame.origin.y, visible.minY + 6), visible.maxY - newSize.height - 6)
            if frame.maxX > visible.maxX - 6 {
                frame.origin.x = visible.maxX - 6 - newSize.width
            }
            frame.origin.x = min(max(frame.origin.x, visible.minX + 6), visible.maxX - newSize.width - 6)
        }
        panel.setFrame(frame, display: true, animate: animated && isVisible)
        layoutDragHandle()
    }

    /// Used by the status-bar menu: show the panel and switch it to settings.
    func showForSettings() {
        show()
    }
}
