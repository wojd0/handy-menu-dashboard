import Foundation
import Observation

@Observable
final class CursorService: UsageDisplaying {
    let provider = Provider.cursor
    var subtitle: String? { userName }

    var isEnabled: Bool {
        get { session.isEnabled }
        set { session.isEnabled = newValue }
    }

    var menuBarDisplayMode: MenuBarDisplayMode {
        get { session.menuBarDisplayMode }
        set { session.menuBarDisplayMode = newValue }
    }

    var menuBarText: String { menuBarFragment(displayMode: menuBarDisplayMode) }
    var spendCents: Int = 0
    var monthlyLimitDollars: Int = 0
    var isUnlimited = false
    var userName: String?

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

    var reading: UsageReading {
        UsageReading(
            used: Double(spendCents) / 100,
            limit: Double(monthlyLimitDollars),
            isUnlimited: isUnlimited,
            amountStyle: .wholeDollars,
            detailStyle: .dollarsWholeLimit
        )
    }

    var spendFormatted: String {
        UsageMath.formatDollars(reading.used)
    }

    var limitFormatted: String {
        if isUnlimited {
            return UsageMath.infinitySymbol
        }
        return "$\(monthlyLimitDollars)"
    }

    var spendPercentUsed: Double { reading.percentUsed }

    var spendPercentRemaining: Double { reading.percentRemaining }

    var isOverLimit: Bool { reading.isOverLimit }

    var detailText: String { reading.detailText }

    var isActive: Bool { isAuthenticated && isEnabled }

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
        session = UsageSession(provider: .cursor, keychain: keychain, preferences: preferences)
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
        spendCents = 0
        monthlyLimitDollars = 0
        isUnlimited = false
        userName = nil
        error = nil
        await WebAuthSession.clearAllWebsiteData()
    }

    func refresh() async {
        await session.run(
            load: { cookie in
                let summary = try await self.fetchUsageSummary(cookie: cookie)
                let name = self.userName == nil ? try await self.fetchMe(cookie: cookie).name : nil
                return CursorPayload(summary: summary, userName: name)
            },
            apply: { payload in
                self.apply(payload.summary)
                if let name = payload.userName {
                    self.userName = name
                }
            },
            unexpected: "Failed to load Cursor usage"
        )
    }

    private func apply(_ summary: CursorUsageSummaryResponse) {
        guard let overall = summary.individualUsage?.overall else { return }
        isUnlimited = summary.isUnlimited == true || overall.limit == nil
        spendCents = overall.used ?? 0
        monthlyLimitDollars = (overall.limit ?? 0) / 100
    }

    private func fetchUsageSummary(cookie: String) async throws -> CursorUsageSummaryResponse {
        let data = try await transport.data(
            for: UsageRequest(url: "https://cursor.com/api/usage-summary", cookieHeader: cookie)
        )
        return try JSONDecoder().decode(CursorUsageSummaryResponse.self, from: data)
    }

    private func fetchMe(cookie: String) async throws -> AuthMeResponse {
        let data = try await transport.data(
            for: UsageRequest(url: "https://www.cursor.com/api/auth/me", cookieHeader: cookie)
        )
        return try JSONDecoder().decode(AuthMeResponse.self, from: data)
    }

    private func startAutoRefresh() {
        refreshLoop.start { [weak self] in
            guard let self, self.isActive else { return }
            await self.refresh()
        }
    }
}

private struct CursorPayload {
    let summary: CursorUsageSummaryResponse
    let userName: String?
}

private struct AuthMeResponse: Decodable {
    let email: String?
    let name: String?
}
