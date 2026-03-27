import SwiftUI

struct UsageProgressBar: View {
    let percentage: Double
    let isOverLimit: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)

                Capsule()
                    .fill(barGradient)
                    .frame(width: max(0, min(percentage / 100, 1.0)) * geometry.size.width)
            }
        }
        .frame(height: 8)
    }

    private var barGradient: some ShapeStyle {
        if isOverLimit {
            return AnyShapeStyle(Color.red)
        }
        if percentage > 90 {
            return AnyShapeStyle(LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing))
        }
        if percentage > 75 {
            return AnyShapeStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing))
        }
        if percentage > 50 {
            return AnyShapeStyle(LinearGradient(colors: [.green, .yellow], startPoint: .leading, endPoint: .trailing))
        }
        return AnyShapeStyle(LinearGradient(colors: [.green, .green], startPoint: .leading, endPoint: .trailing))
    }
}
