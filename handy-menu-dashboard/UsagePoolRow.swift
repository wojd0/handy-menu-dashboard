import SwiftUI

struct UsagePoolRow: View {
    let title: String
    let percent: Double
    var detail: String?
    var resetsAt: Date?

    var body: some View {
        let isOverLimit = UsageMath.isOverLimit(percentUsed: percent)

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer()

                Text(UsageMath.menuBarPercentFragment(percent: percent))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isOverLimit ? .red : .primary)
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
