# AI_glass server (outbound-pull architecture)

Inference is **pulled** by the worker, never pushed to it. This sidesteps the
corporate firewall on the 4090 PC (which blocks inbound) — the worker only makes
**outbound** connections to the hub.

```
iPhone ──(Tailscale, upload + poll)──► [M1 hub :8765] ◄──(Tailscale, outbound pull)── [4090 worker → Ollama]
```

| Component | Runs on | Tailscale IP | Role |
|---|---|---|---|
| `hub.py`    | personal M1 | 100.76.69.64 | job queue + media store + result API (no inference) |
| `worker.py` | 4090 PC     | 100.64.207.80 | pulls jobs, runs Ollama vision, posts captions back |
| iOS app     | iPhone      | 100.92.44.37 | uploads photo, polls caption |

## 1. Hub — on the personal M1

```bash
pip3 install fastapi "uvicorn[standard]" python-multipart
python3 hub.py            # listens on 0.0.0.0:8765, stores data in ~/aiglass-hub
```

If the macOS firewall blocks inbound, allow Python once (admin):
```bash
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode off
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add "$(which python3)"
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp "$(which python3)"
```

Keep the Mac awake while serving: `caffeinate -s python3 hub.py`.

## 2. Worker — on the 4090 PC

Ollama must be running locally with the vision model pulled:
```powershell
ollama pull qwen2.5vl:7b
# OLLAMA_HOST can stay 127.0.0.1:11434 (private) when the worker runs on the same PC
```
Then:
```powershell
python worker.py
```
Standard-library only — no pip install needed. It polls `http://100.76.69.64:8765`.

## 3. End-to-end test (from any tailnet device)

```bash
# upload a JPEG, get a job id
curl -F image=@test.jpg http://100.76.69.64:8765/jobs
# -> {"id":"<jid>","status":"pending"}

# a moment later, read the caption
curl http://100.76.69.64:8765/jobs/<jid>
# -> {"status":"done","result":"机の上にノートパソコンとコーヒーカップがある…"}
```

## Optional shared secret

Set the same `AIGLASS_TOKEN` on the hub, the worker, and (later) the iOS app to
require `Authorization: Bearer <token>`. The tailnet is already private, so this
is optional hardening.

## Future

The same hub/worker pattern extends to audio (Whisper) and faces (InsightFace +
a vector table); `kind` on a job selects the pipeline. Captions/transcripts/face
matches accumulate in the hub DB and feed the on-device companion chat (RAG).
