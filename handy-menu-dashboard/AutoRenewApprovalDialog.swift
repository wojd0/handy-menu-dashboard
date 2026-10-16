import SwiftUI

struct AutoRenewApprovalDialog: View {
    @Bindable var coordinator: SessionUpdateCoordinator
    let providers: [Provider]
    let onApprove: (URL?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedProfile: URL?

    init(
        coordinator: SessionUpdateCoordinator,
        providers: [Provider],
        initialProfile: URL? = nil,
        onApprove: @escaping (URL?) -> Void
    ) {
        self.coordinator = coordinator
        self.providers = providers
        self.onApprove = onApprove
        _selectedProfile = State(initialValue: initialProfile ?? coordinator.resolvedBrowser.flatMap { browser in
            let provider = providers.count == 1 ? providers.first : nil
            return coordinator.savedProfile(for: browser, provider: provider) ?? coordinator.savedProfile(for: browser)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Enable automatic session renewal?", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text("From now on, Handy Menu Dashboard will automatically update these agents' sessions from your browser cookies in the background. You will not be asked to approve each update and do not need to be present.")

            ForEach(providers) { provider in
                Label(provider.displayName, systemImage: provider.iconName)
            }

            BrowserSourcePicker(title: "Browser", source: $coordinator.source)

            if let browser = coordinator.resolvedBrowser,
               let root = browser.engine(home: BrowserHome.current).profileRoot {
                BrowserProfilePicker(browser: browser, root: root, selection: $selectedProfile)
                    .id(browser)
            }

            Text("Only these agents' session cookies are read. They are stored in your Keychain and sent only to the relevant provider to fetch usage. Automatic renewal runs while the app is open and the agent is enabled.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("You can pause all automatic updates in General settings, or uncheck an agent's Auto-Renew checkbox to forget this approval.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Enable Auto-Renew") {
                    onApprove(supportsProfiles ? selectedProfile : nil)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(coordinator.resolvedBrowser == nil || (supportsProfiles && selectedProfile == nil) || coordinator.isHarvesting)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(20)
        .frame(width: 420)
    }

    private var supportsProfiles: Bool {
        coordinator.resolvedBrowser?.engine(home: BrowserHome.current).profileRoot != nil
    }
}
