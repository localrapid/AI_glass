//
//  RootView.swift
//  AIGlass
//
//  Top-level tabs: the glasses control/log (ContentView) and the companion.
//

import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            ContentView()
                .tabItem { Label("グラス", systemImage: "eyeglasses") }
            CompanionView()
                .tabItem { Label("相棒", systemImage: "bubble.left.and.bubble.right.fill") }
        }
    }
}
