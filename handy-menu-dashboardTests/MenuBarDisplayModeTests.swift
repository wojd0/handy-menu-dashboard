import Foundation
import Testing
@testable import handy_menu_dashboard

@Suite("Menu bar display mode")
struct MenuBarDisplayModeTests {
    @Test func migratesLegacyPercentPreferenceToPercentUsed() {
        withDefaults { defaults in
            defaults.set(true, forKey: "cursorMenuBarShowPercent")

            MenuBarDisplayMode.migrateLegacyPreferences(in: defaults)

            #expect(defaults.string(forKey: "cursorMenuBarShowPercent") == "percentUsed")
        }
    }

    @Test func migratesLegacyMonetaryPreferenceToMonetary() {
        withDefaults { defaults in
            defaults.set(false, forKey: "chatgptMenuBarShowPercent")

            MenuBarDisplayMode.migrateLegacyPreferences(in: defaults)

            #expect(defaults.string(forKey: "chatgptMenuBarShowPercent") == "monetary")
        }
    }

    @Test func preservesValidDisplayModeAndRepairsMalformedValue() {
        withDefaults { defaults in
            defaults.set("percentRemaining", forKey: "claudeMenuBarShowPercent")
            defaults.set("unexpected", forKey: "copilotMenuBarShowPercent")

            MenuBarDisplayMode.migrateLegacyPreferences(in: defaults)

            #expect(defaults.string(forKey: "claudeMenuBarShowPercent") == "percentRemaining")
            #expect(defaults.string(forKey: "copilotMenuBarShowPercent") == "monetary")
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "MenuBarDisplayModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }
}
