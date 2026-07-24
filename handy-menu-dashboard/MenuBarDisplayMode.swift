import Foundation

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case monetary
    case percentUsed
    case percentRemaining

    var id: String { rawValue }

    static let preferenceKeys = [
        "cursorMenuBarShowPercent",
        "copilotMenuBarShowPercent",
        "claudeMenuBarShowPercent",
        "chatgptMenuBarShowPercent"
    ]

    static func migrateLegacyPreferences(in defaults: UserDefaults = .standard) {
        for key in preferenceKeys {
            guard let storedValue = defaults.object(forKey: key) else { continue }

            if let rawValue = storedValue as? String,
               MenuBarDisplayMode(rawValue: rawValue) != nil {
                continue
            }

            if let showedPercent = storedValue as? Bool {
                defaults.set(
                    showedPercent ? MenuBarDisplayMode.percentUsed.rawValue : MenuBarDisplayMode.monetary.rawValue,
                    forKey: key
                )
            } else {
                defaults.set(MenuBarDisplayMode.monetary.rawValue, forKey: key)
            }
        }
    }
}
