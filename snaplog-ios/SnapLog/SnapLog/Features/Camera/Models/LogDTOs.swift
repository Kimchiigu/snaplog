
import Foundation

struct UploadURLRequest: Encodable, Sendable {
    let roomId: UUID
    let fileExtension: String
}

struct UploadURLResponse: Decodable, Sendable {
    let uploadURL: String
    let s3Key: String

    var destination: URL { URL(string: uploadURL) ?? URL(fileURLWithPath: "/dev/null") }
}

struct LogConfirmRequest: Encodable, Sendable {
    let s3Key: String
    let duration: Double
    let roomId: UUID
}
