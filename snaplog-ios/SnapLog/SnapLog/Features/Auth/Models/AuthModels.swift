import Foundation

struct AppleAuthRequest: Encodable, Sendable {
    let identityToken: String
}

struct RegisterRequest: Encodable, Sendable {
    let email: String
    let password: String
    let displayName: String
}

struct LoginRequest: Encodable, Sendable {
    let email: String
    let password: String
}

struct DevAuthRequest: Encodable, Sendable {
    let displayName: String
}

struct UserDTO: Decodable, Sendable, Equatable {
    let id: UUID?
    let email: String
    let displayName: String
    let avatarUrl: String?
}

struct AuthResponse: Decodable, Sendable, Equatable {
    let token: String
    let user: UserDTO
}
