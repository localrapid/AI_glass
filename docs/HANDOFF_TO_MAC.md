# 開発環境を Mac に引き継ぐためのチェックリスト

Windows で組んだ AI_glass プロジェクトを Mac に移し、以後 Mac の VS Code + Claude Code で開発を継続するための手順。iOS アプリ開発が Mac でしかできないため、ファームウェアごと一緒に引っ越す方が二重管理を避けられる。

---

## これまでの達成事項（2026-05-23 時点）

- **Phase 0**: 仕様確定・部品調達 ✅
- **Phase 1 step 1**: リポジトリ初期化 ✅
- **Phase 1 step 2**: OpenGlass 解析・FW設計 ✅
- **Phase 1 step 3**: 骨格ファイル群（config.h, ble_protocol.h, etc.） ✅
- **Phase 1 step 4**: ビルド検証＋実機書き込み＋シリアル起動確認 ✅
- **Phase 1 step 5**: BLE 広告（iPhone nRF Connect で `AI_glass` を発見・接続済み） ✅
- **Phase 1 step 6**: カメラ初期化＋10秒ごとのJPEGキャプチャ。30〜60KB / 枚 ✅
- **Phase 1 step 7**: JPEG を BLE Photo Data notify でチャンク送信（180B+2Bカウンタ、`0xFFFF`終端、`setMTU(517)`）。**iOSアプリで実機受信・画像表示までエンドツーエンド成功** ✅（2026-06-03）
- **iOSアプリ骨組み**: `ios_app/AIGlass/`（SwiftUI, Bundle `com.hisame.AIGlass`）。BLEManager がスキャン→自動接続→Photo Data購読→チャンク連結→UIImage化。撮影間隔ボタン（Photo Control書込）付き。実機ビルド・配備済み ✅
- **Phase 1 step 8**: Photo Control の Write をファーム側で実装。`-1`=単発撮影 / `0`=停止 / `1..120`=間隔(秒)。接続中のみ撮影（未接続は停止）。アプリのボタンが実際に撮影を制御 ✅（2026-06-03）
- **TTP223タッチの代替**: はんだ付け不可のため、当面アプリの「1枚」ボタン（Photo Control `-1`）を手動撮影トリガとして使う方針。TTP223実装（step 9）は保留 ✅
- **AI説明文（Claude API）**: `CaptionService.swift` が Haiku 4.5 にJPEG(base64)+日本語プロンプトを投げ説明文を取得。設定画面でAPIキー入力（UserDefaults保存、プロトタイプ用）＋自動生成トグル（既定OFF）。各写真に手動「説明生成」ボタン ✅
  - **コスト注意**: Claude API は **MAXプランとは別の従量課金**。Haiku 4.5 で約0.1円/枚。連続撮影で自動生成すると積み上がるため既定OFF。プロンプトキャッシュは画像が毎回変わるため無効。

**次にやること**: 受信画像＋説明文のローカル永続化（SwiftData等）。その後 Phase 4 のRAG/会話に向けてデータモデル設計。TTP223は基板化(Phase 3)のタイミングで再検討。

---

## ステップ1：Windowsで現状をパッケージ化

プロジェクトのルートディレクトリは：

```
c:\Users\0000400750\Documents\tools\AI_glass\
```

このフォルダごと **AI_glass.zip** に圧縮して、Mac に持っていく。

ZIP に含めるもの：
- `README.md`
- `docs/`（設計ドキュメント類）
- `firmware/`（実装中のArduinoスケッチ）
- `hardware/`、`ios_app/`（空フォルダ）

含めなくてよいもの：
- `firmware/build/`（あれば。`.gitignore` に入っている）

Claude のmemory（`C:\Users\0000400750\.claude\projects\...\memory\`）は **Mac 側で再構築する** 想定。memory の内容は Mac でも引き継げるが、新しい conversation のあるタイミングで Claude が自然に再記録する。**重要な決定事項は `docs/` に書いてあるので、memory が消えても困らない**。

---

## ステップ2：Mac側のツール準備

### 2-1. Homebrew（未インストールなら）

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 2-2. Claude Code

```bash
npm install -g @anthropic-ai/claude-code
```

`npm` が無ければ `brew install node` から。

### 2-3. arduino-cli（ファームウェア開発継続用）

```bash
brew install arduino-cli

