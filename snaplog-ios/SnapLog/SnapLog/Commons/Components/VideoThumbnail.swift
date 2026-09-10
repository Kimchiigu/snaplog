//
//  VideoThumbnail.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 10/09/26.
//

import AVFoundation
import SwiftUI

/// Loads a single frame from a remote video URL and fills the available
/// space with it; shows a charcoal placeholder until (or unless) it loads.
struct VideoThumbnail: View {
    let url: URL

    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Theme.cardElevated
                if isLoading == false {
                    Image(systemName: "video")
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .clipped()
        .task { await loadThumbnail() }
        .accessibilityHidden(true)
    }

    @State private var isLoading = true

    private func loadThumbnail() async {
        guard thumbnail == nil else { return }
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)
        do {
            let image = try await generator.image(at: .zero).image
            thumbnail = UIImage(cgImage: image)
        } catch {
            isLoading = false
        }
    }
}
