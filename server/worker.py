#!/usr/bin/env python3
"""
AI_glass inference worker — runs on the RTX 4090 PC.

OUTBOUND ONLY. Polls the M1 hub for pending jobs, downloads the photo, runs the
local Ollama vision model, and posts the caption back. Because it only makes
outbound connections, it works behind the corporate firewall that blocks
inbound — no port forwarding, no Tailscale serve, no WSL networking needed.

Standard library only — no `pip install` required.

Run (PowerShell or WSL on the 4090):
    python worker.py

Config via env vars (defaults shown):
    AIGLASS_HUB   = http://100.76.69.64:8765     # the M1 hub's Tailscale address
    OLLAMA_URL    = http://localhost:11434       # local Ollama on the 4090
    AIGLASS_MODEL = qwen3-vl:8b   (must be pulled first: `ollama pull qwen3-vl:8b`)
    AIGLASS_TOKEN =                              # must match the hub if set
    AIGLASS_POLL  = 1.5                          # seconds between polls when idle
"""

import os
import json
import time
import base64
import wave
import array
import tempfile
import urllib.request
import urllib.error

def _normalize(url: str) -> str:
    url = url.rstrip("/")
    if not url.startswith(("http://", "https://")):
        url = "http://" + url  # tolerate AIGLASS_HUB=host:port without a scheme
    return url


HUB = _normalize(os.environ.get("AIGLASS_HUB", "http://100.76.69.64:8765"))
OLLAMA = _normalize(os.environ.get("OLLAMA_URL", "http://localhost:11434"))
MODEL = os.environ.get("AIGLASS_MODEL", "qwen3-vl:8b")
TOKEN = os.environ.get("AIGLASS_TOKEN", "")
POLL = float(os.environ.get("AIGLASS_POLL", "1.5"))
# Whisper (audio). Requires `pip install faster-whisper`; loaded lazily so the
# photo-only path needs no extra deps.
WHISPER_MODEL = os.environ.get("AIGLASS_WHISPER_MODEL", "large-v3")
WHISPER_DEVICE = os.environ.get("AIGLASS_WHISPER_DEVICE", "cuda")
WHISPER_COMPUTE = os.environ.get("AIGLASS_WHISPER_COMPUTE", "float16")
_whisper = None

AUTH = {"Authorization": f"Bearer {TOKEN}"} if TOKEN else {}

PROMPT = (
    "次の写真の内容を日本語で説明してください。"
    "条件: 1〜2文。写っている人・物・場所・行動を具体的に。"
    "認識できるキャラクター・商品・ロゴ・店舗・地名などの固有名は、確信があれば具体名で述べる"
    "（例: 単に『ウサギのキャラクター』ではなく、分かれば『ミッフィー』と名前を出す）。確信が無ければ一般名で。"
    "禁止: 「この画像は」「画像には」「写真には」などの前置き。説明本文だけを出力。"
)

# Safety net: strip leading boilerplate the 7B model sometimes adds anyway.
_PREFIXES = ("この画像は", "この画像には", "画像には", "画像は",
             "写真には", "この写真は", "この写真には")


def _clean(text: str) -> str:
    t = text.strip()
    for p in _PREFIXES:
        if t.startswith(p):
            t = t[len(p):].lstrip("、,　 ")
            break
    return t


def _get_json(url, timeout=15):
    req = urllib.request.Request(url, headers=AUTH)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read() or b"null")


def _get_bytes(url, timeout=30):
    req = urllib.request.Request(url, headers=AUTH)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def _post_json(url, payload, timeout=180):
    data = json.dumps(payload).encode()
    headers = {"Content-Type": "application/json", **AUTH}
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read() or b"null")


def caption(jpeg: bytes) -> str:
    b64 = base64.b64encode(jpeg).decode()
    out = _post_json(
        f"{OLLAMA}/api/generate",
        {"model": MODEL, "prompt": PROMPT, "images": [b64], "stream": False},
    )
    return _clean(out.get("response") or "")


def _load_whisper():
    global _whisper
    if _whisper is None:
        from faster_whisper import WhisperModel  # lazy import
        print(f"[worker] loading Whisper {WHISPER_MODEL} ({WHISPER_DEVICE}/{WHISPER_COMPUTE})…")
        _whisper = WhisperModel(WHISPER_MODEL, device=WHISPER_DEVICE, compute_type=WHISPER_COMPUTE)
    return _whisper


def _preprocess_wav(path: str) -> str:
    """PDM mics output a large DC bias and a quiet signal. Remove the DC offset
    and normalize the level so Whisper actually hears the speech."""
    w = wave.open(path, "rb")
    sr, n = w.getframerate(), w.getnframes()
    samples = array.array("h")
    samples.frombytes(w.readframes(n))
    w.close()
    if not samples:
        return path

    dc = sum(samples) / len(samples)
    vals = [x - dc for x in samples]
    peak = max((abs(v) for v in vals), default=0)
    gain = min(0.6 * 32767 / peak, 60.0) if peak > 0 else 1.0
    out = array.array(
        "h", (int(max(-32768, min(32767, v * gain))) for v in vals)
    )
    print(f"[worker]   audio dc={dc:.0f} peak={peak} gain={gain:.1f}x")

    op = path + ".pp.wav"
    ow = wave.open(op, "wb")
    ow.setnchannels(1)
    ow.setsampwidth(2)
    ow.setframerate(sr)
    ow.writeframes(out.tobytes())
    ow.close()
    return op


def transcribe(wav_path: str) -> str:
    model = _load_whisper()
    pp = _preprocess_wav(wav_path)
    try:
        # vad_filter off: clips are short and may be quiet — let Whisper try all.
        segments, _info = model.transcribe(pp, language="ja", vad_filter=False)
        return "".join(seg.text for seg in segments).strip()
    finally:
        if pp != wav_path:
            try:
                os.remove(pp)
            except OSError:
                pass


def main():
    print(f"[worker] hub={HUB} ollama={OLLAMA} model={MODEL} auth={'on' if TOKEN else 'off'}")
    # Fail fast if Ollama isn't reachable.
    try:
        tags = _get_json(f"{OLLAMA}/api/tags")
        print("[worker] ollama models:", [m.get("name") for m in tags.get("models", [])])
    except Exception as e:
        print("[worker] WARNING: cannot reach Ollama:", e)

    while True:
        try:
            job = _get_json(f"{HUB}/jobs/next/claim")
        except Exception as e:
            print("[worker] hub poll error:", e)
            time.sleep(3)
            continue

        if not job:
            time.sleep(POLL)
            continue

        jid = job["id"]
        kind = job.get("kind")
        print(f"[worker] job {jid} ({kind})")
        try:
            if kind == "transcribe":
                wav = _get_bytes(f"{HUB}/jobs/{jid}/audio")
                tmp = os.path.join(tempfile.gettempdir(), f"aiglass_{jid}.wav")
                with open(tmp, "wb") as f:
                    f.write(wav)
                try:
                    text = transcribe(tmp)
                finally:
                    try:
                        os.remove(tmp)
                    except OSError:
                        pass
            else:
                img = _get_bytes(f"{HUB}/jobs/{jid}/image")
                text = caption(img)
            _post_json(f"{HUB}/jobs/{jid}/result", {"result": text})
            print(f"[worker]   -> {text[:70]}")
        except Exception as e:
            print(f"[worker]   error: {e}")
            try:
                _post_json(f"{HUB}/jobs/{jid}/result", {"error": str(e)})
            except Exception:
                pass


if __name__ == "__main__":
    main()
