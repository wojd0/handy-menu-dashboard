import Foundation
import CoreTransferable
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
        switch self {
        case .cursor: true
        case .copilot: FeatureFlags.showGitHubSettings
        case .claude: true
        case .chatgpt: true
        }
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
