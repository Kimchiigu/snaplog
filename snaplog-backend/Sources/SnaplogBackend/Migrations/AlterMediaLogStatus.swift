import Fluent
import FluentSQL

struct AlterMediaLogStatus: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("media_logs")
            .field("status", .string, .required, .sql(.default("processing")))
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("media_logs").deleteField("status").update()
    }
}
