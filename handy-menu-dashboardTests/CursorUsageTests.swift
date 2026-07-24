import Testing
@testable import handy_menu_dashboard

@Suite("Cursor usage")
struct CursorUsageTests {
    @Test func spendFormattedFormatsCentsWithTwoDecimals() {
        let service = CursorService(keychain: InMemoryKeychainStore())
        service.spendCents = 12_345

        #expect(service.spendFormatted == "$123.45")
    }

    @Test func spendPercentUsedIsZeroWhenMonthlyLimitIsZero() {
        let service = CursorService(keychain: InMemoryKeychainStore())
        service.spendCents = 9_999
        service.monthlyLimitDollars = 0

        #expect(service.spendPercentUsed == 0)
    }

    @Test func spendPercentUsedReflectsSpendAgainstLimit() {
        let service = CursorService(keychain: InMemoryKeychainStore())
        service.spendCents = 5_000
        service.monthlyLimitDollars = 100

        #expect(service.spendPercentUsed == 50)
    }

    @Test func spendPercentUsedCanExceedOneHundredWhenOverLimit() {
        let service = CursorService(keychain: InMemoryKeychainStore())
        service.spendCents = 15_000
        service.monthlyLimitDollars = 100

        #expect(service.spendPercentUsed == 150)
    }

    @Test func spendPercentRemainingReflectsAvailableAndOverLimitAmounts() {
        let service = CursorService(keychain: InMemoryKeychainStore())
        service.monthlyLimitDollars = 100

        service.spendCents = 25_000
        #expect(service.spendPercentRemaining == -150)

        service.spendCents = 2_500
        #expect(service.spendPercentRemaining == 75)
    }

    @Test func spendPercentRemainingIsZeroWhenMonthlyLimitIsZero() {
        let service = CursorService(keychain: InMemoryKeychainStore())
        service.spendCents = 2_500

        #expect(service.spendPercentRemaining == 0)
    }

    @Test func menuBarFragmentIsEmptyWhenInactive() {
        let service = CursorService(keychain: InMemoryKeychainStore())
        service.spendCents = 5_000
        service.monthlyLimitDollars = 100

        #expect(service.menuBarFragment == "")
    }

    @Test func menuBarFragmentShowsTruncatedDollarsOverLimit() {
        let service = CursorService(keychain: InMemoryKeychainStore())
        service.isAuthenticated = true
        service.isEnabled = true
        service.spendCents = 15_050
        service.monthlyLimitDollars = 100

        #expect(service.menuBarFragment == "$150/100")
    }

    @Test func menuBarFragmentShowsSpendAndLimitWhenActive() {
        let service = CursorService(keychain: InMemoryKeychainStore())
        service.isAuthenticated = true
        service.isEnabled = true
        service.spendCents = 4_999
        service.monthlyLimitDollars = 50

        #expect(service.menuBarFragment == "$49/50")
    }

    @Test func menuBarFragmentSupportsAllDisplayModes() {
        let service = CursorService(keychain: InMemoryKeychainStore())
        service.isAuthenticated = true
        service.isEnabled = true
        service.spendCents = 12_500
        service.monthlyLimitDollars = 100

        #expect(service.menuBarFragment(displayMode: .monetary) == "$125/100")
        #expect(service.menuBarFragment(displayMode: .percentUsed) == "125%")
        #expect(service.menuBarFragment(displayMode: .percentRemaining) == "-25%")
    }
}
