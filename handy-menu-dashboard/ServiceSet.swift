import Foundation

struct ServiceSet {
    var cursor: CursorService
    var copilot: CopilotService
    var claude: ClaudeService
    var chatgpt: ChatGPTService
    var sessionUpdates: SessionUpdateCoordinator

    init(
        keychain: any KeychainStoring = KeychainStore(),
        dataLoader: @escaping UsageDataLoader = DefaultDataLoader.live,
        autoRefresh: Bool = true,
        preferences: any PreferenceStoring = UserDefaults.standard,
        browserReader: any BrowserCookieReading = LiveBrowserCookieReader(),
        notifier: (any SessionUpdateNotifying)? = nil
    ) {
        let notifier = notifier ?? UserNotificationsNotifier()
        let cursor = CursorService(
            keychain: keychain,
            dataLoader: dataLoader,
            autoRefresh: autoRefresh,
            preferences: preferences
        )
        let copilot = CopilotService(
            keychain: keychain,
            dataLoader: dataLoader,
            autoRefresh: autoRefresh,
            preferences: preferences
        )
        let claude = ClaudeService(
            keychain: keychain,
            dataLoader: dataLoader,
            autoRefresh: autoRefresh,
            preferences: preferences
        )
        let chatgpt = ChatGPTService(
            keychain: keychain,
            dataLoader: dataLoader,
            autoRefresh: autoRefresh,
            preferences: preferences
        )
        self.cursor = cursor
        self.copilot = copilot
        self.claude = claude
        self.chatgpt = chatgpt

        sessionUpdates = SessionUpdateCoordinator(
            resolve: { provider in
                switch provider {
                case .cursor: cursor
                case .copilot: copilot
                case .claude: claude
                case .chatgpt: chatgpt
                }
            },
            reader: browserReader,
            notifier: notifier,
            preferences: preferences,
            observe: autoRefresh
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
