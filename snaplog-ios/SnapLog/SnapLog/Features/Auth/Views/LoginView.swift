//
//  LoginView.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import SwiftUI
import AuthenticationServices

/// Primary login screen offering Sign in with Apple.
struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: AuthViewModel?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "video.badge.ellipsis")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("SnapLog")
                .font(.largeTitle.bold())
            Text("Short video logs, shared with your rooms.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            if let viewModel {
                SignInWithAppleButton(.signIn) { _ in
                    // Default scope is sufficient; no extra fields requested.
                } onCompletion: { result in
                    handle(result, viewModel: viewModel)
                }
            } else {
                ContentUnavailableView("Loading…", systemImage: "hourglass")
            }
            if let viewModel, let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Error: \(errorMessage)")
            }
        }
        .padding(24)
        .task {
            if viewModel == nil {
                viewModel = AuthViewModel(appState: appState, apiClient: AppDependencies.apiClient)
            }
        }
    }

    private func handle(_ result: Result<ASAuthorization, Error>, viewModel: AuthViewModel) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else { return }
            let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            let name = fullName.isEmpty ? nil : fullName
            Task { await viewModel.signIn(appleIdentityToken: token, fullName: name) }
        case .failure(let error):
            Task { await viewModel.report(error) }
        }
    }
}

#Preview {
    LoginView()
        .environment(AppState())
}
