import Fluent
import Foundation
import Queues
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
struct MediaLogController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.post("logs", "upload-url", use: uploadURL)
        routes.post("logs", "confirm", use: confirm)
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
                StitchVideoJobPayload(roomId: body.roomId, s3Key: body.s3Key, duration: body.duration, traceId: req.trace.id)
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
