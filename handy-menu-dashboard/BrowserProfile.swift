import Foundation

nonisolated struct BrowserProfile: Identifiable, Hashable, Sendable {
    let name: String
    let directory: URL
    var id: URL { directory }
}

extension Browser.Engine {
    var profileRoot: URL? {
        switch self {
        case .gecko(let root), .chromium(let root, _, _): root
        case .webkit: nil
        }
    }
}
