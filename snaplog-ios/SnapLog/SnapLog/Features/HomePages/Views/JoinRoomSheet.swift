//
//  JoinRoomSheet.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import SwiftUI

/// Sheet for joining a room with an invite code via `POST /rooms/join`.
struct JoinRoomSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: RoomListViewModel

    @State private var joinCode = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Invite Code") {
                    TextField("Room code", text: $joinCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                Section {
                    PrimaryButton(
                        title: "Join Room",
                        systemImage: "person.badge.plus",
                        isLoading: isSubmitting
                    ) {
                        Task { await submit() }
                    }
                    .listRowBackground(Color.clear)
                }
                if let message = viewModel.errorMessage {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Join Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func submit() async {
        let code = joinCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        if await viewModel.joinRoom(code: code) {
            dismiss()
        }
    }
}

#Preview {
    JoinRoomSheet(
        viewModel: RoomListViewModel(apiClient: AppDependencies.apiClient)
    )
}
