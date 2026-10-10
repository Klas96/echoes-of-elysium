import 'package:flutter/foundation.dart';

import '../creatures/bonds.dart';
import 'adventure.dart';
import 'game_state.dart';
import 'progression.dart';
import 'save_service.dart';

enum QuestStatus { locked, available, accepted, done, turnedIn }

@immutable
class QuestDef {
  final String id;
  final String title;
  final String blurb;
  /// Where to do the fieldwork (woods / city).
  final String hint;
  /// Region badge for board/journal (`woods`, `city`, …).
  final String region;
  final int glimmer;
  final String? gearId;
  final String clueId;
  /// If set, turn-in requires this Bonds item (consumed).
  final String? requiresItem;
  /// How many nest-tagged drone kills complete this job (0 = examine-only).
  final int nestKills;

  /// Drone kills anywhere in [region] that complete this job (0 = none).
  final int regionKills;

  /// Examining this hotspot id (Tiled `examine` object) completes the job.
  final String? examineId;

  /// Board shows the job as LOCKED until any of these story flags is set.
  final List<String> unlockFlags;

  /// Shown while locked.
  final String lockedHint;

  const QuestDef({
    required this.id,
    required this.title,
    required this.blurb,
    required this.hint,
    required this.region,
    required this.glimmer,
    required this.clueId,
    this.gearId,
    this.requiresItem,
    this.nestKills = 0,
    this.regionKills = 0,
    this.examineId,
    this.unlockFlags = const [],
    this.lockedHint = '',
  });

  int get killTarget => nestKills > 0 ? nestKills : regionKills;

  /// Board badge while accepted, e.g. `IN CITY`.
  String get acceptedBoardLabel => 'IN ${region.toUpperCase()}';

  /// Journal line while accepted, e.g. `in city`.
  String get acceptedJournalLabel => 'in $region';
}

/// Lantern Town job board — woods, city, ruins and core loops.
class Quests {
  Quests._();

  static final revision = ValueNotifier<int>(0);

