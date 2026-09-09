import Vapor

enum ModerationService {
    struct Verdict: Codable {
        let approved: Bool
        let reason: String?
    }

    /// Moderation gate for user-generated clips.
    ///
    /// When `MODERATION_URL` is configured, each clip's public R2 URL is POSTed as
    /// `{ "s3Key": ..., "url": ... }` and the endpoint answers `{ "approved": Bool, "reason": String? }`.
    /// Point it at AWS Rekognition, Hive AI, Cloudflare Workers AI, or any wrapper you build.
    /// With no `MODERATION_URL` set (local dev), every clip passes.
    static func check(s3Key: String, publicURL: String, on app: Application) async -> Verdict {
        guard let endpoint = Environment.get("MODERATION_URL") else {
            app.logger.notice("moderation skipped (MODERATION_URL not set) for \(s3Key)")
            return Verdict(approved: true, reason: nil)
        }
        do {
            let response = try await app.client.post(URI(string: endpoint)) { request in
                try request.content.encode(["s3Key": s3Key, "url": publicURL])
            }
            return try response.content.decode(Verdict.self)
        } catch {
            app.logger.error("moderation check failed for \(s3Key): \(error)")
            return Verdict(approved: false, reason: "moderation unavailable")
        }
    }
}
