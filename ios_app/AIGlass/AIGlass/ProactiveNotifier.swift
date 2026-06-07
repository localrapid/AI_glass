//
//  ProactiveNotifier.swift
//  AIGlass
//
//  The companion proactively checks in with casual local notifications
//  ("たわいもないこと"), grounded in recent lifelog entries. Fully on-device:
//  it generates the messages with CompanionBrain and schedules them as local
//  notifications for the coming daytime hours. Re-scheduled whenever the app
//  becomes active, so the content stays fresh and doesn't pile up.
//
//  (Local notifications only — no server push, no background entitlement. A
//  future BGAppRefreshTask could regenerate while the app is closed.)
//

import Foundation
import UserNotifications

@MainActor
enum ProactiveNotifier {
    private static let center = UNUserNotificationCenter.current()
    private static let idPrefix = "companion.proactive."
    private static let dayStart = 8     // earliest hour to ping
    private static let dayEnd = 21      // latest hour to ping

    static func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Regenerate and (re)schedule a few casual check-ins over the coming
    /// daytime hours. `recent` is recent lifelog lines (date-prefixed).
    static func reschedule(recent: [String], enabled: Bool) async {
        // Clear our previously-scheduled pings.
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard enabled, CompanionBrain.isAvailable else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        for (i, fireDate) in upcomingSlots(count: 3).enumerated() {
            let context = recent.shuffled().prefix(4).joined(separator: "\n")
            let body = (try? await CompanionBrain.remark(context: context)) ?? fallback()
            let content = UNMutableNotificationContent()
            content.title = "相棒"
            content.body = body
            content.sound = .default

            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let req = UNNotificationRequest(identifier: idPrefix + String(i), content: content, trigger: trigger)
            try? await center.add(req)
        }
    }

    /// Future fire times, spaced out and clamped to the daytime window.
    private static func upcomingSlots(count: Int) -> [Date] {
        let cal = Calendar.current
        let now = Date()
        let offsets: [TimeInterval] = [2.5 * 3600, 5 * 3600, 8 * 3600]
        var slots: [Date] = []
        for off in offsets.prefix(count) {
            var d = now.addingTimeInterval(off)
            let hour = cal.component(.hour, from: d)
            if hour < dayStart {
                d = cal.date(bySettingHour: dayStart + 1, minute: 0, second: 0, of: d) ?? d
            } else if hour >= dayEnd {
                // push to the next morning, keeping them spread out
                let next = cal.date(byAdding: .day, value: 1, to: d) ?? d
                let h = dayStart + 1 + slots.count * 3
                d = cal.date(bySettingHour: min(h, dayEnd - 1), minute: 0, second: 0, of: next) ?? next
            }
            slots.append(d)
        }
        return slots
    }

    private static func fallback() -> String {
        ["やっほー、元気にしてる？😌", "ちょっと一息つこ？", "今日はどんな感じ？",
         "水分とってる？", "おつかれさま、無理しないでね"].randomElement()!
    }
}
