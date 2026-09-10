//
//  PushService.swift
//  SnapLog
//
//  Created by Christopher Hardy Gunawan on 10/09/26.
//

import OSLog
import UIKit
import UserNotifications

/// Requests notification permission, registers for remote notifications, and
/// uploads the resulting APNs token to the backend (`POST /api/devices`).
@MainActor
@Observable
final class PushService: NSObject, UNUserNotificationCenterDelegate {

    static let shared = PushService()

    private nonisolated(unsafe) static let logger = Logger(subsystem: "com.christopherhygunawan.SnapLog", category: "PushService")

    private(set) var deviceToken: String?

    private var apiClient: APIClientProtocol?

    func configure(apiClient: APIClientProtocol) {
        self.apiClient = apiClient
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAndRegister() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            Self.logger.info("notification authorization granted: \(granted)")
            guard granted else {
                Self.logger.warning("notifications NOT authorized — banners will never show")
                return
            }
        } catch {
            Self.logger.error("authorization request failed: \(error.localizedDescription)")
            return
        }
        UIApplication.shared.registerForRemoteNotifications()
        scheduleHourlyLogReminder()
        showTestBanner()
    }

    func notifyNewLog(author: String, room: String) {
        Self.logger.info("posting local new-log notification: \(author) in \(room)")
        let content = UNMutableNotificationContent()
        content.title = "\(author) logged a clip"
        content.body = "Open SnapLog to watch the new clip in \(room)."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "new-log-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? UNUserNotificationCenter.current().add(request)
    }

    private func showTestBanner() {
        let content = UNMutableNotificationContent()
        content.title = "Notifications are on"
        content.body = "You'll get \"time to log\" at the top of each hour, and a banner when friends log."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let request = UNNotificationRequest(
            identifier: "push-test-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        try? UNUserNotificationCenter.current().add(request)
    }

    private static let hourlyReminderID = "hourly-log-reminder"

    private func scheduleHourlyLogReminder() {
        let content = UNMutableNotificationContent()
        content.title = "Time to log"
        content.body = "A new hour just started — capture your clip."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(minute: 0),
            repeats: true
        )
        let request = UNNotificationRequest(
            identifier: Self.hourlyReminderID,
            content: content,
            trigger: trigger
        )
        try? UNUserNotificationCenter.current().add(request)
    }

    func cancelHourlyLogReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.hourlyReminderID])
    }

    func register(deviceToken data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        guard token != deviceToken else { return }
        self.deviceToken = token
        Self.logger.info("APNs token received: \(token.prefix(12))…")
        Task.detached(priority: .utility) { [apiClient] in
            struct DeviceRegistration: Encodable {
                let token: String
                let platform: String
            }
            do {
                try await apiClient?.requestVoid(
                    path: "/devices",
                    method: .post,
                    body: DeviceRegistration(token: token, platform: "ios")
                )
                Self.logger.info("APNs token uploaded to backend")
            } catch {
                Self.logger.error("APNs token upload failed: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}
