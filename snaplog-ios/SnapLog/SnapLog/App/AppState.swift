//
//  AppState.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import Foundation
import Observation

/// The top-level navigation and session state of the application.
@MainActor
@Observable
final class AppState {

    enum Flow {
        case unauthenticated
        case authenticated
    }

    private(set) var flow: Flow = .unauthenticated

    /// The JWT used to authorize backend requests, if signed in.
    private(set) var authToken: String?

    /// Profile of the signed-in user, if signed in.
    private(set) var currentUser: UserDTO?

    private let keychainStore: KeychainStoring
    private let appleSignIn: AppleSignInService

    init(
        keychainStore: KeychainStoring = KeychainStore(),
        appleSignIn: AppleSignInService = AppleSignInService()
    ) {
        self.keychainStore = keychainStore
        self.appleSignIn = appleSignIn
        // Restore a previous session, if any.
        if let token = keychainStore.readToken() {
            authToken = token
            flow = .authenticated
        }
    }

    func signIn(token: String, user: UserDTO) {
        keychainStore.saveToken(token)
        // Track the Apple credential behind the session (nil for email / dev
        // accounts) so revocation can be detected on later launches.
        let appleUserId = AppleSignInService.appleUserId(from: token)
        keychainStore.saveAppleUserId(AppleSignInService.isAppleAccount(appleUserId) ? appleUserId : nil)
        authToken = token
        currentUser = user
        flow = .authenticated
    }

    func signOut() {
        keychainStore.deleteToken()
        keychainStore.saveAppleUserId(nil)
        authToken = nil
        currentUser = nil
        flow = .unauthenticated
    }

    /// Restores the profile of a session restored from the Keychain by
    /// fetching `GET /api/users/me`. Called once at launch; signs the stale
    /// session out if the token is no longer valid.
    func restoreCurrentUserIfNeeded() async {
        guard authToken != nil, currentUser == nil else { return }
        do {
            currentUser = try await AppDependencies.apiClient.request(path: "/users/me", method: .get)
        } catch {
            if let apiError = error as? APIError,
               case .unauthorized = apiError {
                signOut()
            }
            // Network hiccups keep the session; the profile stays nil.
        }
    }

    /// Drops the restored session when the underlying Apple credential was
    /// revoked (Settings → Apple ID → Sign-In & Security). Email / dev sessions
    /// have no credential to check and are left alone.
    func validateSession() async {
        guard flow == .authenticated, let appleUserId = keychainStore.readAppleUserId() else { return }
        let valid = await appleSignIn.isSessionValid(for: appleUserId)
        if !valid {
            signOut()
        }
    }
}
