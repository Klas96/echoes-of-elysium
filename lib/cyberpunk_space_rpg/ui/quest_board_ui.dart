import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import '../creatures/bonds.dart';
import '../game/quests.dart';

bool get _isTouch =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

const _teal = Color(0xFF00FFCC);
const _amber = Color(0xFFFFE08A);
const _ink = Color(0xFF06060F);

/// Lantern Town job board overlay.
class QuestBoard {
  static final open = ValueNotifier<bool>(false);
  static void Function(bool open)? onOpenChanged;
  static void Function()? dismissOthers;

  static void show() {
    dismissOthers?.call();
    if (open.value) return;
    open.value = true;
    onOpenChanged?.call(true);
  }

  static void hide() {
    if (!open.value) return;
    open.value = false;
    onOpenChanged?.call(false);
  }

  static void toggle() => open.value ? hide() : show();
}

class QuestBoardOverlay extends StatelessWidget {
  const QuestBoardOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: QuestBoard.open,
      builder: (_, open, __) =>
          open ? const _BoardPanel() : const SizedBox.shrink(),
    );
  }
}

class _BoardPanel extends StatelessWidget {
  const _BoardPanel();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 520),
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
              decoration: BoxDecoration(
                color: _ink.withValues(alpha: 0.96),
                border: Border.all(color: _teal.withValues(alpha: 0.7), width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: AnimatedBuilder(
                animation: Listenable.merge([Quests.revision, Bonds.revision]),
                builder: (_, __) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'JOB BOARD',
                            style: TextStyle(
                              color: _teal,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 3,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: QuestBoard.hide,
                          icon: const Icon(Icons.close, color: Colors.white38, size: 20),
                        ),
                      ],
                    ),
                    const Text(
                      'Errands for travellers — woods and city. Return here to turn in.',
                      style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    ...Quests.catalog.map(_jobRow),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: QuestBoard.hide,
                        child: Text(
                          _isTouch ? 'DONE' : 'DONE  (Esc)',
                          style: const TextStyle(color: Colors.white38, letterSpacing: 1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _jobRow(QuestDef q) {
    final s = Quests.status(q.id);
    final label = switch (s) {
      QuestStatus.available => 'ACCEPT',
      QuestStatus.accepted => 'IN WOODS',
      QuestStatus.done => 'TURN IN',
      QuestStatus.turnedIn => 'DONE',
      QuestStatus.locked => 'LOCKED',
    };
    final canAct = s == QuestStatus.available || s == QuestStatus.done;
    final blockedTurnIn = s == QuestStatus.done &&
        q.requiresItem != null &&
        !Bonds.hasItem(q.requiresItem!);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          border: Border.all(color: Colors.white12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(q.title,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(q.blurb,
                      style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.3)),
                  const SizedBox(height: 4),
                  Text(
                    s == QuestStatus.accepted || s == QuestStatus.done
                        ? q.hint
                        : 'Reward: ${q.glimmer}◆${q.gearId != null ? ' + gear' : ''}',
                    style: const TextStyle(color: _amber, fontSize: 10, letterSpacing: 0.5),
                  ),
                  if (blockedTurnIn)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('Bring the moonflower bloom to turn in.',
                          style: TextStyle(color: Color(0xFFFF8866), fontSize: 10)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            TextButton(
              onPressed: !canAct || blockedTurnIn
                  ? null
                  : () {
                      if (s == QuestStatus.available) {
                        Quests.accept(q.id);
                      } else if (s == QuestStatus.done) {
                        Quests.turnIn(q.id);
                      }
                    },
              style: TextButton.styleFrom(
                backgroundColor: _teal.withValues(alpha: canAct && !blockedTurnIn ? 0.18 : 0.06),
                side: BorderSide(
                    color: _teal.withValues(alpha: canAct && !blockedTurnIn ? 0.8 : 0.25)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: canAct && !blockedTurnIn ? _teal : Colors.white24,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
