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
    @AppStorage(Provider.orderStorageKey) private var providerOrderRaw = Provider.defaultOrderRaw
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let lines = Provider.ordered(from: providerOrderRaw)
            .map { provider in
                MenuBarLine(provider: provider, text: fragment(for: provider))
            }
            .filter { !$0.text.isEmpty }

        if let image = renderImage(lines: lines) {
            Image(nsImage: image)
                .renderingMode(.original)
        } else {
            Text("Usage")
                .font(.caption2)
        }
    }

    private func fragment(for provider: Provider) -> String {
        switch provider {
        case .cursor:
            cursorService.menuBarText
        case .copilot:
            copilotService.menuBarText
        case .claude:
            claudeService.menuBarText
        case .chatgpt:
            chatGPTService.menuBarText
        }
    }

    private func renderImage(lines: [MenuBarLine]) -> NSImage? {
        guard !lines.isEmpty else { return nil }

        let columns = MenuBarLayout.columns(from: lines)
        let maximumRowCount = columns.map(\.count).max() ?? 1
        let fontSize = min(11, 21 / CGFloat(maximumRowCount))
        let pixelLength = 1 / displayScale
        let underlineHeight = pixelLength
        let underlineSpacing = pixelLength
        let underlineDecorationHeight = underlineHeight + underlineSpacing
        let columnHeight = (fontSize * 1.2 + underlineDecorationHeight) * CGFloat(maximumRowCount)
        let renderer = ImageRenderer(content:
            HStack(alignment: .top, spacing: 4) {
                ForEach(columns.indices, id: \.self) { columnIndex in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(columns[columnIndex].indices, id: \.self) { rowIndex in
                            let line = columns[columnIndex][rowIndex]
                            Text(line.text)
                                .padding(.bottom, underlineDecorationHeight)
                                .overlay(alignment: .bottom) {
                                    Rectangle()
                                        .fill(line.provider.accentColor)
                                        .frame(height: underlineHeight)
                                }
                        }
                    }
                    .frame(height: columnHeight, alignment: .center)
                }
            }
            .font(.system(size: fontSize))
            .monospacedDigit()
            .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
        )
        renderer.scale = displayScale

        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = false
        return image
    }
}

private struct MenuBarLine {
    let provider: Provider
    let text: String
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
