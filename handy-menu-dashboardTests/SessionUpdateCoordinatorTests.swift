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

    @Test func aNeverConnectedProviderReadsAsNotConnected() {
        let harness = setupTest(Config())

        #expect(harness.coordinator.reason(for: .chatgpt) == "Not connected yet")
    }

    @Test func aDiscardedCopilotSessionReadsAsExpired() async {
        let harness = setupTest(Config(dataLoader: unauthorizedLoader, preauthenticated: [.copilot]))

        await harness.services.copilot.refresh()

        #expect(harness.services.copilot.credentialHeader == nil)
        #expect(harness.coordinator.reason(for: .copilot) == "Session expired")
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

    private var cursorLoader: UsageDataLoader {
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

    private var unauthorizedLoader: UsageDataLoader {
        { request in try httpResponse(for: request, status: 401, json: [:]) }
    }

    private func setupTest(_ config: Config) -> Harness {
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
            autoRefresh: false,
            preferences: InMemoryPreferenceStore(stored),
            browserReader: config.reader ?? reader,
            notifier: notifier
        )

        return Harness(services: services, reader: reader, notifier: notifier)
    }
}
