import Foundation
import Observation

@Observable
final class ChatGPTService {
    typealias DataLoader = (URLRequest) async throws -> (Data, URLResponse)

    var isLoading = false
    var error: String?
    var isAuthenticated = false
    var isEnabled = true

    var currentMonthUsage: Double = 0
    var monthlyLimitCredits: Double = 0
    var enforcementMode: String?
    var limitMode: String?

    private var cookieHeader: String?
    private var refreshTask: Task<Void, Never>?
    private let keychain: any KeychainStoring
    private let dataLoader: DataLoader

    static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/18.5 Safari/605.1.15"

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
        dataLoader: @escaping DataLoader = { try await URLSession.shared.data(for: $0) },
        autoRefresh: Bool = true
    ) {
        self.keychain = keychain
        self.dataLoader = dataLoader
        isEnabled = (UserDefaults.standard.object(forKey: "chatgptEnabled") as? Bool) ?? true
        loadCredentials()
        if autoRefresh {
            startAutoRefresh()
        }
    }

    func saveCookies(_ cookies: [HTTPCookie]) {
        let header = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        guard !header.isEmpty, extractCookieValue(named: "_account", from: header) != nil else { return }
        keychain.saveString(key: .chatGPTCookies, value: header)
        cookieHeader = header
        isAuthenticated = true
        Task { await refresh() }
    }

    func clearCredentials() {
        keychain.delete(key: .chatGPTCookies)
        WebAuthSession.clearCookies(matching: "chatgpt.com")
        cookieHeader = nil
        isAuthenticated = false
        currentMonthUsage = 0
        monthlyLimitCredits = 0
        enforcementMode = nil
        limitMode = nil
        error = nil
    }

    func refresh() async {
        guard let cookieHeader, !cookieHeader.isEmpty else { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let accountCookie = try currentAccountID(from: cookieHeader)
            let accessToken = try await fetchAccessToken(cookieHeader: cookieHeader)
            let tokenAccount = try Self.accountID(fromJWT: accessToken)
            guard accountCookie == tokenAccount else {
                throw ServiceError.accountMismatch
            }

            let usage = try await fetchUsage(
                accountID: accountCookie,
                accessToken: accessToken,
                cookieHeader: cookieHeader
            )
            applyUsage(usage)
            isAuthenticated = true
        } catch let serviceError as ServiceError {
            handleServiceError(serviceError)
        } catch {
            self.error = "Invalid response from ChatGPT"
        }
    }

    static func accountID(fromJWT token: String) throws -> String {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else {
            throw ServiceError.invalidResponse
        }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)

        guard let data = Data(base64Encoded: payload) else {
            throw ServiceError.invalidResponse
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(TokenClaims.self, from: data).auth.chatgptAccountId
        } catch {
            throw ServiceError.invalidResponse
        }
    }

    private func currentAccountID(from cookieHeader: String) throws -> String {
        guard let accountID = extractCookieValue(named: "_account", from: cookieHeader),
              !accountID.isEmpty else {
            throw ServiceError.invalidResponse
        }
        return accountID
    }

    private func fetchAccessToken(cookieHeader: String) async throws -> String {
        let (data, _) = try await performRequest(
            url: "https://chatgpt.com/api/auth/session",
            cookieHeader: cookieHeader
        )

        do {
            let session = try JSONDecoder().decode(AuthSessionResponse.self, from: data)
            guard let accessToken = session.accessToken, !accessToken.isEmpty else {
                throw ServiceError.authExpired
            }
            return accessToken
        } catch let serviceError as ServiceError {
            throw serviceError
        } catch {
            throw ServiceError.invalidResponse
        }
    }

    private func fetchUsage(
        accountID: String,
        accessToken: String,
        cookieHeader: String
    ) async throws -> ChatGPTUsageResponse {
        let path = "https://chatgpt.com/backend-api/accounts/\(accountID)"
            + "/spend-controls/current-user/monthly-usage"
        let (data, _) = try await performRequest(
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
            throw ServiceError.invalidResponse
        }
    }

    private func applyUsage(_ response: ChatGPTUsageResponse) {
        currentMonthUsage = response.currentMonthUsage
        monthlyLimitCredits = response.effectiveMonthlyLimit.limit
        enforcementMode = response.effectiveMonthlyLimit.enforcementMode
        limitMode = response.effectiveMonthlyLimit.limitMode
    }

    private func performRequest(
        url: String,
        cookieHeader: String,
        accessToken: String? = nil,
        accountID: String? = nil
    ) async throws -> (Data, URLResponse) {
        guard let requestURL = URL(string: url) else {
            throw ServiceError.invalidResponse
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        if let accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-ID")
        }

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
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw ServiceError.authExpired
        }
        guard httpResponse.statusCode == 200 else {
            throw ServiceError.httpError(httpResponse.statusCode)
        }
        return (data, response)
    }

    private func extractCookieValue(named name: String, from cookieHeader: String) -> String? {
        for pair in cookieHeader.components(separatedBy: ";") {
            let parts = pair.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
            if parts.count == 2, parts[0] == name {
                return String(parts[1])
            }
        }
        return nil
    }

    private func handleServiceError(_ serviceError: ServiceError) {
        switch serviceError {
        case .authExpired, .accountMismatch:
            isAuthenticated = false
            error = "Session expired. Please sign in again."
        case .httpError(let code):
            error = "ChatGPT returned status \(code)"
        case .network:
            error = "Unable to connect to ChatGPT"
        case .invalidResponse:
            error = "Invalid response from ChatGPT"
        }
    }

    private func loadCredentials() {
        if let header = keychain.loadString(key: .chatGPTCookies), !header.isEmpty {
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
        case accountMismatch
        case httpError(Int)
        case network
        case invalidResponse
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
