import Foundation

enum UsageMath {
    static func formatCentsAsDollars(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        return String(format: "$%.2f", dollars)
    }

    static func spendPercentUsed(spendCents: Int, monthlyLimitDollars: Int) -> Double {
        guard monthlyLimitDollars > 0 else { return 0 }
        return Double(spendCents) / Double(monthlyLimitDollars * 100) * 100
    }

    static func cursorMenuBarFragment(spendCents: Int, monthlyLimitDollars: Int) -> String {
        let dollars = Int(Double(spendCents) / 100.0)
        return "$\(dollars)/\(monthlyLimitDollars)"
    }

    static func menuBarPercentFragment(percent: Double) -> String {
        "\(Int(percent.rounded()))%"
    }

    static func copilotPercentUsed(totalUsed: Int, monthlyEntitlement: Int) -> Double {
        monthlyEntitlement > 0 ? Double(totalUsed) / Double(monthlyEntitlement) * 100 : 0
    }

    static func isOverLimit(percentUsed: Double) -> Bool {
        percentUsed > 100
    }

    static func copilotMenuBarFragment(totalUsed: Int, monthlyEntitlement: Int) -> String {
        "\(totalUsed)/\(monthlyEntitlement)"
    }

    static func sumChargedCents(from events: [FilteredUsageEventsResponse.UsageEvent]) -> Int {
        let total = events.reduce(0.0) { $0 + ($1.chargedCents ?? 0) }
        return Int(total.rounded())
    }

    static func percentUsed(used: Double, limit: Double) -> Double {
        guard limit > 0 else { return 0 }
        return used / limit * 100
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

struct FilteredUsageEventsResponse: Decodable {
    let totalUsageEventsCount: Int
    let usageEventsDisplay: [UsageEvent]

    struct UsageEvent: Decodable {
        let chargedCents: Double?
    }
}

struct TeamSpendResponse: Decodable {
    let teamMemberSpend: [TeamMember]

    struct TeamMember: Decodable {
        let name: String?
        let email: String
        let userId: FlexibleInt?
        let id: FlexibleInt?
        let user_id: FlexibleInt?
        let spendCents: Int?
        let overallSpendCents: Int?
        let monthlyLimitDollars: Int?
        let effectivePerUserLimitDollars: Int?

        var resolvedUserId: Int? {
            userId?.value ?? id?.value ?? user_id?.value
        }
    }
}

struct FlexibleInt: Decodable {
    let value: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let stringValue = try? container.decode(String.self) {
            value = Int(stringValue)
        } else {
            value = nil
        }
    }
}
