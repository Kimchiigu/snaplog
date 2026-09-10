import Fluent
import Foundation
import Redis
@preconcurrency import RediStack
import Vapor

/// Replays cached responses for retried POST requests carrying the same
/// `Idempotency-Key` header, so a flaky connection can't double-log or
/// double-join. Keys are scoped per user and expire after 24 hours.
struct IdempotencyMiddleware: AsyncMiddleware {

    private struct CachedResponse: Codable {
        let status: UInt
        let contentType: String?
        let body: String?
    }


    func respond(to req: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard req.method == .POST,
              let key = req.headers.first(name: "Idempotency-Key"),
              let user = try? req.authenticatedUser,
              let userId = user.id
        else { return try await next.respond(to: req) }

        let redisKey = RedisKey("idem:\(userId.uuidString):\(key)")
        if let cachedData = try? await req.redis.get(redisKey).get(),
           let data = cachedData.data,
           let cached = try? JSONDecoder().decode(CachedResponse.self, from: data) {
            req.logger.info("idempotency replay for key \(key)")
            let body: Response.Body = cached.body.map { Response.Body(string: $0) } ?? .empty
            let response = Response(status: HTTPResponseStatus(statusCode: Int(cached.status)), body: body)
            if let contentType = cached.contentType {
                response.headers.replaceOrAdd(name: .contentType, value: contentType)
            }
            response.headers.replaceOrAdd(name: "Idempotent-Replay", value: "true")
            return response
        }

        let response = try await next.respond(to: req)

        // Only successful responses are cached — failures may be retried for real.
        guard response.status.code >= 200 && response.status.code < 300 else { return response }

        let bodyString = response.body.data.map { String(decoding: $0, as: UTF8.self) }
        let cached = CachedResponse(
            status: UInt(response.status.code),
            contentType: response.headers.first(name: .contentType),
            body: bodyString
        )
        if let encoded = try? JSONEncoder().encode(cached) {
            _ = try? await req.redis.send(
                command: "SETEX",
                with: [
                    RESPValue(from: redisKey),
                    RESPValue(from: "86400"),
                    RESPValue(from: String(decoding: encoded, as: UTF8.self)),
                ]
            ).get()
        }
        return response
    }
}
