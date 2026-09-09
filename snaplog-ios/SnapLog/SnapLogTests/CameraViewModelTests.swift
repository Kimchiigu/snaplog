//
//  CameraViewModelTests.swift
//  SnapLogTests
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import AVFoundation
import Testing
@testable import SnapLog

@MainActor
struct CameraViewModelTests {

    private let roomID = UUID(uuidString: "00000000-0000-0000-0000-00000000000A") ?? UUID()

    // MARK: - Duration constraint (PRD 4.3: strictly 2.0–4.0 s)

    @Test func durationsOutsideWindowAreRejected() {
        let invalid: [Double] = [0.0, 1.9, 4.1, 10.0]
        for duration in invalid {
            #expect(!CameraSessionManager.isValidDuration(duration), "expected \(duration)s rejected")
        }
    }

    @Test func durationsInsideWindowAreAccepted() {
        let valid: [Double] = [2.0, 2.5, 3.99, 4.0]
        for duration in valid {
            #expect(CameraSessionManager.isValidDuration(duration), "expected \(duration)s accepted")
        }
    }

    // MARK: - Dispatch pipeline

    @Test func dispatchFailureKeepsFailurePhase() async throws {
        let api = MockAPIClient()
        api.stubFailure("/logs/upload-url", APIError.network(underlying: "offline"))
        let viewModel = CameraViewModel(apiClient: api, uploader: MockUploader())

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data([0]))

        await viewModel.dispatch(fileURL: fileURL, roomID: roomID, duration: 3.0)

        guard case .failed = viewModel.phase else {
            Issue.record("expected failed phase, got \(viewModel.phase)")
            return
        }
        try? FileManager.default.removeItem(at: fileURL)
    }

    @Test func dispatchSuccessReachesDone() async throws {
        let api = MockAPIClient()
        api.stub(
            "/logs/upload-url",
            result: .success(UploadURLResponse(uploadURL: "http://localhost:1/upload", s3Key: "raw/abc.mp4"))
        )
        // requestVoid only needs a stub present; the body is an empty 202.
        api.stub("/logs/confirm", result: .success(true))
        let viewModel = CameraViewModel(apiClient: api, uploader: MockUploader())

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("src-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data([0, 1, 2]))

        await viewModel.dispatch(fileURL: fileURL, roomID: roomID, duration: 3.0)

        #expect(viewModel.phase == .done)
        try? FileManager.default.removeItem(at: fileURL)
    }

    @Test func uploadFailureKeepsFileForRetry() async throws {
        let api = MockAPIClient()
        api.stub(
            "/logs/upload-url",
            result: .success(UploadURLResponse(uploadURL: "http://localhost:1/upload", s3Key: "raw/def.mp4"))
        )
        let viewModel = CameraViewModel(apiClient: api, uploader: MockUploader(shouldFail: true))

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("keep-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data([0]))

        await viewModel.dispatch(fileURL: fileURL, roomID: roomID, duration: 3.0)

        guard case .failed = viewModel.phase else {
            Issue.record("expected failed phase, got \(viewModel.phase)")
            return
        }
        // The snippet must survive for the offline retry queue.
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// Uploader double: succeeds or throws on demand.
struct MockUploader: VideoUploading, @unchecked Sendable {
    var shouldFail = false

    func upload(fileURL: URL, to destination: URL) async throws {
        if shouldFail { throw APIError.network(underlying: "upload failed") }
    }
}
