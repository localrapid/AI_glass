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
    /// When on, every received photo is auto-captioned. Off by default so
    /// continuous capture doesn't fire inference (or API spend) unattended.
    @Published var autoCaption: Bool {
        didSet { UserDefaults.standard.set(autoCaption, forKey: Keys.autoCaption) }
    }

    // Local hub (4090 via M1) — the default, privacy-preserving, zero-fee path.
    @Published var useHub: Bool {
        didSet { UserDefaults.standard.set(useHub, forKey: Keys.useHub) }
    }
    @Published var hubURL: String {
        didSet { UserDefaults.standard.set(hubURL, forKey: Keys.hubURL) }
    }
    @Published var hubToken: String {
        didSet { UserDefaults.standard.set(hubToken, forKey: Keys.hubToken) }
    }
    /// When on, the companion uses the 4090 (via the hub) for higher-quality
    /// answers when it's reachable, falling back to the on-device model.
    @Published var useHubForChat: Bool {
        didSet { UserDefaults.standard.set(useHubForChat, forKey: Keys.useHubForChat) }
    }

    init() {
        apiKey = UserDefaults.standard.string(forKey: Keys.apiKey) ?? ""
        autoCaption = UserDefaults.standard.object(forKey: Keys.autoCaption) as? Bool ?? false
        useHub = UserDefaults.standard.object(forKey: Keys.useHub) as? Bool ?? true
        hubURL = UserDefaults.standard.string(forKey: Keys.hubURL) ?? "http://100.76.69.64:8765"
        hubToken = UserDefaults.standard.string(forKey: Keys.hubToken) ?? ""
        useHubForChat = UserDefaults.standard.object(forKey: Keys.useHubForChat) as? Bool ?? true
    }

    var hasKey: Bool { !apiKey.isEmpty }
    /// Whether captioning can run with the current backend selection.
    var canCaption: Bool { useHub ? !hubURL.isEmpty : !apiKey.isEmpty }

    private enum Keys {
        static let apiKey = "anthropic_api_key"
        static let autoCaption = "auto_caption"
        static let useHub = "use_hub"
        static let hubURL = "hub_url"
        static let hubToken = "hub_token"
        static let useHubForChat = "use_hub_for_chat"
    }
}
