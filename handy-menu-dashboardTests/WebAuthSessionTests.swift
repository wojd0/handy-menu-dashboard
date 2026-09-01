import Foundation
import Testing
import WebKit
@testable import handy_menu_dashboard

@Suite("Web authentication session")
struct WebAuthSessionTests {
    @Test func logoutClearsProviderAndMicrosoftSSOCookies() async {
        let store = WKWebsiteDataStore.nonPersistent()
        let providerCookie = makeCookie(name: "sessionKey", domain: ".claude.ai")
        let microsoftCookie = makeCookie(name: "ESTSAUTH", domain: ".login.microsoftonline.com")

        await setCookie(providerCookie, in: store)
        await setCookie(microsoftCookie, in: store)
        #expect(await cookies(in: store).count == 2)

        await WebAuthSession.clearAllWebsiteData(in: store)

        #expect(await cookies(in: store).isEmpty)
    }

    private func makeCookie(name: String, domain: String) -> HTTPCookie {
        HTTPCookie(properties: [
            .domain: domain,
            .path: "/",
            .name: name,
            .value: "test-value",
            .secure: "TRUE",
            .expires: Date(timeIntervalSinceNow: 3_600)
        ])!
    }

    private func setCookie(_ cookie: HTTPCookie, in store: WKWebsiteDataStore) async {
        await withCheckedContinuation { continuation in
            store.httpCookieStore.setCookie(cookie) {
                continuation.resume()
            }
        }
    }

    private func cookies(in store: WKWebsiteDataStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }
}
