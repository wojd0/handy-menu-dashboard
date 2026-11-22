import Foundation
import Observation

enum AntigravityUsagePool: Hashable {
    case mostUsed
    case group(name: String, windowIDs: [String])

    var label: String {
        switch self {
        case .mostUsed: "Most Used"
        case .group(let name, _): name
        }
    }

    func resolve(in groups: [AntigravityQuotaResponse.Group]) -> AntigravityQuotaResponse.Group? {
        guard case .group(let name, let windowIDs) = self else { return nil }
        let ids = Set(windowIDs)
        return groups.first { !ids.isDisjoint(with: $0.windows.map(\.id)) }
            ?? groups.first { $0.name == name }
    }
}

enum AntigravityPoolRange: Hashable {
    case mostUsed
    case period(String)

    var label: String {
        switch self {
        case .mostUsed: "Most Used"
        case .period(let period): AntigravityQuotaResponse.Window.periodLabel(period)
        }
    }
}

@Observable
final class AntigravityService: UsageDisplaying {
    static let origin = "https://antigravity.google.com"
    static let quotaURL = "https://aicode.clients6.google.com/$rpc/"
        + "google.gca.aicode.v1alpha.JetskiRemoteAgentProxyService/GetUserQuotaSummary"
    static let apiKey = "AIzaSyCUicsvglkMf8CM2MPlGjopIcIxu3VJEDU"

    let provider = Provider.antigravity

    var isEnabled: Bool {
        get { session.isEnabled }
        set { session.isEnabled = newValue }
    }

    var menuBarDisplayMode: MenuBarDisplayMode {
        get { session.menuBarDisplayMode }
        set { session.menuBarDisplayMode = newValue }
    }

    var menuBarText: String { menuBarFragment(displayMode: menuBarDisplayMode) }

    var groups: [AntigravityQuotaResponse.Group] = []

    var usagePool: AntigravityUsagePool {
        get { storedUsagePool }
        set {
            storedUsagePool = newValue
            ProviderPreferences.setAntigravityUsagePool(newValue, in: preferences)
        }
    }

    var poolRange: AntigravityPoolRange {
        get { storedPoolRange }
        set {
            storedPoolRange = newValue
            ProviderPreferences.setAntigravityPoolRange(newValue, in: preferences)
        }
    }

    private var storedUsagePool: AntigravityUsagePool
    private var storedPoolRange: AntigravityPoolRange

    @ObservationIgnored private let preferences: any PreferenceStoring
    @ObservationIgnored private let session: UsageSession
    @ObservationIgnored private let refreshLoop = RefreshLoop()
    @ObservationIgnored private let transport: UsageTransport
    @ObservationIgnored private let now: () -> Date

    var isLoading: Bool { session.isLoading }

    var isAuthenticated: Bool {
        get { session.isAuthenticated }
        set { session.isAuthenticated = newValue }
    }

    var error: String? {
        get { session.errorMessage }
        set { session.errorMessage = newValue }
    }

    var availableUsagePools: [AntigravityUsagePool] {
        [.mostUsed] + groups.map(\.usagePool)
    }

    var resolvedUsagePool: AntigravityUsagePool {
        usagePool.resolve(in: groups)?.usagePool ?? .mostUsed
    }

    func windows(for usagePool: AntigravityUsagePool) -> [AntigravityQuotaResponse.Window] {
        switch usagePool {
        case .mostUsed: groups.flatMap(\.windows)
        case .group: usagePool.resolve(in: groups)?.windows ?? []
        }
    }

    var availablePoolRanges: [AntigravityPoolRange] {
        var seen = Set<String>()
        let periods = windows(for: resolvedUsagePool).map(\.rangeKey).filter { seen.insert($0).inserted }
        return [.mostUsed] + periods.map(AntigravityPoolRange.period)
    }

    var resolvedPoolRange: AntigravityPoolRange {
        availablePoolRanges.contains(poolRange) ? poolRange : .mostUsed
    }

    var menuBarWindow: AntigravityQuotaResponse.Window? {
        let range = resolvedPoolRange
        return windows(for: resolvedUsagePool)
            .filter { range == .mostUsed || range == .period($0.rangeKey) }
            .max { $0.percentUsed < $1.percentUsed }
    }

    var reading: UsageReading {
        UsageReading(
            used: menuBarWindow?.percentUsed ?? 0,
            limit: menuBarWindow == nil ? 0 : 100,
            amountStyle: .percent,
            detailStyle: .percent
        )
    }

    var isActive: Bool { isAuthenticated && isEnabled }

    func menuBarFragment(displayMode: MenuBarDisplayMode) -> String {
        guard isActive else { return "" }
        return reading.menuBarText(displayMode)
    }

