# ファームウェア設計レポート — OpenGlass 解析 → AI_glass Phase 1 仕様

OpenGlass の firmware.ino を解析し、AI_glass のファームウェアをどう作るかを決めるドキュメント。

---

## 1. OpenGlass ファームウェアの全体像

### 1.1 構成ファイル

| ファイル | 役割 |
|---|---|
| `firmware.ino` | メインスケッチ。BLE・カメラ・マイクの全てを内包 |
| `camera_pins.h` | XIAO ESP32-S3 Sense のカメラGPIO定義 |
| `mulaw.h` | μ-law 音声圧縮ルーチン |
| `opus.h` (条件付き) | Opus 音声コーデック |

### 1.2 BLEサービス設計

**Main Service**：`19B10000-E8F2-537E-4F6C-D104768A1214`

| Characteristic | UUID 末尾 | プロパティ | 用途 |
|---|---|---|---|
| Audio Data | 19B10001 | READ + NOTIFY | デバイス→スマホ。音声フレーム |
| Audio Codec | 19B10002 | READ | 使用コーデックID（1=PCM, 11=μ-law, 20=Opus）|
| Photo Data | 19B10005 | READ + NOTIFY | デバイス→スマホ。JPEG チャンク |
| Photo Control | 19B10006 | WRITE | スマホ→デバイス。撮影コマンド |

加えて標準サービス：Device Information (`0x180A`)、Battery (`0x180F`)。

### 1.3 写真の送信プロトコル

JPEG を **200バイトずつのチャンク** に分割し、各パケットの先頭に **2バイトのフレームカウンタ** を付けて BLE Notify。

```
[counter_LSB][counter_MSB][JPEG bytes (max 200)]
```

転送終了マーカー：カウンタ `0xFFFF` のパケット（ペイロード空）。

カメラ設定：SVGA 800×600、JPEG quality=10、フレームバッファは PSRAM。Grab mode は LATEST（読まれないフレームは捨てる）。

### 1.4 音声の送信プロトコル

20msごとにマイクから読み、コーデックでエンコード、Notify。

```
[counter_LSB][counter_MSB][0x00][encoded audio]
```

デフォルトは PCM 16kHz/16bit。μ-law または Opus に切替可（コンパイル時選択）。

### 1.5 撮影制御コマンド（Photo Control への書き込み値）

| 値 | 意味 |
|---|---|
| `-1` | 1枚撮って停止 |
| `0` | 撮影停止 |
| `5〜300` | 撮影間隔（秒）。5秒単位に丸めて起動 |

### 1.6 不足している機能（今後我々が足すべきもの）

- **物理ボタン／タッチ入力**：一切なし
- **バッテリ実測**：`batteryLevel = 100` 固定の TODO
- **ディープスリープ／省電力**：なし
- **WiFi**：使っていない（BLE のみ）
- **OTA**：なし

---

## 2. ライセンスと流用方針

OpenGlass は **MIT License** 。著作権表示を残せば自由に利用・改変可能。

**戦略**：「Forkとして上流追従する」ではなく、**「コードを取り込んだうえで自前管理する」**。理由：
- OpenGlassは既にアーカイブ済みで上流が動かない
- 我々はBLEのUUIDも機能も変えるので、上流と乖離していく
- 著作権表示は `firmware/THIRD_PARTY_NOTICES.md` でまとめて記載すれば足りる

---

## 3. AI_glass Phase 1 ファームウェア仕様

### 3.1 スコープ（Phase 1で実装するもの）

- BLE で iPhone と接続
- **15秒間隔の自動撮影**（コマンドで間隔変更可能）
- **TTP223 タッチでの手動撮影**
- JPEG を BLE で iPhone に転送
- 接続時 LED 点灯（プロト中のデバッグ用、Phase 3で消す）

**やらないこと（Phase 2以降）**：音声、バッテリ実測、ディープスリープ、VAD、WiFi、OTA、IMU。

### 3.2 BLEサービス設計（AI_glass版）

OpenGlassと衝突しないよう **新UUIDセット** を採用。基底は `a17ec1a5-...` （"ai-glass" の語呂合わせ）。

**Service UUID**：`a17ec1a5-0000-4000-8000-000000000001`

| Characteristic | UUID | プロパティ | Phase 1 | 用途 |
|---|---|---|:-:|---|
| Photo Data | `...000000000002` | READ + NOTIFY | ✅ | JPEGチャンク（OpenGlassと同形式）|
| Photo Control | `...000000000003` | WRITE | ✅ | 撮影コマンド |
| Touch Event | `...000000000004` | NOTIFY | ✅ | タッチ発火を通知（タップ／長押し）|
| Status | `...000000000005` | READ + NOTIFY | ✅ | 撮影中/待機/電池低下フラグ |
| Audio Data | `...000000000006` | READ + NOTIFY | ❌ | Phase 2 |
| Audio Codec | `...000000000007` | READ | ❌ | Phase 2 |

加えて Battery Service (`0x180F`) は Phase 2 で実装。Device Information (`0x180A`) は Phase 1 から実装（モデル名表示用）。

> **UUIDは「概念設計」段階のもの**。実装着手時に `uuidgen` で再採番してもよい。アプリと一致させることが重要。

### 3.3 撮影制御コマンド

OpenGlass の仕組みを継承しつつ拡張：

| 値（int8） | 意味 |
|---|---|
| `-1` | 1枚撮影 |
| `0` | 自動撮影停止 |
| `1〜120` | 自動撮影間隔（秒）。5秒単位に丸めない（10秒運用も試したい）|

### 3.4 タッチ入力仕様

