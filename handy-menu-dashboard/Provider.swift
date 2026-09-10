import Foundation
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

enum Provider: String, CaseIterable, Identifiable, Codable, Transferable {
    case cursor
    case copilot
    case claude
    case chatgpt

    var id: String { rawValue }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }

    var isAvailable: Bool {
        true
    }

    var displayName: String {
        switch self {
        case .cursor: "Cursor"
        case .copilot: "GitHub Copilot"
        case .claude: "Claude"
        case .chatgpt: "ChatGPT"
        }
    }

    var iconName: String {
        switch self {
        case .cursor: "cursorarrow.click"
        case .copilot: "chevron.left.forwardslash.chevron.right"
        case .claude: "sparkle"
        case .chatgpt: "bubble.left.and.bubble.right"
        }
    }

    var enabledKey: String { "\(rawValue)Enabled" }

    var displayModeKey: String { "\(rawValue)MenuBarShowPercent" }

    var keychainKey: KeychainKey {
        switch self {
        case .cursor: .cursorCookies
        case .copilot: .copilotCookies
        case .claude: .claudeCookies
        case .chatgpt: .chatGPTCookies
        }
    }

    var signInTitle: String { "Sign in to \(errorNoun)" }

    var errorNoun: String {
        switch self {
        case .cursor: "Cursor"
        case .copilot: "GitHub"
        case .claude: "Claude"
        case .chatgpt: "ChatGPT"
        }
    }

    var clearsCredentialOnAuthExpiry: Bool {
        switch self {
        case .cursor, .claude: false
        case .copilot, .chatgpt: true
        }
    }

    var accentColor: Color {
        switch self {
        case .cursor: .purple
        case .copilot: .blue
        case .claude: .orange
        case .chatgpt: .white
        }
    }

    static let orderStorageKey = "providerOrder"
    static let defaultOrderRaw = "cursor,copilot,claude,chatgpt"

    static func ordered(from raw: String) -> [Provider] {
        let stored = raw.split(separator: ",").compactMap { Provider(rawValue: String($0)) }
        let missing = allCases.filter { !stored.contains($0) }
        return (stored + missing).filter(\.isAvailable)
    }

    static func raw(from providers: [Provider]) -> String {
        providers.map(\.rawValue).joined(separator: ",")
    }
}
