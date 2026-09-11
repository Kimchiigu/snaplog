import Foundation

enum AppDependencies {

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

@MainActor
enum AuthEventBus {
    static var onUnauthorized: (() -> Void)?

    nonisolated static func unauthorized() {
        Task { @MainActor in onUnauthorized?() }
    }
}
