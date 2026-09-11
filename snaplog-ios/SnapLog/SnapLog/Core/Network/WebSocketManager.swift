import Foundation

enum PresenceEvent: Sendable, Equatable {
    case connected
    case disconnected
    case newDigestReady(roomID: String)
    case newLog(roomID: String, authorName: String?)
    case logDeleted(roomID: String)
    case memberJoined(roomID: String)
}

final class WebSocketManager: NSObject, @unchecked Sendable {

    private let session: URLSession

    private var listeners: [UUID: AsyncStream<PresenceEvent>.Continuation] = [:]
    private var socketTask: URLSessionWebSocketTask?

    private let stateLock = NSLock()
    private var shouldReconnect = false
    private var reconnectAttempt = 0
    private var authToken: String?
    private var pingTask: Task<Void, Never>?

    init(session: URLSession = .shared) {
        self.session = session
        super.init()
    }

    var events: AsyncStream<PresenceEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<PresenceEvent>.makeStream()
        continuation.onTermination = { [weak self] _ in
            self?.stateLock.lock()
            self?.listeners[id] = nil
            self?.stateLock.unlock()
        }
        stateLock.lock()
        listeners[id] = continuation
        stateLock.unlock()
        return stream
    }

    private func broadcast(_ event: PresenceEvent) {
        stateLock.lock()
        let continuations = Array(listeners.values)
        stateLock.unlock()
        for continuation in continuations {
            continuation.yield(event)
        }
    }

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

    private func openSocket() {
        stateLock.lock()
        guard let token = authToken else {
            stateLock.unlock()
            return
        }
        var request = URLRequest(url: AppConfig.presenceWebSocketURL(token: token))
        request.setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")
        let task = session.webSocketTask(with: request)
        socketTask = task
        stateLock.unlock()

        task.resume()
        receiveLoop(on: task)
        startPingLoop(on: task)
        broadcast(.connected)
    }

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
                    self.broadcast(event)
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

        broadcast(.disconnected)
        guard shouldRetry else { return }

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            self?.openSocketIfStillActive()
        }
    }

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
            let event: String
            let roomId: String?
            let authorName: String?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        switch payload.event {
        case "CONNECTED":
            return .connected
        case "NEW_DIGEST_READY":
            guard let roomId = payload.roomId else { return nil }
            return .newDigestReady(roomID: roomId)
        case "NEW_LOG":
            guard let roomId = payload.roomId else { return nil }
            return .newLog(roomID: roomId, authorName: payload.authorName)
        case "LOG_DELETED":
            guard let roomId = payload.roomId else { return nil }
            return .logDeleted(roomID: roomId)
        case "MEMBER_JOINED":
            guard let roomId = payload.roomId else { return nil }
            return .memberJoined(roomID: roomId)
        default:
            return nil
        }
    }
}
