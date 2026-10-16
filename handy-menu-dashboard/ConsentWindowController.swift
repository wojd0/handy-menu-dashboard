import AppKit
import SwiftUI

@MainActor
final class ConsentWindowController {
    static let shared = ConsentWindowController()

    private var panel: NSPanel?

    func show(services: ServiceSet, providers: [Provider]? = nil) {
        let coordinator = services.sessionUpdates
        guard !coordinator.isHarvesting, !(providers ?? coordinator.pending).isEmpty else { return }
        coordinator.skip()

        let content = ConsentPanelContent(
            services: services,
            providers: providers,
            onClose: { [weak self] in self?.close() }
        )

        let hosting = NSHostingController(rootView: content)
        let panel = self.panel ?? makePanel()
        panel.contentViewController = hosting
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Session Update"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func close() {
        panel?.orderOut(nil)
    }
}

private struct ConsentPanelContent: View {
    let services: ServiceSet
    let providers: [Provider]?
    let onClose: () -> Void
    @State private var loginProvider: Provider?

    var body: some View {
        SessionUpdateDialog(
            coordinator: services.sessionUpdates,
            providers: providers,
            onWebViewFallback: { loginProvider = $0 },
            onClose: onClose
        )
        .sheet(item: $loginProvider) { provider in
            ProviderLoginSheet(provider: provider, services: services)
        }
    }
}
