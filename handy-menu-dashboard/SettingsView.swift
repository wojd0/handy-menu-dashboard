import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

private struct DropIndicator: Equatable {
    let provider: Provider
    let after: Bool
}

struct SettingsView: View {
    let services: ServiceSet
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
            CursorLoginView(cursorService: services.cursor)
        }
        .sheet(isPresented: $showCopilotLogin) {
            ValidatingLoginView(provider: .copilot) { await services.copilot.authenticate(with: $0) }
        }
        .sheet(isPresented: $showClaudeLogin) {
            ClaudeLoginView(claudeService: services.claude)
        }
        .sheet(isPresented: $showChatGPTLogin) {
            ValidatingLoginView(provider: .chatgpt) { await services.chatgpt.authenticate(with: $0) }
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
            card(services.cursor) { showCursorLogin = true }
        case .copilot:
            card(services.copilot) { showCopilotLogin = true }
        case .claude:
            claudeCard()
        case .chatgpt:
            card(services.chatgpt) { showChatGPTLogin = true }
        }
    }

    private func card<Service: UsageDisplaying>(
        _ service: Service,
        onSignIn: @escaping () -> Void
    ) -> some View {
        ProviderSettingsCard(
            service: service,
            draggedProvider: $draggedProvider,
            signingOutProvider: signingOutProvider,
            onSignIn: onSignIn,
            onSignOut: { signOut(service.provider) }
        )
    }

    private func claudeCard() -> some View {
        @Bindable var claude = services.claude

        return ProviderSettingsCard(
            service: claude,
            draggedProvider: $draggedProvider,
            signingOutProvider: signingOutProvider,
            onSignIn: { showClaudeLogin = true },
            onSignOut: { signOut(claude.provider) }
        ) {
            HStack {
                Text("Baseline")
                    .font(.callout)
                Picker("", selection: $claude.baseline) {
                    ForEach(ClaudeBaseline.allCases) { baseline in
                        Text(baseline.label).tag(baseline)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
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
            await services[provider].clearCredentials()
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
