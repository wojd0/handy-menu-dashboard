import Foundation

protocol PreferenceStoring {
    func object(forKey defaultName: String) -> Any?
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: PreferenceStoring {}

enum ProviderPreferences {
    static let claudeBaselineKey = "claudeMenuBarBaseline"

    static func isEnabled(_ provider: Provider, in store: any PreferenceStoring) -> Bool {
        (store.object(forKey: provider.enabledKey) as? Bool) ?? false
    }

    static func hasEnabledChoice(_ provider: Provider, in store: any PreferenceStoring) -> Bool {
        store.object(forKey: provider.enabledKey) is Bool
    }

    static func setEnabled(_ value: Bool, for provider: Provider, in store: any PreferenceStoring) {
        store.set(value, forKey: provider.enabledKey)
    }

    static func displayMode(for provider: Provider, in store: any PreferenceStoring) -> MenuBarDisplayMode {
        let stored = store.object(forKey: provider.displayModeKey)
        if let rawValue = stored as? String, let mode = MenuBarDisplayMode(rawValue: rawValue) {
            return mode
        }
        if let showedPercent = stored as? Bool {
            return showedPercent ? .percentUsed : .monetary
        }
        return .monetary
    }

    static func setDisplayMode(
        _ value: MenuBarDisplayMode,
        for provider: Provider,
        in store: any PreferenceStoring
    ) {
        store.set(value.rawValue, forKey: provider.displayModeKey)
    }

    static func claudeBaseline(in store: any PreferenceStoring) -> ClaudeBaseline {
        guard let rawValue = store.object(forKey: claudeBaselineKey) as? String,
              let baseline = ClaudeBaseline(rawValue: rawValue) else {
            return .usageLimit
        }
        return baseline
    }

    static func setClaudeBaseline(_ value: ClaudeBaseline, in store: any PreferenceStoring) {
        store.set(value.rawValue, forKey: claudeBaselineKey)
    }
}
