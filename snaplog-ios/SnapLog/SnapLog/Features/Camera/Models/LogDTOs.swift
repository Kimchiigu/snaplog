//
//  LogDTOs.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import Foundation

/// Response from `POST /logs/upload-url`.
struct UploadURLResponse: Decodable, Sendable {
    let uploadURL: URL
    let logID: String
}

/// Request body for `POST /logs/confirm`.
struct LogConfirmRequest: Encodable, Sendable {
    let logID: String
    let roomID: String
}
