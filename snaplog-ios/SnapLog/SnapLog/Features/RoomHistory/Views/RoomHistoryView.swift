import AVFoundation
import SwiftUI

struct RoomHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let room: Room

    @State private var viewModel = RoomDetailViewModel()
    @State private var reactions: [Reaction] = []
    @State private var draft = ""
    @State private var playingClip: PlaybackClip?

    struct Reaction: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let sentAt = Date()
    }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                feed
                inputBar
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.loadPlayback(roomID: room.id) }
        .refreshable { await viewModel.loadPlayback(roomID: room.id) }
        .sheet(item: $playingClip) { clip in
            ClipPlayerSheet(clip: clip)
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
            }
            .glassEffect(.regular.tint(.black.opacity(0.6)), in: .circle)
            .accessibilityLabel("Back")

            Spacer()

            Text(room.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .glassEffect(.regular.tint(.black.opacity(0.6)), in: .capsule)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                let clips = viewModel.hourlyGroups.flatMap(\.clips)
                    .sorted { $0.createdAt < $1.createdAt }

                if clips.isEmpty && reactions.isEmpty {
                    Text("no logs yet — capture the first one")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 60)
                }

                ForEach(clips) { clip in
                    snippetCard(clip)
                }

                ForEach(reactions) { reaction in
                    reactionBubble(reaction)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private func snippetCard(_ clip: PlaybackClip) -> some View {
        let isMine = clip.authorName == appState.currentUser?.displayName
        return HStack(alignment: .bottom) {
            if isMine { Spacer(minLength: 48) }
            SnippetTile(clip: clip, isMine: isMine) {
                playingClip = clip
            }
            if !isMine { Spacer(minLength: 48) }
        }
    }

    private func reactionBubble(_ reaction: Reaction) -> some View {
        HStack {
            Spacer(minLength: 60)
            Text(reaction.text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.black)
                .padding(12)
                .background(Theme.accent, in: .rect(topLeadingRadius: 16, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 4))
            .frame(maxWidth: 320, alignment: .trailing)
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation { reactions.append(Reaction(text: "WKWKWK")) }
            } label: {
                SmileyIcon(color: Theme.accent, size: 20)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Quick reaction")

            TextField("message", text: $draft)
                .font(.subheadline)
                .foregroundStyle(.white)
                .submitLabel(.send)
                .onSubmit(sendMessage)

            Button(action: sendMessage) {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Theme.canvas)
                    .frame(width: 40, height: 40)
            }
            .glassEffect(.regular.tint(Theme.accent.opacity(0.85)), in: .circle)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Send message")
        }
        .padding(8)
        .glassEffect(.regular.tint(.black.opacity(0.6)), in: .capsule)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func sendMessage() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        withAnimation { reactions.append(Reaction(text: text)) }
    }
}

struct SnippetTile: View {
    let clip: PlaybackClip
    let isMine: Bool
    var onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            ZStack {
                LoopingVideoPlayer(url: clip.playbackURL)

                Text(Self.capturedTime(clip.createdAt))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.6), radius: 3)
            }
            .frame(width: 190, height: 128)
            .clipShape(.rect(cornerRadius: 24))
            .overlay(alignment: .bottomLeading) {
                Text(clip.authorName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(clip.authorName)'s clip, \(String(format: "%.0f", clip.duration)) seconds")
    }

    private static func capturedTime(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}

#Preview {
    RoomHistoryView(
        room: Room(
            id: UUID(),
            name: "balls",
            roomType: .log,
            maxMembers: 4,
            inviteCode: "AB12CD",
            createdAt: nil,
            members: [],
            timeline: []
        )
    )
    .environment(AppState())
}
