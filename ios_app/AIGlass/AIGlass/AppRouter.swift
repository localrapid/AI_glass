//
//  AppRouter.swift
//  AIGlass
//
//  Tiny shared router so non-View code (the notification handler) can ask the
//  UI to switch tabs — e.g. tapping a companion notification opens the 相棒 tab.
//

import Foundation
import Combine

@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    /// 0 = グラス, 1 = 相棒
    @Published var selectedTab = 0
}
