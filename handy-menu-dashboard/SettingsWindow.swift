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
