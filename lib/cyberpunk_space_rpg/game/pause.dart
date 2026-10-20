import '../components/ai_fragment.dart';
import '../components/npc_character.dart';
import '../creatures/journal_ui.dart';

/// Thin hook: HUD / Esc open the journal hub (field tablet).
/// [set] still freezes the engine without UI when a caller needs a silent pause.
class Pause {
  static void Function(bool on)? set;

  /// When true, clearing dialogue must not auto-resume the engine (story
  /// flashbacks are about to keep it paused).
  static bool suppressDialogueHold = false;

  static void show() => Journal.show();
  static void hide() => Journal.hide();

  /// Close talk/absorb UI without firing the overlay resume path.
  static void dismissDialogueForStory() {
    suppressDialogueHold = true;
    NpcCharacter.activeDialogue.value = null;
    AIFragment.activeDialogue.value = null;
    suppressDialogueHold = false;
  }
}
