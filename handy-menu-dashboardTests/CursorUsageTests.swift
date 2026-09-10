import Foundation
import Testing
@testable import handy_menu_dashboard

@Suite("Cursor usage")
struct CursorUsageTests {
    @Test func spendFormattedFormatsCentsWithTwoDecimals() {
        let service = makeService()
        service.spendCents = 12_345

        #expect(service.spendFormatted == "$123.45")
    }

    @Test func spendPercentUsedIsZeroWhenMonthlyLimitIsZero() {
        let service = makeService()
        service.spendCents = 9_999
        service.monthlyLimitDollars = 0

        #expect(service.spendPercentUsed == 0)
    }

    @Test func spendPercentUsedReflectsSpendAgainstLimit() {
        let service = makeService()
        service.spendCents = 5_000
        service.monthlyLimitDollars = 100

        #expect(service.spendPercentUsed == 50)
    }

    @Test func spendPercentUsedCanExceedOneHundredWhenOverLimit() {
        let service = makeService()
        service.spendCents = 15_000
        service.monthlyLimitDollars = 100

        #expect(service.spendPercentUsed == 150)
    }

    @Test func spendPercentRemainingReflectsAvailableAndOverLimitAmounts() {
        let service = makeService()
        service.monthlyLimitDollars = 100

        service.spendCents = 25_000
        #expect(service.spendPercentRemaining == -150)

        service.spendCents = 2_500
        #expect(service.spendPercentRemaining == 75)
    }

    @Test func spendPercentRemainingIsZeroWhenMonthlyLimitIsZero() {
        let service = makeService()
        service.spendCents = 2_500

        #expect(service.spendPercentRemaining == 0)
    }

    @Test func menuBarFragmentIsEmptyWhenInactive() {
        let service = makeService()
        service.spendCents = 5_000
        service.monthlyLimitDollars = 100

        #expect(service.menuBarFragment == "")
    }

    @Test func menuBarFragmentShowsTruncatedDollarsOverLimit() {
        let service = makeService()
        service.isAuthenticated = true
        service.isEnabled = true
        service.spendCents = 15_050
        service.monthlyLimitDollars = 100

        #expect(service.menuBarFragment == "$150/100")
    }

    @Test func menuBarFragmentShowsSpendAndLimitWhenActive() {
        let service = makeService()
        service.isAuthenticated = true
        service.isEnabled = true
        service.spendCents = 4_999
        service.monthlyLimitDollars = 50

        #expect(service.menuBarFragment == "$49/50")
    }

    @Test func menuBarFragmentSupportsAllDisplayModes() {
        let service = makeService()
        service.isAuthenticated = true
        service.isEnabled = true
        service.spendCents = 12_500
        service.monthlyLimitDollars = 100

        #expect(service.menuBarFragment(displayMode: .monetary) == "$125/100")
        #expect(service.menuBarFragment(displayMode: .percentUsed) == "125%")
        #expect(service.menuBarFragment(displayMode: .percentRemaining) == "-25%")
    }

    @Test func unlimitedUsageDisplaysInfinityForLimitAndMenuBarModes() {
        let service = makeService()
        service.isAuthenticated = true
        service.isEnabled = true
        service.spendCents = 15_000
        service.isUnlimited = true

        #expect(service.limitFormatted == "∞")
        #expect(service.menuBarFragment == "$150/∞")
        #expect(service.menuBarFragment(displayMode: .monetary) == "$150/∞")
        #expect(service.menuBarFragment(displayMode: .percentUsed) == "∞%")
        #expect(service.menuBarFragment(displayMode: .percentRemaining) == "∞%")
    }

    @Test func refreshLoadsUsageSummaryThenResolvesUserName() async {
        var paths: [String] = []
        let service = makeAuthenticatedService { request in
            paths.append(request.url!.path)
            return try stub(for: request)
        }

        await service.refresh()

        #expect(paths == ["/api/usage-summary", "/api/auth/me"])
        #expect(service.spendCents == 5_000)
        #expect(service.monthlyLimitDollars == 1_600)
        #expect(service.userName == "Ada Lovelace")
        #expect(service.isAuthenticated)
        #expect(service.error == nil)
    }

