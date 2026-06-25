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
}
