import SwiftUI

@main
struct HandyMenuDashboardApp: App {
    @State private var cursorService = CursorService()
    @State private var copilotService = CopilotService()
    @State private var claudeService = ClaudeService()
    @State private var chatGPTService = ChatGPTService()
    @AppStorage("menuBarInserted") private var menuBarInserted = true

    init() {
        MenuBarDisplayMode.migrateLegacyPreferences()
    }

    var body: some Scene {
        MenuBarExtra(isInserted: $menuBarInserted) {
            DashboardView(
                cursorService: cursorService,
                copilotService: copilotService,
                claudeService: claudeService,
                chatGPTService: chatGPTService
            )
        } label: {
            MenuBarLabel(
                cursorService: cursorService,
                copilotService: copilotService,
                claudeService: claudeService,
                chatGPTService: chatGPTService
            )
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Settings", id: "settings") {
            SettingsView(
                cursorService: cursorService,
                copilotService: copilotService,
                claudeService: claudeService,
                chatGPTService: chatGPTService
            )
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

struct MenuBarLabel: View {
    var cursorService: CursorService
    var copilotService: CopilotService
    var claudeService: ClaudeService
    var chatGPTService: ChatGPTService
    @AppStorage("cursorMenuBarShowPercent") private var cursorDisplayMode = MenuBarDisplayMode.monetary
    @AppStorage("copilotMenuBarShowPercent") private var copilotDisplayMode = MenuBarDisplayMode.monetary
    @AppStorage("claudeMenuBarShowPercent") private var claudeDisplayMode = MenuBarDisplayMode.monetary
    @AppStorage("claudeMenuBarBaseline") private var claudeBaseline = ClaudeBaseline.usageLimit
    @AppStorage("chatgptMenuBarShowPercent") private var chatGPTDisplayMode = MenuBarDisplayMode.monetary
    @AppStorage(Provider.orderStorageKey) private var providerOrderRaw = Provider.defaultOrderRaw
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let lines = Provider.ordered(from: providerOrderRaw)
            .map(fragment(for:))
            .filter { !$0.isEmpty }

        if let image = renderImage(lines: lines) {
            Image(nsImage: image)
        } else {
            Text("Usage")
                .font(.caption2)
        }
    }

    private func fragment(for provider: Provider) -> String {
        switch provider {
        case .cursor:
            cursorService.menuBarFragment(displayMode: cursorDisplayMode)
        case .copilot:
            copilotService.menuBarFragment(displayMode: copilotDisplayMode)
        case .claude:
            claudeService.menuBarFragment(baseline: claudeBaseline, displayMode: claudeDisplayMode)
        case .chatgpt:
            chatGPTService.menuBarFragment(displayMode: chatGPTDisplayMode)
        }
    }

    private func renderImage(lines: [String]) -> NSImage? {
        guard !lines.isEmpty else { return nil }

        let columns = MenuBarLayout.columns(from: lines)
        let maximumRowCount = columns.map(\.count).max() ?? 1
        let fontSize = min(11, 21 / CGFloat(maximumRowCount))
        let columnHeight = fontSize * CGFloat(maximumRowCount) * 1.2
        let renderer = ImageRenderer(content:
            HStack(alignment: .top, spacing: 4) {
                ForEach(columns.indices, id: \.self) { columnIndex in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(columns[columnIndex].indices, id: \.self) { rowIndex in
                            Text(columns[columnIndex][rowIndex])
                        }
                    }
                    .frame(height: columnHeight, alignment: .center)
                }
            }
            .font(.system(size: fontSize))
            .monospacedDigit()
        )
        renderer.scale = displayScale

        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = true
        return image
    }
}

enum MenuBarLayout {
    static func columns<Element>(from items: [Element]) -> [[Element]] {
        guard !items.isEmpty else { return [] }
        guard items.count > 2 else { return [items] }

        var columns: [[Element]] = []
        var nextIndex = 0

        if !items.count.isMultiple(of: 2) {
            columns.append([items[0]])
            nextIndex = 1
        }

        while nextIndex < items.count {
            columns.append(Array(items[nextIndex..<min(nextIndex + 2, items.count)]))
            nextIndex += 2
        }

        return columns
    }
}
