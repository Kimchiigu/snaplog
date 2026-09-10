
import Foundation

enum AppConfig {

    private static let fallbackURL = URL(fileURLWithPath: "/dev/null")

    static var apiBaseURL: URL {
        #if DEBUG
        URL(string: "https://congress-tavern-reshuffle.ngrok-free.dev/api") ?? fallbackURL
        #else
        URL(string: "https://api.snaplog.app/api") ?? fallbackURL
        #endif
    }

    static func presenceWebSocketURL(token: String) -> URL {
        #if DEBUG
        var components = URLComponents(string: "wss://congress-tavern-reshuffle.ngrok-free.dev/presence")
        #else
        var components = URLComponents(string: "wss://api.snaplog.app/presence")
        #endif
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
        return components?.url ?? fallbackURL
    }

    static var mixpanelToken: String { "" }
}
