//
//  LoopingVideoPlayer.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 10/09/26.
//

import AVFoundation
import SwiftUI

/// Streams a remote clip and loops it silently, filling the available space.
/// Used as live video backgrounds on cards and tiles (no play buttons).
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
        .task {
            guard player == nil else { return }
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

/// SwiftUI bridge rendering an `AVPlayer`'s layer directly.
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
