import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A button on a [RoomPanelData]: run [onTap]; the panel closes afterwards
/// unless the action opened another panel.
@immutable
class RoomAction {
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  const RoomAction(this.label, this.onTap, {this.enabled = true});
}

/// What the room panel shows: a speaker/title, one or more pages of text
/// (NEXT between them) and optional actions on the last page.
@immutable
class RoomPanelData {
  final String title;
  final Color color;
  final List<String> pages;
  final List<RoomAction> actions;

  /// Small status line under the text (glimmer, stash balance...).
  final String footer;

  /// Book pages: serif-ish italic body.
  final bool book;

  const RoomPanelData({
    required this.title,
    required this.pages,
    this.color = const Color(0xFFFFC27A),
    this.actions = const [],
    this.footer = '',
    this.book = false,
  });
}

/// Talk / read / menu card for the interiors (#31). Self-contained so the
/// room scene does not depend on the overworld dialogue layer.
class RoomPanel {
  RoomPanel._();
  static final current = ValueNotifier<RoomPanelData?>(null);
  static final page = ValueNotifier<int>(0);

  /// The room scene pauses its engine while a panel is open.
  static void Function(bool open)? onOpenChanged;

  static bool get isOpen => current.value != null;

  static void show(RoomPanelData d) {
    final was = isOpen;
    page.value = 0;
    current.value = d;
    if (!was) onOpenChanged?.call(true);
  }

  static void close() {
    if (!isOpen) return;
    current.value = null;
    page.value = 0;
    onOpenChanged?.call(false);
  }

  static bool get onLastPage {
    final d = current.value;
    return d == null || page.value >= d.pages.length - 1;
  }

  /// NEXT, or CLOSE on the last page when there is nothing to pick.
  static void advance() {
    final d = current.value;
    if (d == null) return;
    if (!onLastPage) {
      page.value++;
    } else if (d.actions.isEmpty) {
      close();
    }
  }

  static void pick(RoomAction a) {
    if (!a.enabled) return;
    final before = current.value;
    a.onTap();
    // Still showing the same card: the action is done, close it.
    if (identical(current.value, before)) close();
  }

  /// Keyboard: E / Enter / Space = next, Esc = close, 1-9 = action.
  static KeyEventResult handleKey(KeyEvent e) {
    final d = current.value;
    if (d == null || e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape) {
      close();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyE || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.space) {
      advance();
      return KeyEventResult.handled;
    }
    if (onLastPage) {
      final n = int.tryParse(e.character ?? '');
      if (n != null && n >= 1 && n <= d.actions.length) {
        pick(d.actions[n - 1]);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }
}

class RoomPanelLayer extends StatelessWidget {
  const RoomPanelLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([RoomPanel.current, RoomPanel.page]),
      builder: (context, _) {
        final d = RoomPanel.current.value;
        if (d == null) return const SizedBox.shrink();
        final i = RoomPanel.page.value.clamp(0, d.pages.length - 1);
        final last = i >= d.pages.length - 1;
        final actions = last ? d.actions : const <RoomAction>[];
        return Positioned(
          bottom: 20,
          left: 16,
          right: 16,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0806).withValues(alpha: 0.95),
                  border: Border.all(color: d.color, width: 1.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.title.toUpperCase(),
                        style: TextStyle(
                            color: d.color, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 3)),
                    const SizedBox(height: 8),
                    Text(d.pages[i],
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.82),
                            fontSize: 15,
                            height: 1.6,
                            fontStyle: d.book ? FontStyle.italic : FontStyle.normal)),
                    if (d.footer.isNotEmpty && last) ...[
                      const SizedBox(height: 6),
                      Text(d.footer, style: const TextStyle(color: Colors.white38, fontSize: 11, height: 1.4)),
                    ],
                    if (actions.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final a in actions) _PanelButton(a, d.color),
                      ]),
                    ],
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TextButton(
                        onPressed: RoomPanel.close,
                        child: Text(actions.isNotEmpty ? 'LEAVE' : (last ? 'CLOSE' : 'SKIP'),
                            style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1)),
                      ),
                      if (!last)
                        TextButton(
                          onPressed: RoomPanel.advance,
                          child: Text('NEXT ›',
                              style: TextStyle(color: d.color, fontSize: 12, letterSpacing: 1)),
                        ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PanelButton extends StatelessWidget {
  final RoomAction action;
  final Color color;
  const _PanelButton(this.action, this.color);

  @override
  Widget build(BuildContext context) {
    final c = action.enabled ? color : Colors.white24;
    return GestureDetector(
      onTap: () => RoomPanel.pick(action),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.withValues(alpha: action.enabled ? 0.16 : 0.05),
          border: Border.all(color: c),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(action.label,
            style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
      ),
    );
  }
}
