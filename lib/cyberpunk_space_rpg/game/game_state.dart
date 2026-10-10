import 'package:flutter/material.dart';

import '../creatures/bonds.dart';
import '../creatures/gates.dart';
import '../creatures/interaction.dart';
import '../creatures/region_gates.dart';
import 'adventure.dart';
import 'memories.dart';
import 'quests.dart';
import 'save_service.dart';

/// Level state and the HUD objective line.
///
/// Objectives are a gentle guide, never a hard gate — except the City south
/// portal, which opens after the Archivist's post-Sentinel talk so the quiet
/// beat has room to land.
class GameState {
  static final objective = ValueNotifier<String>('');
  static final fragmentsCollected = ValueNotifier<int>(0);
  /// Memory fragments 1-2 are in the woods; both (plus the fallen boulder
  /// pushed aside) open the road south (the other three memories are
  /// optional, see Memories).
  static const fragmentsRequired = 2;

  /// The Woods exit rule (brief-woods-befriend-gates): 2 fragments AND the
  /// fallen boulder pushed aside. The fragments sit behind LIGHT and SCENT
  /// gates, so all three Woods friends are needed.
  static const woodsBoulder = 'woods_boulder';
  static bool get woodsExitEarned =>
      fragmentsCollected.value >= fragmentsRequired && Gates.isOpen(woodsBoulder);

  static bool _wired = false;
  static void _wire() {
    if (_wired) return;
    _wired = true;
    Bonds.revision.addListener(_refresh);
    Gates.onChanged = _refresh;
    Gates.onOpened = (id) {
      if (_level == 1 && id == woodsBoulder) _checkWoodsExit();
    };
  }

  static void _checkWoodsExit() {
    if (_level != 1 || portalUnlocked.value || !woodsExitEarned) {
      _refresh();
      return;
    }
    portalUnlocked.value = true;
    _advance(1, _l1Portal);
    GameToast.show('ROAD SOUTH', body: woodsGoal.exitOpens, color: const Color(0xFF66FFAA), seconds: 4);
    _refresh();
    _progress();
  }
  static final portalUnlocked = ValueNotifier<bool>(false);

  /// Shown when the game is finished.
  static const endingText = 'The Aetherians live on.';

  // 1 woods, 2 city, 3 ruins, 4 core, 5 lantern town (0 before any map is ready).
  static int _level = 0;
  static int _step = 0;

  // Level 1 steps
  static const _l1Gaia = 0, _l1Asha = 1, _l1Fragments = 2, _l1Portal = 3;
  // Level 2 steps
  static const _l2Echo = 0,
      _l2Archivist = 1,
      _l2Voss = 2,
      _l2Sentinel = 3,
      _l2Quiet = 4,
      _l2Core = 5;
  // Level 3 steps
  static const _l3Ruins = 0, _l3Shrine = 1, _l3Light = 2;
  // Level 4 steps
  static const _l4Enter = 0, _l4Gaia = 1, _l4Activate = 2;
  // Level 5 steps (peaceful hub)
  static const _l5Town = 0;

  /// Tiled map stem and region id for each level, as stored in the save.
  static const mapIds = {
    1: 'world',
    2: 'world2',
    3: 'world3',
    4: 'world4',
    5: 'world5',
  };
  static const regionIds = {
    1: 'woods',
    2: 'city',
    3: 'ruins',
    4: 'core',
    5: 'town',
  };

  static bool hasVisitedRegion(String regionId) =>
      SaveService.data.flag('visited:$regionId');

  static void markRegionVisited(String regionId) {
    if (regionId.isEmpty || hasVisitedRegion(regionId)) return;
    SaveService.data.setFlag('visited:$regionId');
    _progress();
  }

  static int get level => _level;
  static int get step => _step;

  static int levelForMap(String mapId) =>
      mapIds.entries.firstWhere((e) => e.value == mapId, orElse: () => mapIds.entries.first).key;

  /// Copies the objective state into the save record.
  static void writeTo(SaveData d) {
    if (_level == 0) return;
    d.mapId = mapIds[_level]!;
    d.regionId = regionIds[_level]!;
    d.objectiveStep = _step;
    d.fragments = fragmentsCollected.value;
    d.setFlag('portalUnlocked:${mapIds[_level]}', portalUnlocked.value);
    Gates.writeTo(d);
  }

