import Fluent
import Vapor

/// Account management for the authenticated user.
struct UserController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("users", "me", use: me)
        routes.delete("users", "me", use: deleteAccount)
    }

    /// The authenticated user's public profile.
    @Sendable
    func me(req: Request) async throws -> User.Public {
        try req.authenticatedUser.public
    }

    /// Deletes the account and all of its memberships, logs, and device tokens.
    @Sendable
    func deleteAccount(req: Request) async throws -> HTTPResponseStatus {
        let user = try req.authenticatedUser
        let userId = try user.requireID()

        try await RoomMember.query(on: req.db)
            .filter(\.$user.$id == userId)
            .delete()
        try await MediaLog.query(on: req.db)
            .filter(\.$user.$id == userId)
            .delete()
        try await DeviceToken.query(on: req.db)
            .filter(\.$user.$id == userId)
            .delete()
        try await user.delete(on: req.db)
        return .noContent
    }
}
