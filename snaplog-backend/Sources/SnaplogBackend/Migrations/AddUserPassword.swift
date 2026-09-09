import Fluent

/// Adds the optional password hash column for email/password accounts.
struct AddUserPassword: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("users")
            .field("password_hash", .string)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("users")
            .deleteField("password_hash")
            .update()
    }
}
