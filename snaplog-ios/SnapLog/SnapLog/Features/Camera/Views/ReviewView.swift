
import AVFoundation
import Photos
import SwiftUI

struct ReviewView: View {
    @Environment(\.dismiss) private var dismiss

    let clip: CameraView.CapturedClip
    let preselectedRoom: Room?
    let onSent: () -> Void

    @State private var roomsViewModel = RoomListViewModel(apiClient: AppDependencies.apiClient)
    @State private var sendViewModel = CameraViewModel(apiClient: AppDependencies.apiClient)

    @State private var selectedRoomIDs: Set<UUID> = []
    @State private var caption = ""
    @State private var isMuted = false
    @State private var isSending = false
    @State private var sendError: String?
    @State private var savedToPhotos: Bool?

    @State private var queuePlayer: AVQueuePlayer?
    @State private var playerLooper: AVPlayerLooper?

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                navBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        previewCard
                        roomSection
                        captionField
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await roomsViewModel.loadRooms()
            if let preselectedRoom {
                selectedRoomIDs = [preselectedRoom.id]
            }
            let item = AVPlayerItem(url: clip.fileURL)
            let player = AVQueuePlayer()
            playerLooper = AVPlayerLooper(player: player, templateItem: item)
            player.isMuted = isMuted
            queuePlayer = player
            await player.play()
        }
        .onDisappear {
            queuePlayer?.pause()
            playerLooper?.disableLooping()
        }
        .onChange(of: isMuted) { _, muted in
            queuePlayer?.isMuted = muted
        }
    }

    private var navBar: some View {
        ZStack {
            Text("send")
                .font(.headline)
                .foregroundStyle(.white)
            HStack {
                Button {
                    try? FileManager.default.removeItem(at: clip.fileURL)
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular.tint(.black.opacity(0.6)), in: .circle)
                }
                .accessibilityLabel("Discard clip")
                Spacer()
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Theme.canvas)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Theme.accent))
                }
                .disabled(selectedRoomIDs.isEmpty || isSending)
                .opacity(selectedRoomIDs.isEmpty || isSending ? 0.4 : 1)
                .accessibilityLabel("Send to selected rooms")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var previewCard: some View {
        ZStack {
            if let queuePlayer {
                PlayerContainerView(player: queuePlayer)
            } else {
                Theme.cardElevated
            }

            LiveTimestamp()
                .accessibilityLabel("Capture time")

            HStack {
                Spacer()
                VStack {
                    Spacer()
                    HStack {
                        Button {
                            isMuted.toggle()
                        } label: {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.body)
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .glassEffect(.regular.tint(.black.opacity(0.5)), in: .circle)
                        }
                        .accessibilityLabel(isMuted ? "Unmute preview" : "Mute preview")
                        Spacer()
                        Button(action: saveToPhotos) {
                            Image(systemName: savedToPhotos == true ? "checkmark" : "arrow.down.to.line")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(savedToPhotos == true ? Theme.accent : .white)
                                .frame(width: 40, height: 40)
                                .glassEffect(.regular.tint(.black.opacity(0.5)), in: .circle)
                        }
                        .accessibilityLabel("Save to Photos")
                    }
                    .padding(12)
                }
            }
        }
        .frame(height: 340)
        .clipShape(.rect(cornerRadius: 24))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clip preview, \(String(format: "%.0f", clip.duration)) seconds")
    }

    private var roomSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("send to:")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.muted)

            if roomsViewModel.rooms.isEmpty && roomsViewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(roomsViewModel.rooms) { room in
                    roomRow(room)
                }
            }

            if isSending {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("sending…")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                .padding(.top, 4)
            }
            if let sendError {
                Text(sendError)
                    .font(.footnote)
                    .foregroundStyle(Theme.pink)
            }
        }
    }

    private func roomRow(_ room: Room) -> some View {
        let isSelected = selectedRoomIDs.contains(room.id)
        return Button {
            if isSelected {
                selectedRoomIDs.remove(room.id)
            } else {
                selectedRoomIDs.insert(room.id)
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Theme.accent : Theme.muted.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 24, height: 24)
                    if isSelected {
                        Circle().fill(Theme.accent).frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Theme.canvas)
                    }
                }

                HStack(spacing: -8) {
                    let colors: [Color] = [Theme.pink, Theme.blue, Theme.accent]
                    ForEach(Array(room.members.prefix(3).enumerated()), id: \.offset) { index, _ in
                        SmileyIcon(color: colors[index % colors.count], size: 18)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(room.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(room.members.map(\.displayName).prefix(2).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(14)
            .background(Theme.card, in: .rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(room.displayName)\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(.isButton)
    }

    private var captionField: some View {
        TextField("add a caption…", text: $caption, axis: .vertical)
            .font(.subheadline)
            .foregroundStyle(.white)
            .lineLimit(1...3)
            .padding(14)
            .background(Theme.card, in: .rect(cornerRadius: 20))
            .padding(.top, 4)
    }

    private func send() {
        guard !selectedRoomIDs.isEmpty, !isSending else { return }
        isSending = true
        sendError = nil
        Task {
            queuePlayer?.pause()
            let sent = await sendViewModel.send(
                fileURL: clip.fileURL,
                roomIDs: Array(selectedRoomIDs),
                duration: clip.duration
            )
            isSending = false
            if sent > 0 {
                onSent()
            } else {
                sendError = "Couldn't send. The clip was kept for retry."
            }
        }
    }

    private func saveToPhotos() {
        Task { await saveToPhotosAsync() }
    }

    private func saveToPhotosAsync() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            savedToPhotos = false
            return
        }
        do {
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = clip.fileURL.lastPathComponent
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset()
                    .addResource(with: .video, fileURL: clip.fileURL, options: options)
            }
            savedToPhotos = true
        } catch {
            savedToPhotos = false
        }
    }
}

struct PlayerContainerView: UIViewRepresentable {
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

#Preview {
    ReviewView(
        clip: CameraView.CapturedClip(
            fileURL: URL(fileURLWithPath: "/dev/null"),
            duration: 4
        ),
        preselectedRoom: nil,
        onSent: {}
    )
}
