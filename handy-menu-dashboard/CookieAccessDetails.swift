import SwiftUI

struct CookieAccessDetails: View {
    let providers: [Provider]
    let browser: Browser?
    var home: URL = BrowserHome.current

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Cookie sources")
                    .fontWeight(.semibold)
                Text("Handy Menu Dashboard will read cookies from \(browserName) on this Mac for:")
                    .foregroundStyle(.secondary)

                ForEach(cookieDomains, id: \.self) { domain in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(domain)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("How your cookies are used")
                    .fontWeight(.semibold)
                Text("Cookies are saved in your Keychain on this Mac "
                    + "and used only to authenticate with each provider and fetch your usage.")
                    .foregroundStyle(.secondary)
                Text("They do not leave this device except for these requests to the relevant provider.")
                    .foregroundStyle(.secondary)
            }

            if let browser, isChromium(browser) {
                Text("macOS may ask to allow access to '\(browser.displayName) Safe Storage'.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var browserName: String {
        browser.map { "your \($0.displayName)" } ?? "your browser"
    }

    private var cookieDomains: [String] {
        var seen = Set<String>()
        return providers
            .map { provider in
                switch provider.harvest.domainMatch {
                case .exactOrSuffix(let domain), .contains(let domain): domain
                }
            }
            .filter { seen.insert($0).inserted }
    }

    private func isChromium(_ browser: Browser) -> Bool {
        if case .chromium = browser.engine(home: home) { return true }
        return false
    }
}
