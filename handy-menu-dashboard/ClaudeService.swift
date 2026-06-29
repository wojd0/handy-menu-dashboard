import Foundation
import Observation

enum ClaudeBaseline: String, CaseIterable, Identifiable {
    case usageLimit
    case credit
    case combined

    var id: String { rawValue }

    var label: String {
        switch self {
        case .usageLimit: "Limit"
        case .credit: "Credit"
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
    private var refreshTask: Task<Void, Never>?
    private let keychain: any KeychainStoring

    static let chromeUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        + "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    var combinedUsedDollars: Double { spendUsedDollars + creditUsedDollars }
    var combinedLimitDollars: Double { spendLimitDollars + creditLimitDollars }
    var combinedRemainingDollars: Double { combinedLimitDollars - combinedUsedDollars }

    var isActive: Bool { FeatureFlags.showClaudeSettings && isAuthenticated && isEnabled }

    func percentUsed(for baseline: ClaudeBaseline) -> Double {
        switch baseline {
        case .usageLimit: UsageMath.percentUsed(used: spendUsedDollars, limit: spendLimitDollars)
        case .credit: UsageMath.percentUsed(used: creditUsedDollars, limit: creditLimitDollars)
        case .combined: UsageMath.percentUsed(used: combinedUsedDollars, limit: combinedLimitDollars)
        }
    }

    func detailText(for baseline: ClaudeBaseline) -> String {
        switch baseline {
        case .usageLimit:
            "\(UsageMath.formatDollars(spendUsedDollars)) / \(UsageMath.formatDollars(spendLimitDollars))"
        case .credit:
            "\(UsageMath.formatDollars(creditUsedDollars)) / \(UsageMath.formatDollars(creditLimitDollars))"
        case .combined:
            "\(UsageMath.formatDollars(combinedUsedDollars)) / \(UsageMath.formatDollars(combinedLimitDollars))"
        }
    }

    func menuBarFragment(baseline: ClaudeBaseline, showPercent: Bool) -> String {
        guard isActive else { return "" }
        if showPercent {
            return UsageMath.menuBarPercentFragment(percent: percentUsed(for: baseline))
        }
        switch baseline {
        case .usageLimit:
            return UsageMath.claudeDollarsFragment(used: spendUsedDollars, limit: spendLimitDollars)
        case .credit:
            return UsageMath.claudeDollarsFragment(used: creditUsedDollars, limit: creditLimitDollars)
        case .combined:
            return UsageMath.claudeRemainingFragment(combinedRemainingDollars)
        }
    }

    init(keychain: any KeychainStoring = KeychainStore()) {
        self.keychain = keychain
        isEnabled = (UserDefaults.standard.object(forKey: "claudeEnabled") as? Bool) ?? true
        loadCredentials()
        startAutoRefresh()
    }

    func saveCookies(_ cookies: [HTTPCookie]) {
        let header = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        guard !header.isEmpty else { return }
        keychain.saveString(key: .claudeCookies, value: header)
        cookieHeader = header
        isAuthenticated = true
        Task { await refresh() }
    }

    func clearCredentials() {
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
    }

    func refresh() async {
        guard let cookieHeader, !cookieHeader.isEmpty else { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let orgId = try await resolveOrgId(cookieHeader: cookieHeader)
            let usage = try await fetchUsage(orgId: orgId, cookieHeader: cookieHeader)
            applyUsage(usage)
        } catch let err as ServiceError {
            handleServiceError(err)
        } catch {
            self.error = "Failed to load Claude usage"
        }
    }

    private func resolveOrgId(cookieHeader: String) async throws -> String {
        if let orgId = extractCookieValue(named: "lastActiveOrg", from: cookieHeader) {
            return orgId
        }
        let (data, _) = try await performRequest(
            url: "https://claude.ai/api/organizations",
            cookieHeader: cookieHeader
        )
        struct OrgItem: Decodable { let uuid: String }
        let orgs = try JSONDecoder().decode([OrgItem].self, from: data)
        guard let first = orgs.first else { throw ServiceError.invalidResponse }
        return first.uuid
    }

    private func fetchUsage(orgId: String, cookieHeader: String) async throws -> ClaudeUsageResponse {
        let (data, _) = try await performRequest(
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

    private func extractCookieValue(named name: String, from cookieHeader: String) -> String? {
        for pair in cookieHeader.components(separatedBy: "; ") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 && parts[0] == name {
                return String(parts[1])
            }
        }
        return nil
    }

    private func performRequest(
        url: String,
        cookieHeader: String
    ) async throws(ServiceError) -> (Data, URLResponse) {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "GET"
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue(Self.chromeUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("web_claude_ai", forHTTPHeaderField: "anthropic-client-platform")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw .network
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw .invalidResponse
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw .authExpired
        }

        guard httpResponse.statusCode == 200 else {
            throw .httpError(httpResponse.statusCode)
        }

        return (data, response)
    }

    private func handleServiceError(_ err: ServiceError) {
        switch err {
        case .authExpired:
            isAuthenticated = false
            error = "Session expired. Please sign in again."
        case .httpError(let code):
            error = "Claude returned status \(code)"
        case .network:
            error = "Unable to connect to Claude"
        case .invalidResponse:
            error = "Invalid response from Claude"
        }
    }

    private func loadCredentials() {
        if let header = keychain.loadString(key: .claudeCookies), !header.isEmpty {
            cookieHeader = header
            isAuthenticated = true
        }
    }

    private func startAutoRefresh() {
        refreshTask = Task {
            while !Task.isCancelled {
                if isActive {
                    await refresh()
                }
                try? await Task.sleep(for: .seconds(180))
            }
        }
    }

    private enum ServiceError: Error {
        case authExpired
        case httpError(Int)
        case network
        case invalidResponse
    }
}
