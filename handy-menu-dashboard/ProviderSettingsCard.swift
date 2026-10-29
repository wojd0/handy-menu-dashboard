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
                dragHandle
                Image(systemName: provider.iconName)
                Text(provider.displayName)
                    .font(.headline)
                if isPending {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .help("Session needs updating")
                }
                Spacer()
                Toggle("", isOn: $service.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if service.isAuthenticated {
                extra

                HStack {
                    Text("Menu Bar Unit")
                        .font(.callout)
                    Spacer()
                    Picker("", selection: $service.menuBarDisplayMode) {
                        Text(provider.monetaryLabel).tag(MenuBarDisplayMode.monetary)
                        Text("% Used").tag(MenuBarDisplayMode.percentUsed)
                        Text("% Remaining").tag(MenuBarDisplayMode.percentRemaining)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                HStack {
                    Label("Signed in", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Sign Out", action: onSignOut)
                        .buttonStyle(.bordered)
                        .disabled(isBusy)
                }

                autoRenewCheckbox
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
            ? "Clearing browser session..."
            : "Sign in here…"
    }

    private var updateButtonTitle: String {
        "Update from your \(browserName ?? "browser")…"
    }

    private var dragHandle: some View {
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
