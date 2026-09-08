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
        }
    }
}

#Preview("Unauthenticated") {
    RootView()
        .environment(AppState())
}
