//
//  AuthModels.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import Foundation

/// Request body for `POST /auth/apple`.
struct AppleAuthRequest: Encodable, Sendable {
    let identityToken: String
    let fullName: String?
}

/// Response body from `POST /auth/apple`.
struct AuthResponse: Decodable, Sendable, Equatable {
    let token: String
    let userID: String
}
