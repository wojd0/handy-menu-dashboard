import Foundation

enum AppRuntime {
    static let testHostEnvironmentKey = "HANDY_MENU_DASHBOARD_TEST_HOST"

    static func isTestHost(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment[testHostEnvironmentKey] == "1"
    }

    static func makeServices(environment: [String: String] = ProcessInfo.processInfo.environment) -> ServiceSet {
        guard isTestHost(environment: environment) else { return ServiceSet() }

        return ServiceSet(
            keychain: DisabledKeychainStore(),
            autoRefresh: false,
            browserReader: DisabledBrowserCookieReader(),
            notifier: DisabledNotifier()
        )
    }
}
