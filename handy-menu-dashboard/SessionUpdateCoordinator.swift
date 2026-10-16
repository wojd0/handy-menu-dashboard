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
    private(set) var isAutomaticallyUpdating = false
    private(set) var autoRenewProviders: Set<Provider>
    private var automaticUpdatesEnabled: Bool
    var source: BrowserCookieSource {
        didSet { source.save(to: preferences) }
    }

    @ObservationIgnored private let resolve: @MainActor (Provider) -> any UsageDisplaying
    @ObservationIgnored private let order: () -> [Provider]
    @ObservationIgnored private let reader: any BrowserCookieReading
    @ObservationIgnored private let notifier: any SessionUpdateNotifying
    @ObservationIgnored private let preferences: any PreferenceStoring
    @ObservationIgnored private let defaultBrowser: @MainActor () -> Browser?
    @ObservationIgnored private let automaticallyRefresh: Bool
    @ObservationIgnored private let refreshLoop = RefreshLoop()
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
        automaticallyRefresh = observe
        autoRenewProviders = AutomaticSessionPreferences.providers(in: preferences)
        automaticUpdatesEnabled = (preferences.object(forKey: AutomaticSessionPreferences.enabledKey) as? Bool) ?? true
        source = BrowserCookieSource.load(from: preferences)
        pending = computePending()
        notified = Set(pending.filter { !canAutomaticallyRenew($0) })
        if observe {
            observePending()
            refreshLoop.start { [weak self] in
                await self?.renewAutomatically()
            }
        }
    }

    var isHarvesting: Bool { phase == .harvesting || isAutomaticallyUpdating }

    var hasAutoRenewApprovals: Bool { !autoRenewProviders.isEmpty }

    var automaticallyUpdates: Bool {
        get { hasAutoRenewApprovals && automaticUpdatesEnabled }
        set {
            automaticUpdatesEnabled = newValue && hasAutoRenewApprovals
            preferences.set(automaticUpdatesEnabled, forKey: AutomaticSessionPreferences.enabledKey)
            if automaticallyRefresh && automaticallyUpdates {
                Task { [weak self] in await self?.renewAutomatically() }
            }
        }
    }

    func enableAutoRenew(_ providers: [Provider], profile: URL? = nil) {
        guard !providers.isEmpty else { return }
        autoRenewProviders.formUnion(providers)
        AutomaticSessionPreferences.setProviders(autoRenewProviders, in: preferences)
        if let browser = resolvedBrowser {
            AutomaticSessionPreferences.setProfile(profile, for: browser, in: preferences)
            for provider in providers {
                AutomaticSessionPreferences.setProfile(profile, for: browser, provider: provider, in: preferences)
            }
        }
        automaticallyUpdates = true
    }

    func disableAutoRenew(_ provider: Provider) {
        autoRenewProviders.remove(provider)
        AutomaticSessionPreferences.setProviders(autoRenewProviders, in: preferences)
        if !hasAutoRenewApprovals { automaticallyUpdates = false }
    }

    func savedProfile(for browser: Browser, provider: Provider? = nil) -> URL? {
        AutomaticSessionPreferences.profile(for: browser, provider: provider, in: preferences)
    }

    func approveAndAutoRenew(_ providers: [Provider], profile: URL? = nil) async {
        guard !isHarvesting else { return }
        let targets = providers.isEmpty ? pending : providers
        enableAutoRenew(targets, profile: profile)
        await approve(targets, profile: profile)
    }

    var resolvedBrowser: Browser? {
        source.resolved(defaultBrowser: defaultBrowser)
    }

    var onNotificationOpened: (() -> Void)? {
        get { notifier.onOpen }
        set { notifier.onOpen = newValue }
    }

    func refreshPending() {
        reconcile(with: computePending())
    }

    func approve(_ providers: [Provider], profile: URL? = nil) async {
        guard !isHarvesting else { return }
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
            cookies = try await reader.cookies(from: browser, profile: profile, matching: filters)
        } catch {
            phase = .finished(targets.reduce(into: [:]) { $0[$1] = Self.result(for: error) })
            return
        }

        await adoptEach(cookies.httpCookies, for: targets)
    }

    func adopt(_ cookies: [HTTPCookie], for providers: [Provider]) async {
        guard !isHarvesting else { return }
        phase = .harvesting
        await adoptEach(cookies, for: providers)
    }

    func skip() {
        guard phase != .harvesting else { return }
        phase = .idle
    }

    func renewAutomatically() async {
        guard !isHarvesting, automaticallyUpdates else { return }
        let targets = computePending().filter { canAutomaticallyRenew($0) }
        guard !targets.isEmpty else { return }

        isAutomaticallyUpdating = true
        defer { isAutomaticallyUpdating = false }
        let selectedSource = source
        guard let browser = resolvedBrowser else {
            notifyIfNeeded(computePending())
            return
        }
        let groups = Dictionary(grouping: targets) { savedProfile(for: browser, provider: $0) }
        for (profile, providers) in groups {
            guard !Task.isCancelled, source == selectedSource, automaticallyUpdates else { break }
            await renew(providers, from: browser, profile: profile, selectedSource: selectedSource)
        }
        refreshPending()
        notifyIfNeeded(pending)
    }

    private func renew(_ providers: [Provider], from browser: Browser, profile: URL?, selectedSource: BrowserCookieSource) async {
        let targets = providers.filter { canAutomaticallyRenew($0) && computePending().contains($0) }
        guard !targets.isEmpty else { return }
        let scoped = profile?.startAccessingSecurityScopedResource() ?? false
        defer { if scoped { profile?.stopAccessingSecurityScopedResource() } }

        do {
            let cookies = try await reader.cookies(
                from: browser, profile: profile, matching: targets.map { $0.harvest.domainMatch }, allowUserInteraction: false
            )
            for provider in targets {
                guard !Task.isCancelled, source == selectedSource,
                      canAutomaticallyRenew(provider), computePending().contains(provider) else { continue }
                let harvest = provider.harvest
                guard let sessionCookies = harvest.sessionCookies(from: cookies.httpCookies), !sessionCookies.isEmpty else { continue }
                _ = await resolve(provider).adoptBrowserCookies(sessionCookies, ifAllowed: {
                    !Task.isCancelled && self.source == selectedSource && self.resolvedBrowser == browser
                        && self.canAutomaticallyRenew(provider) && self.computePending().contains(provider)
                })
            }
        } catch {
            // Keep the session pending so the user can use the existing import or sign-in flow.
        }
    }

    private func canAutomaticallyRenew(_ provider: Provider) -> Bool {
        automaticallyUpdates && autoRenewProviders.contains(provider) && resolve(provider).isEnabled
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
            let manual = next.filter { !canAutomaticallyRenew($0) }
            notifyIfNeeded(manual)
            if automaticallyRefresh && !isHarvesting && next.contains(where: canAutomaticallyRenew) {
                Task { [weak self] in await self?.renewAutomatically() }
            }
        }
    }

    private func notifyIfNeeded(_ providers: [Provider]) {
        guard providers.contains(where: { !notified.contains($0) }) else { return }
        notified.formUnion(providers)
        Task { await notifier.notify(pending: providers) }
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
