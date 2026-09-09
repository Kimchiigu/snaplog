//
//  AppConfig.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import Foundation

/// Environment-dependent configuration values for the application.
enum AppConfig {

    /// Non-optional placeholder so config accessors never need force unwrapping.
    private static let fallbackURL = URL(fileURLWithPath: "/dev/null")

    /// Debug builds talk to the local backend; release builds can be pointed elsewhere.
    /// The Vapor API is grouped under `/api` (see `routes.swift`).
    static var apiBaseURL: URL {
        #if DEBUG
        URL(string: "https://congress-tavern-reshuffle.ngrok-free.dev/api") ?? fallbackURL
        #else
        URL(string: "https://api.snaplog.app/api") ?? fallbackURL
        #endif
    }

    /// The presence WebSocket lives at the app root and authenticates with a JWT query param.
    static func presenceWebSocketURL(token: String) -> URL {
        #if DEBUG
        var components = URLComponents(string: "wss://congress-tavern-reshuffle.ngrok-free.dev/presence")
        #else
        var components = URLComponents(string: "wss://api.snaplog.app/presence")
        #endif
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
        return components?.url ?? fallbackURL
    }

    /// Mixpanel project token, injected at build time in release.
    static var mixpanelToken: String { "" }
}
