
import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: AuthViewModel?

    @State private var showingAppleSheet = false
    @State private var showingEmailForm = false

    var body: some View {
        ZStack {
            Color(hex: 0xF8F7F2).ignoresSafeArea()
            DoodleBackground()

            VStack(spacing: 0) {
                Spacer()
                Text("SNAPLOG")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .kerning(2)
                    .foregroundStyle(.black)
                Text("new moment every hour, vlog it with your friends.")
                    .font(.subheadline)
                    .foregroundStyle(Color(hex: 0x8E8E93))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .padding(.horizontal, 32)

                Spacer()

                VStack(spacing: 12) {
                    if let viewModel {
                        actions(viewModel: viewModel)
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: 360)
                .padding(.bottom, 32)
            }
            .padding()
        }
        .sheet(isPresented: $showingAppleSheet) {
            if let viewModel {
                AppleSignInSheet(viewModel: viewModel)
                    .presentationDetents([.height(360)])
                    .presentationDragIndicator(.hidden)
            }
        }
        .sheet(isPresented: $showingEmailForm) {
            if let viewModel {
                EmailFormSheet(viewModel: viewModel)
                    .presentationDetents([.height(440)])
            }
        }
        .task {
            if viewModel == nil {
                viewModel = AuthViewModel(appState: appState, apiClient: AppDependencies.apiClient)
            }
        }
    }

    @ViewBuilder
    private func actions(viewModel: AuthViewModel) -> some View {
        pillButton(title: "Connect with Apple", icon: "apple.logo") {
            showingAppleSheet = true
        }

        Button {
            showingEmailForm = true
        } label: {
            Text("Continue with email")
                .font(.footnote)
                .underline()
                .foregroundStyle(Color(hex: 0x8E8E93))
        }
        .padding(.top, 6)
        .accessibilityLabel("Continue with email")
    }

    private func pillButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                Text(title)
                    .font(.body.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .frame(height: 56)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(.black))
        }
        .accessibilityLabel(title)
    }
}

struct AppleSignInSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: AuthViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Sign in with Apple")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(hex: 0x8E8E93))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                .accessibilityLabel("Dismiss")
            }

            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: 0x2C2C2E))
                        .frame(width: 44, height: 44)
                    SmileyIcon(color: Theme.accent, size: 22)
                }
                Text("Sign in to snaplog using your Apple Account.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            }

            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(hex: 0x2C2C2E))
                        .frame(width: 40, height: 40)
                    SmileyIcon(color: Color(hex: 0xF5C84C), size: 20)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Christopher Hardy Gunawan")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("Your account")
                        .font(.caption)
                        .foregroundStyle(Color(hex: 0x8E8E93))
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(hex: 0x8E8E93))
            }
            .padding(12)
            .background(Capsule().fill(Color(hex: 0x2C2C2E)))

            if viewModel.isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Color(hex: 0x2B62F6))
                    Text("Signing in...")
                        .font(.subheadline)
                        .foregroundStyle(Color(hex: 0x8E8E93))
                }
                .frame(maxWidth: .infinity)
            } else {
                SignInWithAppleButton(.signIn) { _ in
                } onCompletion: { result in
                    handle(result)
                }
                .frame(height: 54)
                .clipShape(.rect(cornerRadius: 27))
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color(hex: 0xFF6B4A))
            }

            Spacer()
        }
        .padding(24)
        .background(Color(hex: 0x1C1C1E))
        .preferredColorScheme(.dark)
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else { return }
            Task { await viewModel.signIn(appleIdentityToken: token) }
        case .failure(let error):
            Task { await viewModel.report(error) }
        }
    }
}

struct EmailFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: AuthViewModel

    private enum EmailMode: String, CaseIterable, Identifiable {
        case signIn = "Sign In"
        case register = "Register"
        var id: String { rawValue }
    }

    @State private var emailMode: EmailMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Continue with email")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(hex: 0x8E8E93))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                .accessibilityLabel("Dismiss")
            }

            Picker("", selection: $emailMode) {
                ForEach(EmailMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
            if emailMode == .register {
                TextField("Display Name", text: $displayName)
                    .textFieldStyle(.roundedBorder)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color(hex: 0xFF6B4A))
            }

            Button {
                Task { await submit() }
            } label: {
                HStack {
                    if viewModel.isLoading { ProgressView().tint(.white) }
                    Text(emailMode == .signIn ? "Sign In" : "Create Account")
                        .font(.body.weight(.semibold))
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .frame(height: 52)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(.black))
            }
            .disabled(viewModel.isLoading)

            Spacer()
        }
        .padding(24)
        .background(Color(hex: 0x1C1C1E))
        .preferredColorScheme(.dark)
    }

    private func submit() async {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.contains("@"), !password.isEmpty else { return }
        switch emailMode {
        case .signIn:
            await viewModel.login(email: email, password: password)
        case .register:
            let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, password.count >= 8 else { return }
            await viewModel.register(email: email, password: password, displayName: name)
        }
    }
}

#Preview {
    LoginView()
        .environment(AppState())
}
