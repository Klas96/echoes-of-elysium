import 'package:flutter/material.dart';

import '../audio/sfx_manager.dart';
import '../components/custom_player.dart';
import '../creatures/bonds.dart';
import '../creatures/day_cycle.dart';
import '../creatures/interaction.dart';
import '../creatures/journal_ui.dart';
import '../game/adventure.dart';
import '../game/game_state.dart';
import '../game/save_service.dart';
import '../game/well_rested.dart';
import 'room_data.dart';
import 'room_panel.dart';
import 'room_services.dart';
import 'room_text.dart';

const _wen = Color(0xFFFFC27A);
const _ferro = Color(0xFFB8C4D8);
const _dao = Color(0xFFFF9E5A);
const _archivist = Color(0xFFFFDD44);
const _asha = Color(0xFFFFB347);
const _plain = Color(0xFFD8C8A8);
const _book = Color(0xFF9FD8C8);

/// The inn bed: save + "well rested" + morning.
class InnRest {
  InnRest._();

  /// Where a rest should respawn Kaela (the inn's exterior door), set by the
  /// room scene on entry.
  static void Function()? setCheckpoint;

  static Future<void> rest() async {
    final t = DayCycle.time.value;
    // Sleeping through a day still wakes you tomorrow morning; a night's
    // sleep is counted by RoomDay when the clock jumps.
    if (!DayCycle.isNight(t)) RoomDay.bump();
    DayCycle.time.value = 0.3;
    SaveService.data.dayTime = 0.3;
    CustomPlayer.healthNotifier.value = CustomPlayer.maxHealth;
    WellRested.grant(); // #32's buff, same as resting at a checkpoint
    setCheckpoint?.call();
    await SaveService.saveNow();
    SfxManager().playChime();
    GameToast.show('WELL RESTED', body: 'Morning · game saved · HP restored', color: _wen, compact: true);
  }
}

String _flavourFromNote(String note) {
  var s = note.trim();
  if (s.startsWith("'") && s.endsWith("'") && s.length > 1) s = s.substring(1, s.length - 1);
  if (s.isNotEmpty && !RegExp(r'[.!?]$').hasMatch(s)) s = '$s.';
  return s;
}

/// "First meeting" line once, then the "later" line.
String _metLine(String who, String first, String later) {
  final key = 'met:$who';
  if (Adventure.flag(key)) return later;
  Adventure.setFlag(key);
  return first;
}

/// Prompt label for a spot kind.
String promptFor(RoomSpot s) => switch (s.kind) {
      'npc' => 'TALK',
      'rest' => 'REST',
      'shop' => 'ORDER',
      'errand' => 'TALK',
      'lore' || 'clue' || 'note' => 'READ',
      'stash' => 'OPEN CHEST',
      'journal' => 'JOURNAL',
      'map' => 'MAP',
      _ => 'EXAMINE',
    };

/// What pressing E at [s] in [room] does.
void useSpot(RoomData room, RoomSpot s) {
  switch ('${room.id}/${s.id}') {
    // --- tea house ---
    case 'tea_house/wen':
      RoomPanel.show(RoomPanelData(
          title: 'Wen', color: _wen, pages: [_metLine('wen', RoomText.wenFirst, RoomText.wenLater)]));
    case 'tea_house/ferro':
      _ferroTalk();
    case 'tea_house/rest_bed':
      RoomPanel.show(RoomPanelData(title: 'Wen', color: _wen, pages: const [
        RoomText.wenRest
      ], actions: [
        RoomAction('SLEEP', () => InnRest.rest()),
      ]));
    case 'tea_house/window_seat':
      _flavour(RoomText.windowSeat);
    case 'noodle_shop/dao' || 'noodle_shop/dao_errand':
      _daoMenu(_metLine('dao', RoomText.daoFirst, RoomText.daoLater));
    case 'noodle_shop/counter_tin':
      _flavour(RoomText.counterTin);
    // --- archive ---
    case 'archive_library/archivist':
      RoomPanel.show(const RoomPanelData(title: 'Archivist', color: _archivist, pages: [RoomText.archivist]));
    case 'archive_library/book_choosing':
      _readBook(RoomText.bookChoosingTitle, RoomText.bookChoosing);
    case 'archive_library/book_lattice_keys':
      _readBook(RoomText.bookLatticeTitle, RoomText.bookLattice);
    case 'archive_library/book_field_notes':
      _readBook(RoomText.bookFieldNotesTitle, RoomText.bookFieldNotes);
      if (Adventure.discover(fieldNotesClue)) {
        Bonds.addGlimmer(5);
        GameToast.show('CLUE LOGGED', body: '+5 glimmer · Field Notes', color: _book, compact: true);
      }
    case 'archive_library/reading_desk':
      _flavour(RoomText.readingDesk);
    // --- ranger cabin ---
    case 'ranger_cabin/asha_note':
      RoomPanel.show(const RoomPanelData(title: 'A note from Asha', color: _asha, pages: [RoomText.ashaNote]));
    case 'ranger_cabin/stash_chest':
      _stash();
    case 'ranger_cabin/desk_journal':
      GameToast.show('JOURNAL',
          body: RoomText.journalCount(Bonds.befriendedCount, Bonds.total), color: _asha, compact: true);
      Journal.show();
    case 'ranger_cabin/wall_map':
      _wallMap();
    case 'ranger_cabin/stove':
      _flavour(RoomText.stove);
    default:
      _flavour(_flavourFromNote(s.note));
  }
}

