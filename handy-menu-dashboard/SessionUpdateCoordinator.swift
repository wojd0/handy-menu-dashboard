import Foundation
import Observation

@MainActor
@Observable
final class SessionUpdateCoordinator {
    enum HarvestResult: Equatable {
        case updated
        case notSignedInBrowser
        case rejected(String)
        case accessDenied
        case keyDenied
        case failed(String)
    }

    enum Phase: Equatable {
        case idle
        case harvesting
        case finished([Provider: HarvestResult])
    }

    private(set) var pending: [Provider] = []
    private(set) var phase: Phase = .idle
    var source: BrowserCookieSource {
        didSet { source.save(to: preferences) }
    }

    @ObservationIgnored private let resolve: @MainActor (Provider) -> any UsageDisplaying
    @ObservationIgnored private let order: () -> [Provider]
    @ObservationIgnored private let reader: any BrowserCookieReading
    @ObservationIgnored private let notifier: any SessionUpdateNotifying
    @ObservationIgnored private let preferences: any PreferenceStoring
    @ObservationIgnored private let defaultBrowser: @MainActor () -> Browser?
    @ObservationIgnored private var notified: Set<Provider> = []

    init(
        resolve: @escaping @MainActor (Provider) -> any UsageDisplaying,
        order: @escaping () -> [Provider] = { Provider.allCases },
        reader: any BrowserCookieReading,
        notifier: any SessionUpdateNotifying,
        preferences: any PreferenceStoring,
        defaultBrowser: @escaping @MainActor () -> Browser? = DefaultBrowser.current,
        observe: Bool = true
    ) {
        self.resolve = resolve
        self.order = order
        self.reader = reader
        self.notifier = notifier
        self.preferences = preferences
        self.defaultBrowser = defaultBrowser
        source = BrowserCookieSource.load(from: preferences)
        pending = computePending()
        notified = Set(pending)
        if observe {
            observePending()
        }
    }

    var resolvedBrowser: Browser? {
        source.resolved(defaultBrowser: defaultBrowser)
    }

    var onNotificationOpened: (() -> Void)? {
        get { notifier.onOpen }
        set { notifier.onOpen = newValue }
    }

    func reason(for provider: Provider) -> String {
        let service = resolve(provider)
        return service.credentialHeader == nil && service.error == nil ? "Not connected yet" : "Session expired"
    }

    func refreshPending() {
        reconcile(with: computePending())
    }

    func approve(_ providers: [Provider]) async {
        guard phase != .harvesting else { return }
        let targets = providers.isEmpty ? pending : providers
        guard !targets.isEmpty else {
            phase = .finished([:])
            return
        }

        phase = .harvesting

        guard let browser = resolvedBrowser else {
            phase = .finished(targets.reduce(into: [:]) { $0[$1] = .failed("No browser selected") })
            return
        }

        let filters = targets.map { $0.harvest.domainMatch }
        let cookies: [BrowserCookie]
        do {
            cookies = try await reader.cookies(from: browser, matching: filters)
        } catch {
            phase = .finished(targets.reduce(into: [:]) { $0[$1] = Self.result(for: error) })
            return
        }

        await adoptEach(cookies.httpCookies, for: targets)
    }

    func adopt(_ cookies: [HTTPCookie], for providers: [Provider]) async {
        guard phase != .harvesting else { return }
        phase = .harvesting
        await adoptEach(cookies, for: providers)
    }

    func skip() {
        guard phase != .harvesting else { return }
        phase = .idle
    }

    private func adoptEach(_ cookies: [HTTPCookie], for providers: [Provider]) async {
        var results: [Provider: HarvestResult] = [:]
        for provider in providers {
            let harvest = provider.harvest
            guard let sessionCookies = harvest.sessionCookies(from: cookies), !sessionCookies.isEmpty else {
                results[provider] = .notSignedInBrowser
                continue
            }
            results[provider] = Self.result(for: await resolve(provider).adoptBrowserCookies(sessionCookies))
        }
        phase = .finished(results)
        refreshPending()
    }

    private func computePending() -> [Provider] {
        order().filter { provider in
            let service = resolve(provider)
            return service.isEnabled && !service.isAuthenticated
        }
    }

    private func observePending() {
        let snapshot = withObservationTracking {
            computePending()
        } onChange: { [weak self] in
            guard let self else { return }
            Task { @MainActor [self] in self.pendingDidChange() }
        }
        reconcile(with: snapshot)
    }

    private func pendingDidChange() {
        observePending()
    }

    private func reconcile(with next: [Provider]) {
        let previous = Set(pending)
        let current = Set(next)
        pending = next

        notified.formIntersection(current)

        if current.isEmpty {
            Task { await notifier.clear() }
            return
        }

        let newlyPending = current.subtracting(notified).subtracting(previous)
        if !newlyPending.isEmpty {
            notified = current
            let toNotify = next
            Task { await notifier.notify(pending: toNotify) }
        }
    }

    private static func result(for outcome: LoginOutcome) -> HarvestResult {
        switch outcome {
        case .authenticated: .updated
        case .staleSession: .rejected("Session expired")
        case .failure(let message): .rejected(message)
        }
    }

    private static func result(for error: BrowserCookieError) -> HarvestResult {
        switch error {
        case .accessDenied: .accessDenied
        case .keyDenied: .keyDenied
        case .notInstalled: .failed("Browser not found")
        case .noProfile: .failed("No browser profile found")
        case .keyUnavailable: .failed("Could not read the browser encryption key")
        case .unreadable: .failed("Could not read the browser cookie store")
        }
    }
}
