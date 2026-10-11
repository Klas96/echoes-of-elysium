#!/usr/bin/env python3
"""Loudness-normalize VO mp3s so dialogue levels match.

Target: -16 LUFS integrated, -1.5 dB true peak (speech / game dialogue).

Uses single-pass loudnorm (two-pass linear mode crushes short ElevenLabs
clips). If a file is still far below target, applies a peak-safe makeup gain.

    python3 tools/normalize_voices.py              # all assets/audio/voices/*.mp3
    python3 tools/normalize_voices.py path.mp3     # one file in place

Used by gen_npc_voices / gen_cutscene_voices after each synthesize.
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VOICES = ROOT / "assets" / "audio" / "voices"

I, TP, LRA = -16.0, -1.5, 11.0
# After loudnorm, re-boost if still quieter than this (short clips).
MIN_OK_LUFS = -19.0
MAX_PEAK_DB = -1.5


def _ffmpeg(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["ffmpeg", "-hide_banner", "-nostats", "-y", *args],
        capture_output=True,
        text=True,
        check=False,
    )


def _measure(path: Path) -> dict[str, float]:
    r = _ffmpeg(
        "-i",
        str(path),
        "-af",
        f"loudnorm=I={I}:TP={TP}:LRA={LRA}:print_format=json",
        "-f",
        "null",
        "-",
    )
    err = r.stderr
    start, end = err.rfind("{"), err.rfind("}")
    if start < 0 or end < 0:
        raise RuntimeError(f"loudnorm measure failed for {path.name}: {err[-400:]}")
    j = json.loads(err[start : end + 1])
    return {
        "i": float(j["input_i"]),
        "tp": float(j["input_tp"]),
        "lra": float(j["input_lra"]),
        "thresh": float(j["input_thresh"]),
    }


def _encode(path: Path, af: str) -> None:
    with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as tmp:
        out = Path(tmp.name)
    try:
        r = _ffmpeg(
            "-i",
            str(path),
            "-af",
            af,
            "-c:a",
            "libmp3lame",
            "-b:a",
            "128k",
            str(out),
        )
        if r.returncode != 0 or not out.exists() or out.stat().st_size < 400:
            raise RuntimeError(f"encode failed for {path.name}: {r.stderr[-400:]}")
        out.replace(path)
    finally:
        if out.exists() and out != path:
            out.unlink(missing_ok=True)


def normalize_file(path: Path) -> None:
    """Normalize [path] in place to ~-16 LUFS."""
    path = path.resolve()
    if not path.is_file():
        raise FileNotFoundError(path)

    # Single-pass loudnorm — stable on short VO.
    _encode(path, f"loudnorm=I={I}:TP={TP}:LRA={LRA}")

    m = _measure(path)
    if m["i"] >= MIN_OK_LUFS:
        return

    # Short / sparse clips: loudnorm under-shoots. Makeup gain capped by peak.
    gain = I - m["i"]
    headroom = MAX_PEAK_DB - m["tp"]
    if headroom < 0.25:
        return  # already near peak ceiling
    gain = min(gain, headroom)
    if gain < 0.5:
        return
    _encode(path, f"volume={gain:.2f}dB")


def main(argv: list[str]) -> int:
    if len(argv) > 1:
        paths = [Path(a) for a in argv[1:]]
    else:
        paths = sorted(VOICES.glob("*.mp3"))
    if not paths:
        print("No mp3s to normalize", file=sys.stderr)
        return 1
    fails: list[str] = []
    for p in paths:
        try:
            before = _measure(p)["i"]
            normalize_file(p)
            after = _measure(p)["i"]
            print(f"OK {p.name:40s}  {before:7.2f} → {after:7.2f} LUFS")
        except Exception as e:
            print(f"FAIL {p.name}: {e}", file=sys.stderr)
            fails.append(p.name)
    print(f"Done. {len(paths) - len(fails)}/{len(paths)} ok.")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
