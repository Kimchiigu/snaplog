//
//  NotificationsListView.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 10/09/26.
//

import SwiftUI

/// The bell sheet: recent "X logged a clip" events, newest first. Tapping an
/// item jumps straight into that room.
struct NotificationsListView: View {
    @Environment(\.dismiss) private var dismiss

    let items: [RoomListViewModel.NotificationItem]
    let onOpenRoom: (UUID) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView {
                        Label("No Notifications", systemImage: "bell.slash")
                    } description: {
                        Text("When friends log clips, they'll show up here.")
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(items) { item in
                                notificationRow(item)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .background(Theme.canvas)
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func notificationRow(_ item: RoomListViewModel.NotificationItem) -> some View {
        Button {
            dismiss()
            onOpenRoom(item.roomID)
        } label: {
            HStack(spacing: 12) {
                SmileyIcon(color: Theme.accent, size: 22)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.cardElevated))

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(item.authorName) logged a clip")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(item.roomName)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Text(item.receivedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(12)
            .background(Theme.card, in: .rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.authorName) logged a clip in \(item.roomName)")
    }
}
