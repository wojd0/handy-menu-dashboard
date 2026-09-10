import Foundation

struct UsageFailure: Error, Equatable {
    enum Kind: Error, Equatable {
        case authExpired
        case rejected(String)
        case httpError(Int)
        case network
        case invalidResponse
    }

    let kind: Kind
    let provider: Provider
}

struct SessionState: Equatable {
    var isAuthenticated: Bool
    var errorMessage: String?
}

struct SessionOutcome: Equatable {
    var state: SessionState
    var discardsCredential: Bool
}

enum SessionTransition {
    static func message(for failure: UsageFailure) -> String {
        switch failure.kind {
        case .authExpired:
            "Session expired. Please sign in again."
        case .rejected(let message):
            message
        case .httpError(let code):
            "\(failure.provider.errorNoun) returned status \(code)"
        case .network:
            "Unable to connect to \(failure.provider.errorNoun)"
        case .invalidResponse:
            "Invalid response from \(failure.provider.errorNoun)"
        }
    }

    static func apply(_ failure: UsageFailure, to state: SessionState) -> SessionOutcome {
        let message = message(for: failure)
        switch failure.kind {
        case .authExpired:
            return SessionOutcome(
                state: SessionState(isAuthenticated: false, errorMessage: message),
                discardsCredential: failure.provider.clearsCredentialOnAuthExpiry
            )
        case .rejected:
            return SessionOutcome(
                state: SessionState(isAuthenticated: false, errorMessage: message),
                discardsCredential: true
            )
        case .httpError, .network, .invalidResponse:
            return SessionOutcome(
                state: SessionState(isAuthenticated: state.isAuthenticated, errorMessage: message),
                discardsCredential: false
            )
        }
    }
}
