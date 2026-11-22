import Foundation
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

enum Provider: String, CaseIterable, Identifiable, Codable, Transferable {
    case cursor
    case copilot
    case claude
    case chatgpt
    case antigravity

    var id: String { rawValue }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }

    var displayName: String {
        switch self {
        case .cursor: "Cursor"
        case .copilot: "GitHub Copilot"
        case .claude: "Claude"
        case .chatgpt: "ChatGPT"
        case .antigravity: "Antigravity"
        }
    }

    var iconName: String {
        switch self {
        case .cursor: "cursorarrow.click"
        case .copilot: "chevron.left.forwardslash.chevron.right"
        case .claude: "sparkle"
        case .chatgpt: "bubble.left.and.bubble.right"
        case .antigravity: "arrow.up.circle"
        }
    }

    var enabledKey: String { "\(rawValue)Enabled" }

    var displayModeKey: String { "\(rawValue)MenuBarShowPercent" }

    var hiddenUsageBarsKey: String { "\(rawValue)HiddenUsageBars" }

    var keychainKey: KeychainKey {
        switch self {
        case .cursor: .cursorCookies
        case .copilot: .copilotCookies
        case .claude: .claudeCookies
        case .chatgpt: .chatGPTCookies
        case .antigravity: .antigravityCookies
        }
    }

    var monetaryLabel: String? {
        switch self {
        case .cursor, .claude: "Dollars"
        case .copilot, .chatgpt: "Credits"
        case .antigravity: nil
        }
    }

    var signInTitle: String { "Sign in to \(errorNoun)" }

    var errorNoun: String {
        switch self {
        case .cursor: "Cursor"
        case .copilot: "GitHub"
        case .claude: "Claude"
        case .chatgpt: "ChatGPT"
        case .antigravity: "Antigravity"
        }
    }

    var clearsCredentialOnAuthExpiry: Bool {
        switch self {
        case .cursor, .claude: false
        case .copilot, .chatgpt, .antigravity: true
        }
    }

    var accentNeedsOutline: Bool {
        switch self {
        case .cursor, .copilot, .claude, .antigravity: false
        case .chatgpt: true
        }
    }

    var accentColor: Color {
        switch self {
        case .cursor: .purple
        case .copilot: .blue
        case .claude: .orange
        case .chatgpt: .white
        case .antigravity: .cyan
        }
    }

    static let orderStorageKey = "providerOrder"
    static let defaultOrderRaw = "cursor,copilot,claude,chatgpt,antigravity"

    static func ordered(from raw: String) -> [Provider] {
        let stored = raw.split(separator: ",").compactMap { Provider(rawValue: String($0)) }
        let missing = allCases.filter { !stored.contains($0) }
        return stored + missing
    }

    static func raw(from providers: [Provider]) -> String {
        providers.map(\.rawValue).joined(separator: ",")
    }
}
