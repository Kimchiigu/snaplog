//
//  CameraView.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import SwiftUI

/// Full-screen capture experience: primary feed fullscreen, floating secondary
/// window, viewfinder overlays, and a shutter that records exactly 4 seconds.
struct CameraView: View {
    @Environment(\.dismiss) private var dismiss

    /// The room this capture started from; it becomes the pre-selected
    /// destination in the review screen. `nil` when opened from the dock.
    let room: Room?

    @State private var sessionManager = CameraSessionManager()
    @State private var viewModel = CameraViewModel(
        apiClient: AppDependencies.apiClient,
        offlineStore: PendingLogStore()
    )

    @State private var capturedClip: CapturedClip?
    @State private var ringProgress: CGFloat = 0

    struct CapturedClip: Identifiable {
        let id = UUID()
        let fileURL: URL
        let duration: TimeInterval
    }

    private var isRecording: Bool {
        if case .recording = viewModel.phase { return true }
        return false
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if sessionManager.isReady {
                CameraPreviewView(sessionManager: sessionManager, role: .primary)
                    .ignoresSafeArea()
                overlayContent
            } else {
                preparingView
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await viewModel.retryPendingLogs()
            await sessionManager.startup()
        }
        .fullScreenCover(item: $capturedClip) { clip in
            ReviewView(clip: clip, preselectedRoom: room) {
                dismiss()
            }
        }
        .onDisappear {
            sessionManager.shutdown()
        }
    }

    // MARK: - Capture

    private func capture() {
        guard !isRecording else {
            sessionManager.stopRecording()
            return
        }
        ringProgress = 0
        withAnimation(.linear(duration: CameraSessionManager.maximumDuration)) {
            ringProgress = 1
        }
        Task {
            guard let captured = await viewModel.record(using: sessionManager) else {
                ringProgress = 0
                return
            }
            ringProgress = 0
            capturedClip = CapturedClip(fileURL: captured.fileURL, duration: captured.duration)
        }
    }

    // MARK: - Preparing state

    private var preparingView: some View {
        VStack(spacing: 14) {
            if sessionManager.setupError != nil {
                ContentUnavailableView {
                    Label("Camera Unavailable", systemImage: "video.slash")
                } description: {
                    Text(sessionManager.setupError ?? "")
                } actions: {
                    Button("Close") { dismiss() }
                }
            } else {
                ProgressView("Preparing camera…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
    }

    // MARK: - Live overlay

    private var overlayContent: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            if isRecording {
                Text("recording…")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.bottom, 8)
            } else if case .failed(let message) = viewModel.phase {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: .capsule)
                    .padding(.bottom, 8)
            }
            zoomBar
            shutterButton
                .padding(.bottom, 20)
            bottomActionBar
                .padding(.bottom, 24)
        }
        .padding()
    }

    private var topBar: some View {
        ZStack {
            VStack(spacing: 4) {
                LiveTimestamp()
                    .accessibilityLabel("Current time")
                if let room {
                    Text(room.displayName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.ultraThinMaterial))
                }
            }
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(.black.opacity(0.45)))
                }
                .accessibilityLabel("Close camera")
            }
        }
    }

    // MARK: - Controls

    private var zoomBar: some View {
        HStack(spacing: 4) {
            ForEach([0.5, 1.0, 2.0], id: \.self) { factor in
                Button {
                    sessionManager.setZoom(factor)
                } label: {
                    Text(factor == 0.5 ? ".5" : String(Int(factor)))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(abs(sessionManager.zoomFactor - factor) < 0.01 ? Theme.canvas : .white)
                        .frame(width: 38, height: 38)
                        .background(
                            Circle().fill(abs(sessionManager.zoomFactor - factor) < 0.01 ? Theme.accent : .black.opacity(0.45))
                        )
                }
                .accessibilityLabel("\(factor) times zoom")
            }
        }
        .padding(5)
        .background(Capsule().fill(.black.opacity(0.3)))
        .padding(.bottom, 18)
    }

    private var shutterButton: some View {
        Button(action: capture) {
            ZStack {
                // Progress ring around the shutter while recording.
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 92, height: 92)
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 84, height: 84)
                SmileyIcon(color: Theme.accent, size: 40)
            }
        }
        .accessibilityLabel(isRecording ? "Stop recording" : "Record a 4 second clip")
    }

    private var bottomActionBar: some View {
        HStack(spacing: 48) {
            Button {
                sessionManager.setTorch(!sessionManager.isTorchOn)
            } label: {
                Image(systemName: sessionManager.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(.black.opacity(0.45)))
            }
            .disabled(sessionManager.isFrontPrimary)
            .accessibilityLabel(sessionManager.isTorchOn ? "Turn off flashlight" : "Turn on flashlight")

            Button {
                sessionManager.switchCameras()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(.black.opacity(0.45)))
            }
            .disabled(!sessionManager.isMultiCamSupported)
            .accessibilityLabel(sessionManager.isFrontPrimary ? "Switch to rear camera" : "Switch to front camera")
        }
    }
}

#Preview {
    CameraView(
        room: Room(
            id: UUID(),
            name: "Weekend Trip",
            roomType: .log,
            maxMembers: 4,
            inviteCode: "AB12CD",
            createdAt: nil,
            members: [],
            timeline: []
        )
    )
    .preferredColorScheme(.dark)
}
