import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/dialog_chrome.dart';

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
        final screen = MediaQuery.sizeOf(context);
        final outer = DialogChrome.outerOf(screen);
        final pad = DialogChrome.paddingOf(screen);
        final compact = DialogChrome.compactOf(screen);
        return Positioned(
          bottom: outer.bottom,
          left: outer.left,
          right: outer.right,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: DialogChrome.maxWidthOf(screen),
                maxHeight: DialogChrome.maxHeightOf(screen),
              ),
              child: DialogChrome.panel(
                accent: d.color,
                compact: compact,
                padding: pad,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DialogChrome.speakerLabel(d.title, d.color, compact: compact),
                      SizedBox(height: compact ? 6 : 8),
                      Text(d.pages[i],
                          style: DialogChrome.bodyStyle(compact: compact).copyWith(
                              fontStyle:
                                  d.book ? FontStyle.italic : FontStyle.normal)),
                      if (d.footer.isNotEmpty && last) ...[
                        SizedBox(height: compact ? 4 : 6),
                        Text(d.footer,
                            style: TextStyle(
                                color: DialogChrome.mute,
                                fontSize: compact ? 10 : 11,
                                height: 1.4)),
                      ],
                      if (actions.isNotEmpty) ...[
                        SizedBox(height: compact ? 8 : 10),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          for (final a in actions)
                            _PanelButton(a, d.color, compact: compact),
                        ]),
                      ],
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        TextButton(
                          onPressed: RoomPanel.close,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                                horizontal: compact ? 8 : 12,
                                vertical: compact ? 4 : 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                              actions.isNotEmpty
                                  ? 'LEAVE'
                                  : (last ? 'CLOSE' : 'SKIP'),
                              style: TextStyle(
                                  color: DialogChrome.mute,
                                  fontSize: compact ? 10 : 11,
                                  letterSpacing: 1)),
                        ),
                        if (!last) ...[
                          const SizedBox(width: 6),
                          DialogChrome.choiceButton(
                            label: 'NEXT ›',
                            accent: d.color,
                            filled: false,
                            compact: compact,
                            onTap: RoomPanel.advance,
                          ),
                        ],
                      ]),
                    ],
                  ),
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
  final bool compact;
  const _PanelButton(this.action, this.color, {this.compact = false});

  @override
  Widget build(BuildContext context) {
    final c = action.enabled ? color : DialogChrome.mute;
    if (!action.enabled) {
      return Opacity(
        opacity: 0.45,
        child: DialogChrome.choiceButton(
          label: action.label,
          accent: c,
          compact: compact,
          onTap: () {},
        ),
      );
    }
    return DialogChrome.choiceButton(
      label: action.label,
      accent: c,
      compact: compact,
      onTap: () => RoomPanel.pick(action),
    );
  }
}
