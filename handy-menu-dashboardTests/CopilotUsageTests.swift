import Foundation
import Testing
import WebKit
@testable import handy_menu_dashboard

@Suite("Copilot usage")
struct CopilotUsageTests {
    @Test func loginUsesAPersistentWebSession() {
        let configuration = CopilotWebView.makeConfiguration()

        #expect(configuration.websiteDataStore.isPersistent)
    }

    @Test func decodesEntitlementResponse() throws {
        let response = try JSONDecoder().decode(CopilotEntitlementResponse.self, from: samplePayload)
        let quota = try #require(response.quotas.premiumInteractionsQuota)

        #expect(quota.total == 350_000)
        #expect(quota.used == 5_343)
        #expect(response.quotas.remaining?.premiumInteractions == 344_657)
        #expect(quota.hasQuota == true)
        #expect(quota.unlimited == false)
    }

    @Test func formatsDashboardAndMenuBarCredits() {
        let service = makeService()
        service.isAuthenticated = true
        service.creditsUsed = 5_343
        service.creditsTotal = 350_000
        service.creditsRemaining = 344_657

        #expect(service.detailText == "5,343 / 350,000 credits")
        #expect(service.menuBarFragment == "5.3K/350K")
        #expect(service.menuBarFragment(displayMode: .percentUsed) == "2%")
        #expect(service.menuBarFragment(displayMode: .percentRemaining) == "98%")
    }

    @Test func menuBarFragmentsAreEmptyWhenInactive() {
        let service = makeService()
        service.creditsUsed = 5_343
        service.creditsTotal = 350_000

        #expect(service.menuBarFragment == "")
        #expect(service.menuBarFragment(displayMode: .percentUsed) == "")
        #expect(service.menuBarFragment(displayMode: .percentRemaining) == "")
    }

    @Test func supportsUnlimitedQuota() async throws {
        let service = CopilotService(
            keychain: InMemoryKeychainStore(),
            dataLoader: { request in
                try response(
                    for: request,
                    json: entitlementJSON(total: 0, used: 42, remaining: 0, unlimited: true)
                )
            },
            autoRefresh: false
        )

        let result = await service.authenticate(with: makeCookies())

        #expect(result == .authenticated)
        #expect(service.isUnlimited)
        #expect(service.detailText == "42 / ∞ credits")
        #expect(service.menuBarFragment == "42/∞")
        #expect(service.menuBarFragment(displayMode: .percentUsed) == "∞%")
    }

    @Test func authenticationPersistsCookiesOnlyAfterValidation() async throws {
        let keychain = InMemoryKeychainStore()
        var requests: [URLRequest] = []
        let service = CopilotService(
            keychain: keychain,
            dataLoader: { request in
                requests.append(request)
                #expect(keychain.loadString(key: .copilotCookies) == nil)
                return try response(for: request, data: samplePayload)
            },
            autoRefresh: false
        )

        let result = await service.authenticate(with: makeCookies())

        #expect(result == .authenticated)
        #expect(service.isAuthenticated)
        #expect(service.creditsUsed == 5_343)
        #expect(service.creditsTotal == 350_000)
        #expect(service.creditsRemaining == 344_657)
        #expect(keychain.loadString(key: .copilotCookies)?.contains("user_session=test-session") == true)
        #expect(requests.count == 1)
        #expect(requests[0].url == CopilotService.entitlementURL)
        #expect(requests[0].value(forHTTPHeaderField: "Cookie")?.contains("user_session=test-session") == true)
        #expect(requests[0].value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(requests[0].value(forHTTPHeaderField: "User-Agent") == CopilotService.browserUserAgent)
    }

    @Test func authenticationRequiresGitHubSessionCookie() async {
        var requestCount = 0
        let service = CopilotService(
            keychain: InMemoryKeychainStore(),
            dataLoader: { _ in
                requestCount += 1
                return (Data(), URLResponse())
            },
            autoRefresh: false
        )
        let cookie = HTTPCookie(properties: [
            .domain: ".github.com",
            .path: "/",
            .name: "_gh_sess",
            .value: "not-an-auth-session"
        ])!

        let result = await service.authenticate(with: [cookie])

        #expect(result == .failure("Invalid response from GitHub"))
        #expect(requestCount == 0)
        #expect(!service.isAuthenticated)
    }

    @Test func authenticationRejectsAndDeletesAStaleSession() async throws {
        let keychain = InMemoryKeychainStore()
        keychain.saveString(key: .copilotCookies, value: "user_session=previous")
        let service = CopilotService(
            keychain: keychain,
            dataLoader: { request in
                try response(for: request, status: 404, json: [:])
            },
            autoRefresh: false
        )

        let result = await service.authenticate(with: makeCookies())

        #expect(result == .staleSession)
        #expect(!service.isAuthenticated)
        #expect(service.error == "Session expired. Please sign in again.")
        #expect(keychain.loadString(key: .copilotCookies) == nil)
    }

    @Test func authenticationRejectsAccountWithoutQuota() async throws {
        let keychain = InMemoryKeychainStore()
        let service = CopilotService(
            keychain: keychain,
            dataLoader: { request in
                try response(
                    for: request,
                    json: entitlementJSON(total: 0, used: 0, remaining: 0, hasQuota: false)
                )
            },
            autoRefresh: false
        )

        let result = await service.authenticate(with: makeCookies())

        #expect(result == .failure("No Copilot credit quota is available for this account."))
        #expect(!service.isAuthenticated)
        #expect(keychain.loadString(key: .copilotCookies) == nil)
    }

