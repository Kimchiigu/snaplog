import APNS
import APNSCore
import Fluent
import Foundation
import Vapor
import VaporAPNS

enum PushNotificationService {
    struct IsConfigured: StorageKey {
        typealias Value = Bool
    }

    static func configure(_ app: Application) throws {
        guard
            let keyPath = Environment.get("APNS_KEY_PATH"),
            let keyId = Environment.get("APNS_KEY_ID"),
            let teamId = Environment.get("APNS_TEAM_ID"),
            let keyData = FileManager.default.contents(atPath: keyPath)
        else {
            app.storage[IsConfigured.self] = false
            app.logger.notice("APNs not configured (need APNS_KEY_PATH, APNS_KEY_ID, APNS_TEAM_ID); pushes will be logged only")
            return
        }
        // Registers both a production and a sandbox client; we pick one per
        // send using the APNS_ENVIRONMENT flag.
        app.apns.configure(.jwt(
            privateKey: try .loadFrom(string: String(decoding: keyData, as: UTF8.self)),
            keyIdentifier: keyId,
            teamIdentifier: teamId
        ))
        app.storage[IsConfigured.self] = true
    }

    static var configured: (Application) -> Bool { { $0.storage[IsConfigured.self] ?? false } }

    static var topic: String {
        Environment.get("APNS_TOPIC")
            ?? Environment.get("APPLE_BUNDLE_ID")
            ?? "com.christopherhygunawan.SnapLog"
    }

    /// Sends "new digest ready" pushes to every member of the room except the uploader.
    /// Used from the queue worker after a stitch job completes.
    static func notifyRoomDigestReady(app: Application, roomId: UUID?, s3Key: String, excluding userId: UUID?) async {
        guard let roomId else { return }
        var tokenQuery = DeviceToken.query(on: app.db)
            .join(RoomMember.self, on: \DeviceToken.$user.$id == \RoomMember.$user.$id)
            .filter(RoomMember.self, \.$room.$id == roomId)
        if let userId {
            tokenQuery = tokenQuery.filter(\.$user.$id != userId)
        }
        let tokens = (try? await tokenQuery.all()) ?? []
        guard !tokens.isEmpty else { return }
        guard configured(app) else {
            app.logger.notice("push skipped (APNs not configured): would notify \(tokens.count) devices for room \(roomId)")
            return
        }
        let notification = APNSAlertNotification(
            alert: .init(
                title: .raw("New video log ready"),
                body: .raw("A new digest just landed in your room.")
            ),
            expiration: .none,
            priority: .immediately,
            topic: topic,
            payload: EmptyPayload(),
            threadID: roomId.uuidString
        )
        // sandbox for local/Xcode builds, production for TestFlight/App Store
        let client: APNSGenericClient
        switch Environment.get("APNS_ENVIRONMENT") {
        case "production": client = app.apns.client(.production)
        default: client = app.apns.client(.development)
        }
        var sent = 0
        for token in tokens {
            do {
                _ = try await client.sendAlertNotification(notification, deviceToken: token.token)
                sent += 1
            } catch {
                app.logger.warning("APNs send failed for token \(token.token.prefix(8))…: \(error)")
            }
        }
        app.logger.info("sent digest-ready push to \(sent)/\(tokens.count) devices for room \(roomId)")
    }
}
