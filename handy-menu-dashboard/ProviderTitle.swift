import SwiftUI

struct ProviderTitle: View {
    let provider: Provider

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(provider.accentColor)
                .frame(width: 8, height: 8)
                .overlay {
                    if provider.accentNeedsOutline {
                        Circle()
                            .strokeBorder(.primary.opacity(0.35), lineWidth: 1)
                    }
                }
                .accessibilityHidden(true)

            Text(provider.displayName)
                .font(.headline)
        }
    }
}
