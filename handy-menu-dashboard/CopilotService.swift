import Foundation
import Observation

@Observable
final class CopilotService: UsageDisplaying {
    let provider = Provider.copilot

    var isEnabled: Bool {
        get { session.isEnabled }
        set { session.isEnabled = newValue }
    }

    var menuBarDisplayMode: MenuBarDisplayMode {
        get { session.menuBarDisplayMode }
        set { session.menuBarDisplayMode = newValue }
    }

    var menuBarText: String { menuBarFragment(displayMode: menuBarDisplayMode) }

    var creditsUsed: Double = 0
    var creditsTotal: Double = 0
    var creditsRemaining: Double = 0
    var isUnlimited = false

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

    static let entitlementURL = URL(string: "https://github.com/github-copilot/chat/entitlement")!
    static let noQuotaMessage = "No Copilot credit quota is available for this account."
    static let legacyKeys: [KeychainKey] = [.copilotUsername, .copilotPAT, .copilotEntitlement]

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
        autoRefresh: Bool = true,
        preferences: any PreferenceStoring = UserDefaults.standard
    ) {
        session = UsageSession(provider: .copilot, keychain: keychain, preferences: preferences)
        transport = UsageTransport(dataLoader: dataLoader, policy: .github)
        session.purgeLegacy(Self.legacyKeys)
        session.loadStoredCredential()
        if autoRefresh {
            startAutoRefresh()
        }
    }

    var credentialHeader: String? { session.cookieHeader }

    func adoptBrowserCookies(_ cookies: [HTTPCookie]) async -> LoginOutcome {
        await authenticate(with: cookies)
    }

    func authenticate(with cookies: [HTTPCookie]) async -> LoginOutcome {
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

        session.isLoading = true
        error = nil
        defer { session.isLoading = false }

        do {
            let entitlement = try await fetchEntitlement(cookieHeader: header)
            let snapshot = try makeSnapshot(from: entitlement)
            session.persist(header)
            apply(snapshot)
            return .authenticated
        } catch let kind as UsageFailure.Kind {
            session.absorb(kind)
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
        session.discardCredential()
        session.purgeLegacy(Self.legacyKeys)
        creditsUsed = 0
        creditsTotal = 0
        creditsRemaining = 0
        isUnlimited = false
        error = nil
        await WebAuthSession.clearAllWebsiteData()
    }

    func refresh() async {
        await session.run(
            load: { cookie in
                let entitlement = try await self.fetchEntitlement(cookieHeader: cookie)
                return try self.makeSnapshot(from: entitlement)
            },
            apply: { self.apply($0) },
            unexpected: "Invalid response from GitHub"
        )
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
