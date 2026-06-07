#!/usr/bin/env python3
"""
Make a VRoid Studio VRM 1.0 export loadable by VRMKit (main branch).

VRoid Studio 2.3.0 omits some fields that VRMKit's (currently strict) VRM 1.0
decoder treats as required, so loading fails with errors like
`keyNotFound("meshAnnotations")` or `keyNotFound("lookUp")`. This script injects
the missing-but-harmless fields in place:

  * extensions.VRMC_vrm.firstPerson.meshAnnotations  -> []  (if missing)
  * extensions.VRMC_vrm.expressions.preset.<all 18>   -> {}  (each missing one)

An empty Expression {} is valid (every field is optional), so this changes
nothing visually — it just satisfies the decoder.

Usage:
    python3 fix_vrm.py path/to/export.vrm  [output.vrm]
    # default output: the AIGlass bundle's model.vrm

Alternative: export from VRoid Studio as **VRM 0.0** instead — VRMKit's VRM0
decoder is mature and needs no patching.
"""
import json
import struct
import sys
from pathlib import Path

PRESETS = ["happy", "angry", "sad", "relaxed", "surprised",
           "aa", "ih", "ou", "ee", "oh",
           "blink", "blinkLeft", "blinkRight",
           "lookUp", "lookDown", "lookLeft", "lookRight", "neutral"]


def fix(src: Path, dst: Path) -> None:
    d = bytearray(src.read_bytes())
    if d[:4] != b"glTF":
        raise SystemExit(f"{src} is not a GLB/VRM binary")
    json_len = struct.unpack("<I", d[12:16])[0]
    head = json.loads(bytes(d[20:20 + json_len]))
    tail = bytes(d[20 + json_len:])          # BIN chunk (unchanged)

    vrm = head.get("extensions", {}).get("VRMC_vrm")
    if vrm is None:
        raise SystemExit("No VRMC_vrm extension — is this a VRM 1.0 file? "
                         "(VRM 0.x needs no patching.)")

    fixes = []
    fp = vrm.setdefault("firstPerson", {})
    if "meshAnnotations" not in fp:
        fp["meshAnnotations"] = []
        fixes.append("firstPerson.meshAnnotations")
    preset = vrm.setdefault("expressions", {}).setdefault("preset", {})
    missing = [k for k in PRESETS if k not in preset]
    for k in missing:
        preset[k] = {}
    if missing:
        fixes.append("expressions.preset += " + ", ".join(missing))

    if not fixes:
        print("Already loadable — nothing to fix.")

    nj = json.dumps(head, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    nj += b" " * ((4 - len(nj) % 4) % 4)      # 4-byte align with spaces
    out = bytearray(struct.pack("<4sII", b"glTF", 2, 0))
    out += struct.pack("<I4s", len(nj), b"JSON")
    out += nj + tail
    struct.pack_into("<I", out, 8, len(out))  # total length
    dst.write_bytes(out)
    print(f"Fixed: {', '.join(fixes) or '(no changes)'}")
    print(f"Wrote {dst} ({len(out)} bytes)")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    src = Path(sys.argv[1]).expanduser()
    default_dst = Path(__file__).resolve().parent.parent / "AIGlass" / "model.vrm"
    dst = Path(sys.argv[2]).expanduser() if len(sys.argv) > 2 else default_dst
    fix(src, dst)
