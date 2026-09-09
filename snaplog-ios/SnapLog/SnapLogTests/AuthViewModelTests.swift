//
//  AuthViewModelTests.swift
//  SnapLogTests
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import Foundation
import Testing
@testable import SnapLog

@MainActor
struct AuthViewModelTests {

    private func makeUser() -> UserDTO {
        UserDTO(id: UUID(), email: "tester@snaplog.dev", displayName: "Tester", avatarUrl: nil)
    }

    @Test func signInSucceedsAndUpdatesAppState() async {
        let api = MockAPIClient()
        api.stub("/auth/apple", result: .success(AuthResponse(token: "jwt-123", user: makeUser())))
        let keychain = MockKeychainStore()
        let appState = AppState(keychainStore: keychain)
        let viewModel = AuthViewModel(appState: appState, apiClient: api)

        await viewModel.signIn(appleIdentityToken: "apple-token")

        #expect(appState.flow == .authenticated)
        #expect(appState.authToken == "jwt-123")
        #expect(appState.currentUser?.displayName == "Tester")
        #expect(keychain.readToken() == "jwt-123")
        #expect(viewModel.errorMessage == nil)
    }

    @Test func devSignInSucceedsInDebug() async {
        let api = MockAPIClient()
        api.stub("/auth/dev", result: .success(AuthResponse(token: "dev-jwt", user: makeUser())))
        let appState = AppState(keychainStore: MockKeychainStore())
        let viewModel = AuthViewModel(appState: appState, apiClient: api)

        await viewModel.devSignIn(displayName: "Simulator Tester")

        #expect(appState.flow == .authenticated)
        #expect(appState.authToken == "dev-jwt")
    }

    @Test func signInFailureShowsMessageAndStaysSignedOut() async {
        let api = MockAPIClient()
        api.stubFailure("/auth/apple", APIError.unauthorized)
        let appState = AppState(keychainStore: MockKeychainStore())
        let viewModel = AuthViewModel(appState: appState, apiClient: api)

        await viewModel.signIn(appleIdentityToken: "bad")

        #expect(appState.flow == .unauthenticated)
        #expect(viewModel.errorMessage != nil)
    }

    @Test func restoredSessionBecomesAuthenticated() {
        let keychain = MockKeychainStore()
        keychain.saveToken("stored-token")
        let appState = AppState(keychainStore: keychain)

        #expect(appState.flow == .authenticated)
        #expect(appState.authToken == "stored-token")
    }

    @Test func signOutClearsEverything() {
        let keychain = MockKeychainStore()
        keychain.saveToken("stored-token")
        let appState = AppState(keychainStore: keychain)

        appState.signOut()

        #expect(appState.flow == .unauthenticated)
        #expect(appState.authToken == nil)
        #expect(appState.currentUser == nil)
        #expect(keychain.readToken() == nil)
    }
}
