//
//  RoomCard.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import SwiftUI

/// Card summarizing a room shown in the room feed.
struct RoomCard: View {
    let room: Room
    var showsRecordingIndicator: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(room.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if showsRecordingIndicator {
                    recordingDot
                }
            }
            Label(
                title: { Text("\(room.memberCount) member\(room.memberCount == 1 ? "" : "s")") },
                icon: { Image(systemName: "person.2") }
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var recordingDot: some View {
        Circle()
            .fill(.green)
            .frame(width: 12, height: 12)
            .accessibilityHidden(true)
    }

    private var accessibilitySummary: String {
        var summary = room.name
        if showsRecordingIndicator {
            summary += ", a member is recording now"
        }
        return summary
    }
}

#Preview {
    RoomCard(
        room: Room(id: "1", name: "Weekend Trip", roomType: .grid, memberCount: 4, joinCode: "AB12"),
        showsRecordingIndicator: true
    )
    .padding()
}
