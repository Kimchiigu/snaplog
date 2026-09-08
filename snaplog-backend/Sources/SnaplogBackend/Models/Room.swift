import Fluent
import Vapor
final class Room: Model, Content, @unchecked Sendable {
    static let schema = "rooms"
    @ID(key: .id)
    var id: UUID?
    @OptionalField(key: "name")
    var name: String?
    @Field(key: "room_type")
    var roomType: String
    @Field(key: "max_members")
    var maxMembers: Int
    @Field(key: "invite_code")
    var inviteCode: String
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    @Siblings(through: RoomMember.self, from: \.$room, to: \.$user)
    var members: [User]
    @Children(for: \.$room)
    var logs: [MediaLog]
    init() {}
    init(
        id: UUID? = nil,
        name: String? = nil,
        roomType: String,
        maxMembers: Int,
        inviteCode: String
    ) {
        self.id = id
        self.name = name
        self.roomType = roomType
        self.maxMembers = maxMembers
        self.inviteCode = inviteCode
    }
}
