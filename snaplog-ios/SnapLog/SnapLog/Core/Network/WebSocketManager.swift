//
//  WebSocketManager.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import Foundation

/// Events emitted by the presence WebSocket.
enum PresenceEvent: Sendable, Equatable {
    case memberStartedRecording(roomID: String, memberID: String)
    case memberStoppedRecording(roomID: String, memberID: String)
    case connected
    case disconnected
}

/// Manages the `/presence` WebSocket connection and exposes incoming events as an async stream.
///
/// All mutable state is guarded by `stateLock`; instances are intended to be
/// created once and shared (see `AppDependencies.presenceSocket`).
final class WebSocketManager: NSObject, @unchecked Sendable {

    private let url: URL
    private let session: URLSession
    private let continuation: AsyncStream<PresenceEvent>.Continuation
    private let stream: AsyncStream<PresenceEvent>
    private var socketTask: URLSessionWebSocketTask?

    private let stateLock = NSLock()
    private var shouldReconnect = false
    private var reconnectAttempt = 0

    init(url: URL = AppConfig.presenceWebSocketURL, session: URLSession = .shared) {
        self.url = url
        self.session = session
        (stream, continuation) = AsyncStream.makeStream(of: PresenceEvent.self)
        super.init()
    }

    /// Incoming presence events, deduplicated and delivered on the caller's task.
    var events: AsyncStream<PresenceEvent> { stream }

    func connect() {
        stateLock.lock()
        defer { stateLock.unlock() }
        shouldReconnect = true
        openSocket()
    }

    func disconnect() {
        stateLock.lock()
        defer { stateLock.unlock() }
        shouldReconnect = false
        socketTask?.cancel(with: .normalClosure, reason: nil)
        socketTask = nil
    }

    func send(_ text: String) async throws {
        guard let socketTask else { throw APIError.invalidResponse }
        try await socketTask.send(.string(text))
    }

    // MARK: - Internals

    private func openSocket() {
        let task = session.webSocketTask(with: url)
        socketTask = task
        task.resume()
        receiveLoop(on: task)
        continuation.yield(.connected)
    }

    private func receiveLoop(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if let event = Self.decode(message) {
                    self.continuation.yield(event)
                }
                self.receiveLoop(on: task)
            case .failure:
                self.handleDisconnect()
            }
        }
    }

    private func handleDisconnect() {
        stateLock.lock()
        let shouldRetry = shouldReconnect
        reconnectAttempt += 1
        let delay = min(Double(reconnectAttempt), 6.0)
        stateLock.unlock()

        continuation.yield(.disconnected)
        guard shouldRetry else { return }

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            self?.openSocketIfStillActive()
        }
    }

    /// Re-opens the socket after a backoff delay, only if not disconnected in the meantime.
    private func openSocketIfStillActive() {
        stateLock.lock()
        let stillActive = shouldReconnect
        stateLock.unlock()
        guard stillActive else { return }
        openSocket()
    }

    private static func decode(_ message: URLSessionWebSocketTask.Message) -> PresenceEvent? {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8) else { return nil }
        struct Payload: Decodable {
            let type: String
            let roomID: String?
            let memberID: String?
        }
        guard let payload = try? JSONDecoder.api.decode(Payload.self, from: data) else { return nil }
        switch payload.type {
        case "recording_started":
            guard let roomID = payload.roomID, let memberID = payload.memberID else { return nil }
            return .memberStartedRecording(roomID: roomID, memberID: memberID)
        case "recording_stopped":
            guard let roomID = payload.roomID, let memberID = payload.memberID else { return nil }
            return .memberStoppedRecording(roomID: roomID, memberID: memberID)
        default:
            return nil
        }
    }
}
