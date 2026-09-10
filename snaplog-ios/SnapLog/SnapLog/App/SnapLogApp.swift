//
//  SnapLogApp.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import SwiftUI

@main
struct SnapLogApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }
    }
}

/// Switches between the login flow and the authenticated experience.
struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.flow {
        case .unauthenticated:
            LoginView()
        case .authenticated:
            RoomListView()
                // Restore the profile of a Keychain-restored session, then
                // drop it if the Apple credential behind it was revoked.
                .task {
                    // Any later 401 (expired/revoked JWT) also ends the session.
                    AuthEventBus.onUnauthorized = { appState.signOut() }
                    await appState.restoreCurrentUserIfNeeded()
                    await appState.validateSession()
                }
        }
    }
}

#Preview("Unauthenticated") {
    RootView()
        .environment(AppState())
}
