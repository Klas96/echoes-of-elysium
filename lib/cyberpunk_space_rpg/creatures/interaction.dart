import 'dart:math';

import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/ai_fragment.dart';
import '../components/npc_character.dart';

/// What the interact prompt shows for the focused object.
@immutable
class PromptInfo {
  /// Action, e.g. BEFRIEND, PUSH, READ.
  final String label;

  /// Seconds E / the button must be held (0 = a tap).
  final double hold;
  final bool enabled;

  /// Clue shown instead of an action when [enabled] is false.
  final String note;

  /// Key item id whose icon is shown beside the prompt (see ItemIcon).
  final String? item;

  const PromptInfo(this.label, {this.hold = 0, this.item}) : enabled = true, note = '';
  const PromptInfo.note(this.note, {this.item}) : label = '', hold = 0, enabled = false;

  @override
  bool operator ==(Object other) =>
      other is PromptInfo &&
      other.label == label &&
      other.hold == hold &&
      other.enabled == enabled &&
      other.note == note &&
      other.item == item;

  @override
  int get hashCode => Object.hash(label, hold, enabled, note, item);
}

/// Something in the world the player can interact with (creatures, rest
/// spots, boulders, glyphs...). Registers itself while mounted; the
/// [InteractionManager] focuses the nearest one in range.
mixin Interactable on GameComponent {
  Vector2 get interactPoint => absoluteCenter;
  double get interactRadius => 44;
  bool get canFocus => true;
  PromptInfo get prompt;
  void interact();

  @override
  void onMount() {
    super.onMount();
    Interaction.registry.add(this);
  }

  @override
  void onRemove() {
    Interaction.registry.remove(this);
    if (Interaction.focus.value == this) Interaction.focus.value = null;
    super.onRemove();
  }
}

class Interaction {
  static final registry = <Interactable>{};
  static final focus = ValueNotifier<Interactable?>(null);
  static final info = ValueNotifier<PromptInfo?>(null);

  /// 0..1 while a hold action is being held.
  static final progress = ValueNotifier<double>(0);

  /// The on-screen button is held (phones have no E key).
  static bool touchHeld = false;

  /// A tap that may be shorter than a frame; consumed once.
  static bool touchTapped = false;

  static void reset() {
    focus.value = null;
    info.value = null;
    progress.value = 0;
    touchHeld = false;
    touchTapped = false;
  }
}

/// Picks the focused interactable each frame and runs tap/hold input
/// (E key or the on-screen prompt). NPC talk and AI fragments keep priority.
class InteractionManager extends GameComponent {
  double _held = 0;
  bool _needRelease = false;
  Interactable? _last;

  @override
  void update(double dt) {
    super.update(dt);
    final player = gameRef.player;
    Interactable? best;
    final busy = NpcCharacter.showPrompt.value ||
        AIFragment.showPrompt.value ||
        NpcCharacter.activeDialogue.value != null ||
        AIFragment.activeDialogue.value != null;
    if (player != null && !busy) {
      final pc = player.position + player.size / 2;
      var bestD = double.infinity;
      for (final i in Interaction.registry) {
        if (!i.isMounted || !i.canFocus) continue;
        final d = i.interactPoint.distanceTo(pc);
        if (d <= i.interactRadius && d < bestD) {
          bestD = d;
          best = i;
        }
      }
    }
    final info = best?.prompt;
    if (Interaction.focus.value != best) Interaction.focus.value = best;
    if (Interaction.info.value != info) Interaction.info.value = info;

    final pressed = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.keyE) ||
        Interaction.touchHeld ||
        Interaction.touchTapped;
    Interaction.touchTapped = false;
    if (best != _last) {
      _last = best;
      _held = 0;
      _needRelease = pressed;
    }
    if (!pressed) _needRelease = false;
    if (best != null && info != null && info.enabled && pressed && !_needRelease) {
      _held += dt;
      if (_held >= info.hold) {
        _held = 0;
        _needRelease = true;
        best.interact();
      }
    } else {
      _held = 0;
    }
    final p = (info != null && info.hold > 0) ? (_held / info.hold).clamp(0.0, 1.0) : 0.0;
    if ((Interaction.progress.value - p).abs() > 0.001) Interaction.progress.value = p;
  }

  @override
  void onRemove() {
    Interaction.reset();
    super.onRemove();
  }
}

/// A short message card (bond moments, finds, lore).
@immutable
class ToastMessage {
  final String title;
  final String body;
  final Color color;
  final String? portrait;
  final int id;
  final bool compact;

  /// Key item id whose icon is shown (even on compact toasts).
  final String? item;
  const ToastMessage(this.title, this.body, this.color, this.portrait, this.id,
      {this.compact = false, this.item});
}

class GameToast {
  static final current = ValueNotifier<ToastMessage?>(null);
  static int _n = 0;

  /// [compact]: small corner chip — one short line, no portrait, fades fast.
  static void show(
    String title, {
    String body = '',
    Color color = const Color(0xFF66FFAA),
    String? portrait,
    double seconds = 2.8,
    bool compact = false,
    String? item,
  }) {
    var b = body.trim();
    if (compact) {
      portrait = null;
      seconds = min(seconds, 2.4);
      if (b.length > 56) b = '${b.substring(0, 54)}…';
    } else if (b.length > 120) {
      b = '${b.substring(0, 118)}…';
    }
    final m = ToastMessage(title, b, color, portrait, ++_n, compact: compact, item: item);
    current.value = m;
    Future.delayed(Duration(milliseconds: (seconds * 1000).round()), () {
      if (current.value?.id == m.id) current.value = null;
    });
  }
}
