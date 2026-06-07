//
//  Embedder.swift
//  AIGlass
//
//  On-device Japanese sentence embeddings via NLContextualEmbedding (the CJK
//  BERT-like model, iOS 17+). Used by the companion's RAG to find the lifelog
//  entries most relevant to a question. Fully on-device / offline.
//

import Foundation
import NaturalLanguage

actor Embedder {
    static let shared = Embedder()

    private var model: NLContextualEmbedding?
    private var triedLoad = false

    /// Lazily create + download(if needed) + load the Japanese model. Returns
    /// nil if unavailable (caller then falls back to lexical retrieval).
    private func ensureModel() async -> NLContextualEmbedding? {
        if triedLoad { return model }
        triedLoad = true
        guard let m = NLContextualEmbedding(language: .japanese) else { return nil }
        if !m.hasAvailableAssets {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                m.requestAssets { _, _ in cont.resume() }
            }
        }
        do {
            try m.load()
            model = m
        } catch {
            model = nil
        }
        return model
    }

    /// Mean-pooled sentence vector for `text`, or nil if the model is unavailable.
    func embed(_ text: String) async -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let m = await ensureModel() else { return nil }
        guard let result = try? m.embeddingResult(for: trimmed, language: .japanese) else { return nil }

        var sum: [Double] = []
        var count = 0
        result.enumerateTokenVectors(in: trimmed.startIndex..<trimmed.endIndex) { vector, _ in
            if sum.isEmpty {
                sum = vector
            } else {
                for i in 0..<min(sum.count, vector.count) { sum[i] += vector[i] }
            }
            count += 1
            return true
        }
        guard count > 0 else { return nil }
        return sum.map { Float($0 / Double(count)) }
    }
}
