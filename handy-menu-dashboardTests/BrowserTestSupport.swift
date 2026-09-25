import Foundation
@testable import handy_menu_dashboard

final class FakeBrowserCookieReader: BrowserCookieReading, @unchecked Sendable {
    private let cookies: [BrowserCookie]
    private let failure: BrowserCookieError?
    private(set) var callCount = 0

    init(cookies: [BrowserCookie] = [], failure: BrowserCookieError? = nil) {
        self.cookies = cookies
        self.failure = failure
    }

    func cookies(
        from browser: Browser,
        matching filters: [CookieHarvest.DomainMatch]
    ) async throws(BrowserCookieError) -> [BrowserCookie] {
        callCount += 1
        if let failure { throw failure }
        guard !filters.isEmpty else { return cookies }
        return cookies.filter { cookie in filters.contains { $0.matches(cookie.domain) } }
    }
}

final class GatedBrowserCookieReader: BrowserCookieReading, @unchecked Sendable {
    private(set) var callCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func cookies(
        from browser: Browser,
        matching filters: [CookieHarvest.DomainMatch]
    ) async throws(BrowserCookieError) -> [BrowserCookie] {
        callCount += 1
        await withCheckedContinuation { self.continuation = $0 }
        return []
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class RecordingNotifier: SessionUpdateNotifying {
    var onOpen: (() -> Void)?
    private(set) var notifications: [[Provider]] = []
    private(set) var clearCount = 0

    func notify(pending: [Provider]) async {
        notifications.append(pending)
    }

    func clear() async {
        clearCount += 1
    }
}
