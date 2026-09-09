import Fluent
import Vapor

/// Account management for the authenticated user.
struct UserController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.delete("users", "me", use: deleteAccount)
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
