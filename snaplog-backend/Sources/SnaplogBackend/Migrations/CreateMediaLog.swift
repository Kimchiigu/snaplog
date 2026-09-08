import Fluent
struct CreateMediaLog: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("media_logs")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("room_id", .uuid, .required, .references("rooms", "id", onDelete: .cascade))
            .field("s3_key", .string, .required)
            .field("duration", .double, .required)
            .field("created_at", .datetime)
            .create()
    }
    func revert(on database: any Database) async throws {
        try await database.schema("media_logs").delete()
    }
}
