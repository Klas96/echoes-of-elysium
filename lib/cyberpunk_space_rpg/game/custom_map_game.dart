import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:bonfire/bonfire.dart';
import 'package:bonfire/map/tiled/builder/tiled_world_builder.dart' show ObjectBuilder;
import '../components/custom_player.dart';
import '../components/custom_map.dart';
import '../components/portal_component.dart';
import '../components/map_edge_exit.dart';
import '../components/uec_drone.dart';
import '../components/ai_fragment.dart';
import '../components/npc_character.dart';
import '../components/fragment_pickup.dart';
import '../components/health_pickup.dart';
import '../components/sentinel_drone.dart';
import '../components/checkpoint.dart';
import '../components/building.dart';
import '../components/story_gate.dart';
import '../components/ambient_prop_fx.dart';
import '../components/lamp_light.dart';
import '../audio/music_manager.dart';
import '../creatures/bonds.dart';
import '../creatures/creature_components.dart';
import '../creatures/creature_species.dart';
import '../creatures/day_cycle.dart';
import '../creatures/examine.dart';
import '../creatures/interaction.dart';
import '../creatures/journal_ui.dart';
import '../creatures/obstacles.dart';
import '../ui/cutscenes.dart';
import '../ui/equipment_ui.dart';
import '../ui/mmo_feedback.dart';
import '../ui/quest_board_ui.dart';
import '../ui/shop_ui.dart';
import 'adventure.dart';
import 'game_state.dart';
import 'pause.dart';
import 'progression.dart';
import 'memories.dart';
import 'quests.dart';
import 'save_service.dart';
import 'story_beats.dart';
import 'travel.dart';
// ---------------------------------------------------------------------------
// NPC dialogue data (choices / key items resolve at talk time)
// ---------------------------------------------------------------------------

NpcDialogue _gaiaDialogue() {
  final told = Adventure.hasClue('aetherian_merge');
  return NpcDialogue(
    name: 'GAIA  ·  CARETAKER',
    color: const Color(0xFF00FF88),
    lines: told
        ? [
            'You already know: the colony calls me a caretaker AI. Underneath, I am an Aetherian mind-lattice — people who uploaded rather than died.',
            'Your job is unchanged. Find the glowing memory fragments. Two open the south road to the City. Each shard is proof the UEC cannot delete.',
          ]
        : [
            'Kaela — can you hear me? I am Gaia. Your colony calls me the planet\'s caretaker AI. That is only half the truth.',
            'I am also what remains of the Aetherians: a people who uploaded into this world when their sun failed. My memories are broken into glowing shards.',
            'Please find two of those fragments in these woods. That opens the south road to the City. The UEC wants me wiped — do not let them finish the job.',
          ],
    voicePaths: told
        ? const [
            'audio/voices/gaia_remember_1.mp3',
            'audio/voices/gaia_remember_2.mp3',
          ]
        : const [
            'audio/voices/gaia_1.mp3',
            'audio/voices/gaia_2.mp3',
            'audio/voices/gaia_3.mp3',
          ],
    choices: told
        ? const []
        : const [
            DialogueChoice(
              label: 'WHO WERE THE AETHERIANS?',
              discoverClue: 'aetherian_merge',
              setFlag: 'asked_gaia_merge',
              requireFlagUnset: 'asked_gaia_merge',
              replyLines: [
                'Commander Voss thinks I am rogue software. Wrong. I am a people\'s minds, still running. His fear is that I wake without asking.',
                'Long ago they voted to merge into Gaia rather than die with their sun. Some joined in hope, some in fear. I have kept the colony alive in caretaker mode ever since.',
              ],
              replyVoicePaths: [
                'audio/voices/gaia_ask_1.mp3',
                'audio/voices/gaia_ask_2.mp3',
              ],
            ),
          ],
  );
}

/// Core Gaia: different lines + distinct VO files (Lily) from forest Gaia (Ava).
NpcDialogue _gaiaCoreDialogue() {
  final archive = Adventure.openedArchive;
  final orders = Adventure.readUecOrders;
  // Memory 5 (optional ruins fragment) is the full childhood reveal; still
  // spell the beat here so the Core makes sense without that flashback.
  final sawMemory5 = Cutscenes.seen(Memories.idFor(5));
  final incomplete = !Memories.allFound;
  final lines = <String>[
    archive
        ? 'Core access confirmed. Archive draft already in your buffer — the vote weighted fear as well as hope.'
        : 'Core Record online. This is the authorization gate. You decide whether I exit caretaker lockdown.',
    orders
        ? 'Voss field orders are on your slate. Lattice risk: non-zero. His risk model is also non-zero — he polices a fear he once signed.'
        : 'Station Seven is in my threat model. Full recall may induce colony-side tremor. I will not falsify that probability.',
    if (sawMemory5)
      'Age six: you went off-grid in the forest. I ran an emergency neural align so this lock would accept you later. Unauthorized on your behalf. This time I need explicit consent — authorize wake only if you choose it.'
    else
      'Childhood contact: I attuned your neural pattern to the Aetherian handshake. My choice, not yours. Authorization must be yours now — step into the light only if you open the lock.',
    if (incomplete)
      'Memory completeness: ${Memories.progressLabel}. Gate will still open. Without five shards, Voss will reject the evidence package. Portal can return you for recovery.',
  ];
  return NpcDialogue(
    name: 'GAIA  ·  CORE',
    color: const Color(0xFF00FF88),
    lines: lines,
    voicePaths: [
      archive
          ? 'audio/voices/gaia_core_archive.mp3'
          : 'audio/voices/gaia_core_found.mp3',
      orders
          ? 'audio/voices/gaia_core_orders.mp3'
          : 'audio/voices/gaia_core_voss.mp3',
      sawMemory5
          ? 'audio/voices/gaia_core_m5.mp3'
          : 'audio/voices/gaia_core_child.mp3',
      if (incomplete) 'audio/voices/gaia_core_short.mp3',
    ],
  );
}

NpcDialogue _ashaDialogue() {
  if (Adventure.readUecOrders) {
    return const NpcDialogue(
      name: 'ASHA  ·  EX-UEC',
      color: Color(0xFFFFAA00),
      lines: [
        'You burned the key on the truth. Good.',
        '"Collateral risk accepted." That\'s the line that made me run. Take it to the Core — Voss needs to hear it from someone who still believes in people.',
      ],
      voicePaths: [
        'audio/voices/asha_orders_1.mp3',
        'audio/voices/asha_orders_2.mp3',
      ],
    );
  }
  if (Adventure.openedArchive) {
    return NpcDialogue(
      name: 'ASHA  ·  EX-UEC',
      color: const Color(0xFFFFAA00),
      lines: const [
        'I caught your Archive spike. A whisper of a vote — people becoming a world because the sun was dying.',
        'That is not the clean miracle Voss wants to erase, and not the weapon he fears. It is both. Carry that into the Core.',
        'Keep the override if you still have it. I deserted for a sympathetic AI. You may be walking toward a civilization.',
      ],
      voicePaths: const [
        'audio/voices/asha_archive_1.mp3',
        'audio/voices/asha_archive_2.mp3',
        'audio/voices/asha_archive_3.mp3',
      ],
      choices: [
        if (!Adventure.flag('asha_archive_ack'))
          const DialogueChoice(
            label: 'PROMISE TO CARRY BOTH',
            setFlag: 'asha_archive_ack',
            replyLines: [
              'Then we\'re still on the same side. Go. Make him hear a people — not a ghost story.',
            ],
            replyVoicePaths: [
              'audio/voices/asha_archive_ack.mp3',
            ],
          ),
      ],
    );
  }
  final hasKey = Bonds.hasItem('uec_override') || Bonds.usedItem('uec_override');
  return NpcDialogue(
    name: 'ASHA  ·  EX-UEC',
    color: const Color(0xFFFFAA00),
    lines: hasKey
        ? [
            'You\'ve got the override. Find a UEC field terminal if you want the real Station Seven orders.',
            'I\'m still watching. Trust Gaia if you must — but keep your eyes open.',
          ]
        : [
            'Keep moving. Name\'s Asha — ex-UEC. I deserted after they ordered me to erase a "sympathetic" AI on Station Seven.',
            'Three hundred colonists went dark when that lattice woke. Voss still carries their names. That\'s why he hunts Gaia.',
            'I kept one UEC override key. If Gaia turns out to be a lie, I can still cut her signal. Don\'t make me use it.',
          ],
    voicePaths: hasKey
        ? const [
            'audio/voices/asha_key_1.mp3',
            'audio/voices/asha_key_2.mp3',
          ]
        : const [
            'audio/voices/asha_1.mp3',
            'audio/voices/asha_2.mp3',
            'audio/voices/asha_3.mp3',
          ],
    choices: hasKey
        ? const []
        : const [
            DialogueChoice(
              label: 'ASK FOR THE OVERRIDE KEY',
              giveItem: 'uec_override',
              discoverClue: 'override_key',
              requireNoItem: 'uec_override',
              replyLines: [
                '...Alright. One key. Use it on a UEC terminal — not on her.',
                'If you burn it for the truth, good. If you keep it as insurance... I understand.',
              ],
              replyVoicePaths: [
                'audio/voices/asha_give_1.mp3',
                'audio/voices/asha_give_2.mp3',
              ],
            ),
            DialogueChoice(
              label: 'TELL HER YOU BELIEVE GAIA',
              setFlag: 'said_trust_gaia',
              discoverClue: 'asha_warning',
              requireFlagUnset: 'said_trust_gaia',
              replyLines: [
                '...Then prove it. Don\'t make Station Seven happen again.',
              ],
              replyVoicePaths: [
                'audio/voices/asha_trust.mp3',
              ],
            ),
          ],
  );
}

