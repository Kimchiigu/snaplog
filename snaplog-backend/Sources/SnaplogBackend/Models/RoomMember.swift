import Fluent
import Vapor
final class RoomMember: Model, Content, @unchecked Sendable {
    static let schema = "room_members"
    @ID(key: .id)
    var id: UUID?
    @Parent(key: "user_id")
    var user: User
    @Parent(key: "room_id")
    var room: Room
    @Field(key: "role")
    var role: String
    @Timestamp(key: "joined_at", on: .create)
    var joinedAt: Date?
    init() {}
    init(
        id: UUID? = nil,
        userId: UUID,
        roomId: UUID,
        role: String
    ) {
        self.id = id
        self.$user.id = userId
        self.$room.id = roomId
        self.role = role
    }
}
