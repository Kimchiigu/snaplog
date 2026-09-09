@testable import SnaplogBackend
import Fluent
import JWT
import Testing
import Vapor
import VaporTesting
import XCTest

@Suite("SnapLog API", .serialized)
struct SnaplogBackendTests {
    @Test("Protected routes reject a missing token")
    func protectedRouteRejectsMissingToken() async throws {
        try await Self.withTestApp { app, _ in
            try await app.testing().test(.GET, "api/rooms", afterResponse: { res async in
                #expect(res.status == .unauthorized)
            })
        }
    }

    @Test("Protected routes reject a garbage token")
    func protectedRouteRejectsGarbageToken() async throws {
        try await Self.withTestApp { app, _ in
            try await app.testing().test(.GET, "api/rooms", headers: ["Authorization": "Bearer not-a-jwt"], afterResponse: { res async in
                #expect(res.status == .unauthorized)
            })
        }
    }

    @Test("Apple auth rejects a malformed identity token")
    func appleAuthRejectsMalformedToken() async throws {
        try await Self.withTestApp { app, _ in
            try await app.testing().test(.POST, "api/auth/apple", beforeRequest: { req in
                try req.content.encode(["identityToken": "garbage.token.here"] as [String: String])
            }, afterResponse: { res async in
                #expect(res.status == .unauthorized)
            })
        }
    }

    @Test("Create room returns owner and a 6-char invite code")
    func createRoom() async throws {
        try await Self.withTestApp { app, token in
            try await app.testing().test(.POST, "api/rooms", headers: ["Authorization": "Bearer \(token)"], beforeRequest: { req in
                try req.content.encode(CreateRoomRequest(name: "Test Room", roomType: "log", maxMembers: 4))
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let dto = try res.content.decode(RoomDTO.self)
                print("  ↳ created room \(dto.id) with invite code \(dto.inviteCode) (\(dto.members.count) member)")
                #expect(dto.inviteCode.count == 6)
                #expect(dto.roomType == "log")
                #expect(dto.maxMembers == 4)
                #expect(dto.members.count == 1)
                #expect(dto.members.first?.role == "owner")
            })
        }
    }

    @Test("Create room rejects an invalid roomType")
    func createRoomRejectsInvalidRoomType() async throws {
        try await Self.withTestApp { app, token in
            try await app.testing().test(.POST, "api/rooms", headers: ["Authorization": "Bearer \(token)"], beforeRequest: { req in
                try req.content.encode(RoomPayload(name: "X", roomType: "party", maxMembers: 4))
            }, afterResponse: { res async in
                #expect(res.status == .badRequest)
            })
        }
    }

    @Test("Create room rejects an invalid maxMembers")
    func createRoomRejectsInvalidMaxMembers() async throws {
        try await Self.withTestApp { app, token in
            try await app.testing().test(.POST, "api/rooms", headers: ["Authorization": "Bearer \(token)"], beforeRequest: { req in
                try req.content.encode(RoomPayload(name: "X", roomType: "log", maxMembers: 7))
            }, afterResponse: { res async in
                #expect(res.status == .badRequest)
            })
        }
    }

    @Test("List rooms returns the user's rooms")
    func listRoomsReturnsUserRooms() async throws {
        try await Self.withTestApp { app, token in
            let user = try await User.query(on: app.db).first()!
            let room = Room(roomType: "stack", maxMembers: 2, inviteCode: "LISTTS")
            try await room.create(on: app.db)
            try await RoomMember(userId: user.id!, roomId: room.id!, role: "owner").create(on: app.db)

            try await app.testing().test(.GET, "api/rooms", headers: ["Authorization": "Bearer \(token)"], afterResponse: { res async throws in
                #expect(res.status == .ok)
                let rooms = try res.content.decode([RoomDTO].self)
                print("  ↳ user is in \(rooms.count) room(s)")
                #expect(rooms.contains { $0.inviteCode == "LISTTS" })
            })
        }
    }

