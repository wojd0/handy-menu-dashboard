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
    @State private var showCursorLogin = false
    @State private var showClaudeLogin = false
    @State private var githubUsername = ""
    @State private var githubPAT = ""
    @State private var copilotEntitlement = ""
    @AppStorage("cursorMenuBarShowPercent") private var cursorShowPercent = false
    @AppStorage("copilotMenuBarShowPercent") private var copilotShowPercent = false
    @AppStorage("claudeMenuBarShowPercent") private var claudeShowPercent = false
    @AppStorage("claudeMenuBarBaseline") private var claudeBaseline = ClaudeBaseline.usageLimit
    @AppStorage(Provider.orderStorageKey) private var providerOrderRaw = Provider.defaultOrderRaw
    @State private var draggedProvider: Provider?
    @State private var dropIndicator: DropIndicator?
    @State private var cardHeights: [Provider: CGFloat] = [:]
    private let fineGrainedPATURL = URL(
        string: "https://github.com/settings/personal-access-tokens/new?"
            + "description=Handy+Menu+Dashboard&expiration=none&permissions=plan:read"
    )!

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
        }
        .animation(.snappy, value: providerOrderRaw)
        .padding(20)
        .frame(width: 460)
        .sheet(isPresented: $showCursorLogin) {
            CursorLoginView(cursorService: cursorService)
        }
        .sheet(isPresented: $showClaudeLogin) {
            ClaudeLoginView(claudeService: claudeService)
        }
        .onAppear {
            githubUsername = copilotService.username
            copilotEntitlement = String(copilotService.monthlyEntitlement)
        }
    }

    @ViewBuilder
    private func section(for provider: Provider) -> some View {
        switch provider {
        case .cursor: cursorSection
        case .copilot: copilotSection
        case .claude: claudeSection
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
                        .labelsHidden()
                        .onChange(of: cursorService.isEnabled) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "cursorEnabled")
                        }
                }
            }

            if cursorService.isAuthenticated {
                HStack {
                    Label("Signed in", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Sign Out") { cursorService.clearCredentials() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Menu Bar Unit")
                        .font(.callout)
                    Spacer()
                    Picker("", selection: $cursorShowPercent) {
                        Text("Dollars").tag(false)
                        Text("Percent").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            } else {
                Text("Sign in via browser to fetch your Cursor usage data.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Sign in to Cursor...") { showCursorLogin = true }
                    .buttonStyle(.borderedProminent)
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
                        .labelsHidden()
                        .onChange(of: copilotService.isEnabled) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "copilotEnabled")
                        }
                }
            }

            if copilotService.isAuthenticated {
                HStack {
                    Label("Configured", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Sign Out") {
                        copilotService.clearCredentials()
                        githubUsername = ""
                        githubPAT = ""
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Monthly entitlement")
                        .font(.callout)
                    TextField("300", text: $copilotEntitlement)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onSubmit {
                            if let entitlement = Int(copilotEntitlement) {
                                copilotService.saveEntitlement(entitlement)
                            }
                        }
                }

                HStack {
                    Text("Menu Bar Unit")
                        .font(.callout)
                    Spacer()
                    Picker("", selection: $copilotShowPercent) {
                        Text("Dollars").tag(false)
                        Text("Percent").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            } else {
                TextField("GitHub Username", text: $githubUsername)
                    .textFieldStyle(.roundedBorder)

                SecureField("Personal Access Token", text: $githubPAT)
                    .textFieldStyle(.roundedBorder)

                Link("Create a fine-grained PAT with \"Plan\" read permission",
                     destination: fineGrainedPATURL)
                    .font(.caption)

                HStack {
                    Text("Monthly entitlement")
                        .font(.callout)
                    TextField("300", text: $copilotEntitlement)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }

                Button("Save") {
                    copilotService.saveCredentials(username: githubUsername, pat: githubPAT)
                    if let entitlement = Int(copilotEntitlement) {
                        copilotService.saveEntitlement(entitlement)
                    }
                }
                .buttonStyle(.borderedProminent)
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
                        .labelsHidden()
                        .onChange(of: claudeService.isEnabled) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "claudeEnabled")
                        }
                }
            }

            if claudeService.isAuthenticated {
                HStack {
                    Label("Signed in", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Sign Out") { claudeService.clearCredentials() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Baseline")
                        .font(.callout)
                    Picker("", selection: $claudeBaseline) {
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
                    Picker("", selection: $claudeShowPercent) {
                        Text("Dollars").tag(false)
                        Text("Percent").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            } else {
                Text("Sign in via browser to fetch your Claude usage data.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Sign in to Claude...") { showClaudeLogin = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
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
