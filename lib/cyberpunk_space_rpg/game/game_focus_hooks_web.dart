import 'dart:html' as html;

import 'package:flutter/foundation.dart';

/// Web: tab hide / window blur often drops KeyUp, leaving WASD stuck.
///
/// Complements [AppLifecycleState] — blur can fire while the tab stays
/// "visible" (another window focused).
void installGameFocusHooks({
  required VoidCallback onLost,
  required VoidCallback onGained,
}) {
  html.window.onBlur.listen((_) => onLost());
  html.window.onFocus.listen((_) => onGained());
  html.document.onVisibilityChange.listen((_) {
    if (html.document.hidden ?? false) {
      onLost();
    } else {
      onGained();
    }
  });
}
