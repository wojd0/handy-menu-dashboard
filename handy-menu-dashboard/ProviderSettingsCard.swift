import SwiftUI

struct ProviderSettingsCard<Service: UsageDisplaying, Extra: View>: View {
    @Bindable var service: Service
    @Binding var draggedProvider: Provider?
    @Binding var autoRenew: Bool
    let automaticallyUpdates: Bool
    let signingOutProvider: Provider?
    var isPending: Bool = false
    var browserName: String?
    let onSignIn: () -> Void
    let onSignOut: () -> Void
    let onUpdateFromBrowser: () -> Void
    @ViewBuilder let extra: Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if service.isAuthenticated {
                    dragHandle
                }
                Text(provider.displayName)
                    .font(.headline)
                if isPending {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .help("Session needs updating")
                }
            }

            if service.isAuthenticated {
                HStack {
                    Text("Show in menu bar control")
                        .font(.callout)
                    Spacer()
                    Toggle("", isOn: $service.isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                extra

                usageBarsMenu

                VStack(alignment: .leading, spacing: 6) {
                    Text("Menu Bar Unit")
                        .font(.callout)
                    FullWidthSegmentedPicker(
                        label: "Menu Bar Unit",
                        selection: displayModeSelection,
                        options: displayModeOptions
                    )
                }

                HStack {
                    autoRenewCheckbox
                    Spacer()
                    Button("Sign Out", action: onSignOut)
                        .buttonStyle(.bordered)
                        .disabled(isBusy)
                }
            } else {
                HStack {
                    Button(updateButtonTitle, action: onUpdateFromBrowser)
                        .buttonStyle(.borderedProminent)
                        .disabled(isBusy)
                    Button(signInButtonTitle, action: onSignIn)
                        .buttonStyle(.bordered)
                        .disabled(isBusy)
                }
            }
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }

    private var provider: Provider { service.provider }

    private var displayModeOptions: [(title: String, value: MenuBarDisplayMode)] {
        let percentOptions: [(title: String, value: MenuBarDisplayMode)] = [
            ("% Used", .percentUsed),
            ("% Remaining", .percentRemaining)
        ]
        guard let monetaryLabel = provider.monetaryLabel else { return percentOptions }
        return [(monetaryLabel, .monetary)] + percentOptions
    }

    private var displayModeSelection: Binding<MenuBarDisplayMode> {
        Binding(
            get: {
                let mode = service.menuBarDisplayMode
                return mode == .monetary && provider.monetaryLabel == nil ? .percentUsed : mode
            },
            set: { service.menuBarDisplayMode = $0 }
        )
    }

    @ViewBuilder
    private var usageBarsMenu: some View {
        let bars = service.usageBars
        if !bars.isEmpty {
            HStack {
                Text("Popover Usage Bars")
                    .font(.callout)
                Spacer()
                Menu(usageBarsSummary(bars)) {
                    ForEach(Array(usageBarSections(bars).enumerated()), id: \.offset) { _, section in
                        if let title = section.title {
                            Section(title) {
                                usageBarToggles(section.bars)
                            }
                        } else {
                            usageBarToggles(section.bars)
                        }
                    }
                }
                .menuIndicator(.visible)
                .fixedSize()
            }
        }
    }

    private func usageBarToggles(_ bars: [UsageBar]) -> some View {
        ForEach(bars) { bar in
            Toggle(bar.title, isOn: Binding(
                get: { service.showsUsageBar(bar.id) },
                set: { service.setUsageBar(bar.id, shown: $0) }
            ))
        }
    }

    private func usageBarSections(_ bars: [UsageBar]) -> [(title: String?, bars: [UsageBar])] {
        bars.reduce(into: []) { sections, bar in
            if let last = sections.indices.last, sections[last].title == bar.section {
                sections[last].bars.append(bar)
            } else {
                sections.append((bar.section, [bar]))
            }
        }
    }

    private func usageBarsSummary(_ bars: [UsageBar]) -> String {
        let shown = bars.filter { service.showsUsageBar($0.id) }.count
        switch shown {
        case bars.count: return "All"
        case 0: return "None"
        default: return "\(shown) of \(bars.count)"
        }
    }

    @ViewBuilder
    private var autoRenewCheckbox: some View {
        if automaticallyUpdates {
            Toggle("Auto-Renew from Your Browser", isOn: $autoRenew)
                .toggleStyle(.checkbox)
                .font(.callout)
                .disabled(isBusy)
        }
    }

    private var isBusy: Bool { signingOutProvider != nil }

    private var signInButtonTitle: String {
        signingOutProvider == provider
            ? "Clearing browser session"
            : "Sign in here"
    }

    private var updateButtonTitle: String {
        "Update from your \(browserName ?? "browser")"
    }

    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .help("Drag to reorder")
            .onDrag {
                let dragged = provider
                draggedProvider = dragged
                let binding = $draggedProvider
                return DragSessionItemProvider(text: dragged.rawValue) {
                    Task { @MainActor in
                        if binding.wrappedValue == dragged {
                            binding.wrappedValue = nil
                        }
                    }
                }
            } preview: {
                Text(provider.displayName)
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
}

extension ProviderSettingsCard where Extra == EmptyView {
    init(
        service: Service,
        draggedProvider: Binding<Provider?>,
        autoRenew: Binding<Bool>,
        automaticallyUpdates: Bool,
        signingOutProvider: Provider?,
        isPending: Bool = false,
        browserName: String? = nil,
        onSignIn: @escaping () -> Void,
        onSignOut: @escaping () -> Void,
        onUpdateFromBrowser: @escaping () -> Void
    ) {
        self.init(
            service: service,
            draggedProvider: draggedProvider,
            autoRenew: autoRenew,
            automaticallyUpdates: automaticallyUpdates,
            signingOutProvider: signingOutProvider,
            isPending: isPending,
            browserName: browserName,
            onSignIn: onSignIn,
            onSignOut: onSignOut,
            onUpdateFromBrowser: onUpdateFromBrowser,
            extra: { EmptyView() }
        )
    }
}