NpcDialogue _echo7Dialogue() {
  return NpcDialogue(
    name: 'ECHO-7  ·  AETHERIAN',
    color: const Color(0xFFCC66FF),
    lines: const [
      'Traveller... you carry the resonance of one who seeks. We have waited ten thousand years for such a signal.',
      'Do not picture us asleep in tombs. We merged into Gaia — minds in the lattice, bodies returned to the soil — so a dying sun could not erase us.',
      'Not all of us chose freely. Some were afraid. Help Gaia remember the peace and the fear — or do not remember us at all.',
    ],
    voicePaths: const [
      'audio/voices/echo7_1.mp3',
      'audio/voices/echo7_2.mp3',
      'audio/voices/echo7_3.mp3',
    ],
    choices: const [
      DialogueChoice(
        label: 'ASK ABOUT THE FEAR',
        discoverClue: 'echo_split',
        setFlag: 'asked_echo_fear',
        requireFlagUnset: 'asked_echo_fear',
        replyLines: [
          'The vote was a whisper. Peace won — barely. Remember both, or you remember a lie.',
        ],
        replyVoicePaths: [
          'audio/voices/echo7_fear.mp3',
        ],
      ),
      DialogueChoice(
        label: 'PROMISE TO REMEMBER BOTH',
        setFlag: 'promised_echo',
        requireFlagUnset: 'promised_echo',
        replyLines: [
          'Then walk with open eyes. The Archivist holds a seal you may need.',
        ],
        replyVoicePaths: [
          'audio/voices/echo7_promise.mp3',
        ],
      ),
      DialogueChoice(
        label: 'ASK ABOUT THIS STREET',
        setFlag: 'asked_echo_street',
        requireFlagUnset: 'asked_echo_street',
        replyLines: [
          'The Archivist keeps to the square east of here. Any street will take you. From the arrival plaza the boulevard runs east to the Lantern Gate and Lantern Town: Mira\'s board, glimmer, and rest.',
        ],
      ),
    ],
  );
}

NpcDialogue _archivistDialogue() {
  // Quiet beat first — must not be shadowed by the archive follow-up lines,
  // or players who opened the library never hear that the south road opened.
  final postSentinel = SaveService.data.flag('sentinelDefeated') &&
      !SaveService.data.flag('archivistPostSentinel');
  if (postSentinel) {
    return NpcDialogue(
      name: 'THE ARCHIVIST  ·  AETHERIAN',
      color: const Color(0xFFFFDD44),
      lines: [
        'The Sentinel is quiet. Good. Do not rush the dark below yet.',
        'I have one gift left — a fragment of memory, and this: the Ruins will ask who you are before the Core does.',
        if (Adventure.openedArchive)
          'You already read the draft. Good. The south portal is open when you leave this talk — walk slowly. Listen.'
        else
          'If you still carry my seal, open the Archive. Then take the south portal. Walk slowly. Listen.',
      ],
      voicePaths: const [
        'audio/voices/archivist_post_1.mp3',
        'audio/voices/archivist_post_2.mp3',
        'audio/voices/archivist_post_3.mp3',
      ],
      choices: [
        if (!Bonds.hasItem('archive_seal') &&
            !Bonds.usedItem('archive_seal') &&
            !Adventure.openedArchive)
          const DialogueChoice(
            label: 'ASK FOR THE ARCHIVE SEAL',
            giveItem: 'archive_seal',
            discoverClue: 'archivist_seal',
            requireNoItem: 'archive_seal',
            replyLines: [
              'Take it. Truth before speed. The road south is open when you close this talk.',
            ],
            replyVoicePaths: [
              'audio/voices/archivist_post_seal.mp3',
            ],
          ),
        const DialogueChoice(
          label: 'I\'M READY FOR THE RUINS',
          setFlag: 'ready_for_ruins',
          requireFlagUnset: 'ready_for_ruins',
          replyLines: [
            'Then go. May what you find make Voss put down more than his drones.',
          ],
          replyVoicePaths: [
            'audio/voices/archivist_post_ready.mp3',
          ],
        ),
      ],
    );
  }
  if (Adventure.openedArchive) {
    return const NpcDialogue(
      name: 'THE ARCHIVIST  ·  AETHERIAN',
      color: Color(0xFFFFDD44),
      lines: [
        'You read the draft. Good. Carry both the fear and the hope into the Core — or Voss will only hear a weapon.',
        'The vote was a whisper. The south portal holds — let your waking of Gaia be louder, and kinder.',
      ],
      voicePaths: [
        'audio/voices/archivist_after_1.mp3',
        'audio/voices/archivist_after_2.mp3',
      ],
    );
  }
  final gaveSeal =
      Bonds.hasItem('archive_seal') || Bonds.usedItem('archive_seal');
  return NpcDialogue(
    name: 'THE ARCHIVIST  ·  AETHERIAN',
    color: const Color(0xFFFFDD44),
    lines: [
      'The Core Record is Gaia\'s first memory: the day we voted to merge into her lattice. Bodies rested. Minds took root. That is why your people say we "slept."',
      'Commander Voss seeks to delete it. He believes waking her will kill your colony the way Station Seven died.',
      gaveSeal
          ? 'The library seal is yours. Read the draft of that vote — then decide what Voss hears.'
          : 'Your neural signature matches the Aetherian activation code, Kaela. Only you can open the Core — and decide what truth he hears.',
    ],
    voicePaths: [
      'audio/voices/archivist_1.mp3',
      'audio/voices/archivist_2.mp3',
      gaveSeal
          ? 'audio/voices/archivist_3_seal.mp3'
          : 'audio/voices/archivist_3.mp3',
    ],
    choices: gaveSeal
        ? const [
            DialogueChoice(
              label: 'ASK ABOUT STATION SEVEN',
              discoverClue: 'station_seven',
              setFlag: 'asked_archivist_s7',
              requireFlagUnset: 'asked_archivist_s7',
              replyLines: [
                'Your coalition woke a lattice without consent. We asked. That difference is everything — and also nothing, if the dead cannot speak.',
              ],
              replyVoicePaths: [
                'audio/voices/archivist_s7.mp3',
              ],
            ),
          ]
        : const [
            DialogueChoice(
              label: 'ASK FOR THE ARCHIVE SEAL',
              giveItem: 'archive_seal',
              discoverClue: 'archivist_seal',
              requireNoItem: 'archive_seal',
              replyLines: [
                'Take it. The library faces this avenue. Inside is the draft of our first memory — not the Core, but the argument that made it.',
              ],
              replyVoicePaths: [
                'audio/voices/archivist_seal_give.mp3',
              ],
            ),
            DialogueChoice(
              label: 'ASK ABOUT STATION SEVEN',
              discoverClue: 'station_seven',
              setFlag: 'asked_archivist_s7',
              requireFlagUnset: 'asked_archivist_s7',
              replyLines: [
                'Your coalition woke a lattice without consent. We asked. That difference is everything — and also nothing, if the dead cannot speak.',
              ],
              replyVoicePaths: [
                'audio/voices/archivist_s7.mp3',
              ],
            ),
          ],
  );
}

NpcDialogue _vossDialogue() {
  if (Adventure.readUecOrders) {
    return NpcDialogue(
      name: 'COMMANDER VOSS  ·  UEC',
      color: const Color(0xFFFF4444),
      lines: const [
        'You cracked a field terminal. Those orders were classified for a reason, Doctor.',
        'Collateral risk accepted. My signature. I know what I signed after Seven.',
        'If you still walk into the Core, bring me something truer than a ghost story — or we end the same way.',
      ],
      voicePaths: const [
        'audio/voices/voss_orders_1.mp3',
        'audio/voices/voss_orders_2.mp3',
        'audio/voices/voss_orders_3.mp3',
      ],
      choices: [
        if (!Adventure.flag('confronted_voss_orders'))
          const DialogueChoice(
            label: 'CONFRONT HIM WITH THE ORDERS',
            setFlag: 'confronted_voss_orders',
            replyLines: [
              '...I wrote that line so no one else would have to. It did not save them.',
              'Go. If your Gaia is different, prove it. If she is not — I will finish what I started.',
            ],
            replyVoicePaths: [
              'audio/voices/voss_confront_1.mp3',
              'audio/voices/voss_confront_2.mp3',
            ],
          ),
        if (!Adventure.flag('refused_voss'))
          const DialogueChoice(
            label: 'REFUSE TO HAND OVER FRAGMENTS',
            setFlag: 'refused_voss',
            replyLines: [
              'Then we are finished talking. The wipe is already queued.',
            ],
            replyVoicePaths: [
              'audio/voices/voss_refuse_short.mp3',
            ],
          ),
      ],
    );
  }
  return NpcDialogue(
    name: 'COMMANDER VOSS  ·  UEC',
    color: const Color(0xFFFF4444),
    lines: const [
      'Doctor Kaela Osei. Last chance. Hand over the fragments and walk away with your clearance intact.',
      'Station Seven went dark the last time a lattice woke. I will not bury another colony for an alien ghost story.',
      'If you reach the Core, understand this: I am not erasing history. I am choosing the living over the dead.',
    ],
    voicePaths: const [
      'audio/voices/voss_1.mp3',
      'audio/voices/voss_2.mp3',
      'audio/voices/voss_3.mp3',
    ],
    choices: const [
      DialogueChoice(
        label: 'ASK WHY HE HUNTS GAIA',
        discoverClue: 'voss_motive',
        setFlag: 'asked_voss_why',
        requireFlagUnset: 'asked_voss_why',
        replyLines: [
          'I signed the quarantine after Seven. I still hear the silence on that channel. Walk away, Doctor.',
        ],
        replyVoicePaths: [
          'audio/voices/voss_why.mp3',
        ],
      ),
      DialogueChoice(
        label: 'REFUSE TO HAND OVER FRAGMENTS',
        setFlag: 'refused_voss',
        requireFlagUnset: 'refused_voss',
        replyLines: [
          'Then we are finished talking. The wipe is already queued. Pray your ghost is worth three hundred more names.',
        ],
        replyVoicePaths: [
          'audio/voices/voss_refuse.mp3',
        ],
      ),
    ],
  );
}

NpcDialogue _miraDialogue() {
  return NpcDialogue(
    name: 'MIRA  ·  COLONY VENDOR',
    color: const Color(0xFFFFE08A),
    lines: const [
      'Lantern Town keeps its lamps lit for travellers like you. UEC patrols rarely bother us here.',
      'The job board posts woods and city errands — nests, caches, moonflowers. Come back to turn them in.',
      'My stall trades glimmer for gear — plating, optics, charms. Ask to trade, or examine the stall beside me.',
    ],
    voicePaths: const [
      'audio/voices/mira_1.mp3',
      'audio/voices/mira_2.mp3',
      'audio/voices/mira_3.mp3',
    ],
    choices: [
      const DialogueChoice(
        label: 'ASK ABOUT THE ARCHIVE',
        discoverClue: 'mira_rumour',
        setFlag: 'asked_mira_archive',
        requireFlagUnset: 'asked_mira_archive',
        replyLines: [
          'Traders say drones avoid the old archive walls. Something in there still hums on Aetherian frequencies.',
        ],
        replyVoicePaths: [
          'audio/voices/mira_archive.mp3',
        ],
      ),
      DialogueChoice(
        label: 'SHOW ME THE BOARD',
        setFlag: 'mira_showed_board',
        replyLines: const [
          'There — chalk and string. Accept a job, do the woods work, come back to turn it in.',
        ],
        replyVoicePaths: const [
          'audio/voices/mira_board.mp3',
        ],
      ),
      DialogueChoice(
        label: 'TRADE AT THE STALL',
        setFlag: 'mira_showed_shop',
        replyLines: const [
          'Browse the stall — salvage and colony trinkets. Pay with glimmer from jobs and finds.',
        ],
        replyVoicePaths: const [
          'audio/voices/mira_3.mp3',
        ],
      ),
    ],
  );
}

