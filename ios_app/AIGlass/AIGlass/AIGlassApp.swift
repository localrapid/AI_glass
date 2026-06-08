//
//  AIGlassApp.swift
//  AIGlass
//

import SwiftUI
import SwiftData

@main
struct AIGlassApp: App {
    let container: ModelContainer

    init() {
        container = try! ModelContainer(
            for: PhotoRecord.self, TranscriptRecord.self, ChatTurn.self, MemoRecord.self)
        // Become the notification delegate and register the repliable category,
        // sharing the same store the UI uses.
        NotificationCoordinator.shared.configure(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
