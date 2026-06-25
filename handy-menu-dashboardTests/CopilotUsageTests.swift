import Testing
@testable import handy_menu_dashboard

@Suite("Copilot usage")
struct CopilotUsageTests {
    @Test func percentUsedIsZeroWhenEntitlementIsZero() {
        #expect(UsageMath.copilotPercentUsed(totalUsed: 42, monthlyEntitlement: 0) == 0)
    }

    @Test func percentUsedReflectsRequestsAgainstEntitlement() {
        #expect(UsageMath.copilotPercentUsed(totalUsed: 150, monthlyEntitlement: 300) == 50)
    }

    @Test func isOverLimitWhenUsageExceedsEntitlement() {
        let percent = UsageMath.copilotPercentUsed(totalUsed: 350, monthlyEntitlement: 300)

        #expect(percent > 100)
        #expect(UsageMath.isOverLimit(percentUsed: percent))
    }

    @Test func menuBarFragmentIsEmptyWhenInactive() {
        let service = CopilotService(keychain: InMemoryKeychainStore())
        service.totalUsed = 120
        service.monthlyEntitlement = 300

        #expect(service.menuBarFragment == "")
    }

    @Test func menuBarFragmentShowsUsedAndEntitlementWhenActive() {
        let service = CopilotService(keychain: InMemoryKeychainStore())
        service.isAuthenticated = true
        service.isEnabled = true
        service.totalUsed = 275
        service.monthlyEntitlement = 300

        #expect(service.menuBarFragment == "275/300")
    }

    @Test func menuBarFragmentShowsOverLimitUsageWhenActive() {
        let service = CopilotService(keychain: InMemoryKeychainStore())
        service.isAuthenticated = true
        service.isEnabled = true
        service.totalUsed = 412
        service.monthlyEntitlement = 300

        #expect(service.menuBarFragment == "412/300")
    }
}