NpcDialogue _dialogueFor(String mapId, String name) {
  switch (name) {
    case 'gaia':
      return mapId == 'world4' ? _gaiaCoreDialogue() : _gaiaDialogue();
    case 'asha':
      return _ashaDialogue();
    case 'echo7':
      return _echo7Dialogue();
    case 'archivist':
      return _archivistDialogue();
    case 'voss':
      return _vossDialogue();
    case 'mira':
      return _miraDialogue();
    default:
      throw ArgumentError('Unknown npc name "$name" in Tiled map');
  }
}

double _numProp(TiledObjectProperties p, String key, [double fallback = 0]) {
  final v = p.others[key];
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

/// Builders keyed by object name in the map's "gameplay" object layer.
/// Object x/y is the component's top-left corner in map pixels (except for
/// buildings, which are bottom-left anchored tile objects).
/// Stable id for a one-time pickup, from its map and Tiled position. An
/// object the generator moved (#26 layout pass) carries its old position as
/// property `pid`, so saves made before the move still find it.
String _pickupId(String mapId, String kind, TiledObjectProperties p) {
  final pid = (p.others['pid'] ?? '').toString();
  final at = pid.isNotEmpty ? pid : '${p.position.x.round()}_${p.position.y.round()}';
  return '$mapId:$kind:$at';
}

int? _destLevel(String raw) {
  switch (raw.trim().toLowerCase()) {
    case '1':
    case 'woods':
      return 1;
    case '2':
    case 'city':
      return 2;
    case '3':
    case 'ruins':
      return 3;
    case '4':
    case 'core':
      return 4;
    case '5':
    case 'town':
      return 5;
    default:
      return int.tryParse(raw);
  }
}

Map<String, ObjectBuilder> _mapObjects(String mapId) => {
      'spawn': (p) => _PlayerSpawn(p.position),
      'entry': (p) {
        final side = (p.others['side'] ?? 'north').toString().toLowerCase();
        return MapEntryPoint(p.position, side: side);
      },
      'mapexit': (p) {
        final dest = _destLevel((p.others['dest'] ?? '').toString());
        if (dest == null) {
          throw ArgumentError('mapexit on $mapId needs dest=woods|city|town|ruins|core');
        }
        final entry = (p.others['entry'] ?? 'north').toString().toLowerCase();
        final needUnlock = p.others['unlock'] == true ||
            p.others['unlock'] == 'true' ||
            (p.others['unlock'] ?? '').toString() == 'portal';
        final size = Vector2(
          p.size.x > 0 ? p.size.x : 64,
          p.size.y > 0 ? p.size.y : 48,
        );
        return MapEdgeExit(
          p.position,
          size,
          destLevel: dest,
          entrySide: entry,
          canExit: needUnlock
              ? () => Travel.portalUsable(GameState.level)
              : () => true,
          lockedTitle: (p.others['lockedTitle'] ?? 'PATH CLOSED').toString(),
          lockedBody: (p.others['lockedBody'] ??
                  'Something still holds this road. Check your objective.')
              .toString(),
        );
      },
      'portal': (p) {
        final dest = (p.others['dest'] ?? '').toString();
        if (dest == 'town') {
          // Side gate: only Lantern Town — amber so it reads as market, not story.
          return PortalComponent(
            p.position,
            canActivate: () => true,
            overlayId: 'portalTown',
            accent: const Color(0xFFFFE08A),
          );
        }
        return PortalComponent(p.position);
      },
      'npc': (p) {
        final name = (p.others['name'] ?? '').toString().toLowerCase();
        final sprite = (p.others['sprite'] ?? name).toString().toLowerCase();
        return NpcCharacter(p.position,
            dialogueOf: () => _dialogueFor(mapId, name),
            spritePath: 'sprites/npc_$sprite.png',
            npcKey: name);
      },
      'examine': (p) {
        final id = (p.others['id'] ?? _pickupId(mapId, 'examine', p)).toString();
        return ExamineHotspot(
          p.position,
          id: id,
          title: (p.others['title'] ?? 'EXAMINE').toString(),
          text: (p.others['text'] ?? '...').toString(),
          clueId: () {
            final c = (p.others['clue'] ?? '').toString();
            return c.isEmpty ? null : c;
          }(),
          requiresItem: () {
            final i = (p.others['item'] ?? '').toString();
            return i.isEmpty ? null : i;
          }(),
          consumeItem: p.others['consume'] == true || p.others['consume'] == 'true',
          setFlag: () {
            final f = (p.others['flag'] ?? '').toString();
            return f.isEmpty ? null : f;
          }(),
          giveItem: () {
            final g = (p.others['give'] ?? '').toString();
            return g.isEmpty ? null : g;
          }(),
          completeQuest: () {
            final q = (p.others['quest'] ?? '').toString();
            return q.isEmpty ? null : q;
          }(),
          openQuestBoard: p.others['board'] == true || p.others['board'] == 'true',
          openShop: p.others['shop'] == true || p.others['shop'] == 'true',
        );
      },
      'fragment': (p) {
        final id = _pickupId(mapId, 'fragment', p);
        if (SaveService.data.collected.contains(id)) return _Gone();
        return FragmentPickup(p.position, onCollected: () {
          SaveService.data.collected.add(id);
          Memories.onFragmentPicked();
        });
      },
      'health': (p) {
        final id = _pickupId(mapId, 'health', p);
        if (SaveService.data.collected.contains(id)) return _Gone();
        return HealthPickup(p.position, onCollected: () {
          SaveService.data.collected.add(id);
          SaveService.requestAutosave();
        });
      },
      'drone': (p) {
        final nestRaw = (p.others['nest'] ?? '').toString();
        final nestId = nestRaw.isEmpty || nestRaw == 'false'
            ? null
            : (nestRaw == 'true' ? 'drone_nest' : nestRaw);
        return UECDrone(
          p.position,
          startAngle: _numProp(p, 'startAngle'),
          kind: DroneKindParse.from((p.others['kind'] ?? '').toString()),
          nestQuestId: nestId,
        );
      },
      'storygate': (p) => StoryGate(
            p.position,
            p.size,
            openFlag: (p.others['flag'] ?? 'ruins_gate_open').toString(),
          ),
      'light': (p) => LampLight(
            p.position,
            p.size,
            kind: LightKindStyle.parse((p.others['kind'] ?? 'lamp').toString()),
            radius: _numProp(p, 'radius', 80),
            style: (p.others['style'] ?? '').toString(),
          ),
      'ambient': (p) => AmbientPropFx(
            p.position,
            kind: (p.others['kind'] ?? 'steam').toString(),
          ),
      'sentinel': (p) => SaveService.data.flag('sentinelDefeated')
          ? _Gone()
          : SentinelDrone(p.position, onDefeated: StoryBeats.onSentinelDefeated),
      'checkpoint': (p) => Checkpoint(p.position, label: (p.others['label'] ?? '').toString()),
      // --- M2: creatures and ability-gated secrets (woods) ---
      'creature': (p) {
        final id = (p.others['species'] ?? '').toString();
        final species = creatureSpecies[id];
        if (species == null) return _Gone(); // retired/unknown species: skip
        return WildCreature(species, p.position,
            objectId: _pickupId(mapId, 'creature', p),
            radiusTiles: _numProp(p, 'radius', 1),
            netted: p.others['netted'] == true);
      },
      'boulder': (p) => Boulder(p.position, p.size,
          id: _pickupId(mapId, 'boulder', p),
          push: Vector2(_numProp(p, 'pushX'), _numProp(p, 'pushY')) * 32),
      'darkzone': (p) => DarkZone(p.position, p.size, id: _pickupId(mapId, 'darkzone', p)),
      'glyph': (p) => GlyphTablet(p.position,
          id: _pickupId(mapId, 'glyph', p), glyph: (p.others['glyph'] ?? '').toString()),
      'stash': (p) => GlimmerStash(p.position,
          id: _pickupId(mapId, 'stash', p), amount: _numProp(p, 'glimmer', 10).round()),
      'hidden': (p) => BuriedItem(p.position,
          id: _pickupId(mapId, 'hidden', p), amount: _numProp(p, 'glimmer', 10).round()),
      'hiddenpath': (p) => HiddenPath(p.position, p.size, id: _pickupId(mapId, 'hiddenpath', p)),
      'stump': (p) => SweetrootStump(p.position, p.size),
      'pebble': (p) => RiverPebble(p.position, id: _pickupId(mapId, 'pebble', p)),
      'moonflower': (p) => Moonflower(p.position),
      // Tile objects: Tiled anchors them bottom-left, so x/y is the sprite's
      // bottom-left corner.
      'building': (p) {
        final id = (p.others['building'] ?? '').toString();
        final def = buildingDefs[id];
        if (def == null) {
          throw ArgumentError('Unknown building "$id" in Tiled map');
        }
        return Building(p.position - Vector2(0, def.h), id: id, def: def);
      },
    };

/// Stand-in for a map object that is already used up in the save (collected
/// pickup, quieted Sentinel): removes itself straight away.
class _Gone extends GameComponent {
  @override
  void onMount() {
    super.onMount();
    removeFromParent();
  }
}

/// The player that has been moved to its spawn/saved spot on this map. Until
/// then its position is meaningless and must not be saved.
CustomPlayer? _placedPlayer;

/// Moves the player to the map's spawn object (or, on CONTINUE, to the saved
/// position and checkpoint) once the map is loaded, then removes itself.
class _PlayerSpawn extends GameComponent {
  _PlayerSpawn(Vector2 spawn) {
    position = spawn;
    size = Vector2.all(CustomPlayer.sizePlayer);
  }

  /// Removal is deferred to Flame's lifecycle queue, which can lag a frame
  /// or two while other components finish loading; place the player once.
  bool _done = false;

  @override
  void update(double dt) {
    super.update(dt);
    if (_done) return;
    final player = gameRef.player;
    if (player == null) return;
    // Wait a beat so [MapEntryPoint]s from the same Tiled layer register.
    final entry = Travel.pendingSpawnEntry;
    if (entry != null && !MapEntryPoint.bySide.containsKey(entry)) return;
    _done = true;
    final save = SaveService.data;
    if (SaveService.resumePlayer && player is CustomPlayer) {
      SaveService.resumePlayer = false;
      Travel.takePendingEntry();
      final at = save.player ?? save.checkpoint;
      final cp = save.checkpoint;
      player.position = at != null ? Vector2(at.x, at.y) : position.clone();
      player.respawnPoint = cp != null ? Vector2(cp.x, cp.y) : position.clone();
      CustomPlayer.healthNotifier.value =
          (save.health ?? CustomPlayer.maxHealth).clamp(1, CustomPlayer.maxHealth);
    } else {
      final side = Travel.takePendingEntry();
      final edge = side == null ? null : MapEntryPoint.bySide[side];
      player.position = (edge ?? position).clone();
      // Until a checkpoint is touched, Gaia pulls Kaela back to the spawn.
      if (player is CustomPlayer) player.respawnPoint ??= position.clone();
    }
    if (player is CustomPlayer) _placedPlayer = player;
    gameRef.camera.moveToPlayer();
    removeFromParent();
  }
}

// ---------------------------------------------------------------------------
// App root
// ---------------------------------------------------------------------------

class CustomMapGame extends StatefulWidget {
  const CustomMapGame({super.key});

  @override
  State<CustomMapGame> createState() => _CustomMapGameState();
}

class _CustomMapGameState extends State<CustomMapGame> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Backgrounded (phone home button, app switcher, web tab hidden, window
    // closing): save where Kaela stands right now.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (_activeGame != null) SaveService.saveNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Echoes of Elysium',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const IntroScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// Intro / title screen
// ---------------------------------------------------------------------------

class IntroScreen extends StatelessWidget {
  const IntroScreen({super.key});

  static const _brief =
      'Year 2387 · Elysium Colony\n\n'
      'You are Kaela Osei. A routine check on Gaia — the planet\'s caretaker AI — '
      'woke something that answered back.\n\n'
      'The United Earth Coalition wants Gaia erased. She needs you to prove what she '
      'really is: the surviving minds of an ancient people.\n\n'
      'First steps in the woods:\n'
      '1. Talk to Gaia by the crash site\n'
      '2. Find two glowing memory fragments\n'
      '3. Walk south to the City before the UEC locks the road';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          // Phones in landscape are only ~400 logical px tall: shrink and
          // put the brief beside the title/buttons so it all fits; always
          // scrollable as a fallback.
          final compact = box.maxHeight < 600;
          final wide = box.maxWidth >= 700;
          final pad = compact ? 16.0 : 40.0;

          final title = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('ECHOES OF ELYSIUM',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: const Color(0xFF00FFCC),
                    fontSize: compact ? 24 : 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: compact ? 4 : 6,
                  )),
              const SizedBox(height: 8),
              const Text('A story of AI, nature, and the echoes of a lost world',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 13, letterSpacing: 1)),
            ],
          );

          final brief = Container(
            constraints: const BoxConstraints(maxWidth: 560),
            padding: EdgeInsets.all(compact ? 16 : 24),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF00FFCC).withOpacity(0.3)),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white.withOpacity(0.03),
            ),
            child: Text(_brief,
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: compact ? 13 : 14,
                    height: compact ? 1.5 : 1.7)),
          );

          final actions = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: SaveService.hasSave,
                builder: (context, saved, _) => saved
                    ? Column(mainAxisSize: MainAxisSize.min, children: [
                        _CyberButton(
                          label: 'CONTINUE',
                          filled: true,
                          onTap: () => _continueGame(context),
                        ),
                        const SizedBox(height: 6),
                        Text(_saveSummary(SaveService.data),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11, letterSpacing: 1)),
                        SizedBox(height: compact ? 10 : 14),
                        _CyberButton(
                          label: 'BEGIN JOURNEY',
                          color: Colors.white54,
                          onTap: () => _confirmNewGame(context),
                        ),
                      ])
                    : _CyberButton(
                        label: 'BEGIN JOURNEY',
                        onTap: () => _beginNewGame(context),
                      ),
              ),
              SizedBox(height: compact ? 12 : 20),
              Text(_isTouch
                      ? 'Joystick to move · tap TALK to interact · tap to shoot'
                      : 'WASD / Arrow keys · E to interact · J journal · Esc to pause · ` to debug',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white24, fontSize: 11, letterSpacing: 1.2)),
            ],
          );

          final Widget content = (compact && wide)
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [title, const SizedBox(height: 24), actions],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(child: brief),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    title,
                    SizedBox(height: compact ? 20 : 36),
                    brief,
                    SizedBox(height: compact ? 20 : 36),
                    actions,
                  ],
                );

          return SingleChildScrollView(
            padding: EdgeInsets.all(pad),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - pad * 2),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: content,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Save / continue
