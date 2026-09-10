import Foundation
import Testing
@testable import handy_menu_dashboard

@Suite("Usage session")
struct UsageSessionTests {
    @Test func storedCredentialIsAdoptedOnLoad() {
        let keychain = InMemoryKeychainStore()
        keychain.saveString(key: .cursorCookies, value: "s=1")
        let session = makeSession(keychain: keychain)

        session.loadStoredCredential()

        #expect(session.isAuthenticated)
        #expect(session.isCurrent("s=1"))
    }

    @Test func anEmptyStoredCredentialIsIgnored() {
        let keychain = InMemoryKeychainStore()
        keychain.saveString(key: .cursorCookies, value: "")
        let session = makeSession(keychain: keychain)

        session.loadStoredCredential()

        #expect(session.isAuthenticated == false)
    }

    @Test func persistWritesToTheKeychainAndAuthenticates() {
        let keychain = InMemoryKeychainStore()
        let session = makeSession(keychain: keychain)

        session.persist("s=1")

        #expect(keychain.loadString(key: .cursorCookies) == "s=1")
        #expect(session.isAuthenticated)
    }

    @Test func isCurrentComparesTheLiveCredential() {
        let session = makeSession()
        session.adopt("first")

        #expect(session.isCurrent("first"))
        #expect(session.isCurrent("second") == false)

        session.discardCredential()

        #expect(session.isCurrent("first") == false)
    }

    @Test func runAppliesThePayloadAndClearsThePreviousError() async {
        let session = makeSession()
        session.adopt("s=1")
        session.errorMessage = "stale error"
        var applied: Int?

        await session.run(load: { _ in 42 }, apply: { applied = $0 }, unexpected: "unexpected")

        #expect(applied == 42)
        #expect(session.errorMessage == nil)
        #expect(session.isAuthenticated)
        #expect(session.isLoading == false)
    }

    @Test func runDoesNothingWithoutACredential() async {
        let session = makeSession()
        var applied = false

        await session.run(load: { _ in 1 }, apply: { _ in applied = true }, unexpected: "unexpected")

        #expect(applied == false)
        #expect(session.isLoading == false)
    }

    @Test func runDiscardsAResponseThatArrivesAfterTheCredentialChanged() async {
        let session = makeSession()
        session.adopt("first")
        var applied = false

        await session.run(
            load: { _ in
                session.adopt("second")
                return 1
            },
            apply: { _ in applied = true },
            unexpected: "unexpected"
        )

        #expect(applied == false)
    }

    @Test func runMapsAnUnrecognisedErrorToItsOwnMessage() async {
        let session = makeSession()
        session.adopt("s=1")

        await session.run(
            load: { _ -> Int in throw NetworkFailure() },
            apply: { _ in },
            unexpected: "Failed to load Cursor usage"
        )

        #expect(session.errorMessage == "Failed to load Cursor usage")
        #expect(session.isAuthenticated)
    }

    @Test func retainingProvidersKeepTheCredentialThroughAuthExpiry() {
        let keychain = InMemoryKeychainStore()
        let session = makeSession(provider: .cursor, keychain: keychain)
        session.persist("s=1")

        session.absorb(.authExpired)

        #expect(session.isAuthenticated == false)
        #expect(session.errorMessage == "Session expired. Please sign in again.")
        #expect(keychain.loadString(key: .cursorCookies) == "s=1")
        #expect(session.isCurrent("s=1"))
    }

    @Test func discardingProvidersDropTheCredentialThroughAuthExpiry() {
        let keychain = InMemoryKeychainStore()
        let session = makeSession(provider: .copilot, keychain: keychain)
        session.persist("s=1")

        session.absorb(.authExpired)

        #expect(session.isAuthenticated == false)
        #expect(session.errorMessage == "Session expired. Please sign in again.")
        #expect(keychain.loadString(key: .copilotCookies) == nil)
        #expect(session.isCurrent("s=1") == false)
    }

    @Test func recoverableFailuresNeverTouchTheCredential() {
        let keychain = InMemoryKeychainStore()
        let session = makeSession(provider: .copilot, keychain: keychain)
        session.persist("s=1")

        session.absorb(.httpError(503))

        #expect(session.isAuthenticated)
        #expect(session.errorMessage == "GitHub returned status 503")
        #expect(keychain.loadString(key: .copilotCookies) == "s=1")
    }

    @Test func purgeLegacyRemovesSupersededKeys() {
        let keychain = InMemoryKeychainStore()
        keychain.saveString(key: .copilotPAT, value: "pat")
        keychain.saveString(key: .copilotUsername, value: "octocat")
        let session = makeSession(provider: .copilot, keychain: keychain)

        session.purgeLegacy(CopilotService.legacyKeys)

        #expect(keychain.loadString(key: .copilotPAT) == nil)
        #expect(keychain.loadString(key: .copilotUsername) == nil)
    }

    private func makeSession(
        provider: Provider = .cursor,
        keychain: any KeychainStoring = InMemoryKeychainStore()
    ) -> UsageSession {
        UsageSession(provider: provider, keychain: keychain)
    }
}
