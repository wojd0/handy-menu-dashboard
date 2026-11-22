import Foundation

protocol PreferenceStoring {
    func object(forKey defaultName: String) -> Any?
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: PreferenceStoring {}

enum ProviderPreferences {
    static let claudeUsagePoolKey = "claudeMenuBarBaseline"
    static let antigravityUsagePoolKey = "antigravityMenuBarUsagePool"
    static let antigravityPoolRangeKey = "antigravityMenuBarPoolRange"

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

    static func claudeUsagePool(in store: any PreferenceStoring) -> ClaudeUsagePool {
        guard let rawValue = store.object(forKey: claudeUsagePoolKey) as? String,
              let usagePool = ClaudeUsagePool(rawValue: rawValue) else {
            return .usageLimit
        }
        return usagePool
    }

    static func setClaudeUsagePool(_ value: ClaudeUsagePool, in store: any PreferenceStoring) {
        store.set(value.rawValue, forKey: claudeUsagePoolKey)
    }

    static func antigravityUsagePool(in store: any PreferenceStoring) -> AntigravityUsagePool {
        guard let stored = store.object(forKey: antigravityUsagePoolKey) as? [String: Any],
              let name = stored["name"] as? String,
              let windowIDs = stored["windowIDs"] as? [String] else {
            return .mostUsed
        }
        return .group(name: name, windowIDs: windowIDs)
    }

    static func setAntigravityUsagePool(_ value: AntigravityUsagePool, in store: any PreferenceStoring) {
        switch value {
        case .mostUsed:
            store.set(nil, forKey: antigravityUsagePoolKey)
        case .group(let name, let windowIDs):
            store.set(["name": name, "windowIDs": windowIDs], forKey: antigravityUsagePoolKey)
        }
    }

    static func antigravityPoolRange(in store: any PreferenceStoring) -> AntigravityPoolRange {
        guard let period = store.object(forKey: antigravityPoolRangeKey) as? String else { return .mostUsed }
        return .period(period)
    }

    static func setAntigravityPoolRange(_ value: AntigravityPoolRange, in store: any PreferenceStoring) {
        switch value {
        case .mostUsed:
            store.set(nil, forKey: antigravityPoolRangeKey)
        case .period(let period):
            store.set(period, forKey: antigravityPoolRangeKey)
        }
    }
}
