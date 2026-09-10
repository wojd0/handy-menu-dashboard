import Foundation
import Observation

enum CopilotAuthenticationResult: Equatable {
    case authenticated
    case staleSession
    case failure(String)
}

@Observable
final class CopilotService {
    typealias DataLoader = (URLRequest) async throws -> (Data, URLResponse)

    var isLoading = false
    var error: String?
    var isAuthenticated = false
    var isEnabled = true

    var creditsUsed: Double = 0
    var creditsTotal: Double = 0
    var creditsRemaining: Double = 0
    var isUnlimited = false

    private var cookieHeader: String?
    private var refreshTask: Task<Void, Never>?
    private let keychain: any KeychainStoring
    private let dataLoader: DataLoader

    static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/18.5 Safari/605.1.15"
    static let websiteDataDomains = ["github.com"]
    static let entitlementURL = URL(string: "https://github.com/github-copilot/chat/entitlement")!

    var percentUsed: Double {
        UsageMath.percentUsed(used: creditsUsed, limit: creditsTotal)
    }

    var percentRemaining: Double {
        UsageMath.percentUsed(used: creditsRemaining, limit: creditsTotal)
    }

    var isOverLimit: Bool {
        !isUnlimited && UsageMath.isOverLimit(percentUsed: percentUsed)
    }

    var isActive: Bool {
        isAuthenticated && isEnabled
    }

    var detailText: String {
        let total = isUnlimited ? UsageMath.infinitySymbol : UsageMath.formatCredits(creditsTotal)
        return "\(UsageMath.formatCredits(creditsUsed)) / \(total) credits"
    }

    var menuBarFragment: String {
        guard isActive else { return "" }
        return UsageMath.copilotCreditsFragment(
            used: creditsUsed,
            total: creditsTotal,
            isUnlimited: isUnlimited
        )
    }

    func menuBarFragment(displayMode: MenuBarDisplayMode) -> String {
        guard isActive else { return "" }
        switch displayMode {
        case .monetary:
            return menuBarFragment
        case .percentUsed:
            return UsageMath.menuBarPercentFragment(percent: percentUsed, isUnlimited: isUnlimited)
        case .percentRemaining:
            return UsageMath.menuBarPercentFragment(percent: percentRemaining, isUnlimited: isUnlimited)
        }
    }

    init(
        keychain: any KeychainStoring = KeychainStore(),
        dataLoader: @escaping DataLoader = { try await URLSession.shared.data(for: $0) },
        autoRefresh: Bool = true
    ) {
        self.keychain = keychain
        self.dataLoader = dataLoader
        isEnabled = (UserDefaults.standard.object(forKey: "copilotEnabled") as? Bool) ?? true
        removeLegacyCredentials()
        loadCredentials()
        if autoRefresh {
            startAutoRefresh()
        }
    }

    func authenticate(with cookies: [HTTPCookie]) async -> CopilotAuthenticationResult {
        let githubCookies = cookies.filter { cookie in
            cookie.domain == "github.com" || cookie.domain.hasSuffix(".github.com")
        }
        let hasSession = githubCookies.contains {
            ($0.name == "user_session" || $0.name == "private_mode_user_session") && !$0.value.isEmpty
        }
        let header = githubCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        guard hasSession, !header.isEmpty else {
            let message = "Invalid response from GitHub"
            error = message
            return .failure(message)
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let entitlement = try await fetchEntitlement(cookieHeader: header)
            let snapshot = try makeSnapshot(from: entitlement)
            keychain.saveString(key: .copilotCookies, value: header)
            cookieHeader = header
            apply(snapshot)
            isAuthenticated = true
            return .authenticated
        } catch let serviceError as ServiceError {
            handleServiceError(serviceError)
            switch serviceError {
            case .authExpired:
                return .staleSession
            case .noQuota, .httpError, .network, .invalidResponse:
                return .failure(error ?? "Unable to sign in to GitHub")
            }
        } catch {
            let message = "Invalid response from GitHub"
            self.error = message
            return .failure(message)
        }
    }

