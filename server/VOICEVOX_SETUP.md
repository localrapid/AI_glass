# 相棒の声を VOICEVOX（4090）にする

相棒の回答を、4090 上の [VOICEVOX](https://voicevox.hys) キャラクター音声で読み上げ、
アバターの口パクを**実際の音声波形に同期**させます。アウトバウンドpull構成のまま：

```
iPhone ──/speak(text)──▶ M1 hub ──(tts job)──▶ 4090 worker
                                                   │ VOICEVOX 合成
iPhone ◀──/jobs/{id}/audio (WAV)── M1 hub ◀──result_audio─┘
```

電話は 4090 に直接触らず、hub 経由で WAV を受け取って再生します。

## 1. 4090 で VOICEVOX エンジンを起動

- [VOICEVOX 公式](https://voicevox.hiroshiba.jp/) から **VOICEVOX** をダウンロードして起動
  （GUI を起動するとエンジンも `127.0.0.1:50021` で立ち上がります）。
- または軽量な **VOICEVOX ENGINE** 単体／Docker でも可:
  ```
  docker run --rm -p 127.0.0.1:50021:50021 voicevox/voicevox_engine:nemo-cuda-latest
  ```
- 確認:
  ```
  curl http://127.0.0.1:50021/version
  curl http://127.0.0.1:50021/speakers   # 話者一覧（id を確認できる）
  ```

## 2. worker を起動（VOICEVOX 設定を渡す）

`worker.py` は `tts` ジョブを自動で処理します。話者は環境変数で指定:

```
AIGLASS_HUB=http://100.76.69.64:8765 \
OLLAMA_URL=http://localhost:11434 \
VOICEVOX_URL=http://127.0.0.1:50021 \
AIGLASS_VOICEVOX_SPEAKER=8 \
python worker.py
```

- `AIGLASS_VOICEVOX_SPEAKER`（既定 **8**）… 話者 id。例: 3=ずんだもん(ノーマル)、
  2=四国めたん(ノーマル)、**8=春日部つむぎ（若い女性・フランク）**。
  `/speakers` の `styles[].id` から選ぶ。
- `AIGLASS_VOICEVOX_SPEED`（既定 1.0）… 話速。

## 3. iPhone 側

設定 ▸「相棒の声を4090のVOICEVOXにする（家にいる時）」を ON（既定 ON）。
家（hub に到達できる時）は VOICEVOX 音声、外出時や VOICEVOX 停止中は自動で
端末音声にフォールバックします。アバターは VOICEVOX 再生中はその音量に合わせて
口が動きます。

> モデルを変えたいだけなら `AIGLASS_VOICEVOX_SPEAKER` を変えて worker を再起動。
> 抑揚や音量は `audio_query` の `intonationScale` / `volumeScale` を worker の
> `tts()` で調整可能（今は speedScale のみ適用）。
