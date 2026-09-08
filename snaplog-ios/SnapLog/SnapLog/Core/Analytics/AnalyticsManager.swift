//
//  AnalyticsManager.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 07/09/26.
//

import Foundation
@preconcurrency import Mixpanel

/// Analytics facade so features log events through one type and tests can use a mock.
protocol AnalyticsService: Sendable {
    func track(event: String, properties: [String: String])
}

/// Mixpanel-backed analytics service.
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
