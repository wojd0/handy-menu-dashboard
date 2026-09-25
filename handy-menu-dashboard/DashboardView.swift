import SwiftUI

struct DashboardView: View {
    let services: ServiceSet
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Provider.orderStorageKey) private var providerOrderRaw = Provider.defaultOrderRaw
    @State private var dialogDismissed = false

    var body: some View {
        let activeProviders = Provider.ordered(from: providerOrderRaw).filter(isActive)
        let pending = services.sessionUpdates.pending

        VStack(alignment: .leading, spacing: 16) {
            if !pending.isEmpty && !dialogDismissed {
                SessionUpdateDialog(
                    coordinator: services.sessionUpdates,
                    width: 240,
                    onWebViewFallback: { _ in openSettings() },
                    onClose: { dialogDismissed = true }
                )
                Divider()
            }

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

            let pendingRows = pending.filter { !activeProviders.contains($0) }
            if dialogDismissed {
                ForEach(pendingRows) { provider in
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(provider.displayName)
                            .font(.callout)
                        Spacer()
                        Text("Needs update")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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

                Button {
                    Task { await services.refreshAll() }
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.title2)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(isRefreshing)
                .help("Refresh all services")
                .accessibilityLabel("Refresh all services")

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
        .onAppear {
            dialogDismissed = false
            services.sessionUpdates.skip()
        }
    }

    private func isActive(_ provider: Provider) -> Bool {
        services[provider].isActive
    }

    private var isRefreshing: Bool {
        Provider.allCases.contains { services[$0].isLoading }
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
            error: service.error
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
