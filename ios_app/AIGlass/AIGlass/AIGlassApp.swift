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
            ContentView()
        }
        .modelContainer(for: [PhotoRecord.self, TranscriptRecord.self])
    }
}