TTP223 を **GPIO D2（XIAO 端子）** に接続する想定。

- **短押し（< 1秒）**：単発撮影をトリガ（内部的に Photo Control に `-1` を書く相当）
- **長押し（≥ 2秒）**：今は撮影せず、Touch Event のみ通知（アプリ側で「録音開始」など割り当てる余地）
- **連打ガード**：500ms 以内の再発火は無視

Touch Event の Notify ペイロード：
```
[event_type: 1byte][duration_ms: 2bytes LE]
  event_type: 0x01=tap, 0x02=long_press
```

### 3.5 タイムラインと電力プロファイル

Phase 1 では省電力を妥協し、**常時動作モード** で実装。

| 状態 | 動作 |
|---|---|
| 起動直後 | BLE 広告開始、カメラ・タッチ初期化、LED 点灯 |
| BLE 未接続 | 撮影せず、Touch Event もキューせず破棄、LED 点滅 |
| BLE 接続中 | Photo Control に従い撮影、Touch Event は即通知 |

実測：XIAO ESP32-S3 Sense が常時動作で **200mA前後**、250mAh電池なら **1〜1.5時間**程度の想定。Phase 2 でディープスリープ＋オンデマンド起動に最適化することで5〜8時間を狙う。

---

## 4. ファイル構成（firmware/ 配下）

```
firmware/
├── AIGlass/                  # Arduino スケッチフォルダ（フォルダ名=スケッチ名）
│   ├── AIGlass.ino           # メインスケッチ
│   ├── config.h              # UUID, GPIO, 撮影パラメータの定数
│   ├── camera_pins.h         # OpenGlassからコピー（XIAO ESP32-S3 Sense用）
│   ├── ble_protocol.h        # BLE characteristic ハンドリング
│   └── touch_input.h         # TTP223 入力（短押し/長押し検出）
├── README.md                 # arduino-cli セットアップ、ビルド・書き込み手順
├── THIRD_PARTY_NOTICES.md    # OpenGlass の MIT 表記
└── .gitignore
```

`.ino` だけで全部書く OpenGlass 流ではなく、**ヘッダで責務を分離**しておく。Phase 2 で音声・電池を足すときに見通しが良いため。

---

## 5. 開発環境セットアップ（arduino-cli）

OpenGlass の readme に従いつつ、ESP32 コアは新しめのバージョンを使う方針。

```powershell
# 1. arduino-cli インストール（既に持っているならスキップ）
winget install ArduinoSA.CLI

# 2. ESP32 ボードパッケージを追加
arduino-cli config init
arduino-cli config add board_manager.additional_urls `
  https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
arduino-cli core update-index
arduino-cli core install esp32:esp32@2.0.17

# 3. XIAO 接続確認
arduino-cli board list

# 4. ビルド＆書き込み（COMポート番号は環境ごとに置換）
arduino-cli compile -b esp32:esp32:XIAO_ESP32S3:PSRAM=opi,PartitionScheme=huge_app firmware/AIGlass
arduino-cli upload -p COM5 -b esp32:esp32:XIAO_ESP32S3 firmware/AIGlass
```

ESP32 コア **2.0.17** を使う理由：OpenGlassが動作確認済み、esp_camera ライブラリのABI互換のため。3.x系は破壊的変更があるので Phase 1 では避ける。

---

## 6. Phase 2 以降への布石

設計時点で意識すべき項目：

- **config.h に全部の数値定数を集約** — Phase 2 で間隔・コーデック・電池しきい値などが増えても1ファイルで管理
- **BLE characteristic は1関数1責務** — Photo Control のハンドラに撮影コマンド以外を入れない
- **タッチ入力は割り込みベース** — Phase 3 のディープスリープからの起床トリガに使うため、polling ではなく `attachInterrupt()` で実装
- **JPEG送信中の他処理ブロック問題** — OpenGlass は写真送信中に音声が止まる。Phase 2 で音声を入れるならキューイング設計を検討

---

## 7. アプリ側との結合ポイント（iOS）

Phase 1 で iOS アプリ側が実装するべきこと：

1. `a17ec1a5-...-0001` サービスを advertise しているデバイスをスキャン
2. 接続後、Photo Data に notify subscribe、Photo Control に `15` を書き込み（15秒間隔開始）
3. Photo Data の2バイトカウンタを使ってチャンクを連結、`0xFFFF` で1枚完成
4. JPEG を Core Data／ファイルシステムに保存
5. Claude API に投げて説明文を取得、画像と紐付けて保存
6. Touch Event の notify を受けたら「手動キャプチャ」フラグを立てる

このプロトコル仕様は `ios_app/` の README にも転載する予定（Phase 1着手時）。

---

## 8. やること（着手順）

1. [ ] firmware/ 配下にディレクトリとファイル骨格を作る（次のステップ）
2. [ ] OpenGlassの `camera_pins.h` と `mulaw.h` をコピー（MIT表記つき）
3. [ ] config.h に UUID、GPIO、撮影パラメータを定義
4. [ ] AIGlass.ino の setup() を空のまま書き、ビルドが通ることを確認
5. [ ] BLE 広告だけ動かして iPhone の nRF Connect で確認
6. [ ] カメラ初期化＋単発撮影、シリアル出力で確認
7. [ ] Photo Data Notify 送信を実装、iPhoneでJPEGとして保存できるか確認
8. [ ] Photo Control の Write を実装、間隔撮影が動くことを確認
9. [ ] TTP223 タッチ入力を実装、Touch Event が飛ぶことを確認

部品到着前にできるのは **1〜4** まで。実機が来てから 5以降に進む。