    func clearCredentials() async {
        keychain.delete(key: .copilotCookies)
        removeLegacyCredentials()
        cookieHeader = nil
        isAuthenticated = false
        creditsUsed = 0
        creditsTotal = 0
        creditsRemaining = 0
        isUnlimited = false
        error = nil
        await WebAuthSession.clearAllWebsiteData()
    }

    func refresh() async {
        guard let cookieHeader, !cookieHeader.isEmpty else { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let entitlement = try await fetchEntitlement(cookieHeader: cookieHeader)
            let snapshot = try makeSnapshot(from: entitlement)
            guard self.cookieHeader == cookieHeader else { return }
            apply(snapshot)
            isAuthenticated = true
        } catch let serviceError as ServiceError {
            handleServiceError(serviceError)
        } catch {
            self.error = "Invalid response from GitHub"
        }
    }

    private func fetchEntitlement(cookieHeader: String) async throws -> CopilotEntitlementResponse {
        let (data, _) = try await performRequest(cookieHeader: cookieHeader)
        do {
            return try JSONDecoder().decode(CopilotEntitlementResponse.self, from: data)
        } catch {
            throw ServiceError.invalidResponse
        }
    }

    private func performRequest(cookieHeader: String) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: Self.entitlementURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await dataLoader(request)
        } catch {
            throw ServiceError.network
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }
        if [401, 403, 404].contains(httpResponse.statusCode) || httpResponse.url?.path == "/login" {
            throw ServiceError.authExpired
        }
        guard httpResponse.statusCode == 200 else {
            throw ServiceError.httpError(httpResponse.statusCode)
        }
        return (data, response)
    }

    private func makeSnapshot(from response: CopilotEntitlementResponse) throws -> UsageSnapshot {
        guard let quota = response.quotas.premiumInteractionsQuota else {
            throw ServiceError.noQuota
        }
        guard quota.hasQuota != false else {
            throw ServiceError.noQuota
        }

        let unlimited = quota.unlimited == true
        guard unlimited || quota.total > 0 else {
            throw ServiceError.noQuota
        }

        return UsageSnapshot(
            used: quota.used,
            total: quota.total,
            remaining: response.quotas.remaining?.premiumInteractions
                ?? max(0, quota.total - quota.used),
            unlimited: unlimited
        )
    }

    private func apply(_ snapshot: UsageSnapshot) {
        creditsUsed = snapshot.used
        creditsTotal = snapshot.total
        creditsRemaining = snapshot.remaining
        isUnlimited = snapshot.unlimited
    }

    private func handleServiceError(_ serviceError: ServiceError) {
        switch serviceError {
        case .authExpired:
            keychain.delete(key: .copilotCookies)
            cookieHeader = nil
            isAuthenticated = false
            error = "Session expired. Please sign in again."
        case .noQuota:
            keychain.delete(key: .copilotCookies)
            cookieHeader = nil
            isAuthenticated = false
            error = "No Copilot credit quota is available for this account."
        case .httpError(let code):
            error = "GitHub returned status \(code)"
        case .network:
            error = "Unable to connect to GitHub"
        case .invalidResponse:
            error = "Invalid response from GitHub"
        }
    }

    private func removeLegacyCredentials() {
        keychain.delete(key: .copilotUsername)
        keychain.delete(key: .copilotPAT)
        keychain.delete(key: .copilotEntitlement)
    }

    private func loadCredentials() {
        if let header = keychain.loadString(key: .copilotCookies), !header.isEmpty {
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

    private struct UsageSnapshot {
        let used: Double
        let total: Double
        let remaining: Double
        let unlimited: Bool
    }

    private enum ServiceError: Error {
        case authExpired
        case noQuota
        case httpError(Int)
        case network
        case invalidResponse
    }
}
