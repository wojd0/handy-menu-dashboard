import Observation

@MainActor
protocol UsageDisplaying: AnyObject, Observable {
    var provider: Provider { get }
    var isAuthenticated: Bool { get set }
    var isEnabled: Bool { get set }
    var menuBarDisplayMode: MenuBarDisplayMode { get set }
    var isLoading: Bool { get }
    var error: String? { get }
    var reading: UsageReading { get }
    var subtitle: String? { get }
    var menuBarText: String { get }
    var isActive: Bool { get }
    func refresh() async
    func clearCredentials() async
}

extension UsageDisplaying {
    var subtitle: String? { nil }
    var isActive: Bool { isAuthenticated && isEnabled }
}
