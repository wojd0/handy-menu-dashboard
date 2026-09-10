import SwiftUI

struct DashboardView: View {
    let services: ServiceSet
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
            await services.refreshAll()
        }
    }

    private func isActive(_ provider: Provider) -> Bool {
        services[provider].isActive
    }

    @ViewBuilder
    private func card(for provider: Provider) -> some View {
        switch provider {
        case .claude:
            ClaudeUsageCardView(claudeService: services.claude)
        case .cursor, .copilot, .chatgpt:
            usageCard(services[provider])
        }
    }

    private func usageCard(_ service: any UsageDisplaying) -> some View {
        let reading = service.reading

        return UsageCardView(
            provider: service.provider,
            percentUsed: reading.percentUsed,
            detailText: reading.detailText,
            subtitle: service.subtitle,
            isOverLimit: reading.isOverLimit,
            isUnlimited: reading.isUnlimited,
            isLoading: service.isLoading,
            error: service.error,
            onRefresh: { Task { await service.refresh() } }
        )
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
