#!/usr/bin/env python3
"""Loudness-normalize VO mp3s so dialogue levels match.

Target: -16 LUFS integrated, -1.5 dB true peak (speech / game dialogue).

Short ElevenLabs clips are often peaky: one syllable hits the ceiling while
the body stays quiet, so plain loudnorm (or peak-capped makeup gain) leaves
them soft. Pipeline:

  1. Mild acompressor — raise speech body vs peaks
  2. Iterative volume toward -16 LUFS
  3. Hard alimiter at ~-1.5 dB so nothing clips

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
# Acceptable band after normalize (integrated LUFS).
OK_LO, OK_HI = -17.5, -14.5
# alimiter limit≈10^(-1.5/20)
LIMIT = 0.84
MAX_ITERS = 5


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


def _encode(src: Path, dst: Path, af: str) -> None:
    r = _ffmpeg(
        "-i",
        str(src),
        "-af",
        af,
        "-ar",
        "44100",
        "-c:a",
        "libmp3lame",
        "-b:a",
        "128k",
        str(dst),
    )
    if r.returncode != 0 or not dst.exists() or dst.stat().st_size < 400:
        raise RuntimeError(f"encode failed for {src.name}: {r.stderr[-400:]}")


def normalize_file(path: Path) -> None:
    """Normalize [path] in place to ~-16 LUFS with speech-friendly dynamics."""
    path = path.resolve()
    if not path.is_file():
        raise FileNotFoundError(path)

    with tempfile.TemporaryDirectory(prefix="norm_vo_") as td:
        td_path = Path(td)
        work = td_path / "a.mp3"
        # Body up, peaks down — fixes short peaky cutscene lines.
        _encode(
            path,
            work,
            "acompressor=threshold=-18dB:ratio=3:attack=8:release=80:makeup=2:knee=6",
        )

        for n in range(MAX_ITERS):
            m = _measure(work)
            err = I - m["i"]
            out = td_path / f"b{n}.mp3"
            if abs(err) <= 1.0:
                # Final peak safety even when level is already close.
                _encode(
                    work,
                    out,
                    f"alimiter=limit={LIMIT}:attack=5:release=50:level_out={LIMIT}",
                )
                work = out
                break
            if err > 0:
                af = (
                    f"volume={err:.2f}dB,"
                    f"alimiter=limit={LIMIT}:attack=5:release=50:level_out={LIMIT}"
                )
            else:
                af = f"volume={err:.2f}dB"
            _encode(work, out, af)
            work = out

        work.replace(path)


def main(argv: list[str]) -> int:
    if len(argv) > 1:
        paths = [Path(a) for a in argv[1:]]
    else:
        paths = sorted(VOICES.glob("*.mp3"))
    if not paths:
        print("No mp3s to normalize", file=sys.stderr)
        return 1
    fails: list[str] = []
    bad: list[str] = []
    for p in paths:
        try:
            before = _measure(p)["i"]
            normalize_file(p)
            after = _measure(p)
            mark = "OK"
            if not (OK_LO <= after["i"] <= OK_HI):
                mark = "WIDE"
                bad.append(p.name)
            if after["tp"] > -0.5:
                mark = "CLIP"
                bad.append(p.name)
            print(
                f"{mark} {p.name:40s}  {before:7.2f} → {after['i']:7.2f} LUFS  "
                f"tp={after['tp']:5.2f}"
            )
        except Exception as e:
            print(f"FAIL {p.name}: {e}", file=sys.stderr)
            fails.append(p.name)
    print(f"Done. {len(paths) - len(fails)}/{len(paths)} ok; {len(set(bad))} outside band.")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
