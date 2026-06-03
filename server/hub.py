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

from fastapi import FastAPI, UploadFile, File, Form, Header, HTTPException
from fastapi.responses import FileResponse
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
    return con


app = FastAPI(title="AI_glass hub")


def check(auth: str | None) -> None:
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
    authorization: str | None = Header(None),
):
    check(authorization)
    jid = uuid.uuid4().hex
    (MEDIA / f"{jid}.jpg").write_bytes(await image.read())
    now = time.time()
    con = db()
    con.execute(
        "INSERT INTO jobs(id,kind,status,created,updated,result,error) VALUES(?,?,?,?,?,?,?)",
        (jid, kind, "pending", now, now, None, None),
    )
    con.commit()
    con.close()
    return {"id": jid, "status": "pending"}


@app.get("/jobs/{jid}")
def get_job(jid: str, authorization: str | None = Header(None)):
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
def list_jobs(limit: int = 50, authorization: str | None = Header(None)):
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
def claim_next(authorization: str | None = Header(None)):
    """Worker pulls the oldest pending job and marks it processing. {} if none."""
    check(authorization)
    con = db()
    row = con.execute(
        "SELECT id,kind FROM jobs WHERE status='pending' ORDER BY created LIMIT 1"
    ).fetchone()
    if not row:
        con.close()
        return {}
    jid, kind = row
    con.execute("UPDATE jobs SET status='processing',updated=? WHERE id=?", (time.time(), jid))
    con.commit()
    con.close()
    return {"id": jid, "kind": kind}


@app.get("/jobs/{jid}/image")
def get_image(jid: str, authorization: str | None = Header(None)):
    check(authorization)
    p = MEDIA / f"{jid}.jpg"
    if not p.exists():
        raise HTTPException(404, "no image")
    return FileResponse(p, media_type="image/jpeg")


@app.post("/jobs/{jid}/result")
async def post_result(jid: str, payload: dict, authorization: str | None = Header(None)):
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


if __name__ == "__main__":
    print(f"AI_glass hub on 0.0.0.0:{PORT}  data={DATA}  auth={'on' if TOKEN else 'off'}")
    uvicorn.run(app, host="0.0.0.0", port=PORT)
