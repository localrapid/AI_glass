//
//  AppSettings.swift
//  AIGlass
//
//  User-configurable settings. The Anthropic API key is entered in the app and
//  persisted in UserDefaults. NOTE: this is fine for a single-user prototype,
//  but embedding an API key on-device is not secure for a shipped product —
//  proxy through a server (and use the Keychain) before distributing.
//

import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {
    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: Keys.apiKey) }
    }
    /// When on, every received photo is auto-captioned via Claude. Off by
    /// default to avoid surprise API spend during continuous capture.
    @Published var autoCaption: Bool {
        didSet { UserDefaults.standard.set(autoCaption, forKey: Keys.autoCaption) }
    }

    init() {
        apiKey = UserDefaults.standard.string(forKey: Keys.apiKey) ?? ""
        autoCaption = UserDefaults.standard.object(forKey: Keys.autoCaption) as? Bool ?? false
    }

    var hasKey: Bool { !apiKey.isEmpty }

    private enum Keys {
        static let apiKey = "anthropic_api_key"
        static let autoCaption = "auto_caption"
    }
}
