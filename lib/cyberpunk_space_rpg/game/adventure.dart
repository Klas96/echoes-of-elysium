import 'package:flutter/foundation.dart';

import '../creatures/bonds.dart';
import 'save_service.dart';

/// A journal clue unlocked by examining, talking, or using a key item.
@immutable
class ClueDef {
  final String id;
  final String title;
  final String body;
  final String where;

  const ClueDef({
    required this.id,
    required this.title,
    required this.body,
    required this.where,
  });
}

/// Player-facing names for key items carried via Bonds (`item:<id>`).
const itemLabels = <String, String>{
  'uec_override': 'UEC Override Key',
  'archive_seal': 'Archive Seal',
  'moonflower_bloom': 'Moonflower Bloom',
  'ruins_gate_key': 'Aetherian Keystone',
};

/// Branching talk options shown on the last line of an [NpcDialogue].
@immutable
class DialogueChoice {
  final String label;
  final List<String> replyLines;
  final List<String> replyVoicePaths;
  final String? giveItem;
  final String? setFlag;
  final String? discoverClue;
  /// Hide this choice once the flag is already set.
  final String? requireFlagUnset;
  /// Hide once the player already carries or has used this item.
  final String? requireNoItem;

  const DialogueChoice({
    required this.label,
    this.replyLines = const [],
    this.replyVoicePaths = const [],
    this.giveItem,
    this.setFlag,
    this.discoverClue,
    this.requireFlagUnset,
    this.requireNoItem,
  });

  bool get visible {
    if (requireFlagUnset != null && Adventure.flag(requireFlagUnset!)) return false;
    if (requireNoItem != null &&
        (Bonds.hasItem(requireNoItem!) || Bonds.usedItem(requireNoItem!))) {
      return false;
    }
    return true;
  }

  void apply() {
    if (giveItem != null) Bonds.giveItem(giveItem!);
    if (setFlag != null) Adventure.setFlag(setFlag!);
    if (discoverClue != null) Adventure.discover(discoverClue!);
  }
}

/// Examine / talk / key-item adventure layer on top of [SaveService] flags.
class Adventure {
  static final revision = ValueNotifier<int>(0);

  static SaveData get _d => SaveService.data;

  static void _bump({bool now = false}) {
    revision.value++;
    Bonds.revision.value++;
    if (now) {
      SaveService.saveNow();
    } else {
      SaveService.requestAutosave();
    }
  }

  static bool flag(String key) => _d.flag(key);
  static void setFlag(String key, [bool value = true]) {
    if (_d.flag(key) == value) return;
    _d.setFlag(key, value);
    _bump();
  }

  static bool hasClue(String id) => _d.flag('clue:$id');

  /// Returns true the first time this clue is found.
  static bool discover(String id) {
    if (hasClue(id)) return false;
    _d.setFlag('clue:$id');
    _bump();
    return true;
  }

  static List<ClueDef> get found =>
      [for (final c in catalog) if (hasClue(c.id)) c];