    @Test func refreshResolvesUserNameOnlyOnce() async {
        var paths: [String] = []
        let service = makeAuthenticatedService { request in
            paths.append(request.url!.path)
            return try stub(for: request)
        }

        await service.refresh()
        await service.refresh()

        #expect(paths.filter { $0 == "/api/auth/me" }.count == 1)
        #expect(paths.filter { $0 == "/api/usage-summary" }.count == 2)
    }

    @Test func refreshAppliesUnlimitedUsage() async {
        let service = makeAuthenticatedService { request in
            try stub(for: request, summary: unlimitedSummaryJSON)
        }

        await service.refresh()

        #expect(service.isUnlimited)
        #expect(service.monthlyLimitDollars == 0)
        #expect(service.limitFormatted == "∞")
    }

    @Test func expiredSessionRetainsStoredCredential() async {
        let keychain = InMemoryKeychainStore()
        keychain.saveString(key: .cursorCookies, value: sessionCookieHeader)
        let service = makeService(keychain: keychain) { request in
            try httpResponse(for: request, status: 401, json: [:])
        }

        await service.refresh()

        #expect(service.isAuthenticated == false)
        #expect(service.error == "Session expired. Please sign in again.")
        #expect(keychain.loadString(key: .cursorCookies) == sessionCookieHeader)
    }

    @Test func refreshKeepsSessionForHTTPFailure() async {
        let service = makeAuthenticatedService { request in
            try httpResponse(for: request, status: 503, json: [:])
        }

        await service.refresh()

        #expect(service.error == "Cursor returned status 503")
        #expect(service.isAuthenticated)
    }

    @Test func refreshMapsNetworkFailure() async {
        let service = makeAuthenticatedService { _ in throw NetworkFailure() }

        await service.refresh()

        #expect(service.error == "Unable to connect to Cursor")
        #expect(service.isAuthenticated)
    }

    @Test func refreshKeepsSessionForMalformedPayload() async {
        let service = makeAuthenticatedService { request in
            try httpResponse(for: request, data: Data("not json".utf8))
        }

        await service.refresh()

        #expect(service.error == "Failed to load Cursor usage")
        #expect(service.isAuthenticated)
    }

    @Test func refreshDiscardsResponseAfterCredentialsAreCleared() async {
        var service: CursorService!
        var didClear = false
        service = makeAuthenticatedService { request in
            if !didClear {
                didClear = true
                await service.clearCredentials()
            }
            return try stub(for: request)
        }

        await service.refresh()

        #expect(didClear)
        #expect(service.spendCents == 0)
        #expect(service.monthlyLimitDollars == 0)
        #expect(service.isAuthenticated == false)
    }

    private var sessionCookieHeader: String { "WorkosCursorSessionToken=test-token" }

    private var summaryJSON: [String: Any] {
        [
            "isUnlimited": false,
            "individualUsage": [
                "overall": ["enabled": true, "used": 5_000, "limit": 160_000, "remaining": 155_000]
            ]
        ]
    }

    private var unlimitedSummaryJSON: [String: Any] {
        [
            "isUnlimited": true,
            "individualUsage": [
                "overall": ["enabled": true, "used": 5_000, "limit": NSNull(), "remaining": NSNull()]
            ]
        ]
    }

    private func stub(
        for request: URLRequest,
        summary: [String: Any]? = nil
    ) throws -> (Data, URLResponse) {
        if request.url!.path == "/api/auth/me" {
            return try httpResponse(for: request, json: ["email": "ada@example.com", "name": "Ada Lovelace"])
        }
        return try httpResponse(for: request, json: summary ?? summaryJSON)
    }

    private func makeService(
        keychain: any KeychainStoring = InMemoryKeychainStore(),
        dataLoader: @escaping UsageDataLoader = { _ in throw NetworkFailure() }
    ) -> CursorService {
        CursorService(keychain: keychain, dataLoader: dataLoader, autoRefresh: false)
    }

    private func makeAuthenticatedService(
        dataLoader: @escaping UsageDataLoader
    ) -> CursorService {
        let keychain = InMemoryKeychainStore()
        keychain.saveString(key: .cursorCookies, value: sessionCookieHeader)
        return makeService(keychain: keychain, dataLoader: dataLoader)
    }
}
