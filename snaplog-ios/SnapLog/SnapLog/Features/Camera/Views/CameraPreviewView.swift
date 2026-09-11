import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    @MainActor let sessionManager: CameraSessionManager
    let role: Role
    var gravity: AVLayerVideoGravity = .resizeAspectFill

    enum Role {
        case primary
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
