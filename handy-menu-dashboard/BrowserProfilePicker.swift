import AppKit
import SwiftUI

struct BrowserProfilePicker: View {
    let browser: Browser
    let root: URL
    @Binding var selection: URL?
    @State private var profiles: [BrowserProfile] = []
    @State private var errorMessage: String?
    @State private var grantedFolder: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Profile", selection: $selection) {
                if profiles.isEmpty {
                    Text("No profiles available").tag(nil as URL?)
                }
                ForEach(profiles) { profile in
                    Text(profileLabel(profile)).tag(Optional(profile.directory))
                }
            }
            .pickerStyle(.menu)
            .disabled(profiles.isEmpty)
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.secondary)
                Button("Allow Access to \(browser.displayName) Folder…", action: chooseFolder)
                    .font(.caption)
            }
        }
        .onAppear { loadProfiles(at: root) }
        .onDisappear { releaseFolder() }
    }

    private func profileLabel(_ profile: BrowserProfile) -> String {
        profiles.filter { $0.name == profile.name }.count > 1
            ? "\(profile.name) (\(profile.directory.lastPathComponent))" : profile.name
    }

    private func loadProfiles(at root: URL) {
        let previousSelection = selection
        selection = nil
        profiles = []
        do {
            switch browser.engine(home: BrowserHome.current) {
            case .gecko:
                profiles = try GeckoCookieStore(profilesRoot: root).profiles(
                    applicationURL: DefaultBrowser.applicationURL(for: browser)
                )
            case .chromium:
                profiles = try ChromiumCookieStore.profiles(at: root)
            case .webkit:
                return
            }
            selection = profiles.first { $0.directory == previousSelection }?.directory ?? profiles.first?.directory
            errorMessage = nil
        } catch {
            switch error {
            case .accessDenied:
                errorMessage = "Allow access to your \(browser.displayName) folder to list its profiles."
            case .noProfile:
                errorMessage = "Choose your \(browser.displayName) folder or a profile folder to continue."
            default:
                errorMessage = "Could not read the profile list. Choose your \(browser.displayName) folder to try again."
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = root
        panel.prompt = "Allow Access"
        panel.message = "Allow access to the \(browser.displayName) folder to list its profiles. "
            + "Session cookies will only be read after you click Approve."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        releaseFolder()
        if folder.startAccessingSecurityScopedResource() { grantedFolder = folder }
        let cookieFile = isGecko ? "cookies.sqlite" : "Cookies"
        if FileManager.default.fileExists(atPath: folder.appending(path: cookieFile).path) {
            profiles = [.init(name: folder.lastPathComponent, directory: folder)]
            selection = folder
            errorMessage = nil
        } else {
            loadProfiles(at: folder)
        }
    }

    private var isGecko: Bool {
        if case .gecko = browser.engine(home: BrowserHome.current) { return true }
        return false
    }

    private func releaseFolder() {
        grantedFolder?.stopAccessingSecurityScopedResource()
        grantedFolder = nil
    }
}
