//
//  HubChatService.swift
//  AIGlass
//
//  Companion chat escalated to the 4090: the iPhone retrieves the relevant
//  lifelog on-device, then sends the question + context to the hub's /ask. The
//  4090 worker generates a higher-quality answer with the big model (pulled as
//  a kind="chat" job — outbound-only, works behind the corporate firewall).
//

import Foundation

enum HubChatService {
    /// Submit a question + retrieved context; wait for the 4090's answer.
    static func ask(question: String,
                    context: String,
                    config: HubCaptionService.Config,
                    timeout: TimeInterval = 90) async throws -> String {
        guard let url = URL(string: "\(config.baseURL)/ask") else { throw HubCaptionService.HubError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10  // fail fast when the hub is unreachable (away from home)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.token.isEmpty {
            request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["question": question, "context": context]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw HubCaptionService.HubError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = obj["id"] as? String
        else { throw HubCaptionService.HubError.decode }

        return try await HubCaptionService.result(jobID: id, config: config, timeout: timeout)
    }
}