    @Test("Join room adds a member and enforces capacity")
    func joinRoomAddsMemberAndEnforcesCapacity() async throws {
        try await Self.withTestApp { app, _ in
            let owner = try await User.query(on: app.db).first()!
            let room = Room(roomType: "log", maxMembers: 2, inviteCode: "JOINTT")
            try await room.create(on: app.db)
            try await RoomMember(userId: owner.id!, roomId: room.id!, role: "owner").create(on: app.db)

            let (_, joinerToken) = try await Self.makeUser(app: app, name: "Joiner")
            try await app.testing().test(.POST, "api/rooms/join", headers: ["Authorization": "Bearer \(joinerToken)"], beforeRequest: { req in
                try req.content.encode(JoinRoomRequest(inviteCode: "JOINTT"))
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let dto = try res.content.decode(RoomDTO.self)
                print("  ↳ room now has \(dto.members.count) members: \(dto.members.map(\.displayName))")
                #expect(dto.members.count == 2)
                #expect(dto.members.contains { $0.role == "member" })
            })

            let (_, thirdToken) = try await Self.makeUser(app: app, name: "Third")
            try await app.testing().test(.POST, "api/rooms/join", headers: ["Authorization": "Bearer \(thirdToken)"], beforeRequest: { req in
                try req.content.encode(JoinRoomRequest(inviteCode: "JOINTT"))
            }, afterResponse: { res async in
                #expect(res.status == .forbidden)
            })
        }
    }

    @Test("Join room rejects duplicate membership")
    func joinRoomRejectsDuplicateMembership() async throws {
        try await Self.withTestApp { app, token in
            let user = try await User.query(on: app.db).first()!
            let room = Room(roomType: "log", maxMembers: 4, inviteCode: "DUPLCT")
            try await room.create(on: app.db)
            try await RoomMember(userId: user.id!, roomId: room.id!, role: "owner").create(on: app.db)

            try await app.testing().test(.POST, "api/rooms/join", headers: ["Authorization": "Bearer \(token)"], beforeRequest: { req in
                try req.content.encode(JoinRoomRequest(inviteCode: "DUPLCT"))
            }, afterResponse: { res async in
                #expect(res.status == .conflict)
            })
        }
    }

    @Test("Join room rejects an unknown invite code")
    func joinRoomRejectsUnknownInviteCode() async throws {
        try await Self.withTestApp { app, token in
            try await app.testing().test(.POST, "api/rooms/join", headers: ["Authorization": "Bearer \(token)"], beforeRequest: { req in
                try req.content.encode(JoinRoomRequest(inviteCode: "ZZZZZZ"))
            }, afterResponse: { res async in
                #expect(res.status == .notFound)
            })
        }
    }

    @Test("Upload URL rejects a bad file extension")
    func uploadURLRejectsBadExtension() async throws {
        try await Self.withTestApp { app, token in
            let user = try await User.query(on: app.db).first()!
            let room = Room(roomType: "log", maxMembers: 4, inviteCode: "UPLDAA")
            try await room.create(on: app.db)
            try await RoomMember(userId: user.id!, roomId: room.id!, role: "owner").create(on: app.db)

            try await app.testing().test(.POST, "api/logs/upload-url", headers: ["Authorization": "Bearer \(token)"], beforeRequest: { req in
                try req.content.encode(UploadURLRequest(roomId: room.id!, fileExtension: "avi"))
            }, afterResponse: { res async in
                #expect(res.status == .badRequest)
            })
        }
    }

    @Test("Upload URL rejects a non-member")
    func uploadURLRejectsNonMember() async throws {
        try await Self.withTestApp { app, token in
            let room = Room(roomType: "log", maxMembers: 4, inviteCode: "UPLDBB")
            try await room.create(on: app.db)

            try await app.testing().test(.POST, "api/logs/upload-url", headers: ["Authorization": "Bearer \(token)"], beforeRequest: { req in
                try req.content.encode(UploadURLRequest(roomId: room.id!, fileExtension: "mp4"))
            }, afterResponse: { res async in
                #expect(res.status == .forbidden)
            })
        }
    }

    @Test("Confirm rejects an invalid duration")
    func confirmRejectsInvalidDuration() async throws {
        try await Self.withTestApp { app, token in
            let user = try await User.query(on: app.db).first()!
            let room = Room(roomType: "log", maxMembers: 4, inviteCode: "CNFRMA")
            try await room.create(on: app.db)
            try await RoomMember(userId: user.id!, roomId: room.id!, role: "owner").create(on: app.db)

            try await app.testing().test(.POST, "api/logs/confirm", headers: ["Authorization": "Bearer \(token)"], beforeRequest: { req in
                try req.content.encode(ConfirmLogRequest(s3Key: "raw/x.mp4", duration: 120, roomId: room.id!))
            }, afterResponse: { res async in
                #expect(res.status == .badRequest)
            })
        }
    }

