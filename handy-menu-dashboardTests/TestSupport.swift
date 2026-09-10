import Foundation

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
