//
//  Room.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import Foundation

/// A room in which members share short video logs.
struct Room: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let roomType: RoomType
    let memberCount: Int
    let joinCode: String?
}

/// Determines how a room renders in the feed.
enum RoomType: String, Codable, Sendable {
    case grid
    case stack
}
