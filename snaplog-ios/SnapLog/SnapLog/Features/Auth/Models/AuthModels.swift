//
//  AuthModels.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import Foundation

/// Request body for `POST /api/auth/apple`.
struct AppleAuthRequest: Encodable, Sendable {
    let identityToken: String
}

/// Request body for `POST /api/auth/register`.
struct RegisterRequest: Encodable, Sendable {
    let email: String
    let password: String
    let displayName: String
}

/// Request body for `POST /api/auth/login`.
struct LoginRequest: Encodable, Sendable {
    let email: String
    let password: String
}

/// Request body for `POST /api/auth/dev` (development only).
struct DevAuthRequest: Encodable, Sendable {
    let displayName: String
}

/// The signed-in user's public profile (`User.Public`).
struct UserDTO: Decodable, Sendable, Equatable {
    let id: UUID?
    let email: String
    let displayName: String
    let avatarUrl: String?
}

/// Response body from `POST /api/auth/apple` and `POST /api/auth/dev`.
struct AuthResponse: Decodable, Sendable, Equatable {
    let token: String
    let user: UserDTO
}
