import Foundation
import NIOConcurrencyHelpers
import NIOCore
import Redis
@preconcurrency import RediStack
import Vapor

enum NetworkMonitor {
    static let podsKey = RedisKey("snaplog:pods")
    static let netlogKey = RedisKey("snaplog:netlog")
    static let countersKey = RedisKey("snaplog:counters")


    static let netlogChannel = RedisChannelName("snaplog:netlog:live")

    static let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    static let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    static let netlogLimit = 200
    static let heartbeatInterval: TimeInterval = 5
    static let podStaleAfter: TimeInterval = 30

    struct PodInfo: Codable {
        let id: String
        let role: String
        let host: String
        let startedAt: Date
        var lastSeen: Date
        var requestCount: Int
    }

    struct LogEntry: Codable {
        let t: Date
        let ip: String
        let source: String
        let method: String
        let path: String
        let status: UInt
        let durationMs: Double
        let pod: String
    }

    static func instanceId() -> String {
        let host = Environment.get("HOSTNAME") ?? "local"
        return host + "-" + String(UUID().uuidString.prefix(8))
    }

    static func startHeartbeat(on app: Application) {
        let id = instanceId()
        let pod = PodInfo(
            id: id,
            role: Environment.get("POD_ROLE") ?? "app",
            host: Environment.get("HOSTNAME") ?? "local",
            startedAt: Date(),
            lastSeen: Date(),
            requestCount: 0
        )
        let counter = NIOLockedValueBox(0)
        app.storage[RequestCounterKey.self] = counter
        let started = NIOLockedValueBox(false)
        let task = Task {
            while !started.withLockedValue({ $0 }) { await Task.yield() }
            while !Task.isCancelled {
                var info = pod
                info.lastSeen = Date()
                info.requestCount = counter.withLockedValue { $0 }
                if let data = try? JSONEncoder().encode(info), let json = String(data: data, encoding: .utf8) {
                    try? await app.redis.hset(id, to: json, in: NetworkMonitor.podsKey).get()
                    try? await app.redis.expire(podsKey, after: TimeAmount.seconds(60)).get()
                }
                try? await Task.sleep(nanoseconds: UInt64(heartbeatInterval * 1_000_000_000))
            }
        }
        final class HeartbeatHandler: LifecycleHandler {
            let task: Task<Void, Never>
            let id: String
            let started: NIOLockedValueBox<Bool>
            init(task: Task<Void, Never>, id: String, started: NIOLockedValueBox<Bool>) {
                self.task = task
                self.id = id
                self.started = started
            }
            func didBootAsync(_ application: Application) async throws {
                started.withLockedValue { $0 = true }
            }
            func shutdown(_ application: Application) {
                task.cancel()
                // Test apps never boot Redis; touching it here races the storage
                // teardown and trips RediStack's "No redis found" fatal.
                guard application.environment != .testing else { return }
                let id = self.id
                Task { _ = try? await application.redis.hdel([id], from: NetworkMonitor.podsKey).get() }
            }
        }
        app.lifecycle.use(HeartbeatHandler(task: task, id: id, started: started))
    }

    struct RequestCounterKey: StorageKey {
        typealias Value = NIOLockedValueBox<Int>
    }

    static func record(_ entry: LogEntry, on app: Application) {
        if let counter = app.storage[RequestCounterKey.self] {
            counter.withLockedValue { $0 += 1 }
        }
        guard let data = try? jsonEncoder.encode(entry),
              let json = String(data: data, encoding: .utf8) else { return }
        Task {
            let redis = app.redis
            try? await redis.lpush(json, into: netlogKey).get()
            _ = try? await redis.publish(json, to: netlogChannel).get()
            try? await redis.ltrim(netlogKey, keepingIndices: 0...(netlogLimit - 1)).get()
            try? await redis.hincrby(1, field: "total", in: countersKey).get()
            try? await redis.hincrby(1, field: entry.source, in: countersKey).get()
            if (400..<600).contains(entry.status) {
                try? await redis.hincrby(1, field: "errors", in: countersKey).get()
            }
        }
    }

    static func activePods(on redis: any RedisClient) async -> [PodInfo] {
        let hash = (try? await redis.hgetall(from: NetworkMonitor.podsKey).get()) ?? [:]
        let raw = hash.values.compactMap { $0.string }
        let cutoff = Date().addingTimeInterval(-podStaleAfter)
        return raw
            .compactMap { $0.data(using: .utf8).flatMap { try? JSONDecoder().decode(PodInfo.self, from: $0) } }
            .filter { $0.lastSeen > cutoff }
            .sorted { $0.lastSeen > $1.lastSeen }
    }

    static func recentLogs(on redis: any RedisClient, pathFilter: String = "", statusFilter: String = "all") async -> [LogEntry] {
        let raw = (try? await redis.lrange(from: netlogKey, indices: 0...199).get()) ?? []
        return raw.compactMap { $0.string }
            .compactMap { $0.data(using: .utf8).flatMap { try? jsonDecoder.decode(LogEntry.self, from: $0) } }
            .filter { entry in
                if !pathFilter.isEmpty, !entry.path.localizedCaseInsensitiveContains(pathFilter) { return false }
                switch statusFilter {
                case "2xx": return (200..<300).contains(entry.status)
                case "3xx": return (300..<400).contains(entry.status)
                case "4xx": return (400..<500).contains(entry.status)
                case "5xx": return (500..<600).contains(entry.status)
                default: return true
                }
            }
    }

    static func counters(on redis: any RedisClient) async -> (total: Int, caddy: Int, direct: Int, errors: Int) {
        let hash = (try? await redis.hgetall(from: countersKey).get()) ?? [:]
        func field(_ name: String) -> Int { hash[name]?.int ?? 0 }
        return (field("total"), field("caddy"), field("direct"), field("errors"))
    }
}

struct NetworkLogMiddleware: AsyncMiddleware {
    let podId = NetworkMonitor.instanceId()

    func respond(to req: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let start = DispatchTime.now()
        let response = try await next.respond(to: req)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        let source = req.headers.first(name: "X-Real-IP") != nil ? "caddy" : "direct"
        var path = req.url.path
        if path.hasPrefix("/api/health") { return response }
        if path.isEmpty { path = "/" }
        NetworkMonitor.record(NetworkMonitor.LogEntry(
            t: Date(),
            ip: req.headers.first(name: "X-Real-IP") ?? req.remoteAddress?.description ?? "-",
            source: source,
            method: req.method.rawValue,
            path: path,
            status: response.status.code,
            durationMs: (elapsed * 10).rounded() / 10,
            pod: podId
        ), on: req.application)
        return response
    }
}
