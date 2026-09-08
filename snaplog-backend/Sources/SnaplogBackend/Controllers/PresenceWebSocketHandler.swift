import Fluent
import Foundation
import JWT
import JWTKit
import NIOConcurrencyHelpers
import RediStack
import Redis
import Vapor
final class PresenceWebSocketHandler: @unchecked Sendable {
    static let shared = PresenceWebSocketHandler()
    private let state = NIOLockedValueBox(State())
    private struct State {
        var sockets: [UUID: [WebSocket]] = [:]
        var subscribed = false
    }
    func connect(req: Request, ws: WebSocket) async {
        let userId: UUID
        do {
            guard let token = req.query[String.self, at: "token"] else {
                throw Abort(.unauthorized, reason: "Missing token query parameter.")
            }
            let payload = try req.jwt.verify(token, as: SessionToken.self)
            guard let id = UUID(uuidString: payload.sub.value) else {
                try? await ws.close()
                return
            }
            userId = id
        } catch {
            try? await ws.close()
            return
        }
        state.withLockedValue { $0.sockets[userId, default: []].append(ws) }
        ws.onClose.whenComplete { [weak self] _ in
            guard let self else { return }
            self.state.withLockedValue {
                $0.sockets[userId]?.removeAll { $0 === ws }
                if $0.sockets[userId]?.isEmpty == true { $0.sockets[userId] = nil }
            }
        }
        ws.onText { socket, text in
            if text == "ping" { try? await socket.send("pong") }
        }
        await subscribeToRoomEvents(on: req.application)
        try? await ws.send(#"{"event":"CONNECTED"}"#)
    }
    private func subscribeToRoomEvents(on app: Application) async {
        let alreadySubscribed = state.withLockedValue { state -> Bool in
            let was = state.subscribed
            state.subscribed = true
            return was
        }
        guard !alreadySubscribed else { return }
        app.redis.subscribe(
            to: [RedisChannelName(TimelineCache.roomEventsChannel)]
        ) { message, _ in
            let raw = message.rawValue
            guard let data = raw.data(using: .utf8),
                  let event = try? JSONDecoder().decode(RoomEventMessage.self, from: data)
            else { return }
            let payload = #"{"event":"\#(event.event)","roomId":"\#(event.roomId)","s3Key":"\#(event.s3Key)"}"#
            Task { await self.broadcast(roomId: event.roomId, message: payload) }
        }.whenComplete { _ in }
    }
    private struct RoomEventMessage: Codable {
        let event: String
        let roomId: String
        let s3Key: String
    }
    private func broadcast(roomId: String, message: String) async {
        let allSockets = state.withLockedValue { $0.sockets.values.flatMap { $0 } }
        for ws in allSockets {
            try? await ws.send(message)
        }
    }
}
