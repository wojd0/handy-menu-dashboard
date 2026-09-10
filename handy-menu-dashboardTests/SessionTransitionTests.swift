import Testing
@testable import handy_menu_dashboard

@Suite("Session transition")
struct SessionTransitionTests {
    @Test func expiredSessionSignsOutEveryProvider() {
        let outcomes = Provider.allCases.map { outcome(for: .authExpired, provider: $0) }

        #expect(outcomes.allSatisfy { $0.state.isAuthenticated == false })
        #expect(outcomes.allSatisfy { $0.state.errorMessage == "Session expired. Please sign in again." })
    }

    @Test func onlyCopilotAndChatGPTDiscardTheCredentialOnAuthExpiry() {
        let discarding = Provider.allCases.filter { outcome(for: .authExpired, provider: $0).discardsCredential }

        #expect(discarding == [.copilot, .chatgpt])
    }

    @Test func httpFailureNamesTheProvider() {
        let messages = Provider.allCases.map { message(for: .httpError(503), provider: $0) }

        #expect(messages == [
            "Cursor returned status 503",
            "GitHub returned status 503",
            "Claude returned status 503",
            "ChatGPT returned status 503"
        ])
    }

    @Test func networkFailureNamesTheProvider() {
        let messages = Provider.allCases.map { message(for: .network, provider: $0) }

        #expect(messages == [
            "Unable to connect to Cursor",
            "Unable to connect to GitHub",
            "Unable to connect to Claude",
            "Unable to connect to ChatGPT"
        ])
    }

    @Test func invalidResponseNamesTheProvider() {
        let messages = Provider.allCases.map { message(for: .invalidResponse, provider: $0) }

        #expect(messages == [
            "Invalid response from Cursor",
            "Invalid response from GitHub",
            "Invalid response from Claude",
            "Invalid response from ChatGPT"
        ])
    }

    @Test func recoverableFailuresKeepTheSessionAndCredential() {
        let kinds: [UsageFailure.Kind] = [.httpError(503), .network, .invalidResponse]

        let outcomes = kinds.map { outcome(for: $0, provider: .copilot) }

        #expect(outcomes.allSatisfy { $0.state.isAuthenticated })
        #expect(outcomes.allSatisfy { !$0.discardsCredential })
    }

    @Test func recoverableFailureDoesNotResurrectASignedOutSession() {
        let result = outcome(for: .network, provider: .cursor, isAuthenticated: false)

        #expect(result.state.isAuthenticated == false)
        #expect(result.state.errorMessage == "Unable to connect to Cursor")
    }

    @Test func rejectionCarriesItsOwnMessageAndAlwaysDiscards() {
        let result = outcome(for: .rejected(CopilotService.noQuotaMessage), provider: .copilot)

        #expect(result.state.errorMessage == "No Copilot credit quota is available for this account.")
        #expect(result.state.isAuthenticated == false)
        #expect(result.discardsCredential)
    }

    private func outcome(
        for kind: UsageFailure.Kind,
        provider: Provider,
        isAuthenticated: Bool = true
    ) -> SessionOutcome {
        SessionTransition.apply(
            UsageFailure(kind: kind, provider: provider),
            to: SessionState(isAuthenticated: isAuthenticated, errorMessage: nil)
        )
    }

    private func message(for kind: UsageFailure.Kind, provider: Provider) -> String {
        SessionTransition.message(for: UsageFailure(kind: kind, provider: provider))
    }
}
