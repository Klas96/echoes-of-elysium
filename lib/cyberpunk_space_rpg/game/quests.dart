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
  final String woodsHint;
  final int glimmer;
  final String? gearId;
  final String clueId;
  /// If set, turn-in requires this Bonds item (consumed).
  final String? requiresItem;

  const QuestDef({
    required this.id,
    required this.title,
    required this.blurb,
    required this.woodsHint,
    required this.glimmer,
    required this.clueId,
    this.gearId,
    this.requiresItem,
  });
}

/// Lantern Town job board — optional woods loops.
class Quests {
  Quests._();

  static final revision = ValueNotifier<int>(0);

  static const catalog = <QuestDef>[
    QuestDef(
      id: 'courier_pack',
      title: 'Lost Courier Pack',
      blurb:
          'A runner dropped a sealed pack on the west trail past the ranger cabin. Bring word that it was found.',
      woodsHint: 'West clearing near the cabin trail (f1).',
      glimmer: 25,
      clueId: 'quest_courier',
    ),
    QuestDef(
      id: 'drone_nest',
      title: 'Quiet the Nest',
      blurb:
          'UEC left a quiet nest mid-woods. Clear the drones and read their field slate.',
      woodsHint: 'Mid-trail clearing south of the second health shrine (d3).',
      glimmer: 10,
      gearId: 'scrap_plating',
      clueId: 'quest_nest',
    ),
    QuestDef(
      id: 'moonflower_draft',
      title: 'Moonflower for the Sick',
      blurb:
          'Mira needs a moonflower bloom from the SCENT trail. Pick one and bring it home.',
      woodsHint: 'Moonflower glade / f3 hollow on the vine-fox trail.',
      glimmer: 15,
      gearId: 'lantern_charm',
      clueId: 'quest_moonflower',
      requiresItem: 'moonflower_bloom',
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
      if (s == QuestStatus.accepted) return 'Job: ${q.title} — ${q.woodsHint}';
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

  /// Mark field work finished (examine / nest clear / bloom picked).
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

  /// Nest drones report kills; completes [drone_nest] after 2.
  static void onNestDroneKilled() {
    if (!_d.flag(_accepted('drone_nest'))) return;
    if (_d.flag(_done('drone_nest'))) return;
    if (!_d.flag('quest:drone_nest:kills')) {
      _d.setFlag('quest:drone_nest:kills');
      _bump();
      return;
    }
    if (!_d.flag('quest:drone_nest:kills2')) {
      _d.setFlag('quest:drone_nest:kills2');
      complete('drone_nest');
    }
  }
}
