//
//  RoomCard.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import SwiftUI

/// Dark charcoal room card for the home list: group thumbnail, title, last
/// activity, unread dot, smiley badge, and a disclosure chevron.
struct RoomCard: View {
    let room: Room
    var showsRecordingIndicator: Bool

    private var isUnread: Bool { showsRecordingIndicator || room.hasFreshActivity }

    var body: some View {
        HStack(spacing: 14) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(room.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if isUnread { unreadDot }
                }
                Text(room.lastActivityLabel ?? "no logs yet")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }

            Spacer()

            SmileyIcon(color: isUnread ? Theme.accent : Theme.muted, size: 22)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    /// Stacked member smileys as the room's group thumbnail.
    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.cardElevated)
                .frame(width: 52, height: 52)
            HStack(spacing: -10) {
                let colors: [Color] = [Theme.pink, Theme.blue, Theme.accent]
                ForEach(Array(room.members.prefix(3).enumerated()), id: \.offset) { index, _ in
                    SmileyIcon(color: colors[index % colors.count], size: 18)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var unreadDot: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }

    private var accessibilitySummary: String {
        var summary = "\(room.displayName), \(room.lastActivityLabel ?? "no logs yet")"
        if isUnread { summary += ", new clip ready" }
        return summary
    }
}

#Preview {
    VStack {
        RoomCard(
            room: Room(
                id: UUID(),
                name: "Weekend Trip",
                roomType: .log,
                maxMembers: 4,
                inviteCode: "AB12CD",
                createdAt: nil,
                members: [
                    RoomMemberDTO(id: UUID(), displayName: "Chris", avatarUrl: nil, role: "owner", joinedAt: nil),
                    RoomMemberDTO(id: UUID(), displayName: "Ada", avatarUrl: nil, role: "member", joinedAt: nil),
                ],
                timeline: [TimelineEntry(s3Key: "raw/x.mp4", duration: 3.2, createdAt: Date().addingTimeInterval(-120).timeIntervalSince1970)]
            ),
            showsRecordingIndicator: false
        )
    }
    .padding()
    .background(Theme.canvas)
}
