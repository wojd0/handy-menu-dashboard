import AppKit
import SwiftUI

enum SettingsWindow {
    static let id = "settings"

    static func open(with openWindow: OpenWindowAction) {
        openWindow(id: id)

        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)

            let settingsWindow = NSApplication.shared.windows.first { window in
                window.identifier?.rawValue.contains(id) == true || window.title == "Settings"
            }
            settingsWindow?.makeKeyAndOrderFront(nil)
            settingsWindow?.orderFrontRegardless()
        }
    }
}

struct CloseOnlyWindowButtons: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        CloseOnlyWindowButtonsView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class CloseOnlyWindowButtonsView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.styleMask.remove(.miniaturizable)
        window.collectionBehavior.insert(.fullScreenNone)
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }
}
