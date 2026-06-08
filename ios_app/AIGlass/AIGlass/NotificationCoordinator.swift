//
//  NotificationCoordinator.swift
//  AIGlass
//
//  Routes a tapped companion notification into the app's chat: it hands the
//  ping text to AppRouter so the 相棒 tab can show it as an incoming message and
//  let the user reply right in the chat screen (the reply + the companion's
//  follow-up all happen in CompanionView, not in a notification popup).
//

import Foundation
import UserNotifications

@MainActor
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()
    static let categoryID = "COMPANION_PING"

    /// Call once at launch: become the UN delegate and register the category.
    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let category = UNNotificationCategory(
            identifier: Self.categoryID, actions: [], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    // Completion-handler (non-async) variants on purpose: the async variants
    // would make the system await this on the main thread while a MainActor hop
    // also waits for that thread → a launch deadlock (whole screen stays black
    // when cold-launched from a tapped notification). Here we return immediately
    // and schedule the state update without blocking.

    // Show companion pings even while the app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Tapping a ping → continue the conversation in the chat screen.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let ping = response.notification.request.content.body
        Task { @MainActor in AppRouter.shared.incomingPing = ping }
        completionHandler()
    }
}
