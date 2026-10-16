import Foundation

nonisolated protocol BrowserCookieReading: Sendable {
    func cookies(
        from browser: Browser,
        profile: URL?,
        matching filters: [CookieHarvest.DomainMatch],
        allowUserInteraction: Bool
    ) async throws(BrowserCookieError) -> [BrowserCookie]
}

extension BrowserCookieReading {
    nonisolated func cookies(
        from browser: Browser, profile: URL?, matching filters: [CookieHarvest.DomainMatch]
    ) async throws(BrowserCookieError) -> [BrowserCookie] {
        try await cookies(from: browser, profile: profile, matching: filters, allowUserInteraction: true)
    }
}

nonisolated struct LiveBrowserCookieReader: BrowserCookieReading {
    let home: URL

    init(home: URL = BrowserHome.current) {
        self.home = home
    }

    @concurrent
    func cookies(
        from browser: Browser,
        profile: URL?,
        matching filters: [CookieHarvest.DomainMatch],
        allowUserInteraction: Bool
    ) async throws(BrowserCookieError) -> [BrowserCookie] {
        switch browser.engine(home: home) {
        case let .gecko(profilesRoot):
            let applicationURL = await DefaultBrowser.applicationURL(for: browser)
            return try GeckoCookieStore(profilesRoot: profilesRoot).cookies(
                matching: filters, profile: profile, applicationURL: applicationURL
            )
        case let .chromium(userDataRoot, service, account):
            return try ChromiumCookieStore(
                userDataRoot: userDataRoot,
                safeStorageService: service,
                safeStorageAccount: account,
                allowUserInteraction: allowUserInteraction
            ).cookies(matching: filters, profile: profile)
        case let .webkit(cookieFile):
            guard FileManager.default.fileExists(atPath: cookieFile.path) else {
                throw .notInstalled
            }
            guard let data = try? Data(contentsOf: cookieFile) else {
                throw .accessDenied
            }
            let all = try SafariBinaryCookies.parse(data)
            guard !filters.isEmpty else { return all }
            return all.filter { cookie in filters.contains { $0.matches(cookie.domain) } }
        }
    }
}

nonisolated struct DisabledBrowserCookieReader: BrowserCookieReading {
    func cookies(
        from browser: Browser,
        profile: URL?,
        matching filters: [CookieHarvest.DomainMatch],
        allowUserInteraction: Bool
    ) async throws(BrowserCookieError) -> [BrowserCookie] {
        throw .notInstalled
    }
}
