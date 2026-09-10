import Foundation
import Testing
@testable import handy_menu_dashboard

@Suite("Claude usage")
struct ClaudeUsageTests {

    func makeService(
        authenticated: Bool = false,
        keychain: any KeychainStoring = InMemoryKeychainStore(),
        dataLoader: @escaping UsageDataLoader = { _ in throw NetworkFailure() }
    ) -> ClaudeService {
        let service = ClaudeService(
            keychain: keychain,
            dataLoader: dataLoader,
            autoRefresh: false,
            preferences: InMemoryPreferenceStore()
        )
        service.isAuthenticated = authenticated
        service.isEnabled = true
        return service
    }

    @Test func percentUsedForUsageLimitIsZeroWhenLimitIsZero() {
        let service = makeService()
        service.spendUsedDollars = 10
        service.spendLimitDollars = 0

        #expect(service.percentUsed(for: .usageLimit) == 0)
    }

    @Test func percentUsedForUsageLimitReflectsUsedAgainstLimit() {
        let service = makeService()
        service.spendUsedDollars = 25
        service.spendLimitDollars = 100

        #expect(service.percentUsed(for: .usageLimit) == 25)
    }

    @Test func percentUsedForCreditIsZeroWhenLimitIsZero() {
        let service = makeService()
        service.creditUsedDollars = 5
        service.creditLimitDollars = 0

        #expect(service.percentUsed(for: .credit) == 0)
    }

    @Test func percentUsedForCreditReflectsUsedAgainstLimit() {
        let service = makeService()
        service.creditUsedDollars = 10
        service.creditLimitDollars = 1000

        #expect(service.percentUsed(for: .credit) == 1)
    }

    @Test func percentUsedForCombinedSumsAllPools() {
        let service = makeService()
        service.spendUsedDollars = 2.39
        service.spendLimitDollars = 3000
        service.creditUsedDollars = 10.50
        service.creditLimitDollars = 1000

        let expected = UsageMath.percentUsed(used: 12.89, limit: 4000)
        #expect(abs(service.percentUsed(for: .combined) - expected) < 0.001)
    }

    @Test func percentUsedCanExceedOneHundredWhenOverLimit() {
        let service = makeService()
        service.spendUsedDollars = 150
        service.spendLimitDollars = 100

        #expect(service.percentUsed(for: .usageLimit) == 150)
    }

    @Test func percentRemainingSupportsEveryBaseline() {
        let service = makeService()
        service.spendUsedDollars = 150
        service.spendLimitDollars = 100
        service.creditUsedDollars = 25
        service.creditLimitDollars = 100

        #expect(service.percentRemaining(for: .usageLimit) == -50)
        #expect(service.percentRemaining(for: .credit) == 75)
        #expect(service.percentRemaining(for: .combined) == 12.5)
    }

    @Test func percentRemainingIsZeroWhenLimitIsZero() {
        let service = makeService()
        service.spendUsedDollars = 10

        #expect(service.percentRemaining(for: .usageLimit) == 0)
    }

    @Test func menuBarFragmentIsEmptyWhenInactive() {
        let service = makeService(authenticated: false)
        service.spendUsedDollars = 50
        service.spendLimitDollars = 100

        #expect(service.menuBarFragment(baseline: .usageLimit, displayMode: .monetary) == "")
    }

    @Test func menuBarFragmentDollarsUsageLimitShowsUsedOverLimit() {
        let service = makeService(authenticated: true)
        service.spendUsedDollars = 2.39
        service.spendLimitDollars = 3000

        #expect(service.menuBarFragment(baseline: .usageLimit, displayMode: .monetary) == "$2/3000")
    }

    @Test func menuBarFragmentDollarsCreditShowsUsedOverLimit() {
        let service = makeService(authenticated: true)
        service.creditUsedDollars = 10.5
        service.creditLimitDollars = 1000

        #expect(service.menuBarFragment(baseline: .credit, displayMode: .monetary) == "$10/1000")
    }

    @Test func menuBarFragmentDollarsCombinedShowsUsedOverLimit() {
        let service = makeService(authenticated: true)
        service.spendUsedDollars = 2.39
        service.spendLimitDollars = 3000
        service.creditUsedDollars = 10.5
        service.creditLimitDollars = 1000

        #expect(service.menuBarFragment(baseline: .combined, displayMode: .monetary) == "$12/4000")
    }

    @Test func menuBarFragmentPercentRoundsToNearestInt() {
        let service = makeService(authenticated: true)
        service.spendUsedDollars = 1
        service.spendLimitDollars = 3

        let percent = service.menuBarFragment(baseline: .usageLimit, displayMode: .percentUsed)
        #expect(percent == "33%")
    }

    @Test func menuBarFragmentShowsSignedPercentRemaining() {
        let service = makeService(authenticated: true)
        service.spendUsedDollars = 5
        service.spendLimitDollars = 4

        let percent = service.menuBarFragment(baseline: .usageLimit, displayMode: .percentRemaining)
        #expect(percent == "-25%")
    }

    @Test func detailTextForUsageLimitFormatsUsedAndLimit() {
        let service = makeService()
        service.spendUsedDollars = 2.39
        service.spendLimitDollars = 3000

        #expect(service.detailText(for: .usageLimit) == "$2.39 / $3000.00")
    }

