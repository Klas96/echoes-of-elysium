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
  });

  /// Board badge while accepted, e.g. `IN CITY`.
  String get acceptedBoardLabel => 'IN ${region.toUpperCase()}';

  /// Journal line while accepted, e.g. `in city`.
  String get acceptedJournalLabel => 'in $region';
}

/// Lantern Town job board — woods and city loops.
class Quests {
  Quests._();

  static final revision = ValueNotifier<int>(0);

  static const catalog = <QuestDef>[
    // --- Woods (Phase A) ---
    QuestDef(
      id: 'courier_pack',
      title: 'Lost Courier Pack',
      blurb:
          'A runner dropped a sealed pack on the west trail past the ranger cabin. Bring word that it was found.',
      hint: 'Woods · west loop from the Crossroads.',
      region: 'woods',
      glimmer: 25,
      clueId: 'quest_courier',
    ),
    QuestDef(
      id: 'drone_nest',
      title: 'Quiet the Nest',
      blurb:
          'UEC left a quiet nest mid-woods. Clear the drones and read their field slate.',
      hint: 'Woods · west loop nest spur past the Crossroads.',
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
      hint: 'Woods · west loop hollow before Asha.',
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
          'UEC parked a nest on the east lot off the avenue. Quiet it before they reinforce.',
      hint: 'City · east lot off the main avenue.',
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
          'A patrol slate went dark in the south-east alley. Find it — and whatever is watching it.',
      hint: 'City · SE alley south of the east lot.',
      region: 'city',
      glimmer: 20,
      clueId: 'quest_city_se',
      nestKills: 1,
    ),
    QuestDef(
      id: 'city_west_cache',
      title: 'West Alley Cache',
      blurb:
          'Traders stashed a cache above the west yard. Recover the marked crate.',
      hint: 'City · west mid-alley between noodle court and the yard.',
      region: 'city',
      glimmer: 22,
      gearId: 'swarm_thrusters',
      clueId: 'quest_city_west',
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
    return QuestStatus.available;
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
      if (s == QuestStatus.accepted) return 'Job: ${q.title} — ${q.hint}';
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
    if (!_d.flag(_accepted(questId))) return;
    if (_d.flag(_done(questId))) return;
    for (var i = 1; i <= q.nestKills; i++) {
      if (!_d.flag(_killFlag(questId, i))) {
        _d.setFlag(_killFlag(questId, i));
        if (i >= q.nestKills) {
          complete(questId);
        } else {
          _bump();
        }
        return;
      }
    }
  }
}
