import Foundation
@testable import handy_menu_dashboard

struct NetworkFailure: Error {}

func httpResponse(
    for request: URLRequest,
    status: Int = 200,
    data: Data
) throws -> (Data, URLResponse) {
    let response = HTTPURLResponse(
        url: request.url!,
        statusCode: status,
        httpVersion: "HTTP/2",
        headerFields: ["Content-Type": "application/json"]
    )!
    return (data, response)
}

func httpResponse(
    for request: URLRequest,
    status: Int = 200,
    json: Any
) throws -> (Data, URLResponse) {
    try httpResponse(for: request, status: status, data: JSONSerialization.data(withJSONObject: json))
}

final class InMemoryPreferenceStore: PreferenceStoring {
    private var storage: [String: Any] = [:]

    init(_ initial: [String: Any] = [:]) {
        storage = initial
    }

    func object(forKey defaultName: String) -> Any? {
        storage[defaultName]
    }

    func set(_ value: Any?, forKey defaultName: String) {
        storage[defaultName] = value
    }
}
