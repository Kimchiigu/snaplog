//
//  AppDependencies.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import Foundation

/// Shared instances used across features.
///
/// Kept as a namespace rather than singletons-in-disguise so tests can
/// construct ViewModels with their own mocks instead.
enum AppDependencies {

    /// The app-wide REST client. Uses a token provider wired to the
    /// keychain so it stays valid across sign-in/sign-out.
    static let apiClient: APIClient = {
        let keychain = KeychainStore()
        return APIClient(
            tokenProvider: { keychain.readToken() },
            onUnauthorized: { AuthEventBus.unauthorized() }
        )
    }()

    static let analytics: AnalyticsService = AnalyticsManager()

    static let presenceSocket = WebSocketManager()
}

/// Bridges background-thread 401s from `APIClient` to main-actor UI state.
@MainActor
enum AuthEventBus {
    static var onUnauthorized: (() -> Void)?

    nonisolated static func unauthorized() {
        Task { @MainActor in onUnauthorized?() }
    }
}