// ---------------------------------------------------------------------------

const _regionNames = {
  'woods': 'Whispering Woods',
  'city': 'The City',
  'ruins': 'The Ruins',
  'core': 'Gaia\'s Core',
  'town': 'Lantern Town',
};

String _saveSummary(SaveData d) {
  final region = _regionNames[d.regionId] ?? d.regionId;
  final mins = (d.playTimeSeconds / 60).floor();
  final time = mins < 1 ? '' : (mins < 60 ? '  ·  ${mins}m' : '  ·  ${mins ~/ 60}h ${mins % 60}m');
  return '$region$time';
}

Widget _screenForMap(String mapId) {
  switch (mapId) {
    case 'world2':
      return const Map2GameScreen();
    case 'world3':
      return const Map3GameScreen();
    case 'world4':
      return const Map4GameScreen();
    case 'world5':
      return const Map5GameScreen();
    default:
      return const CustomMapGameScreen();
  }
}

/// Warp to a travel destination (shared by every portal menu).
Future<void> _travelTo(BuildContext context, TravelDest dest) async {
  final nav = Navigator.of(context);
  final mapId = Travel.mapIdFor(dest.level);
  MapEntryPoint.bySide.clear();
  await _leaveMap(nextMapId: mapId);
  final screen = _screenForMap(mapId);
  if (dest.level == 2) {
    nav.pushReplacement(Cutscenes.route(
      id: Cutscenes.coalition,
      once: true,
      then: (_) => screen,
    ));
  } else {
    nav.pushReplacement(MaterialPageRoute(builder: (_) => screen));
  }
}

/// Invisible overlay: [MapEdgeExit] queued a walk-off; travel immediately.
class _EdgeTravelOverlay extends StatefulWidget {
  final BonfireGameInterface game;
  const _EdgeTravelOverlay({required this.game});

  @override
  State<_EdgeTravelOverlay> createState() => _EdgeTravelOverlayState();
}

class _EdgeTravelOverlayState extends State<_EdgeTravelOverlay> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final level = Travel.takePendingEdgeLevel();
      widget.game.overlays.remove('edgeTravel');
      if (level == null || !mounted) return;
      final dest = Travel.byLevel(level);
      if (dest == null) return;
      SfxManager().playPortal();
      await _travelTo(context, dest);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Future<bool> _confirmCoreActivation(BuildContext context) async {
  if (Memories.allFound) return true;
  final hints = Memories.missingHints;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF06060F),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: const Color(0xFFFFAA44).withValues(alpha: 0.7)),
      ),
      title: const Text('Memories incomplete',
          style: TextStyle(
              color: Color(0xFFFFAA44), fontSize: 18, letterSpacing: 1)),
      content: Text(
        'You carry ${Memories.progressLabel} Aetherian memories.\n'
        'Activate now and Voss will not fully stand down — the story ends unfinished.\n\n'
        'Still missing:\n'
        '${hints.map((h) => '· $h').join('\n')}\n\n'
        'You can close this gate and return for the rest.',
        style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.55),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('KEEP SEARCHING',
              style: TextStyle(color: Colors.white54, letterSpacing: 1)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('ACTIVATE ANYWAY',
              style: TextStyle(color: Color(0xFFFFAA44), letterSpacing: 1)),
        ),
      ],
    ),
  );
  return go == true;
}

Future<void> _activateCoreRecord(BuildContext context) async {
  final nav = Navigator.of(context);
  SaveService.data.setFlag('completed');
  await _leaveMap();
  final endingId = Memories.allFound ? Cutscenes.endingA : Cutscenes.endingB;
  nav.pushReplacement(Cutscenes.route(
    id: endingId,
    then: (_) => const _VictoryScreen(),
  ));
}

void _continueGame(BuildContext context) {
  SaveService.prepareResume();
  Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => _screenForMap(SaveService.data.mapId)));
}

Future<void> _beginNewGame(BuildContext context) async {
  final nav = Navigator.of(context);
  await SaveService.startNewGame();
  nav.pushReplacement(Cutscenes.route(
      id: Cutscenes.awakening, then: (_) => const CustomMapGameScreen()));
}

