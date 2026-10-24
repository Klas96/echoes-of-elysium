import 'package:flutter/material.dart';

import '../audio/sfx_manager.dart';
import '../components/custom_player.dart';
import '../creatures/bonds.dart';
import '../creatures/day_cycle.dart';
import '../creatures/interaction.dart';
import '../creatures/journal_ui.dart';
import '../creatures/region_gates.dart';
import '../game/adventure.dart';
import '../game/game_state.dart';
import '../game/memories.dart';
import '../game/progression.dart';
import '../game/save_service.dart';
import '../game/story_beats.dart';
import '../game/well_rested.dart';
import '../ui/cutscenes.dart';
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
      'lore' || 'note' => 'READ',
      'clue' =>
        (s.id == 'pond_fragment' || s.id == 'merge_draft') ? 'TAKE' : 'READ',
      'stash' => 'OPEN CHEST',
      'journal' => 'MENU',
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
    case 'archive_library/merge_draft':
      _takeMergeDraft();
    case 'archive_library/reading_lamp':
      _flavour(RoomText.readingDesk);
    // --- ranger cabin ---
    case 'ranger_cabin/asha_note':
      RoomPanel.show(const RoomPanelData(title: 'A note from Asha', color: _asha, pages: [RoomText.ashaNote]));
    case 'ranger_cabin/stash_chest':
      _stash();
    case 'ranger_cabin/desk_journal':
      GameToast.show('MENU',
          body: RoomText.journalCount(Bonds.befriendedCount, Bonds.total), color: _asha, compact: true);
      Journal.show();
    case 'ranger_cabin/wall_map':
      _wallMap();
    case 'ranger_cabin/stove':
      _flavour(RoomText.stove);
    case 'pond_grotto/pond_fragment':
      _pondFragment();
    case 'pond_grotto/drip_wall':
      _flavour(RoomText.grottoDrip);
    case 'pond_grotto/pool_edge':
      _flavour(RoomText.grottoPool);
    default:
      _flavour(_flavourFromNote(s.note));
  }
}

void _pondFragment() {
  if (SaveService.data.collected.contains(woodsPondFragment)) {
    RoomPanel.show(const RoomPanelData(
        title: 'Empty alcove', color: _plain, pages: [RoomText.grottoFragmentGone]));
    return;
  }
  SaveService.data.collected.add(woodsPondFragment);
  GameState.onFragmentCollected();
  Memories.onFragmentPicked();
  SfxManager().playChime();
  RoomPanel.show(const RoomPanelData(
      title: 'Memory fragment', color: Color(0xFFE8D0FF), pages: [RoomText.grottoFragmentTake]));
}

/// First Memory Draft on the archive desk — fires Asha's archive_ash beat.
void _takeMergeDraft() {
  if (Adventure.hasClue('archive_first_memory')) {
    RoomPanel.show(const RoomPanelData(
        title: 'Empty desk', color: _plain, pages: [RoomText.mergeDraftGone]));
    return;
  }
  Adventure.discover('archive_first_memory');
  Adventure.discover('asha_on_archive');
  Adventure.setFlag('archive_opened');
  Bonds.addGlimmer(12);
  SfxManager().playChime();
  GameToast.show('DRAFT TAKEN', body: '+12 glimmer · examined', color: _archivist, compact: true);
  RoomPanel.show(const RoomPanelData(
      title: 'First Memory Draft', color: _archivist, pages: [RoomText.mergeDraftTake]));
  // Asha on comms (archive_ash) — stacks over the room once the frame settles.
  if (!Cutscenes.seen(Cutscenes.archiveAsh)) {
    StoryBeats.onArchiveOpened();
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
  final gearIn = Stash.gear;
  final spare = Stash.depositable;
  final gearLine = gearIn.isEmpty
      ? 'no gear'
      : '${gearIn.length} gear · ${[
          for (final id in gearIn) Progression.catalog[id]?.name ?? id
        ].join(', ')}';
  RoomPanel.show(RoomPanelData(
    title: "Asha's chest",
    color: _asha,
    pages: const [RoomText.ashaNote],
    footer:
        'Chest: ${Stash.stored}◆ · $gearLine  ·  You: ${Bonds.glimmer}◆ · ${spare.length} spare',
    actions: [
      RoomAction('DEPOSIT GLIMMER', () {
        final n = Stash.depositAll();
        if (n > 0) {
          GameToast.show('CHEST', body: 'Stored $n glimmer', color: _asha, compact: true);
        }
        _stash();
      }, enabled: Bonds.glimmer > 0),
      RoomAction('TAKE GLIMMER', () {
        final n = Stash.withdrawAll();
        if (n > 0) {
          GameToast.show('CHEST', body: 'Took $n glimmer', color: _asha, compact: true);
        }
        _stash();
      }, enabled: Stash.stored > 0),
      RoomAction('STORE GEAR (−${Stash.gearDepositFee}◆)', _stashDepositGear,
          enabled: spare.isNotEmpty && Bonds.glimmer >= Stash.gearDepositFee),
      RoomAction('TAKE GEAR', _stashWithdrawGear, enabled: gearIn.isNotEmpty),
    ],
  ));
}

void _stashDepositGear() {
  final spare = Stash.depositable;
  if (spare.isEmpty) {
    _stash();
    return;
  }
  RoomPanel.show(RoomPanelData(
    title: 'Store spare gear',
    color: _asha,
    pages: [
      'Each piece costs ${Stash.gearDepositFee} glimmer to bank. Equipped kit stays on you.',
    ],
    footer: 'You have ${Bonds.glimmer} glimmer',
    actions: [
      for (final id in spare)
        RoomAction(
          '${Progression.catalog[id]?.name ?? id}  −${Stash.gearDepositFee}◆',
          () {
            if (Stash.depositGear(id)) {
              GameToast.show('CHEST',
                  body: 'Stored ${Progression.catalog[id]?.name ?? id}',
                  color: _asha,
                  compact: true);
            } else {
              GameToast.show('CHEST',
                  body: 'Need ${Stash.gearDepositFee} glimmer',
                  color: _asha,
                  compact: true);
            }
            _stash();
          },
          enabled: Bonds.glimmer >= Stash.gearDepositFee,
        ),
      RoomAction('BACK', _stash),
    ],
  ));
}

void _stashWithdrawGear() {
  final ids = Stash.gear;
  if (ids.isEmpty) {
    _stash();
    return;
  }
  RoomPanel.show(RoomPanelData(
    title: 'Take gear',
    color: _asha,
    pages: const ['Pull kit back onto the road. Free.'],
    footer: 'In the chest: ${ids.length}',
    actions: [
      for (final id in ids)
        RoomAction(Progression.catalog[id]?.name ?? id, () {
          if (Stash.withdrawGear(id)) {
            GameToast.show('CHEST',
                body: 'Took ${Progression.catalog[id]?.name ?? id}',
                color: _asha,
                compact: true);
          }
          _stash();
        }),
      RoomAction('BACK', _stash),
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
