//
//  RoomDTOs.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import Foundation

/// Request body for `POST /api/rooms`.
struct CreateRoomRequest: Encodable, Sendable {
    let name: String
    let roomType: RoomType
    let maxMembers: Int
}

/// Request body for `POST /api/rooms/join`.
struct JoinRoomRequest: Encodable, Sendable {
    let inviteCode: String
}