  /// CONTINUE: put a level back the way the save left it.
  static void restore(int level, SaveData d) {
    _wire();
    _level = level;
    _step = d.objectiveStep;
    switch (level) {
      case 1:
        fragmentsCollected.value = d.fragments.clamp(0, fragmentsRequired);
        portalUnlocked.value = d.flag('portalUnlocked:world') ||
            (d.fragments >= fragmentsRequired && Gates.isOpen(woodsBoulder));
      case 2:
        // Archivist after Sentinel. Old saves that already unlocked keep it.
        portalUnlocked.value = citySouthOpen ||
            (d.flag('sentinelDefeated') && d.flag('portalUnlocked:world2'));
      case 3:
        portalUnlocked.value = true;
      case 4:
        portalUnlocked.value = d.flag('portalUnlocked:world4');
      case 5:
        portalUnlocked.value = true;
      default:
        portalUnlocked.value = true;
    }
    _refresh();
  }

  static void _progress() => SaveService.requestAutosave();

  static void resetMap1() {
    _wire();
    _level = 1;
    // Walking back into the woods (from the City) must keep what the save
    // already earned: fragments taken, friends made, the road south open.
    // A fresh game has none of these, so it still starts at Gaia.
    final d = SaveService.data;
    final taken = d.collected.where((c) => c.startsWith('world:fragment:')).length;
    fragmentsCollected.value = taken.clamp(0, fragmentsRequired);
    portalUnlocked.value = d.flag('portalUnlocked:world') || woodsExitEarned;
    _step = portalUnlocked.value
        ? _l1Portal
        : taken > 0 || Gates.goalSet('woods')
            ? _l1Fragments
            : d.flag('talked:gaia')
                ? _l1Asha
                : _l1Gaia;
    _refresh();
  }

  static void resetMap2() {
    _level = 2;
    _step = _l2Echo;
    // Re-entering the city (town hop, CONTINUE off) must not erase the south
    // road after the Archivist's post-Sentinel talk.
    portalUnlocked.value = citySouthOpen;
    _refresh();
  }

  /// South gate to the Ruins — opened by the Archivist after the Sentinel.
  static bool get citySouthOpen {
    final d = SaveService.data;
    return d.flag('archivistPostSentinel') || d.flag('portalUnlocked:world2');
  }

  /// Idempotent: persist and open the city → ruins road.
  static void openCitySouth() {
    final d = SaveService.data;
    d.setFlag('archivistPostSentinel');
    d.setFlag('portalUnlocked:world2');
    portalUnlocked.value = true;
    _advance(2, _l2Core);
    _refresh();
    _progress();
  }

  static void resetMap3() {
    _level = 3;
    _step = _l3Ruins;
    portalUnlocked.value = true;
    _refresh();
  }

  static void resetMap4() {
    _level = 4;
    _step = _l4Enter;
    portalUnlocked.value = false;
    _refresh();
  }

  static void resetMap5() {
    _level = 5;
    _step = _l5Town;
    portalUnlocked.value = true;
    _refresh();
  }

  static void onFragmentCollected() {
    // Only the woods count fragments towards a portal; the optional City and
    // Ruins fragments are memories only (Memories).
    if (_level != 1) {
      _progress();
      return;
    }
    final n = fragmentsCollected.value + 1;
    fragmentsCollected.value = n;
    _advance(1, _l1Fragments);
    _checkWoodsExit();
    _progress();
  }

  /// Called when the player opens an NPC's dialogue. [npc] is the Tiled
  /// npc name key (gaia, asha, echo7, archivist, voss).
  static void onNpcTalk(String npc) {
    Memories.onNpcTalk(npc);
    if (!SaveService.data.flag('talked:$npc')) {
      SaveService.data.setFlag('talked:$npc');
      _progress();
    }
    switch (npc) {
      case 'gaia':
        if (_level == 4) {
          portalUnlocked.value = true;
          _advance(4, _l4Activate);
          _refresh();
          _progress();
        } else {
          _advance(1, _l1Asha);
        }
      case 'asha':
        if (_level == 1) Gates.setGoal('woods');
        _advance(1, _l1Fragments);
      case 'echo7':
        _advance(2, _l2Archivist);
      case 'archivist':
        _advance(2, _l2Voss);
        if (SaveService.data.flag('sentinelDefeated')) {
          openCitySouth();
        }
      case 'voss':
        _advance(2, _l2Sentinel);
      case 'mira':
        break;
    }
  }

  /// The Sentinel noticed the player (or was hit): skip straight to it.
  static void onSentinelEngaged() => _advance(2, _l2Sentinel);

  /// Sentinel down — portal stays locked until the Archivist's quiet talk.
  static void onSentinelDefeated() {
    SaveService.data.setFlag('sentinelDefeated');
    _advance(2, _l2Quiet);
    _refresh();
    _progress();
  }

