import Foundation
import Observation

@Observable
final class ChatGPTService: UsageDisplaying {
    let provider = Provider.chatgpt

    var isEnabled: Bool {
        get { session.isEnabled }
        set { session.isEnabled = newValue }
    }

    var menuBarDisplayMode: MenuBarDisplayMode {
        get { session.menuBarDisplayMode }
        set { session.menuBarDisplayMode = newValue }
    }

    var menuBarText: String { menuBarFragment(displayMode: menuBarDisplayMode) }

    var currentMonthUsage: Double = 0
    var monthlyLimitCredits: Double = 0
    var enforcementMode: String?
    var limitMode: String?

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
            used: currentMonthUsage,
            limit: monthlyLimitCredits,
            amountStyle: .compactCredits,
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
        session = UsageSession(provider: .chatgpt, keychain: keychain, preferences: preferences)
        transport = UsageTransport(dataLoader: dataLoader)
        session.loadStoredCredential()
        if autoRefresh {
            startAutoRefresh()
        }
    }

    func authenticate(with cookies: [HTTPCookie]) async -> LoginOutcome {
        let header = CookieHeader.header(from: cookies)
        guard !header.isEmpty, CookieHeader.value(named: "_account", in: header) != nil else {
            let message = "Invalid response from ChatGPT"
            error = message
            return .failure(message)
        }

        session.isLoading = true
        error = nil
        defer { session.isLoading = false }

        do {
            let usage = try await loadUsage(cookieHeader: header)
            session.persist(header)
            applyUsage(usage)
            return .authenticated
        } catch let kind as UsageFailure.Kind {
            session.absorb(kind)
            switch kind {
            case .authExpired:
                return .staleSession
            case .rejected, .httpError, .network, .invalidResponse:
                return .failure(error ?? "Unable to sign in to ChatGPT")
            }
        } catch {
            let message = "Invalid response from ChatGPT"
            self.error = message
            return .failure(message)
        }
    }

    func clearCredentials() async {
        session.discardCredential()
        currentMonthUsage = 0
        monthlyLimitCredits = 0
        enforcementMode = nil
        limitMode = nil
        error = nil
        await WebAuthSession.clearAllWebsiteData()
    }

    func refresh() async {
        await session.run(
            load: { try await self.loadUsage(cookieHeader: $0) },
            apply: { self.applyUsage($0) },
            unexpected: "Invalid response from ChatGPT"
        )
    }

    private func loadUsage(cookieHeader: String) async throws -> ChatGPTUsageResponse {
        let accountCookie = try currentAccountID(from: cookieHeader)
        let accessToken = try await fetchAccessToken(cookieHeader: cookieHeader)
        let tokenAccount = try Self.accountID(fromJWT: accessToken)
        guard accountCookie == tokenAccount else {
            throw UsageFailure.Kind.authExpired
        }

        return try await fetchUsage(
            accountID: accountCookie,
            accessToken: accessToken,
            cookieHeader: cookieHeader
        )
    }

    static func accountID(fromJWT token: String) throws -> String {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else {
            throw UsageFailure.Kind.invalidResponse
        }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)

        guard let data = Data(base64Encoded: payload) else {
            throw UsageFailure.Kind.invalidResponse
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(TokenClaims.self, from: data).auth.chatgptAccountId
        } catch {
            throw UsageFailure.Kind.invalidResponse
        }
    }

    private func currentAccountID(from cookieHeader: String) throws -> String {
        guard let accountID = CookieHeader.value(named: "_account", in: cookieHeader),
              !accountID.isEmpty else {
            throw UsageFailure.Kind.invalidResponse
        }
        return accountID
    }

    private func fetchAccessToken(cookieHeader: String) async throws -> String {
        let data = try await request(
            url: "https://chatgpt.com/api/auth/session",
            cookieHeader: cookieHeader
        )

        do {
            let session = try JSONDecoder().decode(AuthSessionResponse.self, from: data)
            guard let accessToken = session.accessToken, !accessToken.isEmpty else {
                throw UsageFailure.Kind.authExpired
            }
            return accessToken
        } catch let kind as UsageFailure.Kind {
            throw kind
        } catch {
            throw UsageFailure.Kind.invalidResponse
        }
    }

    private func fetchUsage(
        accountID: String,
        accessToken: String,
        cookieHeader: String
    ) async throws -> ChatGPTUsageResponse {
        let path = "https://chatgpt.com/backend-api/accounts/\(accountID)"
            + "/spend-controls/current-user/monthly-usage"
        let data = try await request(
            url: path,
            cookieHeader: cookieHeader,
            accessToken: accessToken,
            accountID: accountID
        )

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(ChatGPTUsageResponse.self, from: data)
        } catch {
            throw UsageFailure.Kind.invalidResponse
        }
    }

    private func applyUsage(_ response: ChatGPTUsageResponse) {
        currentMonthUsage = response.currentMonthUsage
        monthlyLimitCredits = response.effectiveMonthlyLimit.limit
        enforcementMode = response.effectiveMonthlyLimit.enforcementMode
        limitMode = response.effectiveMonthlyLimit.limitMode
    }

    private func request(
        url: String,
        cookieHeader: String,
        accessToken: String? = nil,
        accountID: String? = nil
    ) async throws(UsageFailure.Kind) -> Data {
        var headers = ["Accept": "application/json"]
        if let accessToken {
            headers["Authorization"] = "Bearer \(accessToken)"
        }
        if let accountID {
            headers["ChatGPT-Account-ID"] = accountID
        }
        return try await transport.data(
            for: UsageRequest(url: url, cookieHeader: cookieHeader, headers: headers)
        )
    }

    private func startAutoRefresh() {
        refreshLoop.start { [weak self] in
            guard let self, self.isActive else { return }
            await self.refresh()
        }
    }
}

private struct AuthSessionResponse: Decodable {
    let accessToken: String?
}

private struct TokenAuthClaims: Decodable {
    let chatgptAccountId: String
}

private struct TokenClaims: Decodable {
    let auth: TokenAuthClaims

    enum CodingKeys: String, CodingKey {
        case auth = "https://api.openai.com/auth"
    }
}
