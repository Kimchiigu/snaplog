//
//  RoomDetailView.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 09/09/26.
//

import AVKit
import SwiftUI

/// A room's detail: custom nav bar, stacked member cards with the current
/// hour's timestamp, a tap-to-capture CTA, and the hourly clip timeline.
struct RoomDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let room: Room

    @State private var viewModel = RoomDetailViewModel()
    @State private var showingCamera = false
    @State private var playingClip: PlaybackClip?

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
        .task { await viewModel.loadPlayback(roomID: room.id) }
        .refreshable { await viewModel.loadPlayback(roomID: room.id) }
        .fullScreenCover(isPresented: $showingCamera, onDismiss: {
            Task { await viewModel.loadPlayback(roomID: room.id) }
        }) {
            CameraView(room: room)
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
                    .background(Circle().fill(Theme.card))
            }
            .accessibilityLabel("Back")

            Button {} label: {
                Image(systemName: "calendar")
                    .font(.body)
                    .foregroundStyle(Theme.muted)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.card))
            }
            .accessibilityLabel("Pick a day")

            Spacer()

            roomSelector

            Spacer()

            Button {} label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.body)
                    .foregroundStyle(Theme.muted)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.card))
            }
            .accessibilityLabel("Share room")

            Button {} label: {
                Image(systemName: "ellipsis.bubble")
                    .font(.body)
                    .foregroundStyle(Theme.muted)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.card))
            }
            .accessibilityLabel("Room chat")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var roomSelector: some View {
        HStack(spacing: 8) {
            Text(room.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.muted)
            Circle()
                .fill(Theme.accent)
                .frame(width: 5, height: 5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Theme.card))
        .accessibilityLabel("Room \(room.displayName)")
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
                    ForEach(room.members) { member in
                        memberCard(member)
                    }
                    if !viewModel.hourlyGroups.isEmpty {
                        hourSections
                    } else if room.members.isEmpty {
                        Text("No members yet — share invite code \(room.inviteCode).")
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

    /// One member's stacked card: avatar, hour timestamp overlay, smiley, and
    /// the tap-to-capture CTA on the signed-in member's card.
    private func memberCard(_ member: RoomMemberDTO) -> some View {
        let isMe = member.displayName == appState.currentUser?.displayName
        let latest = viewModel.latestClip(by: member.displayName)

        return ZStack {
            Theme.card

            VStack {
                Spacer()
                LiveTimestamp()
                    .accessibilityLabel("Captured hour")
                Spacer()
            }

            HStack(alignment: .top) {
                SmileyIcon(
                    color: smileyColor(for: member),
                    mood: isMe ? .plain : .upsideDown,
                    size: 30
                )
                Spacer()
            }

            VStack {
                Spacer()
                HStack {
                    Text(member.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    if isMe {
                        Menu {
                            Button("Play latest clip") {
                                if let latest { playingClip = latest }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.body)
                                .foregroundStyle(Theme.muted)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Theme.cardElevated))
                        }
                        .accessibilityLabel("More options")
                    }
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
        .contentShape(.rect)
        .onTapGesture {
            if let latest { playingClip = latest }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(member.displayName)'s card\(latest == nil ? ", no clips yet" : "")")
    }

    private func smileyColor(for member: RoomMemberDTO) -> Color {
        let palette: [Color] = [Theme.pink, Theme.blue, Theme.accent]
        let index = abs(member.displayName.hashValue) % palette.count
        return palette[index]
    }

    // MARK: - Timeline

    private var hourSections: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("today")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.muted)
                .textCase(.uppercase)
                .padding(.top, 8)
            ForEach(viewModel.hourlyGroups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.hourLabel)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                    ForEach(group.clips) { clip in
                        clipRow(clip)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: .rect(cornerRadius: 24))
            }
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
