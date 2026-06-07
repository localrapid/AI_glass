//
//  HubVoiceService.swift
//  AIGlass
//
//  Companion voice via the 4090: POST the answer text to the hub (/speak),
//  which queues a `tts` job; the 4090 worker synthesizes it with VOICEVOX and
//  uploads a WAV. We poll the job, then download the audio for playback.
//

import Foundation

enum HubVoiceService {
    typealias Config = HubCaptionService.Config
    typealias HubError = HubCaptionService.HubError

    static func synthesize(text: String, config: Config, timeout: TimeInterval = 30) async throws -> Data {
        let base = config.baseURL.hasSuffix("/") ? String(config.baseURL.dropLast()) : config.baseURL

        func authed(_ url: URL, method: String = "GET") -> URLRequest {
            var r = URLRequest(url: url)
            r.httpMethod = method
            if !config.token.isEmpty {
                r.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
            }
            return r
        }

        // 1) Create the tts job.
        guard let speakURL = URL(string: "\(base)/speak") else { throw HubError.badURL }
        var post = authed(speakURL, method: "POST")
        post.setValue("application/json", forHTTPHeaderField: "Content-Type")
        post.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])
        post.timeoutInterval = 10
        let (created, cresp) = try await URLSession.shared.data(for: post)
        guard let ch = cresp as? HTTPURLResponse, (200..<300).contains(ch.statusCode) else {
            throw HubError.http((cresp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: created) as? [String: Any],
              let jid = obj["id"] as? String else { throw HubError.decode }

        // 2) Poll until the worker finishes.
        guard let jobURL = URL(string: "\(base)/jobs/\(jid)") else { throw HubError.badURL }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let (jd, _) = try await URLSession.shared.data(for: authed(jobURL))
            if let job = try? JSONSerialization.jsonObject(with: jd) as? [String: Any],
               let status = job["status"] as? String {
                if status == "done" {
                    // 3) Download the synthesized WAV.
                    guard let audioURL = URL(string: "\(base)/jobs/\(jid)/audio") else { throw HubError.badURL }
                    let (audio, aresp) = try await URLSession.shared.data(for: authed(audioURL))
                    guard let ah = aresp as? HTTPURLResponse, (200..<300).contains(ah.statusCode), !audio.isEmpty else {
                        throw HubError.timedOut
                    }
                    return audio
                }
                if status == "error" {
                    throw HubError.jobFailed((job["error"] as? String) ?? "tts failed")
                }
            }
            try await Task.sleep(nanoseconds: 400_000_000)
        }
        throw HubError.timedOut
    }
}
