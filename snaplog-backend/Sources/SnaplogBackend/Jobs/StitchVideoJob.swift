import Fluent
import Foundation
import Queues
import Redis
import RediStack
import Vapor

struct StitchVideoJobPayload: Codable {
    let roomId: UUID
    let s3Key: String
    let duration: Double
}

struct StitchVideoJob: AsyncJob {
    typealias Payload = StitchVideoJobPayload

    func dequeue(_ context: QueueContext, _ payload: StitchVideoJobPayload) async throws {
        let app = context.application
        let logger = context.logger
        let r2 = R2Service(app.r2)
        let roomId = payload.roomId
        logger.info("StitchVideoJob started for room \(roomId)")

        let clips = try await MediaLog.query(on: context.application.db)
            .filter(\.$room.$id == roomId)
            .sort(\.$createdAt, .descending)
            .limit(4)
            .all()

        guard !clips.isEmpty else {
            logger.warning("No clips found for room \(roomId); skipping stitch.")
            return
        }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snaplog-stitch-\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }
        var localPaths: [String] = []

        for clip in clips {
            let data = try await r2.download(key: clip.s3Key, using: app.client)
            let url = workDir.appendingPathComponent("\(UUID().uuidString)-\(clip.s3Key.split(separator: "/").last ?? "clip.mp4")")
            try data.write(to: url)
            localPaths.append(url.path)
        }

        let digestKey = "digests/\(roomId.uuidString)/\(Int(Date().timeIntervalSince1970)).mp4"
        let outputPath = workDir.appendingPathComponent("digest.mp4").path

        if localPaths.count == 1 {
            try await Self.runFFmpeg(arguments: ["-y", "-i", localPaths[0], "-c:v", "libx264", "-preset", "veryfast", outputPath], logger: logger)
        } else {
            while localPaths.count < 4 {
                localPaths.append(localPaths[localPaths.count - 1])
            }
            var args = ["-y"]
            for path in localPaths { args += ["-i", path] }
            let scales = (0..<4).map { "[\(String($0)):v]scale=480:480,setsar=1[v\($0)]" }.joined(separator: ";")
            let xstack = "\(scales);[v0][v1][v2][v3]xstack=inputs=4:layout=0_0|w0_0|0_h0|w0_h0[vout]"
            args += ["-filter_complex", xstack, "-map", "[vout]", "-c:v", "libx264", "-preset", "veryfast", outputPath]
            try await Self.runFFmpeg(arguments: args, logger: logger)
        }
        
        let digestData = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        try await r2.upload(key: digestKey, data: digestData, contentType: "video/mp4", using: app.client)
        let entry = TimelineCache.Entry(
            s3Key: digestKey,
            duration: payload.duration,
            createdAt: Date().timeIntervalSince1970
        )
        let entryJSON = String(data: try JSONEncoder().encode(entry), encoding: .utf8)!
        _ = try await app.redis.zadd(
            [(element: RedisKey(entryJSON), score: entry.createdAt)],
            to: RedisKey(TimelineCache.zsetKey(roomId: roomId))
        ).get()
        let event: [String: String] = [
            "event": "NEW_DIGEST_READY",
            "roomId": roomId.uuidString,
            "s3Key": digestKey
        ]
        let eventJSON = String(data: try JSONEncoder().encode(event), encoding: .utf8)!
        _ = try await app.redis.publish(eventJSON, to: RedisChannelName(TimelineCache.roomEventsChannel)).get()
        logger.info("StitchVideoJob finished for room \(roomId): \(digestKey)")
    }
    private static func runFFmpeg(arguments: [String], logger: Logger) async throws {
        logger.debug("ffmpeg \(arguments.joined(separator: " "))")
        let process = Process()
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw Abort(.internalServerError, reason: "FFmpeg is not installed on the worker.")
        }
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        try process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Abort(.internalServerError, reason: "FFmpeg exited with status \(process.terminationStatus).")
        }
    }
}
