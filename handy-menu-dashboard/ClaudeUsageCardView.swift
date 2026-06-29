import SwiftUI

struct ClaudeUsageCardView: View {
    @Bindable var claudeService: ClaudeService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Claude")
                    .font(.headline)

                Spacer()

                if claudeService.isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                } else {
                    Button {
                        Task { await claudeService.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            if let error = claudeService.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                if claudeService.hasSpend {
                    poolRow(
                        title: "General",
                        used: claudeService.spendUsedDollars,
                        limit: claudeService.spendLimitDollars
                    )
                }

                if claudeService.hasCredit {
                    poolRow(
                        title: "Code and Cowork",
                        used: claudeService.creditUsedDollars,
                        limit: claudeService.creditLimitDollars
                    )
                }
            }
        }
    }

    private func poolRow(title: String, used: Double, limit: Double) -> some View {
        let percent = UsageMath.percentUsed(used: used, limit: limit)
        let isOverLimit = UsageMath.isOverLimit(percentUsed: percent)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(Int(percent))%")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isOverLimit ? .red : .primary)

                if isOverLimit {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption2)
                }
            }

            Text("\(UsageMath.formatDollars(used)) / \(UsageMath.formatDollars(limit))")
                .font(.caption)
                .foregroundStyle(.secondary)

            UsageProgressBar(percentage: percent, isOverLimit: isOverLimit)
        }
    }
}
