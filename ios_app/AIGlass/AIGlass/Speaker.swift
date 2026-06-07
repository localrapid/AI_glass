//
//  Speaker.swift
//  AIGlass
//
//  Text-to-speech for the companion's replies (Japanese). Plays through the
//  phone speaker or connected Bluetooth earphones. Free, on-device.
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class Speaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()
    /// True while an utterance is being spoken — drives the avatar's lip-sync.
    @Published private(set) var isSpeaking = false
    private let synth = AVSpeechSynthesizer()
    private lazy var voice: AVSpeechSynthesisVoice? = Self.bestJapaneseVoice()

    private override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        stop()
        // Route to playback so TTS is audible after a recording session.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .allowBluetoothA2DP])
        try? session.setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate     // natural pace
        utterance.pitchMultiplier = 1.08                        // slightly younger / brighter
        synth.speak(utterance)
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    /// Pick the most natural Japanese voice available: prefer premium > enhanced
    /// quality, and a female voice (e.g. Kyoko / O-ren). Falls back to the
    /// default ja-JP voice if no high-quality voice is installed.
    private static func bestJapaneseVoice() -> AVSpeechSynthesisVoice? {
        let japanese = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("ja") }
        func score(_ v: AVSpeechSynthesisVoice) -> Int {
            var s = 0
            switch v.quality {
            case .premium: s += 100
            case .enhanced: s += 50
            default: break
            }
            if v.gender == .female { s += 10 }
            let id = (v.identifier + " " + v.name).lowercased()
            if id.contains("kyoko") || id.contains("o-ren") || id.contains("oren") { s += 5 }
            return s
        }
        return japanese.max { score($0) < score($1) } ?? AVSpeechSynthesisVoice(language: "ja-JP")
    }

    // MARK: - AVSpeechSynthesizerDelegate (drives lip-sync)
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
