import Foundation
import Testing
@testable import handy_menu_dashboard

@Suite("Cookie harvest")
struct CookieHarvestTests {
    @Test func cursorOnlyHarvestsOnTheSettingsOrDashboardPages() {
        let harvest = Provider.cursor.harvest

        #expect(harvest.acceptsNavigation(to: url("https://www.cursor.com/settings")))
        #expect(harvest.acceptsNavigation(to: url("https://cursor.com/dashboard?tab=usage")))
        #expect(harvest.acceptsNavigation(to: url("https://www.cursor.com/login")) == false)
        #expect(harvest.acceptsNavigation(to: url("https://github.com/settings")) == false)
        #expect(harvest.acceptsNavigation(to: nil) == false)
    }

    @Test func cursorAcceptsAnyCookieNamedLikeASessionOrToken() {
        let harvest = Provider.cursor.harvest

        #expect(harvest.sessionCookies(from: [cookie("WorkosCursorSessionToken", domain: ".cursor.com")]) != nil)
        #expect(harvest.sessionCookies(from: [cookie("access_token", domain: ".cursor.com")]) != nil)
        #expect(harvest.sessionCookies(from: [cookie("theme", domain: ".cursor.com")]) == nil)
    }

    @Test func claudeHarvestsOnAnyPageAndNeedsTheSessionKey() {
        let harvest = Provider.claude.harvest

        #expect(harvest.acceptsNavigation(to: url("https://claude.ai/login")))
        #expect(harvest.acceptsNavigation(to: url("https://claude.ai/chats")))
        #expect(harvest.acceptsNavigation(to: url("https://openai.com/")) == false)
        #expect(harvest.sessionCookies(from: [cookie("sessionKey", domain: ".claude.ai")]) != nil)
        #expect(harvest.sessionCookies(from: [cookie("lastActiveOrg", domain: ".claude.ai")]) == nil)
    }

    @Test func copilotRequiresANonEmptyGitHubSessionCookie() {
        let harvest = Provider.copilot.harvest

        #expect(harvest.acceptsNavigation(to: url("https://github.com/login")))
        #expect(harvest.acceptsNavigation(to: url("https://gist.github.com/")))
        #expect(harvest.acceptsNavigation(to: url("https://notgithub.com/")) == false)
        #expect(harvest.sessionCookies(from: [cookie("user_session", domain: ".github.com")]) != nil)
        #expect(harvest.sessionCookies(from: [cookie("private_mode_user_session", domain: "github.com")]) != nil)
        #expect(harvest.sessionCookies(from: [cookie("user_session", value: "", domain: ".github.com")]) == nil)
        #expect(harvest.sessionCookies(from: [cookie("dotcom_user", domain: ".github.com")]) == nil)
    }

    @Test func chatGPTNeedsBothTheSplitSessionTokenAndTheAccountCookie() {
        let harvest = Provider.chatgpt.harvest
        let sessionToken = cookie("__Secure-next-auth.session-token.0", domain: ".chatgpt.com")
        let account = cookie("_account", domain: ".chatgpt.com")

        #expect(harvest.sessionCookies(from: [sessionToken, account]) != nil)
        #expect(harvest.sessionCookies(from: [sessionToken]) == nil)
        #expect(harvest.sessionCookies(from: [account]) == nil)
    }

    @Test func cookiesFromOtherDomainsAreNeverHarvested() {
        let harvest = Provider.claude.harvest
        let foreign = cookie("sessionKey", domain: ".example.com")
        let own = cookie("sessionKey", domain: ".claude.ai")

        let harvested = harvest.sessionCookies(from: [foreign, own])

        #expect(harvested?.count == 1)
        #expect(harvested?.first?.domain == ".claude.ai")
    }

    @Test func everyProviderStartsOnItsOwnHost() {
        let starts = Provider.allCases.map { $0.harvest.startURL.absoluteString }

        #expect(starts == [
            "https://www.cursor.com/settings",
            "https://github.com/login",
            "https://claude.ai/login",
            "https://chatgpt.com/"
        ])
        #expect(Provider.allCases.allSatisfy { $0.harvest.acceptsNavigation(to: $0.harvest.startURL) })
    }

    @Test func chatGPTClearsOpenAIAlongsideChatGPT() {
        #expect(Provider.chatgpt.harvest.websiteDataDomains == ["chatgpt.com", "openai.com"])
        #expect(Provider.copilot.harvest.websiteDataDomains == ["github.com"])
    }

    @Test func containsDomainBuildsALikePredicate() {
        let predicate = CookieHarvest.DomainMatch.contains("cursor.com").sqlPredicate(column: "host")

        #expect(predicate == "host LIKE '%cursor.com%'")
    }

    @Test func exactOrSuffixDomainCoversTheBareAndDottedForms() {
        let predicate = CookieHarvest.DomainMatch.exactOrSuffix("github.com").sqlPredicate(column: "host_key")

        #expect(predicate == "(host_key = 'github.com' OR host_key = '.github.com' OR host_key LIKE '%.github.com')")
    }

    @Test func sqlPredicateEscapesSingleQuotes() {
        let predicate = CookieHarvest.DomainMatch.contains("o'brien").sqlPredicate(column: "host")

        #expect(predicate == "host LIKE '%o''brien%'")
    }

    private func url(_ string: String) -> URL? {
        URL(string: string)
    }

    private func cookie(_ name: String, value: String = "v", domain: String) -> HTTPCookie {
        HTTPCookie(properties: [
            .domain: domain,
            .path: "/",
            .name: name,
            .value: value
        ])!
    }
}
