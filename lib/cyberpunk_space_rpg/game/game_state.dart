import 'package:flutter/material.dart';

class GameState {
  static final objective = ValueNotifier<String>('');
  static final fragmentsCollected = ValueNotifier<int>(0);
  static const fragmentsRequired = 3;
  static final portalUnlocked = ValueNotifier<bool>(false);

  static void resetMap1() {
    objective.value = 'Collect Aetherian Fragments: 0/$fragmentsRequired';
    fragmentsCollected.value = 0;
    portalUnlocked.value = false;
  }

  static void resetMap2() {
    objective.value = 'Defeat the UEC Sentinel';
    portalUnlocked.value = false;
  }

  static void resetMap3() {
    objective.value = 'Fight through the ruins — reach the Extraction Point';
    portalUnlocked.value = true;
  }

  static void onFragmentCollected() {
    final n = fragmentsCollected.value + 1;
    fragmentsCollected.value = n;
    if (n >= fragmentsRequired) {
      objective.value = 'Reach the portal';
      portalUnlocked.value = true;
    } else {
      objective.value = 'Collect Aetherian Fragments: $n/$fragmentsRequired';
    }
  }

  static void onSentinelDefeated() {
    objective.value = 'The Sentinel is down — reach the Core';
    portalUnlocked.value = true;
  }
}
