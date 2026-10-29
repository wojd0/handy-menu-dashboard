import Foundation
import Testing
@testable import handy_menu_dashboard

@MainActor
@Suite("Session update coordinator")
struct SessionUpdateCoordinatorTests {
    struct Config {
        var cookies: [BrowserCookie] = []
        var readerFailure: BrowserCookieError?
        var dataLoader: UsageDataLoader = { _ in throw NetworkFailure() }
        var preauthenticated: [Provider] = []
        var enabled: [Provider] = Provider.allCases
        var source: Browser = .firefox
        var reader: (any BrowserCookieReading)?
        var preferences: InMemoryPreferenceStore?
        var autoRefresh = false
    }

    struct Harness {
        let services: ServiceSet
        let reader: FakeBrowserCookieReader
        let notifier: RecordingNotifier
        var coordinator: SessionUpdateCoordinator { services.sessionUpdates }
    }

    @Test func nothingIsReadFromTheBrowserBeforeApproval() {
        let harness = setupTest(Config())

        harness.coordinator.refreshPending()

        #expect(harness.reader.callCount == 0)
        #expect(harness.coordinator.pending == [.cursor, .copilot, .claude, .chatgpt])
    }

    @Test func approveAdoptsCursorFromTheBrowserSession() async {
        let harness = setupTest(Config(
            cookies: [BrowserCookie(domain: ".cursor.com", name: "WorkosCursorSessionToken", value: "tok")],
            dataLoader: cursorLoader
        ))

        await harness.coordinator.approve([.cursor])

        let cursorUpdated = harness.coordinator.phase == .finished([.cursor: .updated])
        #expect(cursorUpdated)
        #expect(harness.services.cursor.isAuthenticated)
        #expect(!harness.coordinator.pending.contains(.cursor))
    }

    @Test func approvalPassesTheSelectedProfileToTheReader() async {
        let harness = setupTest(Config())
        let profile = URL(fileURLWithPath: "/test/Profiles/work")
        await harness.coordinator.approve([.chatgpt], profile: profile)
        #expect(harness.reader.selectedProfile == profile)
    }

    @Test func aCopilotRejectionLeavesItPending() async {
        let harness = setupTest(Config(
            cookies: [BrowserCookie(domain: ".github.com", name: "user_session", value: "tok")],
            dataLoader: unauthorizedLoader
        ))

        await harness.coordinator.approve([.copilot])

        guard case let .finished(results) = harness.coordinator.phase else {
            Issue.record("expected finished phase")
            return
        }
        if case .rejected = results[.copilot] {} else {
            Issue.record("expected copilot rejection")
        }
        #expect(harness.coordinator.pending.contains(.copilot))
    }

    @Test func aMissingBrowserSessionReportsNotSignedIn() async {
        let harness = setupTest(Config(
            cookies: [BrowserCookie(domain: ".cursor.com", name: "theme", value: "dark")]
        ))

        await harness.coordinator.approve([.cursor])

        #expect(harness.coordinator.phase == .finished([.cursor: .notSignedInBrowser]))
    }

    @Test func blockedAccessReportsAccessDenied() async {
        let harness = setupTest(Config(readerFailure: .accessDenied))

        await harness.coordinator.approve([.cursor])

        #expect(harness.coordinator.phase == .finished([.cursor: .accessDenied]))
    }

    @Test func neverConnectedProvidersAreNotPendingUntilEnabled() {
        let harness = setupTest(Config(enabled: []))

        let pendingBefore = harness.coordinator.pending
        harness.services.claude.isEnabled = true
        harness.coordinator.refreshPending()

        #expect(pendingBefore.isEmpty)
        #expect(harness.coordinator.pending == [.claude])
    }

    @Test func approvingADisabledProviderEnablesItOnceUpdated() async {
        let harness = setupTest(Config(
            cookies: [BrowserCookie(domain: ".cursor.com", name: "WorkosCursorSessionToken", value: "tok")],
            dataLoader: cursorLoader,
            enabled: []
        ))

        await harness.coordinator.approve([.cursor])

        #expect(harness.coordinator.phase == .finished([.cursor: .updated]))
        #expect(harness.services.cursor.isEnabled)
        #expect(harness.services.cursor.isActive)
    }

