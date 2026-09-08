import Foundation
import JWTKit
import NIOConcurrencyHelpers
import Vapor
struct AppleJWKSVerifier: Sendable {
    static let jwksURL = URI("https://appleid.apple.com/auth/keys")
    private struct JWKSResponse: Decodable {
        let keys: [JWK]
    }
    private struct JWK: Decodable {
        let kty: String
        let kid: String
        let n: String
        let e: String
    }
    private final class Cache: @unchecked Sendable {
        let signers = NIOLockedValueBox<[String: JWTSigner]>([:])
    }
    private let cache = Cache()
    func verify<Payload: JWTPayload>(_ token: String, as payload: Payload.Type, on client: any Client) async throws -> Payload {
        let segments = token.split(separator: ".")
        guard segments.count == 3,
              let headerData = Data(base64URLEncoded: String(segments[0])),
              let header = try? JSONDecoder().decode([String: String].self, from: headerData),
              let kid = header["kid"]
        else {
            throw Abort(.unauthorized, reason: "Malformed identity token.")
        }
        let signer = try await signer(forKid: kid, on: client)
        return try signer.verify(token, as: Payload.self)
    }
    private func signer(forKid kid: String, on client: any Client) async throws -> JWTSigner {
        if let cached = cache.signers.withLockedValue({ $0[kid] }) { return cached }
        let response = try await client.get(Self.jwksURL)
        guard response.status == .ok else {
            throw Abort(.serviceUnavailable, reason: "Could not fetch Apple JWKS.")
        }
        let jwks = try response.content.decode(JWKSResponse.self)
        var signers: [String: JWTSigner] = [:]
        for jwk in jwks.keys where jwk.kty == "RSA" {
            guard let rsaKey = try? RSAKey(modulus: jwk.n, exponent: jwk.e) else { continue }
            signers[jwk.kid] = JWTSigner.rs256(key: rsaKey)
        }
        cache.signers.withLockedValue { $0 = signers }
        guard let signer = signers[kid] else {
            throw Abort(.unauthorized, reason: "Unknown Apple signing key.")
        }
        return signer
    }
}
extension Data {
    init?(base64URLEncoded string: String) {
        let padded = string.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = padded.count % 4 == 0 ? 0 : 4 - padded.count % 4
        self.init(base64Encoded: padded + String(repeating: "=", count: padding))
    }
}