/// Journal clue for the Field Notes book (points at the West Yard fragment).
const fieldNotesClue = 'archive_field_notes';

void _flavour(String text) =>
    RoomPanel.show(RoomPanelData(title: 'Examine', color: _plain, pages: [text]));

void _readBook(String title, String text) =>
    RoomPanel.show(RoomPanelData(title: title, color: _book, pages: [text], book: true));

void _ferroTalk() {
  final first = !Adventure.flag('met:ferro');
  Adventure.setFlag('met:ferro');
  if (Ferro.answeredToday) {
    RoomPanel.show(RoomPanelData(
        title: 'Old Ferro', color: _ferro, pages: [Ferro.rumourToday ?? RoomText.ferroWrong]));
    return;
  }
  RoomPanel.show(RoomPanelData(
    title: 'Old Ferro',
    color: _ferro,
    pages: [if (first) RoomText.ferroFirst, Ferro.riddle.question],
    actions: [
      for (final c in Ferro.choices)
        RoomAction(c.toUpperCase(), () {
          final rumour = Ferro.answer(c);
          if (rumour != null) {
            SfxManager().playChime();
            GameToast.show('RIGHT ANSWER',
                body: '+${RoomText.ferroRewardGlimmer} glimmer', color: _ferro, compact: true);
          }
          RoomPanel.show(RoomPanelData(
              title: 'Old Ferro', color: _ferro, pages: [rumour ?? RoomText.ferroWrong]));
        }),
    ],
  ));
}

void _daoMenu(String greeting) {
  final free = Meals.freeBowlToday;
  final pages = <String>[
    greeting,
    [for (final m in Meals.menu) '${m.name}: ${m.effect}'].join('\n'),
  ];
  final actions = <RoomAction>[
    for (final m in Meals.menu)
      RoomAction(free ? '${m.name.toUpperCase()} · FREE' : '${m.name.toUpperCase()} · ${m.price}',
          () => _order(m), enabled: free || Bonds.glimmer >= m.price),
  ];
  if (DaoErrand.active && DaoErrand.carrying) {
    actions.add(RoomAction('GIVE MOONFLOWER', () {
      if (DaoErrand.deliver()) {
        SfxManager().playChime();
        GameToast.show('ERRAND DONE', body: "Tomorrow's bowl is free", color: _dao, compact: true);
      }
    }));
  } else if (DaoErrand.canAsk || DaoErrand.active) {
    pages.add(RoomText.daoErrand);
    if (DaoErrand.canAsk) {
      actions.add(RoomAction("I'LL BRING ONE", () {
        DaoErrand.accept();
        GameToast.show('ERRAND', body: 'Pick a moonflower in the Woods', color: _dao, compact: true);
      }));
    }
  }
  final active = Meals.byId(Meals.active.value);
  RoomPanel.show(RoomPanelData(
    title: 'Dao',
    color: _dao,
    pages: pages,
    actions: actions,
    footer: [
      'Glimmer ${Bonds.glimmer}',
      if (active != null && Meals.remaining.value > 0) 'Eating: ${active.name} (${Meals.remaining.value.ceil()} s)',
    ].join('  ·  '),
  ));
}

void _order(Meal m) {
  final err = Meals.order(m.id);
  if (err != null) {
    GameToast.show('DAO', body: err, color: _dao, compact: true);
    return;
  }
  SfxManager().playChime();
  GameToast.show(m.name.toUpperCase(), body: m.effect, color: _dao, compact: true);
}

void _stash() {
  RoomPanel.show(RoomPanelData(
    title: "Asha's chest",
    color: _asha,
    pages: const [RoomText.ashaNote],
    footer: 'In the chest: ${Stash.stored} glimmer  ·  Carrying: ${Bonds.glimmer} glimmer',
    actions: [
      RoomAction('DEPOSIT ALL', () {
        final n = Stash.depositAll();
        if (n > 0) GameToast.show('CHEST', body: 'Stored $n glimmer', color: _asha, compact: true);
      }, enabled: Bonds.glimmer > 0),
      RoomAction('TAKE ALL', () {
        final n = Stash.withdrawAll();
        if (n > 0) GameToast.show('CHEST', body: 'Took $n glimmer', color: _asha, compact: true);
      }, enabled: Stash.stored > 0),
    ],
  ));
}

void _wallMap() {
  const names = {
    'woods': 'Whispering Woods',
    'city': 'The City',
    'town': 'Lantern Town',
    'ruins': 'The Ruins',
    'core': "Gaia's Core",
  };
  final walked = [
    for (final e in names.entries) '${GameState.hasVisitedRegion(e.key) ? '■' : '□'} ${e.value}',
  ];
  RoomPanel.show(RoomPanelData(
    title: "Asha's map",
    color: _asha,
    pages: [RoomText.wallMap],
    footer: walked.join('   '),
  ));
}
