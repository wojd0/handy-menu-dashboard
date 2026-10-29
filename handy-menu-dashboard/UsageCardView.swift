import SwiftUI

struct UsageCardView: View {
    let provider: Provider
    let percentUsed: Double
    let detailText: String
    let subtitle: String?
    let isOverLimit: Bool
    var isUnlimited = false
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProviderTitle(provider: provider)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(isUnlimited ? "\(UsageMath.infinitySymbol)%" : "\(Int(percentUsed))%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isOverLimit ? .red : .primary)

                    if isOverLimit {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Text(detailText)
                    .font(.callout)
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if !isUnlimited {
                    UsageProgressBar(percentage: percentUsed, isOverLimit: isOverLimit)
                }
            }
        }
    }
}
