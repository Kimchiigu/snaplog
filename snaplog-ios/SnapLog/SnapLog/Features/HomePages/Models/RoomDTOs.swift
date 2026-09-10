
import Foundation

struct CreateRoomRequest: Encodable, Sendable {
    let name: String
    let roomType: RoomType
    let maxMembers: Int
}

struct JoinRoomRequest: Encodable, Sendable {
    let inviteCode: String
}
