import Foundation
import JWT
import JWTKit
import NIOConcurrencyHelpers
import Redis
@preconcurrency import RediStack
import Vapor

final class DlqWebSocketHandler: @unchecked Sendable {
    static let shared = DlqWebSocketHandler()
    private let state = NIOLockedValueBox(State())
    private struct State {
        var sockets: [WebSocket] = []
        var subscribed = false
    }

    func connect(req: Request, ws: WebSocket) async {
        do {
            guard let token = req.cookies[AdminAuthMiddleware.cookieName]?.string else {
                throw Abort(.unauthorized)
            }
            _ = try req.jwt.verify(token, as: AdminToken.self)
        } catch {
            req.logger.notice("dlq-ws auth failed: \(error)")
            try? await ws.close()
            return
        }
        state.withLockedValue { $0.sockets.append(ws) }
        ws.onClose.whenComplete { [weak self] _ in
            guard let self else { return }
            self.state.withLockedValue { $0.sockets.removeAll { $0 === ws } }
        }
        ws.onText { socket, text in
            if text == "ping" { try? await socket.send("pong") }
        }
        await subscribe(on: req.application)
        try? await ws.send(#"{"event":"connected"}"#)
    }

    private func subscribe(on app: Application) async {
        let alreadySubscribed = state.withLockedValue { state -> Bool in
            let was = state.subscribed
            state.subscribed = true
            return was
        }
        guard !alreadySubscribed else { return }
        app.redis.subscribe(to: [DlqService.liveChannel]) { _, payload in
            guard let json = payload.string else { return }
            Task { await self.broadcast(json) }
        }.whenComplete { _ in }
    }

    private func broadcast(_ json: String) async {
        let sockets = state.withLockedValue { $0.sockets }
        for ws in sockets {
            try? await ws.send(json)
        }
    }
}
