//
//  LogDTOs.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import Foundation

/// Request body for `POST /api/logs/upload-url`.
struct UploadURLRequest: Encodable, Sendable {
    let roomId: UUID
    let fileExtension: String
}

/// Response from `POST /api/logs/upload-url`.
struct UploadURLResponse: Decodable, Sendable {
    let uploadURL: String
    let s3Key: String

    var destination: URL { URL(string: uploadURL) ?? URL(fileURLWithPath: "/dev/null") }
}

/// Request body for `POST /api/logs/confirm`.
struct LogConfirmRequest: Encodable, Sendable {
    let s3Key: String
    let duration: Double
    let roomId: UUID
}
