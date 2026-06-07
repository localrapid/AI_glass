//
//  AIGlassApp.swift
//  AIGlass
//

import SwiftUI
import SwiftData

@main
struct AIGlassApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [PhotoRecord.self, TranscriptRecord.self, ChatTurn.self])
    }
}
