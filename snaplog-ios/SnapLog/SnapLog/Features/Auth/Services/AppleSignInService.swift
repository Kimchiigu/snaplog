
import AuthenticationServices
import Foundation

struct AppleSignInService: Sendable {

    static func appleUserId(from sessionToken: String) -> String? {
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

    static func isAppleAccount(_ appleUserId: String?) -> Bool {
        guard let appleUserId, !appleUserId.isEmpty else { return false }
        return !appleUserId.hasPrefix("email:") && !appleUserId.hasPrefix("dev-")
    }

    init() {}

    func credentialState(for userId: String) async -> ASAuthorizationAppleIDProvider.CredentialState {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userId) { state, _ in
                continuation.resume(returning: state)
            }
        }
    }

    func isSessionValid(for userId: String) async -> Bool {
        await credentialState(for: userId) == .authorized
    }
}
