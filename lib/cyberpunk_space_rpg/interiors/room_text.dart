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

  /// Rumours, one per right answer, in rotation.
  static const ferroRumours = [
    'They say the greenhouse hums at night, like something inside is still singing.',
    'A deer walks the hidden glade, but only after dark and only for the quiet. Thorns hide the way, unless your nose is sharper than mine.',
    'Someone carved a glyph by the pond shallows. Ranger kids swear it glows when the moths come out.',
    "Mira pays well for clearing the east lot. Those drones nest in threes, so don't go in tired.",
    "The south road out of the City opens for nobody, unless the Archivist says so. And he won't, while that Sentinel stands.",
    "Dao's moonflowers come from the Woods. They only open at night.",
  ];

  /// One riddle a day; the right answer is always listed first here (the
  /// panel shuffles the order).
  static const ferroRiddles = <FerroRiddle>[
    FerroRiddle("I sleep all day in a paper lantern, and at night I'm the lantern.",
        'Glowmoth', ['Hushdeer', 'Street lamp']),
    FerroRiddle('Roads run through me but I never move. Every trail in the Woods comes to meet me.',
        'The crossroads stones', ['The pond', "Asha's camp"]),
    FerroRiddle('The more you take from me, the bigger I get.', 'A hole', ['A debt', 'A shadow']),
    FerroRiddle('I wear a shell for a house and carry a boulder like a feather.',
        'Stone turtle', ['Rust beetle', 'Signal crow']),
    FerroRiddle("I hold a whole people, yet I've never been weighed.",
        'Gaia', ['The Archive', 'The Core Record']),
  ];
  static const ferroWrong = 'Hm. Sleep on it.';
  static const ferroRewardGlimmer = 5;

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

class FerroRiddle {
  final String question, answer;
  final List<String> wrong;
  const FerroRiddle(this.question, this.answer, this.wrong);
}
