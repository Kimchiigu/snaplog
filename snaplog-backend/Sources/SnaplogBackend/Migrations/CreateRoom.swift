import Fluent
struct CreateRoom: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("rooms")
            .id()
            .field("name", .string)
            .field("room_type", .string, .required)
            .field("max_members", .int, .required)
            .field("invite_code", .string, .required)
            .field("created_at", .datetime)
            .unique(on: "invite_code")
            .create()
    }
    func revert(on database: any Database) async throws {
        try await database.schema("rooms").delete()
    }
}
