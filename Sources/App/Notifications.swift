// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 WebKroo

import AppKit
import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    var openCSV: (() -> Void)?
    var report: ((String) -> Void)?
    func configure() {
        let center = UNUserNotificationCenter.current(); center.delegate = self
        let dismiss = UNNotificationAction(identifier: "DISMISS", title: "Dismiss", options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: "SENSOR_START", actions: [dismiss], intentIdentifiers: [], options: [])])
        refreshAuthorizationStatus()
    }
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            self.refreshAuthorizationStatus(requestError: error?.localizedDescription)
        }
    }
    func refreshAuthorizationStatus(requestError: String? = nil) {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let message: String
            switch settings.authorizationStatus {
            case .authorized:
                message = "Notifications are allowed."
            case .denied:
                message = "Notifications are off. Enable Privacy Watch in System Settings → Notifications."
            case .notDetermined:
                message = "Allow notifications to receive microphone and camera alerts."
            case .provisional:
                message = "Notifications are delivered quietly. Enable alerts in System Settings → Notifications."
            @unknown default:
                message = "Check notification permissions in System Settings → Notifications."
            }
            DispatchQueue.main.async {
                self?.report?(requestError.map { "\(message) \($0)" } ?? message)
            }
        }
    }
    func send(_ event: SensorEvent) {
        let content = UNMutableNotificationContent()
        content.title = "\(event.sensor.title) in use"
        content.subtitle = NotificationTime.display(event.timestamp)
        content.body = "\(event.appName) • \(event.sensor.title)\n\(NotificationTime.display(event.timestamp))" + (event.observation == "first-observed" ? "\nFirst observed after logging began." : "")
        content.categoryIdentifier = "SENSOR_START"; content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: event.id.uuidString, content: content, trigger: nil)) { error in
            if let error { DispatchQueue.main.async { self.report?(error.localizedDescription) } }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) { handler([.banner, .list, .sound]) }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler handler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier { DispatchQueue.main.async { self.openCSV?() } }
        if response.actionIdentifier == "DISMISS" { center.removeDeliveredNotifications(withIdentifiers: [response.notification.request.identifier]) }
        handler()
    }
}