    @Test func aSecondApprovalWhileHarvestingIsIgnored() async {
        let reader = GatedBrowserCookieReader()
        let harness = setupTest(Config(reader: reader))

        let first = Task { await harness.coordinator.approve([.cursor]) }
        while reader.callCount == 0 { await Task.yield() }
        await harness.coordinator.approve([.cursor])
        let callsWhileHarvesting = reader.callCount
        reader.release()
        await first.value

        #expect(callsWhileHarvesting == 1)
        #expect(harness.coordinator.phase == .finished([.cursor: .notSignedInBrowser]))
    }

    @Test func skipKeepsThePendingProviders() {
        let harness = setupTest(Config())

        harness.coordinator.skip()

        #expect(harness.coordinator.pending == [.cursor, .copilot, .claude, .chatgpt])
    }

    @Test func aNewlyPendingProviderIsNotifiedExactlyOnce() async {
        let harness = setupTest(Config(preauthenticated: [.cursor, .copilot, .claude, .chatgpt]))

        harness.services.cursor.isAuthenticated = false
        harness.coordinator.refreshPending()
        harness.coordinator.refreshPending()
        for _ in 0..<4 { await Task.yield() }

        #expect(harness.notifier.notifications.count == 1)
        #expect(harness.notifier.notifications.first == [.cursor])
    }

    @Test func aDisabledProviderDropsOutOfPending() {
        let harness = setupTest(Config())

        harness.services.chatgpt.isEnabled = false
        harness.coordinator.refreshPending()

        #expect(!harness.coordinator.pending.contains(.chatgpt))
    }

    @Test func automaticUpdatesRequireExplicitApproval() async {
        let harness = setupTest(Config())

        await harness.coordinator.renewAutomatically()
        harness.coordinator.automaticallyUpdates = true
        await harness.coordinator.renewAutomatically()

        #expect(!harness.coordinator.hasAutoRenewApprovals)
        #expect(!harness.coordinator.automaticallyUpdates)
        #expect(harness.reader.callCount == 0)
    }

    @Test func aOneTimeApprovalDoesNotEnableAutoRenew() async {
        let harness = setupTest(Config())

        await harness.coordinator.approve([.cursor])
        await harness.coordinator.renewAutomatically()

        #expect(harness.coordinator.autoRenewProviders.isEmpty)
        #expect(harness.reader.callCount == 1)
    }

    @Test func approvalAndAutoRenewImportsAndRemembersConsent() async {
        let harness = setupTest(Config(cookies: cursorCookies, dataLoader: cursorLoader))
        let profile = URL(fileURLWithPath: "/test/Profiles/work")

        await harness.coordinator.approveAndAutoRenew([.cursor], profile: profile)

        #expect(harness.services.cursor.isAuthenticated)
        #expect(harness.coordinator.phase == .finished([.cursor: .updated]))
        #expect(harness.coordinator.autoRenewProviders == [.cursor])
        #expect(harness.coordinator.automaticallyUpdates)
        #expect(harness.coordinator.savedProfile(for: .firefox) == profile)
    }

    @Test func autoRenewRefreshesOnlyApprovedPendingEnabledProviders() async {
        let harness = setupTest(Config(cookies: cursorCookies, dataLoader: cursorLoader))
        harness.coordinator.enableAutoRenew([.cursor, .claude])
        harness.services.claude.isEnabled = false

        await harness.coordinator.renewAutomatically()

        #expect(harness.services.cursor.isAuthenticated)
        #expect(harness.reader.filters == [Provider.cursor.harvest.domainMatch])
        #expect(harness.coordinator.phase == .idle)
        #expect(!harness.services.copilot.isAuthenticated)
        #expect(!harness.services.claude.isAuthenticated)
        await harness.coordinator.renewAutomatically()
        #expect(harness.reader.callCount == 1)
    }

    @Test func automaticRenewalUsesTheSavedBrowserProfile() async {
        let harness = setupTest(Config())
        let profile = URL(fileURLWithPath: "/test/Profiles/work")
        harness.coordinator.enableAutoRenew([.cursor], profile: profile)

        await harness.coordinator.renewAutomatically()

        #expect(harness.reader.selectedProfile == profile)
        #expect(harness.reader.selectedBrowser == .firefox)
        #expect(!harness.reader.allowedUserInteraction)
    }