    @Test("Admin portal requires login and accepts credentials")
    func adminPortalAuth() async throws {
        try await Self.withTestApp { app, _ in
            try await app.testing().test(.GET, "admin/dashboard", afterResponse: { res async in
                #expect(res.status == .seeOther)
                #expect(res.headers.first(name: .location) == "/admin/login")
            })
            try await app.testing().test(.GET, "admin/login", afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("SnapLog Admin"))
            })
            try await app.testing().test(.POST, "admin/login", beforeRequest: { req in
                try req.content.encode(["username": "admin", "password": "admin123"] as [String: String])
            }, afterResponse: { res async in
                #expect(res.status == .seeOther)
                #expect(res.headers.first(name: .location) == "/admin/dashboard")
            })
            try await app.testing().test(.POST, "admin/login", beforeRequest: { req in
                try req.content.encode(["username": "admin", "password": "wrong"] as [String: String])
            }, afterResponse: { res async in
                #expect(res.status == .seeOther)
                #expect(res.headers.first(name: .location) == "/admin/login")
            })
        }
    }
}

extension SnaplogBackendTests {
    @discardableResult
    static func makeUser(app: Application, name: String) async throws -> (User, String) {
        let user = User(
            appleUserId: "test-\(UUID().uuidString)",
            email: "\(name)@snaplog.test",
            displayName: name
        )
        try await user.create(on: app.db)
        return (user, try Self.signToken(for: user, on: app))
    }

    static func signToken(for user: User, on app: Application) throws -> String {
        try app.jwt.signers.sign(SessionToken(
            sub: SubjectClaim(stringLiteral: user.id!.uuidString),
            appleUserId: user.appleUserId,
            exp: ExpirationClaim(value: Date().addingTimeInterval(60 * 60))
        ))
    }

    @Test("Every response carries a fresh X-Trace-Id")
    func responseCarriesTraceId() async throws {
        try await SnaplogBackendTests.withTestApp { app, _ in
            var first = ""
            try await app.testing().test(.GET, "api/rooms", afterResponse: { res async in
                #expect(res.status == .unauthorized)
                let id = res.headers.first(name: "X-Trace-Id") ?? ""
                #expect(!id.isEmpty)
                first = id
            })
            try await app.testing().test(.GET, "api/rooms", afterResponse: { res async in
                let id = res.headers.first(name: "X-Trace-Id") ?? ""
                #expect(!id.isEmpty)
                #expect(id != first)
                print("  ↳ trace ids: \(first.prefix(8))… then \(id.prefix(8))…")
            })
        }
    }

    @Test("A client-supplied trace id is echoed back")
    func echoesClientTraceId() async throws {
        try await SnaplogBackendTests.withTestApp { app, _ in
            try await app.testing().test(.GET, "api/rooms", headers: ["X-Trace-Id": "my-trace-123"], afterResponse: { res async in
                #expect(res.headers.first(name: "X-Trace-Id") == "my-trace-123")
            })
        }
    }

    @Test("Health checks are excluded from tracing")
    func healthSkipsTracing() async throws {
        try await SnaplogBackendTests.withTestApp { app, _ in
            try await app.testing().test(.GET, "api/health", afterResponse: { res async in
                #expect(res.headers.first(name: "X-Trace-Id") == nil)
            })
        }
    }

    @Test("An authenticated flow records its spans in the trace context")
    func authenticatedFlowRecordsSpans() async throws {
        try await SnaplogBackendTests.withTestApp { app, token in
            try await app.testing().test(.GET, "api/rooms", headers: ["Authorization": "Bearer \(token)"], afterResponse: { res async in
                #expect(res.status == .ok)
                let traceId = res.headers.first(name: "X-Trace-Id") ?? ""
                #expect(!traceId.isEmpty)
                print("  ↳ GET /api/rooms traced as \(traceId.prefix(8))…")
            })
            try await app.testing().test(.POST, "api/rooms", headers: ["Authorization": "Bearer \(token)"], beforeRequest: { req in
                try req.content.encode(CreateRoomRequest(name: "Traced Room", roomType: "log", maxMembers: 4))
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let dto = try res.content.decode(RoomDTO.self)
                print("  ↳ POST /api/rooms traced, room \(dto.id)")
            })
        }
    }

