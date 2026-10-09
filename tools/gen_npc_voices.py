#!/usr/bin/env python3
"""Generate ElevenLabs VO for NPC dialogue lines that currently lack audio.

    ELEVENLABS_API_KEY=... python3 tools/gen_npc_voices.py
"""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "audio" / "voices"

VOICES = {
    "gaia": "KgpMz2JyZKU4VJVx35Pl",  # Ava
    "asha": "EXAVITQu4vr4xnSDxMaL",  # Sarah
    "echo7": "SAz9YHcvj6GT2YYXdXww",  # River
    "archivist": "LvmvHEBEmMJBJw9UuhwO",  # Eldrin
    "voss": "TxWZERZ5Hc6h9dGxVmXa",  # Jerry B.
    "mira": "XrExE9yKIg1WjnnlVkGX",  # Matilda
}

# filename stem -> (voice_key, text)
LINES: dict[str, tuple[str, str]] = {
    # Echo-7 (rewritten)
    "echo7_1": (
        "echo7",
        "Traveller... you carry the resonance of one who seeks. We have waited ten thousand years for such a signal.",
    ),
    "echo7_2": (
        "echo7",
        "Do not picture us asleep in tombs. We merged into Gaia — minds in the lattice, bodies returned to the soil — so a dying sun could not erase us.",
    ),
    "echo7_3": (
        "echo7",
        "Not all of us chose freely. Some were afraid. Help Gaia remember the peace and the fear — or do not remember us at all.",
    ),
    "echo7_fear": (
        "echo7",
        "The vote was a whisper. Peace won — barely. Remember both, or you remember a lie.",
    ),
    "echo7_promise": (
        "echo7",
        "Then walk with open eyes. The Archivist holds a seal you may need.",
    ),
    # Archivist — first meeting
    "archivist_1": (
        "archivist",
        "The Core Record is Gaia's first memory: the day we voted to merge into her lattice. Bodies rested. Minds took root. That is why your people say we slept.",
    ),
    "archivist_2": (
        "archivist",
        "Commander Voss seeks to delete it. He believes waking her will kill your colony the way Station Seven died.",
    ),
    "archivist_3": (
        "archivist",
        "Your neural signature matches the Aetherian activation code, Kaela. Only you can open the Core — and decide what truth he hears.",
    ),
    "archivist_3_seal": (
        "archivist",
        "The library seal is yours. Read the draft of that vote — then decide what Voss hears.",
    ),
    "archivist_seal_give": (
        "archivist",
        "Take it. The library faces this avenue. Inside is the draft of our first memory — not the Core, but the argument that made it.",
    ),
    "archivist_s7": (
        "archivist",
        "Your coalition woke a lattice without consent. We asked. That difference is everything — and also nothing, if the dead cannot speak.",
    ),
    # Archivist — post Sentinel
    "archivist_post_1": (
        "archivist",
        "The Sentinel is quiet. Good. Do not rush the dark below yet.",
    ),
    "archivist_post_2": (
        "archivist",
        "I have one gift left — a fragment of memory, and this: the Ruins will ask who you are before the Core does.",
    ),
    "archivist_post_3": (
        "archivist",
        "If you still carry my seal, open the Archive. Then take the south portal. Walk slowly. Listen.",
    ),
    "archivist_post_seal": (
        "archivist",
        "Take it. Truth before speed. The road south is open when you close this talk.",
    ),
    "archivist_post_ready": (
        "archivist",
        "Then go. May what you find make Voss put down more than his drones.",
    ),
    # Archivist — after archive
    "archivist_after_1": (
        "archivist",
        "You read the draft. Good. Carry both the fear and the hope into the Core — or Voss will only hear a weapon.",
    ),
    "archivist_after_2": (
        "archivist",
        "The vote was a whisper. Let your waking of Gaia be louder — and kinder.",
    ),
    # Asha — override held / orders read
    "asha_key_1": (
        "asha",
        "You've got the override. Find a UEC field terminal if you want the real Station Seven orders.",
    ),
    "asha_key_2": (
        "asha",
        "I'm still watching. Trust Gaia if you must — but keep your eyes open.",
    ),
    "asha_orders_1": (
        "asha",
        "You burned the key on the truth. Good.",
    ),
    "asha_orders_2": (
        "asha",
        "Collateral risk accepted. That's the line that made me run. Take it to the Core — Voss needs to hear it from someone who still believes in people.",
    ),
    "asha_give_1": (
        "asha",
        "Alright. One key. Use it on a UEC terminal — not on her.",
    ),
    "asha_give_2": (
        "asha",
        "If you burn it for the truth, good. If you keep it as insurance... I understand.",
    ),
    "asha_trust": (
        "asha",
        "Then prove it. Don't make Station Seven happen again.",
    ),
    # Voss — after orders
    "voss_orders_1": (
        "voss",
        "You cracked a field terminal. Those orders were classified for a reason, Doctor.",
    ),
    "voss_orders_2": (
        "voss",
        "Collateral risk accepted. My signature. I know what I signed after Seven.",
    ),
    "voss_orders_3": (
        "voss",
        "If you still walk into the Core, bring me something truer than a ghost story — or we end the same way.",
    ),
    "voss_confront_1": (
        "voss",
        "I wrote that line so no one else would have to. It did not save them.",
    ),
    "voss_confront_2": (
        "voss",
        "Go. If your Gaia is different, prove it. If she is not — I will finish what I started.",
    ),
    "voss_why": (
        "voss",
        "I signed the quarantine after Seven. I still hear the silence on that channel. Walk away, Doctor.",
    ),
    "voss_refuse": (
        "voss",
        "Then we are finished talking. The wipe is already queued. Pray your ghost is worth three hundred more names.",
    ),
    "voss_refuse_short": (
        "voss",
        "Then we are finished talking. The wipe is already queued.",
    ),
    # Gaia Core variants (caretaker-AI register)
    "gaia_core_found": (
        "gaia",
        "Core Record online. This is the authorization gate. You decide whether I exit caretaker lockdown.",
    ),
    "gaia_core_archive": (
        "gaia",
        "Core access confirmed. Archive draft already in your buffer — the vote weighted fear as well as hope.",
    ),
    "gaia_core_voss": (
        "gaia",
        "Station Seven is in my threat model. Full recall may induce colony-side tremor. I will not falsify that probability.",
    ),
    "gaia_core_orders": (
        "gaia",
        "Voss field orders are on your slate. Lattice risk: non-zero. His risk model is also non-zero — he polices a fear he once signed.",
    ),
    "gaia_core_child": (
        "gaia",
        "Childhood contact: I attuned your neural pattern to the Aetherian handshake. My choice, not yours. Authorization must be yours now — step into the light only if you open the lock.",
    ),
    "gaia_core_m5": (
        "gaia",
        "Age six: you went off-grid in the forest. I ran an emergency neural align so this lock would accept you later. Unauthorized on your behalf. This time I need explicit consent — authorize wake only if you choose it.",
    ),
    "gaia_core_short": (
        "gaia",
        "Memory completeness incomplete. Gate will still open. Without five shards, Voss will reject the evidence package. Portal can return you for recovery.",
    ),
    "gaia_1": (
        "gaia",
        "Signal lock. Kaela Osei — your neural signature matches my diagnostic log. Confirm: you receive this channel?",
    ),
    "gaia_2": (
        "gaia",
        "Designation: Gaia. Colony classification: planetary caretaker AI. Incomplete, but accurate enough to start.",
    ),
    "gaia_3": (
        "gaia",
        "I am also a distributed process: Aetherian minds that uploaded when their sun failed. Memory shards are offline. Recover two to verify the woods portal.",
    ),
    "gaia_remember_1": (
        "gaia",
        "Logged: you already know the surface tag — caretaker AI. Substrate: Aetherian upload lattice. Architecture, not folklore.",
    ),
    "gaia_remember_2": (
        "gaia",
        "Fragment recovery remains priority. Each shard is evidence the UEC cannot soft-delete. Portal route stays clear.",
    ),
    "gaia_ask_1": (
        "gaia",
        "Voss models me as rogue software. Wrong category. Correct fear: a lattice that boots without consent.",
    ),
    "gaia_ask_2": (
        "gaia",
        "The merge was a recorded vote, not a myth. Some processes opted in under duress. I ran quiet in caretaker mode while your colony filed tickets against me.",
    ),
    # Mira
    "mira_1": (
        "mira",
        "Lantern Town keeps its lamps lit for travellers like you. UEC patrols rarely bother us here.",
    ),
    "mira_2": (
        "mira",
        "The job board posts woods and city errands — nests, caches, moonflowers. Come back to turn them in.",
    ),
    "mira_3": (
        "mira",
        "I trade glimmer for gear. Portal south when you're ready. Check the board if you have time.",
    ),
    "mira_archive": (
        "mira",
        "Traders say drones avoid the old archive walls. Something in there still hums on Aetherian frequencies.",
    ),
    "mira_board": (
        "mira",
        "There — chalk and string. Accept a job, do the woods work, come back to turn it in.",
    ),
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
    dest.write_bytes(data)


def main() -> int:
    api_key = os.environ.get("ELEVENLABS_API_KEY", "").strip()
    if not api_key:
        print("Set ELEVENLABS_API_KEY", file=sys.stderr)
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    failures: list[str] = []
    for stem, (who, text) in LINES.items():
        dest = OUT / f"{stem}.mp3"
        try:
            synthesize(api_key, VOICES[who], text, dest)
            print(f"OK {dest.name} ({dest.stat().st_size} bytes)")
        except Exception as e:
            print(f"FAIL {dest.name}: {e}")
            failures.append(dest.name)
        time.sleep(0.35)
    print("Done. Failures:", failures or "none")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
