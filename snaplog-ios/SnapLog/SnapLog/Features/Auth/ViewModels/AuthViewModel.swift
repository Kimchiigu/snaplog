//
//  AuthViewModel.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import Foundation
import Observation

/// Drives the Sign in with Apple flow and hands the resulting JWT to ``AppState``.
@MainActor
@Observable
final class AuthViewModel {

    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let apiClient: APIClientProtocol
    private let analytics: AnalyticsService
    private let appState: AppState

    init(
        appState: AppState,
        apiClient: APIClientProtocol,
        analytics: AnalyticsService = NoopAnalyticsService()
    ) {
        self.appState = appState
        self.apiClient = apiClient
        self.analytics = analytics
    }

    /// Exchanges an Apple identity token for a SnapLog JWT via `POST /api/auth/apple`.
    func signIn(appleIdentityToken: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response: AuthResponse = try await apiClient.request(
                path: "/auth/apple",
                method: .post,
                body: AppleAuthRequest(identityToken: appleIdentityToken)
            )
            finishSignIn(response)
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// Development-only shortcut backed by `POST /api/auth/dev`.
    func devSignIn(displayName: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response: AuthResponse = try await apiClient.request(
                path: "/auth/dev",
                method: .post,
                body: DevAuthRequest(displayName: displayName)
            )
            finishSignIn(response)
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// Creates an email/password account via `POST /api/auth/register`.
    func register(email: String, password: String, displayName: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response: AuthResponse = try await apiClient.request(
                path: "/auth/register",
                method: .post,
                body: RegisterRequest(email: email, password: password, displayName: displayName)
            )
            finishSignIn(response)
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// Signs in with email/password via `POST /api/auth/login`.
    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response: AuthResponse = try await apiClient.request(
                path: "/auth/login",
                method: .post,
                body: LoginRequest(email: email, password: password)
            )
            finishSignIn(response)
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    private func finishSignIn(_ response: AuthResponse) {
        analytics.track(event: "auth_signed_in", properties: [:])
        appState.signIn(token: response.token, user: response.user)
    }

    /// Surfaces a client-side (e.g. cancelled Sign in with Apple) error to the UI.
    func report(_ error: Error) {
        errorMessage = Self.describe(error)
    }

    static func describe(_ error: Error) -> String {
        guard let apiError = error as? APIError else {
            return "Something went wrong. Please try again."
        }
        switch apiError {
        case .unauthorized:
            return "Invalid email or password."
        case .httpStatus(409):
            return "An account with that email already exists."
        case .decoding:
            return "The server sent an unexpected response."
        case .network:
            return "Can't reach the server. Check your connection."
        default:
            return "Something went wrong. Please try again."
        }
    }
}

/// Analytics no-op used in previews and tests.
struct NoopAnalyticsService: AnalyticsService {
    func track(event: String, properties: [String: String]) {}
}