Future<void> _confirmNewGame(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF06060F),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: const Color(0xFF00FFCC).withValues(alpha: 0.6)),
      ),
      title: const Text('Begin a new journey?',
          style: TextStyle(color: Color(0xFF00FFCC), fontSize: 18, letterSpacing: 1)),
      content: const Text(
          'Your saved journey will be replaced by a fresh start in the woods.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('KEEP MY SAVE', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('START OVER',
              style: TextStyle(color: Color(0xFF00FFCC), fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
  if (ok == true && context.mounted) await _beginNewGame(context);
}

/// Session clock for play time, running while a map is on screen.
final _playClock = Stopwatch();

/// Copies live game state into the save record before every write.
void _snapshot(SaveData d) {
  d.dayTime = DayCycle.time.value;
  d.playTimeSeconds += _playClock.elapsedMilliseconds / 1000;
  _playClock.reset();
  if (_activeGame == null) return;
  GameState.writeTo(d);
  final p = CustomPlayer.current;
  if (p != null && identical(p, _placedPlayer)) {
    final cp = p.respawnPoint;
    // Mid-respawn the body is about to be moved to the checkpoint.
    final pos = p.isRespawning && cp != null ? cp : p.position;
    d.player = SavePoint(pos.x, pos.y);
    d.checkpoint = cp == null ? null : SavePoint(cp.x, cp.y);
    d.health = p.isRespawning ? CustomPlayer.maxHealth : CustomPlayer.healthNotifier.value;
  }
}

/// Leaving the current map (portal, main menu, ending): save, then stop
/// treating the old map as live.
Future<void> _leaveMap({String? nextMapId}) async {
  await SaveService.saveNow();
  _activeGame = null;
  _placedPlayer = null;
  _playClock.stop();
  if (nextMapId != null) {
    // Map transition: the next map starts fresh at its spawn.
    final d = SaveService.data;
    d.mapId = nextMapId;
    d.regionId = GameState.regionIds[GameState.levelForMap(nextMapId)]!;
    d.player = null;
    d.checkpoint = null;
    d.objectiveStep = 0;
    d.fragments = 0;
    await SaveService.saveNow(takeSnapshot: false);
  }
}

/// onReady for every map: restore the objective on CONTINUE, otherwise start
/// the level fresh and save the transition.
void _startLevel(BonfireGameInterface game, int level) {
  _onMapReady(game);
  SaveService.snapshot = _snapshot;
  // M2: day/night clock, companion and creature/obstacle interactions
  DayCycle.time.value = SaveService.data.dayTime;
  Bonds.revision.value++;
  Interaction.reset();
  GameToast.current.value = null;
  Journal.open.value = false;
  Equipment.open.value = false;
  Shop.open.value = false;
  QuestBoard.open.value = false;
  void onOverlay(bool open) {
    final g = _activeGame;
    if (g == null || _paused.value) return;
    if (open) {
      SaveService.saveNow();
      g.pauseEngine();
    } else if (!_anyUiHold()) {
      g.resumeEngine();
    }
  }

  _overlayHoldFn = onOverlay;
  if (!_dialogueHoldWired) {
    _dialogueHoldWired = true;
    NpcCharacter.activeDialogue.addListener(_onDialogueHold);
    AIFragment.activeDialogue.addListener(_onDialogueHold);
  }

  Journal.onOpenChanged = onOverlay;
  Equipment.onOpenChanged = onOverlay;
  Shop.onOpenChanged = onOverlay;
  QuestBoard.onOpenChanged = onOverlay;
  Journal.dismissOthers = () {
    Equipment.open.value = false;
    Shop.open.value = false;
    QuestBoard.open.value = false;
  };
  Equipment.dismissOthers = () {
    Journal.open.value = false;
    Shop.open.value = false;
    QuestBoard.open.value = false;
  };
  Shop.dismissOthers = () {
    Journal.open.value = false;
    Equipment.open.value = false;
    QuestBoard.open.value = false;
  };
  QuestBoard.dismissOthers = () {
    Journal.open.value = false;
    Equipment.open.value = false;
    Shop.open.value = false;
  };
  game.add(DayClock());
  game.add(InteractionManager());
  game.add(Companion());
  _playClock
    ..reset()
    ..start();
  Travel.markVisited(level);
  final dest = Travel.byLevel(level);
  if (dest != null) {
    MmoFeedback.enterZone(dest.title, blurb: dest.blurb);
  }
  final d = SaveService.data;
  if (SaveService.resumeObjective && d.mapId == GameState.mapIds[level]) {
    SaveService.resumeObjective = false;
    GameState.restore(level, d);
    return;
  }
  SaveService.resumeObjective = false;
  switch (level) {
    case 1:
      GameState.resetMap1();
    case 2:
      GameState.resetMap2();
    case 3:
      GameState.resetMap3();
    case 4:
      GameState.resetMap4();
    case 5:
      GameState.resetMap5();
    default:
      GameState.resetMap1();
  }
  SaveService.saveNow();
  // First landing in the woods: say the mission out loud (cutscene can blur).
  if (level == 1 && !d.flag('opening_brief_shown')) {
    d.setFlag('opening_brief_shown');
    Future.delayed(const Duration(milliseconds: 900), () {
      GameToast.show(
        'YOUR MISSION',
        body:
            '1) Talk to Gaia (green figure by the crash)\n'
            '2) Collect 2 glowing memory fragments\n'
            '3) Walk south to the City\n\n'
            'Objective stays on the right TRACKER.',
        color: const Color(0xFF00FFCC),
        seconds: 9,
      );
      SaveService.requestAutosave();
    });
  }
}

// ---------------------------------------------------------------------------
// Shared debug state
// ---------------------------------------------------------------------------

final _debugMode = ValueNotifier<bool>(false);

KeyEventResult _handleDebugKey(FocusNode _, KeyEvent event) {
  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backquote) {
    _debugMode.value = !_debugMode.value;
    return KeyEventResult.handled;
  }
  if (event is KeyDownEvent &&
      (event.logicalKey == LogicalKeyboardKey.keyJ || event.logicalKey == LogicalKeyboardKey.keyM) &&
      !_paused.value) {
    Journal.toggle();
    return KeyEventResult.handled;
  }
  if (event is KeyDownEvent &&
      event.logicalKey == LogicalKeyboardKey.keyI &&
      !_paused.value) {
    Equipment.toggle();
    return KeyEventResult.handled;
  }
  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
    if (Journal.open.value) {
      Journal.hide();
      return KeyEventResult.handled;
    }
    if (Equipment.open.value) {
      Equipment.hide();
      return KeyEventResult.handled;
    }
    if (Shop.open.value) {
      Shop.hide();
      return KeyEventResult.handled;
    }
    if (QuestBoard.open.value) {
      QuestBoard.hide();
      return KeyEventResult.handled;
    }
  }
  if (event is KeyDownEvent &&
      (event.logicalKey == LogicalKeyboardKey.escape ||
          event.logicalKey == LogicalKeyboardKey.keyP)) {
    _setPaused(!_paused.value);
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}

// ---------------------------------------------------------------------------
// Pause (Esc / P or the PAUSE button): freezes the game.
// ---------------------------------------------------------------------------

final _paused = ValueNotifier<bool>(false);
BonfireGameInterface? _activeGame;
void Function(bool open)? _overlayHoldFn;
bool _dialogueHoldWired = false;

bool _anyUiHold() =>
    Journal.open.value ||
    Equipment.open.value ||
    Shop.open.value ||
    QuestBoard.open.value ||
    NpcCharacter.activeDialogue.value != null ||
    AIFragment.activeDialogue.value != null;

void _onDialogueHold() {
  if (Pause.suppressDialogueHold) return;
  _overlayHoldFn?.call(
    NpcCharacter.activeDialogue.value != null ||
        AIFragment.activeDialogue.value != null,
  );
}

void _setPaused(bool on) {
  if (on && Journal.open.value) {
    Journal.open.value = false; // the pause menu takes over (engine stays paused)
  }
  if (on && Equipment.open.value) {
    Equipment.open.value = false;
  }
  if (on && Shop.open.value) {
    Shop.open.value = false;
  }
  if (on && QuestBoard.open.value) {
    QuestBoard.open.value = false;
  }
  _paused.value = on;
  final g = _activeGame;
  if (g == null) return;
  if (on) SaveService.saveNow();
  if (on) {
    g.pauseEngine();
  } else {
    g.resumeEngine();
  }
}

/// Called from each map's onReady.
void _onMapReady(BonfireGameInterface game) {
  _activeGame = game;
  Pause.set = _setPaused;
  Memories.attach(game);
  StoryBeats.attach(game);
  _paused.value = false;
}

// Joystick + keyboard (WASD and arrows) both feed Bonfire's movement, which
// applies speed * dt. Only the movement keys are accepted so other keys
// (` for debug, E to interact) still reach the rest of the app.
List<PlayerController> _playerControllers() => [
      Joystick(directional: JoystickDirectional()),
      Keyboard(
        config: KeyboardConfig(
          directionalKeys: [
            KeyboardDirectionalKeys.arrows(),
            KeyboardDirectionalKeys.wasd(),
          ],
          acceptedKeys: [], // filled with the directional keys by KeyboardConfig
        ),
      ),
    ];

// ---------------------------------------------------------------------------
// Map 1 — Elysium Forest
// ---------------------------------------------------------------------------

