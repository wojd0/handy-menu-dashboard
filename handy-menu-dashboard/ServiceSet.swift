import Foundation

struct ServiceSet {
    var cursor = CursorService()
    var copilot = CopilotService()
    var claude = ClaudeService()
    var chatgpt = ChatGPTService()

    subscript(provider: Provider) -> any UsageDisplaying {
        switch provider {
        case .cursor: cursor
        case .copilot: copilot
        case .claude: claude
        case .chatgpt: chatgpt
        }
    }

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await cursor.refresh() }
            group.addTask { await copilot.refresh() }
            group.addTask { await claude.refresh() }
            group.addTask { await chatgpt.refresh() }
        }
    }
}
