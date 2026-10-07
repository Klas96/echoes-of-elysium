import 'package:flutter/material.dart';

import 'memories.dart';
import 'save_service.dart';

/// Level state and the HUD objective line.
///
/// Objectives are a gentle guide, never a gate: the talk steps only move the
/// text forward, and fragment collection, the Sentinel and the portals work
/// exactly as before whatever order the player does things in. Each level
/// keeps a step index that only ever grows, so a later event (a fragment, the
/// Sentinel) skips any talk steps it supersedes.
class GameState {
  static final objective = ValueNotifier<String>('');
  static final fragmentsCollected = ValueNotifier<int>(0);
  /// Memory fragments 1-2 are in the woods; both open its portal (the
  /// other three memories are optional, see Memories).
  static const fragmentsRequired = 2;
  static final portalUnlocked = ValueNotifier<bool>(false);

  /// Shown when the game is finished.
  static const endingText = 'The Aetherians live on.';

  // 1 woods, 2 city, 3 ruins (0 before any map is ready).
  static int _level = 0;
  static int _step = 0;

  // Level 1 steps
  static const _l1Gaia = 0, _l1Asha = 1, _l1Fragments = 2, _l1Portal = 3;
  // Level 2 steps
  static const _l2Echo = 0, _l2Archivist = 1, _l2Voss = 2, _l2Sentinel = 3, _l2Core = 4;
  // Level 3 steps
  static const _l3Ruins = 0, _l3Light = 1;

  /// Tiled map stem and region id for each level, as stored in the save.
  static const mapIds = {1: 'world', 2: 'world2', 3: 'world3'};
  static const regionIds = {1: 'woods', 2: 'city', 3: 'ruins'};

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
  }

  /// CONTINUE: put a level back the way the save left it.
  static void restore(int level, SaveData d) {
    _level = level;
    _step = d.objectiveStep;
    switch (level) {
      case 1:
        fragmentsCollected.value = d.fragments.clamp(0, fragmentsRequired);
        portalUnlocked.value = d.flag('portalUnlocked:world') || d.fragments >= fragmentsRequired;
      case 2:
        portalUnlocked.value = d.flag('portalUnlocked:world2') || d.flag('sentinelDefeated');
      default:
        portalUnlocked.value = true;
    }
    _refresh();
  }

  static void _progress() => SaveService.requestAutosave();

  static void resetMap1() {
    _level = 1;
    _step = _l1Gaia;
    fragmentsCollected.value = 0;
    portalUnlocked.value = false;
    _refresh();
  }

  static void resetMap2() {
    _level = 2;
    _step = _l2Echo;
    portalUnlocked.value = false;
    _refresh();
  }

  static void resetMap3() {
    _level = 3;
    _step = _l3Ruins;
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
    if (n >= fragmentsRequired) {
      portalUnlocked.value = true;
      _advance(1, _l1Portal);
    } else {
      _advance(1, _l1Fragments);
    }
    _refresh();
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
        _advance(1, _l1Asha);
      case 'asha':
        _advance(1, _l1Fragments);
      case 'echo7':
        _advance(2, _l2Archivist);
      case 'archivist':
        _advance(2, _l2Voss);
      case 'voss':
        _advance(2, _l2Sentinel);
    }
  }

  /// The Sentinel noticed the player (or was hit): skip straight to it.
  static void onSentinelEngaged() => _advance(2, _l2Sentinel);

  static void onSentinelDefeated() {
    SaveService.data.setFlag('sentinelDefeated');
    portalUnlocked.value = true;
    _advance(2, _l2Core);
    _refresh();
    _progress();
  }

  /// The player is close to the level's portal.
  static void onNearPortal() => _advance(3, _l3Light);

  static void _advance(int level, int step) {
    if (_level != level || step <= _step) return;
    _step = step;
    _refresh();
    _progress();
  }

  static void _refresh() {
    objective.value = _text();
  }

  static String _text() {
    switch (_level) {
      case 1:
        if (portalUnlocked.value || _step >= _l1Portal) return 'Slip past the UEC patrols to the portal';
        if (_step >= _l1Fragments) {
          return 'Gather the Aetherian fragments (${fragmentsCollected.value}/$fragmentsRequired)';
        }
        return _step >= _l1Asha ? 'Find Asha by the old trail' : 'Listen to Gaia';
      case 2:
        if (portalUnlocked.value || _step >= _l2Core) return 'Follow the path to the Core';
        if (_step >= _l2Sentinel) return 'Quiet the UEC Sentinel';
        if (_step >= _l2Voss) return 'Hear what Commander Voss wants';
        return _step >= _l2Archivist ? 'Seek out the Archivist' : 'Meet Echo-7';
      case 3:
        return _step >= _l3Light ? 'Reach the light at the Extraction Point' : 'Find a way through the ruins';
    }
    return '';
  }
}
