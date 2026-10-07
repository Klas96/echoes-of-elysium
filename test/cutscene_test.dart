import 'dart:io';

import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/custom_map_game.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/game/save_service.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/ui/cutscene_player.dart';
import 'package:cyberpunk_space_rpg/cyberpunk_space_rpg/ui/cutscenes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Cutscene _asset(String id) => Cutscene.parse(
      File('assets/cutscenes/$id/$id.json').readAsStringSync(),
      basePath: 'assets/cutscenes/$id',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SaveService.data = SaveData();
    SaveService.hasSave.value = false;
    SaveService.snapshot = null;
  });

  group('parsing', () {
    test('awakening.json (Designer format) parses fully', () {
      final s = _asset('awakening');
      expect(s.id, 'awakening');
      expect(s.size, const Size(1280, 720));
      expect(s.panels, hasLength(5));
      expect(s.panels.first.image, 'assets/cutscenes/awakening/awakening_p1.webp');
      expect(s.panels.first.from, const PanKey(1.0, 0.5, 0.5));
      expect(s.panels.first.to, const PanKey(1.08, 0.45, 0.5));
      expect(s.panels[1].lines.single.text, startsWith('Dr. Kaela Osei'));
      expect(s.speaker('N').narrator, isTrue);
      expect(s.speaker('GAIA').name, 'GAIA');
      expect(s.speaker('GAIA').color, const Color(0xFF00FF88));

      final fx = s.panels[2].effects.single;
      expect(fx.type, 'brighten');
      expect(fx.color, const Color(0xFF00FF88));
      expect(fx.duration, 1.5);
      expect(fx.amount(0), 0);
      expect(fx.amount(fx.start + fx.duration), closeTo(fx.strength, 1e-9));

      final card = s.panels[4].titleCard!;
      expect(card.text, 'ECHOES OF ELYSIUM');
      expect(card.position.dy, lessThan(0.4)); // upper sky
      for (final p in s.panels.take(4)) {
        expect(p.titleCard, isNull);
      }
      for (final p in s.panels) {
        expect(File(p.image).existsSync(), isTrue, reason: p.image);
      }
    });

    test('coalition.json parses, including the glow pulse shorthand', () {
      final s = _asset('coalition');
      expect(s.panels, hasLength(4));
      expect(s.panels[0].lines, isEmpty);
      expect(s.panels[2].lines.single.speaker, 'VOSS');
      expect(s.panels[3].effects.single.type, 'pulse');
      expect(s.panels[3].effects.single.color, const Color(0xFF00FF88));
      for (final p in s.panels) {
        expect(File(p.image).existsSync(), isTrue, reason: p.image);
      }
    });

    test('lenient: bad fields fall back, extended keys are honoured', () {
      final s = Cutscene.parse('''{
        "id": "x", "crossfade": "slow", "panelDuration": 5,
        "speakers": {"ECHO": {"name": "THE ECHO", "color": "#FF00FF"}},
        "panels": [
          {"lines": [{"text": "no image, dropped"}]},
          {"image": "assets/elsewhere/a.webp", "pan": {"from": [2, 0.1, 0.9]},
           "duration": 3, "lines": ["plain string", {"speaker": "ECHO", "text": "hi", "delay": 1, "hold": 2}, {"text": ""}],
           "fx": [{"type": "darken", "color": "black"}, {"type": "wobble"}, "flash white"],
           "titleCard": {"text": "THE END", "subtitle": "x", "position": [0.5, 0.8], "hold": 2}},
          {"image": "b.webp", "pan": "nope", "fx": "nothing here"}
        ]}''', basePath: 'assets/cutscenes/x');
      expect(s.crossfade, 0.8);
      expect(s.panels, hasLength(2));
      final a = s.panels[0];
      expect(a.image, 'assets/elsewhere/a.webp');
      expect(a.duration, 3);
      expect(a.from, a.to); // only "from" given: hold still
      expect(a.from.clampedCenter(), const Offset(0.25, 0.75));
      expect(a.lines.map((l) => l.text), ['plain string', 'hi']);
      expect(a.lines[1].delay, 1);
      expect(a.lines[1].holdSeconds, 2);
      expect(a.effects.map((e) => e.type), ['darken', 'flash']);
      expect(a.titleCard!.position, const Offset(0.5, 0.8));
      expect(s.speaker('ECHO').name, 'THE ECHO');
      final b = s.panels[1];
      expect(b.image, 'assets/cutscenes/x/b.webp');
      expect(b.duration, 5);
      expect(b.from, PanKey.identity);
      expect(b.effects, isEmpty);
    });

    test('coalition p4: pulse through the glow mask', () {
      final s = _asset('coalition');
      final fx = s.panels[3].effects.single;
      expect(fx.type, 'pulse');
      expect(fx.color, const Color(0xFF00FF88));
      expect(fx.mask, 'assets/cutscenes/coalition/coalition_p4_glow.webp');
      expect(fx.isLocal, isTrue);
      expect(s.maskPaths, [fx.mask]);
      expect(File(fx.mask!).existsSync(), isTrue);
      // Peaks one breath in, then keeps breathing.
      expect(fx.amount(0), 0);
      expect(fx.amount(fx.start + fx.duration * 1.5), closeTo(fx.strength, 1e-6));
    });

    test('mask and soft-spot fields', () {
      final s = Cutscene.parse('''{"panels": [{"image": "a.webp", "fx": [
          {"type": "brighten", "mask": "m.webp", "strength": 0.5},
          {"type": "flash", "mask": "assets/x/abs.webp"},
          {"type": "brighten", "center": [0.2, 0.7], "radius": 0.1},
          "pulse green glow on the seed (x0.58, y0.63)",
          "brighten cyan from the flower over 2 s"]}]}''', basePath: 'assets/cutscenes/t');
      final fx = s.panels.single.effects;
      expect(fx[0].mask, 'assets/cutscenes/t/m.webp');
      expect(fx[0].strength, 0.5);
      expect(fx[1].mask, 'assets/x/abs.webp');
      expect(fx[2].center, const Offset(0.2, 0.7));
      expect(fx[2].radius, 0.1);
      expect(fx[3].type, 'pulse');
      expect(fx[3].center, const Offset(0.58, 0.63));
      expect(fx[4].center, isNull);
      expect(fx[4].mask, isNull);
      expect(fx[4].duration, 2);
    });

    test('all five memory flashbacks parse', () {
      for (var n = 1; n <= 5; n++) {
        final s = _asset('memory$n');
        expect(s.id, 'memory$n');
        expect(s.panels, hasLength(n == 5 ? 4 : 3), reason: 'memory$n');
        expect(s.crossfade, n == 5 ? 1.2 : 0.8);
        for (final p in s.panels) {
          expect(p.duration, n == 5 ? 8.0 : 7.0);
          expect(p.lines, isNotEmpty);
          expect(p.image, endsWith('.webp'));
          expect(File(p.image).existsSync(), isTrue, reason: p.image);
        }
      }
      final m3 = _asset('memory3');
      expect(m3.panels[1].effects.single.center, const Offset(0.58, 0.63));
      expect(m3.speaker('ARCHIVIST').color, const Color(0xFFFFDD44));
      expect(m3.speaker('AETHERIAN').color, const Color(0xFFCC66FF));
      expect(_asset('memory4').panels[2].effects.single.center, const Offset(0.79, 0.36));
      expect(_asset('memory5').panels[3].effects.single.type, 'brighten');
    });

    test('cutscene assets ship as WebP only', () {
      final pngs = Directory('assets/cutscenes')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.png'));
      expect(pngs, isEmpty);
    });

    test('no usable panels is an error', () {
      expect(() => Cutscene.parse('{"panels": []}'), throwsFormatException);
      expect(() => Cutscene.parse('[1]'), throwsFormatException);
    });
  });

  group('playback', () {
    void run(CutscenePlayback p, double seconds) {
      for (var t = 0.0; t < seconds && !p.isDone; t += 1 / 30) {
        p.tick(1 / 30);
      }
    }

    test('plays every panel and the title card, then finishes once', () {
      var done = 0;
      final p = CutscenePlayback(_asset('awakening'), onDone: () => done++);
      final seen = <int>{};
      for (var i = 0; i < 30 * 120 && !p.isDone; i++) {
        p.tick(1 / 30);
        seen.add(p.panelIndex);
        if (p.phase == CutscenePhase.title) expect(p.panelIndex, 4);
      }
      expect(seen, {0, 1, 2, 3, 4});
      expect(p.isDone, isTrue);
      expect(done, 1);
      run(p, 5);
      expect(done, 1);
    });

    test('taps reveal, then advance; skip fades out', () {
      final p = CutscenePlayback(_asset('awakening'));
      run(p, 0.6); // first line has started typing
      expect(p.currentLine, isNotNull);
      expect(p.lineComplete, isFalse);
      p.advance();
      expect(p.lineComplete, isTrue);
      p.advance();
      expect(p.panelIndex, 1);
      expect(p.previousIndex, 0); // crossfading
      run(p, 1);
      expect(p.previousIndex, isNull);

      var done = false;
      p.onDone = () => done = true;
      p.skip();
      expect(p.phase, CutscenePhase.outro);
      run(p, 1);
      expect(done, isTrue);
    });

    test('a long line stretches the panel instead of being cut off', () {
      final s = _asset('awakening');
      final long = s.panels[1];
      expect(CutscenePlayback.runtime(long), greaterThan(long.duration));
    });
  });

  group('player widget', () {
    for (final size in const [Size(412, 915), Size(915, 412), Size(1280, 720), Size(320, 480)]) {
      testWidgets('lays out without overflow at ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final scene = _asset('awakening');
        final playback = CutscenePlayback(scene)..frozen = true;
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(body: CutscenePlayer(playback: playback, onFinished: () {}))));
        await tester.pump();
        for (final (panel, title) in const [(1, false), (2, false), (4, true)]) {
          playback.jumpTo(panel, title: title);
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(find.text('SKIP  ▸▸'), findsOneWidget);
          if (title) {
            expect(find.text('ECHOES OF ELYSIUM'), findsOneWidget);
          } else {
            expect(find.textContaining(scene.panels[panel].lines.first.text, findRichText: true),
                findsOneWidget);
          }
        }
        // The art must stay on screen.
        final layout = CutsceneLayout.compute(size, scene.aspectRatio);
        expect(layout.visible.width, greaterThan(0));
        expect(layout.visible.bottom, lessThanOrEqualTo(size.height));
        await tester.pump(const Duration(seconds: 4)); // let the precache timeout lapse
      });
    }

    testWidgets('SKIP and Esc finish the cutscene', (tester) async {
      for (final useKey in [false, true]) {
        var finished = 0;
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: CutscenePlayer(
                    key: UniqueKey(), scene: _asset('awakening'), onFinished: () => finished++))));
        await tester.pump(const Duration(seconds: 4)); // past the precache timeout
        await tester.pump(const Duration(milliseconds: 500));
        expect(finished, 0);
        expect(find.text('SKIP  ▸▸'), findsOneWidget);
        if (useKey) {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        } else {
          await tester.tap(find.text('SKIP  ▸▸'));
        }
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(finished, 1, reason: useKey ? 'Esc' : 'SKIP');
      }
    });

    testWidgets('a missing cutscene asset does not block the game', (tester) async {
      var finished = false;
      await tester.pumpWidget(MaterialApp(
          home: CutscenePlayer(asset: 'assets/cutscenes/nope/nope.json', onFinished: () => finished = true)));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      await tester.pump();
      expect(finished, isTrue);
    });
  });

  group('story hooks', () {
    testWidgets('BEGIN JOURNEY plays The Awakening and marks it seen', (tester) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: IntroScreen()));
      await tester.tap(find.text('BEGIN JOURNEY'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(CutsceneScreen), findsOneWidget);
      expect(find.byType(CutscenePlayer), findsOneWidget);
      expect(Cutscenes.seen(Cutscenes.awakening), isFalse);
    });

    test('seen flag round-trips through the save and "once" routes skip it', () async {
      expect(Cutscenes.seen(Cutscenes.coalition), isFalse);
      await Cutscenes.markSeen(Cutscenes.coalition);
      expect(SaveService.data.storyFlags['cutscene:coalition'], isTrue);
      final stored = SaveService.decode(SaveService.encode(SaveService.data))!;
      expect(stored.flag('cutscene:coalition'), isTrue);
      expect(Cutscenes.route(id: Cutscenes.coalition, once: true, then: (_) => const SizedBox()),
          isA<MaterialPageRoute<void>>());
      expect(Cutscenes.route(id: Cutscenes.coalition, then: (_) => const SizedBox()),
          isA<PageRouteBuilder<void>>());
    });
  });
}
