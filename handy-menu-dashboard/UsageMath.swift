import Foundation

enum UsageMath {
    static let infinitySymbol = "∞"

    static func formatCentsAsDollars(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        return String(format: "$%.2f", dollars)
    }

    static func spendPercentUsed(spendCents: Int, monthlyLimitDollars: Int) -> Double {
        guard monthlyLimitDollars > 0 else { return 0 }
        return Double(spendCents) / Double(monthlyLimitDollars * 100) * 100
    }

    static func cursorMenuBarFragment(
        spendCents: Int,
        monthlyLimitDollars: Int,
        isUnlimited: Bool = false
    ) -> String {
        let dollars = Int(Double(spendCents) / 100.0)
        let limit = isUnlimited ? infinitySymbol : "\(monthlyLimitDollars)"
        return "$\(dollars)/\(limit)"
    }

    static func menuBarPercentFragment(percent: Double, isUnlimited: Bool = false) -> String {
        if isUnlimited {
            return "\(infinitySymbol)%"
        }
        return "\(Int(percent.rounded()))%"
    }

    static func isOverLimit(percentUsed: Double) -> Bool {
        percentUsed > 100
    }

    static func copilotCreditsFragment(used: Double, total: Double, isUnlimited: Bool = false) -> String {
        let totalText = isUnlimited ? infinitySymbol : formatAbbreviatedCredits(total)
        return "\(formatAbbreviatedCredits(used))/\(totalText)"
    }

    static func percentUsed(used: Double, limit: Double) -> Double {
        guard limit > 0 else { return 0 }
        return used / limit * 100
    }

    static func percentRemaining(used: Double, limit: Double) -> Double {
        guard limit > 0 else { return 0 }
        return 100 - percentUsed(used: used, limit: limit)
    }

    static func dollars(amountMinor: Int, exponent: Int) -> Double {
        Double(amountMinor) / pow(10.0, Double(exponent))
    }

    static func formatDollars(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    static func claudeDollarsFragment(used: Double, limit: Double) -> String {
        "$\(Int(used))/\(Int(limit))"
    }

    static func chatGPTCreditsFragment(used: Double, limit: Double) -> String {
        "\(formatCompactNumber(used))/\(formatCompactNumber(limit))"
    }

    static func formatCredits(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: value)) ?? formatCompactNumber(value)
    }

    static func formatCompactNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }

    static func formatAbbreviatedCredits(_ value: Double) -> String {
        let absoluteValue = abs(value)
        let divisor: Double
        let suffix: String

        switch absoluteValue {
        case 1_000_000_000...:
            divisor = 1_000_000_000
            suffix = "B"
        case 1_000_000...:
            divisor = 1_000_000
            suffix = "M"
        case 1_000...:
            divisor = 1_000
            suffix = "K"
        default:
            return formatCompactNumber(value)
        }

        let scaled = value / divisor
        let formatted = String(format: "%.1f", scaled)
            .replacingOccurrences(of: "\\.0$", with: "", options: .regularExpression)
        return "\(formatted)\(suffix)"
    }
}

struct CopilotEntitlementResponse: Decodable {
    struct Quotas: Decodable {
        struct Remaining: Decodable {
            let premiumInteractions: Double?
        }

        struct PremiumInteractionsQuota: Decodable {
            let total: Double
            let used: Double
            let hasQuota: Bool?
            let unlimited: Bool?
        }

        let remaining: Remaining?
        let premiumInteractionsQuota: PremiumInteractionsQuota?
    }

    let quotas: Quotas
}

struct ClaudeUsageResponse: Decodable {
    struct Money: Decodable {
        let amountMinor: Int
        let exponent: Int
    }

    struct Spend: Decodable {
        let used: Money?
        let limit: Money?
        let enabled: Bool?
    }

    struct CreditPool: Decodable {
        let utilization: Double?
        let limitDollars: Double?
        let usedDollars: Double?
        let remainingDollars: Double?
        let resetsAt: String?
    }

    let spend: Spend?
    let cinderCove: CreditPool?
}

struct CursorUsageSummaryResponse: Decodable {
    struct UsagePool: Decodable {
        let enabled: Bool?
        let used: Int?
        let limit: Int?
        let remaining: Int?
    }

    struct IndividualUsage: Decodable {
        let overall: UsagePool?
    }

    let isUnlimited: Bool?
    let individualUsage: IndividualUsage?
}

struct ChatGPTUsageResponse: Decodable {
    struct EffectiveMonthlyLimit: Decodable {
        let limit: Double
        let enforcementMode: String?
        let limitMode: String?
    }

    let effectiveMonthlyLimit: EffectiveMonthlyLimit
    let currentMonthUsage: Double
}
