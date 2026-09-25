import Foundation

enum BrowserCookieSource: Hashable {
    case automatic
    case browser(Browser)

    static let storageKey = "browserCookieSource"

    static func load(from store: any PreferenceStoring) -> BrowserCookieSource {
        guard let raw = store.object(forKey: storageKey) as? String else { return .automatic }
        if raw == "automatic" { return .automatic }
        if let browser = Browser(rawValue: raw) { return .browser(browser) }
        return .automatic
    }

    func save(to store: any PreferenceStoring) {
        switch self {
        case .automatic: store.set("automatic", forKey: Self.storageKey)
        case .browser(let browser): store.set(browser.rawValue, forKey: Self.storageKey)
        }
    }

    func resolved(defaultBrowser: @MainActor () -> Browser?) -> Browser? {
        switch self {
        case .automatic: defaultBrowser()
        case .browser(let browser): browser
        }
    }
}
