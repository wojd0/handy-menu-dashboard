import Foundation
import Observation

enum ChatGPTAuthenticationResult: Equatable {
    case authenticated
    case staleSession
    case failure(String)
}

@Observable
final class ChatGPTService {
    var isLoading = false
    var error: String?
    var isAuthenticated = false
    var isEnabled = true

    var currentMonthUsage: Double = 0
    var monthlyLimitCredits: Double = 0
    var enforcementMode: String?
    var limitMode: String?

    private var cookieHeader: String?
    private let refreshLoop = RefreshLoop()
    private let keychain: any KeychainStoring
    private let transport: UsageTransport

    static let websiteDataDomains = ["chatgpt.com", "openai.com"]

    var percentUsed: Double {
        UsageMath.percentUsed(used: currentMonthUsage, limit: monthlyLimitCredits)
    }

    var percentRemaining: Double {
        UsageMath.percentRemaining(used: currentMonthUsage, limit: monthlyLimitCredits)
    }

    var isOverLimit: Bool {
        UsageMath.isOverLimit(percentUsed: percentUsed)
    }

    var isActive: Bool {
        isAuthenticated && isEnabled
    }

    var detailText: String {
        "\(UsageMath.formatCredits(currentMonthUsage)) / "
            + "\(UsageMath.formatCredits(monthlyLimitCredits)) credits"
    }

    var menuBarFragment: String {
        guard isActive else { return "" }
        return UsageMath.chatGPTCreditsFragment(used: currentMonthUsage, limit: monthlyLimitCredits)
    }

    func menuBarFragment(displayMode: MenuBarDisplayMode) -> String {
        guard isActive else { return "" }
        switch displayMode {
        case .monetary:
            return menuBarFragment
        case .percentUsed:
            return UsageMath.menuBarPercentFragment(percent: percentUsed)
        case .percentRemaining:
            return UsageMath.menuBarPercentFragment(percent: percentRemaining)
        }
    }

    init(
        keychain: any KeychainStoring = KeychainStore(),
        dataLoader: @escaping UsageDataLoader = DefaultDataLoader.live,
        autoRefresh: Bool = true
    ) {
        self.keychain = keychain
        transport = UsageTransport(dataLoader: dataLoader)
        isEnabled = (UserDefaults.standard.object(forKey: "chatgptEnabled") as? Bool) ?? true
        loadCredentials()
        if autoRefresh {
            startAutoRefresh()
        }
    }

    func authenticate(with cookies: [HTTPCookie]) async -> ChatGPTAuthenticationResult {
        let header = CookieHeader.header(from: cookies)
        guard !header.isEmpty, CookieHeader.value(named: "_account", in: header) != nil else {
            let message = "Invalid response from ChatGPT"
            error = message
            return .failure(message)
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let usage = try await loadUsage(cookieHeader: header)
            keychain.saveString(key: .chatGPTCookies, value: header)
            cookieHeader = header
            applyUsage(usage)
            isAuthenticated = true
            return .authenticated
        } catch let kind as UsageFailure.Kind {
            handleFailure(kind)
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
        keychain.delete(key: .chatGPTCookies)
        cookieHeader = nil
        isAuthenticated = false
        currentMonthUsage = 0
        monthlyLimitCredits = 0
        enforcementMode = nil
        limitMode = nil
        error = nil
        await WebAuthSession.clearAllWebsiteData()
    }

    func refresh() async {
        guard let cookieHeader, !cookieHeader.isEmpty else { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let usage = try await loadUsage(cookieHeader: cookieHeader)
            guard self.cookieHeader == cookieHeader else { return }
            applyUsage(usage)
            isAuthenticated = true
        } catch let kind as UsageFailure.Kind {
            handleFailure(kind)
        } catch {
            self.error = "Invalid response from ChatGPT"
        }
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

    private func handleFailure(_ kind: UsageFailure.Kind) {
        let outcome = SessionTransition.apply(
            UsageFailure(kind: kind, provider: .chatgpt),
            to: SessionState(isAuthenticated: isAuthenticated, errorMessage: error)
        )
        isAuthenticated = outcome.state.isAuthenticated
        error = outcome.state.errorMessage
        if outcome.discardsCredential {
            keychain.delete(key: .chatGPTCookies)
            cookieHeader = nil
        }
    }

    private func loadCredentials() {
        if let header = keychain.loadString(key: .chatGPTCookies), !header.isEmpty {
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
