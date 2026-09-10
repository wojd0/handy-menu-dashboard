import Foundation

typealias UsageDataLoader = (URLRequest) async throws -> (Data, URLResponse)

enum DefaultDataLoader {
    static let live: UsageDataLoader = { try await URLSession.shared.data(for: $0) }
}
