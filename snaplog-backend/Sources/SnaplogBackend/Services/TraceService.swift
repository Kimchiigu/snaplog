import Foundation
import NIOConcurrencyHelpers
import Redis
@preconcurrency import RediStack
import Vapor

enum TraceService {
    static let tracesKey = RedisKey("snaplog:traces")
    static let liveChannel = RedisChannelName("snaplog:traces:live")
    static let traceLimit = 100
    static let headerName = "X-Trace-Id"

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

    struct Span: Codable {
        let name: String
        let offsetMs: Double
        let durationMs: Double
        let detail: String?
    }

    struct TraceRecord: Codable {
        let id: String
        let method: String
        let path: String
        let status: UInt
        let startedAt: Date
        let totalMs: Double
        let pod: String
        var spans: [Span]
    }

    struct SpanEvent: Codable {
        let traceId: String
        let span: Span
    }

    final class Context: @unchecked Sendable {
        let id: String
        let start = DispatchTime.now()
        private let spans = NIOLockedValueBox([Span]())

        init(id: String) {
            self.id = id
        }

        func record(_ name: String, detail: String? = nil, durationMs: Double) {
            let offset = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            let rounded = (durationMs * 10).rounded() / 10
            spans.withLockedValue {
                $0.append(Span(name: name, offsetMs: (offset * 10).rounded() / 10, durationMs: rounded, detail: detail))
            }
        }

        func span<T>(_ name: String, detail: String? = nil, _ body: () async throws -> T) async rethrows -> T {
            let begin = DispatchTime.now()
            let value = try await body()
            record(name, detail: detail, durationMs: Double(DispatchTime.now().uptimeNanoseconds - begin.uptimeNanoseconds) / 1_000_000)
            return value
        }

        func finish(method: String, path: String, status: UInt, pod: String) -> TraceRecord {
            let total = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            return TraceRecord(
                id: id,
                method: method,
                path: path,
                status: status,
                startedAt: Date(),
                totalMs: (total * 10).rounded() / 10,
                pod: pod,
                spans: spans.withLockedValue { $0 }
            )
        }
    }

    struct ContextKey: StorageKey {
        typealias Value = Context
    }

    static func store(_ record: TraceRecord, on app: Application) async {
        guard app.environment != .testing,
              let data = try? encoder.encode(record),
              let json = String(data: data, encoding: .utf8) else { return }
        let redis = app.redis
        try? await redis.lpush(json, into: tracesKey).get()
        try? await redis.ltrim(tracesKey, keepingIndices: 0...(traceLimit - 1)).get()
        _ = try? await redis.publish(json, to: liveChannel).get()
    }

    static func publishSpan(traceId: String, _ span: Span, on app: Application) {
        guard app.environment != .testing else { return }
        let event = SpanEvent(traceId: traceId, span: span)
        guard let data = try? encoder.encode(event), let json = String(data: data, encoding: .utf8) else { return }
        Task {
            _ = try? await app.redis.publish(json, to: liveChannel).get()
        }
    }

    static func recent(on redis: any RedisClient, limit: Int = 50) async -> [TraceRecord] {
        let raw = (try? await redis.lrange(from: tracesKey, indices: 0...(limit - 1)).get()) ?? []
        return raw.compactMap { $0.string }
            .compactMap { $0.data(using: .utf8).flatMap { try? decoder.decode(TraceRecord.self, from: $0) } }
    }
}

struct TraceMiddleware: AsyncMiddleware {
    let podId = NetworkMonitor.instanceId()

    func respond(to req: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        if req.url.path.hasPrefix("/api/health") {
            return try await next.respond(to: req)
        }
        let id = req.headers.first(name: TraceService.headerName) ?? UUID().uuidString
        let context = TraceService.Context(id: id)
        req.storage[TraceService.ContextKey.self] = context
        let response: Response
        do {
            response = try await next.respond(to: req)
        } catch {
            let status = (error as? any AbortError)?.status.code ?? 500
            await TraceService.store(context.finish(method: req.method.rawValue, path: req.url.path, status: status, pod: podId), on: req.application)
            throw error
        }
        response.headers.replaceOrAdd(name: TraceService.headerName, value: id)
        await TraceService.store(context.finish(method: req.method.rawValue, path: req.url.path, status: response.status.code, pod: podId), on: req.application)
        return response
    }
}

extension Request {
    var trace: TraceService.Context {
        if let existing = storage[TraceService.ContextKey.self] {
            return existing
        }
        let detached = TraceService.Context(id: "detached")
        storage[TraceService.ContextKey.self] = detached
        return detached
    }
}
