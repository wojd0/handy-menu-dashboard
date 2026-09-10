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
final class ClaudeService {
    var isLoading = false
    var error: String?
    var isAuthenticated = false
    var isEnabled = true

    var spendUsedDollars: Double = 0
    var spendLimitDollars: Double = 0
    var creditUsedDollars: Double = 0
    var creditLimitDollars: Double = 0
    var creditRemainingDollars: Double = 0
    var hasSpend = false
    var hasCredit = false

    private var cookieHeader: String?
    private let refreshLoop = RefreshLoop()
    private let keychain: any KeychainStoring
    private let transport: UsageTransport

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
        autoRefresh: Bool = true
    ) {
        self.keychain = keychain
        transport = UsageTransport(dataLoader: dataLoader)
        isEnabled = (UserDefaults.standard.object(forKey: "claudeEnabled") as? Bool) ?? true
        loadCredentials()
        if autoRefresh {
            startAutoRefresh()
        }
    }

    func saveCookies(_ cookies: [HTTPCookie]) {
        let header = CookieHeader.header(from: cookies)
        guard !header.isEmpty else { return }
        keychain.saveString(key: .claudeCookies, value: header)
        cookieHeader = header
        isAuthenticated = true
        Task { await refresh() }
    }

    func clearCredentials() async {
        keychain.delete(key: .claudeCookies)
        cookieHeader = nil
        isAuthenticated = false
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
        guard let cookieHeader, !cookieHeader.isEmpty else { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let orgId = try await resolveOrgId(cookieHeader: cookieHeader)
            let usage = try await fetchUsage(orgId: orgId, cookieHeader: cookieHeader)
            guard self.cookieHeader == cookieHeader else { return }
            applyUsage(usage)
        } catch let kind as UsageFailure.Kind {
            handleFailure(kind)
        } catch {
            self.error = "Failed to load Claude usage"
        }
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

        isAuthenticated = true
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

    private func handleFailure(_ kind: UsageFailure.Kind) {
        let outcome = SessionTransition.apply(
            UsageFailure(kind: kind, provider: .claude),
            to: SessionState(isAuthenticated: isAuthenticated, errorMessage: error)
        )
        isAuthenticated = outcome.state.isAuthenticated
        error = outcome.state.errorMessage
        if outcome.discardsCredential {
            keychain.delete(key: .claudeCookies)
            cookieHeader = nil
        }
    }

    private func loadCredentials() {
        if let header = keychain.loadString(key: .claudeCookies), !header.isEmpty {
            cookieHeader = header
            isAuthenticated = true
        }
    }

    private func startAutoRefresh() {
        refreshLoop.start { [weak self] in
            guard let self, self.isActive else { return }
            await self.refresh()
        }
    }
}
