import 'dart:math';

import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';

import '../audio/sfx_manager.dart';
import '../game/adventure.dart';
import 'bonds.dart';
import 'interaction.dart';

/// World hotspot: EXAMINE (or USE ITEM when gated). Optional clue unlock.
class ExamineHotspot extends GameComponent with Interactable {
  final String id;
  final String title;
  final String text;
  final String? clueId;
  final String? requiresItem;
  final bool consumeItem;
  final String? setFlag;
  double _pulse = 0;

  ExamineHotspot(
    Vector2 position, {
    required this.id,
    required this.title,
    required this.text,
    this.clueId,
    this.requiresItem,
    this.consumeItem = false,
    this.setFlag,
  }) {
    this.position = position;
    size = Vector2.all(20);
  }

  bool get _done => Adventure.flag('examined:$id') ||
      (setFlag != null && Adventure.flag(setFlag!)) ||
      (clueId != null && Adventure.hasClue(clueId!) && requiresItem != null);

  bool get _hasKey => requiresItem == null || Bonds.hasItem(requiresItem!);

  @override
  double get interactRadius => 36;

  @override
  PromptInfo get prompt {
    if (requiresItem != null && !_hasKey && !_done) {
      final name = itemLabels[requiresItem!] ?? requiresItem!;
      return PromptInfo.note('Locked · needs $name');
    }
    if (requiresItem != null && _hasKey && !_done) {
      return const PromptInfo('USE ITEM');
    }
    if (_done) return PromptInfo.note(title);
    return const PromptInfo('EXAMINE');
  }

  @override
  void interact() {
    if (requiresItem != null && !_hasKey && !_done) return;
    if (requiresItem != null && _hasKey && !_done && consumeItem) {
      Bonds.useItem(requiresItem!);
    }
    Adventure.setFlag('examined:$id');
    if (setFlag != null) Adventure.setFlag(setFlag!);
    var body = text;
    if (clueId != null && Adventure.discover(clueId!)) {
      final clue = Adventure.byId(clueId!);
      if (clue != null) {
        body = '${clue.body}\n\n— Clue added to journal.';
      }
    }
    SfxManager().playChime();
    GameToast.show(title, body: body, color: const Color(0xFFAAEEFF), seconds: 6);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _pulse += dt * 2.2;
  }

  @override
  void render(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    final p = sin(_pulse);
    final col = _done
        ? const Color(0xFF668899)
        : (_hasKey || requiresItem == null)
            ? const Color(0xFF88DDFF)
            : const Color(0xFFAA8866);
    canvas.drawCircle(
      Offset(cx, cy),
      5 + p * 1.5,
      Paint()
        ..color = col.withOpacity(0.35 + p * 0.1)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(Offset(cx, cy), 2.2, Paint()..color = col.withOpacity(0.85));
  }
}
