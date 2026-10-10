/// Lines for the enterable interiors (#31), verbatim from GameConcept's
/// interiors-text.md (Oct 10, 2026). Edit there first, then copy here.
class RoomText {
  RoomText._();

  // --- Tea house: the inn at Lantern Gate ---------------------------------
  static const wenFirst = 'Sit, Kaela. The road can wait the length of one cup.';
  static const wenRest = "Sleep here and the city's noise goes soft. You'll wake well rested.";
  static const wenLater = 'Your usual cup is still warm.';
  static const ferroFirst =
      "A riddle for a listener. Answer it and I'll tell you something the board doesn't know.";

  /// One per in-game day, in order. Add more here as GameConcept writes them.
  static const ferroRumours = [
    'They say the greenhouse hums at night, like something inside is still singing.',
  ];
  static const windowSeat = 'Lantern Road runs east from here. The lamps were lit by hand, every one.';

  // --- Noodle shop on Market Row ------------------------------------------
  static const daoFirst = 'Sit! Eat! You look like a forest walked on you.';
  static const daoErrand =
      "My moonflower ran out. Bring me one from the Woods and tomorrow's bowl is free.";
  static const daoLater = 'Back again! Good. Sit.';
  static const counterTin = 'A tin of chopsticks. One pair is carved with a vine fox.';

  // --- Archive library ------------------------------------------------------
  static const archivist = "Few walk in here who aren't already dust. Read gently.";
  static const bookChoosingTitle = 'The Choosing';
  static const bookChoosing = 'The Aetherians did not lose a war. They declined one.';
  static const bookLatticeTitle = 'Lattice Keys';
  static const bookLattice = 'A keystone fits only a gate that remembers it.';
  static const bookFieldNotesTitle = 'Field Notes, author unknown';
  static const bookFieldNotes =
      'A fragment was carried south, toward the alleys where the drones now hum.';
  static const readingDesk = 'A lamp still lit. Someone was here not long ago.';

  // --- Ranger cabin ---------------------------------------------------------
  static const ashaNote = 'Kaela, use what you need. The chest is yours now. A.';
  static String journalCount(int n, int total) => '$n of $total creatures befriended';
  static const wallMap = "Asha has pinned every trail she's walked. A few are still blank.";
  static const stove =
      'A low fire, still crackling. Asha must have stoked it before she left. It smells of pine.';

  // --- Still-locked doors ---------------------------------------------------
  static const lockedDoors = {
    'apartment_block': "Buzzers, none answered. Someone's left a light on, three floors up.",
    'greenhouse': 'Fogged glass. Something green presses against it from inside.',
    'ruin_shrine': 'The doorway is carved shut. A glyph above it waits to be read.',
  };
}
