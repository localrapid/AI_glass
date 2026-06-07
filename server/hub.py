#!/usr/bin/env python3
"""
AI_glass hub — runs on the personal M1 Mac.

A lightweight job queue + media store. The iPhone uploads a photo and creates a
"caption" job; the RTX 4090 worker pulls pending jobs (outbound only), runs the
vision model locally, and posts the result back; the iPhone polls the result.

Everything flows over Tailscale. The hub only needs to accept inbound from your
own tailnet devices, so it runs fine on a low-power machine — it does no
inference itself.

Run:
    pip3 install fastapi "uvicorn[standard]" python-multipart
    python3 hub.py                 # listens on 0.0.0.0:8765

Optional shared secret (set the SAME value on the worker and the iOS app):
    AIGLASS_TOKEN=somesecret python3 hub.py
"""

import os
import time
import uuid
import sqlite3
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, UploadFile, File, Form, Header, HTTPException, Request
from fastapi.responses import FileResponse, HTMLResponse
import uvicorn

DATA = Path(os.environ.get("AIGLASS_DATA", str(Path.home() / "aiglass-hub")))
MEDIA = DATA / "media"
DB = DATA / "hub.db"
TOKEN = os.environ.get("AIGLASS_TOKEN", "")  # empty = no auth (tailnet is already private)
PORT = int(os.environ.get("AIGLASS_PORT", "8765"))

MEDIA.mkdir(parents=True, exist_ok=True)


def db() -> sqlite3.Connection:
    con = sqlite3.connect(DB, timeout=30)
    con.execute(
        """CREATE TABLE IF NOT EXISTS jobs(
               id TEXT PRIMARY KEY,
               kind TEXT,
               status TEXT,          -- pending | processing | done | error
               created REAL,
               updated REAL,
               result TEXT,
               error TEXT
           )"""
    )
    # payload holds the prompt text for kind='chat' jobs (added later).
    try:
        con.execute("ALTER TABLE jobs ADD COLUMN payload TEXT")
    except sqlite3.OperationalError:
        pass  # column already exists
    return con


app = FastAPI(title="AI_glass hub")


def check(auth: Optional[str]) -> None:
    if TOKEN and auth != f"Bearer {TOKEN}":
        raise HTTPException(status_code=401, detail="bad or missing token")


@app.get("/health")
def health():
    return {"ok": True}


# --- iPhone -> hub ---------------------------------------------------------

@app.post("/jobs")
async def create_job(
    image: UploadFile = File(...),
    kind: str = Form("caption"),
    authorization: Optional[str] = Header(None),
):
    check(authorization)
    jid = uuid.uuid4().hex
    ext = "wav" if kind == "transcribe" else "jpg"
    (MEDIA / f"{jid}.{ext}").write_bytes(await image.read())
    now = time.time()
    # kind == "store": keep the image but don't queue it for captioning
    # (the iPhone uploads every photo for storage; captioning is opt-in).
    status = "stored" if kind == "store" else "pending"
    con = db()
    con.execute(
        "INSERT INTO jobs(id,kind,status,created,updated,result,error) VALUES(?,?,?,?,?,?,?)",
        (jid, kind, status, now, now, None, None),
    )
    con.commit()
    con.close()
    return {"id": jid, "status": status}


@app.post("/ask")
def ask(payload: dict, authorization: Optional[str] = Header(None)):
    """Companion chat (kind='chat'). The iPhone sends a question + already-
    retrieved lifelog context; the 4090 worker generates the answer with the
    big model. Returns a job id the app polls via GET /jobs/{id}."""
    check(authorization)
    question = (payload.get("question") or "").strip()
    context = (payload.get("context") or "").strip()
    prompt = f"# これまでのログ\n{context if context else '（記録なし）'}\n\n# 質問\n{question}"
    jid = uuid.uuid4().hex
    now = time.time()
    con = db()
    con.execute(
        "INSERT INTO jobs(id,kind,status,created,updated,result,error,payload) VALUES(?,?,?,?,?,?,?,?)",
        (jid, "chat", "pending", now, now, None, None, prompt),
    )
    con.commit()
    con.close()
    return {"id": jid, "status": "pending"}


@app.post("/speak")
def speak(payload: dict, authorization: Optional[str] = Header(None)):
    """Companion voice (kind='tts'). The iPhone sends answer text; the 4090
    worker synthesizes it with VOICEVOX and uploads a WAV. Returns a job id the
    app polls via GET /jobs/{id}, then downloads GET /jobs/{id}/audio."""
    check(authorization)
    text = (payload.get("text") or "").strip()
    if not text:
        raise HTTPException(400, "empty text")
    jid = uuid.uuid4().hex
    now = time.time()
    con = db()
    con.execute(
        "INSERT INTO jobs(id,kind,status,created,updated,result,error,payload) VALUES(?,?,?,?,?,?,?,?)",
        (jid, "tts", "pending", now, now, None, None, text),
    )
    con.commit()
    con.close()
    return {"id": jid, "status": "pending"}


@app.post("/jobs/{jid}/recaption")
def recaption(jid: str, authorization: Optional[str] = Header(None)):
    """Re-queue an already-stored photo for captioning."""
    check(authorization)
    con = db()
    con.execute(
        "UPDATE jobs SET kind='caption',status='pending',updated=? WHERE id=?",
        (time.time(), jid),
    )
    con.commit()
    con.close()
    return {"id": jid, "status": "pending"}


