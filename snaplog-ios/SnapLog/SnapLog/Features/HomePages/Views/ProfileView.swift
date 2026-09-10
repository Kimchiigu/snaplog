
import SwiftUI

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var isDeletingAccount = false
    @State private var confirmDelete = false
    @State private var deleteError: String?

    var body: some View {
        NavigationStack {
            List {
                accountSection
                dangerSection
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Delete your account?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) {
                    Task { await deleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your account, room memberships, and all your clips. This can't be undone.")
            }
        }
    }

    private var accountSection: some View {
        Section("Account") {
            LabeledContent("Name") {
                Text(appState.currentUser?.displayName ?? "—")
            }
            LabeledContent("Email") {
                Text(appState.currentUser?.email ?? "—")
                    .textSelection(.enabled)
            }
        }
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                appState.signOut()
                dismiss()
            } label: {
                Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
            }

            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Delete Account", systemImage: "trash")
            }
            .disabled(isDeletingAccount)

            if isDeletingAccount {
                HStack {
                    Spacer()
                    ProgressView("Deleting account…")
                    Spacer()
                }
            }
            if let deleteError {
                Text(deleteError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } footer: {
            Text("Deleting your account also removes you from every room and deletes every clip you've shared.")
        }
    }

    private func deleteAccount() async {
        isDeletingAccount = true
        deleteError = nil
        defer { isDeletingAccount = false }
        do {
            try await AppDependencies.apiClient.requestVoid(path: "/users/me", method: .delete, body: Optional<Int>.none)
            appState.signOut()
            dismiss()
        } catch {
            deleteError = "Couldn't delete your account. Check your connection and try again."
        }
    }
}

#Preview {
    ProfileView()
        .environment(AppState())
}