    @Test func detailTextForCreditFormatsUsedAndLimit() {
        let service = makeService()
        service.creditUsedDollars = 10.498
        service.creditLimitDollars = 1000

        #expect(service.detailText(for: .credit) == "$10.50 / $1000.00")
    }

    @Test func detailTextForCombinedFormatsUsedAndLimit() {
        let service = makeService()
        service.spendUsedDollars = 2.39
        service.spendLimitDollars = 3000
        service.creditUsedDollars = 10.5
        service.creditLimitDollars = 1000

        #expect(service.detailText(for: .combined) == "$12.89 / $4000.00")
    }

    @Test func refreshResolvesOrgFromCookieAndAppliesBothPools() async {
        var paths: [String] = []
        let service = makeAuthenticatedService { request in
            paths.append(request.url!.path)
            return try self.stub(for: request)
        }

        await service.refresh()

        #expect(paths == ["/api/organizations/org-123/usage"])
        #expect(service.spendUsedDollars == 2.39)
        #expect(service.spendLimitDollars == 3000)
        #expect(service.creditUsedDollars == 10.5)
        #expect(service.creditLimitDollars == 1000)
        #expect(service.creditRemainingDollars == 989.5)
        #expect(service.hasSpend)
        #expect(service.hasCredit)
        #expect(service.isAuthenticated)
    }

    @Test func refreshFallsBackToOrganizationsEndpointWithoutOrgCookie() async {
        var paths: [String] = []
        let keychain = InMemoryKeychainStore()
        keychain.saveString(key: .claudeCookies, value: "sessionKey=sk-test")
        let service = makeService(keychain: keychain) { request in
            paths.append(request.url!.path)
            if request.url!.path == "/api/organizations" {
                return try httpResponse(for: request, json: [["uuid": "org-from-api"]])
            }
            return try self.stub(for: request)
        }

        await service.refresh()

        #expect(paths == ["/api/organizations", "/api/organizations/org-from-api/usage"])
        #expect(service.spendUsedDollars == 2.39)
    }

    @Test func refreshComputesCreditRemainingWhenAbsent() async {
        let service = makeAuthenticatedService { request in
            try self.stub(for: request, usage: self.usageJSON(includeRemaining: false))
        }

        await service.refresh()

        #expect(service.creditRemainingDollars == 989.5)
    }

    @Test func expiredSessionRetainsStoredCredential() async {
        let keychain = InMemoryKeychainStore()
        keychain.saveString(key: .claudeCookies, value: sessionCookieHeader)
        let service = makeService(authenticated: true, keychain: keychain) { request in
            try httpResponse(for: request, status: 403, json: [:])
        }

        await service.refresh()

        #expect(service.isAuthenticated == false)
        #expect(service.error == "Session expired. Please sign in again.")
        #expect(keychain.loadString(key: .claudeCookies) == sessionCookieHeader)
    }

    @Test func refreshKeepsSessionForHTTPFailure() async {
        let service = makeAuthenticatedService { request in
            try httpResponse(for: request, status: 502, json: [:])
        }

        await service.refresh()

        #expect(service.error == "Claude returned status 502")
        #expect(service.isAuthenticated)
    }

    @Test func refreshMapsNetworkFailure() async {
        let service = makeAuthenticatedService { _ in throw NetworkFailure() }

        await service.refresh()

        #expect(service.error == "Unable to connect to Claude")
        #expect(service.isAuthenticated)
    }

    @Test func refreshKeepsSessionForMalformedPayload() async {
        let service = makeAuthenticatedService { request in
            try httpResponse(for: request, data: Data("not json".utf8))
        }

        await service.refresh()

        #expect(service.error == "Failed to load Claude usage")
        #expect(service.isAuthenticated)
    }

    @Test func refreshDiscardsResponseAfterCredentialsAreCleared() async {
        var service: ClaudeService!
        var didClear = false
        service = makeAuthenticatedService { request in
            if !didClear {
                didClear = true
                await service.clearCredentials()
            }
            return try self.stub(for: request)
        }

        await service.refresh()

        #expect(didClear)
        #expect(service.spendUsedDollars == 0)
        #expect(service.hasSpend == false)
        #expect(service.isAuthenticated == false)
    }

    private var sessionCookieHeader: String { "sessionKey=sk-test; lastActiveOrg=org-123" }

    private func usageJSON(includeRemaining: Bool = true) -> [String: Any] {
        var pool: [String: Any] = [
            "utilization": 0.0105,
            "limit_dollars": 1000,
            "used_dollars": 10.5,
            "resets_at": "2026-10-01T00:00:00Z"
        ]
        if includeRemaining {
            pool["remaining_dollars"] = 989.5
        }
        return [
            "spend": [
                "used": ["amount_minor": 239, "exponent": 2],
                "limit": ["amount_minor": 300_000, "exponent": 2],
                "enabled": true
            ],
            "cinder_cove": pool
        ]
    }

    private func stub(
        for request: URLRequest,
        usage: [String: Any]? = nil
    ) throws -> (Data, URLResponse) {
        try httpResponse(for: request, json: usage ?? usageJSON())
    }

    private func makeAuthenticatedService(
        dataLoader: @escaping UsageDataLoader
    ) -> ClaudeService {
        let keychain = InMemoryKeychainStore()
        keychain.saveString(key: .claudeCookies, value: sessionCookieHeader)
        return makeService(authenticated: true, keychain: keychain, dataLoader: dataLoader)
    }
}
