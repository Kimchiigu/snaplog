
import AVFoundation
import SwiftUI

struct LoopingVideoPlayer: View {
    let url: URL
    var isMuted = true

    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        ZStack {
            if let player {
                AVPlayerLayerView(player: player)
            } else {
                Theme.cardElevated
            }
        }
        .clipped()
        .task(id: url) {
            player?.pause()
            looper?.disableLooping()
            looper = nil
            player = nil
            let item = AVPlayerItem(url: url)
            let queuePlayer = AVQueuePlayer()
            looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
            queuePlayer.isMuted = isMuted
            player = queuePlayer
            await queuePlayer.play()
        }
        .onDisappear {
            player?.pause()
            looper?.disableLooping()
        }
        .accessibilityHidden(true)
    }
}

struct AVPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as? AVPlayerLayer ?? AVPlayerLayer() }
    }

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}
