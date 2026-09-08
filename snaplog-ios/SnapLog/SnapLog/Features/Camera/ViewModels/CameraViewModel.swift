//
//  CameraViewModel.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import AVFoundation
import Foundation
import Observation
import UIKit

/// Drives the record → pre-sign → upload → confirm dispatch pipeline.
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

    /// Records a snippet through the session manager and dispatches it if valid.
    func recordAndDispatch(
        using sessionManager: CameraSessionManager,
        roomID: String
    ) async {
        guard sessionManager.isAuthorized else {
            phase = .failed(message: "Camera access is required to record.")
            return
        }
        phase = .recording

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("snaplog-\(UUID().uuidString).mp4")

        let fileURL: URL? = await withCheckedContinuation { continuation in
            sessionManager.startRecording(to: url) { result in
                continuation.resume(returning: result)
            }
        }

        guard let fileURL else {
            phase = .failed(message: "Recording was too short — hold for at least 2 seconds.")
            return
        }
        await dispatch(fileURL: fileURL, roomID: roomID)
    }

    /// Runs the upload-url → R2 upload → confirm pipeline for a recorded file.
    func dispatch(fileURL: URL, roomID: String) async {
        do {
            let upload: UploadURLResponse = try await apiClient.request(
                path: "/logs/upload-url",
                method: .post,
                body: ["room_id": roomID]
            )
            phase = .uploading(progress: 0)

            try await uploader.upload(fileURL: fileURL, to: upload.uploadURL)
            try? FileManager.default.removeItem(at: fileURL)

            phase = .confirming
            try await apiClient.request(
                path: "/logs/confirm",
                method: .post,
                body: LogConfirmRequest(logID: upload.logID, roomID: roomID)
            )
            analytics.track(event: "log_dispatched", properties: ["room_id": roomID])
            phase = .done
        } catch {
            // Buffer the snippet so it can be retried when connectivity returns.
            offlineStore?.enqueue(localFileURL: fileURL, roomID: roomID)
            phase = .failed(message: "Upload failed. Your snippet was kept for retry.")
        }
    }

    /// Re-attempts dispatch of buffered snippets, oldest first.
    func retryPendingLogs() async {
        guard let offlineStore else { return }
        offlineStore.pruneMissingFiles()
        for log in offlineStore.pending() {
            offlineStore.remove(log)
            await dispatch(fileURL: log.localFileURL, roomID: log.roomID)
            guard case .done = phase else { continue }
        }
        phase = .idle
    }
}

/// Uploads a recorded video to object storage.
protocol VideoUploading: Sendable {
    func upload(fileURL: URL, to destination: URL) async throws
}

/// `URLSessionUploadTask`-backed uploader used in production.
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
