//
//  CameraPreviewView.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import AVFoundation
import SwiftUI
import UIKit

/// UIKit wrapper for `AVCaptureVideoPreviewLayer` — the only way to render a
/// live camera feed. The layer is wired to the requested role via the session
/// manager's explicit connections; roles stay fixed to their views, so
/// "switch camera" simply rebinds the connections.
struct CameraPreviewView: UIViewRepresentable {
    @MainActor let sessionManager: CameraSessionManager
    let role: Role
    var gravity: AVLayerVideoGravity = .resizeAspectFill

    enum Role {
        /// Recorded feed shown fullscreen.
        case primary
        /// Preview-only feed shown in the floating window.
        case secondary
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as? AVCaptureVideoPreviewLayer ?? AVCaptureVideoPreviewLayer()
        }
    }

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.videoGravity = gravity
        switch role {
        case .primary: sessionManager.attachPrimaryPreview(view.previewLayer)
        case .secondary: sessionManager.attachSecondaryPreview(view.previewLayer)
        }
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.previewLayer.videoGravity = gravity
    }
}
