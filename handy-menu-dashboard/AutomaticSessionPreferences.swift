import Foundation

enum AutomaticSessionPreferences {
    static let providersKey = "automaticSessionUpdateProviders"
    static let enabledKey = "automaticSessionUpdatesEnabled"

    static func providers(in store: any PreferenceStoring) -> Set<Provider> {
        let rawValues = store.object(forKey: providersKey) as? [String] ?? []
        return Set(rawValues.compactMap(Provider.init(rawValue:)))
    }

    static func setProviders(_ providers: Set<Provider>, in store: any PreferenceStoring) {
        store.set(Provider.allCases.filter { providers.contains($0) }.map(\.rawValue), forKey: providersKey)
    }

    static func profile(for browser: Browser, provider: Provider? = nil, in store: any PreferenceStoring) -> URL? {
        if let bookmark = store.object(forKey: bookmarkKey(browser, provider)) as? Data {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                bookmarkDataIsStale: &isStale
            ) {
                return url
            }
        }
        guard let path = store.object(forKey: profileKey(browser, provider)) as? String else { return nil }
        return URL(fileURLWithPath: path)
    }

    static func setProfile(_ profile: URL?, for browser: Browser, provider: Provider? = nil, in store: any PreferenceStoring) {
        store.set(profile?.path, forKey: profileKey(browser, provider))
        let bookmark = try? profile?.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess])
        store.set(bookmark, forKey: bookmarkKey(browser, provider))
    }

    private static func profileKey(_ browser: Browser, _ provider: Provider?) -> String {
        "automaticSessionProfile.\(browser.rawValue).\(provider?.rawValue ?? "selected")"
    }

    private static func bookmarkKey(_ browser: Browser, _ provider: Provider?) -> String {
        "automaticSessionProfileBookmark.\(browser.rawValue).\(provider?.rawValue ?? "selected")"
    }
}
