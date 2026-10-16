import Foundation
import Testing
@testable import handy_menu_dashboard

@Suite("Browser")
struct BrowserTests {
    @Test func resolvesKnownBundleIdentifiers() {
        #expect(Browser.resolve(bundleID: "org.mozilla.firefox") == .firefox)
        #expect(Browser.resolve(bundleID: "org.mozilla.firefoxdeveloperedition") == .firefoxDeveloperEdition)
        #expect(Browser.resolve(bundleID: "org.mozilla.nightly") == .firefoxNightly)
        #expect(Browser.resolve(bundleID: "com.google.Chrome") == .chrome)
        #expect(Browser.resolve(bundleID: "app.zen-browser.zen") == .zen)
        #expect(Browser.resolve(bundleID: "com.apple.Safari") == .safari)
        #expect(Browser.resolve(bundleID: "com.unknown.Thing") == nil)
    }

    @Test(arguments: [Browser.firefox, .firefoxDeveloperEdition, .firefoxNightly])
    func geckoProfilesRootIsUnderApplicationSupport(browser: Browser) {
        let home = URL(fileURLWithPath: "/Users/tester")

        let engine = browser.engine(home: home)

        guard case let .gecko(profilesRoot) = engine else {
            Issue.record("expected gecko engine")
            return
        }
        #expect(profilesRoot.path == "/Users/tester/Library/Application Support/Firefox")
    }

    @Test func chromiumEngineCarriesTheSafeStorageNames() {
        let home = URL(fileURLWithPath: "/Users/tester")

        let engine = Browser.chrome.engine(home: home)

        guard case let .chromium(userDataRoot, service, account) = engine else {
            Issue.record("expected chromium engine")
            return
        }
        #expect(userDataRoot.path == "/Users/tester/Library/Application Support/Google/Chrome")
        #expect(service == "Chrome Safe Storage")
        #expect(account == "Chrome")
    }

    @Test func safariEnginePointsAtTheContainerCookieFile() {
        let home = URL(fileURLWithPath: "/Users/tester")

        let engine = Browser.safari.engine(home: home)

        guard case let .webkit(cookieFile) = engine else {
            Issue.record("expected webkit engine")
            return
        }
        #expect(cookieFile.path.hasSuffix("com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"))
    }
}
