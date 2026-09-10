//
//  AppDelegate.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 10/09/26.
//

import UIKit
import UserNotifications

/// Receives the APNs device token from UIKit and hands it to ``PushService``.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushService.shared.register(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("APNs registration failed: \(error.localizedDescription)")
    }
}
