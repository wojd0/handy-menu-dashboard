import Testing
@testable import handy_menu_dashboard

@Suite("Provider ordering")
struct ProviderTests {
    @Test func appendsChatGPTToPreviouslyStoredOrder() {
        let providers = Provider.ordered(from: "cursor,copilot,claude")

        #expect(providers.contains(.chatgpt))
        #expect(providers.last == .chatgpt)
    }

    @Test func preservesExplicitChatGPTPosition() {
        let raw = "chatgpt,claude,cursor,copilot"

        #expect(Provider.raw(from: Provider.ordered(from: raw)) == raw)
    }
}
