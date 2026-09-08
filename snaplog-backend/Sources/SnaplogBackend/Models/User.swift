import Fluent
import Vapor

final class User: Model, Content, Authenticatable, @unchecked Sendable {
    static let schema = "users"
    
    @ID(key: .id)
    var id: UUID?
    @Field(key: "apple_user_id")
    var appleUserId: String
    @Field(key: "email")
    var email: String
    @Field(key: "display_name")
    var displayName: String
    @OptionalField(key: "avatar_url")
    var avatarUrl: String?
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    @Siblings(through: RoomMember.self, from: \.$user, to: \.$room)
    var rooms: [Room]

    init() {}

    init(
        id: UUID? = nil,
        appleUserId: String,
        email: String,
        displayName: String,
        avatarUrl: String? = nil
    ) {
        self.id = id
        self.appleUserId = appleUserId
        self.email = email
        self.displayName = displayName
        self.avatarUrl = avatarUrl
    }
}