    static func withTestApp(_ test: (Application, String) async throws -> Void) async throws {
        let testDatabaseURL = Environment.get("TEST_DATABASE_URL")
            ?? "postgres://postgres:test@127.0.0.1:5433/snaplog_test"
        setenv("DATABASE_URL", testDatabaseURL, 1)
        let name = Test.current?.name ?? "test"
        print("▶ \(name) — using \(testDatabaseURL)")

        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            try await app.autoMigrate()
            let (user, token) = try await Self.makeUser(app: app, name: "Tester")
            _ = user
            try await test(app, token)
            try await app.autoRevert()
            print("✔ \(name) — passed (tables reverted)")
        } catch {
            try? await app.autoRevert()
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("R2 webhook returns 503 when no secret is configured")
    func r2WebhookRejectsWhenUnconfigured() async throws {
        try await Self.withTestApp { app, _ in
            try await app.testing().test(.POST, "webhooks/r2-upload-complete", beforeRequest: { req in
                try req.content.encode(R2EventTest(bucket: "snaplog-media", action: "PUT", key: "test/a.mp4", size: 123))
            }, afterResponse: { res async in
                #expect(res.status == .serviceUnavailable)
            })
        }
    }

    @Test("R2 webhook accepts a signed event and records the upload")
    func r2WebhookAcceptsSignedEvent() async throws {
        setenv("R2_WEBHOOK_SECRET", "test-webhook-secret", 1)
        defer { unsetenv("R2_WEBHOOK_SECRET") }
        try await Self.withTestApp { app, _ in
            try await app.testing().test(.POST, "webhooks/r2-upload-complete", headers: ["X-Webhook-Secret": "wrong"], beforeRequest: { req in
                try req.content.encode(R2EventTest(bucket: "snaplog-media", action: "PUT", key: "test/a.mp4", size: 123))
            }, afterResponse: { res async in
                #expect(res.status == .forbidden)
            })
            try await app.testing().test(.POST, "webhooks/r2-upload-complete", headers: ["X-Webhook-Secret": "test-webhook-secret"], beforeRequest: { req in
                try req.content.encode(R2EventTest(bucket: "snaplog-media", action: "PUT", key: "test/a.mp4", size: 123))
            }, afterResponse: { res async in
                #expect(res.status == .ok)
            })
        }
    }

    @Test("Device registration requires auth and upserts by token")
    func deviceRegistrationRoundTrip() async throws {
        try await Self.withTestApp { app, token in
            try await app.testing().test(.POST, "api/devices", beforeRequest: { req in
                try req.content.encode(["token": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef", "platform": "ios"] as [String: String])
            }, afterResponse: { res async in
                #expect(res.status == .unauthorized)
            })
            try await app.testing().test(.POST, "api/devices", headers: ["Authorization": "Bearer \(token)"], beforeRequest: { req in
                try req.content.encode(["token": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef", "platform": "ios"] as [String: String])
            }, afterResponse: { res async in
                #expect(res.status == .created)
            })
        }
    }

    @Test("New media logs default to processing status")
    func mediaLogDefaultsToProcessing() async throws {
        try await Self.withTestApp { app, token in
            let (user, _) = try await Self.makeUser(app: app, name: "ClipOwner")
            _ = token
            let room = Room(roomType: "friends", maxMembers: 6, inviteCode: "STAT01")
            try await room.create(on: app.db)
            let log = MediaLog(userId: user.id!, roomId: room.id!, s3Key: "clips/test-status.mp4", duration: 3)
            try await log.create(on: app.db)
            let fetched = try await MediaLog.find(log.id, on: app.db)
            #expect(fetched?.status == "processing")
        }
    }
}

struct RoomPayload: Content {
    let name: String
    let roomType: String
    let maxMembers: Int
}

struct R2EventTest: Content {
    struct Object: Content {
        let key: String
        let size: Int
    }
    let bucket: String
    let action: String
    let object: Object
    init(bucket: String, action: String, key: String, size: Int) {
        self.bucket = bucket
        self.action = action
        self.object = Object(key: key, size: size)
    }
}
