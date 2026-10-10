import 'package:flutter/foundation.dart';

import '../creatures/bonds.dart';
import '../creatures/day_cycle.dart';
import '../game/save_service.dart';
import 'room_text.dart';

/// In-game day counter (#31): Ferro's daily rumour and Dao's daily errand.
/// Counts each time the day clock wraps past midnight, including resting
/// through the night. Stored in the save as `extra.day`.
class RoomDay {
  RoomDay._();
  static const _key = 'day';
  static double? _last;
  static bool _listening = false;

  static int get today => (SaveService.data.extra[_key] as num?)?.toInt() ?? 0;

  /// Start counting (idempotent; buildings call it when a map loads).
  static void ensure() {
    if (_listening) return;
    _listening = true;
    _last = DayCycle.time.value;
    DayCycle.time.addListener(_onTime);
  }

  static void _onTime() => observe(DayCycle.time.value);

  /// A late-evening -> morning jump is a new day (wrap or rest at night).
  @visibleForTesting
  static void observe(double t) {
    final last = _last;
    _last = t;
    if (last != null && last >= 0.75 && t <= 0.4) {
      SaveService.data.extra[_key] = today + 1;
    }
  }

  /// Skip to the next day (sleeping through daytime at the inn).
  static void bump() => SaveService.data.extra[_key] = today + 1;

  @visibleForTesting
  static void resetForTest() => _last = null;
}

/// Dao's bowls (#31): each costs glimmer and gives a short buff, one at a
/// time. Counted in unpaused play time; remaining time is saved
/// (`extra.meal` = {id, left}).
class Meal {
  final String id, name, effect;
  final int price;
  final double seconds;
  const Meal(this.id, this.name, this.effect, this.price, this.seconds);
}

class Meals {
  Meals._();
  static const _key = 'meal';

  /// Effect text is GameConcept's menu line.
  static const menu = [
    Meal('ember_broth', 'Ember broth', 'regenerate faster for a short while.', 6, 120),
    Meal('moss_noodles', 'Moss noodles', 'run a little faster for a short while.', 6, 120),
    Meal('night_bowl', 'Night bowl', 'see creatures from further away at night.', 8, 180),
  ];

  static const regenBoost = 2.0; // ember broth: x2 regen, no wait after a hit
  static const speedBoost = 1.15; // moss noodles
  static const nightSightBoost = 1.6; // night bowl, creature spotting radius

  static final active = ValueNotifier<String?>(null);
  static final remaining = ValueNotifier<double>(0);

  static Meal? byId(String? id) {
    for (final m in menu) {
      if (m.id == id) return m;
    }
    return null;
  }

  static SaveData? _loadedFrom;

  /// Adopt the save's meal once per loaded save (new game / CONTINUE).
  static void _sync() {
    if (identical(_loadedFrom, SaveService.data)) return;
    _loadedFrom = SaveService.data;
    load();
  }

  static bool isActive(String id) {
    _sync();
    return active.value == id && remaining.value > 0;
  }
  static double get regenMultiplier => isActive('ember_broth') ? regenBoost : 1;
  static bool get skipRegenDelay => isActive('ember_broth');
  static double get speedMultiplier => isActive('moss_noodles') ? speedBoost : 1;
  static double get nightSightMultiplier =>
      isActive('night_bowl') && DayCycle.night ? nightSightBoost : 1;

  /// Free bowl earned from yesterday's errand, usable today.
  static bool get freeBowlToday => DaoErrand.freeBowlDay == RoomDay.today;

  /// Order a bowl. Returns null on success, otherwise why not.
  static String? order(String id) {
    final m = byId(id);
    if (m == null) return 'Not on the menu.';
    final free = freeBowlToday;
    if (!free && !Bonds.spendGlimmer(m.price)) return 'Needs ${m.price} glimmer.';
    if (free) DaoErrand.useFreeBowl();
    _loadedFrom = SaveService.data;
    active.value = m.id;
    remaining.value = m.seconds;
    _persist();
    SaveService.requestAutosave();
    return null;
  }

  static void load() {
    final v = SaveService.data.extra[_key];
    if (v is Map && byId(v['id'] as String?) != null && v['left'] is num) {
      active.value = v['id'] as String;
      remaining.value = (v['left'] as num).toDouble();
    } else {
      active.value = null;
      remaining.value = 0;
    }
  }

  static void tick(double dt) {
    _sync();
    final before = remaining.value;
    if (before <= 0) return;
    final next = before - dt;
    if (next <= 0) {
      remaining.value = 0;
      active.value = null;
      _persist();
      return;
    }
    remaining.value = next;
    if (next.ceil() != before.ceil()) _persist();
  }

  static void _persist() {
    final id = active.value;
    if (id == null || remaining.value <= 0) {
      SaveService.data.extra.remove(_key);
    } else {
      SaveService.data.extra[_key] = {'id': id, 'left': double.parse(remaining.value.toStringAsFixed(1))};
    }
  }
}

