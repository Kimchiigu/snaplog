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

    /// Exchanges an Apple identity token for a SnapLog JWT via `POST /auth/apple`.
    func signIn(appleIdentityToken: String, fullName: String?) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response: AuthResponse = try await apiClient.request(
                path: "/auth/apple",
                method: .post,
                body: AppleAuthRequest(identityToken: appleIdentityToken, fullName: fullName)
            )
            analytics.track(event: "auth_signed_in", properties: ["user_id": response.userID])
            appState.signIn(token: response.token)
        } catch {
            errorMessage = Self.describe(error)
        }
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
            return "Sign in failed. Please try again."
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
