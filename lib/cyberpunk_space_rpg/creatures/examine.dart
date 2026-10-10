import 'dart:math';

import 'package:bonfire/bonfire.dart';
import 'package:flutter/material.dart';

import '../audio/sfx_manager.dart';
import '../game/adventure.dart';
import '../game/game_state.dart';
import '../game/quests.dart';
import '../ui/quest_board_ui.dart';
import '../ui/shop_ui.dart';
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
  final String? giveItem;
  final String? completeQuest;
  final bool openQuestBoard;
  final bool openShop;
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
    this.giveItem,
    this.completeQuest,
    this.openQuestBoard = false,
    this.openShop = false,
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
    if (openQuestBoard) return const PromptInfo('READ BOARD');
    if (openShop) return const PromptInfo('TRADE');
    if (requiresItem != null && !_hasKey && !_done) {
      if (requiresItem == 'ruins_gate_key') {
        return PromptInfo.note('Sealed · keystone is in the NE wing', item: requiresItem);
      }
      final name = itemLabels[requiresItem!] ?? requiresItem!;
      return PromptInfo.note('Locked · needs $name', item: requiresItem);
    }
    if (requiresItem != null && _hasKey && !_done) {
      return PromptInfo('USE ITEM', item: requiresItem);
    }
    if (_done) return PromptInfo.note(title);
    if (_dropVisible) return PromptInfo('EXAMINE', item: giveItem);
    return const PromptInfo('EXAMINE');
  }

  @override
  void interact() {
    if (openQuestBoard) {
      QuestBoard.show();
      return;
    }
    if (openShop) {
      Shop.show();
      return;
    }
    if (requiresItem != null && !_hasKey && !_done) {
      final name = itemLabels[requiresItem!] ?? requiresItem!;
      final body = requiresItem == 'ruins_gate_key'
          ? 'Find the Aetherian Keystone in the north-east wing, then return here.'
          : 'Needs $name.';
      GameToast.show('SEALED', body: body, color: const Color(0xFFFFAABB), compact: true, item: requiresItem);
      GameState.refreshObjective();
      return;
    }
    if (requiresItem != null && _hasKey && !_done && consumeItem) {
      Bonds.useItem(requiresItem!);
    }
    Adventure.setFlag('examined:$id');
    if (setFlag != null) Adventure.setFlag(setFlag!);
    String? gotItem;
    if (giveItem != null && !Bonds.hasItem(giveItem!) && !Bonds.usedItem(giveItem!)) {
      Bonds.giveItem(giveItem!);
      gotItem = giveItem;
    }
    if (completeQuest != null) Quests.complete(completeQuest!);
    Quests.onExamined(id);
    final loggedClue = clueId != null && Adventure.discover(clueId!);
    var reward = 0;
    if (loggedClue) {
      reward = requiresItem != null ? 10 : 5;
      Bonds.addGlimmer(reward);
    }
    if (clueId == 'shrine_note') GameState.onShrineExamined();
    SfxManager().playChime();
    GameToast.show(
      title,
      body: loggedClue
          ? (reward > 0 ? '+$reward glimmer · clue logged' : 'Clue logged · Journal → Clues')
          : text,
      color: const Color(0xFFAAEEFF),
      compact: true,
      item: gotItem ?? (consumeItem ? requiresItem : null),
    );
  }

  /// A [giveItem] not yet picked up shows its world-drop art.
  bool get _dropVisible =>
      giveItem != null && !_done && !Bonds.hasItem(giveItem!) && !Bonds.usedItem(giveItem!);

  SpriteAnimationTicker? _drop;

  @override
  Future<void> onLoad() async {
    final path = itemDropSparkle(giveItem);
    if (path != null) {
      try {
        // <id>_drop_sparkle.png: 2 frames of 32x32 at 0.4 s (Designer json);
        // hold the plain drop longer than the sparkle.
        final img = await Flame.images.load(path);
        final n = max(1, img.width ~/ 32);
        _drop = SpriteAnimation.fromFrameData(
          img,
          SpriteAnimationData.variable(
            amount: n,
            stepTimes: [for (var i = 0; i < n; i++) i == 0 ? 1.2 : 0.4],
            textureSize: Vector2.all(32),
          ),
        ).createTicker();
      } catch (_) {
        _drop = null;
      }
    }
    return super.onLoad();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _pulse += dt * 2.2;
    _drop?.update(dt);
  }

  @override
  void render(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    final p = sin(_pulse);
    if (_drop != null && _dropVisible) {
      // 32x32 drop, centred on the hotspot with a soft glow under it.
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy + 9), width: 18, height: 6),
        Paint()
          ..color = const Color(0xFF88DDFF).withValues(alpha: 0.25 + p * 0.08)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      _drop!.getSprite().render(
            canvas,
            position: Vector2(cx - 16, cy - 16),
            size: Vector2.all(32),
            overridePaint: Paint()..filterQuality = FilterQuality.none,
          );
      return;
    }
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
