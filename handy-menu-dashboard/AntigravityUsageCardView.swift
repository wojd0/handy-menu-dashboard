import SwiftUI

struct AntigravityUsageCardView: View {
    let service: AntigravityService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProviderTitle(provider: .antigravity)

            if let error = service.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                ForEach(service.groups, id: \.name) { group in
                    let windows = group.windows.filter { service.showsUsageBar($0.id) }
                    if !windows.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ForEach(windows, id: \.id) { window in
                                UsagePoolRow(
                                    title: window.title,
                                    percent: window.percentUsed,
                                    resetsAt: window.resetsAt
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