arduino-cli config init
arduino-cli config add board_manager.additional_urls \
  https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
arduino-cli core update-index
arduino-cli core install esp32:esp32@2.0.17
```

### 2-4. Xcode（既にあり）

特に追加作業なし。Command Line Tools が入っていなければ：

```bash
xcode-select --install
```

### 2-5. VS Code + Claude Code 拡張

VS Code をインストール後、拡張機能から **Claude Code** を入れる。または ターミナルから `claude` コマンドで起動。

---

## ステップ3：プロジェクトを Mac で展開

```bash
mkdir -p ~/Documents/tools
cd ~/Documents/tools
unzip ~/Downloads/AI_glass.zip
cd AI_glass
ls
# README.md  docs/  firmware/  hardware/  ios_app/
```

---

## ステップ4：ファームウェアの疎通確認（Mac側）

XIAO を USB で Mac に接続：

```bash
arduino-cli board list
```

→ `/dev/cu.usbmodemXXXX` のような名前で出てくる。COM11 ではなく Mac 形式のデバイスパス。

ビルド：

```bash
cd ~/Documents/tools/AI_glass
arduino-cli compile \
  --fqbn esp32:esp32:XIAO_ESP32S3:PSRAM=opi,PartitionScheme=default_8MB \
  firmware/AIGlass
```

書き込み（ポートは実際の値に置き換え）：

```bash
arduino-cli upload \
  -p /dev/cu.usbmodem14201 \
  --fqbn esp32:esp32:XIAO_ESP32S3:PSRAM=opi,PartitionScheme=default_8MB \
  firmware/AIGlass
```

シリアル監視：

```bash
arduino-cli monitor -p /dev/cu.usbmodem14201 -c baudrate=115200
```

→ 期待出力：

```
==================================
AI_glass firmware booting
  device : AI_glass
  fw     : 0.1.0-phase1-step6
  board  : Seeed XIAO ESP32-S3 Sense
==================================
[BLE] init
[BLE] advertising as "AI_glass"
[CAM] init OK
[CAM] captured XXXXX bytes
```

ここまで動けば Windows と完全に等価な状態。

---

## ステップ5：Claude Code を起動して再開

```bash
cd ~/Documents/tools/AI_glass
claude
```

最初のプロンプトとして次のように伝えると、Claude Code が状況を即座に把握してくれる：

> AI_glass プロジェクトを Windows から Mac に引き継ぎました。
> `docs/HANDOFF_TO_MAC.md` と `README.md` を読んで現状を把握してください。
> 次は Phase 1 step 7（BLE経由でJPEG送信）と iOSアプリ骨組み開発です。

これで Mac での開発を継続できる。

---

## ステップ6：iOSアプリの着手

Xcode で新規プロジェクトを `ios_app/` 配下に作成：

```bash
cd ~/Documents/tools/AI_glass/ios_app
# Xcode → File → New → Project → iOS App
# Product Name: AIGlass
# 保存先: 今いるディレクトリ
```

その後の作業は Claude Code に任せられる：
- `xcodebuild -project AIGlass.xcodeproj -scheme AIGlass -destination 'platform=iOS,...' build` でビルド
- `xcrun simctl ...` でシミュレータ操作
- Swift ファイルの編集は Claude Code が直接

実機ビルドの初回のみ、Xcode GUI で Signing 設定（Personal Team の選択）が必要。

---

## 注意点

- **memory の再構築**: 最初のセッションで Claude が user/project memory を再作成する。ユーザの役割や決定事項は `docs/` から拾ってくれる
- **VS Code でファイル開く時の改行コード**: Windows で作った `.h`、`.cpp` ファイルは CRLF の可能性あり。実害は無いが、気になれば一括 LF 変換
- **Xcode の Bundle Identifier**: Apple ID の Personal Team では同じ Bundle ID を別人が使うと衝突する。`com.あなたの名前.aiglass` のようにユニークに
