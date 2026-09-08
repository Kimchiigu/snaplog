import Crypto
import Fluent
import Foundation
import JWT
import JWTKit
import Redis
import Vapor

struct AdminToken: JWTPayload {
    let sub: SubjectClaim
    let exp: ExpirationClaim

    func verify(using signer: some JWTSigner) throws {
        guard sub.value == "admin" else {
            throw Abort(.unauthorized, reason: "Not an admin token.")
        }
        try exp.verifyNotExpired()
    }
}

struct AdminAuthMiddleware: AsyncMiddleware {
    static let cookieName = "admin_token"

    func respond(to req: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        if let token = req.cookies[Self.cookieName]?.string,
           (try? req.jwt.verify(token, as: AdminToken.self)) != nil {
            return try await next.respond(to: req)
        }
        return req.redirect(to: "/admin/login")
    }
}

struct AdminController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("admin", "dashboard", use: dashboard)
        routes.get("admin", "users", use: usersPage)
        routes.get("admin", "users", ":id", "edit", use: userEditPage)
        routes.post("admin", "users", ":id", use: userUpdate)
        routes.post("admin", "users", ":id", "delete", use: userDelete)
        routes.get("admin", "rooms", use: roomsPage)
        routes.post("admin", "rooms", use: roomCreate)
        routes.get("admin", "rooms", ":id", "edit", use: roomEditPage)
        routes.post("admin", "rooms", ":id", use: roomUpdate)
        routes.post("admin", "rooms", ":id", "delete", use: roomDelete)
        routes.get("admin", "media", use: mediaPage)
        routes.post("admin", "media", ":id", "delete", use: mediaDelete)
        routes.get("admin", "api", "netlogs", use: netlogsJSON)
        routes.get("admin", "upload-test", use: uploadTestPage)
        routes.post("admin", "upload-test", use: uploadSubmit)
    }

    struct LoginForm: Content {
        let username: String
        let password: String?
        let passwordHash: String?

        var acceptedPassword: String? { password ?? passwordHash }
    }

    @Sendable
    func loginPage(req: Request) async throws -> View {
        try await req.view.render("login", ["error": req.session.data["loginError"] ?? ""])
    }

    @Sendable
    func loginSubmit(req: Request) async throws -> Response {
        let form = try req.content.decode(LoginForm.self)
        let expectedUser = Environment.get("ADMIN_USERNAME") ?? "admin"
        let expectedPass = Environment.get("ADMIN_PASSWORD") ?? "admin123"
        let provided = form.acceptedPassword ?? ""
        let expectedHash = SHA256.hash(data: Data(expectedPass.utf8)).map { String(format: "%02x", $0) }.joined()
        let matches = provided == expectedPass || provided.lowercased() == expectedHash
        guard form.username == expectedUser, matches else {
            req.session.data["loginError"] = "Invalid username or password."
            return req.redirect(to: "/admin/login")
        }
        let token = try req.jwt.sign(AdminToken(
            sub: SubjectClaim(stringLiteral: expectedUser),
            exp: ExpirationClaim(value: Date().addingTimeInterval(Self.tokenLifetime))
        ))
        req.session.data["loginError"] = nil
        let response = req.redirect(to: "/admin/dashboard")
        response.cookies[AdminAuthMiddleware.cookieName] = .init(
            string: token,
            expires: Date().addingTimeInterval(Self.tokenLifetime),
            maxAge: Int(Self.tokenLifetime),
            path: "/",
            isHTTPOnly: true,
            sameSite: .lax
        )
        return response
    }

    @Sendable
    func logout(req: Request) async throws -> Response {
        let response = req.redirect(to: "/admin/login")
        response.cookies[AdminAuthMiddleware.cookieName] = .expired
        req.session.destroy()
        return response
    }

    static let tokenLifetime: TimeInterval = 60 * 60 * 24 * 7

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    struct UserRow: Encodable {
        let id: UUID?
        let displayName: String
        let email: String
        let appleUserId: String
        let createdAt: String
    }

    struct RoomRow: Encodable {
        let id: UUID?
        let name: String
        let roomType: String
        let inviteCode: String
        let maxMembers: Int
        let memberCount: Int
        let createdAt: String
    }

    struct MediaRow: Encodable {
        let id: UUID?
        let user: String
        let room: String
        let s3Key: String
        let duration: Double
        let createdAt: String
        let previewURL: String
        let kind: String
    }

    struct UserOption: Encodable { let id: UUID?; let displayName: String }
    struct RoomOption: Encodable { let id: UUID?; let label: String }

    private func userRows(on db: any Database) async throws -> [UserRow] {
        try await User.query(on: db).sort(\.$createdAt, .descending).all().map {
            .init(
                id: $0.id,
                displayName: $0.displayName,
                email: $0.email,
                appleUserId: $0.appleUserId,
                createdAt: $0.createdAt.map(Self.dateFormatter.string) ?? "-"
            )
        }
    }

    private func roomRows(on db: any Database) async throws -> [RoomRow] {
        try await Room.query(on: db).with(\.$members).sort(\.$createdAt, .descending).all().map {
            .init(
                id: $0.id,
                name: $0.name ?? "-",
                roomType: $0.roomType,
                inviteCode: $0.inviteCode,
                maxMembers: $0.maxMembers,
                memberCount: $0.$members.value?.count ?? 0,
                createdAt: $0.createdAt.map(Self.dateFormatter.string) ?? "-"
            )
        }
    }

    private func mediaRows(on req: Request, limit: Int? = nil) async throws -> [MediaRow] {
        let r2 = R2Service(req.application.r2)
        var query = MediaLog.query(on: req.db)
            .with(\.$user)
            .with(\.$room)
            .sort(\.$createdAt, .descending)
        if let limit { query = query.limit(limit) }
        return try await query.all().map {
            let url = (try? r2.presignedGetURL(key: $0.s3Key)) ?? ""
            let ext = ($0.s3Key as NSString).pathExtension.lowercased()
            let kind = ["jpg", "jpeg", "png", "webp", "gif", "heic"].contains(ext) ? "image"
                : ["mp4", "mov", "m4v"].contains(ext) ? "video"
                : "other"
            return .init(
                id: $0.id,
                user: $0.$user.value?.displayName ?? "?",
                room: $0.$room.value?.name ?? $0.$room.id.uuidString.prefix(8).description,
                s3Key: $0.s3Key,
                duration: $0.duration,
                createdAt: $0.createdAt.map(Self.dateFormatter.string) ?? "-",
                previewURL: url,
                kind: kind
            )
        }
    }

    @Sendable
    func dashboard(req: Request) async throws -> View {
        let userCount = try await User.query(on: req.db).count()
        let roomCount = try await Room.query(on: req.db).count()
        let mediaCount = try await MediaLog.query(on: req.db).count()
        let totalDuration = try await MediaLog.query(on: req.db).sum(\.$duration) ?? 0.0
        let counters = await NetworkMonitor.counters(on: req.redis)
        struct PodRow: Encodable {
            let id: String
            let role: String
            let host: String
            let startedAt: String
            let lastSeen: String
            let requestCount: Int
        }
        struct LogRow: Encodable {
            let t: String
            let ip: String
            let source: String
            let method: String
            let path: String
            let status: Int
            let durationMs: Double
            let pod: String
        }
        struct Context: Encodable {
            let userCount: Int
            let roomCount: Int
            let mediaCount: Int
            let totalDuration: Double
            let users: [UserRow]
            let rooms: [RoomRow]
            let media: [MediaRow]
            let pods: [PodRow]
            let netlogs: [LogRow]
            let totalRequests: Int
            let caddyRequests: Int
            let directRequests: Int
            let errorRequests: Int
            let flash: String
        }
        let pods = await NetworkMonitor.activePods(on: req.redis).map {
            PodRow(
                id: $0.id,
                role: $0.role,
                host: $0.host,
                startedAt: Self.dateFormatter.string(from: $0.startedAt),
                lastSeen: Self.dateFormatter.string(from: $0.lastSeen),
                requestCount: $0.requestCount
            )
        }
        let netlogs = await NetworkMonitor.recentLogs(on: req.redis).map {
            LogRow(
                t: Self.timeFormatter.string(from: $0.t),
                ip: $0.ip,
                source: $0.source,
                method: $0.method,
                path: $0.path,
                status: Int($0.status),
                durationMs: $0.durationMs,
                pod: $0.pod
            )
        }
        return try await req.view.render("dashboard", Context(
            userCount: userCount,
            roomCount: roomCount,
            mediaCount: mediaCount,
            totalDuration: totalDuration,
            users: Array(try await userRows(on: req.db).prefix(5)),
            rooms: Array(try await roomRows(on: req.db).prefix(5)),
            media: try await mediaRows(on: req, limit: 6),
            pods: pods,
            netlogs: netlogs,
            totalRequests: counters.total,
            caddyRequests: counters.caddy,
            directRequests: counters.direct,
            errorRequests: counters.errors,
            flash: req.session.data["flash"] ?? ""
        ))
    }

    @Sendable
    func usersPage(req: Request) async throws -> View {
        struct Context: Encodable { let users: [UserRow]; let flash: String }
        return try await req.view.render("users", Context(
            users: try await userRows(on: req.db),
            flash: req.session.data["flash"] ?? ""
        ))
    }

    @Sendable
    func userEditPage(req: Request) async throws -> View {
        guard let user = try await User.find(req.parameters.get("id"), on: req.db) else {
            throw Abort(.notFound)
        }
        struct Context: Encodable {
            let id: UUID?
            let displayName: String
            let email: String
            let avatarUrl: String
        }
        return try await req.view.render("userEdit", Context(
            id: user.id,
            displayName: user.displayName,
            email: user.email,
            avatarUrl: user.avatarUrl ?? ""
        ))
    }

    struct UserEditForm: Content {
        let displayName: String
        let email: String
        let avatarUrl: String?
    }

    @Sendable
    func userUpdate(req: Request) async throws -> Response {
        guard let user = try await User.find(req.parameters.get("id"), on: req.db) else {
            throw Abort(.notFound)
        }
        let form = try req.content.decode(UserEditForm.self)
        user.displayName = form.displayName
        user.email = form.email
        user.avatarUrl = form.avatarUrl.flatMap { $0.isEmpty ? nil : $0 }
        try await user.update(on: req.db)
        req.session.data["flash"] = "User updated."
        return req.redirect(to: "/admin/users")
    }

    @Sendable
    func userDelete(req: Request) async throws -> Response {
        guard let user = try await User.find(req.parameters.get("id"), on: req.db) else {
            throw Abort(.notFound)
        }
        try await user.delete(on: req.db)
        req.session.data["flash"] = "User deleted."
        return req.redirect(to: "/admin/users")
    }

    @Sendable
    func roomsPage(req: Request) async throws -> View {
        struct Context: Encodable { let rooms: [RoomRow]; let flash: String }
        return try await req.view.render("rooms", Context(
            rooms: try await roomRows(on: req.db),
            flash: req.session.data["flash"] ?? ""
        ))
    }

    struct RoomForm: Content {
        let name: String?
        let roomType: String
        let maxMembers: Int
        let inviteCode: String?
    }

    @Sendable
    func roomCreate(req: Request) async throws -> Response {
        let form = try req.content.decode(RoomForm.self)
        guard ["log", "stack"].contains(form.roomType), [2, 3, 4, 5, 20].contains(form.maxMembers) else {
            req.session.data["flash"] = "Invalid room type or max members."
            return req.redirect(to: "/admin/rooms")
        }
        let room = Room(
            name: form.name.flatMap { $0.isEmpty ? nil : $0 },
            roomType: form.roomType,
            maxMembers: form.maxMembers,
            inviteCode: form.inviteCode.flatMap { $0.isEmpty ? nil : $0.uppercased() } ?? Self.generateInviteCode()
        )
        try await room.create(on: req.db)
        req.session.data["flash"] = "Room created with code \(room.inviteCode)."
        return req.redirect(to: "/admin/rooms")
    }

    @Sendable
    func roomEditPage(req: Request) async throws -> View {
        guard let room = try await Room.find(req.parameters.get("id"), on: req.db) else {
            throw Abort(.notFound)
        }
        struct Context: Encodable {
            let id: UUID?
            let name: String
            let roomType: String
            let inviteCode: String
            let maxMembers: Int
        }
        return try await req.view.render("roomEdit", Context(
            id: room.id,
            name: room.name ?? "",
            roomType: room.roomType,
            inviteCode: room.inviteCode,
            maxMembers: room.maxMembers
        ))
    }

    @Sendable
    func roomUpdate(req: Request) async throws -> Response {
        guard let room = try await Room.find(req.parameters.get("id"), on: req.db) else {
            throw Abort(.notFound)
        }
        let form = try req.content.decode(RoomForm.self)
        guard ["log", "stack"].contains(form.roomType), [2, 3, 4, 5, 20].contains(form.maxMembers) else {
            req.session.data["flash"] = "Invalid room type or max members."
            return req.redirect(to: "/admin/rooms")
        }
        room.name = form.name.flatMap { $0.isEmpty ? nil : $0 }
        room.roomType = form.roomType
        room.maxMembers = form.maxMembers
        if let code = form.inviteCode, !code.isEmpty { room.inviteCode = code.uppercased() }
        try await room.update(on: req.db)
        req.session.data["flash"] = "Room updated."
        return req.redirect(to: "/admin/rooms")
    }

    @Sendable
    func roomDelete(req: Request) async throws -> Response {
        guard let room = try await Room.find(req.parameters.get("id"), on: req.db) else {
            throw Abort(.notFound)
        }
        try await room.delete(on: req.db)
        req.session.data["flash"] = "Room deleted."
        return req.redirect(to: "/admin/rooms")
    }

    @Sendable
    func mediaPage(req: Request) async throws -> View {
        struct Context: Encodable { let media: [MediaRow]; let flash: String }
        return try await req.view.render("media", Context(
            media: try await mediaRows(on: req),
            flash: req.session.data["flash"] ?? ""
        ))
    }

    @Sendable
    func mediaDelete(req: Request) async throws -> Response {
        guard let log = try await MediaLog.find(req.parameters.get("id"), on: req.db) else {
            throw Abort(.notFound)
        }
        try await log.delete(on: req.db)
        req.session.data["flash"] = "Media log deleted."
        return req.redirect(to: "/admin/media")
    }

    struct NetlogRow: Content {
        let t: String
        let ip: String
        let source: String
        let method: String
        let path: String
        let status: Int
        let durationMs: Double
        let pod: String
    }

    @Sendable
    func netlogsJSON(req: Request) async throws -> [NetlogRow] {
        let pathFilter = req.query[String.self, at: "path"] ?? ""
        let statusFilter = req.query[String.self, at: "status"] ?? "all"
        let entries = await NetworkMonitor.recentLogs(on: req.redis, pathFilter: pathFilter, statusFilter: statusFilter)
        return entries.map {
            NetlogRow(
                t: Self.timeFormatter.string(from: $0.t),
                ip: $0.ip,
                source: $0.source,
                method: $0.method,
                path: $0.path,
                status: Int($0.status),
                durationMs: $0.durationMs,
                pod: $0.pod
            )
        }
    }

    @Sendable
    func uploadTestPage(req: Request) async throws -> View {
        struct Context: Encodable {
            let users: [UserOption]
            let rooms: [RoomOption]
            let flash: String
        }
        let users = try await User.query(on: req.db).sort(\.$displayName).all()
            .map { UserOption(id: $0.id, displayName: $0.displayName) }
        let rooms = try await Room.query(on: req.db).sort(\.$createdAt, .descending).all()
            .map { RoomOption(id: $0.id, label: $0.name ?? $0.inviteCode) }
        return try await req.view.render("upload", Context(users: users, rooms: rooms, flash: req.session.data["flash"] ?? ""))
    }

    struct UploadForm: Content {
        let file: File
        let userId: UUID
        let roomId: UUID
        let duration: Double
    }

    static let allowedExtensions = ["mp4", "mov", "jpg", "jpeg", "png", "webp", "gif", "heic"]

    @Sendable
    func uploadSubmit(req: Request) async throws -> Response {
        let form: UploadForm
        do {
            form = try req.content.decode(UploadForm.self)
        } catch {
            req.session.data["flash"] = "Invalid form: \(error.localizedDescription)"
            return req.redirect(to: "/admin/upload-test")
        }
        let ext = (form.file.filename as NSString).pathExtension.lowercased()
        guard Self.allowedExtensions.contains(ext) else {
            req.session.data["flash"] = "Unsupported file type .\(ext). Allowed: \(Self.allowedExtensions.joined(separator: ", "))"
            return req.redirect(to: "/admin/upload-test")
        }
        let key = "uploads/\(UUID().uuidString).\(ext)"
        do {
            let r2 = R2Service(req.application.r2)
            let contentType = form.file.contentType.map(\.description) ?? "application/octet-stream"
            try await r2.upload(key: key, data: Data(form.file.data.readableBytesView), contentType: contentType, using: req.client)
            let log = MediaLog(userId: form.userId, roomId: form.roomId, s3Key: key, duration: form.duration)
            try await log.create(on: req.db)
            req.session.data["flash"] = "Uploaded \(form.file.filename) → \(key)"
        } catch {
            req.session.data["flash"] = "Upload failed: \(error)"
        }
        return req.redirect(to: "/admin/upload-test")
    }

    static func generateInviteCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }
}
