import SwiftUI

struct DashboardView: View {
    var cursorService: CursorService
    var copilotService: CopilotService
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if cursorService.isActive || copilotService.isActive {
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
                Button(action: { openWindow(id: "settings") }) {
                    Image(systemName: "gearshape")
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
                group.addTask { await copilotService.refresh() }
            }
        }
    }
}
