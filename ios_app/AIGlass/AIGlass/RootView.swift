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
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \PhotoRecord.receivedAt, order: .reverse) private var photos: [PhotoRecord]
    @Query(sort: \TranscriptRecord.receivedAt, order: .reverse) private var transcripts: [TranscriptRecord]

    var body: some View {
        TabView {
            ContentView(settings: settings)
                .tabItem { Label("グラス", systemImage: "eyeglasses") }
            CompanionView(settings: settings)
                .tabItem { Label("相棒", systemImage: "bubble.left.and.bubble.right.fill") }
        }
        .onAppear { ProactiveNotifier.requestAuthorization() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                let recent = recentLines()
                let enabled = settings.proactiveEnabled
                Task { await ProactiveNotifier.reschedule(recent: recent, enabled: enabled) }
            }
        }
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
        return lines
            .sorted { $0.0 < $1.0 }
            .map { "\($0.0.formatted(.dateTime.month().day().hour().minute())) \($0.1)" }
    }
}
