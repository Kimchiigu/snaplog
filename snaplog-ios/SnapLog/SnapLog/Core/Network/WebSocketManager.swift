//
//  WebSocketManager.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import Foundation

/// Events emitted by the `/presence` WebSocket.
enum PresenceEvent: Sendable, Equatable {
    case connected
    case disconnected
    case newDigestReady(roomID: String)
}

/// Manages the `/presence` WebSocket connection and exposes incoming events as an async stream.
///
/// All mutable state is guarded by `stateLock`; instances are intended to be
/// created once and shared (see `AppDependencies.presenceSocket`).
final class WebSocketManager: NSObject, @unchecked Sendable {

    private let session: URLSession
    private let continuation: AsyncStream<PresenceEvent>.Continuation
    private let stream: AsyncStream<PresenceEvent>
    private var socketTask: URLSessionWebSocketTask?

    private let stateLock = NSLock()
    private var shouldReconnect = false
    private var reconnectAttempt = 0
    private var authToken: String?
    private var pingTask: Task<Void, Never>?

    init(session: URLSession = .shared) {
        self.session = session
        (stream, continuation) = AsyncStream.makeStream(of: PresenceEvent.self)
        super.init()
    }

    /// Incoming presence events, delivered on the caller's task.
    var events: AsyncStream<PresenceEvent> { stream }

    /// Connects to `​/presence?token=<jwt>` and starts a ping keepalive.
    func connect(token: String) {
        stateLock.lock()
        authToken = token
        shouldReconnect = true
        stateLock.unlock()
        openSocket()
    }

    func disconnect() {
        stateLock.lock()
        defer { stateLock.unlock() }
        shouldReconnect = false
        pingTask?.cancel()
        socketTask?.cancel(with: .normalClosure, reason: nil)
        socketTask = nil
    }

    // MARK: - Internals

    private func openSocket() {
        stateLock.lock()
        guard let token = authToken else {
            stateLock.unlock()
            return
        }
        var request = URLRequest(url: AppConfig.presenceWebSocketURL(token: token))
        // Skip ngrok's free-tier browser interstitial when tunneling.
        request.setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")
        let task = session.webSocketTask(with: request)
        socketTask = task
        stateLock.unlock()

        task.resume()
        receiveLoop(on: task)
        startPingLoop(on: task)
        continuation.yield(.connected)
    }

    /// The server expects a literal "ping" text frame and answers "pong".
    private func startPingLoop(on task: URLSessionWebSocketTask) {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard let self, !Task.isCancelled else { return }
                try? await self.sendPing(on: task)
            }
        }
    }

    private func sendPing(on task: URLSessionWebSocketTask) async {
        try? await task.send(.string("ping"))
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

    /// Backend frames look like `{"event":"NEW_DIGEST_READY","roomId":"…","s3Key":"…"}`
    /// or `{"event":"CONNECTED"}`.
    private static func decode(_ message: URLSessionWebSocketTask.Message) -> PresenceEvent? {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8) else { return nil }
        struct Payload: Decodable {
            let event: String
            let roomId: String?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        switch payload.event {
        case "CONNECTED":
            return .connected
        case "NEW_DIGEST_READY":
            guard let roomId = payload.roomId else { return nil }
            return .newDigestReady(roomID: roomId)
        default:
            return nil
        }
    }
}
