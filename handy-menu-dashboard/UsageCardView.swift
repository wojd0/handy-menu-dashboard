import SwiftUI

struct UsageCardView: View {
    let serviceName: String
    let percentUsed: Double
    let detailText: String
    let subtitle: String?
    let isOverLimit: Bool
    let isLoading: Bool
    let error: String?
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(serviceName)
                    .font(.headline)

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                } else {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(percentUsed))%")
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
                    .foregroundStyle(.secondary)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                UsageProgressBar(percentage: percentUsed, isOverLimit: isOverLimit)
            }
        }
    }
}
