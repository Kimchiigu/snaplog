import Fluent
import Foundation
import Redis
@preconcurrency import RediStack
import Vapor

enum DlqService {
    static let dlqKey = RedisKey("snaplog:dlq")
    static let liveChannel = RedisChannelName("snaplog:dlq:live")
    static let dlqLimit = 100
    static let maxAttempts = 3

    struct Entry: Codable {
        let job: String
        let s3Key: String
        let roomId: UUID
        let reason: String
        let failedAt: Date
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func record(_ entry: Entry, on app: Application) async {
        guard app.environment != .testing else { return }
        guard let data = try? encoder.encode(entry), let json = String(data: data, encoding: .utf8) else { return }
        let redis = app.redis
        try? await redis.lpush(json, into: dlqKey).get()
        try? await redis.ltrim(dlqKey, keepingIndices: 0...(dlqLimit - 1)).get()
        _ = try? await redis.publish(json, to: liveChannel).get()
    }

    static func recent(on redis: any RedisClient, limit: Int = 25) async -> [Entry] {
        let raw = (try? await redis.lrange(from: dlqKey, indices: 0...(limit - 1)).get()) ?? []
        return raw.compactMap { $0.string }
            .compactMap { $0.data(using: .utf8).flatMap { try? decoder.decode(Entry.self, from: $0) } }
    }

    static func markFailed(s3Key: String, on db: any Database) async {
        if let log = try? await MediaLog.query(on: db).filter(\.$s3Key == s3Key).first() {
            log.status = "failed"
            try? await log.update(on: db)
        }
    }
}
