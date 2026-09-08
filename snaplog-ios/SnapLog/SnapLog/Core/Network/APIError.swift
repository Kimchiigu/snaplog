//
//  APIError.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import Foundation

/// Errors produced by ``APIClient``.
enum APIError: Error, Equatable {
    case invalidURL
    case invalidResponse
    case unauthorized
    case httpStatus(Int)
    case decoding(underlying: String)
    case network(underlying: String)
}
