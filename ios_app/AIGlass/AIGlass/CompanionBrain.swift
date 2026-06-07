//
//  CompanionBrain.swift
//  AIGlass
//
//  The on-device "brain" for the companion (相棒), using Apple's Foundation
//  Models framework (the ~3B on-device LLM in iOS 26). This is the privacy-
//  preserving, offline, zero-cost path. Used first as a "quality probe": given
//  recent lifelog entries as context, answer a Japanese question grounded in
//  them — so we can judge on-device quality before building the full RAG.
//

import Foundation
import FoundationModels

enum CompanionBrain {
    enum BrainError: LocalizedError {
        case unavailable
        var errorDescription: String? {
            "オンデバイスAI（Apple Intelligence）が利用できません。設定 → Apple Intelligence を有効にしてください（対応端末のみ）。"
        }
    }

    /// nil when the on-device model is ready; otherwise a user-facing reason.
    static var availabilityMessage: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable:
            return "オンデバイスAI（Apple Intelligence）が未準備です。設定 → Apple Intelligence を有効化してください（対応端末のみ・初回はモデルDLに時間がかかります）。"
        @unknown default:
            return "オンデバイスAIの状態を確認できません。"
        }
    }

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Answer a question grounded ONLY in the provided lifelog context.
    static func answer(question: String, context: String) async throws -> String {
        guard isAvailable else { throw BrainError.unavailable }

        let instructions = """
        あなたはユーザーの生活を記録した「ログ」を知る、親しみやすいAI相棒です。
        日本語で、話し言葉で、簡潔に答えてください。
        回答は与えられたログ（各行の先頭に日時）だけを根拠にしてください。
        ログから分かる場合は「いつのことか」も自然に添えてください。
        ログに無いことは推測せず「記録には無いみたい」と正直に答えてください。
        """
        let session = LanguageModelSession(instructions: instructions)
        let prompt = """
        # これまでのログ
        \(context.isEmpty ? "（まだ記録がありません）" : context)

        # 質問
        \(question)
        """
        let response = try await session.respond(to: prompt)
        return response.content
    }
}
