import Fluent
import JWT
import Vapor
let appleJWKSVerifier = AppleJWKSVerifier()
struct SessionToken: JWTPayload {
    let sub: SubjectClaim
    let appleUserId: String
    let exp: ExpirationClaim
    func verify(using signer: some JWTSigner) throws {
        try exp.verifyNotExpired()
    }
}
struct AppleIdentityToken: JWTPayload {
    let iss: IssuerClaim
    let aud: AudienceClaim
    let sub: SubjectClaim
    let email: String?
    let emailVerified: String?
    let exp: ExpirationClaim
    func verify(using signer: some JWTSigner) throws {
        try exp.verifyNotExpired()
        guard iss.value == "https://appleid.apple.com" else {
            throw Abort(.unauthorized, reason: "Unexpected token issuer.")
        }
        let bundleId = Environment.get("APPLE_BUNDLE_ID") ?? "com.christopherhygunawan.SnapLog"
        try aud.verifyIntendedAudience(includes: bundleId)
    }
}
struct AppleAuthRequest: Content {
    let identityToken: String
}

struct RegisterRequest: Content {
    let email: String
    let password: String
    let displayName: String
}

struct LoginRequest: Content {
    let email: String
    let password: String
}
struct AuthResponse: Content {
    let token: String
    let user: User.Public
}
extension User {
    struct Public: Content {
        let id: UUID?
        let email: String
        let displayName: String
        let avatarUrl: String?
    }
    var `public`: Public {
        Public(id: id, email: email, displayName: displayName, avatarUrl: avatarUrl)
    }
}
struct AuthController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.post("auth", "apple", use: appleSignIn)
        routes.post("auth", "register", use: register)
        routes.post("auth", "login", use: login)
    }

    @Sendable
    func register(req: Request) async throws -> AuthResponse {
        let body = try req.content.decode(RegisterRequest.self)
        let email = body.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = body.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.contains("@"), email.contains("."),
              body.password.count >= 8, !name.isEmpty else {
            throw Abort(.badRequest, reason: "Provide a valid email, a display name, and a password of at least 8 characters.")
        }
        let existing = try await User.query(on: req.db)
            .filter(\.$email == email)
            .first()
        guard existing == nil else {
            throw Abort(.conflict, reason: "An account with that email already exists.")
        }
        let user = User(
            appleUserId: "email:\(email)",
            email: email,
            displayName: name,
            passwordHash: try Bcrypt.hash(body.password)
        )
        try await user.create(on: req.db)
        return AuthResponse(token: try signSession(for: user, req: req), user: user.public)
    }

    @Sendable
    func login(req: Request) async throws -> AuthResponse {
        let body = try req.content.decode(LoginRequest.self)
        let email = body.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let user = try await User.query(on: req.db)
            .filter(\.$email == email)
            .first(),
            let hash = user.passwordHash,
            try Bcrypt.verify(body.password, created: hash) else {
            throw Abort(.unauthorized, reason: "Invalid email or password.")
        }
        return AuthResponse(token: try signSession(for: user, req: req), user: user.public)
    }

    private func signSession(for user: User, req: Request) throws -> String {
        let session = SessionToken(
            sub: SubjectClaim(stringLiteral: user.id!.uuidString),
            appleUserId: user.appleUserId,
            exp: ExpirationClaim(value: Date().addingTimeInterval(60 * 60 * 24 * 30))
        )
        return try req.jwt.sign(session)
    }
    @Sendable
    func devLogin(req: Request) async throws -> AuthResponse {
        let displayName = (try? req.content.decode([String: String].self))?["displayName"] ?? "Dev Tester"
        let appleUserId = "dev-\(displayName.lowercased().replacingOccurrences(of: " ", with: "-"))"
        var user = try await User.query(on: req.db)
            .filter(\.$appleUserId == appleUserId)
            .first()
        if user == nil {
            let newUser = User(
                appleUserId: appleUserId,
                email: "\(appleUserId)@snaplog.dev",
                displayName: displayName
            )
            try await newUser.create(on: req.db)
            user = newUser
        }
        guard let user else { throw Abort(.internalServerError) }
        let session = SessionToken(
            sub: SubjectClaim(stringLiteral: user.id!.uuidString),
            appleUserId: appleUserId,
            exp: ExpirationClaim(value: Date().addingTimeInterval(60 * 60 * 24))
        )
        return AuthResponse(token: try req.jwt.sign(session), user: user.public)
    }
    @Sendable
    func appleSignIn(req: Request) async throws -> AuthResponse {
        let body = try req.content.decode(AppleAuthRequest.self)
        let appleToken: AppleIdentityToken
        do {
            appleToken = try await req.trace.span("auth.verifyAppleToken") {
                try await appleJWKSVerifier.verify(body.identityToken, as: AppleIdentityToken.self, on: req.client)
            }
        } catch {
            req.logger.warning("Apple token verification failed: \(error)")
            throw Abort(.unauthorized, reason: "Invalid Apple identity token.")
        }
        let appleUserId = appleToken.sub.value
        var user = try await req.trace.span("db.findUserByAppleId") {
            try await User.query(on: req.db)
                .filter(\.$appleUserId == appleUserId)
                .first()
        }
        if user == nil {
            let email = appleToken.email
                ?? "\(appleUserId)@privaterelay.appleid.com"
            user = try await req.trace.span("db.createUser", detail: email) {
                let newUser = User(
                    appleUserId: appleUserId,
                    email: email,
                    displayName: email.components(separatedBy: "@").first ?? "Snapper"
                )
                try await newUser.create(on: req.db)
                return newUser
            }
        }
        guard let user else {
            throw Abort(.internalServerError, reason: "Failed to create user.")
        }
        let session = SessionToken(
            sub: SubjectClaim(stringLiteral: user.id!.uuidString),
            appleUserId: appleUserId,
            exp: ExpirationClaim(value: Date().addingTimeInterval(60 * 60 * 24 * 30))
        )
        let signStart = DispatchTime.now()
        let token = try req.jwt.sign(session)
        req.trace.record("jwt.signSession", durationMs: Double(DispatchTime.now().uptimeNanoseconds - signStart.uptimeNanoseconds) / 1_000_000)
        return AuthResponse(token: token, user: user.public)
    }
}
struct JWTAuthMiddleware: AsyncMiddleware {
    func respond(to req: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let payload = try await req.trace.span("auth.verifySessionJWT") {
            try req.jwt.verify(as: SessionToken.self)
        }
        guard let userId = UUID(uuidString: payload.sub.value) else {
            throw Abort(.unauthorized, reason: "Malformed session token.")
        }
        let user = try await req.trace.span("db.findSessionUser", detail: userId.uuidString) {
            try await User.find(userId, on: req.db)
        }
        guard let user else {
            throw Abort(.unauthorized, reason: "User no longer exists.")
        }
        req.auth.login(user)
        return try await next.respond(to: req)
    }
}
extension Request {
    var authenticatedUser: User {
        get throws { try auth.require(User.self) }
    }
}
