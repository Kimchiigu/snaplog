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

    // MARK: - Apple credential tracking

    /// Builds a JWT-shaped string whose payload encodes `claims`.
    private func fakeJWT(_ claims: [String: String]) -> String {
        let encoder = JSONEncoder()
        let segment = { (dict: [String: String]) -> String in
            let data = (try? encoder.encode(dict)) ?? Data()
            return data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return segment(["alg": "HS256"]) + "." + segment(claims) + ".signature"
    }

    @Test func appleUserIdIsParsedFromSessionJWT() {
        let jwt = fakeJWT(["appleUserId": "001234.abcdef.1234", "sub": "user-uuid"])
        #expect(AppleSignInService.appleUserId(from: jwt) == "001234.abcdef.1234")
        #expect(AppleSignInService.appleUserId(from: "not-a-jwt") == nil)
    }

    @Test func onlyRealAppleAccountsAreTracked() {
        #expect(AppleSignInService.isAppleAccount("001234.abcdef.1234"))
        #expect(!AppleSignInService.isAppleAccount("email:tester@snaplog.dev"))
        #expect(!AppleSignInService.isAppleAccount("dev-tester"))
        #expect(!AppleSignInService.isAppleAccount(nil))
        #expect(!AppleSignInService.isAppleAccount(""))
    }

    @Test func signInPersistsAppleCredentialForAppleAccountsOnly() {
        // Apple sign-in: the credential id is stored for revocation checks.
        let appleKeychain = MockKeychainStore()
        let appleState = AppState(keychainStore: appleKeychain)
        appleState.signIn(token: fakeJWT(["appleUserId": "001234.abcdef"]), user: makeUser())
        #expect(appleKeychain.readAppleUserId() == "001234.abcdef")

        // Email / dev sign-ins carry no Apple credential to track.
        let emailKeychain = MockKeychainStore()
        let emailState = AppState(keychainStore: emailKeychain)
        emailState.signIn(token: fakeJWT(["appleUserId": "email:tester@snaplog.dev"]), user: makeUser())
        #expect(emailKeychain.readAppleUserId() == nil)
    }
}
