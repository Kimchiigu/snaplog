import Fluent
import Vapor
final class MediaLog: Model, Content, @unchecked Sendable {
    static let schema = "media_logs"
    @ID(key: .id)
    var id: UUID?
    @Parent(key: "user_id")
    var user: User
    @Parent(key: "room_id")
    var room: Room
    @Field(key: "s3_key")
    var s3Key: String
    @Field(key: "duration")
    var duration: Double
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    init() {}
    init(
        id: UUID? = nil,
        userId: UUID,
        roomId: UUID,
        s3Key: String,
        duration: Double
    ) {
        self.id = id
        self.$user.id = userId
        self.$room.id = roomId
        self.s3Key = s3Key
        self.duration = duration
    }
}
