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
    @ObservedObject var settings: AppSettings

    @Query(sort: \PhotoRecord.receivedAt, order: .reverse) private var photos: [PhotoRecord]
    @Query(sort: \TranscriptRecord.receivedAt, order: .reverse) private var transcripts: [TranscriptRecord]
    @Query(sort: \MemoRecord.createdAt, order: .reverse) private var memos: [MemoRecord]

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatTurn.createdAt) private var turns: [ChatTurn]

    @State private var index = CompanionIndex()
    @StateObject private var speech = SpeechInput()
    @State private var autoSpeak = true
    @State private var question = ""
    @State private var thinking = false
    @State private var errorText: String?
    @ObservedObject private var router = AppRouter.shared
    /// A companion check-in ("何してる？") shown as an incoming message; the next
    /// send replies to it (conversation continues in-chat).
    @State private var pendingPing: String?

    private let samples = ["今日は何を見た？", "最近どんなことを話してた？", "あれ、どこに置いたっけ？"]
    private let topK = 8

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AvatarView()
                    .frame(height: 240)
                    .clipped()
                Divider()
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

                    if let ping = pendingPing {
                        pingBubble(ping)
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
            }
            .navigationTitle("相棒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        autoSpeak.toggle()
                        if !autoSpeak { stopSpeaking() }
                    } label: {
                        Image(systemName: autoSpeak ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    }
                }
                if !turns.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            for t in turns { modelContext.delete(t) }
                            try? modelContext.save()
                        } label: { Image(systemName: "trash") }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .onAppear { speech.requestAuthorization(); adoptIncomingPing() }
            .onChange(of: router.incomingPing) { _, _ in adoptIncomingPing() }
            .onChange(of: speech.transcript) { _, t in
                if speech.isRecording { question = t }
            }
            .onChange(of: speech.isRecording) { wasRecording, isRecording in
                if wasRecording && !isRecording
                    && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ask()
                }
            }
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
                Button { speech.toggle() } label: {
                    Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.fill")
                }
                .buttonStyle(.bordered)
                .tint(speech.isRecording ? .red : .accentColor)
                .disabled(thinking || !CompanionBrain.isAvailable)

                TextField(speech.isRecording ? "聞いています…" : (pendingPing != nil ? "返信する…" : "相棒に聞いてみる"), text: $question, axis: .vertical)
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

    private func turnView(_ turn: ChatTurn) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(turn.question)
                .font(.callout.bold())
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(10)
                .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                Text(turn.answer)
                    .font(.body).textSelection(.enabled)
                if turn.refCount > 0 {
                    DisclosureGroup("参照したログ \(turn.refCount)件") {
                        Text(turn.referencedLog)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                    .font(.caption2)
                }
                HStack {
                    Button { Task { await speak(turn.answer) } } label: {
                        Label("読み上げ", systemImage: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption2)
                    Spacer()
                    if let src = turn.source {
                        Text(src == "4090" ? "via 4090" : "via 端末")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Text(turn.createdAt.formatted(.dateTime.month().day().hour().minute()))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
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
        for m in memos where !m.text.isEmpty {
            entries.append(.init(id: m.id, date: m.createdAt, text: "話したこと: \(m.text)"))
        }
        return entries
    }

    /// Speak with the 4090's VOICEVOX voice when the hub is reachable, else
    /// fall back to the on-device voice.
    private func speak(_ text: String) async {
        if settings.useHub && settings.useHubVoice && !settings.hubURL.isEmpty {
            if let wav = try? await HubVoiceService.synthesize(
                text: text,
                config: .init(baseURL: settings.hubURL, token: settings.hubToken)) {
                VoicePlayer.shared.play(wav)
                return
            }
        }
        Speaker.shared.speak(text)
    }

    private func stopSpeaking() {
        Speaker.shared.stop()
        VoicePlayer.shared.stop()
    }

    /// Pull a tapped notification's ping into the chat as an incoming message.
    private func adoptIncomingPing() {
        if let p = router.incomingPing {
            pendingPing = p
            router.incomingPing = nil
        }
    }

    /// The companion's incoming check-in bubble; the user replies from the input.
    private func pingBubble(_ ping: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ping)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Label("相棒からの声かけ — 下の欄から返信してね", systemImage: "bubble.left.fill")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("やめる") { pendingPing = nil }
                    .font(.caption2).buttonStyle(.borderless)
            }
        }
    }

    /// Reply to a check-in: save the reply as a learnable memo, generate the
    /// companion's curious follow-up on-device, and show it as the next ping.
    private func replyToPing(_ ping: String, _ text: String) {
        let context = recentContextString()
        Task {
            let followUp = (try? await CompanionBrain.followUp(ping: ping, reply: text, context: context))
                ?? "なるほど〜！それで、どんな感じ？"
            modelContext.insert(MemoRecord(text: text))
            modelContext.insert(ChatTurn(question: text, answer: followUp,
                                         referencedLog: "（相棒の声かけ）\(ping)", refCount: 0, source: "オンデバイス"))
            try? modelContext.save()
            pendingPing = followUp               // continue the conversation in-chat
            if autoSpeak { await speak(followUp) }
            thinking = false
        }
    }

    /// Recent (last 24h) lifelog + memos, for grounding a follow-up.
    private func recentContextString() -> String {
        let since = Date().addingTimeInterval(-24 * 3600)
        return allEntries()
            .filter { $0.date > since }
            .sorted { $0.date < $1.date }
            .suffix(8)
            .map { "\($0.date.formatted(.dateTime.month().day().hour().minute())) \($0.text)" }
            .joined(separator: "\n")
    }

    private func ask() {
        if speech.isRecording { speech.stop() }   // tapping send also ends dictation
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !thinking else { return }
        question = ""
        thinking = true
        errorText = nil
        // If a companion check-in is pending, treat this as a reply to it and
        // keep the conversation going in-chat.
        if let ping = pendingPing {
            pendingPing = nil
            replyToPing(ping, q)
            return
        }
        let allEntriesList = allEntries()
        let now = Date()
        Task {
            // Narrow to a time window if the question mentions one (「昨日の」等).
            var pool = allEntriesList
            if let window = CompanionDates.range(from: q, now: now) {
                let filtered = pool.filter { window.contains($0.date) }
                if !filtered.isEmpty { pool = filtered }
            }
            let hits = await index.topK(query: q, entries: pool, k: topK)
            let dateLine = "現在の日時: \(now.formatted(.dateTime.year().month().day().hour().minute()))"
            let body = hits
                .sorted { $0.date < $1.date }
                .map { "\($0.date.formatted(.dateTime.month().day().hour().minute())) \($0.text)" }
                .joined(separator: "\n")
            let context = body.isEmpty ? dateLine : "\(dateLine)\n\n\(body)"
            do {
                var answer = ""
                var source = "オンデバイス"
                // At home (hub reachable) use the 4090's bigger model; otherwise
                // fall back to the on-device model.
                if settings.useHub && settings.useHubForChat && !settings.hubURL.isEmpty {
                    if let hub = try? await HubChatService.ask(
                        question: q, context: context,
                        config: .init(baseURL: settings.hubURL, token: settings.hubToken)) {
                        answer = hub
                        source = "4090"
                    }
                }
                if answer.isEmpty {
                    answer = try await CompanionBrain.answer(question: q, context: context)
                }
                modelContext.insert(ChatTurn(question: q, answer: answer,
                                             referencedLog: context, refCount: hits.count, source: source))
                try? modelContext.save()
                if autoSpeak { await speak(answer) }
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            thinking = false
        }
    }
}
