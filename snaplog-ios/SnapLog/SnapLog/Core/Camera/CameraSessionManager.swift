//
//  CameraSessionManager.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import AVFoundation
import UIKit

/// Runs a multi-cam capture session with the rear camera as the primary feed
/// and the front camera recorded alongside it.
@MainActor
final class CameraSessionManager: NSObject, AVCaptureFileOutputRecordingDelegate {

    static let minimumDuration: TimeInterval = 2.0
    static let maximumDuration: TimeInterval = 4.0

    /// Whether a recorded duration satisfies the strict 2.0–4.0 s window.
    static func isValidDuration(_ duration: TimeInterval) -> Bool {
        duration >= minimumDuration && duration <= maximumDuration
    }

    private let session = AVCaptureMultiCamSession()
    /// Separate lightweight session driving the floating front-camera preview;
    /// preview layers cannot select a specific input on a shared multi-cam session.
    private let frontPreviewSession = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private(set) var isRecording = false
    private(set) var isAuthorized = false
    private(set) var isSessionConfigured = false

    private var recordingEnded: ((URL?) -> Void)?
    private var autoStopWorkItem: DispatchWorkItem?
    private var recordingStartedAt: Date?

    var isMultiCamSupported: Bool { AVCaptureMultiCamSession.isMultiCamSupported }
    var previewSession: AVCaptureSession { session }
    var frontPreview: AVCaptureSession { frontPreviewSession }

    // MARK: - Permissions

    func requestAccess() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        let micGranted = await AVAudioApplication.requestRecordPermission()
        isAuthorized = granted && micGranted
    }

    // MARK: - Session setup

    func configureSession() {
        guard !isSessionConfigured else { return }
        session.beginConfiguration()
        defer {
            session.commitConfiguration()
            isSessionConfigured = true
        }

        guard let rearCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let rearInput = try? AVCaptureDeviceInput(device: rearCamera),
              session.canAddInput(rearInput) else { return }
        session.addInput(rearInput)

        // The front camera runs alongside the rear feed when multi-cam is supported.
        if isMultiCamSupported,
           let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
           let frontInput = try? AVCaptureDeviceInput(device: frontCamera),
           session.canAddInput(frontInput) {
            session.addInput(frontInput)
        }

        guard session.canAddOutput(movieOutput) else { return }
        session.addOutput(movieOutput)

        configureFrontPreviewSession()
    }

    private func configureFrontPreviewSession() {
        guard isMultiCamSupported,
              let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: frontCamera),
              frontPreviewSession.canAddInput(input) else { return }
        frontPreviewSession.beginConfiguration()
        frontPreviewSession.addInput(input)
        frontPreviewSession.commitConfiguration()
        frontPreviewSession.sessionPreset = .vga640x480
    }

    func startRunning() {
        guard !session.isRunning else { return }
        // AVFoundation start/stop is blocking and must run off the main thread;
        // the session objects are internally thread-safe.
        nonisolated(unsafe) let session = self.session
        nonisolated(unsafe) let frontSession = frontPreviewSession
        Task.detached(priority: .userInitiated) {
            session.startRunning()
            frontSession.startRunning()
        }
    }

    func stopRunning() {
        guard session.isRunning else { return }
        nonisolated(unsafe) let session = self.session
        nonisolated(unsafe) let frontSession = frontPreviewSession
        Task.detached(priority: .userInitiated) {
            session.stopRunning()
            frontSession.stopRunning()
        }
    }

    // MARK: - Recording

    /// Starts a recording that is hard-clamped to the 2.0–4.0 s window.
    func startRecording(to url: URL, onFinish: @escaping (URL?) -> Void) {
        guard !isRecording else { return }
        isRecording = true
        recordingStartedAt = Date()
        recordingEnded = onFinish
        movieOutput.startRecording(to: url, recordingDelegate: self)

        // Auto-stop at the maximum allowed duration.
        let stop = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                self.movieOutput.stopRecording()
            }
        }
        autoStopWorkItem = stop
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.maximumDuration, execute: stop)
    }

    func stopRecording() {
        guard isRecording else { return }
        autoStopWorkItem?.cancel()
        movieOutput.stopRecording()
    }

    // MARK: - AVCaptureFileOutputRecordingDelegate

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            self.isRecording = false
            self.autoStopWorkItem?.cancel()
            let duration = self.recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            // Enforce the strict 2.0–4.0 second duration window before accepting the file.
            guard error == nil, Self.isValidDuration(duration) else {
                try? FileManager.default.removeItem(at: outputFileURL)
                self.recordingEnded?(nil)
                self.recordingEnded = nil
                return
            }
            self.recordingEnded?(outputFileURL)
            self.recordingEnded = nil
        }
    }
}
