import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

private struct DropIndicator: Equatable {
    let provider: Provider
    let after: Bool
}

struct SettingsView: View {
    let services: ServiceSet
    @State private var loginProvider: Provider?
    @AppStorage(Provider.orderStorageKey) private var providerOrderRaw = Provider.defaultOrderRaw
    @AppStorage("menuBarInserted") private var menuBarInserted = true
    @State private var launchAtLogin = false
    @State private var draggedProvider: Provider?
    @State private var dropIndicator: DropIndicator?
    @State private var cardHeights: [Provider: CGFloat] = [:]
    @State private var signingOutProvider: Provider?
    @State private var autoRenewProvider: Provider?

    var body: some View {
        ScrollView {
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

                if !services.sessionUpdates.pending.isEmpty {
                    Button("Sign in all…") {
                        ConsentWindowController.shared.show(
                            services: services,
                            providers: services.sessionUpdates.pending
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(signingOutProvider != nil || services.sessionUpdates.isHarvesting)
                    .help("Sign in all enabled, logged-out agents using cookies from your browser")
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                generalSection
            }
            .padding(20)
        }
        .animation(.snappy, value: providerOrderRaw)
        .frame(width: 460)
        .frame(minHeight: 400, idealHeight: 780, maxHeight: 900)
        .sheet(item: $loginProvider) { provider in
            ProviderLoginSheet(provider: provider, services: services)
        }
        .sheet(item: $autoRenewProvider) { provider in
            AutoRenewApprovalDialog(coordinator: services.sessionUpdates, providers: [provider]) { profile in
                services.sessionUpdates.enableAutoRenew([provider], profile: profile)
            }
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

            browserCookiesRow

            automaticUpdatesCheckbox

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

    private var browserCookiesRow: some View {
        @Bindable var coordinator = services.sessionUpdates

        return HStack {
            Text("Browser Cookies")
                .font(.callout)
            Spacer()
            BrowserSourcePicker(title: "", source: $coordinator.source)
                .labelsHidden()
                .fixedSize()
                .disabled(coordinator.isHarvesting)
        }
    }

    private var automaticUpdatesCheckbox: some View {
        @Bindable var coordinator = services.sessionUpdates

        return Toggle("Auto Update from Your Browser", isOn: $coordinator.automaticallyUpdates)
            .toggleStyle(.checkbox)
            .disabled(!coordinator.hasAutoRenewApprovals)
            .help("Pause or resume automatic updates for agents with Auto-Renew approval")
    }

    private func autoRenewBinding(for provider: Provider) -> Binding<Bool> {
        Binding(
            get: { services.sessionUpdates.autoRenewProviders.contains(provider) },
            set: { enabled in
                if enabled {
                    autoRenewProvider = provider
                } else {
                    services.sessionUpdates.disableAutoRenew(provider)
                }
            }
        )
    }

    @ViewBuilder
    private func section(for provider: Provider) -> some View {
        switch provider {
        case .cursor:
            card(services.cursor)
        case .copilot:
            card(services.copilot)
        case .claude:
            claudeCard()
        case .chatgpt:
            card(services.chatgpt)
        }
    }

    private var browserName: String? {
        services.sessionUpdates.resolvedBrowser?.displayName
    }

    private func isPending(_ provider: Provider) -> Bool {
        services.sessionUpdates.pending.contains(provider)
    }

    private func updateFromBrowser(_ provider: Provider) {
        ConsentWindowController.shared.show(services: services, providers: [provider])
    }

    private func card<Service: UsageDisplaying>(_ service: Service) -> some View {
        ProviderSettingsCard(
            service: service,
            draggedProvider: $draggedProvider,
            autoRenew: autoRenewBinding(for: service.provider),
            automaticallyUpdates: services.sessionUpdates.automaticallyUpdates,
            signingOutProvider: signingOutProvider,
            isPending: isPending(service.provider),
            browserName: browserName,
            onSignIn: { loginProvider = service.provider },
            onSignOut: { signOut(service.provider) },
            onUpdateFromBrowser: { updateFromBrowser(service.provider) }
        )
    }

    private func claudeCard() -> some View {
        @Bindable var claude = services.claude

        let usagePools = claude.availableUsagePools

        return ProviderSettingsCard(
            service: claude,
            draggedProvider: $draggedProvider,
            autoRenew: autoRenewBinding(for: claude.provider),
            automaticallyUpdates: services.sessionUpdates.automaticallyUpdates,
            signingOutProvider: signingOutProvider,
            isPending: isPending(claude.provider),
            browserName: browserName,
            onSignIn: { loginProvider = .claude },
            onSignOut: { signOut(claude.provider) },
            onUpdateFromBrowser: { updateFromBrowser(.claude) },
            extra: {
                if usagePools.count > 1 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Usage Pool")
                            .font(.callout)
                        Picker("Usage Pool", selection: Binding(
                            get: { claude.resolvedUsagePool },
                            set: { claude.usagePool = $0 }
                        )) {
                            ForEach(usagePools) { usagePool in
                                Text(usagePool.label).tag(usagePool)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        )
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
        services[provider].isEnabled = false
        services.sessionUpdates.refreshPending()

        Task {
            await services[provider].clearCredentials()
            services.sessionUpdates.refreshPending()
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
