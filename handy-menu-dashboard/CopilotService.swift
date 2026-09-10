import Foundation
import Observation

enum CopilotAuthenticationResult: Equatable {
    case authenticated
    case staleSession
    case failure(String)
}

@Observable
final class CopilotService {
    var isLoading = false
    var error: String?
    var isAuthenticated = false
    var isEnabled = true

    var creditsUsed: Double = 0
    var creditsTotal: Double = 0
    var creditsRemaining: Double = 0
    var isUnlimited = false

    private var cookieHeader: String?
    private let refreshLoop = RefreshLoop()
    private let keychain: any KeychainStoring
    private let transport: UsageTransport

    static let websiteDataDomains = ["github.com"]
    static let entitlementURL = URL(string: "https://github.com/github-copilot/chat/entitlement")!
    static let noQuotaMessage = "No Copilot credit quota is available for this account."

    var reading: UsageReading {
        UsageReading(
            used: creditsUsed,
            limit: creditsTotal,
            isUnlimited: isUnlimited,
            amountStyle: .abbreviatedCredits,
            detailStyle: .credits
        )
    }

    var percentUsed: Double { reading.percentUsed }

    var percentRemaining: Double { reading.percentRemaining }

    var isOverLimit: Bool { reading.isOverLimit }

    var isActive: Bool {
        isAuthenticated && isEnabled
    }

    var detailText: String { reading.detailText }

    var menuBarFragment: String {
        menuBarFragment(displayMode: .monetary)
    }

    func menuBarFragment(displayMode: MenuBarDisplayMode) -> String {
        guard isActive else { return "" }
        return reading.menuBarText(displayMode)
    }

    init(
        keychain: any KeychainStoring = KeychainStore(),
        dataLoader: @escaping UsageDataLoader = DefaultDataLoader.live,
        autoRefresh: Bool = true
    ) {
        self.keychain = keychain
        transport = UsageTransport(dataLoader: dataLoader, policy: .github)
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
        let header = CookieHeader.header(from: githubCookies)
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
        } catch let kind as UsageFailure.Kind {
            handleFailure(kind)
            switch kind {
            case .authExpired:
                return .staleSession
            case .rejected, .httpError, .network, .invalidResponse:
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
        } catch let kind as UsageFailure.Kind {
            handleFailure(kind)
        } catch {
            self.error = "Invalid response from GitHub"
        }
    }

    private func fetchEntitlement(cookieHeader: String) async throws -> CopilotEntitlementResponse {
        let data = try await transport.data(
            for: UsageRequest(
                url: Self.entitlementURL.absoluteString,
                cookieHeader: cookieHeader,
                headers: ["Accept": "application/json"]
            )
        )
        do {
            return try JSONDecoder().decode(CopilotEntitlementResponse.self, from: data)
        } catch {
            throw UsageFailure.Kind.invalidResponse
        }
    }

    private func makeSnapshot(from response: CopilotEntitlementResponse) throws -> UsageSnapshot {
        guard let quota = response.quotas.premiumInteractionsQuota else {
            throw UsageFailure.Kind.rejected(Self.noQuotaMessage)
        }
        guard quota.hasQuota != false else {
            throw UsageFailure.Kind.rejected(Self.noQuotaMessage)
        }

        let unlimited = quota.unlimited == true
        guard unlimited || quota.total > 0 else {
            throw UsageFailure.Kind.rejected(Self.noQuotaMessage)
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

    private func handleFailure(_ kind: UsageFailure.Kind) {
        let outcome = SessionTransition.apply(
            UsageFailure(kind: kind, provider: .copilot),
            to: SessionState(isAuthenticated: isAuthenticated, errorMessage: error)
        )
        isAuthenticated = outcome.state.isAuthenticated
        error = outcome.state.errorMessage
        if outcome.discardsCredential {
            keychain.delete(key: .copilotCookies)
            cookieHeader = nil
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
        refreshLoop.start { [weak self] in
            guard let self, self.isActive else { return }
            await self.refresh()
        }
    }

    private struct UsageSnapshot {
        let used: Double
        let total: Double
        let remaining: Double
        let unlimited: Bool
    }
}
