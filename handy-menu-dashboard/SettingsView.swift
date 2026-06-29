import SwiftUI

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
    private let fineGrainedPATURL = URL(
        string: "https://github.com/settings/personal-access-tokens/new?"
            + "description=Handy+Menu+Dashboard&expiration=none&permissions=plan:read"
    )!

    var body: some View {
        VStack(spacing: 16) {
            cursorSection
            if FeatureFlags.showGitHubSettings {
                copilotSection
            }
            if FeatureFlags.showClaudeSettings {
                claudeSection
            }
        }
        .padding(20)
        .frame(width: 380)
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

    private var cursorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
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
                    Text("Menu Bar")
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
                    Text("Menu Bar")
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
                    Spacer()
                    Picker("", selection: $claudeBaseline) {
                        ForEach(ClaudeBaseline.allCases) { baseline in
                            Text(baseline.label).tag(baseline)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                HStack {
                    Text("Menu Bar")
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
