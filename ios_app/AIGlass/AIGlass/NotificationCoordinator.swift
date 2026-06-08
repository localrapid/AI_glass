//
//  NotificationCoordinator.swift
//  AIGlass
//
//  Makes the companion's notifications conversational: each ping carries a
//  "返信" text field, so the user can reply right from the notification
//  ("仕事中だよ〜"). The reply is saved as a learnable memo, the companion
//  generates a curious follow-up on-device, and that follow-up is delivered as
//  the next ping — so the chat continues through notifications. Tapping a ping
//  opens the 相棒 tab.
//

import Foundation
import UserNotifications
import SwiftData

@MainActor
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()
    static let categoryID = "COMPANION_PING"
    static let replyAction = "REPLY"

    private var context: ModelContext?

    /// Call once at launch: store the model context, become the UN delegate,
    /// and register the repliable notification category.
    func configure(context: ModelContext) {
        self.context = context
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let reply = UNTextInputNotificationAction(
            identifier: Self.replyAction,
            title: "返信",
            options: [],
            textInputButtonTitle: "送信",
            textInputPlaceholder: "メッセージを入力")
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [reply],
            intentIdentifiers: [],
            options: [])
        center.setNotificationCategories([category])
    }

    // Show companion pings even while the app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let ping = response.notification.request.content.body
        if let textResponse = response as? UNTextInputNotificationResponse {
            await handleReply(ping: ping, reply: textResponse.userText)
        } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            await MainActor.run { AppRouter.shared.selectedTab = 1 }   // open 相棒
        }
    }

    private func handleReply(ping: String, reply: String) async {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Remember what the user told us (joins the lifelog corpus → learning).
        context?.insert(MemoRecord(text: text))

        let recent = recentContext()
        let followUp = (try? await CompanionBrain.followUp(ping: ping, reply: text, context: recent))
            ?? "なるほど〜！それで、どんな感じ？"

        context?.insert(ChatTurn(
            question: text, answer: followUp,
            referencedLog: "（相棒の声かけ）\(ping)", refCount: 0, source: "オンデバイス"))
        try? context?.save()

        // Deliver the follow-up as the next (repliable) ping → conversation loop.
        let content = UNMutableNotificationContent()
        content.title = "相棒"
        content.body = followUp
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        let request = UNNotificationRequest(
            identifier: "companion.followup." + UUID().uuidString,
            content: content, trigger: nil)               // deliver now
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Recent (last 24h) lifelog + memos, for grounding the follow-up.
    private func recentContext() -> String {
        guard let context else { return "" }
        let since = Date().addingTimeInterval(-24 * 3600)
        var lines: [(Date, String)] = []
        if let photos = try? context.fetch(FetchDescriptor<PhotoRecord>()) {
            for p in photos where p.receivedAt > since {
                if let c = p.caption, !c.isEmpty { lines.append((p.receivedAt, "見たもの: \(c)")) }
            }
        }
        if let transcripts = try? context.fetch(FetchDescriptor<TranscriptRecord>()) {
            for t in transcripts where t.receivedAt > since {
                if let s = t.transcript, !s.isEmpty { lines.append((t.receivedAt, "聞いたこと: \(s)")) }
            }
        }
        if let memos = try? context.fetch(FetchDescriptor<MemoRecord>()) {
            for m in memos where m.createdAt > since {
                lines.append((m.createdAt, "話したこと: \(m.text)"))
            }
        }
        return lines
            .sorted { $0.0 < $1.0 }
            .suffix(8)
            .map { "\($0.0.formatted(.dateTime.month().day().hour().minute())) \($0.1)" }
            .joined(separator: "\n")
    }
}
