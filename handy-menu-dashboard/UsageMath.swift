import Foundation

enum UsageMath {
    static let infinitySymbol = "∞"

    static func menuBarPercentFragment(percent: Double, isUnlimited: Bool = false) -> String {
        if isUnlimited {
            return "\(infinitySymbol)%"
        }
        return "\(Int(percent.rounded()))%"
    }

    static func isOverLimit(percentUsed: Double) -> Bool {
        percentUsed > 100
    }

    static func percentUsed(used: Double, limit: Double) -> Double {
        guard limit > 0 else { return 0 }
        return used / limit * 100
    }

    static func percentRemaining(used: Double, limit: Double) -> Double {
        guard limit > 0 else { return 0 }
        return 100 - percentUsed(used: used, limit: limit)
    }

    static func resetText(for date: Date, now: Date = Date()) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "Resets now" }

        let sixHours: TimeInterval = 6 * 3600
        if seconds < sixHours {
            let totalMinutes = max(1, Int(seconds / 60))
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            switch (hours, minutes) {
            case (0, _): return "Resets in \(minutes)m"
            case (_, 0): return "Resets in \(hours)h"
            default: return "Resets in \(hours)h \(minutes)m"
            }
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return "Resets " + formatter.localizedString(for: date, relativeTo: now)
    }

    static func dollars(amountMinor: Int, exponent: Int) -> Double {
        Double(amountMinor) / pow(10.0, Double(exponent))
    }

    static func formatDollars(_ value: Double) -> String {
        String(format: "$%.2f", value)
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

    struct Window: Decodable {
        let utilization: Double?
        let resetsAt: String?
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init(_ stringValue: String) { self.stringValue = stringValue }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    let spend: Spend?
    let creditPool: CreditPool?
    let fiveHour: Window?
    let sevenDay: Window?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        spend = try container.decodeIfPresent(Spend.self, forKey: AnyKey("spend"))
        fiveHour = try container.decodeIfPresent(Window.self, forKey: AnyKey("fiveHour"))
        sevenDay = try container.decodeIfPresent(Window.self, forKey: AnyKey("sevenDay"))

        if let known = try container.decodeIfPresent(CreditPool.self, forKey: AnyKey("cinderCove")) {
            creditPool = known
        } else {
            let others = container.allKeys.sorted { $0.stringValue < $1.stringValue }
            creditPool = others
                .compactMap { try? container.decode(CreditPool.self, forKey: $0) }
                .first { $0.limitDollars != nil }
        }
    }
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
