
import Foundation
import Observation

@MainActor
@Observable
final class AppState {

    enum Flow {
        case unauthenticated
        case authenticated
    }

    private(set) var flow: Flow = .unauthenticated

    private(set) var authToken: String?

    private(set) var currentUser: UserDTO?

    private let keychainStore: KeychainStoring
    private let appleSignIn: AppleSignInService

    init(
        keychainStore: KeychainStoring = KeychainStore(),
        appleSignIn: AppleSignInService = AppleSignInService()
    ) {
        self.keychainStore = keychainStore
        self.appleSignIn = appleSignIn
        if let token = keychainStore.readToken() {
            authToken = token
            flow = .authenticated
        }
    }

    func signIn(token: String, user: UserDTO) {
        keychainStore.saveToken(token)
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

    func restoreCurrentUserIfNeeded() async {
        guard authToken != nil, currentUser == nil else { return }
        do {
            currentUser = try await AppDependencies.apiClient.request(path: "/users/me", method: .get)
        } catch {
            if let apiError = error as? APIError,
               case .unauthorized = apiError {
                signOut()
            }
        }
    }

    func validateSession() async {
        guard flow == .authenticated, let appleUserId = keychainStore.readAppleUserId() else { return }
        let valid = await appleSignIn.isSessionValid(for: appleUserId)
        if !valid {
            signOut()
        }
    }
}
