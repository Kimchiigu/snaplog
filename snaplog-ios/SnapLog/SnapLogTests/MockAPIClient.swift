//
//  MockAPIClient.swift
//  SnapLogTests
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import Foundation
@testable import SnapLog

/// Scriptable mock used by ViewModel tests.
final class MockAPIClient: APIClientProtocol, @unchecked Sendable {

    struct Call {
        let path: String
        let method: HTTPMethod
    }

    private enum Stub {
        case success(Any)
        case failure(Error)
    }

    private let lock = NSLock()
    private var stubs: [String: Stub] = [:]
    private(set) var recordedCalls: [Call] = []

    func stub<T>(_ path: String, result: Result<T, Error>) {
        lock.lock()
        defer { lock.unlock() }
        switch result {
        case .success(let value): stubs[path] = .success(value)
        case .failure(let error): stubs[path] = .failure(error)
        }
    }

    /// Failure overload that doesn't need a concrete success type.
    func stubFailure(_ path: String, _ error: Error) {
        lock.lock()
        defer { lock.unlock() }
        stubs[path] = .failure(error)
    }

    func request<Body: Encodable, Response: Decodable>(
        path: String, method: HTTPMethod, body: Body?
    ) async throws -> Response {
        try value(path: path, method: method)
    }

    func request<Response: Decodable>(path: String, method: HTTPMethod) async throws -> Response {
        try value(path: path, method: method)
    }

    func request<Body: Encodable>(path: String, method: HTTPMethod, body: Body?) async throws {
        _ = try rawValue(path: path, method: method)
    }

    func requestVoid<Body: Encodable>(path: String, method: HTTPMethod, body: Body?) async throws {
        _ = try rawValue(path: path, method: method)
    }

    private func value<Response>(path: String, method: HTTPMethod) throws -> Response {
        let any = try rawValue(path: path, method: method)
        guard let typed = any as? Response else {
            throw APIError.decoding(underlying: "Stub for \(path) did not match \(Response.self)")
        }
        return typed
    }

    private func rawValue(path: String, method: HTTPMethod) throws -> Any {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append(Call(path: path, method: method))

        guard let stub = stubs[path] else {
            throw APIError.invalidResponse
        }
        switch stub {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }
}

/// In-memory Keychain double.
final class MockKeychainStore: KeychainStoring, @unchecked Sendable {
    private var token: String?
    private var appleUserId: String?

    func saveToken(_ token: String) { self.token = token }
    func readToken() -> String? { token }
    func deleteToken() { token = nil }
    func saveAppleUserId(_ appleUserId: String?) { self.appleUserId = appleUserId }
    func readAppleUserId() -> String? { appleUserId }
}
