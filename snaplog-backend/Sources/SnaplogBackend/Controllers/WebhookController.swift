import Fluent
import Foundation
import Redis
@preconcurrency import RediStack
import Vapor

/// Asynchronous webhooks for direct-to-R2 uploads plus device registration for pushes.
struct WebhookController {
    /// External webhook lives at the root (R2 Event Notifications call it directly).
    func bootWebhook(routes: any RoutesBuilder) {
        routes.post("webhooks", "r2-upload-complete", use: r2UploadComplete)
    }

    /// Device registration lives under /api behind JWT auth.
    func bootDevices(routes: any RoutesBuilder) {
        let authed = routes.grouped(JWTAuthMiddleware())
        authed.post("devices", use: registerDevice)
    }

    struct R2EventNotification: Content {
        struct Record: Content {
            let key: String?
            let size: Int?
        }
        let bucket: String?
        let action: String?
        let `object`: Record?
    }

    /// Called by Cloudflare R2 Event Notifications when an object lands in the bucket.
    /// Keeps a Redis record of every seen upload so `POST /logs/confirm` can be reconciled
    /// and abandoned uploads (crashed client, dropped network) stay visible for cleanup
    /// via `GET /admin/api/orphan-uploads`.
    @Sendable
    func r2UploadComplete(req: Request) async throws -> Response {
        guard let secret = Environment.get("R2_WEBHOOK_SECRET") else {
            throw Abort(.serviceUnavailable, reason: "Webhook endpoint is not configured.")
        }
        guard req.headers.first(name: "X-Webhook-Secret") == secret else {
            throw Abort(.forbidden, reason: "Invalid webhook secret.")
        }
        let event = try req.content.decode(R2EventNotification.self)
        guard let key = event.object?.key, !key.isEmpty else {
            return Response(status: .ok)
        }
        // Test apps never boot Redis; the auth + decode path is what tests exercise.
        guard req.application.environment != .testing else {
            return Response(status: .ok)
        }
        let seenKey = RedisKey("snaplog:uploads:seen")
        let record = "\(key)|\(Date().timeIntervalSince1970)"
        _ = try? await req.redis.sadd(record, to: seenKey).get()
        _ = try? await req.redis.expire(seenKey, after: .seconds(60 * 60 * 48)).get()
        req.logger.info("R2 upload webhook: \(key) (\(event.object?.size ?? 0) bytes, action \(event.action ?? "?"))")
        return Response(status: .ok)
    }

    struct RegisterDeviceRequest: Content {
        let token: String
        let platform: String?
    }

    /// iOS registers its APNs token after login so the worker can push digest notifications.
    @Sendable
    func registerDevice(req: Request) async throws -> Response {
        let user = try req.authenticatedUser
        let body = try req.content.decode(RegisterDeviceRequest.self)
        guard !body.token.isEmpty else {
            throw Abort(.badRequest, reason: "token must not be empty.")
        }
        if let existing = try await DeviceToken.query(on: req.db).filter(\.$token == body.token).first() {
            existing.$user.id = user.id!
            existing.platform = body.platform ?? "ios"
            try await existing.update(on: req.db)
        } else {
            let device = DeviceToken(userId: user.id!, token: body.token, platform: body.platform ?? "ios")
            try await device.create(on: req.db)
        }
        req.logger.info("PUSH device registered: user \(user.displayName), token \(body.token.prefix(12))…")
        return Response(status: .created)
    }
}
