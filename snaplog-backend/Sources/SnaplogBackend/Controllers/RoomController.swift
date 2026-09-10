import Fluent
import Foundation
import Redis
@preconcurrency import RediStack
import Vapor
enum TimelineCache {
    static let roomEventsChannel = "room_events"
    static func zsetKey(roomId: UUID) -> String { "room:\(roomId.uuidString):timeline" }
    struct Entry: Codable {
        let s3Key: String
        let duration: Double
        let createdAt: Double
    }
}
struct RoomController: RouteCollection {
    struct PlaybackClipDTO: Content {
        let s3Key: String
        let url: String
        let duration: Double
        let createdAt: Date
        let authorName: String
    }

    func boot(routes: any RoutesBuilder) throws {
        routes.get("rooms", use: index)
        routes.post("rooms", use: create)
        routes.post("rooms", "join", use: join)
        routes.get("rooms", ":roomID", "playback", use: playback)
        routes.patch("rooms", ":roomID", use: update)
    }

    /// Request body for `PATCH /api/rooms/:roomID`.
    struct UpdateRoomRequest: Content {
        var name: String?
        var maxMembers: Int?
    }

    /// Updates a room's name and/or size. The caller must be a member.
    @Sendable
    func update(req: Request) async throws -> RoomDTO {
        let user = try req.authenticatedUser
        guard let roomID = req.parameters.get("roomID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid room id.")
        }
        let body = try req.content.decode(UpdateRoomRequest.self)

        let room = try await Room.query(on: req.db)
            .filter(\.$id == roomID)
            .with(\.$members)
            .first()
        guard let room else { throw Abort(.notFound, reason: "No room found.") }
        guard room.members.contains(where: { $0.id == user.id }) else {
            throw Abort(.forbidden, reason: "You're not a member of this room.")
        }