    init(
        keychain: any KeychainStoring = KeychainStore(),
        dataLoader: @escaping UsageDataLoader = DefaultDataLoader.live,
        autoRefresh: Bool = true,
        preferences: any PreferenceStoring = UserDefaults.standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.preferences = preferences
        storedUsagePool = ProviderPreferences.antigravityUsagePool(in: preferences)
        storedPoolRange = ProviderPreferences.antigravityPoolRange(in: preferences)
        session = UsageSession(provider: .antigravity, keychain: keychain, preferences: preferences)
        transport = UsageTransport(dataLoader: dataLoader)
        self.now = now
        session.loadStoredCredential()
        if autoRefresh {
            startAutoRefresh()
        }
    }

    var credentialHeader: String? { session.cookieHeader }

    func adoptBrowserCookies(_ cookies: [HTTPCookie], ifAllowed: @escaping @MainActor () -> Bool = { true }) async -> LoginOutcome {
        await authenticate(with: cookies, ifAllowed: ifAllowed)
    }

    func authenticate(with cookies: [HTTPCookie]) async -> LoginOutcome {
        await authenticate(with: cookies, ifAllowed: { true })
    }

    private func authenticate(with cookies: [HTTPCookie], ifAllowed: @MainActor () -> Bool) async -> LoginOutcome {
        guard ifAllowed() else { return .failure("Session update cancelled") }
        let host = URL(string: Self.quotaURL)?.host ?? ""
        let header = CookieHeader.header(from: GoogleSessionAuthorization.sentCookies(cookies, to: host))
        guard CookieHeader.value(named: "SAPISID", in: header) != nil else {
            let message = "No Google session found"
            error = message
            return .failure(message)
        }

        session.isLoading = true
        error = nil
        defer { session.isLoading = false }

        do {
            let quota = try await loadQuota(cookieHeader: header)
            guard ifAllowed() else { return .failure("Session update cancelled") }
            session.persist(header)
            applyQuota(quota)
            return .authenticated
        } catch let kind as UsageFailure.Kind {
            guard ifAllowed() else { return .failure("Session update cancelled") }
            session.absorb(kind)
            switch kind {
            case .authExpired:
                return .staleSession
            case .rejected, .httpError, .network, .invalidResponse:
                return .failure(error ?? "Unable to sign in to Antigravity")
            }
        } catch {
            guard ifAllowed() else { return .failure("Session update cancelled") }
            let message = "Invalid response from Antigravity"
            self.error = message
            return .failure(message)
        }
    }

    func clearCredentials() async {
        session.discardCredential()
        groups = []
        error = nil
        await WebAuthSession.clearAllWebsiteData()
    }

    func refresh() async {
        await session.run(
            load: { try await self.loadQuota(cookieHeader: $0) },
            apply: { self.applyQuota($0) },
            unexpected: "Invalid response from Antigravity"
        )
    }

    private func loadQuota(cookieHeader: String) async throws -> AntigravityQuotaResponse {
        let timestamp = Int(now().timeIntervalSince1970)
        guard let authorization = GoogleSessionAuthorization.header(
            cookieHeader: cookieHeader,
            origin: Self.origin,
            timestamp: timestamp
        ) else {
            throw UsageFailure.Kind.authExpired
        }

        let data = try await transport.data(
            for: UsageRequest(
                url: Self.quotaURL,
                cookieHeader: cookieHeader,
                headers: [
                    "Accept": "*/*",
                    "Content-Type": "application/json+protobuf",
                    "Authorization": authorization,
                    "Origin": Self.origin,
                    "X-Goog-Api-Key": Self.apiKey,
                    "X-Goog-AuthUser": "0",
                    "X-User-Agent": "grpc-web-javascript/0.1"
                ],
                method: "POST",
                body: Data("[]".utf8)
            )
        )

        do {
            return try JSONDecoder().decode(AntigravityQuotaResponse.self, from: data)
        } catch {
            throw UsageFailure.Kind.invalidResponse
        }
    }

    private func applyQuota(_ response: AntigravityQuotaResponse) {
        groups = response.groups.filter { !$0.windows.isEmpty }.map(\.sessionFirst)
    }

    private func startAutoRefresh() {
        refreshLoop.start { [weak self] in
            guard let self, self.session.refreshesOnTick else { return }
            await self.refresh()
        }
    }
}

extension AntigravityQuotaResponse.Group {
    var usagePool: AntigravityUsagePool {
        .group(name: name, windowIDs: windows.map(\.id))
    }

    var sessionFirst: Self {
        let ordered = windows.enumerated().sorted {
            ($0.element.periodRank, $0.offset) < ($1.element.periodRank, $1.offset)
        }
        return Self(name: name, windows: ordered.map(\.element))
    }
}

extension AntigravityQuotaResponse.Window {
    static func periodLabel(_ period: String) -> String {
        switch period {
        case "5h": "Session (5h)"
        case "weekly": "Weekly"
        default: period.capitalized
        }
    }

    var rangeKey: String { period ?? id }

    var periodRank: Int {
        switch period {
        case "5h": 0
        case "weekly": 1
        default: 2
        }
    }

    var title: String {
        switch period {
        case "5h", "weekly": Self.periodLabel(rangeKey)
        default: label ?? id
        }
    }
}
