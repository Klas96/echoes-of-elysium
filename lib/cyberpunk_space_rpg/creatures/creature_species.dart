/// M2 creature roster for the Whispering Woods: who they are, where they
/// live, how to befriend them and what they can do as a companion.
///
/// Pure data (no Flutter/Flame), so the bond rules are unit tested.
library;

/// Companion abilities that act as keys for optional secrets.
enum Ability { light, scent, push }

extension AbilityInfo on Ability {
  String get label => switch (this) {
        Ability.light => 'LIGHT',
        Ability.scent => 'SCENT',
        Ability.push => 'PUSH',
      };

  String get description => switch (this) {
        Ability.light => 'Brightens dark places and wakes sleeping glyphs.',
        Ability.scent => 'Follows hidden trails and buried things.',
        Ability.push => 'Moves heavy boulders.',
      };

  /// Value stored in SaveData.abilities.
  String get saveKey => name;
}

/// How a creature is befriended (see [checkBond]).
enum BondRule {
  /// Approach at night without running or shooting nearby.
  nightQuiet,

  /// Offer [CreatureSpecies.item].
  offerItem,

  /// Free it from a UEC drone net (the interaction itself is the bond).
  freeFromNet,

  /// Stand still nearby until it comes out of hiding, then bond.
  stillWatch,

  /// Find it at night (it only appears in its hidden glade after dark).
  nightPresence,
}

class CreatureSpecies {
  final String id;
  final String name;
  final String habitat;

  /// Discovery hint, shown in the journal once the creature has been seen.
  final String hint;

  /// Gaia's lore line, shown once befriended.
  final String lore;
  final Ability? ability;
  final bool flying;

  /// Only out (visible, bondable) at night.
  final bool nightOnly;
  final BondRule rule;

  /// Item id for [BondRule.offerItem].
  final String? item;
  final String? itemName;

  /// Wander speed in px/s.
  final double speed;

  /// Home region id (GameState.regionIds): the creature only follows Kaela
  /// and its ability only works there (see Regions).
  final String region;

  const CreatureSpecies({
    required this.id,
    required this.name,
    required this.habitat,
    required this.hint,
    required this.lore,
    required this.rule,
    this.ability,
    this.flying = false,
    this.nightOnly = false,
    this.item,
    this.itemName,
    this.speed = 18,
    this.region = 'woods',
  });

  String get sheet => 'creatures/${id}_sheet.png';
  String get shadow => 'creatures/${id}_shadow.png';
  String portraitAsset(String variant) =>
      'assets/images/creatures/${id}_portrait${variant.isEmpty ? '' : '_$variant'}.png';
}

const creatureOrder = ['glowmoth', 'vinefox', 'stoneturtle', 'puffcap', 'brookling', 'hushdeer'];

const creatureSpecies = <String, CreatureSpecies>{
  'glowmoth': CreatureSpecies(
    id: 'glowmoth',
    name: 'Glowmoth',
    habitat: 'Whispering Woods, at night',
    hint: 'It drifts only where no footsteps hurry.',
    lore: 'The glowmoths carry the last light of each day into the dark. The Aetherians called them lanterns of memory.',
    rule: BondRule.nightQuiet,
    ability: Ability.light,
    flying: true,
    nightOnly: true,
    speed: 14,
  ),
  'vinefox': CreatureSpecies(
    id: 'vinefox',
    name: 'Vine Fox',
    habitat: 'Whispering Woods, old stumps',
    hint: 'Something sweet grows where the old trees fell.',
    lore: 'Vine foxes can smell a path long after it\'s overgrown. They have never once been lost.',
    rule: BondRule.offerItem,
    item: 'sweetroot',
    itemName: 'sweetroot',
    ability: Ability.scent,
    speed: 24,
  ),
  'stoneturtle': CreatureSpecies(
    id: 'stoneturtle',
    name: 'Stone Turtle',
    habitat: 'Riverbank',
    hint: 'Caught in something cold and humming. It cannot move.',
    lore: 'Stone turtles have walked this river for three hundred years. They remember when it ran the other way.',
    rule: BondRule.freeFromNet,
    ability: Ability.push,
    speed: 8,
  ),
  'puffcap': CreatureSpecies(
    id: 'puffcap',
    name: 'Puffcap',
    habitat: 'Mossy hollows',
    hint: 'It\'s shy of footsteps.',
    lore: 'Puffcaps grow from the same roots as the forest. When one sleeps, so does a little patch of woods.',
    rule: BondRule.stillWatch,
    speed: 0,
  ),
  'brookling': CreatureSpecies(
    id: 'brookling',
    name: 'Brookling',
    habitat: 'River shallows',
    hint: 'It collects pretty stones.',
    lore: 'Brooklings line their dens with the shiniest pebbles they find. Some dens are older than the colony.',
    rule: BondRule.offerItem,
    item: 'pebble',
    itemName: 'river pebble',
    speed: 20,
  ),
  'hushdeer': CreatureSpecies(
    id: 'hushdeer',
    name: 'Hushdeer',
    habitat: 'Hidden glade, at night',
    hint: 'Follow the scent of moonflowers.',
    lore: 'Few have seen a hushdeer. The Aetherians believed they guard the places Gaia dreams.',
    rule: BondRule.nightPresence,
    nightOnly: true,
    speed: 12,
  ),
};

