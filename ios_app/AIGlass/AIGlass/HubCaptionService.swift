//
//  HubCaptionService.swift
//  AIGlass
//
//  Talks to the local AI_glass hub (running on the personal M1 over Tailscale).
//  Uploads a JPEG as a "caption" job, then polls until the 4090 worker has run
//  the local vision model and posted the Japanese description back.
//
//  This is the privacy-preserving, zero-API-fee path. CaptionService (Claude)
//  remains as an optional cloud fallback selectable in settings.
//

import Foundation

enum HubCaptionService {
    struct Config {
        let baseURL: String   // e.g. http://100.76.69.64:8765
        let token: String     // optional shared secret; "" = none
    }

    enum HubError: LocalizedError {
        case badURL
        case http(Int)
        case decode
        case jobFailed(String)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .badURL:            return "ハブURLが不正です"
            case .http(let s):       return "ハブ通信エラー(\(s))"
            case .decode:            return "ハブ応答が不正です"
            case .jobFailed(let m):  return "推論失敗: \(m)"
            case .timedOut:          return "推論がタイムアウトしました"
            }
        }
    }

    /// Submit a photo and wait for the caption. Polls every ~1.2s up to `timeout`.
    static func caption(jpeg: Data, config: Config, timeout: TimeInterval = 90) async throws -> String {
        let jobID = try await upload(jpeg: jpeg, kind: "caption", config: config)
        return try await result(jobID: jobID, config: config, timeout: timeout)
    }

    /// Image URL on the hub for an already-uploaded job (used after the local
    /// copy is pruned). Note: no auth header — fine when the hub has no token.
    static func imageURL(jobID: String, config: Config) -> URL? {
        URL(string: "\(config.baseURL)/jobs/\(jobID)/image")
    }

    // MARK: - POST /jobs (multipart)

    /// Upload a photo to the hub. kind "store" = keep but don't caption;
    /// kind "caption" = also queue for the worker. Returns the job id.
    static func upload(jpeg: Data, kind: String, config: Config) async throws -> String {
        guard let url = URL(string: "\(config.baseURL)/jobs") else { throw HubError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        addAuth(&request, config)

        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"kind\"\r\n\r\n\(kind)\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"image\"; filename=\"photo.jpg\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpeg)
        append("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        try ensureOK(response)
        guard
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = obj["id"] as? String
        else { throw HubError.decode }
        return id
    }

    /// Re-queue an already-stored job for captioning.
    static func recaption(jobID: String, config: Config) async throws {
        guard let url = URL(string: "\(config.baseURL)/jobs/\(jobID)/recaption") else { throw HubError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addAuth(&request, config)
        let (_, response) = try await URLSession.shared.data(for: request)
        try ensureOK(response)
    }

    // MARK: - GET /jobs/{id} (poll)

    static func result(jobID: String, config: Config, timeout: TimeInterval = 90) async throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard let url = URL(string: "\(config.baseURL)/jobs/\(jobID)") else { throw HubError.badURL }
            var request = URLRequest(url: url)
            addAuth(&request, config)
            let (data, response) = try await URLSession.shared.data(for: request)
            try ensureOK(response)
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                switch obj["status"] as? String {
                case "done":
                    return (obj["result"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                case "error":
                    throw HubError.jobFailed(obj["error"] as? String ?? "unknown")
                default:
                    break  // pending / processing — keep polling
                }
            }
            try await Task.sleep(nanoseconds: 1_200_000_000)
        }
        throw HubError.timedOut
    }

    // MARK: - helpers

    private static func addAuth(_ request: inout URLRequest, _ config: Config) {
        if !config.token.isEmpty {
            request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        }
    }

    private static func ensureOK(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw HubError.decode }
        guard (200..<300).contains(http.statusCode) else { throw HubError.http(http.statusCode) }
    }
}
