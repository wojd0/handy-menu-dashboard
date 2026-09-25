import Foundation
import Observation

@Observable
final class UsageSession {
    let provider: Provider

    var isLoading = false
    var isAuthenticated = false
    var errorMessage: String?

    @ObservationIgnored private(set) var cookieHeader: String?
    @ObservationIgnored private let keychain: any KeychainStoring
    @ObservationIgnored private let preferences: any PreferenceStoring

    private var storedEnabled: Bool
    private var storedDisplayMode: MenuBarDisplayMode

    init(
        provider: Provider,
        keychain: any KeychainStoring,
        preferences: any PreferenceStoring = UserDefaults.standard
    ) {
        self.provider = provider
        self.keychain = keychain
        self.preferences = preferences
        storedEnabled = ProviderPreferences.isEnabled(provider, in: preferences)
        storedDisplayMode = ProviderPreferences.displayMode(for: provider, in: preferences)
    }

    var isEnabled: Bool {
        get { storedEnabled }
        set {
            storedEnabled = newValue
            ProviderPreferences.setEnabled(newValue, for: provider, in: preferences)
        }
    }

    var menuBarDisplayMode: MenuBarDisplayMode {
        get { storedDisplayMode }
        set {
            storedDisplayMode = newValue
            ProviderPreferences.setDisplayMode(newValue, for: provider, in: preferences)
        }
    }

    var isActive: Bool { isAuthenticated && isEnabled }

    func loadStoredCredential() {
        guard let header = keychain.loadString(key: provider.keychainKey), !header.isEmpty else { return }
        adopt(header)
    }

    func adopt(_ header: String) {
        cookieHeader = header
        isAuthenticated = true
    }

    func persist(_ header: String) {
        keychain.saveString(key: provider.keychainKey, value: header)
        adopt(header)
    }

    func discardCredential() {
        keychain.delete(key: provider.keychainKey)
        cookieHeader = nil
        isAuthenticated = false
    }

    func purgeLegacy(_ keys: [KeychainKey]) {
        for key in keys {
            keychain.delete(key: key)
        }
    }

    func isCurrent(_ header: String) -> Bool {
        cookieHeader == header
    }

    func absorb(_ kind: UsageFailure.Kind) {
        let outcome = SessionTransition.apply(
            UsageFailure(kind: kind, provider: provider),
            to: SessionState(isAuthenticated: isAuthenticated, errorMessage: errorMessage)
        )
        isAuthenticated = outcome.state.isAuthenticated
        errorMessage = outcome.state.errorMessage
        if outcome.discardsCredential {
            discardCredential()
        }
    }

    func run<T>(
        load: (String) async throws -> T,
        apply: (T) -> Void,
        unexpected: String
    ) async {
        guard let cookieHeader, !cookieHeader.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let payload = try await load(cookieHeader)
            guard isCurrent(cookieHeader) else { return }
            isAuthenticated = true
            apply(payload)
        } catch let kind as UsageFailure.Kind {
            guard isCurrent(cookieHeader) else { return }
            absorb(kind)
        } catch {
            guard isCurrent(cookieHeader) else { return }
            errorMessage = unexpected
        }
    }
}
