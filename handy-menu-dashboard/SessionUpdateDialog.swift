import AppKit
import SwiftUI

struct SessionUpdateDialog: View {
    @Bindable var coordinator: SessionUpdateCoordinator
    var providers: [Provider]?
    var width: CGFloat = 360
    var onWebViewFallback: (Provider) -> Void = { _ in }
    var onClose: () -> Void = {}

    @State private var isWorking = false
    @State private var manualText = ""
    @State private var manualError: String?

    private var home: URL { URL(fileURLWithPath: NSHomeDirectory()) }

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
                    Spacer()
                    Text(coordinator.reason(for: provider))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            BrowserSourcePicker(title: "Browser", source: $coordinator.source)

            Text(explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Skip") {
                    coordinator.skip()
                    onClose()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Approve") {
                    approve(targets)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking || targets.isEmpty)
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

            HStack {
                Spacer()
                Button("Done") {
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
            case .notSignedInBrowser, .rejected:
                Button("Sign in via browser…") { onWebViewFallback(provider) }
                    .font(.caption)
            case .accessDenied, .keyDenied:
                Text("Access blocked").font(.caption).foregroundStyle(.orange)
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(.red)
            case .none:
                EmptyView()
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
                    home: home
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
                        Button("Grant Full Disk Access…") { openFullDiskAccess() }
                    }
                }
                .font(.caption)

                if let manualError {
                    Text(manualError).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    private var explanation: String {
        let hosts = targets
            .flatMap { $0.harvest.websiteDataDomains }
            .reduced()
            .joined(separator: ", ")
        let browserName = coordinator.resolvedBrowser?.displayName ?? "your browser"
        var text = "Handy Menu Dashboard will read cookies for \(hosts) from \(browserName)'s cookie store on this Mac. "
            + "Only session cookies are kept, saved to your Keychain. Nothing leaves your Mac except the usual usage requests."
        if let browser = coordinator.resolvedBrowser, isChromium(browser) {
            text += " macOS may ask to allow access to '\(browser.displayName) Safe Storage'."
        }
        return text
    }

    private func isChromium(_ browser: Browser) -> Bool {
        if case .chromium = browser.engine(home: home) { return true }
        return false
    }

    private func needsManual(_ results: [Provider: SessionUpdateCoordinator.HarvestResult]) -> Bool {
        results.values.contains { $0 == .accessDenied || $0 == .keyDenied }
    }

    private func approve(_ providers: [Provider]) {
        isWorking = true
        Task {
            await coordinator.approve(providers)
            isWorking = false
        }
    }

    private func importFromClipboard(_ browser: Browser) {
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

    private func openFullDiskAccess() {
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