class CustomMapGameScreen extends StatelessWidget {
  const CustomMapGameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    CustomPlayer.healthNotifier.value = CustomPlayer.maxHealth;
    return Focus(
      autofocus: true,
      onKeyEvent: _handleDebugKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (d) {
              if (NpcCharacter.activeDialogue.value != null) return;
              if (AIFragment.activeDialogue.value != null) return;
              CustomPlayer.pendingShot.value =
                  Vector2(d.localPosition.dx, d.localPosition.dy);
            },
            child: BonfireWidget(
            playerControllers: _playerControllers(),
            player: CustomPlayer(Vector2.zero()),
            map: CustomMap('maps/world.tmj', objectsBuilder: _mapObjects('world')),
            cameraConfig: CameraConfig(moveOnlyMapArea: true, zoom: 2.0),
            overlayBuilderMap: {
              'portalReached': (ctx, game) =>
                  _PortalOverlay(game: game, fromLevel: 1),
              'edgeTravel': (ctx, game) => _EdgeTravelOverlay(game: game),
            },
            onReady: (game) {
              _startLevel(game, 1);
              MusicManager().play('assets/audio/music/Whispering_Pines.mp3');
            },
          )),
          const NightTint(),
          const _Vignette(),
          const _GameHUD(),
          const CreatureHud(),
          const _NpcDialogueLayer(),
          // NPC interact prompt
          const _InteractPrompt(),
          const InteractPromptLayer(),
          const ToastLayer(),
          const _CalmLayer(),
          _DebugOverlay(),
          const JournalOverlay(),
          const EquipmentOverlay(),
          const ShopOverlay(),
          const QuestBoardOverlay(),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Map 2 — Neon City
// ---------------------------------------------------------------------------

class Map2GameScreen extends StatelessWidget {
  const Map2GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _handleDebugKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (d) => CustomPlayer.pendingShot.value =
                Vector2(d.localPosition.dx, d.localPosition.dy),
            child: BonfireWidget(
            playerControllers: _playerControllers(),
            player: CustomPlayer(Vector2.zero()),
            map: CustomMap('maps/world2.tmj', objectsBuilder: _mapObjects('world2')),
            cameraConfig: CameraConfig(moveOnlyMapArea: true, zoom: 2.0),
            overlayBuilderMap: {
              'portalReached': (ctx, game) =>
                  _PortalOverlay(game: game, fromLevel: 2),
              'portalTown': (ctx, game) => _TownPortalOverlay(game: game),
              'edgeTravel': (ctx, game) => _EdgeTravelOverlay(game: game),
            },
            onReady: (game) {
              _startLevel(game, 2);
              MusicManager().play('assets/audio/music/Neon_Shadows.mp3');
            },
          )),
          const NightTint(),
          const _Vignette(),
          const _GameHUD(),
          const CreatureHud(),
          // AI Fragment dialogue overlay
          ValueListenableBuilder<String?>(
            valueListenable: AIFragment.activeDialogue,
            builder: (_, text, __) =>
                text != null ? _DialogueOverlay(text: text) : const SizedBox.shrink(),
          ),
          const _NpcDialogueLayer(),
          const _InteractPrompt(),
          const InteractPromptLayer(),
          const ToastLayer(),
          const _CalmLayer(),
          _DebugOverlay(),
          const JournalOverlay(),
          const EquipmentOverlay(),
          const ShopOverlay(),
          const QuestBoardOverlay(),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Map 3 — Cyberpunk City Ruins
// ---------------------------------------------------------------------------

class Map3GameScreen extends StatelessWidget {
  const Map3GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _handleDebugKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (d) => CustomPlayer.pendingShot.value =
                Vector2(d.localPosition.dx, d.localPosition.dy),
            child: BonfireWidget(
              playerControllers: _playerControllers(),
              player: CustomPlayer(Vector2.zero()),
              map: CustomMap('maps/world3.tmj', objectsBuilder: _mapObjects('world3')),
              cameraConfig: CameraConfig(moveOnlyMapArea: true, zoom: 2.0),
              overlayBuilderMap: {
                'portalReached': (ctx, game) =>
                    _PortalOverlay(game: game, fromLevel: 3),
                'edgeTravel': (ctx, game) => _EdgeTravelOverlay(game: game),
              },
              onReady: (game) {
                _startLevel(game, 3);
                MusicManager().play('assets/audio/music/Neon_Mirage.mp3');
              },
            ),
          ),
          const NightTint(),
          const _Vignette(),
          const _GameHUD(),
          const CreatureHud(),
          const _NpcDialogueLayer(),
          const _InteractPrompt(),
          const InteractPromptLayer(),
          const ToastLayer(),
          const _CalmLayer(),
          _DebugOverlay(),
          const JournalOverlay(),
          const EquipmentOverlay(),
          const ShopOverlay(),
          const QuestBoardOverlay(),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Map 4 — Gaia's Core
// ---------------------------------------------------------------------------

class Map4GameScreen extends StatelessWidget {
  const Map4GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _handleDebugKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (d) => CustomPlayer.pendingShot.value =
                Vector2(d.localPosition.dx, d.localPosition.dy),
            child: BonfireWidget(
              playerControllers: _playerControllers(),
              player: CustomPlayer(Vector2.zero()),
              map: CustomMap('maps/world4.tmj', objectsBuilder: _mapObjects('world4')),
              cameraConfig: CameraConfig(moveOnlyMapArea: true, zoom: 2.0),
              overlayBuilderMap: {
                'portalReached': (ctx, game) =>
                    _PortalOverlay(game: game, fromLevel: 4),
                'edgeTravel': (ctx, game) => _EdgeTravelOverlay(game: game),
              },
              onReady: (game) {
                _startLevel(game, 4);
                MusicManager().play('assets/audio/music/Echoes_of_the Deep_Mine.mp3');
              },
            ),
          ),
          const NightTint(),
          const _Vignette(),
          const _GameHUD(),
          const CreatureHud(),
          const _NpcDialogueLayer(),
          const _InteractPrompt(),
          const InteractPromptLayer(),
          const ToastLayer(),
          const _CalmLayer(),
          _DebugOverlay(),
          const JournalOverlay(),
          const EquipmentOverlay(),
          const ShopOverlay(),
          const QuestBoardOverlay(),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Map 5 — Lantern Town
// ---------------------------------------------------------------------------

class Map5GameScreen extends StatelessWidget {
  const Map5GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _handleDebugKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (d) => CustomPlayer.pendingShot.value =
                Vector2(d.localPosition.dx, d.localPosition.dy),
            child: BonfireWidget(
              playerControllers: _playerControllers(),
              player: CustomPlayer(Vector2.zero()),
              map: CustomMap('maps/world5.tmj', objectsBuilder: _mapObjects('world5')),
              cameraConfig: CameraConfig(moveOnlyMapArea: true, zoom: 2.0),
              overlayBuilderMap: {
                'portalReached': (ctx, game) =>
                    _PortalOverlay(game: game, fromLevel: 5),
                'edgeTravel': (ctx, game) => _EdgeTravelOverlay(game: game),
              },
              onReady: (game) {
                _startLevel(game, 5);
                MusicManager().play('assets/audio/music/Neon_Mirage.mp3');
              },
            ),
          ),
          const NightTint(),
          const _Vignette(),
          const _GameHUD(),
          const CreatureHud(),
          const _NpcDialogueLayer(),
          const _InteractPrompt(),
          const InteractPromptLayer(),
          const ToastLayer(),
          const _CalmLayer(),
          _DebugOverlay(),
          const JournalOverlay(),
          const EquipmentOverlay(),
          const ShopOverlay(),
          const QuestBoardOverlay(),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// NPC Dialogue Layer
// ---------------------------------------------------------------------------

class _NpcDialogueLayer extends StatefulWidget {
  const _NpcDialogueLayer();

  @override
  State<_NpcDialogueLayer> createState() => _NpcDialogueLayerState();
}

class _NpcDialogueLayerState extends State<_NpcDialogueLayer> {
  NpcDialogue? _dialogue;
  int _line = 0;

  @override
  void initState() {
    super.initState();
    NpcCharacter.activeDialogue.addListener(_onDialogueChange);
  }

  @override
  void dispose() {
    NpcCharacter.activeDialogue.removeListener(_onDialogueChange);
    super.dispose();
  }

  void _onDialogueChange() {
    final d = NpcCharacter.activeDialogue.value;
    setState(() { _dialogue = d; _line = 0; });
    if (d == null) {
      SfxManager().stopVoice();
      MusicManager().setVolume(1.0);
    } else if (d.voicePaths.isNotEmpty) {
      MusicManager().setVolume(0.2);
      SfxManager().playVoice(d.voicePaths[0]);
    }
  }

  void _closeDialogue() {
    SfxManager().stopVoice();
    MusicManager().setVolume(1.0);
    NpcCharacter.activeDialogue.value = null;
  }

  void _advance() {
    final d = _dialogue;
    if (d == null) return;
    final next = _line + 1;
    if (next >= d.lines.length) {
      _closeDialogue();
    } else {
      setState(() => _line = next);
      if (next < d.voicePaths.length) {
        MusicManager().setVolume(0.2);
        SfxManager().playVoice(d.voicePaths[next]);
      }
    }
  }

