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
  /// Who hands the job out and takes the turn-in (`mira`, `asha`, …).
  final String giver;
  /// Display name for board / objective copy.
  final String giverLabel;
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
    required this.giver,
    required this.giverLabel,
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

  /// Board / HUD when fieldwork is finished.
  String get returnToLabel => 'Return to $giverLabel';
}

/// Character-driven jobs — fewer posts, each owned by an NPC (#32).
class Quests {
  Quests._();

  static final revision = ValueNotifier<int>(0);

  static const catalog = <QuestDef>[
    // --- Woods ---
    QuestDef(
      id: 'drone_nest',
      title: 'Quiet the Nest',
      blurb:
          'Asha wants the west-loop nest quiet. Clear the pads and read their field slate.',
      hint: 'Woods · nest spur off the south-west bend of the west loop.',
      region: 'woods',
      glimmer: 10,
      gearId: 'scrap_plating',
      clueId: 'quest_nest',
      giver: 'asha',
      giverLabel: 'Asha',
      nestKills: 2,
    ),
    QuestDef(
      id: 'moonflower_draft',
      title: 'Moonflower for the Sick',
      blurb:
          'Dao needs a moonflower bloom from the SCENT trail for the sick — and for honest lamps.',
      hint: 'Woods · south-west trail, just west of Asha\'s camp.',
      region: 'woods',
      glimmer: 15,
      gearId: 'lantern_charm',
      clueId: 'quest_moonflower',
      giver: 'dao',
      giverLabel: 'Dao',
      requiresItem: 'moonflower_bloom',
    ),
    // --- City ---
    QuestDef(
      id: 'city_east_nest',
      title: 'East Lot Nest',
      blurb:
          'Mira wants the east lot quiet before UEC reinforces the Lantern Gate road.',
      hint: 'City · east lot, south of the Lantern Gate.',
      region: 'city',
      glimmer: 18,
      gearId: 'pulse_optic',
      clueId: 'quest_city_east',
      giver: 'mira',
      giverLabel: 'Mira',
      nestKills: 2,
    ),
    QuestDef(
      id: 'city_west_cache',
      title: 'West Alley Cache',
      blurb:
          'Echo-7 marked a trader cache in the west lane. Recover it before scavengers do.',
      hint: 'City · west lane between Market Row and Echo district.',
      region: 'city',
      glimmer: 22,
      gearId: 'swarm_thrusters',
      clueId: 'quest_city_west',
      giver: 'echo7',
      giverLabel: 'Echo-7',
    ),
    // --- Ruins ---
    QuestDef(
      id: 'ruins_shrine_waymarker',
      title: 'Shrine Waymarker',
      blurb:
          'The Archivist wants a reading from the SW waymarker — an anomaly past the clearing.',
      hint: 'Ruins · SW waymarker past the clearing.',
      region: 'ruins',
      glimmer: 20,
      clueId: 'quest_ruins_shrine',
      giver: 'archivist',
      giverLabel: 'Archivist',
      examineId: 'ruins_dead_end',
      unlockFlags: ['sentinelDefeated', 'visited:ruins'],
      lockedHint: 'Opens once the road to the Ruins is clear.',
    ),
    // --- Core ---
    QuestDef(
      id: 'core_console_reading',
      title: 'Console Reading',
      blurb:
          'The Archivist wants the wipe queue in writing. Read the Core console and bring word back.',
      hint: 'Core · the console by the dais.',
      region: 'core',
      glimmer: 30,
      clueId: 'quest_core_console',
      giver: 'archivist',
      giverLabel: 'Archivist',
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

  static List<QuestDef> jobsForGiver(String giver) => [
        for (final q in catalog)
          if (q.giver == giver) q,
      ];

  /// ACCEPT / TURN IN choices for an NPC talk (or Dao panel).
  static List<DialogueChoice> dialogueChoicesFor(String giver) {
    final out = <DialogueChoice>[];
    for (final q in jobsForGiver(giver)) {
      final s = status(q.id);
      if (s == QuestStatus.available) {
        out.add(DialogueChoice(
          label: 'ACCEPT · ${q.title.toUpperCase()}',
          acceptQuest: q.id,
          replyLines: [
            'Good. ${q.hint}',
            'When it\'s done, come back to me — not the board.',
          ],
        ));
      } else if (s == QuestStatus.done) {
        final blocked =
            q.requiresItem != null && !Bonds.hasItem(q.requiresItem!);
        if (blocked) {
          out.add(DialogueChoice(
            label: 'ABOUT · ${q.title.toUpperCase()}',
            replyLines: const [
              'Bring the moonflower bloom and I\'ll settle up.',
            ],
          ));
        } else {
          out.add(DialogueChoice(
            label: 'TURN IN · ${q.title.toUpperCase()}',
            turnInQuest: q.id,
            replyLines: [
              'That\'s what I needed. ${q.glimmer} glimmer — thank you.',
            ],
          ));
        }
      }
    }
    return out;
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
      if (s == QuestStatus.done) {
        return 'Job ready: ${q.returnToLabel} — "${q.title}"';
      }
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
      if (q.examineId == examineId && status(q.id) == QuestStatus.accepted) {
        complete(q.id);
      }
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
