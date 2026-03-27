import Foundation
import Observation

@Observable
final class CopilotService {
    var isLoading = false
    var error: String?
    var isAuthenticated = false

    var isEnabled = true
    var totalUsed: Int = 0
    var monthlyEntitlement: Int = 300
    var percentUsed: Double = 0
    var isOverLimit: Bool = false

    var username: String = ""
    private var pat: String = ""
    private var refreshTask: Task<Void, Never>?

    var isActive: Bool { isAuthenticated && isEnabled }

    var menuBarFragment: String {
        guard isActive else { return "" }
        return "\(totalUsed)/\(monthlyEntitlement)"
    }

    init() {
        isEnabled = (UserDefaults.standard.object(forKey: "copilotEnabled") as? Bool) ?? true
        loadCredentials()
        startAutoRefresh()
    }

    func saveCredentials(username: String, pat: String) {
        guard !username.isEmpty, !pat.isEmpty else { return }
        self.username = username
        self.pat = pat
        KeychainService.saveString(key: .copilotUsername, value: username)
        KeychainService.saveString(key: .copilotPAT, value: pat)
        isAuthenticated = true
        Task { await refresh() }
    }

    func saveEntitlement(_ value: Int) {
        monthlyEntitlement = value
        KeychainService.saveString(key: .copilotEntitlement, value: String(value))
        recalculate()
    }

    func clearCredentials() {
        KeychainService.delete(key: .copilotUsername)
        KeychainService.delete(key: .copilotPAT)
        username = ""
        pat = ""
        isAuthenticated = false
        totalUsed = 0
        percentUsed = 0
        isOverLimit = false
        error = nil
    }

    func refresh() async {
        guard !username.isEmpty, !pat.isEmpty else { return }

        isLoading = true
        error = nil

        do {
            let now = Calendar.current.dateComponents([.year, .month], from: Date())
            guard let year = now.year, let month = now.month else {
                error = "Failed to determine current date"
                isLoading = false
                return
            }

            var components = URLComponents(string: "https://api.github.com/users/\(username)/settings/billing/premium_request/usage")!
            components.queryItems = [
                URLQueryItem(name: "year", value: String(year)),
                URLQueryItem(name: "month", value: String(month))
            ]

            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                error = "Invalid response from GitHub"
                isLoading = false
                return
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                isAuthenticated = false
                error = "Authentication failed. Check your PAT."
                isLoading = false
                return
            }

            guard httpResponse.statusCode == 200 else {
                error = "GitHub returned status \(httpResponse.statusCode)"
                isLoading = false
                return
            }

            let usageResponse = try JSONDecoder().decode(CopilotUsageResponse.self, from: data)
            totalUsed = usageResponse.usageItems.reduce(0) { $0 + $1.grossQuantity }
            recalculate()
            isAuthenticated = true
        } catch {
            self.error = "Failed to load Copilot usage"
        }

        isLoading = false
    }

    private func recalculate() {
        percentUsed = monthlyEntitlement > 0 ? Double(totalUsed) / Double(monthlyEntitlement) * 100 : 0
        isOverLimit = percentUsed > 100
    }

    private func loadCredentials() {
        if let savedUsername = KeychainService.loadString(key: .copilotUsername),
           let savedPAT = KeychainService.loadString(key: .copilotPAT),
           !savedUsername.isEmpty, !savedPAT.isEmpty {
            username = savedUsername
            pat = savedPAT
            isAuthenticated = true
        }
        if let savedEntitlement = KeychainService.loadString(key: .copilotEntitlement),
           let value = Int(savedEntitlement) {
            monthlyEntitlement = value
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
}

private struct CopilotUsageResponse: Decodable {
    let usageItems: [UsageItem]

    struct UsageItem: Decodable {
        let grossQuantity: Int
    }
}
