import Foundation
import Testing
@testable import handy_menu_dashboard

@Suite("Provider preferences")
struct ProviderPreferencesTests {
    @Test func enabledKeysMatchTheKeysShippedBeforeTheyWereDerived() {
        let keys = Provider.allCases.map(\.enabledKey)

        #expect(keys == ["cursorEnabled", "copilotEnabled", "claudeEnabled", "chatgptEnabled"])
    }

    @Test func displayModeKeysMatchTheKeysShippedBeforeTheyWereDerived() {
        let keys = Provider.allCases.map(\.displayModeKey)

        #expect(keys == [
            "cursorMenuBarShowPercent",
            "copilotMenuBarShowPercent",
            "claudeMenuBarShowPercent",
            "chatgptMenuBarShowPercent"
        ])
    }

    @Test func claudeUsagePoolKeyIsUnchanged() {
        #expect(ProviderPreferences.claudeUsagePoolKey == "claudeMenuBarBaseline")
    }

    @Test func providersAreDisabledUntilTurnedOn() {
        let store = InMemoryPreferenceStore()

        #expect(ProviderPreferences.isEnabled(.cursor, in: store) == false)
        #expect(ProviderPreferences.hasEnabledChoice(.cursor, in: store) == false)

        ProviderPreferences.setEnabled(true, for: .cursor, in: store)

        #expect(ProviderPreferences.isEnabled(.cursor, in: store))
        #expect(ProviderPreferences.hasEnabledChoice(.cursor, in: store))
        #expect(ProviderPreferences.isEnabled(.claude, in: store) == false)
    }

    @Test func displayModeRoundTripsPerProvider() {
        let store = InMemoryPreferenceStore()

        ProviderPreferences.setDisplayMode(.percentRemaining, for: .copilot, in: store)

        #expect(ProviderPreferences.displayMode(for: .copilot, in: store) == .percentRemaining)
        #expect(ProviderPreferences.displayMode(for: .cursor, in: store) == .monetary)
    }

    @Test func aLegacyBooleanDisplayModeIsStillReadable() {
        let store = InMemoryPreferenceStore([
            Provider.cursor.displayModeKey: true,
            Provider.claude.displayModeKey: false
        ])

        #expect(ProviderPreferences.displayMode(for: .cursor, in: store) == .percentUsed)
        #expect(ProviderPreferences.displayMode(for: .claude, in: store) == .monetary)
    }

    @Test func claudeUsagePoolRoundTrips() {
        let store = InMemoryPreferenceStore()

        #expect(ProviderPreferences.claudeUsagePool(in: store) == .usageLimit)

        ProviderPreferences.setClaudeUsagePool(.combined, in: store)

        #expect(ProviderPreferences.claudeUsagePool(in: store) == .combined)
    }

    @Test func theSessionPersistsWhatTheToggleSets() {
        let store = InMemoryPreferenceStore()
        let service = CursorService(
            keychain: InMemoryKeychainStore(),
            autoRefresh: false,
            preferences: store
        )

        service.isEnabled = false
        service.menuBarDisplayMode = .percentUsed

        #expect(store.object(forKey: "cursorEnabled") as? Bool == false)
        #expect(store.object(forKey: "cursorMenuBarShowPercent") as? String == "percentUsed")
    }

    @Test func aServiceStartsFromWhatWasStored() {
        let store = InMemoryPreferenceStore([
            "cursorEnabled": false,
            "cursorMenuBarShowPercent": "percentRemaining"
        ])

        let service = CursorService(
            keychain: InMemoryKeychainStore(),
            autoRefresh: false,
            preferences: store
        )

        #expect(service.isEnabled == false)
        #expect(service.menuBarDisplayMode == .percentRemaining)
    }

    @Test func claudeStartsFromTheStoredUsagePool() {
        let store = InMemoryPreferenceStore(["claudeMenuBarBaseline": "credit"])

        let service = ClaudeService(
            keychain: InMemoryKeychainStore(),
            autoRefresh: false,
            preferences: store
        )

        #expect(service.usagePool == .credit)
    }
}