  static ClueDef? byId(String id) {
    for (final c in catalog) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Used the override on the City UEC terminal (or has the clue).
  static bool get readUecOrders => hasClue('uec_orders') || flag('read_uec_orders');

  /// Opened the Archive Library with the seal.
  static bool get openedArchive =>
      hasClue('archive_first_memory') || flag('archive_opened');

  /// Extra victory paragraphs when key clues shaped the ending.
  static String get endingCoda {
    final parts = <String>[];
    if (readUecOrders) {
      parts.add(
        'The Station Seven orders stay on your slate — not as a weapon, but as proof that fear already wrote UEC policy once.');
    }
    if (openedArchive) {
      parts.add(
        'The archive draft travels with Gaia\'s waking: the merge was never clean courage. It was a whisper of a vote, and you chose to remember it.');
    }
    if (flag('said_trust_gaia') && flag('promised_echo')) {
      parts.add(
        'Asha\'s trust and Echo-7\'s promise both held. The living and the remembered share the same sky tonight.');
    }
    if (flag('asha_archive_ack') || hasClue('asha_on_archive')) {
      parts.add(
        'Asha\'s channel still echoes: carry the fear with the hope. Voss heard a people tonight — not only a lattice.');
    }
    // Quests.turnedInCount imported via save flags to avoid a circular import.
    final jobs = [
      'quest:courier_pack:turned_in',
      'quest:drone_nest:turned_in',
      'quest:moonflower_draft:turned_in',
      'quest:city_east_nest:turned_in',
      'quest:city_se_patrol:turned_in',
      'quest:city_west_cache:turned_in',
    ].where(flag).length;
    if (jobs >= 2) {
      parts.add(
        'Lantern Town\'s errands followed you into the Core — woods trails and city alleys both. The colony still believes in small kindnesses.');
    }
    if (flag('ruins_gate_open') || hasClue('ruins_keystone')) {
      parts.add(
        'You carried the keystone through the SE gate. The Core did not open for the UEC — it opened for a living hand.');
    }
    return parts.join('\n\n');
  }

  static const catalog = <ClueDef>[
    ClueDef(
      id: 'boot_print',
      title: 'UEC Boot Print',
      body:
          'Fresh composite sole marks in the moss — patrol size. Someone from the coalition walked this trail after the rain.',
      where: 'Woods · near Asha',
    ),
    ClueDef(
      id: 'gaia_plaque',
      title: 'Weathered Plaque',
      body:
          '"We did not conquer this world. We asked to stay." Beneath, a later cut: "Bodies to soil. Minds to Gaia." — not sleep. Merge.',
      where: 'Woods · crash site',
    ),
    ClueDef(
      id: 'aetherian_merge',
      title: 'The Merge',
      body:
          'The colony tagged Gaia as a caretaker AI. Incomplete: she is also an Aetherian upload lattice — minds in process, bodies returned — so a dying sun could not erase them. She ran quiet in caretaker mode until Kaela\'s diagnostic opened the channel.',
      where: 'Woods · Gaia',
    ),
    ClueDef(
      id: 'asha_warning',
      title: "Asha's Warning",
      body:
          'She kept a UEC override after Station Seven. Trust is not the same as certainty — she wants a way out if Gaia lies.',
      where: 'Woods · Asha',
    ),
    ClueDef(
      id: 'override_key',
      title: 'Override Key Taken',
      body:
          'Asha handed you a single-use UEC field override. It opens coalition terminals — and could still cut a lattice signal.',
      where: 'Woods · Asha',
    ),
    ClueDef(
      id: 'echo_split',
      title: 'The Split Vote',
      body:
          'Echo-7 remembers fear as clearly as peace. Not every Aetherian chose the merge. Some only had nowhere else to go.',
      where: 'City · Echo-7',
    ),
    ClueDef(
      id: 'archivist_seal',
      title: 'Archive Seal',
      body:
          'The Archivist entrusted you with the seal to the library across the avenue. Inside: Gaia\'s first written memory.',
      where: 'City · Archivist',
    ),
    ClueDef(
      id: 'city_archive_hint',
      title: 'Archive Plaque',
      body:
          'The library holds first-memory drafts — not the Core itself. Worth opening before you face Voss\'s wipe.',
      where: 'City · Archive',
    ),
    ClueDef(
      id: 'city_yard_memo',
      title: 'Scout Slate',
      body:
          'UEC scouts were ordered to avoid the archive walls. Something there still hums on Aetherian frequencies.',
      where: 'City · west yard',
    ),
    ClueDef(
      id: 'ruins_landing',
      title: 'Landing Mark',
      body:
          'Wipe paint on Aetherian stone — scratched out by a later hand. Someone already doubted the order.',
      where: 'Ruins · landing',
    ),
    ClueDef(
      id: 'ruins_ring',
      title: 'Broken Ring',
      body:
          'A cracked memory circle. The south-west shrine path feels warmer — Memory 5 waits off the main road.',
      where: 'Ruins · clearing',
    ),
    ClueDef(
      id: 'ruins_dead_end',
      title: 'Dead-End Terminal',
      body:
          'UEC noted a \"civilian anomaly\" by the shrine. The south-west dead end holds a memory fragment — worth the detour before the Core.',
      where: 'Ruins · south-west',
    ),
    ClueDef(
      id: 'station_seven',
      title: 'Station Seven',
      body:
          'Three hundred colonists went dark when a lattice woke. Voss still carries their names. That is why he hunts Gaia.',
      where: 'City · talk',
    ),
    ClueDef(
      id: 'voss_motive',
      title: "Voss's Motive",
      body:
          'He is not erasing history for sport. He is choosing the living over the dead — and he believes you will bury another colony.',
      where: 'City · Voss',
    ),
    ClueDef(
      id: 'uec_orders',
      title: 'Field Orders · Station Seven',
      body:
          'Terminal log: "Sympathetic AI classified for erasure. Collateral risk accepted." Voss signed the follow-up quarantine. Asha\'s name is on the desertion list.',
      where: 'City · UEC terminal',
    ),
    ClueDef(
      id: 'archive_first_memory',
      title: 'First Memory Draft',
      body:
          'A brittle page: "If we merge, we stop dying with our sun. If we do not, we end as dust that remembers nothing." The vote passed by a whisper.',
      where: 'City · Archive Library',
    ),
    ClueDef(
      id: 'asha_on_archive',
      title: "Asha's Channel",
      body:
          'Asha caught the Archive spike on her comms. She heard the whisper-vote too: not clean courage — people scared enough to become the world. She wants that fear carried to the Core, where Voss only hears weapons.',
      where: 'City · Archive · Asha link',
    ),
    ClueDef(
      id: 'mira_rumour',
      title: "Mira's Rumour",
      body:
          'Lantern Town traders say UEC drones avoid the old archive. Something in the walls still hums on Aetherian frequencies.',
      where: 'Lantern Town · Mira',
    ),
    ClueDef(
      id: 'quest_courier',
      title: 'Courier Pack Found',
      body:
          'You recovered a sealed town pack on the west woods trail. Mira\'s board pays for proof that travellers still finish errands.',
      where: 'Woods · west loop · Town board',
    ),
    ClueDef(
      id: 'quest_nest',
      title: 'Nest Cleared',
      body:
          'Two UEC units held the west loop. Their slate called it a nest until recall. Lantern Town sleeps easier with them gone.',
      where: 'Woods · west loop · Town board',
    ),
    ClueDef(
      id: 'quest_nest_slate',
      title: 'Nest Field Slate',
      body:
          'UEC roster for a quiet mid-woods nest: hold until recall. Someone in Town already knew.',
      where: 'Woods · west loop',
    ),
    ClueDef(
      id: 'quest_moonflower',
      title: 'Moonflower Delivered',
      body:
          'A bloom from the SCENT trail, cold as glass. Mira needed it for the sick — and for the lamps that keep Town honest.',
      where: 'Woods · moonflowers · Town board',
    ),
    ClueDef(
      id: 'quest_city_east',
      title: 'East Lot Cleared',
      body:
          'The east lot nest is quiet. Town sleeps easier knowing the avenue\'s flank is clear.',
      where: 'City · east lot · Town board',
    ),
    ClueDef(
      id: 'quest_city_east_slate',
      title: 'East Lot Slate',
      body:
          'UEC nest roster for the east lot. Someone in Lantern Town already had the job posted.',
      where: 'City · east lot',
    ),
    ClueDef(
      id: 'quest_city_se',
      title: 'South Alley Sweep',
      body:
          'You recovered the dead patrol pad from the SE alley. Another quiet UEC hole plugged.',
      where: 'City · SE alley · Town board',
    ),
    ClueDef(
      id: 'quest_city_west',
      title: 'West Cache Recovered',
      body:
          'Trader salvage from the west alley, marked for Mira\'s board. The colony still shares.',
      where: 'City · west alley · Town board',
    ),
    ClueDef(
      id: 'ruins_keystone',
      title: 'Aetherian Keystone',
      body:
          'A cold keystone from the north-east wing. The SE gate toward the Core will accept only this.',
      where: 'Ruins · NE key wing',
    ),
    ClueDef(
      id: 'ruins_gate_open',
      title: 'SE Gate Opened',
      body:
          'The lattice lock accepted the keystone. The road to the Core is a choice you unlocked — not a UEC breach.',
      where: 'Ruins · SE gate',
    ),
    ClueDef(
      id: 'shrine_note',
      title: 'Shrine Scratching',
      body:
          'Someone carved into the ruin shrine base: "Core below. Choose before he does." The cut is recent.',
      where: 'Ruins · shrine',
    ),
    ClueDef(
      id: 'core_console',
      title: 'Core Console',
      body:
          'Activation requires a living neural match — yours. The console will not choose for you. Voss\'s remote wipe is already queued.',
      where: 'Core · threshold',
    ),
  ];
}
