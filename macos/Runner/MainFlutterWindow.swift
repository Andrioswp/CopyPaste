import Cocoa
import FlutterMacOS

/// CopyPaste lives in the menu bar, so the window declared in MainMenu.xib is
/// created but never shown. The Flutter surface is hosted by `PanelController`
/// instead.
class MainFlutterWindow: NSWindow {
    override func awakeFromNib() {
        super.awakeFromNib()
        isReleasedWhenClosed = false
        orderOut(nil)
    }
}