/// Dao's daily errand: "Bring me one from the Woods and tomorrow's bowl is
/// free." While asked, the Woods moonflowers can be picked (item
/// `dao_moonflower`, separate from Mira's quest bloom).
class DaoErrand {
  DaoErrand._();
  static const _key = 'daoErrand';
  static const item = 'dao_moonflower';

  static Map<String, dynamic> get _m {
    final v = SaveService.data.extra[_key];
    if (v is Map<String, dynamic>) return v;
    final m = <String, dynamic>{};
    SaveService.data.extra[_key] = m;
    return m;
  }

  static int? _int(String k) => (_m[k] as num?)?.toInt();

  /// Asked and not yet delivered.
  static bool get active => _m['asked'] == true;
  static bool get deliveredToday => _int('doneDay') == RoomDay.today;
  static bool get canAsk => !active && !deliveredToday;
  static bool get carrying => Bonds.hasItem(item);
  static int? get freeBowlDay => _int('freeDay');

  static void accept() {
    if (!canAsk) return;
    _m['asked'] = true;
    SaveService.requestAutosave();
  }

  /// Moonflowers in the Woods are pickable for Dao right now.
  static bool get wantsFlower => active && !carrying;

  static void pick() {
    if (!wantsFlower) return;
    Bonds.giveItem(item);
  }

  /// Hand the flower over. Returns true when delivered.
  static bool deliver() {
    if (!active || !carrying) return false;
    Bonds.useItem(item);
    // Can be picked again for tomorrow's errand.
    SaveService.data.setFlag('used:$item', false);
    _m
      ..['asked'] = false
      ..['doneDay'] = RoomDay.today
      ..['freeDay'] = RoomDay.today + 1;
    SaveService.requestAutosave();
    return true;
  }

  static void useFreeBowl() => _m.remove('freeDay');
}

/// Asha's chest (#31 + #32): a glimmer stash between trips. Minimal hook:
/// #32 has no item stash yet, so this banks glimmer only
/// (`extra.stashGlimmer`).
class Stash {
  Stash._();
  static const _key = 'stashGlimmer';

  static int get stored => (SaveService.data.extra[_key] as num?)?.toInt() ?? 0;

  static void _set(int v) {
    if (v <= 0) {
      SaveService.data.extra.remove(_key);
    } else {
      SaveService.data.extra[_key] = v;
    }
    Bonds.revision.value++;
    SaveService.requestAutosave();
  }

  static int depositAll() {
    final n = Bonds.glimmer;
    if (n <= 0 || !Bonds.spendGlimmer(n)) return 0;
    _set(stored + n);
    return n;
  }

  static int withdrawAll() {
    final n = stored;
    if (n <= 0) return 0;
    _set(0);
    Bonds.addGlimmer(n);
    return n;
  }
}

/// Old Ferro's riddles (#31): one a day. A right answer gets the next
/// rumour in rotation (none repeats until all are heard) + 5 glimmer and
/// moves on to the next riddle; a wrong answer brings the same riddle back
/// the next in-game day. Saved as `extra.ferro`.
class Ferro {
  Ferro._();
  static const _key = 'ferro';

  static Map<String, dynamic> get _m {
    final v = SaveService.data.extra[_key];
    if (v is Map<String, dynamic>) return v;
    final m = <String, dynamic>{};
    SaveService.data.extra[_key] = m;
    return m;
  }

  static int _int(String k, [int d = 0]) => (_m[k] as num?)?.toInt() ?? d;

  /// Riddles solved so far (index of today's riddle, mod the list).
  static int get solved => _int('riddle');

  /// Rumours told so far (next rumour, mod the list).
  static int get rumoursTold => _int('rumour');

  static bool get answeredToday => _m.containsKey('day') && _int('day') == RoomDay.today;
  static bool get rightToday => answeredToday && _m['right'] == true;

  static FerroRiddle get riddle => RoomText.ferroRiddles[solved % RoomText.ferroRiddles.length];

  /// Today's rumour after a right answer.
  static String? get rumourToday {
    if (!rightToday) return null;
    return RoomText.ferroRumours[_int('told') % RoomText.ferroRumours.length];
  }

  /// The three answers, shuffled per day so the right one moves around.
  static List<String> get choices {
    final r = riddle;
    final all = [r.answer, ...r.wrong];
    final shift = (RoomDay.today + solved * 2) % all.length;
    return [...all.skip(shift), ...all.take(shift)];
  }

  /// Answer today's riddle. Returns the rumour on a right answer, null on a
  /// wrong one (or if already answered today).
  static String? answer(String choice) {
    if (answeredToday) return null;
    final right = choice == riddle.answer;
    _m['day'] = RoomDay.today;
    _m['right'] = right;
    if (!right) {
      SaveService.requestAutosave();
      return null;
    }
    final told = rumoursTold;
    _m['told'] = told;
    _m['rumour'] = told + 1;
    _m['riddle'] = solved + 1;
    Bonds.addGlimmer(RoomText.ferroRewardGlimmer);
    return RoomText.ferroRumours[told % RoomText.ferroRumours.length];
  }
}
