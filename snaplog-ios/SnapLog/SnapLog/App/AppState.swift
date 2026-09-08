//
//  AppState.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import Foundation
import Observation

/// The top-level navigation state of the application.
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

    private let keychainStore: KeychainStoring

    init(keychainStore: KeychainStoring = KeychainStore()) {
        self.keychainStore = keychainStore
        // Restore a previous session, if any.
        if let token = keychainStore.readToken() {
            authToken = token
            flow = .authenticated
        }
    }

    func signIn(token: String) {
        keychainStore.saveToken(token)
        authToken = token
        flow = .authenticated
    }

    func signOut() {
        keychainStore.deleteToken()
        authToken = nil
        flow = .unauthenticated
    }
}
