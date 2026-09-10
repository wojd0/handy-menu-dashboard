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
    var isUnlimited = false
    var userName: String?

    private var cookieHeader: String?
    private let refreshLoop = RefreshLoop()
    private let keychain: any KeychainStoring
    private let dataLoader: UsageDataLoader

    static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/18.5 Safari/605.1.15"

    var spendFormatted: String {
        UsageMath.formatCentsAsDollars(spendCents)
    }

    var limitFormatted: String {
        if isUnlimited {
            return UsageMath.infinitySymbol
        }
        return "$\(monthlyLimitDollars)"
    }

    var spendPercentUsed: Double {
        UsageMath.spendPercentUsed(spendCents: spendCents, monthlyLimitDollars: monthlyLimitDollars)
    }

    var spendPercentRemaining: Double {
        UsageMath.percentRemaining(
            used: Double(spendCents),
            limit: Double(monthlyLimitDollars * 100)
        )
    }

    var isActive: Bool { isAuthenticated && isEnabled }

    var menuBarFragment: String {
        guard isActive else { return "" }
        return UsageMath.cursorMenuBarFragment(
            spendCents: spendCents,
            monthlyLimitDollars: monthlyLimitDollars,
            isUnlimited: isUnlimited
        )
    }

    func menuBarFragment(displayMode: MenuBarDisplayMode) -> String {
        guard isActive else { return "" }
        switch displayMode {
        case .monetary:
            return menuBarFragment
        case .percentUsed:
            return UsageMath.menuBarPercentFragment(percent: spendPercentUsed, isUnlimited: isUnlimited)
        case .percentRemaining:
            return UsageMath.menuBarPercentFragment(percent: spendPercentRemaining, isUnlimited: isUnlimited)
        }
    }

    init(
        keychain: any KeychainStoring = KeychainStore(),
        dataLoader: @escaping UsageDataLoader = DefaultDataLoader.live,
        autoRefresh: Bool = true
    ) {
        self.keychain = keychain
        self.dataLoader = dataLoader
        isEnabled = (UserDefaults.standard.object(forKey: "cursorEnabled") as? Bool) ?? true
        loadCredentials()
        if autoRefresh {
            startAutoRefresh()
        }
    }

    func saveCookies(_ cookies: [HTTPCookie]) {
        let header = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        guard !header.isEmpty else { return }
        keychain.saveString(key: .cursorCookies, value: header)
        cookieHeader = header
        isAuthenticated = true
        Task { await refresh() }
    }

    func clearCredentials() async {
        keychain.delete(key: .cursorCookies)
        cookieHeader = nil
        isAuthenticated = false
        spendCents = 0
        monthlyLimitDollars = 0
        isUnlimited = false
        userName = nil
        error = nil
        await WebAuthSession.clearAllWebsiteData()
    }

    func refresh() async {
        guard let cookieHeader, !cookieHeader.isEmpty else { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let summary = try await fetchUsageSummary(cookie: cookieHeader)
            guard self.cookieHeader == cookieHeader else { return }
            isAuthenticated = true

            if let overall = summary.individualUsage?.overall {
                isUnlimited = summary.isUnlimited == true || overall.limit == nil
                spendCents = overall.used ?? 0
                monthlyLimitDollars = (overall.limit ?? 0) / 100
            }

            if userName == nil {
                let me = try await fetchMe(cookie: cookieHeader)
                guard self.cookieHeader == cookieHeader else { return }
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
            (data, response) = try await dataLoader(request)
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
        refreshLoop.start { [weak self] in
            guard let self, self.isActive else { return }
            await self.refresh()
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
