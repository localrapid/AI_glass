//
//  CaptionService.swift
//  AIGlass
//
//  Sends a captured JPEG to the Claude Messages API and returns a short
//  Japanese description. Uses URLSession directly (no Anthropic SDK exists for
//  Swift) against the raw HTTP API.
//
//  Model: claude-haiku-4-5 — the cheapest vision-capable tier. An 800x600 JPEG
//  is ~640 image tokens, so each caption costs on the order of $0.001. Prompt
//  caching is not used: the image (the bulk of the input) changes every call,
//  and the small system prompt is below the cacheable minimum.
//

import Foundation

enum CaptionService {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-haiku-4-5"
    private static let anthropicVersion = "2023-06-01"

    private static let systemPrompt =
        "あなたは画像に何が写っているかを日本語で簡潔に説明するアシスタントです。" +
        "1〜2文で、写っている人・物・場所・行動など具体的な内容を述べてください。" +
        "「画像には」などの前置きや定型句は不要で、説明本文だけを返してください。"

    enum CaptionError: LocalizedError {
        case missingKey
        case badResponse
        case http(status: Int, message: String)
        case emptyContent

        var errorDescription: String? {
            switch self {
            case .missingKey:          return "APIキーが未設定です"
            case .badResponse:         return "サーバ応答が不正です"
            case .http(let s, let m):  return "APIエラー(\(s)): \(m)"
            case .emptyContent:        return "説明が空でした"
            }
        }
    }

    static func caption(jpeg: Data, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else { throw CaptionError.missingKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 200,
            "system": systemPrompt,
            "messages": [[
                "role": "user",
                "content": [
                    [
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": jpeg.base64EncodedString(),
                        ],
                    ],
                    ["type": "text", "text": "この画像を説明してください。"],
                ],
            ]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CaptionError.badResponse }

        guard (200..<300).contains(http.statusCode) else {
            throw CaptionError.http(status: http.statusCode, message: extractError(data))
        }

        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = object["content"] as? [[String: Any]]
        else { throw CaptionError.badResponse }

        let text = content
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { throw CaptionError.emptyContent }
        return text
    }

    /// Pull `error.message` out of an Anthropic error envelope for display.
    private static func extractError(_ data: Data) -> String {
        if
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = object["error"] as? [String: Any],
            let message = error["message"] as? String
        {
            return message
        }
        return String(data: data, encoding: .utf8) ?? "unknown"
    }
}
