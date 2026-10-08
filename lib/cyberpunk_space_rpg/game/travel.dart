import 'game_state.dart';

/// A warp destination shown in the portal travel menu.
class TravelDest {
  final int level;
  final String title;
  final String blurb;
  final String regionId;

  const TravelDest({
    required this.level,
    required this.title,
    required this.blurb,
    required this.regionId,
  });
}

/// Shared travel network: portals offer a clear forward path plus quieter returns.
class Travel {
  Travel._();

  static const List<TravelDest> all = [
    TravelDest(
      level: 1,
      title: 'Whispering Woods',
      blurb: 'Gaia\'s glade. Home of the first UEC breach.',
      regionId: 'woods',
    ),
    TravelDest(
      level: 2,
      title: 'The City',
      blurb: 'Neon streets, the tea house, and the UEC checkpoint.',
      regionId: 'city',
    ),
    TravelDest(
      level: 5,
      title: 'Lantern Town',
      blurb: 'Quiet market alleys. Mira trades glimmer for gear.',
      regionId: 'town',
    ),
    TravelDest(
      level: 3,
      title: 'The Ruins',
      blurb: 'Collapsed Aetherian districts on the road to the Core.',
      regionId: 'ruins',
    ),
    TravelDest(
      level: 4,
      title: 'Gaia\'s Core',
      blurb: 'Sacred chamber under the ruins. The Core Record waits.',
      regionId: 'core',
    ),
  ];

  static void markVisited(int level) {
    final region = GameState.regionIds[level];
    if (region == null || region.isEmpty) return;
    GameState.markRegionVisited(region);
  }

  /// Story-forward level from [fromLevel], if any (side hubs excluded).
  static int? storyNextLevel(int fromLevel) {
    switch (fromLevel) {
      case 1:
        return 2;
      case 2:
        return 3;
      case 3:
        return 4;
      case 5:
        return 2; // leave town → city
      default:
        return null;
    }
  }

  /// Destinations the player may travel to (excluding [fromLevel]).
  static List<TravelDest> availableFrom(int fromLevel) {
    final unlocked = GameState.portalUnlocked.value;
    return all.where((d) {
      if (d.level == fromLevel) return false;
      // Return travel to anywhere already visited.
      if (GameState.hasVisitedRegion(d.regionId)) return true;
      // First-time story / side unlocks.
      if (d.level == 1) return true; // woods is always a home return
      if (d.level == 2 && fromLevel == 1 && unlocked) return true;
      if (d.level == 5 && fromLevel == 2) return true; // city → town side gate
      if (d.level == 3 && fromLevel == 2 && unlocked) return true;
      if (d.level == 4 && fromLevel == 3) return true;
      return false;
    }).toList();
  }

  /// Forward destination (highlighted) plus quieter return list.
  /// Lantern Town is never the main "continue" from the city avenue portal —
  /// that side trip uses the dedicated town gate.
  static ({TravelDest? continueTo, List<TravelDest> returns}) menuFrom(int fromLevel) {
    final available = availableFrom(fromLevel);
    // City main portal: don't offer town here (use the Lantern Gate).
    final filtered = fromLevel == 2
        ? available.where((d) => d.level != 5).toList()
        : available;

    final nextId = storyNextLevel(fromLevel);
    TravelDest? cont;
    if (nextId != null) {
      for (final d in filtered) {
        if (d.level == nextId) {
          cont = d;
          break;
        }
      }
    }
    final returns = [
      for (final d in filtered)
        if (d.level != cont?.level) d,
    ];
    return (continueTo: cont, returns: returns);
  }

  /// Whether the portal on [level] should open (story unlock or return options).
  static bool portalUsable(int level) {
    if (GameState.portalUnlocked.value) return true;
    return availableFrom(level).isNotEmpty;
  }

  static TravelDest? byLevel(int level) {
    for (final d in all) {
      if (d.level == level) return d;
    }
    return null;
  }

  static String mapIdFor(int level) => GameState.mapIds[level]!;
}
