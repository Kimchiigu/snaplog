//
//  AppleSignInService.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 10/09/26.
//

import AuthenticationServices
import Foundation

/// Tracks the health of the Sign in with Apple credential behind the active session.
///
/// The backend JWT is valid for 30 days, but the user can revoke SnapLog at any time
/// in Settings → Apple ID → Sign-In & Security. This service asks Apple whether the
/// credential is still authorized so `AppState` can drop a stale session on launch.
struct AppleSignInService: Sendable {

    /// The `appleUserId` claim of the backend session JWT, or `nil` when the token
    /// isn't signed in with Apple (email / dev accounts skip credential checks).
    static func appleUserId(from sessionToken: String) -> String? {
        // JWT = header.payload.signature; the payload is base64url-encoded JSON.
        let segments = sessionToken.split(separator: ".")
        guard segments.count == 3 else { return nil }

        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }

        guard let data = Data(base64Encoded: base64),
              let claims = try? JSONDecoder().decode([String: String].self, from: data)
        else { return nil }
        return claims["appleUserId"]
    }

    /// True when the credential belongs to a real Apple sign-in (not the
    /// `email:`-prefixed or `dev:`-prefixed accounts used by the other flows).
    static func isAppleAccount(_ appleUserId: String?) -> Bool {
        guard let appleUserId, !appleUserId.isEmpty else { return false }
        return !appleUserId.hasPrefix("email:") && !appleUserId.hasPrefix("dev-")
    }

    init() {}

    /// Maps `getCredentialState`'s callback API to async/await.
    func credentialState(for userId: String) async -> ASAuthorizationAppleIDProvider.CredentialState {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userId) { state, _ in
                continuation.resume(returning: state)
            }
        }
    }

    /// Whether the Apple credential behind `userId` is still authorized.
    /// Revoked, not-found and transferred credentials all end the session.
    func isSessionValid(for userId: String) async -> Bool {
        await credentialState(for: userId) == .authorized
    }
}
