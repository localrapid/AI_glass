//
//  CompanionView.swift
//  AIGlass
//
//  Companion (相棒) — on-device RAG chat. A question retrieves the most
//  relevant lifelog entries (semantic embeddings, lexical fallback) and the
//  on-device LLM answers grounded in them. Fully on-device / offline / private.
//

import SwiftUI
import SwiftData

struct CompanionView: View {
    @Query(sort: \PhotoRecord.receivedAt, order: .reverse) private var photos: [PhotoRecord]
    @Query(sort: \TranscriptRecord.receivedAt, order: .reverse) private var transcripts: [TranscriptRecord]

    @State private var index = CompanionIndex()
    @State private var turns: [Turn] = []
    @State private var question = ""
    @State private var thinking = false
    @State private var errorText: String?

    private let samples = ["今日は何を見た？", "最近どんなことを話してた？", "あれ、どこに置いたっけ？"]
    private let topK = 8

    struct Turn: Identifiable {
        let id = UUID()
        let q: String
        let a: String
        let refs: Int
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let msg = CompanionBrain.availabilityMessage {
                        Label(msg, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(.orange)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }

                    Text("これまでのログ（\(logCount)件）から関連を探して答えます。")
                        .font(.caption).foregroundStyle(.secondary)

                    ForEach(turns) { turn in
                        turnView(turn)
                    }

                    if thinking {
                        HStack(spacing: 8) { ProgressView(); Text("関連ログを探して考え中…") }
                            .foregroundStyle(.secondary)
                    }
                    if let e = errorText {
                        Text(e).font(.callout).foregroundStyle(.red)
                    }
                    if turns.isEmpty && logCount == 0 {
                        Text("まだログがありません。グラスで写真を撮る／録音すると、その内容を根拠に答えられます。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("相棒")
            .safeAreaInset(edge: .bottom) { inputBar }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            if turns.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(samples, id: \.self) { s in
                            Button(s) { question = s; ask() }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            HStack(alignment: .bottom) {
                TextField("相棒に聞いてみる", text: $question, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                Button { ask() } label: { Image(systemName: "paperplane.fill") }
                    .buttonStyle(.borderedProminent)
                    .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || thinking || !CompanionBrain.isAvailable)
            }
            .padding(.horizontal)
            .padding(.bottom, 6)
        }
        .background(.bar)
    }

    private func turnView(_ turn: Turn) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(turn.q)
                .font(.callout.bold())
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(10)
                .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(turn.a)
                    .font(.body).textSelection(.enabled)
                Text("参照ログ \(turn.refs)件")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var logCount: Int {
        photos.lazy.filter { $0.caption != nil }.count
            + transcripts.lazy.filter { ($0.transcript?.isEmpty == false) }.count
    }

    private func allEntries() -> [CompanionIndex.Entry] {
        var entries: [CompanionIndex.Entry] = []
        for p in photos where p.caption != nil {
            entries.append(.init(id: p.id, date: p.receivedAt, text: "見たもの: \(p.caption!)"))
        }
        for t in transcripts where (t.transcript?.isEmpty == false) {
            entries.append(.init(id: t.id, date: t.receivedAt, text: "聞いたこと: \(t.transcript!)"))
        }
        return entries
    }

    private func ask() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        question = ""
        thinking = true
        errorText = nil
        let entries = allEntries()
        Task {
            let hits = await index.topK(query: q, entries: entries, k: topK)
            let context = hits
                .sorted { $0.date < $1.date }
                .map { "\($0.date.formatted(.dateTime.month().day().hour().minute())) \($0.text)" }
                .joined(separator: "\n")
            do {
                let a = try await CompanionBrain.answer(question: q, context: context)
                turns.append(Turn(q: q, a: a, refs: hits.count))
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            thinking = false
        }
    }
}
