//
//  CameraView.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import SwiftUI

/// Full-screen capture experience: rear feed, floating front-camera window,
/// and a record button clamped to the 2–4 second window.
struct CameraView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sessionManager = CameraSessionManager()
    @State private var viewModel = CameraViewModel(
        apiClient: AppDependencies.apiClient,
        offlineStore: PendingLogStore()
    )

    @State private var frontPreviewVisible = true

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreviewView(session: sessionManager.previewSession)
                .ignoresSafeArea()

            overlayContent
        }
        .task {
            await viewModel.retryPendingLogs()
            await sessionManager.requestAccess()
            sessionManager.configureSession()
            sessionManager.startRunning()
        }
        .onDisappear {
            sessionManager.stopRunning()
        }
        .onChange(of: viewModel.phase) { _, newPhase in
            if newPhase == .done {
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var overlayContent: some View {
        VStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .padding(12)
                        .background(.ultraThinMaterial, in: .circle)
                }
                .accessibilityLabel("Close camera")
                Spacer()
                if frontPreviewVisible {
                    CameraPreviewView(session: sessionManager.frontPreview)
                        .frame(width: 110, height: 160)
                        .clipShape(.rect(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(.white.opacity(0.4), lineWidth: 1)
                        }
                        .padding(.trailing)
                        .accessibilityLabel("Front camera preview")
                        .onTapGesture { frontPreviewVisible = false }
                }
            }
            Spacer()
            statusMessage
            controls
        }
        .padding()
    }

    @ViewBuilder
    private var statusMessage: some View {
        switch viewModel.phase {
        case .uploading(let progress):
            ProgressView(value: progress) {
                Text("Uploading…")
            }
            .padding(.bottom, 8)
        case .confirming:
            Text("Finishing up…")
                .padding(.bottom, 8)
        case .failed(let message):
            Text(message)
                .font(.footnote)
                .padding(8)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 8))
                .padding(.bottom, 8)
        default:
            EmptyView()
        }
    }

    private var controls: some View {
        Button {
            Task { await viewModel.recordAndDispatch(using: sessionManager, roomID: "current") }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 84, height: 84)
                Circle()
                    .fill(viewModel.phase == .recording ? .red : .white)
                    .frame(width: 68, height: 68)
            }
        }
        .disabled(viewModel.phase == .recording || isBusyUploading)
        .accessibilityLabel(
            viewModel.phase == .recording ? "Recording" : "Record a 2 to 4 second video log"
        )
        .padding(.bottom, 24)
    }

    private var isBusyUploading: Bool {
        switch viewModel.phase {
        case .uploading, .confirming, .done: true
        default: false
        }
    }
}

#Preview {
    CameraView()
}
