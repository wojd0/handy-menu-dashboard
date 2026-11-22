import Foundation

struct UsageBar: Hashable, Identifiable {
    static let primary = UsageBar(id: "usage", title: "Usage")

    let id: String
    let title: String
    var section: String?
}