    @Test func eachAgentKeepsItsApprovedProfile() async {
        let harness = setupTest(Config())
        let first = URL(fileURLWithPath: "/test/Profiles/work")
        let second = URL(fileURLWithPath: "/test/Profiles/personal")
        harness.coordinator.enableAutoRenew([.cursor], profile: first)
        harness.coordinator.enableAutoRenew([.claude], profile: second)

        await harness.coordinator.renewAutomatically()

        #expect(Set(harness.reader.profiles.compactMap { $0 }) == [first, second])
        #expect(harness.reader.callCount == 2)
    }

    @Test func globalDisablePreservesApprovalsAndCanResume() async {
        let harness = setupTest(Config(cookies: cursorCookies, dataLoader: cursorLoader))
        harness.coordinator.enableAutoRenew([.cursor])
        harness.coordinator.automaticallyUpdates = false

        await harness.coordinator.renewAutomatically()

        #expect(harness.reader.callCount == 0)
        #expect(harness.coordinator.hasAutoRenewApprovals)
        #expect(harness.coordinator.autoRenewProviders == [.cursor])
        harness.coordinator.automaticallyUpdates = true
        await harness.coordinator.renewAutomatically()
        #expect(harness.services.cursor.isAuthenticated)
    }

    @Test func disablingAnAgentForgetsConsentAndDisablesTheLastGlobalCheckbox() async {
        let harness = setupTest(Config())
        harness.coordinator.enableAutoRenew([.cursor, .claude])
        harness.coordinator.disableAutoRenew(.cursor)
        #expect(harness.coordinator.autoRenewProviders == [.claude])
        #expect(harness.coordinator.automaticallyUpdates)

        harness.coordinator.disableAutoRenew(.claude)
        await harness.coordinator.renewAutomatically()

        #expect(!harness.coordinator.hasAutoRenewApprovals)
        #expect(!harness.coordinator.automaticallyUpdates)
        #expect(harness.reader.callCount == 0)
    }

    @Test func consentAndGlobalPauseSurviveRelaunch() {
        let preferences = InMemoryPreferenceStore([BrowserCookieSource.storageKey: Browser.firefox.rawValue])
        let harness = setupTest(Config(preferences: preferences))
        let profile = URL(fileURLWithPath: "/test/Profiles/work")
        harness.coordinator.enableAutoRenew([.cursor], profile: profile)
        harness.coordinator.automaticallyUpdates = false

        let relaunched = setupTest(Config(preferences: preferences))
        #expect(relaunched.coordinator.autoRenewProviders == [.cursor])
        #expect(!relaunched.coordinator.automaticallyUpdates)
        #expect(relaunched.coordinator.savedProfile(for: .firefox) == profile)

        relaunched.coordinator.disableAutoRenew(.cursor)
        let afterRevocation = setupTest(Config(preferences: preferences))
        #expect(afterRevocation.coordinator.autoRenewProviders.isEmpty)
    }

    @Test func failedAutomaticUpdatesRemainPendingAndDoNotRepeatNotifications() async {
        let harness = setupTest(Config(readerFailure: .accessDenied, preauthenticated: [.cursor], enabled: [.cursor]))
        harness.coordinator.enableAutoRenew([.cursor])
        harness.services.cursor.isAuthenticated = false
        harness.coordinator.refreshPending()

        await harness.coordinator.renewAutomatically()
        await harness.coordinator.renewAutomatically()
        for _ in 0..<4 { await Task.yield() }

        #expect(harness.coordinator.pending == [.cursor])
        #expect(harness.coordinator.phase == .idle)
        #expect(harness.reader.callCount == 2)
        #expect(harness.notifier.notifications == [[.cursor]])
    }