/// Everything a bond check needs to know about the moment.
class BondContext {
  final bool isNight;

  /// No running and no shots nearby (see QuietTracker).
  final bool quiet;
  final Set<String> items;

  /// Still caught in the drone net (stone turtle).
  final bool netted;

  /// Out of hiding (puffcap, see StillWatch).
  final bool emerged;

  const BondContext({
    this.isNight = false,
    this.quiet = true,
    this.items = const {},
    this.netted = false,
    this.emerged = false,
  });
}

/// Result of a bond check: [ok] with the action [label], or a gentle [note]
/// about why not (worded as a clue, never as a failure).
class BondCheck {
  final bool ok;
  final String label;
  final String note;
  const BondCheck.yes(this.label) : ok = true, note = '';
  const BondCheck.no(this.note) : ok = false, label = '';

  @override
  String toString() => ok ? 'yes($label)' : 'no($note)';
}

BondCheck checkBond(CreatureSpecies s, BondContext c) {
  switch (s.rule) {
    case BondRule.nightQuiet:
      if (!c.isNight) return const BondCheck.no('It is resting somewhere out of sight.');
      if (!c.quiet) return const BondCheck.no('It flutters off. Come closer softly: no running, no shots.');
      return const BondCheck.yes('BEFRIEND');
    case BondRule.offerItem:
      if (c.items.contains(s.item)) return BondCheck.yes('OFFER ${s.itemName!.toUpperCase()}');
      return BondCheck.no(s.id == 'vinefox'
          ? 'It sniffs your hands, hoping for something sweet.'
          : 'It looks at your empty hands, then at the shallows.');
    case BondRule.freeFromNet:
      if (c.netted) return const BondCheck.yes('FREE IT');
      return const BondCheck.yes('BEFRIEND');
    case BondRule.stillWatch:
      if (!c.emerged) return const BondCheck.no('Only a cap peeks out of the moss. Stay still a while.');
      if (!c.quiet) return const BondCheck.no('It ducks back into its cap.');
      return const BondCheck.yes('BEFRIEND');
    case BondRule.nightPresence:
      if (!c.isNight) return const BondCheck.no('Hoofprints in the moss, nothing more. Perhaps after dark.');
      if (!c.quiet) return const BondCheck.no('It lifts its head, ready to bolt. Gently now.');
      return const BondCheck.yes('BEFRIEND');
  }
}

/// "Quiet approach": shots within [hearing] px or walking right up to the
/// creature for too long startle it for a few seconds (it just hops away;
/// nothing bad happens).
class QuietTracker {
  static const hearing = 160.0;
  static const shotNoise = 1.0;
  static const movingNoisePerSecond = 0.7;
  static const decayPerSecond = 0.4;
  static const startleSeconds = 4.0;

  double noise = 0;
  double startledFor = 0;

  /// Returns true when this shot startled it.
  bool onShot(double distance) {
    if (distance > hearing) return false;
    noise += shotNoise;
    return _check();
  }

  /// [movingClose]: the player is moving right next to it. Returns true when
  /// it got startled this tick.
  bool tick(double dt, {required bool movingClose}) {
    if (startledFor > 0) startledFor = (startledFor - dt).clamp(0, startleSeconds);
    if (movingClose) {
      noise += movingNoisePerSecond * dt;
    } else {
      noise = (noise - decayPerSecond * dt).clamp(0, 10);
    }
    return _check();
  }

  bool _check() {
    if (noise >= 1) {
      noise = 0.3;
      startledFor = startleSeconds;
      return true;
    }
    return false;
  }

  bool get quiet => startledFor <= 0 && noise < 0.6;
}

/// Puffcap: comes out after the player stands still within range for
/// [emergeSeconds]; ducks back in when the player walks around nearby or
/// leaves for a while.
class StillWatch {
  static const emergeSeconds = 5.0;
  static const hideAfterMoving = 1.2;
  static const hideAfterAway = 3.0;

  double still = 0;
  double _moving = 0;
  double _away = 0;
  bool out = false;

  /// 0..1 towards coming out (for a peeking frame).
  double get progress => out ? 1 : (still / emergeSeconds).clamp(0, 1);

  void tick(double dt, {required bool near, required bool moving}) {
    if (near && !moving) {
      still += dt;
      _moving = 0;
      _away = 0;
      if (still >= emergeSeconds) out = true;
    } else if (near) {
      still = 0;
      _away = 0;
      if (out) {
        _moving += dt;
        if (_moving >= hideAfterMoving) out = false;
      }
    } else {
      still = 0;
      _moving = 0;
      if (out) {
        _away += dt;
        if (_away >= hideAfterAway) out = false;
      }
    }
  }
}
