import Foundation
import Testing
@testable import handy_menu_dashboard

@Suite("Login flow")
struct LoginFlowTests {
    @Test func successfulValidationSignalsAuthentication() async {
        var authenticatedCalls = 0
        let flow = makeFlow { _ in .authenticated }
        flow.effects = LoginFlow.Effects(
            clearWebsiteData: { _ in },
            reload: {},
            authenticated: { authenticatedCalls += 1 }
        )

        await flow.harvested(makeCookies())

        #expect(flow.didAuthenticate)
        #expect(authenticatedCalls == 1)
        #expect(flow.errorMessage == nil)
        #expect(flow.isValidating == false)
    }

    @Test func nothingRevalidatesOnceAuthenticated() async {
        var calls = 0
        let flow = makeFlow { _ in
            calls += 1
            return .authenticated
        }

        await flow.harvested(makeCookies())
        await flow.harvested(makeCookies())

        #expect(calls == 1)
    }

    @Test func aStaleSessionClearsWebsiteDataBeforeReloading() async {
        var events: [String] = []
        var cleared: [[String]] = []
        let flow = makeFlow(provider: .chatgpt) { _ in .staleSession }
        flow.effects = LoginFlow.Effects(
            clearWebsiteData: { domains in
                events.append("clear")
                cleared.append(domains)
            },
            reload: { events.append("reload") }
        )

        await flow.harvested(makeCookies())

        #expect(events == ["clear", "reload"])
        #expect(cleared == [["chatgpt.com", "openai.com"]])
        #expect(flow.errorMessage == "Session expired. Please sign in again.")
        #expect(flow.didAuthenticate == false)
    }

    @Test func aStaleSessionDropsTheCookiesItCouldNotUse() async {
        let flow = makeFlow { _ in .staleSession }
        flow.effects = LoginFlow.Effects(clearWebsiteData: { _ in }, reload: {})

        await flow.harvested(makeCookies())

        #expect(flow.canReplayLastCookies == false)
    }

    @Test func aRecoverableFailureKeepsTheCookiesAndAllowsAnotherAttempt() async {
        var calls = 0
        let flow = makeFlow { _ in
            calls += 1
            return calls == 1 ? .failure("Unable to sign in to GitHub") : .authenticated
        }

        await flow.harvested(makeCookies())
        let messageAfterFailure = flow.errorMessage
        let replayable = flow.canReplayLastCookies
        await flow.harvested(makeCookies())

        #expect(messageAfterFailure == "Unable to sign in to GitHub")
        #expect(replayable)
        #expect(calls == 2)
        #expect(flow.didAuthenticate)
    }

    @Test func aFailureIgnoresCookieChangesUntilTheNextNavigation() async {
        var calls = 0
        let flow = makeFlow { _ in
            calls += 1
            return .failure("nope")
        }
        await flow.harvested(makeCookies())

        await flow.harvested(makeCookies(), fromCookieChange: true)
        let callsAfterCookieChange = calls
        await flow.harvested(makeCookies())

        #expect(callsAfterCookieChange == 1)
        #expect(calls == 2)
    }

    @Test func retryReplaysTheCookiesFromTheFailedAttempt() async {
        var calls = 0
        let flow = makeFlow { _ in
            calls += 1
            return calls == 1 ? .failure("nope") : .authenticated
        }
        await flow.harvested(makeCookies())

        let action = await flow.retry(attempt: 1)

        #expect(action == .replayed)
        #expect(calls == 2)
        #expect(flow.didAuthenticate)
    }

    @Test func retryAsksForFreshCookiesWhenThereAreNoneToReplay() async {
        let flow = makeFlow { _ in .authenticated }

        let action = await flow.retry(attempt: 1)

        #expect(action == .needsFreshCookies)
    }

    @Test func retryAfterAStaleSessionAsksForFreshCookies() async {
        let flow = makeFlow { _ in .staleSession }
        flow.effects = LoginFlow.Effects(clearWebsiteData: { _ in }, reload: {})
        await flow.harvested(makeCookies())

        let action = await flow.retry(attempt: 1)

        #expect(action == .needsFreshCookies)
    }

    @Test func theSameRetryAttemptIsHandledOnce() async {
        let flow = makeFlow { _ in .failure("nope") }
        await flow.harvested(makeCookies())

        let first = await flow.retry(attempt: 1)
        let second = await flow.retry(attempt: 1)

        #expect(first == .replayed)
        #expect(second == .none)
    }

    @Test func theInitialRetryAttemptIsAlreadyHandled() async {
        let flow = makeFlow { _ in .authenticated }

        let action = await flow.retry(attempt: 0)

        #expect(action == .none)
    }

    private func makeFlow(
        provider: Provider = .copilot,
        authenticate: @escaping ([HTTPCookie]) async -> LoginOutcome
    ) -> LoginFlow {
        LoginFlow(harvest: provider.harvest, authenticate: authenticate)
    }

    private func makeCookies() -> [HTTPCookie] {
        [
            HTTPCookie(properties: [
                .domain: ".github.com",
                .path: "/",
                .name: "user_session",
                .value: "test-session"
            ])!
        ]
    }
}
