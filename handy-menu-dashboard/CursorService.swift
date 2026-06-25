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

    var spendFormatted: String {
        let dollars = Double(spendCents) / 100.0
        return String(format: "$%.2f", dollars)
    }

    var limitFormatted: String {
        "$\(monthlyLimitDollars)"
    }

    var spendPercentUsed: Double {
        guard monthlyLimitDollars > 0 else { return 0 }
        return Double(spendCents) / Double(monthlyLimitDollars * 100) * 100
    }

    var isActive: Bool { isAuthenticated && isEnabled }

    var menuBarFragment: String {
        guard isActive else { return "" }
        let dollars = Int(Double(spendCents) / 100.0)
        return "$\(dollars)/\(monthlyLimitDollars)"
    }

    var menuBarPercentFragment: String {
        guard isActive else { return "" }
        return "\(Int(spendPercentUsed.rounded()))%"
    }

    init() {
        isEnabled = (UserDefaults.standard.object(forKey: "cursorEnabled") as? Bool) ?? true
        loadCredentials()
        startAutoRefresh()
    }

    func saveCookies(_ cookies: [HTTPCookie]) {
        let header = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        guard !header.isEmpty else { return }
        KeychainService.saveString(key: .cursorCookies, value: header)
        cookieHeader = header
        isAuthenticated = true
        Task { await refresh() }
    }

    func clearCredentials() {
        KeychainService.delete(key: .cursorCookies)
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

        do {
            if userEmail == nil {
                let me = try await fetchMe(cookie: cookieHeader)
                userEmail = me.email
                userName = me.name
            }
        } catch let error as ServiceError {
            handleServiceError(error)
            isLoading = false
            return
        } catch {
            self.error = "Failed to verify session"
            isLoading = false
            return
        }

        guard let email = userEmail else {
            self.error = "Could not determine user email"
            isLoading = false
            return
        }

        isAuthenticated = true

        do {
            let spend = try await fetchTeamSpend(cookie: cookieHeader)

            if let myEntry = spend.teamMemberSpend.first(where: { $0.email.lowercased() == email.lowercased() }) {
                monthlyLimitDollars = myEntry.effectivePerUserLimitDollars ?? myEntry.monthlyLimitDollars ?? 0
                if userName == nil { userName = myEntry.name }

                if let teamId = extractCookieValue(named: "team_id", from: cookieHeader).flatMap({ Int($0) }),
                   let userId = myEntry.resolvedUserId {
                    spendCents = try await fetchCurrentPeriodSpendCents(cookie: cookieHeader, teamId: teamId, userId: userId)
                } else {
                    spendCents = myEntry.spendCents ?? myEntry.overallSpendCents ?? 0
                }
            }
        } catch let error as ServiceError {
            switch error {
            case .authExpired:
                self.error = "Team spend access denied. Session may have expired."
            case .httpError(let code):
                self.error = "Team spend returned status \(code)"
            case .network:
                self.error = "Unable to connect to Cursor"
            case .invalidResponse:
                self.error = "Invalid team spend response"
            }
        } catch {
            self.error = "Failed to load team spend"
        }

        isLoading = false
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

    private func performRequest(url: String, cookie: String, method: String = "GET", body: Data? = nil) async throws(ServiceError) -> (Data, URLResponse) {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
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
        if let header = KeychainService.loadString(key: .cursorCookies), !header.isEmpty {
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

private struct TeamSpendResponse: Decodable {
    let teamMemberSpend: [TeamMember]

    struct TeamMember: Decodable {
        let name: String?
        let email: String
        let userId: FlexibleInt?
        let id: FlexibleInt?
        let user_id: FlexibleInt?
        let spendCents: Int?
        let overallSpendCents: Int?
        let monthlyLimitDollars: Int?
        let effectivePerUserLimitDollars: Int?

        var resolvedUserId: Int? {
            userId?.value ?? id?.value ?? user_id?.value
        }
    }
}

private struct FilteredUsageEventsResponse: Decodable {
    let totalUsageEventsCount: Int
    let usageEventsDisplay: [UsageEvent]

    struct UsageEvent: Decodable {
        let chargedCents: Double?
    }
}

private struct FlexibleInt: Decodable {
    let value: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let stringValue = try? container.decode(String.self) {
            value = Int(stringValue)
        } else {
            value = nil
        }
    }
}
