import AVKit
import OSLog
import Photos
import SwiftUI

struct RoomDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let room: Room

    @State private var viewModel = RoomDetailViewModel()
    @State private var showingCamera = false
    @State private var showingHistory = false
    @State private var showingSettings = false
    @State private var playingClip: PlaybackClip?
    @State private var updatedRoom: Room?
    @State private var hourOffset = 0
    @State private var rotationDetector = RotationDetector()

    private var effectiveRoom: Room { viewModel.liveRoom ?? updatedRoom ?? room }

    private var isOwner: Bool {
        effectiveRoom.members.first { $0.id == appState.currentUser?.id }?.role == "owner"
    }

    private var selectedHourDate: Date {
        Calendar.current.date(byAdding: .hour, value: -hourOffset, to: Date()) ?? Date()
    }

    private static func hourLabel(for date: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        return String(format: "%02d:00", hour)
    }

    private var selectedHourClips: [PlaybackClip] {
        let calendar = Calendar.current
        let selected = selectedHourDate
        return viewModel.hourlyGroups
            .flatMap(\.clips)
            .filter { calendar.isDate($0.createdAt, equalTo: selected, toGranularity: .hour) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                navBar
                content
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.loadPlayback(roomID: room.id)
            if let token = appState.authToken {
                viewModel.startObservingPresence(roomID: room.id)
            }
        }
        .onDisappear {
            viewModel.stopObservingPresence()
            rotationDetector.stop()
        }
        .task { rotationDetector.start() }
        .onChange(of: rotationDetector.isLandscape) { _, isLandscape in
            showingCamera = isLandscape
        }
        .refreshable { await viewModel.loadPlayback(roomID: room.id) }
        .fullScreenCover(isPresented: $showingCamera, onDismiss: {
            Task { await viewModel.loadPlayback(roomID: room.id) }
        }) {
            CameraView(room: effectiveRoom)
        }
        .fullScreenCover(isPresented: $showingHistory, onDismiss: {
            Task { await viewModel.loadPlayback(roomID: room.id) }
        }) {
            RoomHistoryView(room: effectiveRoom)
        }
        .sheet(isPresented: $showingSettings) {
            RoomSettingsSheet(
                room: effectiveRoom,
                viewModel: viewModel,
                isOwner: isOwner,
                onSaved: { updated in
                    updatedRoom = updated
                },
                onLeft: {
                    dismiss()
                }
            )
            .environment(appState)
        }
        .sheet(item: $playingClip) { clip in
            ClipPlayerSheet(clip: clip)
        }
    }

    private var navBar: some View {
        HStack(spacing: 14) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .glassEffect(.regular.tint(.black.opacity(0.6)), in: .circle)
            }
            .accessibilityLabel("Back")

            Spacer()

            Button {
                showingSettings = true
            } label: {
                HStack(spacing: 6) {
                    Text(effectiveRoom.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .glassEffect(.regular.tint(.black.opacity(0.6)), in: .capsule)
            }
            .accessibilityLabel("Room \(effectiveRoom.displayName), settings")

            Spacer()
            
            Button {
                showingHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.body)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40)
                    .glassEffect(.regular.tint(.black.opacity(0.6)), in: .circle)
            }
            .accessibilityLabel("Room history")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.hourlyGroups.isEmpty {
            Spacer()
            ProgressView()
            Spacer()
        } else {
            ScrollView {
                VStack(spacing: 14) {
                    if let message = viewModel.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                    hourPager
                    ForEach(effectiveRoom.members) { member in
                        memberCard(member)
                    }
                    if effectiveRoom.members.isEmpty {
                        Text("No members yet — share invite code \(effectiveRoom.inviteCode).")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
    }

    private var hourPager: some View {
        HStack(spacing: 18) {
            Button {
                withAnimation { hourOffset += 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular.tint(.black.opacity(0.6)), in: .circle)
            .accessibilityLabel("Previous hour")

            Text(Self.hourLabel(for: selectedHourDate))
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(minWidth: 96)
                .contentShape(.rect)

            Button {
                withAnimation { hourOffset = max(hourOffset - 1, 0) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular.tint(.black.opacity(0.6)), in: .circle)
            .disabled(hourOffset == 0)
            .accessibilityLabel("Next hour")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func memberCard(_ member: RoomMemberDTO) -> some View {
        let isMe = member.displayName == appState.currentUser?.displayName
        let current = selectedHourClips.first { $0.authorName == member.displayName }
        let loggedThisHour = hourOffset == 0 && current != nil && isMe

        return ZStack {
            if let current {
                LoopingVideoPlayer(url: current.playbackURL)
            } else {
                Theme.card
            }

            LinearGradient(
                colors: [.black.opacity(0.15), .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )

            Color.clear.contentShape(.rect)
                .onTapGesture {
                    if let current { playingClip = current }
                }

            VStack {
                Spacer()
                Text(Self.hourLabel(for: selectedHourDate))
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
            }

            VStack {
                Spacer()
                HStack {
                    Text(member.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    clipMenu(current: current, isMine: isMe)
                }
                if isMe {
                    if hourOffset > 0 {
                        Text("past hour — view only")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Theme.cardElevated))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 10)
                            .accessibilityLabel("Past hour, capturing is closed")
                    } else if loggedThisHour {
                        Text("logged — back at \(nextHourLabel())")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Theme.cardElevated))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 10)
                            .accessibilityLabel("Already logged this hour")
                    } else {
                        Button {
                            showingCamera = true
                        } label: {
                            Text("tap to capture")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.canvas)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule()
                                        .fill(Theme.accent.opacity(0.9))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Tap to capture a clip for this room")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                    }
                }
            }
            .padding(16)
        }
        .frame(height: isMe ? 210 : 170)
        .clipShape(.rect(cornerRadius: 24))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(member.displayName)'s card\(current == nil ? ", no clips this hour" : "")")
    }

    private func nextHourLabel() -> String {
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        return Self.hourLabel(for: next)
    }

    @ViewBuilder
    private func clipMenu(current: PlaybackClip?, isMine: Bool) -> some View {
        Menu {
            if let current {
                Button {
                    Task { await saveClip(current) }
                } label: {
                    Label("Save to Photos", systemImage: "arrow.down.to.line")
                }
                Button {
                    playingClip = current
                } label: {
                    Label("Play fullscreen", systemImage: "play.rectangle")
                }
            }
            if isMine, let current {
                Button(role: .destructive) {
                    Task { await deleteClip(current) }
                } label: {
                    Label("Delete Clip", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body)
                .foregroundStyle(Theme.muted)
                .frame(width: 36, height: 36)
                .glassEffect(.regular.tint(.black.opacity(0.6)), in: .circle)
        }
        .accessibilityLabel("Clip options")
    }

    private static let saveLogger = Logger(subsystem: "com.christopherhygunawan.SnapLog", category: "SaveClip")

    private func saveClip(_ clip: PlaybackClip) async {
        Self.saveLogger.info("save requested: \(clip.s3Key)")
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            Self.saveLogger.warning("photos permission denied (\(status.rawValue))")
            viewModel.report("Photos access is needed to save clips.")
            return
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("snaplog-save-\(UUID().uuidString).mp4")
        do {
            let sourceURL = clip.playbackURL
            let download = Task.detached(priority: .userInitiated) { () throws -> Int in
                let (data, response) = try await URLSession.shared.data(from: sourceURL)
                guard let http = response as? HTTPURLResponse,
                      (200..<400).contains(http.statusCode),
                      data.count > 1024 else {
                    throw URLError(.zeroByteResource)
                }
                try data.write(to: tempURL, options: .atomic)
                return data.count
            }
            let byteCount = try await download.value
            Self.saveLogger.info("downloaded \(byteCount) bytes, saving to Photos")
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = tempURL.lastPathComponent
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset()
                    .addResource(with: .video, fileURL: tempURL, options: options)
            }
            Self.saveLogger.info("saved to Photos successfully")
            viewModel.report("Saved to Photos.")
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            Self.saveLogger.error("save failed: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tempURL)
            viewModel.report("Couldn't save the clip.")
        }
    }

    private func deleteClip(_ clip: PlaybackClip) async {
        if await viewModel.deleteClip(roomID: room.id, s3Key: clip.s3Key) {
            await viewModel.loadPlayback(roomID: room.id)
        }
    }

}

struct ClipPlayerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let clip: PlaybackClip
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            Group {
                if let player {
                    VideoPlayer(player: player)
                } else {
                    ProgressView()
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(clip.authorName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        player?.pause()
                        dismiss()
                    }
                }
            }
            .task {
                if player == nil {
                    player = AVPlayer(url: clip.playbackURL)
                    await player?.play()
                }
            }
            .onDisappear { player?.pause() }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    NavigationStack {
        RoomDetailView(
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
    }
    .environment(AppState())
}
