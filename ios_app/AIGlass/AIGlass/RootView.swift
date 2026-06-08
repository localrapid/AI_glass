//
//  RootView.swift
//  AIGlass
//
//  Top-level tabs: the glasses control/log (ContentView) and the companion.
//  Also drives the companion's proactive check-in notifications: it asks for
//  permission once and re-schedules a few casual pings (from recent lifelog)
//  each time the app becomes active.
//

import SwiftUI
import SwiftData

struct RootView: View {
    @StateObject private var settings = AppSettings()
    @ObservedObject private var router = AppRouter.shared
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \PhotoRecord.receivedAt, order: .reverse) private var photos: [PhotoRecord]
    @Query(sort: \TranscriptRecord.receivedAt, order: .reverse) private var transcripts: [TranscriptRecord]
    @Query(sort: \MemoRecord.createdAt, order: .reverse) private var memos: [MemoRecord]

    var body: some View {
        TabView(selection: $router.selectedTab) {
            ContentView(settings: settings)
                .tabItem { Label("グラス", systemImage: "eyeglasses") }
                .tag(0)
            CompanionView(settings: settings)
                .tabItem { Label("相棒", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(1)
        }
        .onAppear {
            ProactiveNotifier.requestAuthorization()
            if router.incomingPing != nil { router.selectedTab = 1 }   // launched from a ping
        }
        .onChange(of: router.incomingPing) { _, ping in
            if ping != nil { router.selectedTab = 1 }                  // tapped while running
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { scheduleProactive() }
        }
        // Re-schedule immediately when the toggles change (so test mode takes
        // effect without needing another active transition).
        .onChange(of: settings.proactiveEnabled) { _, _ in scheduleProactive() }
        .onChange(of: settings.proactiveTestMode) { _, _ in scheduleProactive() }
    }

    private func scheduleProactive() {
        let recent = recentLines()
        let enabled = settings.proactiveEnabled
        let testMode = settings.proactiveTestMode
        Task { await ProactiveNotifier.reschedule(recent: recent, enabled: enabled, testMode: testMode) }
    }

    /// Recent (last 24h) lifelog lines, date-prefixed and chronological.
    private func recentLines() -> [String] {
        let since = Date().addingTimeInterval(-24 * 3600)
        var lines: [(Date, String)] = []
        for p in photos {
            guard p.receivedAt > since, let c = p.caption, !c.isEmpty else { continue }
            lines.append((p.receivedAt, "見たもの: \(c)"))
        }
        for t in transcripts {
            guard t.receivedAt > since, let s = t.transcript, !s.isEmpty else { continue }
            lines.append((t.receivedAt, "聞いたこと: \(s)"))
        }
        for m in memos {
            guard m.createdAt > since else { continue }
            lines.append((m.createdAt, "話したこと: \(m.text)"))
        }
        return lines
            .sorted { $0.0 < $1.0 }
            .map { "\($0.0.formatted(.dateTime.month().day().hour().minute())) \($0.1)" }
    }
}
