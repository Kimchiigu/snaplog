//
//  Room.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import Foundation

/// A room as returned by the backend's `RoomDTO`.
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

/// Layout flavour of a room; raw values match the backend strings.
enum RoomType: String, Codable, Sendable {
    /// Single chronological log feed.
    case log
    /// Stacked cards layout.
    case stack

    /// Allowed `maxMembers` values the backend accepts on room creation.
    static let allowedMaxMembers = [2, 3, 4, 5, 20]
}

/// A member of a room (`RoomDTO.MemberDTO`).
struct RoomMemberDTO: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let displayName: String
    let avatarUrl: String?
    let role: String
    let joinedAt: Date?
}

/// A stitched clip in a room's timeline (`RoomDTO.TimelineEntryDTO`).
struct TimelineEntry: Codable, Hashable, Sendable {
    let s3Key: String
    let duration: Double
    let createdAt: Double
}