  /// Ruin shrine examined (optional memory path).
  static void onShrineExamined() {
    if (_level == 3) _advance(3, _l3Shrine);
  }

  /// The player is close to the level's portal.
  static void onNearPortal() {
    // Ruins: portal sits just past the SE gate — don't spoil the objective
    // while the keystone lock still blocks the approach.
    if (_level == 3) {
      if (Adventure.flag('ruins_gate_open')) _advance(3, _l3Light);
      return;
    }
    if (_level == 4) _advance(4, _l4Gaia);
  }

  static void _advance(int level, int step) {
    if (_level != level || step <= _step) return;
    _step = step;
    _refresh();
    _progress();
  }

  static void _refresh() {
    objective.value = _text();
  }

  /// Quest board / adventure hooks can refresh the HUD line without advancing steps.
  static void refreshObjective() => _refresh();

  static String _text() {
    // Optional town jobs: soft hint when story is not mid-critical beat.
    final job = Quests.objectiveHint;
    switch (_level) {
      case 1:
        if (portalUnlocked.value || _step >= _l1Portal) {
          return job ??
              'Mission: take the south-east meadow road off the map to the City (Lantern Town lies east of its plaza)';
        }
        if (_step >= _l1Fragments || Gates.goalSet('woods')) {
          // Friends first: while a closed gate still waits for its creature.
          final waiting = gatesIn('woods').any((g) => !Gates.isOpen(g.id) && !Bonds.isBefriended(g.creature));
          if (waiting) return Gates.tracker('woods');
          if (fragmentsCollected.value < fragmentsRequired) {
            return '${Gates.tracker('woods')} · memory fragments '
                '${fragmentsCollected.value}/$fragmentsRequired (pond grotto, east grove)';
          }
          return '${Gates.tracker('woods')} · the fallen boulder on the south road';
        }
        if (job != null && _step >= _l1Asha) return job;
        return _step >= _l1Asha
            ? 'Next: find Asha at her camp south of the standing stones — she knows the woods'
            : 'Mission: talk to Gaia by the crash site (green figure nearby)';
      case 2:
        if (portalUnlocked.value || _step >= _l2Core) {
          if (!Adventure.openedArchive &&
              (Bonds.hasItem('archive_seal') ||
                  Bonds.usedItem('archive_seal') ||
                  Adventure.hasClue('archivist_seal'))) {
            return 'Open the Archive (optional) — then south to the Ruins';
          }
          return job ?? 'South road → Ruins · or walk east to Lantern Town';
        }
        if (_step >= _l2Quiet || SaveService.data.flag('sentinelDefeated')) {
          return 'Speak with the Archivist — then the road south opens';
        }
        if (_step >= _l2Sentinel) return 'Quiet the UEC Sentinel';
        if (_step >= _l2Voss) return 'Hear what Commander Voss wants';
        if (Bonds.hasItem('archive_seal') && !Adventure.openedArchive) {
          return 'Use the Archivist\'s seal on the Archive Library';
        }
        if (_step >= _l2Archivist) return 'Seek out the Archivist';
        return 'Arrival plaza: west → market & Echo-7 · south → Archive Square · east → Lantern Gate';
      case 3:
        if (Adventure.flag('ruins_gate_open')) {
          return 'Descend to Gaia\'s Core';
        }
        if (Bonds.hasItem('ruins_gate_key')) {
          return 'Back to the SE sealed gate — USE the keystone';
        }
        // Always steer toward the key; shrine / Memory 5 stay optional side paths.
        if (_step >= _l3Shrine ||
            Adventure.hasClue('shrine_note') ||
            Adventure.hasClue('ruins_ring') ||
            Adventure.hasClue('ruins_landing') ||
            _step >= _l3Light) {
          return 'North-east wing for the Aetherian Keystone (opens SE gate)';
        }
        return 'Central clearing · then NE for the keystone (SE gate is locked)';
      case 4:
        if (portalUnlocked.value || _step >= _l4Activate) {
          if (Memories.allFound) return 'Activate the Core Record';
          return 'Activate Core (${Memories.progressLabel}) — or seek missing memories';
        }
        if (Memories.allFound) {
          return _step >= _l4Gaia ? 'Speak with Gaia at the dais' : 'Enter Gaia\'s Core';
        }
        return _step >= _l4Gaia
            ? 'Speak with Gaia · memories ${Memories.progressLabel}'
            : 'Core ahead · memories ${Memories.progressLabel}';
      case 5:
        return job ?? 'Mira\'s stall (trade glimmer) · job board · west road → City';
    }
    return '';
  }
}
