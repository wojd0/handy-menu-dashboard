import SwiftUI

struct ClaudeUsageCardView: View {
    @Bindable var claudeService: ClaudeService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProviderTitle(provider: .claude)

            if let error = claudeService.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                if claudeService.hasSession {
                    poolRow(
                        title: "Session (5h)",
                        percent: claudeService.sessionPercent,
                        resetsAt: claudeService.sessionResetsAt
                    )
                }

                if claudeService.hasWeekly {
                    poolRow(
                        title: "Weekly",
                        percent: claudeService.weeklyPercent,
                        resetsAt: claudeService.weeklyResetsAt
                    )
                }

                if claudeService.hasSpend {
                    poolRow(
                        title: "General",
                        percent: UsageMath.percentUsed(
                            used: claudeService.spendUsedDollars,
                            limit: claudeService.spendLimitDollars
                        ),
                        detail: claudeService.detailText(for: .usageLimit)
                    )
                }

                if claudeService.hasCredit {
                    poolRow(
                        title: "Credit",
                        percent: UsageMath.percentUsed(
                            used: claudeService.creditUsedDollars,
                            limit: claudeService.creditLimitDollars
                        ),
                        detail: claudeService.detailText(for: .credit)
                    )
                }
            }
        }
    }

    private func poolRow(
        title: String,
        percent: Double,
        detail: String? = nil,
        resetsAt: Date? = nil
    ) -> some View {
        let isOverLimit = UsageMath.isOverLimit(percentUsed: percent)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(Int(percent))%")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isOverLimit ? .red : .primary)

                if isOverLimit {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption2)
                }
            }

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }

            if let resetsAt {
                Text(UsageMath.resetText(for: resetsAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            UsageProgressBar(percentage: percent, isOverLimit: isOverLimit)
        }
    }
}
