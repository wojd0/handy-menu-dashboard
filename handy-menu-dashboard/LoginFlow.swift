import Foundation
import Observation

enum LoginOutcome: Equatable {
    case authenticated
    case staleSession
    case failure(String)
}

enum LoginRetryAction: Equatable {
    case none
    case replayed
    case needsFreshCookies
}

@Observable
final class LoginFlow {
    struct Effects {
        var clearWebsiteData: ([String]) async -> Void
        var reload: () -> Void
        var authenticated: () -> Void = {}
    }

    private(set) var isValidating = false
    private(set) var errorMessage: String?
    private(set) var didAuthenticate = false

    @ObservationIgnored var effects: Effects?
    @ObservationIgnored private let harvest: CookieHarvest
    @ObservationIgnored private let authenticate: ([HTTPCookie]) async -> LoginOutcome
    @ObservationIgnored private var isAuthenticating = false
    @ObservationIgnored private var lastCookies: [HTTPCookie]?
    @ObservationIgnored private var handledRetryAttempt = 0

    init(harvest: CookieHarvest, authenticate: @escaping ([HTTPCookie]) async -> LoginOutcome) {
        self.harvest = harvest
        self.authenticate = authenticate
    }

    var canReplayLastCookies: Bool { lastCookies != nil }

    func harvested(_ cookies: [HTTPCookie]) async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        lastCookies = cookies
        errorMessage = nil
        isValidating = true

        let outcome = await authenticate(cookies)
        isValidating = false

        switch outcome {
        case .authenticated:
            didAuthenticate = true
            effects?.authenticated()
        case .staleSession:
            lastCookies = nil
            errorMessage = "Session expired. Please sign in again."
            await effects?.clearWebsiteData(harvest.websiteDataDomains)
            isAuthenticating = false
            effects?.reload()
        case .failure(let message):
            isAuthenticating = false
            errorMessage = message
        }
    }

    func retry(attempt: Int) async -> LoginRetryAction {
        guard handledRetryAttempt != attempt else { return .none }
        handledRetryAttempt = attempt
        guard let lastCookies else { return .needsFreshCookies }
        await harvested(lastCookies)
        return .replayed
    }
}
