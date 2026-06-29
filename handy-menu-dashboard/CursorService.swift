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
    private var userEmail: String?
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
        userEmail = nil
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
            let email = try await verifiedUserEmail(cookie: cookieHeader)
            let spend = try await fetchTeamSpend(cookie: cookieHeader)

            if let myEntry = spend.teamMemberSpend.first(where: { $0.email.lowercased() == email.lowercased() }) {
                monthlyLimitDollars = myEntry.effectivePerUserLimitDollars ?? myEntry.monthlyLimitDollars ?? 0
                if userName == nil { userName = myEntry.name }
                spendCents = try await resolvedSpendCents(for: myEntry, cookie: cookieHeader)
            }
        } catch let error as ServiceError {
            handleServiceError(error)
        } catch {
            self.error = "Failed to load Cursor usage"
        }
    }

    private func fetchMe(cookie: String) async throws -> AuthMeResponse {
        let (data, _) = try await performRequest(url: "https://www.cursor.com/api/auth/me", cookie: cookie)
        return try JSONDecoder().decode(AuthMeResponse.self, from: data)
    }

    private func fetchTeamSpend(cookie: String) async throws -> TeamSpendResponse {
        guard let teamId = extractCookieValue(named: "team_id", from: cookie) else {
            throw ServiceError.invalidResponse
        }
        let body = ["teamId": Int(teamId) ?? 0] as [String: Any]
        let jsonBody = try? JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await performRequest(
            url: "https://cursor.com/api/dashboard/get-team-spend",
            cookie: cookie,
            method: "POST",
            body: jsonBody
        )
        return try JSONDecoder().decode(TeamSpendResponse.self, from: data)
    }

    private func verifiedUserEmail(cookie: String) async throws -> String {
        if userEmail == nil {
            let me = try await fetchMe(cookie: cookie)
            userEmail = me.email
            userName = me.name
        }

        guard let email = userEmail else {
            throw ServiceError.invalidResponse
        }

        isAuthenticated = true
        return email
    }

    private func resolvedSpendCents(for member: TeamSpendResponse.TeamMember, cookie: String) async throws -> Int {
        if let teamId = extractCookieValue(named: "team_id", from: cookie).flatMap({ Int($0) }),
           let userId = member.resolvedUserId {
            return try await fetchCurrentPeriodSpendCents(cookie: cookie, teamId: teamId, userId: userId)
        }

        return member.spendCents ?? member.overallSpendCents ?? 0
    }

    private func fetchCurrentPeriodSpendCents(cookie: String, teamId: Int, userId: Int) async throws -> Int {
        let (startDate, endDate) = currentPeriodRangeMilliseconds()
        let pageSize = 1000
        var page = 1
        var totalCents = 0.0

        while true {
            let body: [String: Any] = [
                "teamId": teamId,
                "startDate": startDate,
                "endDate": endDate,
                "userId": userId,
                "page": page,
                "pageSize": pageSize
            ]
            let jsonBody = try? JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await performRequest(
                url: "https://cursor.com/api/dashboard/get-filtered-usage-events",
                cookie: cookie,
                method: "POST",
                body: jsonBody
            )
            let response = try JSONDecoder().decode(FilteredUsageEventsResponse.self, from: data)

            totalCents += response.usageEventsDisplay.reduce(0.0) { $0 + ($1.chargedCents ?? 0) }

            if response.usageEventsDisplay.isEmpty || page * pageSize >= response.totalUsageEventsCount {
                break
            }
            page += 1
        }

        return Int(totalCents.rounded())
    }

    private func currentPeriodRangeMilliseconds() -> (start: String, end: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let now = Date()
        let monthComponents = calendar.dateComponents([.year, .month], from: now)
        let startOfMonth = calendar.date(from: monthComponents) ?? now

        let startMs = Int64(startOfMonth.timeIntervalSince1970 * 1000)
        let endMs = Int64(now.timeIntervalSince1970 * 1000)

        return (String(startMs), String(endMs))
    }

    private func extractCookieValue(named name: String, from cookieHeader: String) -> String? {
        for pair in cookieHeader.components(separatedBy: "; ") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 && parts[0] == name {
                return String(parts[1])
            }
        }
        return nil
    }

    private func performRequest(
        url: String,
        cookie: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws(ServiceError) -> (Data, URLResponse) {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
            request.setValue("https://cursor.com/dashboard/usage", forHTTPHeaderField: "Referer")
        }

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
