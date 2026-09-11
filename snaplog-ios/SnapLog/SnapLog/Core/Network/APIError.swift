import Foundation

enum APIError: Error, Equatable {
    case invalidURL
    case invalidResponse
    case unauthorized
    case httpStatus(Int)
    case decoding(underlying: String)
    case network(underlying: String)
}
