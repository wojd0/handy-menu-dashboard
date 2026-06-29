import SwiftUI

@main
struct HandyMenuDashboardApp: App {
    @State private var cursorService = CursorService()
    @State private var copilotService = CopilotService()
    @State private var claudeService = ClaudeService()

    var body: some Scene {
        MenuBarExtra {
            DashboardView(cursorService: cursorService, copilotService: copilotService, claudeService: claudeService)
        } label: {
            MenuBarLabel(cursorService: cursorService, copilotService: copilotService, claudeService: claudeService)
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView(cursorService: cursorService, copilotService: copilotService, claudeService: claudeService)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

struct MenuBarLabel: View {
    var cursorService: CursorService
    var copilotService: CopilotService
    var claudeService: ClaudeService
    @AppStorage("cursorMenuBarShowPercent") private var cursorShowPercent = false
    @AppStorage("copilotMenuBarShowPercent") private var copilotShowPercent = false
    @AppStorage("claudeMenuBarShowPercent") private var claudeShowPercent = false
    @AppStorage("claudeMenuBarBaseline") private var claudeBaseline = ClaudeBaseline.usageLimit
    @AppStorage(Provider.orderStorageKey) private var providerOrderRaw = Provider.defaultOrderRaw
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let lines = Provider.ordered(from: providerOrderRaw)
            .map(fragment(for:))
            .filter { !$0.isEmpty }

        if let image = renderImage(lines: lines) {
            Image(nsImage: image)
        } else {
            Text("Usage")
                .font(.caption2)
        }
    }

    private func fragment(for provider: Provider) -> String {
        switch provider {
        case .cursor:
            cursorShowPercent ? cursorService.menuBarPercentFragment : cursorService.menuBarFragment
        case .copilot:
            copilotShowPercent ? copilotService.menuBarPercentFragment : copilotService.menuBarFragment
        case .claude:
            claudeService.menuBarFragment(baseline: claudeBaseline, showPercent: claudeShowPercent)
        }
    }

    private func renderImage(lines: [String]) -> NSImage? {
        guard !lines.isEmpty else { return nil }

        let fontSize = min(11, 21 / CGFloat(lines.count))
        let renderer = ImageRenderer(content:
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                }
            }
            .font(.system(size: fontSize))
            .monospacedDigit()
        )
        renderer.scale = displayScale

        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = true
        return image
    }
}
