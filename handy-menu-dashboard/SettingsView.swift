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
            ValidatingLoginView(provider: .copilot) { await copilotService.authenticate(with: $0) }
        }
        .sheet(isPresented: $showClaudeLogin) {
            ClaudeLoginView(claudeService: claudeService)
        }
        .sheet(isPresented: $showChatGPTLogin) {
            ValidatingLoginView(provider: .chatgpt) { await chatGPTService.authenticate(with: $0) }
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
        case .cursor:
            ProviderSettingsCard(
                service: cursorService,
                draggedProvider: $draggedProvider,
                signingOutProvider: signingOutProvider,
                onSignIn: { showCursorLogin = true },
                onSignOut: { signOut(cursorService.provider) }
            )
        case .copilot:
            ProviderSettingsCard(
                service: copilotService,
                draggedProvider: $draggedProvider,
                signingOutProvider: signingOutProvider,
                onSignIn: { showCopilotLogin = true },
                onSignOut: { signOut(copilotService.provider) }
            )
        case .claude:
            ProviderSettingsCard(
                service: claudeService,
                draggedProvider: $draggedProvider,
                signingOutProvider: signingOutProvider,
                onSignIn: { showClaudeLogin = true },
                onSignOut: { signOut(claudeService.provider) }
            ) {
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
            }
        case .chatgpt:
            ProviderSettingsCard(
                service: chatGPTService,
                draggedProvider: $draggedProvider,
                signingOutProvider: signingOutProvider,
                onSignIn: { showChatGPTLogin = true },
                onSignOut: { signOut(chatGPTService.provider) }
            )
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