        if let name = body.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            room.name = name
        }
        if let maxMembers = body.maxMembers {
            guard [2, 3, 4, 5, 20].contains(maxMembers) else {
                throw Abort(.badRequest, reason: "maxMembers must be 2, 3, 4, 5, or 20.")
            }
            guard room.members.count <= maxMembers else {
                throw Abort(.badRequest, reason: "Room already has \(room.members.count) members.")
            }
            room.maxMembers = maxMembers
        }
        try await room.update(on: req.db)

        let pivots = try await RoomMember.query(on: req.db)
            .filter(\.$room.$id == roomID)
            .with(\.$user)
            .all()
        let summaries = pivots.map {
            RoomMember.Summary(role: $0.role, joinedAt: $0.joinedAt, user: $0.user)
        }
        return RoomDTO(room: room, members: summaries, timeline: [])
    }

    /// Pre-signed GET URLs for every clip in a room, for client-side playback.
    @Sendable
    func playback(req: Request) async throws -> [PlaybackClipDTO] {
        let user = try req.authenticatedUser
        guard let roomId = req.parameters.get("roomID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid room id.")
        }
        try await MediaLogController.assertMembership(userId: user.id!, roomId: roomId, on: req.db)
        let logs = try await MediaLog.query(on: req.db)
            .filter(\.$room.$id == roomId)
            .with(\.$user)
            .sort(\.$createdAt, .descending)
            .all()
        let r2 = R2Service(req.r2)
        return try logs.compactMap { log in
            guard !log.s3Key.isEmpty, let createdAt = log.createdAt else { return nil }
            let key = log.s3Key
            let url: String
            do {
                url = try r2.presignedGetURL(key: key)
            } catch {
                req.logger.warning("R2 presign GET failed for \(key): \(error)")
                return nil
            }
            return PlaybackClipDTO(
                s3Key: key,
                url: url,
                duration: log.duration,
                createdAt: createdAt,
                authorName: log.user.displayName
            )
        }
    }
    @Sendable
    func index(req: Request) async throws -> [RoomDTO] {
        let user = try req.authenticatedUser
        let rooms = try await req.trace.span("db.roomsForUser") {
            try await user.$rooms.query(on: req.db).all()
        }
        let roomIds = rooms.compactMap(\.id)
        let pivots = try await req.trace.span("db.roomMembers") {
            try await RoomMember.query(on: req.db)
                .filter(\.$room.$id ~~ roomIds)
                .with(\.$user)
                .all()
        }
        let membersByRoom = Dictionary(grouping: pivots, by: { $0.$room.id })
            .mapValues { $0.map { RoomMember.Summary(role: $0.role, joinedAt: $0.joinedAt, user: $0.user) } }
        return try await withThrowingTaskGroup(of: (Int, RoomDTO).self) { group in
            for (idx, room) in rooms.enumerated() {
                let redis = req.redis
                let key = TimelineCache.zsetKey(roomId: room.id!)
                let summaries = membersByRoom[room.id!] ?? []
                group.addTask {
                    let data = (try? await redis.zrangebyscore(
                        from: RedisKey(key),
                        withScoresBetween: (.inclusive(-.infinity), .inclusive(.infinity))
                    ).get()) ?? []
                    let entries: [TimelineCache.Entry] = data.compactMap { member in
                        guard let json = member.string?.data(using: .utf8) else { return nil }
                        return try? JSONDecoder().decode(TimelineCache.Entry.self, from: json)
                    }
                    .sorted { $0.createdAt > $1.createdAt }
                    let dto = RoomDTO(
                        room: room,
                        members: summaries,
                        timeline: entries.map {
                            .init(s3Key: $0.s3Key, duration: $0.duration, createdAt: $0.createdAt)
                        }
                    )
                    return (idx, dto)
                }
            }
            var results = [RoomDTO?](repeating: nil, count: rooms.count)
            for try await (idx, dto) in group { results[idx] = dto }
            return results.compactMap { $0 }
        }
    }
    @Sendable
    func create(req: Request) async throws -> RoomDTO {
        let user = try req.authenticatedUser
        let body = try req.content.decode(CreateRoomRequest.self)
        guard body.roomType == "log" || body.roomType == "stack" else {
            throw Abort(.badRequest, reason: "roomType must be \"log\" or \"stack\".")
        }
        guard [2, 3, 4, 5, 20].contains(body.maxMembers) else {
            throw Abort(.badRequest, reason: "maxMembers must be 2, 3, 4, 5, or 20.")
        }
        var inviteCode = Self.generateInviteCode()
        while try await Room.query(on: req.db)
            .filter(\.$inviteCode == inviteCode)
            .first() != nil
        {
            inviteCode = Self.generateInviteCode()
        }
        let room = Room(
            name: body.name,
            roomType: body.roomType,
            maxMembers: body.maxMembers,
            inviteCode: inviteCode
        )
        try await req.trace.span("db.createRoom", detail: inviteCode) {
            try await room.create(on: req.db)
        }
        let membership = RoomMember(userId: user.id!, roomId: room.id!, role: "owner")
        try await req.trace.span("db.createOwnerMembership") {
            try await membership.create(on: req.db)
        }
        return RoomDTO(room: room, members: [
            .init(role: "owner", joinedAt: membership.joinedAt, user: user)
        ], timeline: [])
    }
    @Sendable
    func join(req: Request) async throws -> RoomDTO {
        let user = try req.authenticatedUser
        let body = try req.content.decode(JoinRoomRequest.self)
        guard body.inviteCode.count == 6 else {
            throw Abort(.badRequest, reason: "inviteCode must be 6 characters.")
        }
        let room = try await req.trace.span("db.findRoomByInviteCode", detail: body.inviteCode) {
            try await Room.query(on: req.db)
                .filter(\.$inviteCode == body.inviteCode)
                .with(\.$members)
                .first()
        }
        guard let room else {
            throw Abort(.notFound, reason: "No room found for this invite code.")
        }
        if room.members.contains(where: { $0.id == user.id }) {
            throw Abort(.conflict, reason: "Already a member of this room.")
        }
        guard room.members.count < room.maxMembers else {
            throw Abort(.forbidden, reason: "Room is full.")
        }
        let membership = RoomMember(userId: user.id!, roomId: room.id!, role: "member")
        try await req.trace.span("db.createMembership") {
            try await membership.create(on: req.db)
        }
        let pivots = try await RoomMember.query(on: req.db)
            .filter(\.$room.$id == room.id!)
            .with(\.$user)
            .all()
        let summaries = pivots.map {
            RoomMember.Summary(role: $0.role, joinedAt: $0.joinedAt, user: $0.user)
        }
        return RoomDTO(room: room, members: summaries, timeline: [])
    }
    private static func generateInviteCode() -> String {
        let allowed = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).map { _ in allowed.randomElement()! })
    }
}
