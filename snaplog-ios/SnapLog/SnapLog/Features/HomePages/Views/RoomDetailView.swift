//
//  RoomDetailView.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 09/09/26.
//

import AVKit
import Photos
import SwiftUI

/// A room's detail for the *current* hour: member cards with their clips
/// playing as live video backgrounds, the hour's label, and a tap-to-capture
/// CTA. Earlier hours live in the history page.
struct RoomDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let room: Room

    @State private var viewModel = RoomDetailViewModel()
    @State private var showingCamera = false
    @State private var showingHistory = false
    @State private var showingSettings = false
    @State private var playingClip: PlaybackClip?
    /// The room after an in-place settings update (name/size/members).
    @State private var updatedRoom: Room?
    /// Which clip each member's card is paged to (index into newest-first).
    @State private var clipPageIndex: [UUID: Int] = [:]

    /// The freshest copy of the room (settings updates included).
    private var effectiveRoom: Room { updatedRoom ?? room }

    /// The current hour's label, e.g. "08:00" (not the live minute time).
    private static func hourLabel(for date: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        return String(format: "%02d:00", hour)
    }

    /// Only clips captured within the current clock hour are shown here.
    private var currentHourClips: [PlaybackClip] {
        let calendar = Calendar.current
        let now = Date()
        return viewModel.hourlyGroups
            .flatMap(\.clips)
            .filter { calendar.isDate($0.createdAt, equalTo: now, toGranularity: .hour) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.canvas.ignoresSafeArea()
                VStack(spacing: 0) {
                    navBar
                    content
                }
            }
            // Rotating the phone jumps straight into the camera.
            .onChange(of: geo.size.width > geo.size.height) { _, isLandscape in
                showingCamera = isLandscape
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.loadPlayback(roomID: room.id) }
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
            RoomSettingsSheet(room: effectiveRoom, viewModel: viewModel) { updated in
                updatedRoom = updated
            }
            .environment(appState)
        }
        .sheet(item: $playingClip) { clip in
            ClipPlayerSheet(clip: clip)
        }
    }

    // MARK: - Nav bar

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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Content

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
                    ForEach(effectiveRoom.members) { member in
                        memberCard(member)
                    }
                    if effectiveRoom.members.isEmpty {
                        Text("No members yet — share invite code \(effectiveRoom.inviteCode).")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 8)
                    }
                    currentHourTimeline
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
    }

    /// One member's card: their current-hour clips playing as a looping video
    /// background (paged with left/right taps), the hour label, a 3-dot menu
    /// with save/delete, and — on the signed-in member's card — the CTA.
    private func memberCard(_ member: RoomMemberDTO) -> some View {
        let isMe = member.displayName == appState.currentUser?.displayName
        let clips = currentHourClips.filter { $0.authorName == member.displayName }
        let index = min(clipPageIndex[member.id] ?? 0, max(clips.count - 1, 0))
        let current = clips.indices.contains(index) ? clips[index] : nil

        return ZStack {
            if let current {
                LoopingVideoPlayer(url: current.playbackURL)
            } else {
                Theme.card
            }

            // Dim scrim so overlays stay readable over video.
            LinearGradient(
                colors: [.black.opacity(0.15), .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Paging zones: tap the left/right edges to move between clips.
            HStack(spacing: 0) {
                pageZone(alignment: .leading, visible: index + 1 < clips.count) {
                    clipPageIndex[member.id] = index + 1
                }
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture {
                        if let current { playingClip = current }
                    }
                pageZone(alignment: .trailing, visible: index > 0) {
                    clipPageIndex[member.id] = index - 1
                }
            }

            VStack {
                Spacer()
                Text(Self.hourLabel())
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
                    Button {
                        showingCamera = true
                    } label: {
                        Text("tap to capture")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.canvas)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Theme.accent))
                    }
                    .accessibilityLabel("Tap to capture a clip for this room")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                }
            }
            .padding(16)
        }
        .frame(height: isMe ? 210 : 170)
        .clipShape(.rect(cornerRadius: 24))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(member.displayName)'s card\(current == nil ? ", no clips this hour" : ", clip \(index + 1) of \(clips.count)")")
    }

    /// An invisible tap zone with an optional chevron hint.
    private func pageZone(
        alignment: Alignment,
        visible: Bool,
        action: @escaping () -> Void
    ) -> some View {
        ZStack {
            Color.clear.contentShape(.rect)
            if visible {
                Image(systemName: alignment == .leading ? "chevron.left" : "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(6)
                    .background(.black.opacity(0.35), in: .circle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                    .padding(.horizontal, 8)
            }
        }
        .frame(width: 56)
        .contentShape(.rect)
        .onTapGesture { action() }
        .accessibilityHidden(true)
    }

    /// The 3-dot menu: save the shown clip to Photos, or delete one's own.
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

    /// Downloads the remote clip and saves it to the photo library.
    private func saveClip(_ clip: PlaybackClip) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: clip.playbackURL)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("snaplog-save-\(UUID().uuidString).mp4")
            try data.write(to: tempURL)
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else { return }
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset()
                    .addResource(with: .video, fileURL: tempURL, options: nil)
            }
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            viewModel.report("Couldn't save the clip.")
        }
    }

    /// Deletes the shown clip (own clips only) and refreshes.
    private func deleteClip(_ clip: PlaybackClip) async {
        if await viewModel.deleteClip(roomID: room.id, s3Key: clip.s3Key) {
            await viewModel.loadPlayback(roomID: room.id)
        }
    }

    // MARK: - Current-hour timeline

    @ViewBuilder
    private var currentHourTimeline: some View {
        if !currentHourClips.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(currentHourClips) { clip in
                    clipRow(clip)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: 24))
        }
    }

    private func clipRow(_ clip: PlaybackClip) -> some View {
        Button {
            playingClip = clip
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.authorName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                    Text(clip.createdAt.formatted(date: .omitted, time: .standard))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Text(String(format: "%.1fs", clip.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.muted)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play \(clip.authorName)'s clip from \(clip.createdAt.formatted(date: .omitted, time: .standard))")
    }
}

/// Full-screen player for a single clip, streaming from its pre-signed URL.
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
