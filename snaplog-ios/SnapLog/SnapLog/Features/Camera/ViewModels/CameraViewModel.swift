
import AVFoundation
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class CameraViewModel {

    enum Phase: Equatable {
        case idle
        case recording
        case uploading(progress: Double)
        case confirming
        case done
        case failed(message: String)
    }

    private(set) var phase: Phase = .idle

    private static let minimumDurationPromptAfter: TimeInterval = 3.0

    private let apiClient: APIClientProtocol
    private let analytics: AnalyticsService
    private let uploader: VideoUploading
    private let offlineStore: PendingLogStore?

    init(
        apiClient: APIClientProtocol,
        analytics: AnalyticsService = NoopAnalyticsService(),
        uploader: VideoUploading = URLSessionVideoUploader(),
        offlineStore: PendingLogStore? = nil
    ) {
        self.apiClient = apiClient
        self.analytics = analytics
        self.uploader = uploader
        self.offlineStore = offlineStore
    }

    func recordAndDispatch(
        using sessionManager: CameraSessionManager,
        roomID: UUID
    ) async {
        guard let captured = await record(using: sessionManager) else { return }
        await dispatch(fileURL: captured.fileURL, roomID: roomID, duration: captured.duration)
    }

    func record(
        using sessionManager: CameraSessionManager
    ) async -> (fileURL: URL, duration: TimeInterval)? {
        guard sessionManager.isAuthorized else {
            phase = .failed(message: "Camera access is required to record.")
            return nil
        }
        phase = .recording

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("snaplog-\(UUID().uuidString).mp4")

        let startedAt = Date()
        let (fileURL, recordedDuration): (URL?, TimeInterval) = await withCheckedContinuation { continuation in
            sessionManager.startRecording(to: url) { url, duration in
                continuation.resume(returning: (url, duration))
            }
        }

        guard let fileURL else {
            let elapsed = Date().timeIntervalSince(startedAt)
            let message = elapsed < Self.minimumDurationPromptAfter
                ? "Recording was too short — hold for at least 2 seconds."
                : "Recording failed. Please try again."
            phase = .failed(message: message)
            return nil
        }
        phase = .idle
        return (fileURL, recordedDuration)
    }

    @discardableResult
    func send(fileURL: URL, roomIDs: [UUID], duration: TimeInterval) async -> Int {
        var sent = 0
        for (index, roomID) in roomIDs.enumerated() {
            let target: URL
            if index == roomIDs.count - 1 {
                target = fileURL
            } else {
                let copy = FileManager.default.temporaryDirectory
                    .appendingPathComponent("snaplog-\(UUID().uuidString).mp4")
                do {
                    try FileManager.default.copyItem(at: fileURL, to: copy)
                    target = copy
                } catch {
                    continue
                }
            }
            await dispatch(fileURL: target, roomID: roomID, duration: duration)
            if case .done = phase { sent += 1 }
        }
        return sent
    }

    func dispatch(fileURL: URL, roomID: UUID, duration: Double) async {
        do {
            let upload: UploadURLResponse = try await apiClient.request(
                path: "/logs/upload-url",
                method: .post,
                body: UploadURLRequest(roomId: roomID, fileExtension: "mp4")
            )
            phase = .uploading(progress: 0)

            try await uploader.upload(fileURL: fileURL, to: upload.destination)
            try? FileManager.default.removeItem(at: fileURL)

            phase = .confirming
            try await apiClient.requestVoid(
                path: "/logs/confirm",
                method: .post,
                body: LogConfirmRequest(s3Key: upload.s3Key, duration: duration, roomId: roomID)
            )
            analytics.track(event: "log_dispatched", properties: ["room_id": roomID.uuidString])
            phase = .done
        } catch {
            offlineStore?.enqueue(localFileURL: fileURL, roomID: roomID.uuidString)
            phase = .failed(message: "Upload failed. Your snippet was kept for retry.")
        }
    }

    func retryPendingLogs() async {
        guard let offlineStore else { return }
        offlineStore.pruneMissingFiles()
        for log in offlineStore.pending() {
            offlineStore.remove(log)
            guard let roomID = UUID(uuidString: log.roomID),
                  FileManager.default.fileExists(atPath: log.localFileURL.path) else { continue }
            await dispatch(fileURL: log.localFileURL, roomID: roomID, duration: 3.0)
            guard case .done = phase else { continue }
        }
        phase = .idle
    }
}

protocol VideoUploading: Sendable {
    func upload(fileURL: URL, to destination: URL) async throws
}

struct URLSessionVideoUploader: VideoUploading {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func upload(fileURL: URL, to destination: URL) async throws {
        var request = URLRequest(url: destination)
        request.httpMethod = "PUT"
        request.setValue("video/mp4", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await session.upload(for: request, fromFile: fileURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
    }
}
