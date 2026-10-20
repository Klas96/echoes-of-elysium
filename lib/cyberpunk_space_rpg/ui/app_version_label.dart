import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Quiet "v0.3.9" from the built [pubspec] version (not a hand-kept string).
class AppVersionLabel extends StatelessWidget {
  final TextAlign align;
  final double fontSize;

  const AppVersionLabel({
    super.key,
    this.align = TextAlign.center,
    this.fontSize = 11,
  });

  static Future<PackageInfo>? _cached;

  static Future<PackageInfo> _info() =>
      _cached ??= PackageInfo.fromPlatform();

  /// e.g. `v0.3.9` — empty while loading / on failure.
  static Future<String> label() async {
    try {
      final info = await _info();
      final v = info.version.trim();
      if (v.isEmpty) return '';
      return v.startsWith('v') ? v : 'v$v';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: label(),
      builder: (context, snap) {
        final text = snap.data ?? '';
        if (text.isEmpty) return const SizedBox.shrink();
        return Text(
          text,
          textAlign: align,
          style: TextStyle(
            color: Colors.white24,
            fontSize: fontSize,
            letterSpacing: 1.4,
          ),
        );
      },
    );
  }
}
