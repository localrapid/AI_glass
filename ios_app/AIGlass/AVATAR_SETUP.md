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
4. **Dependency Rule** を **Branch ▸ `main`** に変更 → **Add Package**
   - ⚠️ **VRM 1.0 対応と RealityKit 描画はまだタグ未リリース**（0.7.1 は
     VRM 0.x 専用で、本コードの `.v0/.v1` API も無くビルドできません）。
     必ず `main` ブランチを指定すること。
5. プロダクト選択ダイアログで、ターゲット **AIGlass** に対して
   - ✅ **VRMKit**
   - ✅ **VRMRealityKit**
   の 2 つを追加（VRMSceneKit は不要）→ **Add Package**

> このリポジトリの `project.pbxproj` は既に Branch `main` 参照に設定済み・
> `Package.resolved` も main にピン留め済みです。クローンして開いた場合は
> Xcode が自動で main を解決します。

これでビルドすると `AvatarView` の本体（RealityKit 描画）が有効になります。

## ステップ 2: VRM モデルを置く

`AIGlass` フォルダは **File System Synchronized Group** なので、
**`ios_app/AIGlass/AIGlass/model.vrm` にファイルを置くだけ**で Xcode が
自動的にアプリ（バンドルリソース）に取り込みます（ドラッグ不要）。

- VRoid Studio / VRoid Hub から落としたモデルが `.glb` 拡張子でも、中身が
  VRM（`VRMC_vrm` 拡張を持つ）なら **`model.vrm` にリネームするだけ**で OK。
- VRM **0.x / 1.0 どちらでも可**。正面向きはコードがバージョンを見て自動で
  合わせます（VRM0=180°回転 / VRM1=回転なし）。
- 別のモデルに差し替えたいときは `model.vrm` を置き換えるだけ。

> `model.vrm` は `.gitignore` 済み（VRoid モデルはライセンスがあり、サイズも
> 大きいため公開リポジトリには含めない）。

ビルドして相棒タブを開くと、上部にアバターが表示され、相棒が話すと
口が動きます。`model.vrm` が無い／読めない間は「アバター未設定」カードが出ます。

> ステップ 1（パッケージ追加）を終えていないと、`canImport(VRMRealityKit)`
> が false のままなので、モデルを置いても枠はプレースホルダ表示になります。

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
