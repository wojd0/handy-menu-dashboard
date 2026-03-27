import SwiftUI

@main
struct wojciech_little_dashboardApp: App {
    @State private var cursorService = CursorService()
    @State private var copilotService = CopilotService()

    var body: some Scene {
        MenuBarExtra {
            DashboardView(cursorService: cursorService, copilotService: copilotService)
        } label: {
            MenuBarLabel(cursorService: cursorService, copilotService: copilotService)
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView(cursorService: cursorService, copilotService: copilotService)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

struct MenuBarLabel: View {
    var cursorService: CursorService
    var copilotService: CopilotService

    var body: some View {
        let cursorText = cursorService.menuBarFragment
        let copilotText = copilotService.menuBarFragment
        let hasCursor = !cursorText.isEmpty
        let hasCopilot = !copilotText.isEmpty

        if hasCursor || hasCopilot {
            VStack(alignment: .leading, spacing: 0) {
                if hasCursor {
                    Text(cursorText)
                }
                if hasCopilot {
                    Text(copilotText)
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
