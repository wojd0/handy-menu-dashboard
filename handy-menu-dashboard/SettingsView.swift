import SwiftUI

struct SettingsView: View {
    @Bindable var cursorService: CursorService
    @Bindable var copilotService: CopilotService
    @State private var showCursorLogin = false
    @State private var githubUsername = ""
    @State private var githubPAT = ""
    @State private var copilotEntitlement = ""

    var body: some View {
        VStack(spacing: 16) {
            cursorSection
            copilotSection
        }
        .padding(20)
        .frame(width: 380)
        .sheet(isPresented: $showCursorLogin) {
            CursorLoginView(cursorService: cursorService)
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
            } else {
                TextField("GitHub Username", text: $githubUsername)
                    .textFieldStyle(.roundedBorder)

                SecureField("Personal Access Token", text: $githubPAT)
                    .textFieldStyle(.roundedBorder)

                Link("Create a fine-grained PAT with \"Plan\" read permission",
                     destination: URL(string: "https://github.com/settings/personal-access-tokens/new?description=Handy+Menu+Dashboard&expiration=none&permissions=plan:read")!)
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
}
