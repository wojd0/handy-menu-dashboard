import Foundation
import Observation

enum ClaudeBaseline: String, CaseIterable, Identifiable {
    case usageLimit
    case credit
    case combined

    var id: String { rawValue }

    var label: String {
        switch self {
        case .usageLimit: "General"
        case .credit: "Code and Cowork"
        case .combined: "Combined"
        }
    }
}

@Observable
final class ClaudeService: UsageDisplaying {
    let provider = Provider.claude

    var reading: UsageReading { reading(for: baseline) }

    var isEnabled: Bool {
        get { session.isEnabled }
        set { session.isEnabled = newValue }
    }

    var menuBarDisplayMode: MenuBarDisplayMode {
        get { session.menuBarDisplayMode }
        set { session.menuBarDisplayMode = newValue }
    }

    var baseline: ClaudeBaseline {
        get { storedBaseline }
        set {
            storedBaseline = newValue
            ProviderPreferences.setClaudeBaseline(newValue, in: preferences)
        }
    }

    var menuBarText: String {
        menuBarFragment(baseline: baseline, displayMode: menuBarDisplayMode)
    }

    var spendUsedDollars: Double = 0
    var spendLimitDollars: Double = 0
    var creditUsedDollars: Double = 0
    var creditLimitDollars: Double = 0
    var creditRemainingDollars: Double = 0
    var hasSpend = false
    var hasCredit = false

    private var storedBaseline: ClaudeBaseline

    @ObservationIgnored private let preferences: any PreferenceStoring
    @ObservationIgnored private let session: UsageSession
    @ObservationIgnored private let refreshLoop = RefreshLoop()
    @ObservationIgnored private let transport: UsageTransport

    var isLoading: Bool { session.isLoading }

    var isAuthenticated: Bool {
        get { session.isAuthenticated }
        set { session.isAuthenticated = newValue }
    }

    var error: String? {
        get { session.errorMessage }
        set { session.errorMessage = newValue }
    }

    var combinedUsedDollars: Double { spendUsedDollars + creditUsedDollars }
    var combinedLimitDollars: Double { spendLimitDollars + creditLimitDollars }
    var combinedRemainingDollars: Double { combinedLimitDollars - combinedUsedDollars }

    var isActive: Bool { isAuthenticated && isEnabled }

    func reading(for baseline: ClaudeBaseline) -> UsageReading {
        switch baseline {
        case .usageLimit:
            makeReading(used: spendUsedDollars, limit: spendLimitDollars)
        case .credit:
            makeReading(used: creditUsedDollars, limit: creditLimitDollars)
        case .combined:
            makeReading(used: combinedUsedDollars, limit: combinedLimitDollars)
        }
    }

    private func makeReading(used: Double, limit: Double) -> UsageReading {
        UsageReading(used: used, limit: limit, amountStyle: .wholeDollars, detailStyle: .dollars)
    }

    func percentUsed(for baseline: ClaudeBaseline) -> Double {
        reading(for: baseline).percentUsed
    }

    func percentRemaining(for baseline: ClaudeBaseline) -> Double {
        reading(for: baseline).percentRemaining
    }

    func detailText(for baseline: ClaudeBaseline) -> String {
        reading(for: baseline).detailText
    }

    func menuBarFragment(baseline: ClaudeBaseline, displayMode: MenuBarDisplayMode) -> String {
        guard isActive else { return "" }
        return reading(for: baseline).menuBarText(displayMode)
    }

    init(
        keychain: any KeychainStoring = KeychainStore(),
        dataLoader: @escaping UsageDataLoader = DefaultDataLoader.live,
        autoRefresh: Bool = true,
        preferences: any PreferenceStoring = UserDefaults.standard
    ) {
        self.preferences = preferences
        storedBaseline = ProviderPreferences.claudeBaseline(in: preferences)
        session = UsageSession(provider: .claude, keychain: keychain, preferences: preferences)
        transport = UsageTransport(dataLoader: dataLoader)
        session.loadStoredCredential()
        if autoRefresh {
            startAutoRefresh()
        }
    }

    func saveCookies(_ cookies: [HTTPCookie]) {
        let header = CookieHeader.header(from: cookies)
        guard !header.isEmpty else { return }
        session.persist(header)
        Task { await refresh() }
    }

    func clearCredentials() async {
        session.discardCredential()
        spendUsedDollars = 0
        spendLimitDollars = 0
        creditUsedDollars = 0
        creditLimitDollars = 0
        creditRemainingDollars = 0
        hasSpend = false
        hasCredit = false
        error = nil
        await WebAuthSession.clearAllWebsiteData()
    }

    func refresh() async {
        await session.run(
            load: { cookie in
                let orgId = try await self.resolveOrgId(cookieHeader: cookie)
                return try await self.fetchUsage(orgId: orgId, cookieHeader: cookie)
            },
            apply: { self.applyUsage($0) },
            unexpected: "Failed to load Claude usage"
        )
    }

    private func resolveOrgId(cookieHeader: String) async throws -> String {
        if let orgId = CookieHeader.value(named: "lastActiveOrg", in: cookieHeader) {
            return orgId
        }
        let data = try await request(url: "https://claude.ai/api/organizations", cookieHeader: cookieHeader)
        struct OrgItem: Decodable { let uuid: String }
        let orgs = try JSONDecoder().decode([OrgItem].self, from: data)
        guard let first = orgs.first else { throw UsageFailure.Kind.invalidResponse }
        return first.uuid
    }

    private func fetchUsage(orgId: String, cookieHeader: String) async throws -> ClaudeUsageResponse {
        let data = try await request(
            url: "https://claude.ai/api/organizations/\(orgId)/usage",
            cookieHeader: cookieHeader
        )
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ClaudeUsageResponse.self, from: data)
    }

    private func applyUsage(_ response: ClaudeUsageResponse) {
        if let spend = response.spend, let used = spend.used, let limit = spend.limit {
            spendUsedDollars = UsageMath.dollars(amountMinor: used.amountMinor, exponent: used.exponent)
            spendLimitDollars = UsageMath.dollars(amountMinor: limit.amountMinor, exponent: limit.exponent)
            hasSpend = true
        }

        if let pool = response.cinderCove {
            creditUsedDollars = pool.usedDollars ?? 0
            creditLimitDollars = pool.limitDollars ?? 0
            if let remaining = pool.remainingDollars {
                creditRemainingDollars = remaining
            } else {
                creditRemainingDollars = creditLimitDollars - creditUsedDollars
            }
            hasCredit = true
        }
    }

    private func request(url: String, cookieHeader: String) async throws(UsageFailure.Kind) -> Data {
        try await transport.data(
            for: UsageRequest(
                url: url,
                cookieHeader: cookieHeader,
                headers: ["anthropic-client-platform": "web_claude_ai"]
            )
        )
    }

    private func startAutoRefresh() {
        refreshLoop.start { [weak self] in
            guard let self, self.isActive else { return }
            await self.refresh()
        }
    }
}
