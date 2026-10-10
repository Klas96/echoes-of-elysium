/// Companions stay in their home region (brief-woods-befriend-gates, part 2):
/// each creature only follows Kaela inside its home region, and its ability
/// only works there. The journal still lists every friend everywhere.
///
/// Pure Dart (no Flutter/Flame) so the rule is unit tested.
library;

import 'creature_species.dart';

class Regions {
  Regions._();

  /// Region of the map on screen (GameState.regionIds), set when a map
  /// starts. Interiors keep the region of the map they open from.
  static String current = 'woods';

  /// Region of the map Kaela just left ('' at startup / on CONTINUE).
  static String previous = '';

  static String homeOf(String speciesId) => creatureSpecies[speciesId]?.region ?? 'woods';

  /// [speciesId] walks with Kaela in [region].
  static bool followsIn(String speciesId, String region) => homeOf(speciesId) == region;

  /// Some creature whose home is [region] has [ability] at all.
  static bool abilityHomeIn(Ability ability, String region) =>
      creatureSpecies.values.any((s) => s.ability == ability && s.region == region);

  /// [speciesId]'s ability can be used in [region] (only at home).
  static bool abilityWorksIn(String speciesId, String region) =>
      creatureSpecies[speciesId]?.ability != null && homeOf(speciesId) == region;

  /// Pretty name for toasts/journal.
  static String nameOf(String region) => switch (region) {
        'woods' => 'the Woods',
        'city' => 'the City',
        'ruins' => 'the Ruins',
        'town' => 'Lantern Town',
        'core' => 'the Core',
        _ => region,
      };
}
