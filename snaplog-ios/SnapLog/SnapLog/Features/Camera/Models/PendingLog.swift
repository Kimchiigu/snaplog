//
//  PendingLog.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import Foundation
import SwiftData

/// A recorded snippet waiting to be uploaded, kept across launches as an offline buffer.
@Model
final class PendingLog {
    var localFileURL: URL
    var roomID: String
    var createdAt: Date

    init(localFileURL: URL, roomID: String, createdAt: Date = Date()) {
        self.localFileURL = localFileURL
        self.roomID = roomID
        self.createdAt = createdAt
    }
}
