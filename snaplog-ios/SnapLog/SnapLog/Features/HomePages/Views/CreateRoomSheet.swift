
import SwiftUI

struct CreateRoomSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: RoomListViewModel

    @State private var roomName = ""
    @State private var roomType: RoomType = .log
    @State private var maxMembers = 4
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Room Details") {
                    TextField("Room name", text: $roomName)
                    Picker("Layout", selection: $roomType) {
                        Text("Log").tag(RoomType.log)
                        Text("Stack").tag(RoomType.stack)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Members") {
                    Picker("Max Members", selection: $maxMembers) {
                        ForEach(RoomType.allowedMaxMembers, id: \.self) { count in
                            Text(count == 20 ? "20 (Class)" : "\(count)").tag(count)
                        }
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
                    if let message = viewModel.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
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
        if await viewModel.createRoom(named: name, roomType: roomType, maxMembers: maxMembers) {
            dismiss()
        }
    }
}

#Preview {
    CreateRoomSheet(
        viewModel: RoomListViewModel(apiClient: AppDependencies.apiClient)
    )
}
