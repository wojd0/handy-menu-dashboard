import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

private struct DropIndicator: Equatable {
    let provider: Provider
    let after: Bool
}

struct SettingsView: View {
    @Bindable var cursorService: CursorService
    @Bindable var copilotService: CopilotService
    @Bindable var claudeService: ClaudeService
    @Bindable var chatGPTService: ChatGPTService
    @State private var showCursorLogin = false
    @State private var showCopilotLogin = false
    @State private var showClaudeLogin = false
    @State private var showChatGPTLogin = false
    @AppStorage(Provider.orderStorageKey) private var providerOrderRaw = Provider.defaultOrderRaw
    @AppStorage("menuBarInserted") private var menuBarInserted = true
    @State private var launchAtLogin = false
    @State private var draggedProvider: Provider?
    @State private var dropIndicator: DropIndicator?
    @State private var cardHeights: [Provider: CGFloat] = [:]
    @State private var signingOutProvider: Provider?

    var body: some View {
        VStack(spacing: 16) {
            ForEach(Provider.ordered(from: providerOrderRaw)) { provider in
                section(for: provider)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeights[provider] = $0 }
                    .overlay(alignment: .top) { insertionLine(for: provider, after: false).offset(y: -10) }
                    .overlay(alignment: .bottom) { insertionLine(for: provider, after: true).offset(y: 10) }
                    .opacity(draggedProvider == provider ? 0.4 : 1)
                    .onDrop(
                        of: [.text],
                        delegate: ProviderDropDelegate(
                            provider: provider,
                            height: cardHeights[provider] ?? 0,
                            draggedProvider: $draggedProvider,
                            dropIndicator: $dropIndicator,
                            onReorder: reorder
                        )
                    )
            }

            generalSection
        }
        .animation(.snappy, value: providerOrderRaw)
        .padding(20)
        .frame(width: 460)
        .sheet(isPresented: $showCursorLogin) {
            CursorLoginView(cursorService: cursorService)
        }
        .sheet(isPresented: $showCopilotLogin) {
            CopilotLoginView(copilotService: copilotService)
        }
        .sheet(isPresented: $showClaudeLogin) {
            ClaudeLoginView(claudeService: claudeService)
        }
        .sheet(isPresented: $showChatGPTLogin) {
            ChatGPTLoginView(chatGPTService: chatGPTService)
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            NSApp.setActivationPolicy(.regular)
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
        .onChange(of: launchAtLogin) { _, newValue in
            let previousValue = !newValue
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                launchAtLogin = previousValue
            }
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "gearshape")
                Text("General")
                    .font(.headline)
            }

            Toggle("Launch at Login", isOn: $launchAtLogin)
                .toggleStyle(.switch)

            HStack {
                if menuBarInserted {
                    Label("In menu bar", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                } else {
                    Text("Icon removed from menu bar")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add to Menu Bar") { menuBarInserted = true }
                    .disabled(menuBarInserted)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func section(for provider: Provider) -> some View {
        switch provider {
        case .cursor: cursorSection
        case .copilot: copilotSection
        case .claude: claudeSection
        case .chatgpt: chatGPTSection
        }
    }

    @ViewBuilder
    private func insertionLine(for provider: Provider, after: Bool) -> some View {
        if dropIndicator == DropIndicator(provider: provider, after: after) {
            Capsule()
                .fill(Color.accentColor)
                .frame(height: 3)
                .padding(.horizontal, 4)
        }
    }

    private func reorder(moved: Provider, onto target: Provider, after: Bool) -> Bool {
        guard moved != target else { return false }
        var order = Provider.ordered(from: providerOrderRaw)
        order.removeAll { $0 == moved }
        guard let targetIndex = order.firstIndex(of: target) else { return false }
        order.insert(moved, at: after ? targetIndex + 1 : targetIndex)
        providerOrderRaw = Provider.raw(from: order)
        return true
    }

    private func dragHandle(for provider: Provider) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.callout)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .help("Drag to reorder")
            .onDrag {
                draggedProvider = provider
                return NSItemProvider(object: provider.rawValue as NSString)
            } preview: {
                Label(provider.displayName, systemImage: provider.iconName)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .onHover { hovering in
                if hovering {
                    NSCursor.openHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
    }

    private var cursorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                dragHandle(for: .cursor)
                Image(systemName: "cursorarrow.click")
                Text("Cursor")
                    .font(.headline)
                Spacer()
                if cursorService.isAuthenticated {
                    Toggle("", isOn: $cursorService.isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            if cursorService.isAuthenticated {
                HStack {
                    Label("Signed in", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Sign Out") { signOut(.cursor) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(signingOutProvider != nil)
                }

                HStack {
                    Text("Menu Bar Unit")
                        .font(.callout)
                    Spacer()
                    Picker("", selection: $cursorService.menuBarDisplayMode) {
                        Text("Dollars").tag(MenuBarDisplayMode.monetary)
                        Text("% Used").tag(MenuBarDisplayMode.percentUsed)
                        Text("% Remaining").tag(MenuBarDisplayMode.percentRemaining)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            } else {
                Text("Sign in via browser to fetch your Cursor usage data.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(signInButtonTitle(for: .cursor)) { showCursorLogin = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(signingOutProvider != nil)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }

    private var copilotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                dragHandle(for: .copilot)
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                Text("GitHub Copilot")
                    .font(.headline)
                Spacer()
                if copilotService.isAuthenticated {
                    Toggle("", isOn: $copilotService.isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            if copilotService.isAuthenticated {
                HStack {
                    Label("Signed in", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Sign Out") { signOut(.copilot) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(signingOutProvider != nil)
                }

                HStack {
                    Text("Menu Bar Unit")
                        .font(.callout)
                    Spacer()
                    Picker("", selection: $copilotService.menuBarDisplayMode) {
                        Text("Credits").tag(MenuBarDisplayMode.monetary)
                        Text("% Used").tag(MenuBarDisplayMode.percentUsed)
                        Text("% Remaining").tag(MenuBarDisplayMode.percentRemaining)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            } else {
                Text("Sign in via browser to fetch your GitHub Copilot credit usage.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(signInButtonTitle(for: .copilot)) { showCopilotLogin = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(signingOutProvider != nil)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }

    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                dragHandle(for: .claude)
                Image(systemName: "sparkle")
                Text("Claude")
                    .font(.headline)
                Spacer()
                if claudeService.isAuthenticated {
                    Toggle("", isOn: $claudeService.isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            if claudeService.isAuthenticated {
                HStack {
                    Label("Signed in", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Sign Out") { signOut(.claude) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(signingOutProvider != nil)
                }

                HStack {
                    Text("Baseline")
                        .font(.callout)
                    Picker("", selection: $claudeService.baseline) {
                        ForEach(ClaudeBaseline.allCases) { baseline in
                            Text(baseline.label).tag(baseline)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                HStack {
                    Text("Menu Bar Unit")
                        .font(.callout)
                    Spacer()
                    Picker("", selection: $claudeService.menuBarDisplayMode) {
                        Text("Dollars").tag(MenuBarDisplayMode.monetary)
                        Text("% Used").tag(MenuBarDisplayMode.percentUsed)
                        Text("% Remaining").tag(MenuBarDisplayMode.percentRemaining)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            } else {
                Text("Sign in via browser to fetch your Claude usage data.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(signInButtonTitle(for: .claude)) { showClaudeLogin = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(signingOutProvider != nil)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }

    private var chatGPTSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                dragHandle(for: .chatgpt)
                Image(systemName: "bubble.left.and.bubble.right")
                Text("ChatGPT")
                    .font(.headline)
                Spacer()
                if chatGPTService.isAuthenticated {
                    Toggle("", isOn: $chatGPTService.isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            if chatGPTService.isAuthenticated {
                HStack {
                    Label("Signed in", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Sign Out") { signOut(.chatgpt) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(signingOutProvider != nil)
                }

                HStack {
                    Text("Menu Bar Unit")
                        .font(.callout)
                    Spacer()
                    Picker("", selection: $chatGPTService.menuBarDisplayMode) {
                        Text("Credits").tag(MenuBarDisplayMode.monetary)
                        Text("% Used").tag(MenuBarDisplayMode.percentUsed)
                        Text("% Remaining").tag(MenuBarDisplayMode.percentRemaining)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            } else {
                Text("Sign in via browser to fetch your ChatGPT monthly credit usage.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(signInButtonTitle(for: .chatgpt)) { showChatGPTLogin = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(signingOutProvider != nil)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }

    private func signInButtonTitle(for provider: Provider) -> String {
        signingOutProvider == provider ? "Clearing browser session..." : "Sign in to \(provider.displayName)..."
    }

    private func signOut(_ provider: Provider) {
        guard signingOutProvider == nil else { return }
        signingOutProvider = provider

        Task {
            switch provider {
            case .cursor:
                await cursorService.clearCredentials()
            case .claude:
                await claudeService.clearCredentials()
            case .chatgpt:
                await chatGPTService.clearCredentials()
            case .copilot:
                await copilotService.clearCredentials()
            }
            signingOutProvider = nil
        }
    }
}

private struct ProviderDropDelegate: DropDelegate {
    let provider: Provider
    let height: CGFloat
    @Binding var draggedProvider: Provider?
    @Binding var dropIndicator: DropIndicator?
    let onReorder: (Provider, Provider, Bool) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        draggedProvider != nil
    }

    func dropEntered(info: DropInfo) {
        updateIndicator(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateIndicator(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if dropIndicator?.provider == provider {
            withAnimation(.easeOut(duration: 0.1)) { dropIndicator = nil }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggedProvider = nil
            withAnimation(.easeOut(duration: 0.1)) { dropIndicator = nil }
        }
        guard let moved = draggedProvider else { return false }
        return onReorder(moved, provider, isAfter(info))
    }

    private func updateIndicator(_ info: DropInfo) {
        guard let dragged = draggedProvider, dragged != provider else { return }
        let indicator = DropIndicator(provider: provider, after: isAfter(info))
        if dropIndicator != indicator {
            withAnimation(.easeOut(duration: 0.1)) { dropIndicator = indicator }
        }
    }

    private func isAfter(_ info: DropInfo) -> Bool {
        info.location.y > height / 2
    }
}
