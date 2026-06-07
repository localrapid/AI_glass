//
//  RootView.swift
//  AIGlass
//
//  Top-level tabs: the glasses control/log (ContentView) and the companion.
//

import SwiftUI

struct RootView: View {
    @StateObject private var settings = AppSettings()

    var body: some View {
        TabView {
            ContentView(settings: settings)
                .tabItem { Label("グラス", systemImage: "eyeglasses") }
            CompanionView(settings: settings)
                .tabItem { Label("相棒", systemImage: "bubble.left.and.bubble.right.fill") }
        }
    }
}
