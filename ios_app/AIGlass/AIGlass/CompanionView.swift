//
//  CompanionView.swift
//  AIGlass
//
//  Step 1 of the companion (相棒): a "quality probe". Feeds recent lifelog
//  entries (image captions + audio transcripts) as context to the on-device
//  LLM and answers a Japanese question — so we can judge on-device quality
//  before building the full RAG (embeddings + vector search).
//

import SwiftUI
import SwiftData

struct CompanionView: View {
    @Query(sort: \PhotoRecord.receivedAt, order: .reverse) private var photos: [PhotoRecord]
    @Query(sort: \TranscriptRecord.receivedAt, order: .reverse) private var transcripts: [TranscriptRecord]

    @State private var question = ""
    @State private var answer = ""
    @State private var errorText: String?
    @State private var thinking = false

    private let samples = ["今日は何を見た？", "最近どんなことを話してた？", "あれ、どこに置いたっけ？"]
    private let maxEntries = 40

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let msg = CompanionBrain.availabilityMessage {
                        Label(msg, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }

                    Text("オンデバイスAIに、これまでのログ（直近\(usedCount)件）を根拠に聞いてみます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // sample questions
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(samples, id: \.self) { s in
                                Button(s) { question = s }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                    }

                    HStack(alignment: .bottom) {
                        TextField("質問を入力", text: $question, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)
                        Button {
                            ask()
                        } label: {
                            Image(systemName: "paperplane.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || thinking || !CompanionBrain.isAvailable)
                    }

                    if thinking {
                        HStack(spacing: 8) { ProgressView(); Text("考え中…") }
                            .foregroundStyle(.secondary)
                    }
                    if let e = errorText {
                        Text(e).font(.callout).foregroundStyle(.red)
                    }
                    if !answer.isEmpty {
                        Text(answer)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }

                    if usedCount == 0 {
                        Text("まだログがありません。グラスで写真を撮る／録音すると、その内容を根拠に答えられるようになります。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("相棒")
        }
    }

    private var usedCount: Int {
        let c = photos.lazy.filter { $0.caption != nil }.count
            + transcripts.lazy.filter { ($0.transcript?.isEmpty == false) }.count
        return min(maxEntries, c)
    }

    private func ask() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        let ctx = buildContext()
        thinking = true
        answer = ""
        errorText = nil
        Task {
            do {
                answer = try await CompanionBrain.answer(question: q, context: ctx)
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            thinking = false
        }
    }

    /// Most-recent log entries, newest first, time-stamped. (The probe uses a
    /// simple recency cut; the real RAG step replaces this with vector search.)
    private func buildContext() -> String {
        var entries: [(Date, String)] = []
        for p in photos where p.caption != nil {
            entries.append((p.receivedAt, "見たもの: \(p.caption!)"))
        }
        for t in transcripts where (t.transcript?.isEmpty == false) {
            entries.append((t.receivedAt, "聞いたこと: \(t.transcript!)"))
        }
        entries.sort { $0.0 > $1.0 }
        return entries.prefix(maxEntries).map { entry in
            "\(entry.0.formatted(.dateTime.month().day().hour().minute())) \(entry.1)"
        }.joined(separator: "\n")
    }
}
