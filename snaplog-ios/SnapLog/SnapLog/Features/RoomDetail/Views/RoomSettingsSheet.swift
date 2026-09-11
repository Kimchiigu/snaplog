import SwiftUI

struct RoomSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let room: Room
    let viewModel: RoomDetailViewModel
    let isOwner: Bool
    let onSaved: (Room) -> Void
    let onLeft: () -> Void

    @State private var name = ""
    @State private var maxMembers = 4
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var copiedCode = false
    @State private var confirmLeave = false
    @State private var isLeaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Room") {
                    TextField("Room name", text: $name)
                    Picker("Room size", selection: $maxMembers) {
                        ForEach(RoomType.allowedMaxMembers, id: \.self) { size in
                            Text("\(size) members").tag(size)
                        }
                    }
                }

                Section {
                    HStack {
                        Text(room.inviteCode)
                            .font(.title3.monospaced().weight(.bold))
                        Spacer()
                        Button {
                            UIPasteboard.general.string = room.inviteCode
                            copiedCode = true
                        } label: {
                            Label(copiedCode ? "Copied" : "Copy", systemImage: copiedCode ? "checkmark" : "doc.on.doc")
                                .font(.footnote)
                        }
                    }
                } header: {
                    Text("Invite Code")
                } footer: {
                    Text("Share this code so friends can join the room.")
                }

                Section("Members (\(room.members.count)/\(maxMembers))") {
                    ForEach(room.members) { member in
                        HStack {
                            Text(member.displayName)
                            Spacer()
                            Text(member.role)
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        confirmLeave = true
                    } label: {
                        if isLeaving {
                            ProgressView()
                        } else {
                            Label(
                                isOwner ? "Delete Room" : "Leave Room",
                                systemImage: isOwner ? "trash" : "rectangle.portrait.and.arrow.right"
                            )
                        }
                    }
                    .disabled(isLeaving)
                } footer: {
                    Text(isOwner
                         ? "Deleting the room removes it — and every clip in it — for all members."
                         : "Leaving keeps the room for the other members; you can rejoin with the invite code.")
                }
            }
            .confirmationDialog(
                isOwner ? "Delete this room?" : "Leave this room?",
                isPresented: $confirmLeave,
                titleVisibility: .visible
            ) {
                Button(isOwner ? "Delete Room" : "Leave Room", role: .destructive) {
                    Task { await leaveOrDelete() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(isOwner
                     ? "All members are removed and every clip in the room is deleted. This can't be undone."
                     : "You'll stop seeing this room in your list.")
            }
            .navigationTitle("Room Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await save() }
                        }
                    }
                }
            }
            .alert("Couldn't save", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            name = room.displayName
            maxMembers = room.maxMembers
        }
    }

    private func leaveOrDelete() async {
        isLeaving = true
        defer { isLeaving = false }
        let succeeded = isOwner
            ? await viewModel.deleteRoom(roomID: room.id)
            : await viewModel.leaveRoom(roomID: room.id)
        if succeeded {
            onLeft()
            dismiss()
        } else {
            saveError = viewModel.errorMessage ?? "Please try again."
        }
    }

    private func save() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            saveError = "The room needs a name."
            return
        }
        isSaving = true
        defer { isSaving = false }
        if let updated = await viewModel.updateRoom(
            roomID: room.id,
            name: trimmed == room.displayName ? nil : trimmed,
            maxMembers: maxMembers == room.maxMembers ? nil : maxMembers
        ) {
            onSaved(updated)
            dismiss()
        } else {
            saveError = viewModel.errorMessage ?? "Please try again."
        }
    }
}

#Preview {
    RoomSettingsSheet(
        room: Room(
            id: UUID(),
            name: "balls",
            roomType: .log,
            maxMembers: 4,
            inviteCode: "AB12CD",
            createdAt: nil,
            members: [],
            timeline: []
        ),
        viewModel: RoomDetailViewModel(),
        isOwner: true,
        onSaved: { _ in },
        onLeft: {}
    )
}
