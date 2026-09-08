import Fluent
import Vapor

struct RoomDTO: Content {
    let id: UUID
    let name: String?
    let roomType: String
    let maxMembers: Int
    let inviteCode: String
    let createdAt: Date?
    let members: [MemberDTO]
    let timeline: [TimelineEntryDTO]

    struct MemberDTO: Content {
        let id: UUID
        let displayName: String
        let avatarUrl: String?
        let role: String
        let joinedAt: Date?
    }
    
    struct TimelineEntryDTO: Content {
        let s3Key: String
        let duration: Double
        let createdAt: Double
    }
}

extension RoomDTO {
    init(room: Room, members: [RoomMember.Summary], timeline: [TimelineEntryDTO]) {
        self.id = room.id!
        self.name = room.name
        self.roomType = room.roomType
        self.maxMembers = room.maxMembers
        self.inviteCode = room.inviteCode
        self.createdAt = room.createdAt
        self.members = members.map {
            .init(
                id: $0.user.id!,
                displayName: $0.user.displayName,
                avatarUrl: $0.user.avatarUrl,
                role: $0.role,
                joinedAt: $0.joinedAt
            )
        }
        self.timeline = timeline
    }
}

extension RoomMember {
    struct Summary {
        let role: String
        let joinedAt: Date?
        let user: User
    }
}

struct CreateRoomRequest: Content {
    let name: String?
    let roomType: String
    let maxMembers: Int
}

struct JoinRoomRequest: Content {
    let inviteCode: String
}
