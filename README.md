# AI_glass

ディスプレイのない、自分専用のAI相棒を育てるための眼鏡デバイス。

## ビジョン

カメラとマイクを搭載した眼鏡が日常を吸い、スマホ＋クラウドAIがそれを長期記憶に変換していく。最終形は **「自分の生活を非常によく知っているAI相棒」と、テキスト・音声で雑談・相談できる** こと。

ライフログは目的ではなく素材。アプリの主役は閲覧UIではなく **会話インターフェース＋RAG** 。

### 想定ユースケース

- 「昨日コンビニで何買ったっけ」
- 「あの人だれだっけ（先週紹介された人）」
- 「家を出るとき鍵持ってた?」
- 「今日変だったこと、なんかなかった?」
- 「最近の自分、疲れてる?」（メタ視点でのフィードバック）

## システム構成

```
[眼鏡デバイス]                    [iPhoneアプリ]              [クラウド]
 XIAO ESP32-S3 Sense              SwiftUI / SwiftData          Claude API
 + OV2640 カメラ      ─ BLE/WiFi ─▶ Core Bluetooth     ─ HTTPS ─▶ Whisper API
 + PDM マイク                     ローカル画像/音声DB
 + 静電タッチセンサ                会話UI + RAG
 + LiPo 200-300mAh                ベクトル検索
```

## フェーズ計画

| Phase | 目標 | 状態 |
|-------|------|------|
| 0 | 仕様確定・部品調達 | 進行中 |
| 1 | XIAO + iPhone で 15秒ごとの画像キャプチャ → Claude 説明文 | 未着手 |
| 2 | 音声録音 + Whisper + 1日サマリ + 手動撮影ボタン | 未着手 |
| 3 | カスタムPCB + 3Dプリント筐体でフレーム化 | 未着手 |
| 4 | 会話UI + RAG（過去の出来事を引いて答える相棒） | 未着手 |
| 5 | 仕上げ（OTA, 防滴, βテスト） | 未着手 |

## ディレクトリ構成

- [firmware/](firmware/) — XIAO ESP32-S3 用ファームウェア（PlatformIO/Arduino）
- [ios_app/](ios_app/) — iOS アプリ（SwiftUI + Core Bluetooth）
- [hardware/](hardware/) — 回路図、BOM、3Dモデル
- [docs/](docs/) — 設計メモ、決定事項、参考資料
  - [docs/PARTS_LIST.md](docs/PARTS_LIST.md) — Phase 1 用部品リスト

## 主要な決定事項

- 撮影トリガ：自動（15秒間隔から開始）＋ テンプル静電タッチによる手動
- AI処理：クラウド全振り（Claude / Whisper）
- 対応OS：iOSのみ
- HW出発点：Seeed XIAO ESP32-S3 Sense
- プライバシー：プロトタイプでは録画LED・撮影音なし

## 参考プロジェクト

- [OpenGlass](https://github.com/BasedHardware/OpenGlass) — 同じく XIAO ESP32-S3 ベースのOSS AIグラス（**現在はアーカイブ、Omiに統合**）。HW構成・ファームウェアは直接参考にできる。アプリはReact Native実装なので我々のiOSネイティブ方針とは別物
- [Omi](https://github.com/BasedHardware/omi) — OpenGlassの後継。音声寄りライフロガー
- [Brilliant Labs Frame](https://brilliant.xyz/) — ディスプレイ付きOSS AIグラス