    @Test(arguments: ["agent", "global", "provider", "browser"])
    func disablingDuringABrowserReadPreventsAdoption(change: String) async {
        let reader = GatedBrowserCookieReader(cookies: cursorCookies)
        let harness = setupTest(Config(dataLoader: cursorLoader, reader: reader))
        harness.coordinator.enableAutoRenew([.cursor])
        let renewal = Task { await harness.coordinator.renewAutomatically() }
        while reader.callCount == 0 { await Task.yield() }

        switch change {
        case "agent": harness.coordinator.disableAutoRenew(.cursor)
        case "global": harness.coordinator.automaticallyUpdates = false
        case "provider": harness.services.cursor.isEnabled = false
        default: harness.coordinator.source = .browser(.chrome)
        }
        await harness.coordinator.approve([.cursor])
        reader.release()
        await renewal.value

        #expect(reader.callCount == 1)
        #expect(!harness.services.cursor.isAuthenticated)
        #expect(harness.services.cursor.credentialHeader == nil)
        #expect(!harness.coordinator.isHarvesting)
    }

    @Test func disablingDuringValidationPreventsSavingTheSession() async {
        var onValidation: () -> Void = {}
        let harness = setupTest(Config(
            cookies: [BrowserCookie(domain: ".github.com", name: "user_session", value: "tok")],
            dataLoader: { request in
                onValidation()
                return try httpResponse(for: request, json: [
                    "quotas": ["premium_interactions_quota": ["total": 100, "used": 5, "has_quota": true]]
                ])
            },
            enabled: [.copilot]
        ))
        harness.coordinator.enableAutoRenew([.copilot])
        onValidation = { harness.coordinator.disableAutoRenew(.copilot) }

        await harness.coordinator.renewAutomatically()
        onValidation = {}

        #expect(!harness.services.copilot.isAuthenticated)
        #expect(harness.services.copilot.credentialHeader == nil)
        #expect(!harness.coordinator.automaticallyUpdates)
    }

    @Test func observedAuthenticationExpiryAutomaticallyRenewsWithoutOpeningADialog() async {
        let authenticatedLoader = cursorLoader
        let loader: UsageDataLoader = { request in
            if request.value(forHTTPHeaderField: "Cookie") == "preloaded=1" {
                return try httpResponse(for: request, status: 401, json: [:])
            }
            return try await authenticatedLoader(request)
        }
        let harness = setupTest(Config(
            cookies: cursorCookies, dataLoader: loader,
            preauthenticated: [.cursor], enabled: [.cursor], autoRefresh: true
        ))
        harness.coordinator.enableAutoRenew([.cursor])
        harness.services.cursor.isAuthenticated = false

        for _ in 0..<1_000 {
            if harness.reader.callCount > 0 && harness.services.cursor.isAuthenticated { break }
            await Task.yield()
        }

        #expect(harness.reader.callCount > 0)
        #expect(harness.services.cursor.isAuthenticated)
        #expect(harness.coordinator.phase == .idle)
        #expect(harness.notifier.notifications.isEmpty)
    }
}

private extension SessionUpdateCoordinatorTests {
    var cursorCookies: [BrowserCookie] {
        [BrowserCookie(domain: ".cursor.com", name: "WorkosCursorSessionToken", value: "tok")]
    }

    var cursorLoader: UsageDataLoader {
        { request in
            if request.url!.path == "/api/auth/me" {
                return try httpResponse(for: request, json: ["email": "a@b.c", "name": "Ada"])
            }
            return try httpResponse(for: request, json: [
                "isUnlimited": false,
                "individualUsage": ["overall": ["enabled": true, "used": 5_000, "limit": 160_000]]
            ])
        }
    }

    var unauthorizedLoader: UsageDataLoader {
        { request in try httpResponse(for: request, status: 401, json: [:]) }
    }

    func setupTest(_ config: Config) -> Harness {
        let keychain = InMemoryKeychainStore()
        for provider in config.preauthenticated {
            keychain.saveString(key: provider.keychainKey, value: "preloaded=1")
        }

        let reader = FakeBrowserCookieReader(cookies: config.cookies, failure: config.readerFailure)
        let notifier = RecordingNotifier()
        var stored: [String: Any] = [BrowserCookieSource.storageKey: config.source.rawValue]
        for provider in config.enabled {
            stored[provider.enabledKey] = true
        }

        let services = ServiceSet(
            keychain: keychain,
            dataLoader: config.dataLoader,
            autoRefresh: config.autoRefresh,
            preferences: config.preferences ?? InMemoryPreferenceStore(stored),
            browserReader: config.reader ?? reader,
            notifier: notifier
        )

        return Harness(services: services, reader: reader, notifier: notifier)
    }
}
