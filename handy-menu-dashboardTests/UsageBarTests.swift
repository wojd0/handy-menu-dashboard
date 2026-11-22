import Foundation
import Testing
@testable import handy_menu_dashboard

@Suite("Usage bars")
struct UsageBarTests {
    @Test func hiddenUsageBarsKeysAreDerivedFromTheProvider() {
        let keys = Provider.allCases.map(\.hiddenUsageBarsKey)

        #expect(keys == [
            "cursorHiddenUsageBars",
            "copilotHiddenUsageBars",
            "claudeHiddenUsageBars",
            "chatgptHiddenUsageBars",
            "antigravityHiddenUsageBars"
        ])
    }

    @Test func everyUsageBarIsShownByDefault() {
        let service = CursorService(
            keychain: InMemoryKeychainStore(),
            autoRefresh: false,
            preferences: InMemoryPreferenceStore()
        )

        #expect(service.usageBars == [.primary])
        #expect(service.hiddenUsageBars.isEmpty)
        #expect(service.showsAnyUsageBar)
    }

    @Test func aHiddenUsageBarIsPersistedAndRestored() {
        let preferences = InMemoryPreferenceStore()
        let session = UsageSession(provider: .claude, keychain: InMemoryKeychainStore(), preferences: preferences)

        session.hiddenUsageBars = ["weekly", "credit"]

        #expect(preferences.object(forKey: "claudeHiddenUsageBars") as? [String] == ["credit", "weekly"])
        let restored = UsageSession(provider: .claude, keychain: InMemoryKeychainStore(), preferences: preferences)
        #expect(restored.hiddenUsageBars == ["weekly", "credit"])

        restored.hiddenUsageBars = []
        #expect(preferences.object(forKey: "claudeHiddenUsageBars") == nil)
    }

    @Test func hidingTheOnlyUsageBarHidesTheProvider() {
        let service = CopilotService(
            keychain: InMemoryKeychainStore(),
            autoRefresh: false,
            preferences: InMemoryPreferenceStore()
        )

        service.setUsageBar(UsageBar.primary.id, shown: false)
        #expect(service.showsAnyUsageBar == false)

        service.setUsageBar(UsageBar.primary.id, shown: true)
        #expect(service.showsAnyUsageBar)
    }

    @Test func claudeListsOnlyThePoolsInThePayload() {
        let service = ClaudeService(
            keychain: InMemoryKeychainStore(),
            autoRefresh: false,
            preferences: InMemoryPreferenceStore()
        )

        #expect(service.usageBars.isEmpty)
        #expect(service.showsAnyUsageBar)

        service.hasSession = true
        service.hasCredit = true

        #expect(service.usageBars.map(\.id) == ["session", "credit"])
        #expect(service.usageBars.map(\.title) == ["Session (5h)", "Credit"])
    }
}
