import SwiftUI

struct DashboardView: View {
    var cursorService: CursorService
    var copilotService: CopilotService
    var claudeService: ClaudeService
    @Environment(\.openWindow) private var openWindow
    @AppStorage("claudeMenuBarBaseline") private var claudeBaseline = ClaudeBaseline.usageLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if cursorService.isActive || copilotService.isActive || claudeService.isActive {
                if cursorService.isActive {
                    UsageCardView(
                        serviceName: "Cursor",
                        percentUsed: cursorService.spendPercentUsed,
                        detailText: "\(cursorService.spendFormatted) / \(cursorService.limitFormatted)",
                        subtitle: cursorService.userName,
                        isOverLimit: cursorService.spendPercentUsed > 100,
                        isLoading: cursorService.isLoading,
                        error: cursorService.error,
                        onRefresh: { Task { await cursorService.refresh() } }
                    )
                }

                if cursorService.isActive && copilotService.isActive {
                    Divider()
                }

                if copilotService.isActive {
                    UsageCardView(
                        serviceName: "GitHub Copilot",
                        percentUsed: copilotService.percentUsed,
                        detailText: "\(copilotService.totalUsed) / \(copilotService.monthlyEntitlement) premium requests",
                        subtitle: nil,
                        isOverLimit: copilotService.isOverLimit,
                        isLoading: copilotService.isLoading,
                        error: copilotService.error,
                        onRefresh: { Task { await copilotService.refresh() } }
                    )
                }

                if (cursorService.isActive || copilotService.isActive) && claudeService.isActive {
                    Divider()
                }

                if claudeService.isActive {
                    UsageCardView(
                        serviceName: "Claude",
                        percentUsed: claudeService.percentUsed(for: claudeBaseline),
                        detailText: claudeService.detailText(for: claudeBaseline),
                        subtitle: nil,
                        isOverLimit: claudeService.percentUsed(for: claudeBaseline) > 100,
                        isLoading: claudeService.isLoading,
                        error: claudeService.error,
                        onRefresh: { Task { await claudeService.refresh() } }
                    )
                }
            } else {
                VStack(spacing: 8) {
                    Text("No services configured")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Open Settings to connect your accounts")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Divider()

            HStack {
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 280)
        .task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await cursorService.refresh() }
                if FeatureFlags.showGitHubSettings {
                    group.addTask { await copilotService.refresh() }
                }
                if FeatureFlags.showClaudeSettings {
                    group.addTask { await claudeService.refresh() }
                }
            }
        }
    }

    private func openSettings() {
        openWindow(id: "settings")

        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)

            let settingsWindow = NSApplication.shared.windows.first { window in
                window.identifier?.rawValue.contains("settings") == true || window.title == "Settings"
            }
            settingsWindow?.makeKeyAndOrderFront(nil)
            settingsWindow?.orderFrontRegardless()
        }
    }
}
