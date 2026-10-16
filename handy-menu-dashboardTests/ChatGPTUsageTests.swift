import Foundation
import Testing
import WebKit
@testable import handy_menu_dashboard

@Suite("ChatGPT usage")
struct ChatGPTUsageTests {
    private let accountID = "11111111-2222-3333-4444-555555555555"

    @Test func loginUsesAPersistentWebSession() {
        let configuration = ValidatingWebView.makeConfiguration()

        #expect(configuration.websiteDataStore.isPersistent)
    }

    @Test func decodesMonthlyUsageResponse() throws {
        let data = Data(
            """
            {
              "effective_monthly_limit": {
                "limit": 40000,
                "enforcement_mode": "HARD_CAP",
                "limit_mode": "amount_credits"
              },
              "current_month_usage": 12.5
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let response = try decoder.decode(ChatGPTUsageResponse.self, from: data)

        #expect(response.currentMonthUsage == 12.5)
        #expect(response.effectiveMonthlyLimit.limit == 40_000)
        #expect(response.effectiveMonthlyLimit.enforcementMode == "HARD_CAP")
        #expect(response.effectiveMonthlyLimit.limitMode == "amount_credits")
    }

    @Test func percentageIsZeroWhenLimitIsZero() {
        let service = makeService()
        service.currentMonthUsage = 42
        service.monthlyLimitCredits = 0

        #expect(service.percentUsed == 0)
    }

    @Test func percentageCanExceedLimit() {
        let service = makeService()
        service.currentMonthUsage = 125
        service.monthlyLimitCredits = 100

        #expect(service.percentUsed == 125)
        #expect(service.isOverLimit)
    }

    @Test func percentRemainingIsSignedAndZeroWithoutLimit() {
        let service = makeService()
        service.currentMonthUsage = 125
        service.monthlyLimitCredits = 100

        #expect(service.percentRemaining == -25)

        service.monthlyLimitCredits = 0
        #expect(service.percentRemaining == 0)
    }

    @Test func formatsDashboardCreditsWithGroupingAndFraction() {
        let service = makeService()
        service.currentMonthUsage = 12.5
        service.monthlyLimitCredits = 40_000

        #expect(service.detailText == "12.5 / 40,000 credits")
    }

    @Test func menuBarFragmentsAreEmptyWhenInactive() {
        let service = makeService()
        service.currentMonthUsage = 12.5
        service.monthlyLimitCredits = 40_000

        #expect(service.menuBarFragment == "")
        #expect(service.menuBarFragment(displayMode: .percentUsed) == "")
        #expect(service.menuBarFragment(displayMode: .percentRemaining) == "")
    }

    @Test func menuBarSupportsCreditsAndPercentModes() {
        let service = makeService()
        service.isAuthenticated = true
        service.isEnabled = true
        service.currentMonthUsage = 10_000
        service.monthlyLimitCredits = 40_000

        #expect(service.menuBarFragment == "10000/40000")
        #expect(service.menuBarFragment(displayMode: .monetary) == "10000/40000")
        #expect(service.menuBarFragment(displayMode: .percentUsed) == "25%")
        #expect(service.menuBarFragment(displayMode: .percentRemaining) == "75%")
    }

    @Test func extractsAccountFromJWT() throws {
        let token = makeJWT(accountID: accountID)

        #expect(try ChatGPTService.accountID(fromJWT: token) == accountID)
    }

    @Test func rejectsMalformedJWT() {
        #expect(throws: (any Error).self) {
            try ChatGPTService.accountID(fromJWT: "not-a-jwt")
        }
    }

    private func makeService() -> ChatGPTService {
        ChatGPTService(
            keychain: InMemoryKeychainStore(),
            autoRefresh: false,
            preferences: InMemoryPreferenceStore()
        )
    }

    private func makeJWT(accountID: String) -> String {
        let payload = "{\"https://api.openai.com/auth\":{\"chatgpt_account_id\":\"\(accountID)\"}}"
        let data = Data(payload.utf8)
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(encoded).signature"
    }

    private func makeCookies() -> [HTTPCookie] {
        [
            HTTPCookie(properties: [
                .domain: ".chatgpt.com",
                .path: "/",
                .name: "_account",
                .value: accountID
            ])!,
            HTTPCookie(properties: [
                .domain: ".chatgpt.com",
                .path: "/",
                .name: "__Secure-next-auth.session-token.0",
                .value: "test"
            ])!
        ]
    }

    private func response(
        for request: URLRequest,
        status: Int = 200,
        json: Any
    ) throws -> (Data, URLResponse) {
        let data = try JSONSerialization.data(withJSONObject: json)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/2",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (data, response)
    }
}

extension ChatGPTUsageTests {
    @Test func authenticationPersistsCookiesOnlyAfterValidation() async throws {
        let keychain = InMemoryKeychainStore()
        let token = makeJWT(accountID: accountID)
        var requests: [URLRequest] = []
        let service = ChatGPTService(
            keychain: keychain,
            dataLoader: { request in
                requests.append(request)
                #expect(keychain.loadString(key: .chatGPTCookies) == nil)
                if request.url?.path == "/api/auth/session" {
                    return try response(for: request, json: ["accessToken": token])
                }
                return try response(
                    for: request,
                    json: [
                        "effective_monthly_limit": [
                            "limit": 40_000,
                            "enforcement_mode": "HARD_CAP",
                            "limit_mode": "amount_credits"
                        ],
                        "current_month_usage": 125.25
                    ]
                )
            },
            autoRefresh: false,
            preferences: InMemoryPreferenceStore()
        )

        let result = await service.authenticate(with: makeCookies())

        #expect(result == .authenticated)
        #expect(service.isAuthenticated)
        #expect(service.currentMonthUsage == 125.25)
        #expect(keychain.loadString(key: .chatGPTCookies)?.contains("_account=\(accountID)") == true)
        #expect(requests.count == 2)
    }

    @Test func authenticationRejectsAndDeletesAStaleSession() async throws {
        let keychain = InMemoryKeychainStore()
        keychain.saveString(key: .chatGPTCookies, value: "previous=session")
        let service = ChatGPTService(
            keychain: keychain,
            dataLoader: { request in
                try response(for: request, status: 401, json: [:])
            },
            autoRefresh: false,
            preferences: InMemoryPreferenceStore()
        )

        let result = await service.authenticate(with: makeCookies())

        #expect(result == .staleSession)
        #expect(!service.isAuthenticated)
        #expect(service.error == "Session expired. Please sign in again.")
        #expect(keychain.loadString(key: .chatGPTCookies) == nil)
    }

    @Test func authenticationKeepsRecoverableFailuresRetryable() async {
        struct NetworkFailure: Error {}
        let keychain = InMemoryKeychainStore()
        let service = ChatGPTService(
            keychain: keychain,
            dataLoader: { _ in throw NetworkFailure() },
            autoRefresh: false,
            preferences: InMemoryPreferenceStore()
        )

        let result = await service.authenticate(with: makeCookies())

        #expect(result == .failure("Unable to connect to ChatGPT"))
        #expect(!service.isAuthenticated)
        #expect(keychain.loadString(key: .chatGPTCookies) == nil)
    }

    @Test func browserImportDoesNotPersistAfterApprovalIsRevokedDuringValidation() async {
        let keychain = InMemoryKeychainStore()
        let token = makeJWT(accountID: accountID)
        var approved = true
        let service = ChatGPTService(
            keychain: keychain,
            dataLoader: { request in
                if request.url?.path == "/api/auth/session" {
                    return try response(for: request, json: ["accessToken": token])
                }
                approved = false
                return try response(for: request, json: [
                    "effective_monthly_limit": ["limit": 40_000], "current_month_usage": 12.5
                ])
            },
            autoRefresh: false,
            preferences: InMemoryPreferenceStore()
        )

        let result = await service.adoptBrowserCookies(makeCookies(), ifAllowed: { approved })

        #expect(result == .failure("Session update cancelled"))
        #expect(!service.isAuthenticated)
        #expect(!service.isEnabled)
        #expect(keychain.loadString(key: .chatGPTCookies) == nil)
    }

    @Test func refreshLoadsSessionThenMonthlyUsage() async throws {
        let keychain = InMemoryKeychainStore()
        keychain.saveString(
            key: .chatGPTCookies,
            value: "_account=\(accountID); __Secure-next-auth.session-token.0=test"
        )
        let token = makeJWT(accountID: accountID)
        var requests: [URLRequest] = []
        let service = ChatGPTService(
            keychain: keychain,
            dataLoader: { request in
                requests.append(request)
                if request.url?.path == "/api/auth/session" {
                    return try response(
                        for: request,
                        json: ["accessToken": token]
                    )
                }
                return try response(
                    for: request,
                    json: [
                        "effective_monthly_limit": [
                            "limit": 40_000,
                            "enforcement_mode": "HARD_CAP",
                            "limit_mode": "amount_credits"
                        ],
                        "current_month_usage": 125.25
                    ]
                )
            },
            autoRefresh: false,
            preferences: InMemoryPreferenceStore()
        )

        await service.refresh()

        #expect(service.error == nil)
        #expect(service.isAuthenticated)
        #expect(service.currentMonthUsage == 125.25)
        #expect(service.monthlyLimitCredits == 40_000)
        #expect(requests.count == 2)
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
        #expect(requests[1].value(forHTTPHeaderField: "ChatGPT-Account-ID") == accountID)
    }

    @Test func refreshRejectsAccountMismatch() async {
        let keychain = InMemoryKeychainStore()
        keychain.saveString(
            key: .chatGPTCookies,
            value: "_account=\(accountID); __Secure-next-auth.session-token.0=test"
        )
        let otherAccountID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        let token = makeJWT(accountID: otherAccountID)
        let service = ChatGPTService(
            keychain: keychain,
            dataLoader: { request in
                try response(for: request, json: ["accessToken": token])
            },
            autoRefresh: false,
            preferences: InMemoryPreferenceStore()
        )

        await service.refresh()

        #expect(!service.isAuthenticated)
        #expect(service.error == "Session expired. Please sign in again.")
        #expect(keychain.loadString(key: .chatGPTCookies) == nil)
    }

    @Test func refreshMapsNetworkFailure() async {
        struct NetworkFailure: Error {}
        let keychain = InMemoryKeychainStore()
        keychain.saveString(
            key: .chatGPTCookies,
            value: "_account=\(accountID); __Secure-next-auth.session-token.0=test"
        )
        let service = ChatGPTService(
            keychain: keychain,
            dataLoader: { _ in throw NetworkFailure() },
            autoRefresh: false,
            preferences: InMemoryPreferenceStore()
        )

        await service.refresh()

        #expect(service.error == "Unable to connect to ChatGPT")
    }

    @Test func refreshMapsHTTPFailure() async {
        let keychain = InMemoryKeychainStore()
        keychain.saveString(
            key: .chatGPTCookies,
            value: "_account=\(accountID); __Secure-next-auth.session-token.0=test"
        )
        let service = ChatGPTService(
            keychain: keychain,
            dataLoader: { request in
                try response(for: request, status: 429, json: [:])
            },
            autoRefresh: false,
            preferences: InMemoryPreferenceStore()
        )

        await service.refresh()

        #expect(service.error == "ChatGPT returned status 429")
    }

    @Test func refreshRejectsMalformedSessionPayload() async {
        let keychain = InMemoryKeychainStore()
        keychain.saveString(
            key: .chatGPTCookies,
            value: "_account=\(accountID); __Secure-next-auth.session-token.0=test"
        )
        let service = ChatGPTService(
            keychain: keychain,
            dataLoader: { request in
                try response(for: request, json: ["unexpected": true])
            },
            autoRefresh: false,
            preferences: InMemoryPreferenceStore()
        )

        await service.refresh()

        #expect(!service.isAuthenticated)
        #expect(service.error == "Session expired. Please sign in again.")
    }
}
