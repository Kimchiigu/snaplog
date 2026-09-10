
import SwiftUI

struct JoinRoomSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: RoomListViewModel

    @State private var inviteCode = ""
    @State private var isSubmitting = false

    private var trimmedCode: String {
        inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Invite code", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.title3.monospaced())
                        .onChange(of: inviteCode) { _, newValue in
                            if newValue.count > 6 {
                                inviteCode = String(newValue.prefix(6))
                            }
                        }
                } header: {
                    Text("Invite Code")
                } footer: {
                    Text("Ask the room owner for their 6-character code.")
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
                    if let message = viewModel.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
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
        guard trimmedCode.count == 6 else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        if await viewModel.joinRoom(inviteCode: trimmedCode) {
            dismiss()
        }
    }
}

#Preview {
    JoinRoomSheet(
        viewModel: RoomListViewModel(apiClient: AppDependencies.apiClient)
    )
}
