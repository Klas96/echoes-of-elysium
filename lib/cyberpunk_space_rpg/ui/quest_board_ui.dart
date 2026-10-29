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

/// Lantern Town job board overlay — browse + accept. Turn-in is at the giver.
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
                      'Errands from people on the road. Accept here or from them — turn in at the giver.',
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
      QuestStatus.accepted => q.acceptedBoardLabel,
      QuestStatus.done => q.returnToLabel.toUpperCase(),
      QuestStatus.turnedIn => 'DONE',
      QuestStatus.locked => 'LOCKED',
    };
    final canAccept = s == QuestStatus.available;
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
                  Text('From ${q.giverLabel} · ${q.blurb}',
                      style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.3)),
                  const SizedBox(height: 4),
                  Text(
                    s == QuestStatus.locked
                        ? q.lockedHint
                        : s == QuestStatus.accepted && q.killTarget > 0
                            ? '${q.hint}  ${Quests.kills(q.id)}/${q.killTarget}'
                            : s == QuestStatus.accepted
                                ? q.hint
                                : s == QuestStatus.done
                                    ? (blockedTurnIn
                                        ? 'Bring the moonflower bloom to ${q.giverLabel}.'
                                        : q.returnToLabel)
                                    : 'Reward: ${q.glimmer}◆${q.gearId != null ? ' + gear' : ''}',
                    style: const TextStyle(color: _amber, fontSize: 10, letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            TextButton(
              onPressed: !canAccept
                  ? null
                  : () {
                      Quests.accept(q.id);
                    },
              style: TextButton.styleFrom(
                backgroundColor: _teal.withValues(alpha: canAccept ? 0.18 : 0.06),
                side: BorderSide(
                    color: _teal.withValues(alpha: canAccept ? 0.8 : 0.25)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: canAccept ? _teal : Colors.white24,
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
