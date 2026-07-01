import Foundation
import Observation

@Observable
final class CursorService {
    var isLoading = false
    var error: String?
    var isAuthenticated = false

    var isEnabled = true
    var spendCents: Int = 0
    var monthlyLimitDollars: Int = 0
    var userName: String?

    private var cookieHeader: String?
    private var refreshTask: Task<Void, Never>?
    private let keychain: any KeychainStoring

    static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/18.5 Safari/605.1.15"

    var spendFormatted: String {
        UsageMath.formatCentsAsDollars(spendCents)
    }

    var limitFormatted: String {
        "$\(monthlyLimitDollars)"
    }

    var spendPercentUsed: Double {
        UsageMath.spendPercentUsed(spendCents: spendCents, monthlyLimitDollars: monthlyLimitDollars)
    }

    var isActive: Bool { isAuthenticated && isEnabled }

    var menuBarFragment: String {
        guard isActive else { return "" }
        return UsageMath.cursorMenuBarFragment(spendCents: spendCents, monthlyLimitDollars: monthlyLimitDollars)
    }

    var menuBarPercentFragment: String {
        guard isActive else { return "" }
        return UsageMath.menuBarPercentFragment(percent: spendPercentUsed)
    }

    init(keychain: any KeychainStoring = KeychainStore()) {
        self.keychain = keychain
        isEnabled = (UserDefaults.standard.object(forKey: "cursorEnabled") as? Bool) ?? true
        loadCredentials()
        startAutoRefresh()
    }

    func saveCookies(_ cookies: [HTTPCookie]) {
        let header = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        guard !header.isEmpty else { return }
        keychain.saveString(key: .cursorCookies, value: header)
        cookieHeader = header
        isAuthenticated = true
        Task { await refresh() }
    }

    func clearCredentials() {
        keychain.delete(key: .cursorCookies)
        WebAuthSession.clearCookies(matching: "cursor.com")
        cookieHeader = nil
        isAuthenticated = false
        spendCents = 0
        monthlyLimitDollars = 0
        userName = nil
        error = nil
    }

    func refresh() async {
        guard let cookieHeader, !cookieHeader.isEmpty else { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let summary = try await fetchUsageSummary(cookie: cookieHeader)
            isAuthenticated = true

            if let overall = summary.individualUsage?.overall {
                spendCents = overall.used ?? 0
                monthlyLimitDollars = (overall.limit ?? 0) / 100
            }

            if userName == nil {
                let me = try await fetchMe(cookie: cookieHeader)
                userName = me.name
            }
        } catch let error as ServiceError {
            handleServiceError(error)
        } catch {
            self.error = "Failed to load Cursor usage"
        }
    }

    private func fetchUsageSummary(cookie: String) async throws -> CursorUsageSummaryResponse {
        let (data, _) = try await performRequest(url: "https://cursor.com/api/usage-summary", cookie: cookie)
        return try JSONDecoder().decode(CursorUsageSummaryResponse.self, from: data)
    }

    private func fetchMe(cookie: String) async throws -> AuthMeResponse {
        let (data, _) = try await performRequest(url: "https://www.cursor.com/api/auth/me", cookie: cookie)
        return try JSONDecoder().decode(AuthMeResponse.self, from: data)
    }

    private func performRequest(
        url: String,
        cookie: String
    ) async throws(ServiceError) -> (Data, URLResponse) {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "GET"
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")

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

    private func handleServiceError(_ error: ServiceError) {
        switch error {
        case .authExpired:
            isAuthenticated = false
            self.error = "Session expired. Please sign in again."
        case .httpError(let code):
            self.error = "Cursor returned status \(code)"
        case .network:
            self.error = "Unable to connect to Cursor"
        case .invalidResponse:
            self.error = "Invalid response from Cursor"
        }
    }

    private func loadCredentials() {
        if let header = keychain.loadString(key: .cursorCookies), !header.isEmpty {
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

private struct AuthMeResponse: Decodable {
    let email: String?
    let name: String?
}
