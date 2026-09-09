//
//  LoginView.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import SwiftUI
import AuthenticationServices

/// Login screen: Sign in with Apple as the primary action, plus email
/// sign-in / registration.
struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: AuthViewModel?

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
        ScrollView {
            VStack(spacing: 20) {
                header
                if let viewModel {
                    emailForm(viewModel: viewModel)
                    divider
                    appleButton(viewModel: viewModel)
                    #if DEBUG
                    devSignInButton(viewModel: viewModel)
                    #endif
                }
            }
            .padding(24)
        }
        .task {
            if viewModel == nil {
                viewModel = AuthViewModel(appState: appState, apiClient: AppDependencies.apiClient)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.badge.ellipsis")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("SnapLog")
                .font(.largeTitle.bold())
            Text("Short video logs, shared with your rooms.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 48)
        .padding(.bottom, 12)
    }

    // MARK: - Email form

    @ViewBuilder
    private func emailForm(viewModel: AuthViewModel) -> some View {
        VStack(spacing: 12) {
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
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Error: \(errorMessage)")
            }

            PrimaryButton(
                title: emailMode == .signIn ? "Sign In with Email" : "Create Account",
                systemImage: "envelope",
                isLoading: viewModel.isLoading
            ) {
                Task { await submitEmail(viewModel: viewModel) }
            }
        }
        .submitLabel(.go)
        .onSubmit { Task { await submitEmail(viewModel: viewModel) } }
    }

    private func submitEmail(viewModel: AuthViewModel) async {
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

    private var divider: some View {
        HStack {
            Rectangle().fill(.quaternary).frame(height: 1)
            Text("or").font(.caption).foregroundStyle(.secondary)
            Rectangle().fill(.quaternary).frame(height: 1)
        }
    }

    // MARK: - Apple

    @ViewBuilder
    private func appleButton(viewModel: AuthViewModel) -> some View {
        SignInWithAppleButton(.signIn) { _ in
            // Default scope is sufficient; no extra fields requested.
        } onCompletion: { result in
            handle(result, viewModel: viewModel)
        }
        .frame(height: 54) // The control stretches without a fixed height.
        .clipShape(.rect(cornerRadius: 12))
    }

    #if DEBUG
    /// Development shortcut backed by `POST /api/auth/dev` — skips verification.
    @ViewBuilder
    private func devSignInButton(viewModel: AuthViewModel) -> some View {
        Button {
            Task { await viewModel.devSignIn(displayName: "Simulator Tester") }
        } label: {
            Label("Dev Sign In (Simulator)", systemImage: "wrench.and.screwdriver")
                .font(.footnote)
        }
        .padding(.top, 8)
    }
    #endif

    private func handle(_ result: Result<ASAuthorization, Error>, viewModel: AuthViewModel) {
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

#Preview {
    LoginView()
        .environment(AppState())
}
