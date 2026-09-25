import SwiftUI

struct ProviderLoginSheet: View {
    let provider: Provider
    let services: ServiceSet

    var body: some View {
        switch provider {
        case .cursor:
            CursorLoginView(cursorService: services.cursor)
        case .copilot:
            ValidatingLoginView(provider: .copilot) { await services.copilot.authenticate(with: $0) }
        case .claude:
            ClaudeLoginView(claudeService: services.claude)
        case .chatgpt:
            ValidatingLoginView(provider: .chatgpt) { await services.chatgpt.authenticate(with: $0) }
        }
    }
}
