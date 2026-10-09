import '../components/ai_fragment.dart';
import '../components/npc_character.dart';

/// Thin hook so HUD chips can open the pause menu without importing the map.
class Pause {
  static void Function(bool on)? set;

  /// When true, clearing dialogue must not auto-resume the engine (story
  /// flashbacks are about to keep it paused).
  static bool suppressDialogueHold = false;

  static void show() => set?.call(true);
  static void hide() => set?.call(false);

  /// Close talk/absorb UI without firing the overlay resume path.
  static void dismissDialogueForStory() {
    suppressDialogueHold = true;
    NpcCharacter.activeDialogue.value = null;
    AIFragment.activeDialogue.value = null;
    suppressDialogueHold = false;
  }
}
