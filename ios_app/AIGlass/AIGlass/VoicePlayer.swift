//
//  VoicePlayer.swift
//  AIGlass
//
//  Plays a synthesized WAV (e.g. VOICEVOX from the 4090) through the phone
//  speaker / Bluetooth, and exposes a live audio level (0…1) so the avatar can
//  lip-sync to the *actual* voice instead of a fixed wiggle.
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class VoicePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = VoicePlayer()

    @Published private(set) var isPlaying = false
    /// Mouth-open amount derived from the audio envelope, 0…1.
    private(set) var level: CGFloat = 0

    private var player: AVAudioPlayer?
    private var meter: Timer?

    func play(_ wav: Data) {
        stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .allowBluetoothA2DP])
        try? session.setActive(true)

        guard let p = try? AVAudioPlayer(data: wav) else { return }
        p.isMeteringEnabled = true
        p.delegate = self
        p.prepareToPlay()
        p.play()
        player = p
        isPlaying = true

        meter = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    func stop() {
        meter?.invalidate(); meter = nil
        player?.stop(); player = nil
        level = 0
        isPlaying = false
    }

    private func sample() {
        guard let p = player, p.isPlaying else { level = 0; return }
        p.updateMeters()
        // averagePower is dB in roughly -160…0. Map speech (~-40…-10) to 0…1.
        let power = p.averagePower(forChannel: 0)
        let norm = max(0, min(1, (Double(power) + 40) / 30))
        level = CGFloat(norm) * 0.9
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
