import Foundation

enum AmountStyle {
    case wholeDollars
    case abbreviatedCredits
    case compactCredits

    func text(used: Double, limit: Double, isUnlimited: Bool) -> String {
        switch self {
        case .wholeDollars:
            "$\(Int(used))/" + (isUnlimited ? UsageMath.infinitySymbol : String(Int(limit)))
        case .abbreviatedCredits:
            "\(UsageMath.formatAbbreviatedCredits(used))/"
                + (isUnlimited ? UsageMath.infinitySymbol : UsageMath.formatAbbreviatedCredits(limit))
        case .compactCredits:
            "\(UsageMath.formatCompactNumber(used))/"
                + (isUnlimited ? UsageMath.infinitySymbol : UsageMath.formatCompactNumber(limit))
        }
    }
}

enum DetailStyle {
    case dollarsWholeLimit
    case dollars
    case credits

    func text(used: Double, limit: Double, isUnlimited: Bool) -> String {
        switch self {
        case .dollarsWholeLimit:
            "\(UsageMath.formatDollars(used)) / " + (isUnlimited ? UsageMath.infinitySymbol : "$\(Int(limit))")
        case .dollars:
            "\(UsageMath.formatDollars(used)) / \(UsageMath.formatDollars(limit))"
        case .credits:
            "\(UsageMath.formatCredits(used)) / "
                + (isUnlimited ? UsageMath.infinitySymbol : UsageMath.formatCredits(limit))
                + " credits"
        }
    }
}

struct UsageReading: Equatable {
    var used: Double
    var limit: Double
    var isUnlimited: Bool
    var amountStyle: AmountStyle
    var detailStyle: DetailStyle

    init(
        used: Double,
        limit: Double,
        isUnlimited: Bool = false,
        amountStyle: AmountStyle,
        detailStyle: DetailStyle
    ) {
        self.used = used
        self.limit = limit
        self.isUnlimited = isUnlimited
        self.amountStyle = amountStyle
        self.detailStyle = detailStyle
    }

    var percentUsed: Double {
        UsageMath.percentUsed(used: used, limit: limit)
    }

    var percentRemaining: Double {
        UsageMath.percentRemaining(used: used, limit: limit)
    }

    var isOverLimit: Bool {
        !isUnlimited && UsageMath.isOverLimit(percentUsed: percentUsed)
    }

    var detailText: String {
        detailStyle.text(used: used, limit: limit, isUnlimited: isUnlimited)
    }

    func menuBarText(_ mode: MenuBarDisplayMode) -> String {
        switch mode {
        case .monetary:
            amountStyle.text(used: used, limit: limit, isUnlimited: isUnlimited)
        case .percentUsed:
            UsageMath.menuBarPercentFragment(percent: percentUsed, isUnlimited: isUnlimited)
        case .percentRemaining:
            UsageMath.menuBarPercentFragment(percent: percentRemaining, isUnlimited: isUnlimited)
        }
    }
}
