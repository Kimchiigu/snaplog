
import SwiftUI

struct NewLogNoticeCard: View {
    let notice: RoomListViewModel.NewLogNotice
    let onView: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SmileyIcon(color: Theme.accent, size: 24)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.cardElevated))

            VStack(alignment: .leading, spacing: 2) {
                Text("\(notice.authorName) logged a clip")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(notice.roomName)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Button(action: onView) {
                Text("View")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.canvas)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .glassEffect(.regular.tint(Theme.accent.opacity(0.85)), in: .capsule)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("View \(notice.authorName)'s new clip in \(notice.roomName)")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Dismiss notification")
        }
        .padding(12)
        .glassEffect(.regular.tint(.black.opacity(0.6)), in: .rect(cornerRadius: 24))
        .task {
            try? await Task.sleep(for: .seconds(6))
            onDismiss()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("New clip notification from \(notice.authorName) in \(notice.roomName)")
    }
}
