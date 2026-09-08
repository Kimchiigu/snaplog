//
//  CreateRoomSheet.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import SwiftUI

/// Sheet for creating a new room via `POST /rooms`.
struct CreateRoomSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: RoomListViewModel

    @State private var roomName = ""
    @State private var roomType: RoomType = .grid
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Room Details") {
                    TextField("Room name", text: $roomName)
                    Picker("Layout", selection: $roomType) {
                        Text("Grid (2x2)").tag(RoomType.grid)
                        Text("Stack").tag(RoomType.stack)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    PrimaryButton(
                        title: "Create Room",
                        systemImage: "plus",
                        isLoading: isSubmitting
                    ) {
                        Task { await submit() }
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("New Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func submit() async {
        let name = roomName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        if await viewModel.createRoom(named: name, roomType: roomType) {
            dismiss()
        }
    }
}

#Preview {
    CreateRoomSheet(
        viewModel: RoomListViewModel(apiClient: AppDependencies.apiClient)
    )
}
