import Testing
@testable import handy_menu_dashboard

@Suite("Claude usage")
struct ClaudeUsageTests {

    func makeService(authenticated: Bool = false) -> ClaudeService {
        let service = ClaudeService(keychain: InMemoryKeychainStore())
        service.isAuthenticated = authenticated
        service.isEnabled = true
        return service
    }

    @Test func percentUsedForUsageLimitIsZeroWhenLimitIsZero() {
        let service = makeService()
        service.spendUsedDollars = 10
        service.spendLimitDollars = 0

        #expect(service.percentUsed(for: .usageLimit) == 0)
    }

    @Test func percentUsedForUsageLimitReflectsUsedAgainstLimit() {
        let service = makeService()
        service.spendUsedDollars = 25
        service.spendLimitDollars = 100

        #expect(service.percentUsed(for: .usageLimit) == 25)
    }

    @Test func percentUsedForCreditIsZeroWhenLimitIsZero() {
        let service = makeService()
        service.creditUsedDollars = 5
        service.creditLimitDollars = 0

        #expect(service.percentUsed(for: .credit) == 0)
    }

    @Test func percentUsedForCreditReflectsUsedAgainstLimit() {
        let service = makeService()
        service.creditUsedDollars = 10
        service.creditLimitDollars = 1000

        #expect(service.percentUsed(for: .credit) == 1)
    }

    @Test func percentUsedForCombinedSumsAllPools() {
        let service = makeService()
        service.spendUsedDollars = 2.39
        service.spendLimitDollars = 3000
        service.creditUsedDollars = 10.50
        service.creditLimitDollars = 1000

        let expected = UsageMath.percentUsed(used: 12.89, limit: 4000)
        #expect(abs(service.percentUsed(for: .combined) - expected) < 0.001)
    }

    @Test func percentUsedCanExceedOneHundredWhenOverLimit() {
        let service = makeService()
        service.spendUsedDollars = 150
        service.spendLimitDollars = 100

        #expect(service.percentUsed(for: .usageLimit) == 150)
    }

    @Test func menuBarFragmentIsEmptyWhenInactive() {
        let service = makeService(authenticated: false)
        service.spendUsedDollars = 50
        service.spendLimitDollars = 100

        #expect(service.menuBarFragment(baseline: .usageLimit, showPercent: false) == "")
    }

    @Test func menuBarFragmentDollarsUsageLimitShowsUsedOverLimit() {
        let service = makeService(authenticated: true)
        service.spendUsedDollars = 2.39
        service.spendLimitDollars = 3000

        #expect(service.menuBarFragment(baseline: .usageLimit, showPercent: false) == "$2/3000")
    }

    @Test func menuBarFragmentDollarsCreditShowsUsedOverLimit() {
        let service = makeService(authenticated: true)
        service.creditUsedDollars = 10.5
        service.creditLimitDollars = 1000

        #expect(service.menuBarFragment(baseline: .credit, showPercent: false) == "$10/1000")
    }

    @Test func menuBarFragmentDollarsCombinedShowsRemaining() {
        let service = makeService(authenticated: true)
        service.spendUsedDollars = 2.39
        service.spendLimitDollars = 3000
        service.creditUsedDollars = 10.5
        service.creditLimitDollars = 1000

        let remaining = (3000 + 1000) - (2.39 + 10.5)
        let expected = "$\(Int(remaining))"
        #expect(service.menuBarFragment(baseline: .combined, showPercent: false) == expected)
    }

    @Test func menuBarFragmentPercentRoundsToNearestInt() {
        let service = makeService(authenticated: true)
        service.spendUsedDollars = 1
        service.spendLimitDollars = 3

        let percent = service.menuBarFragment(baseline: .usageLimit, showPercent: true)
        #expect(percent == "33%")
    }

    @Test func detailTextForUsageLimitFormatsUsedAndLimit() {
        let service = makeService()
        service.spendUsedDollars = 2.39
        service.spendLimitDollars = 3000

        #expect(service.detailText(for: .usageLimit) == "$2.39 / $3000.00")
    }

    @Test func detailTextForCreditFormatsUsedAndLimit() {
        let service = makeService()
        service.creditUsedDollars = 10.498
        service.creditLimitDollars = 1000

        #expect(service.detailText(for: .credit) == "$10.50 / $1000.00")
    }

    @Test func detailTextForCombinedFormatsUsedAndLimit() {
        let service = makeService()
        service.spendUsedDollars = 2.39
        service.spendLimitDollars = 3000
        service.creditUsedDollars = 10.5
        service.creditLimitDollars = 1000

        #expect(service.detailText(for: .combined) == "$12.89 / $4000.00")
    }
}
