/// Thin hook so HUD chips can open the pause menu without importing the map.
class Pause {
  static void Function(bool on)? set;

  static void show() => set?.call(true);
  static void hide() => set?.call(false);
}
