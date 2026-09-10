import Testing
@testable import handy_menu_dashboard

@Suite("Usage reading")
struct UsageReadingTests {
    @Test func percentRemainingIsAlwaysTheComplementOfPercentUsed() {
        let underLimit = makeReading(used: 25, limit: 100)
        let overLimit = makeReading(used: 125, limit: 100)

        #expect(underLimit.percentRemaining == 75)
        #expect(overLimit.percentRemaining == -25)
        #expect(overLimit.percentUsed + overLimit.percentRemaining == 100)
    }

    @Test func percentsAreZeroWithoutALimit() {
        let reading = makeReading(used: 10, limit: 0)

        #expect(reading.percentUsed == 0)
        #expect(reading.percentRemaining == 0)
    }

    @Test func overLimitIsSuppressedForUnlimitedAccounts() {
        let limited = makeReading(used: 125, limit: 100)
        let unlimited = makeReading(used: 125, limit: 100, isUnlimited: true)

        #expect(limited.isOverLimit)
        #expect(unlimited.isOverLimit == false)
    }

    @Test func wholeDollarsTruncatesTowardsZero() {
        #expect(makeReading(used: 150.5, limit: 100).menuBarText(.monetary) == "$150/100")
        #expect(makeReading(used: 49.99, limit: 50).menuBarText(.monetary) == "$49/50")
        #expect(makeReading(used: 12.89, limit: 4000).menuBarText(.monetary) == "$12/4000")
    }

    @Test func unlimitedRendersInfinityInEveryMode() {
        let reading = makeReading(used: 150, limit: 100, isUnlimited: true)

        #expect(reading.menuBarText(.monetary) == "$150/∞")
        #expect(reading.menuBarText(.percentUsed) == "∞%")
        #expect(reading.menuBarText(.percentRemaining) == "∞%")
    }

    @Test func creditStylesRenderTheirOwnScale() {
        let abbreviated = makeReading(used: 5_343, limit: 350_000, amountStyle: .abbreviatedCredits)
        let compact = makeReading(used: 10_000, limit: 40_000, amountStyle: .compactCredits)

        #expect(abbreviated.menuBarText(.monetary) == "5.3K/350K")
        #expect(compact.menuBarText(.monetary) == "10000/40000")
    }

    @Test func percentModesRoundToTheNearestWholeNumber() {
        let reading = makeReading(used: 1, limit: 3)

        #expect(reading.menuBarText(.percentUsed) == "33%")
        #expect(reading.menuBarText(.percentRemaining) == "67%")
    }

    @Test func detailStylesRenderTheirOwnUnits() {
        let cursor = makeReading(used: 123.45, limit: 100, detailStyle: .dollarsWholeLimit)
        let claude = makeReading(used: 2.39, limit: 3000, detailStyle: .dollars)
        let credits = makeReading(used: 5_343, limit: 350_000, detailStyle: .credits)

        #expect(cursor.detailText == "$123.45 / $100")
        #expect(claude.detailText == "$2.39 / $3000.00")
        #expect(credits.detailText == "5,343 / 350,000 credits")
    }

    @Test func unlimitedDetailTextDropsTheLimit() {
        let cursor = makeReading(used: 123.45, limit: 100, isUnlimited: true, detailStyle: .dollarsWholeLimit)
        let credits = makeReading(used: 42, limit: 0, isUnlimited: true, detailStyle: .credits)

        #expect(cursor.detailText == "$123.45 / ∞")
        #expect(credits.detailText == "42 / ∞ credits")
    }

    private func makeReading(
        used: Double,
        limit: Double,
        isUnlimited: Bool = false,
        amountStyle: AmountStyle = .wholeDollars,
        detailStyle: DetailStyle = .dollars
    ) -> UsageReading {
        UsageReading(
            used: used,
            limit: limit,
            isUnlimited: isUnlimited,
            amountStyle: amountStyle,
            detailStyle: detailStyle
        )
    }
}
