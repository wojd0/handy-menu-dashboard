import Foundation

struct ServiceSet {
    var cursor: CursorService
    var copilot: CopilotService
    var claude: ClaudeService
    var chatgpt: ChatGPTService

    init(
        keychain: any KeychainStoring = KeychainStore(),
        dataLoader: @escaping UsageDataLoader = DefaultDataLoader.live,
        autoRefresh: Bool = true,
        preferences: any PreferenceStoring = UserDefaults.standard
    ) {
        cursor = CursorService(
            keychain: keychain,
            dataLoader: dataLoader,
            autoRefresh: autoRefresh,
            preferences: preferences
        )
        copilot = CopilotService(
            keychain: keychain,
            dataLoader: dataLoader,
            autoRefresh: autoRefresh,
            preferences: preferences
        )
        claude = ClaudeService(
            keychain: keychain,
            dataLoader: dataLoader,
            autoRefresh: autoRefresh,
            preferences: preferences
        )
        chatgpt = ChatGPTService(
            keychain: keychain,
            dataLoader: dataLoader,
            autoRefresh: autoRefresh,
            preferences: preferences
        )
    }

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
