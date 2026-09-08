//
//  CameraPreviewView.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import AVFoundation
import SwiftUI
import UIKit

/// UIKit wrapper for `AVCaptureVideoPreviewLayer`, the only way to render a live camera feed.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var gravity: AVLayerVideoGravity = .resizeAspectFill

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as? AVCaptureVideoPreviewLayer ?? AVCaptureVideoPreviewLayer() }
    }

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = gravity
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
        uiView.previewLayer.videoGravity = gravity
    }
}
