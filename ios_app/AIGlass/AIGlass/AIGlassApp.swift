//
//  AIGlassApp.swift
//  AIGlass
//

import SwiftUI
import SwiftData

@main
struct AIGlassApp: App {
    init() {
        // Become the notification delegate + register the category at launch.
        NotificationCoordinator.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [PhotoRecord.self, TranscriptRecord.self, ChatTurn.self, MemoRecord.self])
    }
}
