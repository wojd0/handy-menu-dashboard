import Foundation

struct CookieHarvest: Equatable {
    enum DomainMatch: Equatable {
        case exactOrSuffix(String)
        case contains(String)

        func matches(_ domain: String) -> Bool {
            switch self {
            case .exactOrSuffix(let base):
                domain == base || domain.hasSuffix("." + base)
            case .contains(let fragment):
                domain.contains(fragment)
            }
        }
    }

    enum SessionRule: Equatable {
        case anyNamed(Set<String>, requireNonEmptyValue: Bool)
        case nameContainsAny([String])
        case prefixedAndNamed(prefix: String, required: String)

        func isSatisfied(by cookies: [HTTPCookie]) -> Bool {
            switch self {
            case .anyNamed(let names, let requireNonEmptyValue):
                cookies.contains { names.contains($0.name) && (!requireNonEmptyValue || !$0.value.isEmpty) }
            case .nameContainsAny(let fragments):
                cookies.contains { cookie in
                    let name = cookie.name.lowercased()
                    return fragments.contains { name.contains($0.lowercased()) }
                }
            case .prefixedAndNamed(let prefix, let required):
                cookies.contains { $0.name.hasPrefix(prefix) } && cookies.contains { $0.name == required }
            }
        }
    }

    let startURL: URL
    let requiredPathFragments: [String]
    let domainMatch: DomainMatch
    let sessionRule: SessionRule
    let websiteDataDomains: [String]

    func acceptsNavigation(to url: URL?) -> Bool {
        guard let url, let host = url.host, domainMatch.matches(host) else { return false }
        guard !requiredPathFragments.isEmpty else { return true }
        return requiredPathFragments.contains { url.path.contains($0) }
    }

    func sessionCookies(from cookies: [HTTPCookie]) -> [HTTPCookie]? {
        let scoped = cookies.filter { domainMatch.matches($0.domain) }
        guard sessionRule.isSatisfied(by: scoped) else { return nil }
        return scoped
    }
}

extension Provider {
    var harvest: CookieHarvest {
        switch self {
        case .cursor:
            CookieHarvest(
                startURL: URL(string: "https://www.cursor.com/settings")!,
                requiredPathFragments: ["/settings", "/dashboard"],
                domainMatch: .contains("cursor.com"),
                sessionRule: .nameContainsAny(["session", "token"]),
                websiteDataDomains: ["cursor.com"]
            )
        case .copilot:
            CookieHarvest(
                startURL: URL(string: "https://github.com/login")!,
                requiredPathFragments: [],
                domainMatch: .exactOrSuffix("github.com"),
                sessionRule: .anyNamed(["user_session", "private_mode_user_session"], requireNonEmptyValue: true),
                websiteDataDomains: ["github.com"]
            )
        case .claude:
            CookieHarvest(
                startURL: URL(string: "https://claude.ai/login")!,
                requiredPathFragments: [],
                domainMatch: .contains("claude.ai"),
                sessionRule: .anyNamed(["sessionKey"], requireNonEmptyValue: false),
                websiteDataDomains: ["claude.ai"]
            )
        case .chatgpt:
            CookieHarvest(
                startURL: URL(string: "https://chatgpt.com/")!,
                requiredPathFragments: [],
                domainMatch: .contains("chatgpt.com"),
                sessionRule: .prefixedAndNamed(prefix: "__Secure-next-auth.session-token", required: "_account"),
                websiteDataDomains: ["chatgpt.com", "openai.com"]
            )
        }
    }
}
