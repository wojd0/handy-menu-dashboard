import Foundation
import Observation

enum ClaudeUsagePool: String, CaseIterable, Identifiable {
    case usageLimit
    case credit
    case combined
    case session
    case weekly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .usageLimit: "General"
        case .credit: "Credit"
        case .combined: "Combined"
        case .session: "Session (5h)"
        case .weekly: "Weekly"
        }
    }
}

@Observable
final class ClaudeService: UsageDisplaying {
    let provider = Provider.claude

    var reading: UsageReading { reading(for: resolvedUsagePool) }

    var isEnabled: Bool {
        get { session.isEnabled }
        set { session.isEnabled = newValue }
    }

    var menuBarDisplayMode: MenuBarDisplayMode {
        get { session.menuBarDisplayMode }
        set { session.menuBarDisplayMode = newValue }
    }

    var usagePool: ClaudeUsagePool {
        get { storedUsagePool }
        set {
            storedUsagePool = newValue
            ProviderPreferences.setClaudeUsagePool(newValue, in: preferences)
        }
    }

    var menuBarText: String {
        menuBarFragment(usagePool: resolvedUsagePool, displayMode: menuBarDisplayMode)
    }

    var spendUsedDollars: Double = 0
    var spendLimitDollars: Double = 0
    var creditUsedDollars: Double = 0
    var creditLimitDollars: Double = 0
    var creditRemainingDollars: Double = 0
    var sessionPercent: Double = 0
    var sessionResetsAt: Date?
    var weeklyPercent: Double = 0
    var weeklyResetsAt: Date?
    var hasSpend = false
    var hasCredit = false
    var hasSession = false
    var hasWeekly = false

    private var storedUsagePool: ClaudeUsagePool

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

    var availableUsagePools: [ClaudeUsagePool] {
        ClaudeUsagePool.allCases.filter(hasPool(for:))
    }

    var resolvedUsagePool: ClaudeUsagePool {
        if hasPool(for: usagePool) { return usagePool }
        if hasSession { return .session }
        if hasWeekly { return .weekly }
        return usagePool
    }

    func hasPool(for usagePool: ClaudeUsagePool) -> Bool {
        switch usagePool {
        case .usageLimit: hasSpend
        case .credit: hasCredit
        case .combined: hasSpend && hasCredit
        case .session: hasSession
        case .weekly: hasWeekly
        }
    }

    func reading(for usagePool: ClaudeUsagePool) -> UsageReading {
        switch usagePool {
        case .usageLimit:
            makeReading(used: spendUsedDollars, limit: spendLimitDollars)
        case .credit:
            makeReading(used: creditUsedDollars, limit: creditLimitDollars)
        case .combined:
            makeReading(used: combinedUsedDollars, limit: combinedLimitDollars)
        case .session:
            makeWindowReading(percent: sessionPercent)
        case .weekly:
            makeWindowReading(percent: weeklyPercent)
        }
    }

    private func makeReading(used: Double, limit: Double) -> UsageReading {
        UsageReading(used: used, limit: limit, amountStyle: .wholeDollars, detailStyle: .dollars)
    }

    private func makeWindowReading(percent: Double) -> UsageReading {
        UsageReading(used: percent, limit: 100, amountStyle: .percent, detailStyle: .percent)
    }

    func percentUsed(for usagePool: ClaudeUsagePool) -> Double {
        reading(for: usagePool).percentUsed
    }

    func percentRemaining(for usagePool: ClaudeUsagePool) -> Double {
        reading(for: usagePool).percentRemaining
    }

    func detailText(for usagePool: ClaudeUsagePool) -> String {
        reading(for: usagePool).detailText
    }

    func menuBarFragment(usagePool: ClaudeUsagePool, displayMode: MenuBarDisplayMode) -> String {
        guard isActive else { return "" }
        return reading(for: usagePool).menuBarText(displayMode)
    }

    init(
        keychain: any KeychainStoring = KeychainStore(),
        dataLoader: @escaping UsageDataLoader = DefaultDataLoader.live,
        autoRefresh: Bool = true,
        preferences: any PreferenceStoring = UserDefaults.standard
    ) {
        self.preferences = preferences
        storedUsagePool = ProviderPreferences.claudeUsagePool(in: preferences)
        session = UsageSession(provider: .claude, keychain: keychain, preferences: preferences)
        transport = UsageTransport(dataLoader: dataLoader)
        session.loadStoredCredential()
        if autoRefresh {
            startAutoRefresh()
        }
    }

    var credentialHeader: String? { session.cookieHeader }

    func saveCookies(_ cookies: [HTTPCookie]) {
        let header = CookieHeader.header(from: cookies)
        guard !header.isEmpty else { return }
        session.persist(header)
        Task { await refresh() }
    }

    func adoptBrowserCookies(_ cookies: [HTTPCookie], ifAllowed: @escaping @MainActor () -> Bool = { true }) async -> LoginOutcome {
        let header = CookieHeader.header(from: cookies)
        guard !header.isEmpty else { return .failure("No Claude cookies found") }
        guard ifAllowed() else { return .failure("Session update cancelled") }

        session.persist(header)
        await refresh()

        return isAuthenticated ? .authenticated : .failure(error ?? "Unable to sign in to Claude")
    }

    func clearCredentials() async {
        session.discardCredential()
        spendUsedDollars = 0
        spendLimitDollars = 0
        creditUsedDollars = 0
        creditLimitDollars = 0
        creditRemainingDollars = 0
        sessionPercent = 0
        sessionResetsAt = nil
        weeklyPercent = 0
        weeklyResetsAt = nil
        hasSpend = false
        hasCredit = false
        hasSession = false
        hasWeekly = false
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
        } else {
            spendUsedDollars = 0
            spendLimitDollars = 0
            hasSpend = false
        }

        if let pool = response.creditPool {
            creditUsedDollars = pool.usedDollars ?? 0
            creditLimitDollars = pool.limitDollars ?? 0
            creditRemainingDollars = pool.remainingDollars ?? creditLimitDollars - creditUsedDollars
            hasCredit = true
        } else {
            creditUsedDollars = 0
            creditLimitDollars = 0
            creditRemainingDollars = 0
                hasCredit = false
        }

        let session = response.fiveHour?.utilization
        sessionPercent = session ?? 0
        sessionResetsAt = session == nil ? nil : response.fiveHour?.resetsAt.flatMap(Self.parseDate)
        hasSession = session != nil

        let weekly = response.sevenDay?.utilization
        weeklyPercent = weekly ?? 0
        weeklyResetsAt = weekly == nil ? nil : response.sevenDay?.resetsAt.flatMap(Self.parseDate)
        hasWeekly = weekly != nil
    }

    static func parseDate(_ text: String) -> Date? {
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return (try? fractional.parse(text)) ?? (try? Date.ISO8601FormatStyle().parse(text))
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
