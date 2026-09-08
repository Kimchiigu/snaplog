//
//  RoomDTOs.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import Foundation

/// Response envelope for `GET /rooms`.
struct RoomListResponse: Decodable, Sendable {
    let rooms: [Room]
}

/// Request body for `POST /rooms`.
struct CreateRoomRequest: Encodable, Sendable {
    let name: String
    let roomType: RoomType
}

/// Request body for `POST /rooms/join`.
struct JoinRoomRequest: Encodable, Sendable {
    let code: String
}
