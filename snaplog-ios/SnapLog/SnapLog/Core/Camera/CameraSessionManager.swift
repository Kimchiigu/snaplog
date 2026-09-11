import AVFoundation
import Observation
import UIKit

@MainActor
@Observable
final class CameraSessionManager: NSObject, AVCaptureFileOutputRecordingDelegate {

    nonisolated static let minimumDuration: TimeInterval = 2.0
    nonisolated static let maximumDuration: TimeInterval = 4.0

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

    private(set) var isReady = false
    private(set) var isRecording = false
    private(set) var isAuthorized = false
    private(set) var setupError: String?
    private var isStarting = false

    private(set) var isFrontPrimary = false
    private(set) var isTorchOn = false
    private(set) var zoomFactor: CGFloat = 1

    private var recordingEnded: ((URL?, TimeInterval) -> Void)?
    private var autoStopWorkItem: DispatchWorkItem?
    private var watchdogWorkItem: DispatchWorkItem?

    var isMultiCamSupported: Bool { AVCaptureMultiCamSession.isMultiCamSupported }
    var captureSession: AVCaptureSession { session }

    private var primaryInput: AVCaptureDeviceInput? { isFrontPrimary ? frontInput : rearInput }
    private var secondaryInput: AVCaptureDeviceInput? { isFrontPrimary ? rearInput : frontInput }

    static let shared = CameraSessionManager()

    func startup() async {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        if !isReady {
            await requestAccess()
            guard isAuthorized else {
                setupError = "Camera access is required to record."
                return
            }
            configureSession()
            guard rearInput != nil else { return } // configureSession already set setupError.
        }
        setupError = nil

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

    private func configureSession() {
        guard rearInput == nil else { return } // idempotent
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .inputPriority

        let rearDevice = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        guard let rearDevice,
              let rear = try? AVCaptureDeviceInput(device: rearDevice),
              session.canAddInput(rear) else {
            setupError = "Couldn't access the rear camera."
            return
        }
        session.addInputWithNoConnections(rear)
        rearInput = rear
        // Start at logical 1x: the ultra-wide's native factor frames like 0.5x,
        // so jump straight to the wide-equivalent factor without a visible ramp.
        if let device = rearInput?.device {
            let target = Swift.min(
                Swift.max(zoomBase(for: device), device.minAvailableVideoZoomFactor),
                device.maxAvailableVideoZoomFactor
            )
            if target > 1 {
                try? device.lockForConfiguration()
                device.videoZoomFactor = target
                device.unlockForConfiguration()
            }
        }

        if AVCaptureMultiCamSession.isMultiCamSupported,
           let frontDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
           let front = try? AVCaptureDeviceInput(device: frontDevice),
           session.canAddInput(front) {
            session.addInputWithNoConnections(front)
            frontInput = front
        }

        session.addOutputWithNoConnections(movieOutput)
        movieOutput.maxRecordedDuration = CMTime(seconds: Self.maximumDuration, preferredTimescale: 600)
        rebuildConnections()
    }

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
        if layer.session !== session {
            layer.setSessionWithNoConnection(session)
        }
        let connection = AVCaptureConnection(inputPort: port, videoPreviewLayer: layer)
        guard session.canAddConnection(connection) else { return nil }
        session.addConnection(connection)
        return connection
    }

    func attachPrimaryPreview(_ layer: AVCaptureVideoPreviewLayer) {
        primaryPreviewLayer = layer
        rebuildConnections()
    }

    func attachSecondaryPreview(_ layer: AVCaptureVideoPreviewLayer) {
        secondaryPreviewLayer = layer
        rebuildConnections()
    }

    func switchCameras() {
        guard frontInput != nil else { return }
        isFrontPrimary.toggle()
        isTorchOn = false
        rebuildConnections()
    }

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

    func setZoom(_ factor: CGFloat) {
        guard let device = primaryInput?.device else { return }
        let base = zoomBase(for: device)
        let minFactor = device.minAvailableVideoZoomFactor
        let maxFactor = Swift.min(device.maxAvailableVideoZoomFactor, 12)
        let clamped = Swift.min(Swift.max(factor * base, minFactor), maxFactor)
        do {
            try device.lockForConfiguration()
            device.ramp(toVideoZoomFactor: clamped, withRate: 8)
            device.unlockForConfiguration()
            zoomFactor = clamped / base
        } catch {
        }
    }

    private func zoomBase(for device: AVCaptureDevice) -> CGFloat {
        guard device.deviceType == .builtInUltraWideCamera,
              let wide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        else { return 1 }
        let ultraHalf = CGFloat(device.activeFormat.videoFieldOfView) * .pi / 360
        let wideHalf = CGFloat(wide.activeFormat.videoFieldOfView) * .pi / 360
        guard ultraHalf > 0, wideHalf > 0 else { return 1 }
        return tan(ultraHalf) / tan(wideHalf)
    }

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

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        let duration = output.recordedDuration.seconds
        let failed = (error != nil) || duration.isNaN
            || duration < Self.minimumDuration
            || duration > Self.maximumDuration * 1.1
        let reported = Swift.min(duration, Self.maximumDuration)
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
            self.recordingEnded?(outputFileURL, reported)
            self.recordingEnded = nil
        }
    }
}
