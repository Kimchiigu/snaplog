import Fluent
import Foundation
import Queues
import Redis
@preconcurrency import RediStack
import Vapor
struct UploadURLRequest: Content {
    let roomId: UUID
    let fileExtension: String
}
struct UploadURLResponse: Content {
    let uploadURL: String
    let s3Key: String
}
struct ConfirmLogRequest: Content {
    let s3Key: String
    let duration: Double
    let roomId: UUID
}
/// Request body for `POST /api/logs/delete`.
struct DeleteLogRequest: Content {
    let roomId: UUID
    let s3Key: String
}

struct MediaLogController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.post("logs", "upload-url", use: uploadURL)
        routes.post("logs", "confirm", use: confirm)
        routes.post("logs", "delete", use: delete)
    }

    /// Deletes one of the caller's own logs from a room (DB row + timeline cache).
    @Sendable
    func delete(req: Request) async throws -> HTTPResponseStatus {
        let user = try req.authenticatedUser
        let body = try req.content.decode(DeleteLogRequest.self)
        try await Self.assertMembership(userId: user.id!, roomId: body.roomId, on: req.db)

        let log = try await MediaLog.query(on: req.db)
            .filter(\.$s3Key == body.s3Key)
            .filter(\.$room.$id == body.roomId)
            .first()
        guard let log else { throw Abort(.notFound, reason: "No log found for that key.") }
        guard log.$user.id == user.id else {
            throw Abort(.forbidden, reason: "You can only delete your own logs.")
        }
        try await log.delete(on: req.db)

        // Keep the room's cached timeline in sync.
        let key = TimelineCache.zsetKey(roomId: body.roomId)
        let redis = req.redis
        let data = (try? await redis.zrangebyscore(
            from: RedisKey(key),
            withScoresBetween: (.inclusive(-.infinity), .inclusive(.infinity))
        ).get()) ?? []
        for member in data {
            guard let original = member.string as String?,
                  let json = original.data(using: String.Encoding.utf8),
                  let entry = try? JSONDecoder().decode(TimelineCache.Entry.self, from: json),
                  entry.s3Key == body.s3Key else { continue }
            _ = try? await redis.send(
                command: "ZREM",
                with: [RESPValue(from: RedisKey(key)), RESPValue(from: original)]
            ).get()
        }
        // Let the room's members know a clip disappeared.
        RoomController.publishRoomEvent(on: req, event: "LOG_DELETED", roomId: body.roomId, s3Key: body.s3Key)
        return .noContent
    }
    @Sendable
    func uploadURL(req: Request) async throws -> UploadURLResponse {
        let user = try req.authenticatedUser
        let body = try req.content.decode(UploadURLRequest.self)
        try await req.trace.span("db.assertMembership") {
            try await Self.assertMembership(userId: user.id!, roomId: body.roomId, on: req.db)
        }
        let allowedExtensions = ["mp4", "mov"]
        guard allowedExtensions.contains(body.fileExtension.lowercased()) else {
            throw Abort(.badRequest, reason: "fileExtension must be mp4 or mov.")
        }
        let s3Key = "raw/\(body.roomId.uuidString)/\(user.id!.uuidString)-\(UUID().uuidString).\(body.fileExtension.lowercased())"
        let r2 = R2Service(req.r2)
        let url: String
        do {
            url = try await req.trace.span("r2.presignPut", detail: s3Key) {
                try r2.presignedPutURL(
                    key: s3Key,
                    contentType: body.fileExtension.lowercased() == "mov"
                        ? "video/quicktime" : "video/mp4"
                )
            }
        } catch {
            req.logger.error("R2 pre-sign failed: \(error)")
            throw Abort(.serviceUnavailable, reason: "Object storage is not configured.")
        }
        return UploadURLResponse(uploadURL: url, s3Key: s3Key)
    }
    @Sendable
    func confirm(req: Request) async throws -> Response {
        let user = try req.authenticatedUser
        let body = try req.content.decode(ConfirmLogRequest.self)
        try await req.trace.span("db.assertMembership") {
            try await Self.assertMembership(userId: user.id!, roomId: body.roomId, on: req.db)
        }
        guard body.duration > 0, body.duration <= 60 else {
            throw Abort(.badRequest, reason: "duration must be between 0 and 60 seconds.")
        }

        // One log per user per clock hour: a log at 9:25 blocks the next
        // until 10:00. Checking the handful of most recent logs is enough.
        let recentLogs = try await MediaLog.query(on: req.db)
            .filter(\.$user.$id == user.id!)
            .filter(\.$room.$id == body.roomId)
            .sort(\.$createdAt, .descending)
            .limit(5)
            .all()
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        if recentLogs.map(\.createdAt).compactMap({ $0 })
            .contains(where: { calendar.isDate($0, equalTo: now, toGranularity: .hour) }) {
            throw Abort(.conflict, reason: "You already logged this hour. Try again at the top of the hour.")
        }

        let log = MediaLog(
            userId: user.id!,
            roomId: body.roomId,
            s3Key: body.s3Key,
            duration: body.duration
        )
        try await req.trace.span("db.createMediaLog", detail: body.s3Key) {
            try await log.create(on: req.db)
        }
        try await req.trace.span("queue.enqueueStitch") {
            try await req.queue.dispatch(
                StitchVideoJob.self,
                StitchVideoJobPayload(roomId: body.roomId, s3Key: body.s3Key, duration: body.duration, traceId: req.trace.id),
                maxRetryCount: DlqService.maxAttempts
            )
        }
        // Tell the room's members a new clip just landed (the stitched digest
        // gets its own NEW_DIGEST_READY event once the worker finishes).
        req.logger.info("new log confirmed: room \(body.roomId.uuidString) by \(user.displayName) (\(body.s3Key)) — broadcasting + pushing")
        RoomController.publishRoomEvent(
            on: req, event: "NEW_LOG", roomId: body.roomId, s3Key: body.s3Key,
            authorName: user.displayName
        )
        // Push notification for members not connected over the WebSocket.
        let app = req.application
        Task.detached {
            await PushNotificationService.notifyRoomNewLog(
                app: app, roomId: body.roomId, authorName: user.displayName
            )
        }
        return Response(status: .accepted)
    }
    static func assertMembership(userId: UUID, roomId: UUID, on db: any Database) async throws {
        let isMember = try await RoomMember.query(on: db)
            .filter(\.$user.$id == userId)
            .filter(\.$room.$id == roomId)
            .first() != nil
        guard isMember else {
            throw Abort(.forbidden, reason: "You are not a member of this room.")
        }
    }
}
