
import Foundation

struct Room: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let name: String?
    let roomType: RoomType
    let maxMembers: Int
    let inviteCode: String
    let createdAt: Date?
    let members: [RoomMemberDTO]
    let timeline: [TimelineEntry]

    var displayName: String { name ?? "Untitled Room" }
}

enum RoomType: String, Codable, Sendable {
    case log
    case stack

    static let allowedMaxMembers = [2, 3, 4, 5, 20]
}

struct RoomMemberDTO: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let displayName: String
    let avatarUrl: String?
    let role: String
    let joinedAt: Date?
}

struct TimelineEntry: Codable, Hashable, Sendable {
    let s3Key: String
    let duration: Double
    let createdAt: Double
}