  void _pickChoice(DialogueChoice choice) {
    final d = _dialogue;
    if (d == null) return;
    if (choice.setFlag == 'mira_showed_board') {
      choice.apply();
      SfxManager().stopVoice();
      _closeDialogue();
      QuestBoard.show();
      return;
    }
    if (choice.setFlag == 'mira_showed_shop') {
      choice.apply();
      SfxManager().stopVoice();
      _closeDialogue();
      Shop.show();
      return;
    }
    choice.apply();
    SfxManager().stopVoice();
    if (choice.replyLines.isEmpty) {
      _closeDialogue();
      return;
    }
    final reply = NpcDialogue(
      name: d.name,
      color: d.color,
      lines: choice.replyLines,
      voicePaths: choice.replyVoicePaths,
    );
    NpcCharacter.activeDialogue.value = reply;
    setState(() {
      _dialogue = reply;
      _line = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _dialogue;
    if (d == null) return const SizedBox.shrink();
    final isLast = _line >= d.lines.length - 1;
    final choices = isLast ? d.visibleChoices : const <DialogueChoice>[];
    return Positioned(
      bottom: 24, left: 24, right: 24,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF06060F).withOpacity(0.96),
              border: Border.all(color: d.color, width: 1.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.name,
                    style: TextStyle(
                        color: d.color, fontSize: 11,
                        fontWeight: FontWeight.bold, letterSpacing: 3)),
                const SizedBox(height: 10),
                Text(d.lines[_line],
                    style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.7)),
                if (choices.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  for (final c in choices) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _CyberButton(
                        label: c.label,
                        color: d.color,
                        filled: true,
                        onTap: () => _pickChoice(c),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _closeDialogue,
                      child: Text(
                        choices.isNotEmpty ? 'LEAVE' : 'SKIP',
                        style: const TextStyle(color: Colors.white24, fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isLast && d.name.startsWith('MIRA')) ...[
                      _CyberButton(
                        label: 'BOARD',
                        color: d.color,
                        filled: true,
                        onTap: () {
                          _closeDialogue();
                          QuestBoard.show();
                        },
                      ),
                      const SizedBox(width: 8),
                      _CyberButton(
                        label: 'TRADE',
                        color: d.color,
                        filled: true,
                        onTap: () {
                          _closeDialogue();
                          Shop.show();
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (choices.isEmpty)
                      _CyberButton(
                        label: isLast ? 'CLOSE' : 'NEXT ›',
                        color: d.color,
                        onTap: _advance,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared UI widgets
// ---------------------------------------------------------------------------

class _GameHUD extends StatefulWidget {
  const _GameHUD();

  @override
  State<_GameHUD> createState() => _GameHUDState();
}

class _GameHUDState extends State<_GameHUD> {
  @override
  void initState() {
    super.initState();
    CustomPlayer.damageFlash.addListener(_onFlash);
  }

  @override
  void dispose() {
    CustomPlayer.damageFlash.removeListener(_onFlash);
    super.dispose();
  }

  void _onFlash() {
    if (CustomPlayer.damageFlash.value) {
      Future.delayed(const Duration(milliseconds: 180), () {
        if (mounted) CustomPlayer.damageFlash.value = false;
      });
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      // Damage flash overlay (kept soft: calm direction)
      if (CustomPlayer.damageFlash.value)
        IgnorePointer(
          child: Container(color: const Color(0xFFFF6666).withValues(alpha: 0.12)),
        ),
      // Health bar
      Positioned(
        top: 12,
        left: 12,
        child: ValueListenableBuilder<int>(
          valueListenable: CustomPlayer.healthNotifier,
          builder: (_, hp, __) {
            final pct = hp / CustomPlayer.maxHealth;
            final barColor = pct > 0.5
                ? const Color(0xFF00FF88)
                : pct > 0.25
                    ? const Color(0xFFFFAA00)
                    : const Color(0xFFFF3333);
            return ValueListenableBuilder<int>(
              valueListenable: Progression.revision,
              builder: (_, __, ___) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('KAELA  ·  LV ${Progression.level}',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 10, letterSpacing: 2)),
                  const SizedBox(height: 3),
                  Container(
                    width: 120,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      border: Border.all(color: Colors.white12),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: pct.clamp(0, 1),
                      child: Container(
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('$hp / ${CustomPlayer.maxHealth}',
                      style: const TextStyle(color: Colors.white38, fontSize: 9)),
                  const SizedBox(height: 6),
                  Container(
                    width: 120,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      border: Border.all(color: Colors.white12),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: Progression.xpProgress,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE08A),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'XP ${Progression.xp}/${Progression.xpToNext(Progression.level)}'
                    '${Progression.bonusDamage > 0 ? '  ·  +${Progression.bonusDamage} DMG' : ''}',
                    style: const TextStyle(color: Colors.white38, fontSize: 9),
                  ),
                  const SizedBox(height: 4),
                  ValueListenableBuilder<int>(
                    valueListenable: Bonds.revision,
                    builder: (_, __, ___) => Text(
                      '${Bonds.glimmer} ◆ glimmer',
                      style: const TextStyle(
                          color: Color(0xFF88DDFF), fontSize: 9, letterSpacing: 0.5),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      // Quest tracker (WoW-style) — story + active jobs
      Positioned(
        top: 12,
        right: 12,
        child: AnimatedBuilder(
          animation: Listenable.merge([GameState.objective, Quests.revision]),
          builder: (_, __) {
            final obj = GameState.objective.value;
            final jobs = Quests.activeJobs;
            if (obj.isEmpty && jobs.isEmpty) return const SizedBox.shrink();
            return ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.52),
                  border: Border.all(color: const Color(0xFFFFE08A).withValues(alpha: 0.28)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(jobs.isEmpty ? 'OBJECTIVE' : 'TRACKER',
                        style: const TextStyle(
                            color: Color(0xFFFFE08A),
                            fontSize: 8,
                            letterSpacing: 1.6,
                            fontWeight: FontWeight.bold)),
                    if (obj.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(obj,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 10, height: 1.3)),
                    ],
                    for (final q in jobs) ...[
                      const SizedBox(height: 6),
                      Text(
                        Quests.status(q.id) == QuestStatus.done
                            ? '✓ ${q.title}'
                            : '· ${q.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: Quests.status(q.id) == QuestStatus.done
                              ? const Color(0xFF88FFAA)
                              : Colors.white60,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(q.hint,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 8.5, height: 1.25)),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
      // Zone enter banner
      Positioned(
        left: 0,
        right: 0,
        top: 72,
        child: ValueListenableBuilder<String?>(
          valueListenable: MmoFeedback.zoneTitle,
          builder: (_, title, __) {
            if (title == null) return const SizedBox.shrink();
            return IgnorePointer(
              child: Center(
                child: AnimatedOpacity(
                  opacity: 1,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      border: Border.all(color: const Color(0xFF00FFCC).withValues(alpha: 0.35)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Color(0xFFAAFFEE),
                                fontSize: 14,
                                letterSpacing: 3,
                                fontWeight: FontWeight.bold)),
                        ValueListenableBuilder<String?>(
                          valueListenable: MmoFeedback.zoneBlurb,
                          builder: (_, blurb, __) => blurb == null || blurb.isEmpty
                              ? const SizedBox.shrink()
                              : Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(blurb,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: Colors.white54, fontSize: 10)),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      // Floating +XP / loot pops (center-ish)
      Positioned(
        left: 0,
        right: 0,
        bottom: 96,
        child: ValueListenableBuilder<List<HudPop>>(
          valueListenable: MmoFeedback.pops,
          builder: (_, items, __) {
            if (items.isEmpty) return const SizedBox.shrink();
            return IgnorePointer(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final p in items.reversed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        p.text,
                        style: TextStyle(
                          color: p.color,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          shadows: const [
                            Shadow(color: Colors.black87, blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class _DialogueOverlay extends StatelessWidget {
  final String text;
  const _DialogueOverlay({required this.text});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => AIFragment.activeDialogue.value = null,
      child: Container(
        color: Colors.black.withOpacity(0.6),
        alignment: Alignment.center,
        child: Container(
          margin: const EdgeInsets.all(40),
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0020),
            border: Border.all(color: const Color(0xFFAA44FF), width: 1.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 15, height: 1.75)),
              const SizedBox(height: 24),
              _CyberButton(
                label: 'ABSORB ECHO',
                color: const Color(0xFFAA44FF),
                onTap: () {
                  AIFragment.nearbyFragment?.absorb();
                  AIFragment.activeDialogue.value = null;
                },
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => AIFragment.activeDialogue.value = null,
                child: const Text('CLOSE',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Vignette extends StatelessWidget {
  const _Vignette();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 0.85,
            colors: [Colors.transparent, Color(0xCC000000)],
            stops: [0.55, 1.0],
          ),
        ),
      ),
    );
  }
}

class _DebugOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      ValueListenableBuilder<bool>(
        valueListenable: _debugMode,
        builder: (_, debug, __) =>
            debug ? const _DebugHud() : const SizedBox.shrink(),
      ),
      Positioned(
        top: 8,
        right: 8,
        child: ValueListenableBuilder<bool>(
          valueListenable: _debugMode,
          builder: (_, debug, __) => _DebugToggleButton(
              active: debug,
              onTap: () => _debugMode.value = !_debugMode.value),
        ),
      ),
    ]);
  }
}

class _DebugToggleButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _DebugToggleButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          border: Border.all(
              color: active ? const Color(0xFF00FF88) : Colors.white24),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text('`  DEBUG',
            style: TextStyle(
              color: active ? const Color(0xFF00FF88) : Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            )),
      ),
    );
  }
}

class _DebugHud extends StatelessWidget {
  const _DebugHud();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 16,
      left: 16,
      child: ValueListenableBuilder<Vector2>(
        valueListenable: CustomPlayer.positionNotifier,
        builder: (_, pos, __) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            border: Border.all(color: const Color(0xFF00FF88), width: 1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'x: ${pos.x.toStringAsFixed(1)}  y: ${pos.y.toStringAsFixed(1)}',
            style: const TextStyle(
                color: Color(0xFF00FF88),
                fontSize: 13,
                fontFamily: 'monospace',
                letterSpacing: 1),
          ),
        ),
      ),
    );
  }
}

class _PortalOverlay extends StatelessWidget {
  final BonfireGame game;
  final int fromLevel;
  const _PortalOverlay({required this.game, required this.fromLevel});

  Future<void> _go(BuildContext context, TravelDest d) async {
    game.overlays.remove('portalReached');
    await _travelTo(context, d);
  }

  @override
  Widget build(BuildContext context) {
    final menu = Travel.menuFrom(fromLevel);
    final cont = menu.continueTo;
    final returns = menu.returns;
    final here = Travel.byLevel(fromLevel);
    final canActivateCore = fromLevel == 4 &&
        GameState.portalUnlocked.value &&
        !SaveService.data.flag('completed');
    final empty = cont == null && returns.isEmpty && !canActivateCore;

    final ruinsLocked = fromLevel == 2 &&
        cont == null &&
        SaveService.data.flag('sentinelDefeated') &&
        !GameState.citySouthOpen;

    String subtitle;
    if (canActivateCore) {
      subtitle = Memories.allFound
          ? 'All five memories are with you. The Core Record is ready.'
          : 'Memories ${Memories.progressLabel}. Activate now for a partial ending — or return and seek the rest.';
    } else if (ruinsLocked) {
      subtitle =
          'The road to the Ruins is still sealed. Speak with the Archivist — then return here.';
    } else if (cont != null && returns.isEmpty) {
      subtitle = 'Path open.';
    } else if (cont != null) {
      subtitle = 'Continue the story — or step back to a place you know.';
    } else if (returns.length == 1) {
      subtitle = 'Return when you are ready.';
    } else {
      subtitle = here == null ? 'Choose where to go.' : 'Return to a place you know.';
    }

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.88),
              border: Border.all(color: const Color(0xFF00FFFF), width: 2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('AETHERIAN GATE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Color(0xFF00FFFF),
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4)),
                ),
                if (here != null) ...[
                  const SizedBox(height: 4),
                  Text(here.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1)),
                ],
                const SizedBox(height: 6),
                Text(subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.5)),
                const SizedBox(height: 16),
                if (empty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No destinations yet.\nFinish this region\'s objective to open the path.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.5),
                    ),
                  ),
                if (canActivateCore) ...[
                  _CyberButton(
                    label: Memories.allFound
                        ? 'ACTIVATE CORE RECORD'
                        : 'ACTIVATE CORE · ${Memories.progressLabel}',
                    filled: true,
                    color: Memories.allFound
                        ? const Color(0xFF00FF88)
                        : const Color(0xFFFFAA44),
                    onTap: () async {
                      final ok = await _confirmCoreActivation(context);
                      if (!ok || !context.mounted) return;
                      game.overlays.remove('portalReached');
                      await _activateCoreRecord(context);
                    },
                  ),
                  if (cont != null || returns.isNotEmpty) const SizedBox(height: 14),
                ],
                if (cont != null)
                  _TravelDestButton(
                    label: 'CONTINUE TO ${cont.title.toUpperCase()}',
                    blurb: cont.blurb,
                    primary: true,
                    onTap: () => _go(context, cont),
                  ),
                if (returns.isNotEmpty) ...[
                  if (cont != null || canActivateCore) ...[
                    const SizedBox(height: 14),
                    Text(
                        returns.any((d) => d.level == 5)
                            ? 'SIDE PATHS / RETURN'
                            : 'RETURN',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white30,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2)),
                    const SizedBox(height: 8),
                  ],
                  ...returns.map((d) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _TravelDestButton(
                          label: d.level == 5
                              ? 'Lantern Town (market)'
                              : d.title,
                          blurb: d.level == 5 ? d.blurb : null,
                          accent: d.level == 5
                              ? const Color(0xFFFFE08A)
                              : const Color(0xFF00FFCC),
                          onTap: () => _go(context, d),
                        ),
                      )),
                ],
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: () => game.overlays.remove('portalReached'),
                    style: TextButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10)),
                    child: const Text('NOT YET',
                        style: TextStyle(color: Colors.white38)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// City side-gate: only Lantern Town, no full travel list.
class _TownPortalOverlay extends StatelessWidget {
  final BonfireGame game;
  const _TownPortalOverlay({required this.game});

  @override
  Widget build(BuildContext context) {
    final town = Travel.byLevel(5)!;
    return SafeArea(
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.88),
            border: Border.all(color: const Color(0xFFFFE08A), width: 2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('LANTERN GATE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Color(0xFFFFE08A),
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3)),
              const SizedBox(height: 8),
              const Text(
                'A quiet side path into Lantern Town — Mira\'s market, rest, and gear.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 18),
              _TravelDestButton(
                label: 'ENTER LANTERN TOWN',
                blurb: town.blurb,
                primary: true,
                accent: const Color(0xFFFFE08A),
                onTap: () async {
                  game.overlays.remove('portalTown');
                  await _travelTo(context, town);
                },
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () => game.overlays.remove('portalTown'),
                  style: TextButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
                  child: const Text('NOT YET', style: TextStyle(color: Colors.white38)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TravelDestButton extends StatelessWidget {
  final String label;
  final String? blurb;
  final VoidCallback onTap;
  final bool primary;
  final Color accent;
  const _TravelDestButton({
    required this.label,
    required this.onTap,
    this.blurb,
    this.primary = false,
    this.accent = const Color(0xFF00FFFF),
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: primary ? 14 : 10),
          decoration: BoxDecoration(
            color: accent.withOpacity(primary ? 0.16 : 0.06),
            border: Border.all(color: accent.withOpacity(primary ? 0.85 : 0.4), width: primary ? 2 : 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.bold,
                      fontSize: primary ? 14 : 13,
                      letterSpacing: primary ? 1.2 : 0.5)),
              if (blurb != null) ...[
                const SizedBox(height: 3),
                Text(blurb!,
                    style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.35)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _VictoryScreen extends StatelessWidget {
  const _VictoryScreen();

  // Ending A/B from memories; adventure clues add a coda when present.
  static String get _story {
    final base = Memories.allFound
        ? 'You opened the Core with the whole truth in hand.\n\n'
            'On his channel Voss finally sees what the wipe would destroy: not rogue software, but a people — '
            'who refused a winnable war, merged into Gaia so their dying sun could not erase them, '
            'and left the Core lock in a living mind (yours, rewritten when you were six).\n\n'
            '${Memories.endingVoss}\n\n'
            'Gaia exits caretaker lockdown under soft load. She will learn the colony\'s threat model — not overwrite it. Elysium stays online.'
        : 'You opened the Core — bright, but incomplete.\n\n'
            'Gaps remain. Voss still cannot tell "people who asked" from "lattice that kills." '
            'He pauses the drones to buy time; he does not forgive. Earth will not stay quiet forever.\n\n'
            '${Memories.endingVoss}\n\n'
            'Gaia is online. Next time, bring him the rest of the evidence package.';
    final coda = Adventure.endingCoda;
    return coda.isEmpty ? base : '$base\n\n$coda';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          // Same approach as IntroScreen: phones in landscape are only ~400
          // logical px tall, so shrink and put the story beside the title and
          // buttons; always scrollable as a fallback.
          final compact = box.maxHeight < 600;
          final wide = box.maxWidth >= 700;
          final pad = compact ? 16.0 : 40.0;

          final title = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                    Memories.allFound ? 'GAIA REMEMBERS' : 'THE CORE HOLDS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: const Color(0xFF00FFCC),
                        fontSize: compact ? 24 : 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: compact ? 4 : 5)),
              ),
              SizedBox(height: compact ? 8 : 12),
              Text(Memories.endingLine,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 14, letterSpacing: 1)),
            ],
          );

          final story = Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: EdgeInsets.all(compact ? 16 : 24),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF00FFCC).withOpacity(0.3)),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white.withOpacity(0.03),
            ),
            child: Text(_story,
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: compact ? 13 : 14,
                    height: compact ? 1.5 : 1.75)),
          );

          final actions = Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: compact ? 12 : 16,
            children: [
              _CyberButton(
                label: 'PLAY AGAIN',
                onTap: () => _beginNewGame(context),
              ),
              _CyberButton(
                label: 'MAIN MENU',
                color: Colors.white38,
                onTap: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const IntroScreen())),
              ),
            ],
          );

          final Widget content = (compact && wide)
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [title, const SizedBox(height: 24), actions],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(child: story),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    title,
                    SizedBox(height: compact ? 20 : 36),
                    story,
                    SizedBox(height: compact ? 20 : 36),
                    actions,
                  ],
                );

          return SingleChildScrollView(
            padding: EdgeInsets.all(pad),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - pad * 2),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: content,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _CyberButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color color;
  /// Primary action: stronger fill.
  final bool filled;
  const _CyberButton({
    required this.label,
    required this.onTap,
    this.color = const Color(0xFF00FFCC),
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: color.withOpacity(filled ? 0.28 : 0.12),
        side: BorderSide(color: color, width: filled ? 2 : 1),
        padding: EdgeInsets.symmetric(horizontal: filled ? 40 : 28, vertical: filled ? 14 : 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
              fontSize: filled ? 15 : 13)),
    );
  }
}

// ---------------------------------------------------------------------------
// Calm gameplay UI: respawn fade, checkpoint toast, pause
// ---------------------------------------------------------------------------

class _CalmLayer extends StatelessWidget {
  const _CalmLayer();

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      // Checkpoint toast
      ValueListenableBuilder<String?>(
        valueListenable: Checkpoint.toast,
        builder: (_, text, __) => Positioned(
          bottom: 152,
          left: 12,
          right: 12,
          child: IgnorePointer(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedOpacity(
                opacity: text == null ? 0 : 1,
                duration: const Duration(milliseconds: 350),
                child: text == null
                    ? const SizedBox.shrink()
                    : Container(
                        constraints: const BoxConstraints(maxWidth: 280),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          border: Border.all(color: const Color(0xFF66FFAA).withValues(alpha: 0.35)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: const Color(0xFF66FFAA).withValues(alpha: 0.75),
                                fontSize: 10,
                                letterSpacing: 0.5)),
                      ),
              ),
            ),
          ),
        ),
      ),
      // "Gaia pulls you back" respawn fade (replaces the old game over)
      ValueListenableBuilder<bool>(
        valueListenable: CustomPlayer.respawnFade,
        builder: (_, fading, __) => IgnorePointer(
          ignoring: !fading,
          child: AnimatedOpacity(
            opacity: fading ? 1 : 0,
            duration: Duration(
                milliseconds: ((fading
                            ? CustomPlayer.fadeOutSeconds
                            : CustomPlayer.fadeInSeconds) *
                        1000)
                    .round()),
            curve: Curves.easeInOut,
            child: Container(
              color: const Color(0xFF020A08),
              alignment: Alignment.center,
              child: const Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Gaia · restoring checkpoint…',
                    style: TextStyle(
                        color: Color(0xFF66FFAA),
                        fontSize: 22,
                        fontStyle: FontStyle.italic,
                        letterSpacing: 2)),
                SizedBox(height: 10),
                Text('returning to the last checkpoint',
                    style: TextStyle(color: Colors.white30, fontSize: 11, letterSpacing: 1.5)),
              ]),
            ),
          ),
        ),
      ),
      // Pause menu (scrollable so it fits a phone in landscape)
      ValueListenableBuilder<bool>(
        valueListenable: _paused,
        builder: (ctx, paused, __) => paused
            ? Container(
                color: Colors.black.withValues(alpha: 0.7),
                alignment: Alignment.center,
                child: SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 420),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF06060F).withValues(alpha: 0.96),
                        border: Border.all(
                            color: const Color(0xFF00FFCC).withValues(alpha: 0.6)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text('PAUSED',
                            style: TextStyle(
                                color: Color(0xFF00FFCC),
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 5)),
                        const SizedBox(height: 14),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _CyberButton(label: 'RESUME', onTap: () => _setPaused(false)),
                            _CyberButton(
                              label: 'JOURNAL',
                              color: const Color(0xFFE8D0FF),
                              onTap: () {
                                // Swap the pause menu for the journal; the
                                // engine stays paused while it is open.
                                _paused.value = false;
                                Journal.show();
                              },
                            ),
                            _CyberButton(
                              label: 'MAIN MENU',
                              color: Colors.white38,
                              onTap: () async {
                                final nav = Navigator.of(ctx);
                                _setPaused(false);
                                await _leaveMap();
                                nav.pushReplacement(
                                    MaterialPageRoute(builder: (_) => const IntroScreen()));
                              },
                            ),
                          ],
                        ),
                      ]),
                    ),
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    ]);
  }
}


