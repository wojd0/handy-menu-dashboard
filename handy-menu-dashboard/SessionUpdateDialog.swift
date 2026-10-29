import AppKit
import SwiftUI

struct SessionUpdateDialog: View {
    @Bindable var coordinator: SessionUpdateCoordinator
    var providers: [Provider]?
    var width: CGFloat = 360
    var onWebViewFallback: (Provider) -> Void = { _ in }
    var onClose: () -> Void = {}

    @State private var isWorking = false
    @State private var selectedProfile: URL?
    @State private var manualText = ""
    @State private var manualError: String?
    @State private var browserError: String?
    @State private var showsAutoRenewApproval = false
    @State private var autoRenewTargets: [Provider] = []

    private var home: URL { BrowserHome.current }

    private var targets: [Provider] { providers ?? coordinator.pending }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            switch coordinator.phase {
            case .idle, .harvesting:
                requestBody
            case .finished(let results):
                resultsBody(results)
            }
        }
        .padding(18)
        .frame(width: width)
        .sheet(isPresented: $showsAutoRenewApproval) {
            AutoRenewApprovalDialog(
                coordinator: coordinator,
                providers: autoRenewTargets,
                initialProfile: selectedProfile
            ) { profile in
                selectedProfile = profile
                showsAutoRenewApproval = false
                approve(autoRenewTargets, autoRenew: true)
            }
        }
        .onChange(of: coordinator.phase) { _, phase in
            guard case .finished(let results) = phase,
                  !results.isEmpty,
                  results.values.allSatisfy({ $0 == .updated }) else { return }
            coordinator.skip()
            onClose()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(targets.count == 1
                ? "1 agent needs updating"
                : "\(targets.count) agents need updating")
                .font(.headline)
        }
    }

    private var requestBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(targets) { provider in
                HStack(spacing: 8) {
                    Image(systemName: provider.iconName)
                    Text(provider.displayName)
                        .font(.callout)
                }
            }

            Divider()

            BrowserSourcePicker(title: "Browser", source: $coordinator.source)
                .disabled(isWorking)

            if let browser = coordinator.resolvedBrowser, let root = browser.engine(home: home).profileRoot {
                BrowserProfilePicker(browser: browser, root: root, selection: $selectedProfile)
                    .id(browser)
                    .disabled(isWorking)
            }

            cookieAccessDetails

            Button("Approve and Auto-Renew") {
                autoRenewTargets = targets
                showsAutoRenewApproval = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking || coordinator.isHarvesting || targets.isEmpty || needsProfile)

            HStack {
                Button("Cancel") {
                    coordinator.skip()
                    onClose()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Approve") {
                    approve(targets)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking || coordinator.isHarvesting || targets.isEmpty || needsProfile)
            }
        }
    }

    private func resultsBody(_ results: [Provider: SessionUpdateCoordinator.HarvestResult]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(orderedKeys(results)) { provider in
                resultRow(provider, result: results[provider])
            }

            if needsManual(results) {
                manualSection(results)
            }

            if results.values.contains(where: { $0 != .updated }) {
                Text("After signing in using \(browserName), return here and choose Try Again to import fresh cookies. "
                    + "Use the same browser profile selected for import.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let browserError {
                Text(browserError).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Button("Try Again") { coordinator.skip() }
                Spacer()
                Button("Close") {
                    coordinator.skip()
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func orderedKeys(_ results: [Provider: SessionUpdateCoordinator.HarvestResult]) -> [Provider] {
        Provider.allCases.filter { results[$0] != nil }
    }

    @ViewBuilder
    private func resultRow(_ provider: Provider, result: SessionUpdateCoordinator.HarvestResult?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: provider.iconName)
                Text(provider.displayName)
                    .font(.callout)
                Spacer()
                switch result {
                case .updated:
                    Label("Updated", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .labelStyle(.iconOnly)
                    Text("Updated").font(.caption).foregroundStyle(.secondary)
                case .notSignedInBrowser:
                    Text("Not signed in").font(.caption).foregroundStyle(.orange)
                case .rejected(let message), .failed(let message):
                    Text(message).font(.caption).foregroundStyle(.red)
                case .accessDenied, .keyDenied:
                    Text("Access blocked").font(.caption).foregroundStyle(.orange)
                case .none:
                    EmptyView()
                }
            }

            if let result, result != .updated {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        signInOptions(provider)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        signInOptions(provider)
                    }
                }
                .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func signInOptions(_ provider: Provider) -> some View {
        Button("Sign in here") { onWebViewFallback(provider) }
        Button("Sign in using \(browserName)") { signInUsingBrowser(provider) }
    }

    private func signInUsingBrowser(_ provider: Provider) {
        browserError = nil
        guard let browser = coordinator.resolvedBrowser,
              let applicationURL = DefaultBrowser.applicationURL(for: browser) else {
            browserError = "Could not open the selected browser. Choose Try Again to select another browser."
            return
        }
        Task {
            do {
                _ = try await NSWorkspace.shared.open(
                    [provider.harvest.startURL],
                    withApplicationAt: applicationURL,
                    configuration: NSWorkspace.OpenConfiguration()
                )
            } catch {
                browserError = "Could not open \(browser.displayName). Open it manually to sign in, then choose Try Again."
            }
        }
    }

    @ViewBuilder
    private func manualSection(_ results: [Provider: SessionUpdateCoordinator.HarvestResult]) -> some View {
        if let browser = coordinator.resolvedBrowser {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("\(browser.displayName) blocked direct access. Run this in Terminal, then import:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let command = ManualCookieImport.command(
                    for: browser,
                    filters: targets.map { $0.harvest.domainMatch },
                    home: home,
                    profile: selectedProfile
                )
                Text(command)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                HStack {
                    Button("Copy Command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    }
                    Button("Import from Clipboard") { importFromClipboard(browser) }
                    if browser == .safari {
                        Button("Grant Full Disk Access") { openFullDiskAccess() }
                    }
                }
                .font(.caption)

                if let manualError {
                    Text(manualError).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    private var cookieDomains: [String] {
        targets
            .map { provider in
                switch provider.harvest.domainMatch {
                case .exactOrSuffix(let domain), .contains(let domain): domain
                }
            }
            .reduced()
    }

    private var browserName: String {
        coordinator.resolvedBrowser.map { "your \($0.displayName)" } ?? "your browser"
    }

    private var cookieAccessDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Cookie sources")
                    .fontWeight(.semibold)
                Text("Handy Menu Dashboard will read cookies from \(browserName) on this Mac for:")
                    .foregroundStyle(.secondary)

                ForEach(cookieDomains, id: \.self) { domain in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(domain)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("How your cookies are used")
                    .fontWeight(.semibold)
                Text("Cookies are saved in your Keychain on this Mac "
                    + "and used only to authenticate with each provider and fetch your usage.")
                    .foregroundStyle(.secondary)
                Text("They do not leave this device except for these requests to the relevant provider.")
            }

            if let browser = coordinator.resolvedBrowser, isChromium(browser) {
                Text("macOS may ask to allow access to '\(browser.displayName) Safe Storage'.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var supportsProfiles: Bool {
        coordinator.resolvedBrowser?.engine(home: home).profileRoot != nil
    }

    private var needsProfile: Bool { supportsProfiles && selectedProfile == nil }

}

private extension SessionUpdateDialog {
    func isChromium(_ browser: Browser) -> Bool {
        if case .chromium = browser.engine(home: home) { return true }
        return false
    }

    func needsManual(_ results: [Provider: SessionUpdateCoordinator.HarvestResult]) -> Bool {
        results.values.contains { $0 == .accessDenied || $0 == .keyDenied }
    }

    func approve(_ providers: [Provider], autoRenew: Bool = false) {
        isWorking = true
        Task {
            let profile = supportsProfiles ? selectedProfile : nil
            if autoRenew {
                await coordinator.approveAndAutoRenew(providers, profile: profile)
            } else {
                await coordinator.approve(providers, profile: profile)
            }
            isWorking = false
        }
    }

    func importFromClipboard(_ browser: Browser) {
        manualError = nil
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            manualError = "Clipboard is empty. Run the command first."
            return
        }
        NSPasteboard.general.clearContents()
        let cookies: [BrowserCookie]
        do {
            cookies = try ManualCookieImport.parse(text, browser: browser, home: home)
        } catch {
            manualError = "Could not read the pasted cookies."
            return
        }
        Task {
            await coordinator.adopt(cookies.httpCookies, for: targets)
        }
    }

    func openFullDiskAccess() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

private extension Array where Element == String {
    func reduced() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
