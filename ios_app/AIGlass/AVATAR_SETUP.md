# 相棒アバター（VRM）セットアップ

相棒タブの上部に 3D アバターを表示します。VRoid Studio などで作った
`.vrm` モデルを、RealityKit（[VRMKit](https://github.com/tattn/VRMKit) /
VRMRealityKit）で **端末上・オフライン** で描画します。アバターは軽く揺れ・
まばたきし、相棒が読み上げる時に口パクします（`Speaker.isSpeaking` に連動）。

> コード（`AvatarView.swift`）は `#if canImport(VRMRealityKit)` で保護して
> あるので、パッケージ未追加でもアプリはビルドできます（プレースホルダ表示）。
> 下記 2 ステップを終えると本物のアバターに切り替わります。

---

## ステップ 1: VRMKit パッケージを追加（Xcode・1 回だけ）

1. Xcode で `AIGlass.xcodeproj` を開く
2. メニュー **File ▸ Add Package Dependencies…**
3. 右上の検索欄に URL を貼り付け:
   ```
   https://github.com/tattn/VRMKit
   ```
4. **Dependency Rule** はそのまま（Up to Next Major）→ **Add Package**
5. プロダクト選択ダイアログで、ターゲット **AIGlass** に対して
   - ✅ **VRMKit**
   - ✅ **VRMRealityKit**
   の 2 つを追加（VRMSceneKit は不要）→ **Add Package**

これでビルドすると `AvatarView` の本体（RealityKit 描画）が有効になります。

## ステップ 2: VRM モデルを追加

### VRoid Studio でモデルを用意
1. [VRoid Studio](https://vroid.com/studio)（無料）でアバターを作成
   （プリセットのままでも OK）
2. **エクスポート ▸ VRM** で書き出し
   - 安定版の **VRM 0.0** で書き出すのが無難（このコードは VRM0 前提で
     正面を向くよう 180° 回転させています）
   - 「VRM 1.0」で書き出して背を向く場合は、`AvatarView.swift` の
     `private let facing: Float = .pi` を `0` に変更
3. 書き出したファイルを **`model.vrm`** にリネーム

### Xcode に取り込む
1. `model.vrm` を Xcode のプロジェクトナビゲータ（AIGlass グループ）へドラッグ
2. ダイアログで
   - ✅ **Copy items if needed**
   - ✅ ターゲット **AIGlass** にチェック
3. 追加完了

ビルドして相棒タブを開くと、上部にアバターが表示され、相棒が話すと
口が動きます。`model.vrm` が無い間は「アバター未設定」のカードが出ます。

---

## 調整したいとき（`AvatarView.swift`）

| 見た目 | 変更箇所 |
|---|---|
| 顔の寄り（バストアップ↔全身） | `cam.look(at:from:)` の `from` の z（小さい=寄る）と `fieldOfViewInDegrees` |
| 正面を向かない | `facing`（`.pi` ↔ `0`） |
| 口パクの大きさ・速さ | `update` 内の `sin(time * 11)` と `* 0.8` |
| まばたき間隔 | `truncatingRemainder(dividingBy: 4.0)` |
| 表情（喜怒哀楽） | `setBlendShape(value:for: .preset(.joy/.angry/.sorrow/.fun))` |

将来: 回答の感情に合わせて表情 blendshape を切り替える、4090 の VOICEVOX
音声に口パクを同期する、などに拡張可能。
