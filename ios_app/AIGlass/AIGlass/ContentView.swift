//
//  ContentView.swift
//  AIGlass
//
//  Phase 1 step 7/8 + captioning UI: BLE connection state, the latest JPEG from
//  the glasses, in-progress chunk count, capture-interval controls, an AI
//  description (Claude) per photo, and a list of received frames.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var ble = BLEManager()
    @StateObject private var settings = AppSettings()
    @State private var showSettings = false

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PhotoRecord.receivedAt, order: .reverse) private var photos: [PhotoRecord]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statusCard
                    latestImageCard
                    controlCard
                    historyList
                }
                .padding()
            }
            .navigationTitle("AI_glass")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(settings: settings)
            }
        }
        .onAppear {
            // Let the BLE manager read the current captioning preferences
            // without owning settings state.
            ble.captionConfig = {
                BLEManager.CaptionSettings(
                    auto: settings.autoCaption,
                    useHub: settings.useHub,
                    hubURL: settings.hubURL,
                    hubToken: settings.hubToken,
                    apiKey: settings.apiKey
                )
            }
            ble.attach(context: modelContext)
        }
    }

    // MARK: Connection status

    private var statusCard: some View {
        HStack {
            Circle()
                .fill(ble.state == .connected ? .green : .secondary)
                .frame(width: 12, height: 12)
            Text(ble.state.rawValue)
                .font(.headline)
            Spacer()
            if ble.negotiatedMTU > 0 {
                Text("MTU≈\(ble.negotiatedMTU)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Latest image + caption

    private var latestImageCard: some View {
        VStack(spacing: 8) {
            if let latest = photos.first {
                if let img = latest.image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Text("\(latest.byteCount) bytes ・ \(latest.chunkCount) chunks\(latest.hadGap ? " ⚠️gap" : "")")
                    .font(.caption.monospaced())
                    .foregroundStyle(latest.hadGap ? .orange : .secondary)
                captionView(for: latest)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.quaternary)
                        .frame(height: 220)
                    VStack(spacing: 6) {
                        Image(systemName: "camera.metering.unknown")
                            .font(.largeTitle)
                        if ble.chunksInProgress > 0 {
                            Text("受信中… \(ble.chunksInProgress) chunks / \(ble.bytesInProgress) bytes")
                        } else {
                            Text("まだ写真を受信していません")
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            if !ble.lastLog.isEmpty {
                Text(ble.lastLog)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func captionView(for photo: PhotoRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if photo.isCaptioning {
                HStack(spacing: 6) {
                    ProgressView()
                    Text("AIが説明を生成中…").font(.callout)
                }
            } else if let caption = photo.caption {
                Text(caption)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error = photo.captionError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                Button("再試行") { ble.requestCaption(for: photo.id) }
                    .buttonStyle(.bordered)
                    .disabled(!settings.canCaption)
            } else {
                Button {
                    ble.requestCaption(for: photo.id)
                } label: {
                    Label("AIで説明を生成", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!settings.canCaption)
                if !settings.canCaption {
                    Text(settings.useHub
                         ? "⚙️ 設定でハブURLを入力すると説明を生成できます"
                         : "⚙️ 設定でAPIキーを入力すると説明を生成できます")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Capture control (Photo Control writes — Phase 1 step 8)

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("撮影コントロール")
                .font(.subheadline.bold())
            HStack {
                Button("1枚") { ble.sendControl(PhotoControlCommand.captureOnce) }
                Button("5秒")  { ble.sendControl(5) }
                Button("10秒") { ble.sendControl(10) }
                Button("15秒") { ble.sendControl(15) }
                Button("停止") { ble.sendControl(PhotoControlCommand.stop) }
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .disabled(ble.state != .connected)
        .opacity(ble.state == .connected ? 1 : 0.5)
    }

    // MARK: History

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("受信履歴 (\(photos.count))")
                .font(.subheadline.bold())
            ForEach(photos) { photo in
                HStack(spacing: 12) {
                    PhotoImageView(record: photo, hubURL: settings.hubURL)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(photo.receivedAt, format: .dateTime.hour().minute().second())
                            .font(.callout)
                        if let caption = photo.caption {
                            Text(caption)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        } else {
                            Text(photo.isLocal
                                 ? "\(photo.byteCount) bytes ・ \(photo.chunkCount) chunks"
                                 : "ハブ保存 ・ \(photo.chunkCount) chunks")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if photo.isCaptioning { ProgressView() }
                    if photo.hadGap {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Settings

private struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("推論バックエンド") {
                    Toggle("ローカルハブを使う（4090）", isOn: $settings.useHub)
                    Text(settings.useHub
                         ? "Tailscale経由で自宅の4090に推論させます。API課金ゼロ・画像は自分の機材内。"
                         : "Claude API（クラウド）に推論させます。MAXプランとは別の従量課金。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if settings.useHub {
                    Section("ローカルハブ") {
                        TextField("http://100.76.69.64:8765", text: $settings.hubURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        SecureField("共有トークン（任意）", text: $settings.hubToken)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Text("M1ハブのTailscaleアドレス。iPhoneもTailscaleに接続している必要があります。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Claude API キー") {
                        SecureField("sk-ant-...", text: $settings.apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Text("console.anthropic.com で発行したAPIキー。MAXプランとは別課金（従量制）です。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("AI説明") {
                    Toggle("受信ごとに自動で説明を生成", isOn: $settings.autoCaption)
                    Text("ONにすると写真1枚ごとに推論します。連続撮影中は負荷/費用が積み上がるため、まずはOFF＋手動生成を推奨。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }
}

/// Shows a photo from the local cache if present, otherwise fetches it from the
/// hub (for items whose local copy was pruned after 3 days).
private struct PhotoImageView: View {
    let record: PhotoRecord
    let hubURL: String

    var body: some View {
        Group {
            if let img = record.image {
                Image(uiImage: img).resizable().scaledToFill()
            } else if let jid = record.hubJobID, let url = URL(string: "\(hubURL)/jobs/\(jid)/image") {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else if phase.error != nil {
                        placeholder("icloud.slash")        // hub unreachable
                    } else {
                        placeholder("arrow.down.circle")   // loading
                    }
                }
            } else {
                placeholder("photo")
            }
        }
    }

    private func placeholder(_ symbol: String) -> some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Image(systemName: symbol).font(.caption).foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