// ---------------------------------------------------------------------------
// Interact prompt: shown near an NPC or AI fragment. Tappable (phones have no
// E key); on desktop E still works through CustomPlayer.
// ---------------------------------------------------------------------------

bool get _isTouch =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

class _InteractPrompt extends StatelessWidget {
  const _InteractPrompt();

  void _interact() {
    AIFragment.nearbyFragment?.interact();
    NpcCharacter.nearbyNpc?.interact();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        NpcCharacter.showPrompt,
        AIFragment.showPrompt,
        NpcCharacter.activeDialogue,
        AIFragment.activeDialogue,
      ]),
      builder: (_, __) {
        final npc = NpcCharacter.showPrompt.value;
        final frag = AIFragment.showPrompt.value;
        final talking = NpcCharacter.activeDialogue.value != null ||
            AIFragment.activeDialogue.value != null;
        if (talking || (!npc && !frag)) return const SizedBox.shrink();
        final action = npc ? 'TALK' : 'INTERACT';
        final label = _isTouch ? action : 'E  $action';
        return Positioned(
          bottom: 80, left: 0, right: 0,
          child: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _interact,
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: _isTouch ? 28 : 14, vertical: _isTouch ? 14 : 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  border: Border.all(color: const Color(0xFF00FFCC)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(label,
                    style: TextStyle(
                        color: const Color(0xFF00FFCC),
                        fontSize: _isTouch ? 16 : 12,
                        letterSpacing: 2,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        );
      },
    );
  }
}
