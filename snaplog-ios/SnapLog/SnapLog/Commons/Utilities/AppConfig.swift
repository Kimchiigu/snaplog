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
    static var apiBaseURL: URL {
        #if DEBUG
        URL(string: "http://localhost:8080") ?? fallbackURL
        #else
        URL(string: "https://api.snaplog.app") ?? fallbackURL
        #endif
    }

    static var presenceWebSocketURL: URL {
        #if DEBUG
        URL(string: "ws://localhost:8080/presence") ?? fallbackURL
        #else
        URL(string: "wss://api.snaplog.app/presence") ?? fallbackURL
        #endif
    }

    /// Mixpanel project token, injected at build time in release.
    static var mixpanelToken: String { "" }
}
