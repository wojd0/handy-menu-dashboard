import Testing
@testable import handy_menu_dashboard

@Suite("Provider ordering")
struct ProviderTests {
    @Test func appendsChatGPTToPreviouslyStoredOrder() {
        let providers = Provider.ordered(from: "cursor,copilot,claude")

        #expect(providers == [.cursor, .copilot, .claude, .chatgpt, .antigravity])
    }

    @Test func appendsAntigravityToPreviouslyStoredOrder() {
        let providers = Provider.ordered(from: "chatgpt,claude,cursor,copilot")

        #expect(providers.last == .antigravity)
    }

    @Test func preservesExplicitChatGPTPosition() {
        let raw = "chatgpt,antigravity,claude,cursor,copilot"

        #expect(Provider.raw(from: Provider.ordered(from: raw)) == raw)
    }
}
