import AppKit

/// The menu-bar item: left click opens the panel at the cursor, right click
/// shows the context menu.
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    var onOpen: (() -> Void)?
    var onSettings: (() -> Void)?
    var onClear: (() -> Void)?
    var onToggleLogin: (() -> Void)?
    var onQuit: (() -> Void)?

    var launchAtLogin: Bool = false {
        didSet { loginItem.state = launchAtLogin ? .on : .off }
    }

    private lazy var loginItem: NSMenuItem = {
        let item = NSMenuItem(
            title: "Запускать при входе",
            action: #selector(toggleLogin),
            keyEquivalent: ""
        )
        item.target = self
        return item
    }()

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: "CopyPaste"
            )
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.toolTip = "CopyPaste — история буфера"
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        buildMenu()
    }

    private func buildMenu() {
        let open = NSMenuItem(title: "Открыть панель", action: #selector(openPanel), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let settings = NSMenuItem(title: "Настройки…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let clear = NSMenuItem(title: "Очистить историю", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Выход", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            onOpen?()
        }
    }

    private func showMenu() {
        guard let button = statusItem.button else { return }
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height + 4),
            in: button
        )
    }

    @objc private func openPanel() {
        onOpen?()
    }

    @objc private func openSettings() {
        onSettings?()
    }

    @objc private func clearHistory() {
        onClear?()
    }

    @objc private func toggleLogin() {
        onToggleLogin?()
    }

    @objc private func quit() {
        onQuit?()
    }
}
