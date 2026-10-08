#!/usr/bin/env python3
"""Generate ElevenLabs voiceovers for cutscene dialogue lines.

Requires ELEVENLABS_API_KEY in the environment. Writes MP3s under
assets/audio/voices/cut_*.mp3 and patches each cutscene JSON with matching
"voice" fields on every line.

    ELEVENLABS_API_KEY=... python3 tools/gen_cutscene_voices.py
"""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CUTSCENES = ROOT / "assets" / "cutscenes"
OUT = ROOT / "assets" / "audio" / "voices"

# Match the NPC cast; add Kaela + a calm narrator.
VOICES = {
    "N": "JBFqnCBsd6RMkjVDRZzb",  # George — warm storyteller
    "NARRATOR": "JBFqnCBsd6RMkjVDRZzb",
    "KAELA": "XrExE9yKIg1WjnnlVkGX",  # Matilda — young professional
    "GAIA": "KgpMz2JyZKU4VJVx35Pl",  # Ava — ethereal
    "VOSS": "TxWZERZ5Hc6h9dGxVmXa",  # Jerry B. — military
    "AETHERIAN": "SAz9YHcvj6GT2YYXdXww",  # River — otherworldly
    "ECHO-7": "SAz9YHcvj6GT2YYXdXww",
    "ARCHIVIST": "LvmvHEBEmMJBJw9UuhwO",  # Eldrin — wise
    "ASHA": "EXAVITQu4vr4xnSDxMaL",  # Sarah
}


def synthesize(api_key: str, voice_id: str, text: str, dest: Path) -> None:
    url = f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}"
    body = json.dumps(
        {
            "text": text,
            "model_id": "eleven_multilingual_v2",
            "voice_settings": {
                "stability": 0.42,
                "similarity_boost": 0.8,
                "style": 0.3,
                "use_speaker_boost": True,
            },
        }
    ).encode()
    req = urllib.request.Request(
        url,
        data=body,
        headers={
            "Accept": "audio/mpeg",
            "Content-Type": "application/json",
            "xi-api-key": api_key,
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = resp.read()
    if len(data) < 800:
        raise RuntimeError(f"short response for {dest.name}: {data[:200]!r}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)


def iter_lines(scene: dict):
    for pi, panel in enumerate(scene.get("panels") or []):
        raw = panel.get("lines") or []
        for li, line in enumerate(raw):
            if isinstance(line, str):
                yield pi, li, "N", line, True
            elif isinstance(line, dict):
                text = (line.get("text") or "").strip()
                if not text:
                    continue
                sp = line.get("speaker") or "N"
                yield pi, li, sp, text, False


def main() -> int:
    api_key = os.environ.get("ELEVENLABS_API_KEY", "").strip()
    if not api_key:
        print("Set ELEVENLABS_API_KEY", file=sys.stderr)
        return 1

    OUT.mkdir(parents=True, exist_ok=True)
    failures: list[str] = []
    generated = 0

    for path in sorted(CUTSCENES.glob("*/*.json")):
        scene = json.loads(path.read_text())
        scene_id = scene.get("id") or path.stem
        panels = scene.get("panels") or []
        changed = False

        for pi, li, speaker, text, was_string in iter_lines(scene):
            key = speaker.upper()
            voice_id = VOICES.get(key) or VOICES["N"]
            fname = f"cut_{scene_id}_p{pi + 1}_l{li + 1}.mp3"
            dest = OUT / fname
            rel = f"audio/voices/{fname}"

            # Normalize string lines into objects so we can attach voice.
            line_obj = panels[pi]["lines"][li]
            if was_string:
                line_obj = {"speaker": "N", "text": text}
                panels[pi]["lines"][li] = line_obj
                changed = True
            if line_obj.get("voice") != rel:
                line_obj["voice"] = rel
                changed = True

            try:
                synthesize(api_key, voice_id, text, dest)
                generated += 1
                print(f"OK {fname} ({dest.stat().st_size} bytes) [{speaker}]")
            except Exception as e:
                print(f"FAIL {fname}: {e}", file=sys.stderr)
                failures.append(fname)
            time.sleep(0.35)

        if changed:
            path.write_text(json.dumps(scene, indent=2, ensure_ascii=False) + "\n")
            print(f"patched {path.relative_to(ROOT)}")

    print(f"Done. generated={generated} failures={failures or 'none'}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
