import Fluent
struct CreateRoomMember: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("room_members")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("room_id", .uuid, .required, .references("rooms", "id", onDelete: .cascade))
            .field("role", .string, .required)
            .field("joined_at", .datetime)
            .unique(on: "user_id", "room_id")
            .create()
    }
    func revert(on database: any Database) async throws {
        try await database.schema("room_members").delete()
    }
}
