
import SwiftUI

@main
struct SnapLogApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .task {
                    PushService.shared.configure(apiClient: AppDependencies.apiClient)
                }
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.flow {
        case .unauthenticated:
            LoginView()
                .task { PushService.shared.cancelHourlyLogReminder() }
        case .authenticated:
            RoomListView()
                .task {
                    AuthEventBus.onUnauthorized = { appState.signOut() }
                    await appState.restoreCurrentUserIfNeeded()
                    await appState.validateSession()
                    await PushService.shared.requestAndRegister()
                }
        }
    }
}

#Preview("Unauthenticated") {
    RootView()
        .environment(AppState())
}
