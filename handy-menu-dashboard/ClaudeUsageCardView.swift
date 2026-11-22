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
                    UsagePoolRow(
                        title: "Session (5h)",
                        percent: claudeService.sessionPercent,
                        resetsAt: claudeService.sessionResetsAt
                    )
                }

                if claudeService.hasWeekly {
                    UsagePoolRow(
                        title: "Weekly",
                        percent: claudeService.weeklyPercent,
                        resetsAt: claudeService.weeklyResetsAt
                    )
                }

                if claudeService.hasSpend {
                    UsagePoolRow(
                        title: "General",
                        percent: UsageMath.percentUsed(
                            used: claudeService.spendUsedDollars,
                            limit: claudeService.spendLimitDollars
                        ),
                        detail: claudeService.detailText(for: .usageLimit)
                    )
                }

                if claudeService.hasCredit {
                    UsagePoolRow(
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
}
