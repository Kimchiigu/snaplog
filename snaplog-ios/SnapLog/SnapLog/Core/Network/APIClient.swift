import Foundation

final class APIClient: Sendable, APIClientProtocol {

    private let session: URLSession
    private let baseURL: URL
    private let tokenProvider: @Sendable () -> String?
    private let onUnauthorized: (@Sendable () -> Void)?

    init(
        session: URLSession = .shared,
        baseURL: URL = AppConfig.apiBaseURL,
        tokenProvider: @escaping @Sendable () -> String? = { nil },
        onUnauthorized: (@Sendable () -> Void)? = nil
    ) {
        self.session = session
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.onUnauthorized = onUnauthorized
    }

    func request<Body: Encodable, Response: Decodable>(
        path: String,
        method: HTTPMethod,
        body: Body? = nil
    ) async throws -> Response {
        let data = try await send(path: path, method: method, bodyData: encode(body))
        do {
            return try JSONDecoder.api.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(underlying: error.localizedDescription)
        }
    }

    func request<Response: Decodable>(path: String, method: HTTPMethod) async throws -> Response {
        let data = try await send(path: path, method: method, bodyData: nil)
        do {
            return try JSONDecoder.api.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(underlying: error.localizedDescription)
        }
    }

    func request<Body: Encodable>(path: String, method: HTTPMethod, body: Body?) async throws {
        _ = try await send(path: path, method: method, bodyData: encode(body))
    }

    func requestVoid<Body: Encodable>(path: String, method: HTTPMethod, body: Body?) async throws {
        _ = try await send(path: path, method: method, bodyData: encode(body))
    }

    private func encode<Body: Encodable>(_ body: Body?) throws -> Data? {
        guard let body else { return nil }
        do {
            return try JSONEncoder.api.encode(body)
        } catch {
            throw APIError.network(underlying: error.localizedDescription)
        }
    }

    private func send(path: String, method: HTTPMethod, bodyData: Data?) async throws -> Data {
        guard let url = URL(string: baseURL.absoluteString + path) else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url.absoluteURL)
        request.httpMethod = method.rawValue
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if method == .post {
            request.setValue(UUID().uuidString, forHTTPHeaderField: "Idempotency-Key")
        }
        request.setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")
        if let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            switch HTTPStatusCategory(http.statusCode) {
            case .success:
                return data
            case .unauthorized:
                onUnauthorized?()
                throw APIError.unauthorized
            case .failure:
                throw APIError.httpStatus(http.statusCode)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(underlying: error.localizedDescription)
        }
    }
}

protocol APIClientProtocol: Sendable {
    func request<Body: Encodable, Response: Decodable>(
        path: String, method: HTTPMethod, body: Body?
    ) async throws -> Response
    func request<Response: Decodable>(path: String, method: HTTPMethod) async throws -> Response
    func request<Body: Encodable>(path: String, method: HTTPMethod, body: Body?) async throws
    func requestVoid<Body: Encodable>(path: String, method: HTTPMethod, body: Body?) async throws
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

private enum HTTPStatusCategory {
    case success
    case unauthorized
    case failure

    init(_ statusCode: Int) {
        switch statusCode {
        case 200..<300: self = .success
        case 401: self = .unauthorized
        default: self = .failure
        }
    }
}

extension JSONDecoder {
    static let api: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension JSONEncoder {
    static let api: JSONEncoder = JSONEncoder()
}
