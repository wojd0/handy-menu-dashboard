import SwiftUI

struct ProviderSettingsCard<Service: UsageDisplaying, Extra: View>: View {
    @Bindable var service: Service
    @Binding var draggedProvider: Provider?
    let signingOutProvider: Provider?
    let onSignIn: () -> Void
    let onSignOut: () -> Void
    @ViewBuilder let extra: Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                dragHandle
                Image(systemName: provider.iconName)
                Text(provider.displayName)
                    .font(.headline)
                Spacer()
                if service.isAuthenticated {
                    Toggle("", isOn: $service.isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            if service.isAuthenticated {
                HStack {
                    Label("Signed in", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Sign Out", action: onSignOut)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(isBusy)
                }

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
            } else {
                Text(provider.signInBlurb)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(signInButtonTitle, action: onSignIn)
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }

    private var provider: Provider { service.provider }

    private var isBusy: Bool { signingOutProvider != nil }

    private var signInButtonTitle: String {
        signingOutProvider == provider
            ? "Clearing browser session..."
            : "Sign in to \(provider.displayName)..."
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
        signingOutProvider: Provider?,
        onSignIn: @escaping () -> Void,
        onSignOut: @escaping () -> Void
    ) {
        self.init(
            service: service,
            draggedProvider: draggedProvider,
            signingOutProvider: signingOutProvider,
            onSignIn: onSignIn,
            onSignOut: onSignOut,
            extra: { EmptyView() }
        )
    }
}
