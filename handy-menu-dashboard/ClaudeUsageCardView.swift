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
                if claudeService.hasSession && claudeService.showsUsageBar(ClaudeUsagePool.session.rawValue) {
                    UsagePoolRow(
                        title: "Session (5h)",
                        percent: claudeService.sessionPercent,
                        resetsAt: claudeService.sessionResetsAt
                    )
                }

                if claudeService.hasWeekly && claudeService.showsUsageBar(ClaudeUsagePool.weekly.rawValue) {
                    UsagePoolRow(
                        title: "Weekly",
                        percent: claudeService.weeklyPercent,
                        resetsAt: claudeService.weeklyResetsAt
                    )
                }

                if claudeService.hasSpend && claudeService.showsUsageBar(ClaudeUsagePool.usageLimit.rawValue) {
                    UsagePoolRow(
                        title: "General",
                        percent: UsageMath.percentUsed(
                            used: claudeService.spendUsedDollars,
                            limit: claudeService.spendLimitDollars
                        ),
                        detail: claudeService.detailText(for: .usageLimit)
                    )
                }

                if claudeService.hasCredit && claudeService.showsUsageBar(ClaudeUsagePool.credit.rawValue) {
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
