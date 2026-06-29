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

    var body: some View {
        let cursorText = cursorShowPercent ? cursorService.menuBarPercentFragment : cursorService.menuBarFragment
        let copilotText = copilotShowPercent ? copilotService.menuBarPercentFragment : copilotService.menuBarFragment
        let claudeText = claudeService.menuBarFragment(baseline: claudeBaseline, showPercent: claudeShowPercent)
        let hasCursor = !cursorText.isEmpty
        let hasCopilot = !copilotText.isEmpty
        let hasClaude = !claudeText.isEmpty

        if hasCursor || hasCopilot || hasClaude {
            VStack(alignment: .leading, spacing: 0) {
                if hasCursor {
                    Text(cursorText)
                }
                if hasCopilot {
                    Text(copilotText)
                }
                if hasClaude {
                    Text(claudeText)
                }
            }
            .font(.caption2)
            .monospacedDigit()
        } else {
            Text("Usage")
                .font(.caption2)
        }
    }
}