  static const catalog = <QuestDef>[
    // --- Woods (Phase A) ---
    QuestDef(
      id: 'courier_pack',
      title: 'Lost Courier Pack',
      blurb:
          'A runner dropped a sealed pack in the west hollow below the crash site. Bring word that it was found.',
      hint: 'Woods · west hollow, on the loop below the crash site.',
      region: 'woods',
      glimmer: 25,
      clueId: 'quest_courier',
    ),
    QuestDef(
      id: 'drone_nest',
      title: 'Quiet the Nest',
      blurb:
          'UEC left a quiet nest mid-woods. Clear the drones and read their field slate.',
      hint: 'Woods · nest spur off the south-west bend of the west loop.',
      region: 'woods',
      glimmer: 10,
      gearId: 'scrap_plating',
      clueId: 'quest_nest',
      nestKills: 2,
    ),
    QuestDef(
      id: 'moonflower_draft',
      title: 'Moonflower for the Sick',
      blurb:
          'Mira needs a moonflower bloom from the SCENT trail. Pick one and bring it home.',
      hint: 'Woods · south-west trail, just west of Asha\'s camp.',
      region: 'woods',
      glimmer: 15,
      gearId: 'lantern_charm',
      clueId: 'quest_moonflower',
      requiresItem: 'moonflower_bloom',
    ),
    // --- City (Phase B) ---
    QuestDef(
      id: 'city_east_nest',
      title: 'East Lot Nest',
      blurb:
          'UEC parked a nest on the east lot below the Lantern Gate. Quiet it before they reinforce.',
      hint: 'City · east lot, south of the Lantern Gate.',
      region: 'city',
      glimmer: 18,
      gearId: 'pulse_optic',
      clueId: 'quest_city_east',
      nestKills: 2,
    ),
    QuestDef(
      id: 'city_se_patrol',
      title: 'South Alley Sweep',
      blurb:
          'A patrol slate went dark in the south-east patrol alley. Find it — and whatever is watching it.',
      hint: 'City · patrol alley, between the east lot and Sentinel plaza.',
      region: 'city',
      glimmer: 20,
      clueId: 'quest_city_se',
      nestKills: 1,
    ),
    QuestDef(
      id: 'city_west_cache',
      title: 'West Alley Cache',
      blurb:
          'Traders stashed a cache in the west lane above Echo district. Recover the marked crate.',
      hint: 'City · west lane between Market Row and Echo district.',
      region: 'city',
      glimmer: 22,
      gearId: 'swarm_thrusters',
      clueId: 'quest_city_west',
    ),
    // --- Ruins (Phase C) ---
    QuestDef(
      id: 'ruins_landing_rubbing',
      title: 'Paint Over Stone',
      blurb:
          'Someone scratched out a UEC order at the ruined landing. Read what is left before the rain takes it.',
      hint: 'Ruins · landing mark by the north road.',
      region: 'ruins',
      glimmer: 18,
      clueId: 'quest_ruins_landing',
      examineId: 'ruins_landing_mark',
      unlockFlags: ['sentinelDefeated', 'visited:ruins'],
      lockedHint: 'Opens once the road to the Ruins is clear.',
    ),
    QuestDef(
      id: 'ruins_lattice_sweep',
      title: 'Lattice Sweep',
      blurb:
          'Drones keep circling the old lattice. Down three of them so the scavengers can work.',
      hint: 'Ruins · any UEC drones.',
      region: 'ruins',
      glimmer: 24,
      gearId: 'barrier_coil',
      clueId: 'quest_ruins_sweep',
      regionKills: 3,
      unlockFlags: ['sentinelDefeated', 'visited:ruins'],
      lockedHint: 'Opens once the road to the Ruins is clear.',
    ),
    QuestDef(
      id: 'ruins_shrine_waymarker',
      title: 'Shrine Waymarker',
      blurb:
          'A dead UEC pad points at an anomaly south-west. Find the waymarker and log the reading for Mira.',
      hint: 'Ruins · SW waymarker past the clearing.',
      region: 'ruins',
      glimmer: 20,
      clueId: 'quest_ruins_shrine',
      examineId: 'ruins_dead_end',
      unlockFlags: ['sentinelDefeated', 'visited:ruins'],
      lockedHint: 'Opens once the road to the Ruins is clear.',
    ),
    // --- Core (Phase D) ---
    QuestDef(
      id: 'core_static',
      title: 'Core Static',
      blurb:
          'UEC drones hum in Gaia\'s halls. Quiet two so the Core can hear itself think.',
      hint: 'Core · any UEC drones.',
      region: 'core',
      glimmer: 28,
      clueId: 'quest_core_static',
      regionKills: 2,
      unlockFlags: ['ruins_gate_open', 'visited:core'],
      lockedHint: 'Opens once the sealed gate in the Ruins is open.',
    ),
    QuestDef(
      id: 'core_console_reading',
      title: 'Console Reading',
      blurb:
          'Mira wants the wipe queue in writing. Read the Core console and bring back what it says.',
      hint: 'Core · the console by the dais.',
      region: 'core',
      glimmer: 30,
      clueId: 'quest_core_console',
      examineId: 'core_console',
      unlockFlags: ['ruins_gate_open', 'visited:core'],
      lockedHint: 'Opens once the sealed gate in the Ruins is open.',
    ),
  ];

  static SaveData get _d => SaveService.data;

  static void _bump({bool now = false}) {
    revision.value++;
    Adventure.revision.value++;
    Bonds.revision.value++;
    GameState.refreshObjective();
    if (now) {
      SaveService.saveNow();
    } else {
      SaveService.requestAutosave();
    }
  }

  static String _accepted(String id) => 'quest:$id:accepted';
  static String _done(String id) => 'quest:$id:done';
  static String _turnedIn(String id) => 'quest:$id:turned_in';
  static String _killFlag(String id, int n) => 'quest:$id:kill$n';

