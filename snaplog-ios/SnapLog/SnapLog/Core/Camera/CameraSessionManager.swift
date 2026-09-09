//
//  CameraSessionManager.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import AVFoundation
import UIKit

/// Runs a multi-cam capture session: one camera is the recorded primary feed
/// (fullscreen preview), the other is preview-only in the floating window.
///
/// Follows Apple's capture-session guidance: all configuration happens inside
/// `beginConfiguration()`/`commitConfiguration()` with the preset set first;
/// `startRunning()` runs on a background serial queue and `isReady` is only
/// set once the session is actually running; preview layers attach through
/// explicit connections so each view binds to the intended camera.
@MainActor
final class CameraSessionManager: NSObject, AVCaptureFileOutputRecordingDelegate {

    nonisolated static let minimumDuration: TimeInterval = 2.0
    nonisolated static let maximumDuration: TimeInterval = 4.0

    /// Whether a recorded duration satisfies the strict 2.0–4.0 s window.
    nonisolated static func isValidDuration(_ duration: TimeInterval) -> Bool {
        duration >= minimumDuration && duration <= maximumDuration
    }

    private let session = AVCaptureMultiCamSession()
    private let sessionQueue = DispatchQueue(label: "com.snaplog.camera", qos: .userInitiated)
    private let movieOutput = AVCaptureMovieFileOutput()
    private nonisolated(unsafe) var rearInput: AVCaptureDeviceInput?
    private nonisolated(unsafe) var frontInput: AVCaptureDeviceInput?

    private var movieConnection: AVCaptureConnection?
    private var primaryPreviewConnection: AVCaptureConnection?
    private var secondaryPreviewConnection: AVCaptureConnection?
    private nonisolated(unsafe) var primaryPreviewLayer: AVCaptureVideoPreviewLayer?
    private nonisolated(unsafe) var secondaryPreviewLayer: AVCaptureVideoPreviewLayer?

    /// True once the session is configured AND running — previews may attach.
    private(set) var isReady = false
    private(set) var isRecording = false
    private(set) var isAuthorized = false
    private(set) var setupError: String?

    /// Whether the front camera is currently the recorded primary feed.
    private(set) var isFrontPrimary = false
    private(set) var isTorchOn = false
    private(set) var zoomFactor: CGFloat = 1

    private var recordingEnded: ((URL?, TimeInterval) -> Void)?
    private var autoStopWorkItem: DispatchWorkItem?
    private var watchdogWorkItem: DispatchWorkItem?

    var isMultiCamSupported: Bool { AVCaptureMultiCamSession.isMultiCamSupported }
    var captureSession: AVCaptureSession { session }

    /// The input whose feed is recorded and shown fullscreen.
    private var primaryInput: AVCaptureDeviceInput? { isFrontPrimary ? frontInput : rearInput }
    /// The preview-only input shown in the floating window.
    private var secondaryInput: AVCaptureDeviceInput? { isFrontPrimary ? rearInput : frontInput }

    // MARK: - Startup

