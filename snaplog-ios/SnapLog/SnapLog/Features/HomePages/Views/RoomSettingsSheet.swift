//
//  RoomSettingsSheet.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 10/09/26.
//

import SwiftUI

/// Editable room details: name, size, member list, and the invite code
/// others can use to join.
struct RoomSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let room: Room
    let viewModel: RoomDetailViewModel
    /// Called with the refreshed room after a successful save.
    let onSaved: (Room) -> Void

    @State private var name = ""
    @State private var maxMembers = 4
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var copiedCode = false

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
        onSaved: { _ in }
    )
}