  static QuestDef? def(String id) {
    for (final q in catalog) {
      if (q.id == id) return q;
    }
    return null;
  }

  static QuestStatus status(String id) {
    if (_d.flag(_turnedIn(id))) return QuestStatus.turnedIn;
    if (_d.flag(_done(id))) return QuestStatus.done;
    if (_d.flag(_accepted(id))) return QuestStatus.accepted;
    final q = def(id);
    if (q != null && q.unlockFlags.isNotEmpty && !q.unlockFlags.any(_d.flag)) {
      return QuestStatus.locked;
    }
    return QuestStatus.available;
  }

  /// Kill progress for drone jobs (0 for others).
  static int kills(String id) {
    final q = def(id);
    if (q == null) return 0;
    var n = 0;
    for (var i = 1; i <= q.killTarget; i++) {
      if (_d.flag(_killFlag(id, i))) n++;
    }
    return n;
  }

  static bool get anyActive =>
      catalog.any((q) => status(q.id) == QuestStatus.accepted || status(q.id) == QuestStatus.done);

  static int get turnedInCount =>
      catalog.where((q) => status(q.id) == QuestStatus.turnedIn).length;

  static List<QuestDef> get activeJobs => [
        for (final q in catalog)
          if (status(q.id) == QuestStatus.accepted || status(q.id) == QuestStatus.done) q,
      ];

  static String? get objectiveHint {
    for (final q in catalog) {
      final s = status(q.id);
      if (s == QuestStatus.accepted) {
        final t = q.killTarget;
        final progress = t > 0 ? ' (${kills(q.id)}/$t)' : '';
        return 'Job: ${q.title}$progress — ${q.hint}';
      }
      if (s == QuestStatus.done) return 'Job ready: turn in "${q.title}" at the Town board';
    }
    return null;
  }

  static bool accept(String id) {
    if (status(id) != QuestStatus.available) return false;
    _d.setFlag(_accepted(id));
    _bump();
    return true;
  }

  static bool complete(String id) {
    if (!_d.flag(_accepted(id))) return false;
    if (_d.flag(_done(id)) || _d.flag(_turnedIn(id))) return false;
    _d.setFlag(_done(id));
    _bump();
    return true;
  }

  static bool turnIn(String id) {
    final q = def(id);
    if (q == null) return false;
    if (status(id) != QuestStatus.done) return false;
    if (q.requiresItem != null) {
      if (!Bonds.hasItem(q.requiresItem!)) return false;
      Bonds.useItem(q.requiresItem!);
    }
    _d.setFlag(_turnedIn(id));
    Adventure.discover(q.clueId);
    if (q.glimmer > 0) Bonds.addGlimmer(q.glimmer);
    if (q.gearId != null) Progression.grantGear(q.gearId!);
    _bump(now: true);
    return true;
  }

  /// Nest-tagged drones call this with their quest id.
  static void onNestDroneKilled(String questId) {
    final q = def(questId);
    if (q == null || q.nestKills <= 0) return;
    _countKill(q);
  }

  /// Every drone kill: advances accepted "clear N drones in <region>" jobs.
  static void onDroneKilled(String regionId) {
    for (final q in catalog) {
      if (q.regionKills > 0 && q.region == regionId) _countKill(q);
    }
  }

  /// An examine hotspot was used: completes accepted jobs that point at it.
  static void onExamined(String examineId) {
    for (final q in catalog) {
      if (q.examineId == examineId && status(q.id) == QuestStatus.accepted) complete(q.id);
    }
  }

  static void _countKill(QuestDef q) {
    final questId = q.id;
    if (!_d.flag(_accepted(questId))) return;
    if (_d.flag(_done(questId))) return;
    for (var i = 1; i <= q.killTarget; i++) {
      if (!_d.flag(_killFlag(questId, i))) {
        _d.setFlag(_killFlag(questId, i));
        if (i >= q.killTarget) {
          complete(questId);
        } else {
          _bump();
        }
        return;
      }
    }
  }
}