    /// Requests permissions, configures the session, and starts it running.
    /// Preview views must not attach until this completes (`isReady == true`).
    func startup() async {
        await requestAccess()
        guard isAuthorized else {
            setupError = "Camera access is required to record."
            return
        }
        configureSession()
        guard rearInput != nil else { return } // configureSession already set setupError.
        // Wait for startRunning to finish before announcing readiness —
        // starting a recording against a non-running session never fires the
        // delegate and hangs the pipeline.
        nonisolated(unsafe) let session = self.session
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                if !session.isRunning { session.startRunning() }
                continuation.resume()
            }
        }
        isReady = true
    }

    private func requestAccess() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        let micGranted = await AVAudioApplication.requestRecordPermission()
        isAuthorized = granted && micGranted
    }

    func shutdown() {
        cancelRecordingTimers()
        nonisolated(unsafe) let session = self.session
        sessionQueue.async {
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    // MARK: - Session configuration

    private func configureSession() {
        guard rearInput == nil else { return } // idempotent
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // Multi-cam sessions must use .inputPriority (per AVCaptureMultiCamSession docs).
        session.sessionPreset = .inputPriority

        // Prefer dual/triple virtual devices so 0.5x zoom reaches the ultra-wide.
        let rearDevice = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        guard let rearDevice,
              let rear = try? AVCaptureDeviceInput(device: rearDevice),
              session.canAddInput(rear) else {
            setupError = "Couldn't access the rear camera."
            return
        }
        session.addInputWithNoConnections(rear)
        rearInput = rear

        if AVCaptureMultiCamSession.isMultiCamSupported,
           let frontDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
           let front = try? AVCaptureDeviceInput(device: frontDevice),
           session.canAddInput(front) {
            session.addInputWithNoConnections(front)
            frontInput = front
        }

        session.addOutputWithNoConnections(movieOutput)
        rebuildConnections()
    }

    /// (Re)builds the movie + preview connections for the current primary camera.
    private func rebuildConnections() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        for connection in [movieConnection, primaryPreviewConnection, secondaryPreviewConnection].compactMap({ $0 }) {
            if session.connections.contains(connection) {
                session.removeConnection(connection)
            }
        }
        movieConnection = nil
        primaryPreviewConnection = nil
        secondaryPreviewConnection = nil

        // Only the primary feed is recorded.
        if let primaryInput {
            let connection = AVCaptureConnection(inputPorts: primaryInput.ports, output: movieOutput)
            guard session.canAddConnection(connection) else {
                setupError = "Couldn't configure recording output."
                return
            }
            session.addConnection(connection)
            movieConnection = connection
        }

        primaryPreviewConnection = attach(primaryPreviewLayer, to: primaryInput)
        secondaryPreviewConnection = attach(secondaryPreviewLayer, to: secondaryInput)
    }

    @discardableResult
    private func attach(
        _ layer: AVCaptureVideoPreviewLayer?,
        to input: AVCaptureDeviceInput?
    ) -> AVCaptureConnection? {
        guard let layer, let input,
              let port = input.ports.first(where: { $0.mediaType == .video }) else { return nil }
        layer.session = session
        let connection = AVCaptureConnection(inputPort: port, videoPreviewLayer: layer)
        guard session.canAddConnection(connection) else { return nil }
        session.addConnection(connection)
        return connection
    }

    // MARK: - Preview attachment

    /// Connects a preview layer to the primary (recorded) feed. Call when `isReady`.
    func attachPrimaryPreview(_ layer: AVCaptureVideoPreviewLayer) {
        primaryPreviewLayer = layer
        rebuildConnections()
    }

    /// Connects a preview layer to the secondary (floating window) feed. Call when `isReady`.
    func attachSecondaryPreview(_ layer: AVCaptureVideoPreviewLayer) {
        secondaryPreviewLayer = layer
        rebuildConnections()
    }

    // MARK: - Camera controls

    /// Swaps which camera is recorded fullscreen and which is in the PiP window.
    func switchCameras() {
        guard frontInput != nil else { return }
        isFrontPrimary.toggle()
        isTorchOn = false
        rebuildConnections()
    }

    /// Toggles the rear torch (flashlight). Front cameras have no torch.
    func setTorch(_ on: Bool) {
        isTorchOn = on
        guard let rearDevice = rearInput?.device, rearDevice.hasTorch else { return }
        do {
            try rearDevice.lockForConfiguration()
            rearDevice.torchMode = on ? .on : .off
            rearDevice.unlockForConfiguration()
        } catch {
            isTorchOn = false
        }
    }

    /// Sets the primary camera's zoom. 0.5 maps to the widest available factor
    /// (ultra-wide on supporting devices), and everything is clamped to the
    /// device's supported range.
    func setZoom(_ factor: CGFloat) {
        guard let device = primaryInput?.device else { return }
        let minFactor = device.minAvailableVideoZoomFactor
        let maxFactor = Swift.min(device.maxAvailableVideoZoomFactor, 10)
        let clamped = factor < 1 ? minFactor : Swift.min(Swift.max(factor, minFactor), maxFactor)
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
            zoomFactor = clamped
        } catch {
            // Unsupported factor for this device; keep the previous zoom.
        }
    }

    // MARK: - Recording

    /// Starts a recording that auto-stops at exactly `maximumDuration`.
    /// `onFinish` receives the file URL and its measured duration, or `(nil, 0)`
    /// if the recording failed or fell outside the 2.0–4.0 s window.
    func startRecording(to url: URL, onFinish: @escaping (URL?, TimeInterval) -> Void) {
        guard !isRecording, isReady else {
            if !isReady { setupError = "Camera isn't ready yet." }
            onFinish(nil, 0)
            return
        }
        isRecording = true
        recordingEnded = onFinish
        movieOutput.startRecording(to: url, recordingDelegate: self)

        let stop = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                self.movieOutput.stopRecording()
            }
        }
        autoStopWorkItem = stop
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.maximumDuration, execute: stop)

        // Safety net: if the delegate never fires (e.g. broken output connection),
        // fail the capture instead of hanging the pipeline forever.
        let watchdog = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                self.isRecording = false
                self.recordingEnded?(nil, 0)
                self.recordingEnded = nil
            }
        }
        watchdogWorkItem = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.maximumDuration + 2.5, execute: watchdog)
    }

    func stopRecording() {
        guard isRecording else { return }
        movieOutput.stopRecording()
    }

    private func cancelRecordingTimers() {
        autoStopWorkItem?.cancel()
        autoStopWorkItem = nil
        watchdogWorkItem?.cancel()
        watchdogWorkItem = nil
    }

    // MARK: - AVCaptureFileOutputRecordingDelegate

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        // The file's own duration is authoritative; wall-clock measurement
        // overshoots because this delegate fires slightly after the auto-stop.
        let duration = output.recordedDuration.seconds
        let failed = (error != nil) || duration.isNaN || !Self.isValidDuration(duration)
        Task { @MainActor in
            guard self.isRecording else { return }
            self.isRecording = false
            self.cancelRecordingTimers()
            guard !failed else {
                try? FileManager.default.removeItem(at: outputFileURL)
                self.recordingEnded?(nil, 0)
                self.recordingEnded = nil
                return
            }
            self.recordingEnded?(outputFileURL, duration)
            self.recordingEnded = nil
        }
    }
}