    @Test func authenticationKeepsRecoverableFailuresRetryable() async {
        struct NetworkFailure: Error {}
        let keychain = InMemoryKeychainStore()
        let service = CopilotService(
            keychain: keychain,
            dataLoader: { _ in throw NetworkFailure() },
            autoRefresh: false
        )

        let result = await service.authenticate(with: makeCookies())

        #expect(result == .failure("Unable to connect to GitHub"))
        #expect(!service.isAuthenticated)
        #expect(keychain.loadString(key: .copilotCookies) == nil)
    }

    @Test func refreshLoadsQuotaAndFallsBackToCalculatedRemaining() async throws {
        let keychain = InMemoryKeychainStore()
        keychain.saveString(key: .copilotCookies, value: "user_session=test-session")
        let service = CopilotService(
            keychain: keychain,
            dataLoader: { request in
                try response(
                    for: request,
                    json: entitlementJSON(total: 1_000, used: 125, remaining: nil)
                )
            },
            autoRefresh: false
        )

        await service.refresh()

        #expect(service.isAuthenticated)
        #expect(service.creditsUsed == 125)
        #expect(service.creditsTotal == 1_000)
        #expect(service.creditsRemaining == 875)
        #expect(service.percentUsed == 12.5)
        #expect(service.percentRemaining == 87.5)
    }

    @Test func refreshExpiresUnauthorizedSession() async throws {
        let keychain = InMemoryKeychainStore()
        keychain.saveString(key: .copilotCookies, value: "user_session=test-session")
        let service = CopilotService(
            keychain: keychain,
            dataLoader: { request in
                try response(for: request, status: 401, json: [:])
            },
            autoRefresh: false
        )

        await service.refresh()

        #expect(!service.isAuthenticated)
        #expect(service.error == "Session expired. Please sign in again.")
        #expect(keychain.loadString(key: .copilotCookies) == nil)
    }

    @Test func refreshKeepsSessionForHTTPFailure() async throws {
        let keychain = InMemoryKeychainStore()
        keychain.saveString(key: .copilotCookies, value: "user_session=test-session")
        let service = CopilotService(
            keychain: keychain,
            dataLoader: { request in
                try response(for: request, status: 429, json: [:])
            },
            autoRefresh: false
        )

        await service.refresh()

        #expect(service.isAuthenticated)
        #expect(service.error == "GitHub returned status 429")
        #expect(keychain.loadString(key: .copilotCookies) != nil)
    }

    @Test func refreshKeepsSessionForMalformedPayload() async throws {
        let keychain = InMemoryKeychainStore()
        keychain.saveString(key: .copilotCookies, value: "user_session=test-session")
        let service = CopilotService(
            keychain: keychain,
            dataLoader: { request in
                try response(for: request, json: ["unexpected": true])
            },
            autoRefresh: false
        )

        await service.refresh()

        #expect(service.isAuthenticated)
        #expect(service.error == "Invalid response from GitHub")
        #expect(keychain.loadString(key: .copilotCookies) != nil)
    }

    @Test func initializationRemovesLegacyCredentials() {
        let keychain = InMemoryKeychainStore()
        keychain.saveString(key: .copilotUsername, value: "octocat")
        keychain.saveString(key: .copilotPAT, value: "github_pat_test")
        keychain.saveString(key: .copilotEntitlement, value: "300")

        let service = CopilotService(keychain: keychain, autoRefresh: false)

        #expect(!service.isAuthenticated)
        #expect(keychain.loadString(key: .copilotUsername) == nil)
        #expect(keychain.loadString(key: .copilotPAT) == nil)
        #expect(keychain.loadString(key: .copilotEntitlement) == nil)
    }

    private func makeService() -> CopilotService {
        CopilotService(keychain: InMemoryKeychainStore(), autoRefresh: false)
    }

    private func makeCookies() -> [HTTPCookie] {
        [
            HTTPCookie(properties: [
                .domain: ".github.com",
                .path: "/",
                .name: "user_session",
                .value: "test-session",
                .secure: "TRUE"
            ])!,
            HTTPCookie(properties: [
                .domain: ".github.com",
                .path: "/",
                .name: "dotcom_user",
                .value: "octocat"
            ])!
        ]
    }

    private func entitlementJSON(
        total: Double,
        used: Double,
        remaining: Double?,
        hasQuota: Bool = true,
        unlimited: Bool = false
    ) -> [String: Any] {
        var quotas: [String: Any] = [
            "premiumInteractionsQuota": [
                "total": total,
                "used": used,
                "hasQuota": hasQuota,
                "unlimited": unlimited
            ]
        ]
        if let remaining {
            quotas["remaining"] = ["premiumInteractions": remaining]
        }
        return ["quotas": quotas]
    }

    private func response(
        for request: URLRequest,
        status: Int = 200,
        json: Any
    ) throws -> (Data, URLResponse) {
        try response(for: request, status: status, data: JSONSerialization.data(withJSONObject: json))
    }

    private func response(
        for request: URLRequest,
        status: Int = 200,
        data: Data
    ) throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/2",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (data, response)
    }

    private var samplePayload: Data {
        Data(
            """
            {
              "licenseType": "licensed_full",
              "quotas": {
                "limits": { "premiumInteractions": 350000 },
                "remaining": {
                  "premiumInteractions": 344657,
                  "chatPercentage": 100.0,
                  "premiumInteractionsPercentage": 98.4
                },
                "resetDate": "2026-10-01",
                "resetDateUtc": "2026-10-01T00:00:00.000Z",
                "overagesEnabled": true,
                "tokenBasedBillingEnabled": true,
                "premiumInteractionsQuota": {
                  "percentRemaining": 98.4,
                  "total": 350000,
                  "used": 5343.0,
                  "hasQuota": true,
                  "unlimited": false,
                  "creditsUsed": 5342
                }
              },
              "plan": "enterprise",
              "trial": { "eligible": false }
            }
            """.utf8
        )
    }
}
