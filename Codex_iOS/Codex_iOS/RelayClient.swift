import Foundation

protocol RelayClientProtocol {
    func health(baseURL: URL, token: String?) async throws -> RelayHealthResponse
    func listThreads(baseURL: URL, token: String?) async throws -> [RelayThreadSummary]
    func getThread(baseURL: URL, token: String?, threadID: String) async throws -> RelayThreadResponse
    func chat(baseURL: URL, token: String?, payload: RelayChatRequest) async throws -> RelayChatResponse
}

struct RelayClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func health(baseURL: URL, token: String?) async throws -> RelayHealthResponse {
        let request = try makeRequest(baseURL: baseURL, path: "/health", method: "GET", token: token)
        return try await send(request)
    }

    func listThreads(baseURL: URL, token: String?) async throws -> [RelayThreadSummary] {
        let request = try makeRequest(baseURL: baseURL, path: "/v1/threads", method: "GET", token: token)
        return try await send(request)
    }

    func getThread(baseURL: URL, token: String?, threadID: String) async throws -> RelayThreadResponse {
        let path = "/v1/threads/\(threadID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? threadID)"
        let request = try makeRequest(baseURL: baseURL, path: path, method: "GET", token: token)
        return try await send(request)
    }

    func chat(baseURL: URL, token: String?, payload: RelayChatRequest) async throws -> RelayChatResponse {
        var request = try makeRequest(baseURL: baseURL, path: "/v1/chat", method: "POST", token: token)
        request.httpBody = try JSONEncoder().encode(payload)
        return try await send(request)
    }

    private func makeRequest(baseURL: URL, path: String, method: String, token: String?) throws -> URLRequest {
        guard let endpoint = URL(string: path, relativeTo: baseURL) else {
            throw RelayClientError.invalidURL
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let cleanToken = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cleanToken, !cleanToken.isEmpty {
            request.setValue(cleanToken, forHTTPHeaderField: "x-relay-token")
        }

        return request
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RelayClientError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw RelayClientError.network("Missing HTTP response")
        }

        guard (200..<300).contains(http.statusCode) else {
            if let server = try? RelayCoders.makeDecoder().decode(RelayErrorResponse.self, from: data) {
                throw RelayClientError.server(server.error)
            }

            let body = String(data: data, encoding: .utf8) ?? "unknown server error"
            throw RelayClientError.server("HTTP \(http.statusCode): \(body)")
        }

        do {
            return try RelayCoders.makeDecoder().decode(T.self, from: data)
        } catch {
            throw RelayClientError.decoding(error.localizedDescription)
        }
    }
}

extension RelayClient: RelayClientProtocol {}

enum RelayClientError: LocalizedError {
    case invalidURL
    case network(String)
    case server(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid relay URL"
        case let .network(message):
            return "Network error: \(message)"
        case let .server(message):
            return "Relay error: \(message)"
        case let .decoding(message):
            return "Response parse error: \(message)"
        }
    }
}
