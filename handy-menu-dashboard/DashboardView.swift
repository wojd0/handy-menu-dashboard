import SwiftUI

struct DashboardView: View {
    var cursorService: CursorService
    var copilotService: CopilotService
    var claudeService: ClaudeService
    var chatGPTService: ChatGPTService
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Provider.orderStorageKey) private var providerOrderRaw = Provider.defaultOrderRaw

    var body: some View {
        let activeProviders = Provider.ordered(from: providerOrderRaw).filter(isActive)

        VStack(alignment: .leading, spacing: 16) {
            if activeProviders.isEmpty {
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
            } else {
                ForEach(Array(activeProviders.enumerated()), id: \.element) { index, provider in
                    if index > 0 {
                        Divider()
                    }
                    card(for: provider)
                }
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
                group.addTask { await claudeService.refresh() }
                group.addTask { await chatGPTService.refresh() }
            }
        }
    }

    private func isActive(_ provider: Provider) -> Bool {
        switch provider {
        case .cursor: cursorService.isActive
        case .copilot: copilotService.isActive
        case .claude: claudeService.isActive
        case .chatgpt: chatGPTService.isActive
        }
    }

    @ViewBuilder
    private func card(for provider: Provider) -> some View {
        switch provider {
        case .cursor:
            UsageCardView(
                provider: .cursor,
                percentUsed: cursorService.spendPercentUsed,
                detailText: "\(cursorService.spendFormatted) / \(cursorService.limitFormatted)",
                subtitle: cursorService.userName,
                isOverLimit: cursorService.spendPercentUsed > 100,
                isUnlimited: cursorService.isUnlimited,
                isLoading: cursorService.isLoading,
                error: cursorService.error,
                onRefresh: { Task { await cursorService.refresh() } }
            )
        case .copilot:
            UsageCardView(
                provider: .copilot,
                percentUsed: copilotService.percentUsed,
                detailText: "\(copilotService.totalUsed) / \(copilotService.monthlyEntitlement) premium requests",
                subtitle: nil,
                isOverLimit: copilotService.isOverLimit,
                isLoading: copilotService.isLoading,
                error: copilotService.error,
                onRefresh: { Task { await copilotService.refresh() } }
            )
        case .claude:
            ClaudeUsageCardView(claudeService: claudeService)
        case .chatgpt:
            UsageCardView(
                provider: .chatgpt,
                percentUsed: chatGPTService.percentUsed,
                detailText: chatGPTService.detailText,
                subtitle: nil,
                isOverLimit: chatGPTService.isOverLimit,
                isLoading: chatGPTService.isLoading,
                error: chatGPTService.error,
                onRefresh: { Task { await chatGPTService.refresh() } }
            )
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
