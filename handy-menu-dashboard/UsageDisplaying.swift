import Foundation
import Observation

@MainActor
protocol UsageDisplaying: AnyObject, Observable {
    var provider: Provider { get }
    var isAuthenticated: Bool { get set }
    var isEnabled: Bool { get set }
    var menuBarDisplayMode: MenuBarDisplayMode { get set }
    var hiddenUsageBars: Set<String> { get set }
    var usageBars: [UsageBar] { get }
    var isLoading: Bool { get }
    var error: String? { get }
    var reading: UsageReading { get }
    var subtitle: String? { get }
    var menuBarText: String { get }
    var isActive: Bool { get }
    var credentialHeader: String? { get }
    func refresh() async
    func clearCredentials() async
    func adoptBrowserCookies(_ cookies: [HTTPCookie], ifAllowed: @escaping @MainActor () -> Bool) async -> LoginOutcome
}

extension UsageDisplaying {
    func adoptBrowserCookies(_ cookies: [HTTPCookie]) async -> LoginOutcome {
        await adoptBrowserCookies(cookies, ifAllowed: { true })
    }

    var subtitle: String? { nil }
    var usageBars: [UsageBar] { [.primary] }

    func showsUsageBar(_ id: String) -> Bool {
        !hiddenUsageBars.contains(id)
    }

    var showsAnyUsageBar: Bool {
        usageBars.isEmpty || usageBars.contains { showsUsageBar($0.id) }
    }

    func setUsageBar(_ id: String, shown: Bool) {
        if shown {
            hiddenUsageBars.remove(id)
        } else {
            hiddenUsageBars.insert(id)
        }
    }
    var isActive: Bool { isAuthenticated && isEnabled }
}
