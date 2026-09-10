
import Foundation
@preconcurrency import Mixpanel

protocol AnalyticsService: Sendable {
    func track(event: String, properties: [String: String])
}

final class AnalyticsManager: AnalyticsService {

    private nonisolated(unsafe) let mixpanel: MixpanelInstance?

    init(token: String = AppConfig.mixpanelToken) {
        guard !token.isEmpty else {
            mixpanel = nil
            return
        }
        mixpanel = Mixpanel.initialize(token: token, trackAutomaticEvents: true)
    }

    func track(event: String, properties: [String: String]) {
        mixpanel?.track(event: event, properties: properties)
    }
}
