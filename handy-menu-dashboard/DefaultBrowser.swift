import AppKit

enum DefaultBrowser {
    static func current() -> Browser? {
        guard let httpsURL = URL(string: "https://example.com"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: httpsURL),
              let bundle = Bundle(url: appURL),
              let bundleID = bundle.bundleIdentifier else {
            return nil
        }
        return Browser.resolve(bundleID: bundleID)
    }

    static func installed() -> [Browser] {
        Browser.allCases.filter { browser in
            browser.bundleIDs.contains { bundleID in
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
            }
        }
    }
}
