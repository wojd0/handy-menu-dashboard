import Foundation
import Testing
@testable import handy_menu_dashboard

@Suite("Claude usage pool selection")
struct ClaudeUsagePoolTests {
    @Test(arguments: ClaudeUsagePool.allCases, [ClaudeUsagePool.usageLimit, .credit, .session, .weekly])
    func menuBarUsesTheOnlyAvailablePool(savedPool: ClaudeUsagePool, availablePool: ClaudeUsagePool) async {
        let preferences = InMemoryPreferenceStore([
            "claudeMenuBarBaseline": savedPool.rawValue,
            "claudeMenuBarShowPercent": "percentUsed"
        ])
        let keychain = InMemoryKeychainStore()
        keychain.saveString(key: .claudeCookies, value: "sessionKey=test; lastActiveOrg=test-org")
        let service = ClaudeService(
            keychain: keychain,
            dataLoader: { request in
                try httpResponse(for: request, json: self.payload(for: availablePool))
            },
            autoRefresh: false,
            preferences: preferences
        )

        await service.refresh()

        #expect(service.error == nil)
        #expect(service.availableUsagePools == [availablePool])
        #expect(service.resolvedUsagePool == availablePool)
        #expect(service.menuBarText == "17%")
        #expect(abs(service.reading.percentUsed - 16.84) < 0.001)
        #expect(service.usagePool == savedPool)
        #expect(ProviderPreferences.claudeUsagePool(in: preferences) == savedPool)

        service.menuBarDisplayMode = .percentRemaining
        #expect(service.menuBarText == "83%")
    }

    @Test func menuBarReturnsToChosenPoolWhenItBecomesAvailableAgain() async {
        var payload = payload(for: .usageLimit)
        let keychain = InMemoryKeychainStore()
        keychain.saveString(key: .claudeCookies, value: "sessionKey=test; lastActiveOrg=test-org")
        let service = ClaudeService(
            keychain: keychain,
            dataLoader: { request in try httpResponse(for: request, json: payload) },
            autoRefresh: false,
            preferences: InMemoryPreferenceStore(["claudeMenuBarBaseline": "credit"])
        )
        service.menuBarDisplayMode = .percentUsed

        await service.refresh()
        #expect(service.resolvedUsagePool == .usageLimit)
        #expect(service.menuBarText == "17%")

        payload["cinder_cove"] = ["used_dollars": 40, "limit_dollars": 100]
        await service.refresh()

        #expect(service.resolvedUsagePool == .credit)
        #expect(service.menuBarText == "40%")
    }

    @Test func fallbackKeepsWindowPriorityBeforeDollarPools() {
        let service = ClaudeService(
            keychain: InMemoryKeychainStore(),
            autoRefresh: false,
            preferences: InMemoryPreferenceStore(["claudeMenuBarBaseline": "combined"])
        )
        service.hasSession = true
        service.hasWeekly = true
        service.hasCredit = true

        #expect(service.resolvedUsagePool == .session)

        service.hasSession = false
        #expect(service.resolvedUsagePool == .weekly)

        service.hasWeekly = false
        #expect(service.resolvedUsagePool == .credit)

        service.hasCredit = false
        #expect(service.resolvedUsagePool == .combined)
    }

    private func payload(for pool: ClaudeUsagePool) -> [String: Any] {
        switch pool {
        case .usageLimit, .combined:
            ["spend": [
                "used": ["amount_minor": 8420, "exponent": 2],
                "limit": ["amount_minor": 50000, "exponent": 2],
                "enabled": true
            ]]
        case .credit:
            ["cinder_cove": ["used_dollars": 84.2, "limit_dollars": 500]]
        case .session:
            ["five_hour": ["utilization": 16.84]]
        case .weekly:
            ["seven_day": ["utilization": 16.84]]
        }
    }
}
