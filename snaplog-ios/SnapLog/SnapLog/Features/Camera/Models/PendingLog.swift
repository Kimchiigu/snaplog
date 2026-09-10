
import Foundation
import SwiftData

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