@app.get("/jobs/{jid}")
def get_job(jid: str, authorization: Optional[str] = Header(None)):
    check(authorization)
    con = db()
    row = con.execute(
        "SELECT id,kind,status,created,updated,result,error FROM jobs WHERE id=?", (jid,)
    ).fetchone()
    con.close()
    if not row:
        raise HTTPException(404, "no such job")
    keys = ["id", "kind", "status", "created", "updated", "result", "error"]
    return dict(zip(keys, row))


@app.get("/jobs")
def list_jobs(limit: int = 50, authorization: Optional[str] = Header(None)):
    check(authorization)
    con = db()
    rows = con.execute(
        "SELECT id,kind,status,created,result FROM jobs ORDER BY created DESC LIMIT ?",
        (limit,),
    ).fetchall()
    con.close()
    keys = ["id", "kind", "status", "created", "result"]
    return [dict(zip(keys, r)) for r in rows]


# --- 4090 worker <-> hub (outbound from the worker) ------------------------

@app.get("/jobs/next/claim")
def claim_next(authorization: Optional[str] = Header(None)):
    """Worker pulls the oldest pending job and marks it processing. {} if none."""
    check(authorization)
    con = db()
    row = con.execute(
        "SELECT id,kind,payload FROM jobs WHERE status='pending' AND kind IN ('caption','transcribe','chat','tts') ORDER BY created LIMIT 1"
    ).fetchone()
    if not row:
        con.close()
        return {}
    jid, kind, payload = row
    con.execute("UPDATE jobs SET status='processing',updated=? WHERE id=?", (time.time(), jid))
    con.commit()
    con.close()
    return {"id": jid, "kind": kind, "payload": payload}


@app.get("/jobs/{jid}/image")
def get_image(jid: str, authorization: Optional[str] = Header(None)):
    check(authorization)
    p = MEDIA / f"{jid}.jpg"
    if not p.exists():
        raise HTTPException(404, "no image")
    return FileResponse(p, media_type="image/jpeg")


@app.get("/jobs/{jid}/audio")
def get_audio(jid: str, authorization: Optional[str] = Header(None)):
    check(authorization)
    p = MEDIA / f"{jid}.wav"
    if not p.exists():
        raise HTTPException(404, "no audio")
    return FileResponse(p, media_type="audio/wav")


@app.post("/jobs/{jid}/result_audio")
async def post_result_audio(jid: str, request: Request, authorization: Optional[str] = Header(None)):
    """Worker uploads synthesized WAV bytes (raw body) for a 'tts' job."""
    check(authorization)
    data = await request.body()
    (MEDIA / f"{jid}.wav").write_bytes(data)
    con = db()
    con.execute(
        "UPDATE jobs SET status='done',result=?,updated=? WHERE id=?",
        ("(audio)", time.time(), jid),
    )
    con.commit()
    con.close()
    return {"ok": True, "bytes": len(data)}


@app.post("/jobs/{jid}/result")
async def post_result(jid: str, payload: dict, authorization: Optional[str] = Header(None)):
    check(authorization)
    con = db()
    if payload.get("error"):
        con.execute(
            "UPDATE jobs SET status='error',error=?,updated=? WHERE id=?",
            (str(payload["error"]), time.time(), jid),
        )
    else:
        con.execute(
            "UPDATE jobs SET status='done',result=?,updated=? WHERE id=?",
            (payload.get("result", ""), time.time(), jid),
        )
    con.commit()
    con.close()
    return {"ok": True}


@app.get("/gallery", response_class=HTMLResponse)
def gallery(limit: int = 100):
    """Simple browsable page pairing each photo with its caption."""
    con = db()
    rows = con.execute(
        "SELECT id,status,created,result FROM jobs ORDER BY created DESC LIMIT ?", (limit,)
    ).fetchall()
    con.close()
    cards = []
    for jid, status, created, result in rows:
        ts = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(created or 0))
        cap = (result or ("（未生成）" if status != "done" else "")) or ""
        cards.append(
            f'<div class="c"><img loading="lazy" src="/jobs/{jid}/image">'
            f'<div class="t">{ts} ・ {status}</div><div class="cap">{cap}</div></div>'
        )
    html = (
        "<!doctype html><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'>"
        "<title>AI_glass gallery</title><style>"
        "body{font-family:-apple-system,sans-serif;margin:0;background:#111;color:#eee}"
        ".g{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:12px;padding:12px}"
        ".c{background:#1c1c1e;border-radius:12px;overflow:hidden}"
        ".c img{width:100%;display:block;aspect-ratio:4/3;object-fit:cover}"
        ".t{font:12px monospace;color:#888;padding:6px 10px 0}"
        ".cap{padding:4px 10px 10px;font-size:14px;line-height:1.4}"
        "</style><h2 style=padding:12px>AI_glass gallery</h2>"
        f"<div class=g>{''.join(cards)}</div>"
    )
    return HTMLResponse(html)


if __name__ == "__main__":
    print(f"AI_glass hub on 0.0.0.0:{PORT}  data={DATA}  auth={'on' if TOKEN else 'off'}")
    uvicorn.run(app, host="0.0.0.0", port=PORT)
