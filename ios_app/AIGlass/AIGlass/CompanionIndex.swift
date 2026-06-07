//
//  CompanionIndex.swift
//  AIGlass
//
//  Retrieval for the companion's RAG: given a question, return the most
//  relevant lifelog entries (semantic via embeddings, with a lexical fallback).
//  Embeddings are cached in memory per launch (keyed by entry id).
//

import Foundation
import NaturalLanguage

@MainActor
final class CompanionIndex {
    struct Entry: Identifiable {
        let id: UUID
        let date: Date
        let text: String
    }

    private var cache: [UUID: [Float]] = [:]

    /// Top-k most relevant entries for `query`.
    func topK(query: String, entries: [Entry], k: Int) async -> [Entry] {
        guard !entries.isEmpty else { return [] }

        if let q = await Embedder.shared.embed(query) {
            var scored: [(Entry, Float)] = []
            for e in entries {
                let v: [Float]
                if let cached = cache[e.id] {
                    v = cached
                } else if let nv = await Embedder.shared.embed(e.text) {
                    cache[e.id] = nv
                    v = nv
                } else {
                    continue  // embedding failed for this entry; skip
                }
                scored.append((e, cosine(q, v)))
            }
            if scored.isEmpty { return lexicalTopK(query: query, entries: entries, k: k) }
            scored.sort { $0.1 > $1.1 }
            return scored.prefix(k).map { $0.0 }
        } else {
            return lexicalTopK(query: query, entries: entries, k: k)
        }
    }

    // MARK: - helpers

    private func cosine(_ a: [Float], _ b: [Float]) -> Float {
        let n = min(a.count, b.count)
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<n {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        return (na > 0 && nb > 0) ? dot / (na.squareRoot() * nb.squareRoot()) : 0
    }

    private func lexicalTopK(query: String, entries: [Entry], k: Int) -> [Entry] {
        let q = Set(terms(query))
        let scored = entries
            .map { e -> (Entry, Int) in
                let et = Set(terms(e.text))
                return (e, q.intersection(et).count)
            }
            .sorted { $0.1 > $1.1 }
        if (scored.first?.1 ?? 0) == 0 {
            // No lexical overlap — fall back to most recent.
            return entries.sorted { $0.date > $1.date }.prefix(k).map { $0 }
        }
        return scored.prefix(k).map { $0.0 }
    }

    private func terms(_ s: String) -> [String] {
        let tok = NLTokenizer(unit: .word)
        tok.string = s
        var out: [String] = []
        tok.enumerateTokens(in: s.startIndex..<s.endIndex) { range, _ in
            out.append(String(s[range]).lowercased())
            return true
        }
        return out
    }
}
