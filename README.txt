ASBuilder 1.1.0 - build planner for Azeroth Survivors
=====================================================

INSTALL
  Windows / Linux : put the ASBuilder folder in benilla-config/AddOns/ next to the game.
  Browser         : Options -> AddOns -> install ASBuilder.zip.
  The addon loads at the next world entry.

COMMANDS
  /asb               open or close the planner (the minimap button does the same)
  /asb tracker       tracker: in runs / always / hidden
  /asb lock          lock or unlock the tracker
  /asb scale 0.9     tracker size
  /asb reset         tracker back to its first place

PLANNER
  - New makes an empty build for your character's class. Name and class are at the top.
  - Stages: every build has four stages, Early Game, Mid Game, End Game and Endless (the
    tabs along the top). Each stage has its own picks, target ranks, banishes and notes.
    Type in the box on the right of the tabs to rename the selected stage. "Copy previous"
    fills a stage with the stage before it, to build on (raise targets, swap pieces).
  - Stage checks: in a run, spells, rings and trinkets stay once taken (only the amulet can
    be swapped) and a banished card never comes back. A stage that leaves out what an
    earlier stage takes, or takes a spell an earlier stage banishes, gets a red "!" on its
    tab and a warning strip under the palette. Fix repairs it in one click.
  - Click the icons in the middle to add or remove spells (6), rings (2), trinkets (2) and
    amulets (1 main + 2 alternatives). The small icon on a legendary amulet shows the spell
    it remakes.
  - The right panel has a tab for each: Spells, Rings, Trinkets, Amulet. Each tab has its
    own priority order (arrows to reorder) and a target per pick:
      spells: a target rank, +/- ("max" = keep upgrading);
      jewelry: a target value, typed: what the piece should give, e.g. 30 for -30% cooldowns
      or 4.5 for +4.5 health per second (empty = keep upgrading). The tracker reads the
      value live from the piece's tooltip.
  - Clear (above the list) empties the open tab in the stage being edited: Spells (with
    the banish marks), Rings, Trinkets or Amulet. Like every change, Save keeps it.
  - Banish: the Banish button on a spell row (or right-click a spell icon) marks the spell
    to banish when its card comes up. It takes no spell slot; 3 at most.
  - Alt: on the Amulet tab, mark up to two amulets as alternatives (blue). Wearing the main
    amulet or any alternative fills the amulet slot.
  - Switching class keeps each class's spells (in every stage): switch back and they return.
  - Changes are a draft until you press Save. Picking another build throws unsaved changes
    away, so a build you did not save goes back to how it was. Unsaved builds show a * in
    the list and "Unsaved changes" above the editor.
  - Use this build: the tracker follows the saved version of it for that class (the same
    as choosing it in the tracker's menu).
  - Transfer Current Build Into Planner: makes a new build of everything you have in the
    run right now (spells and worn jewelry, their current ranks as targets).
  - Export gives a code to share; Import takes one and adds the build exactly as it was
    (every stage with its picks, targets, banishes, alternatives and notes). Since 1.1.0
    codes start with ASB2: and are about a quarter of the old length (a full four-stage
    build without notes is around 350 characters), so they fit in a Discord message; notes
    add about 1.3 characters per letter. Older ASB1 codes, and codes made by 1.0 (into
    Early Game), still import.

TRACKER (while you play) - three separate panels
  BUILD
  - The header is the build menu: click it to choose one of your saved builds of the
    hero's class (or None, or open the planner). Every time you enter the game no build is
    chosen; a /reload keeps the choice.
  - Stage: the stage being followed. It moves on by itself when every pick of the stage
    reaches its target rank (empty stages are skipped), and to the Endless stage when the
    run goes endless. Click it to step to another stage by hand.
  - Spell: / Jewelry: the next spell and the next piece of jewelry to take or upgrade
    (level-up cards are spells, caches offer jewelry). Lit yellow while cards are on screen.
    "Slots full": the build's missing pieces cannot be taken because the slots are full.
  - Book button: planner. Drag the header to move the tracker.
  SPELLS
  - Every spell that matters, in one list. The header counts your spell slots (3/6).
    The build's spells come faded with no mark until you take them; taken: full colour and a
    green dot (R3 = rank 3, R2/5 = rank 2 of target 5). A spell you took that the build does
    not want: violet dot. Spells to banish: faded with no mark until you have the spell,
    then a red dot and BANISH.
  - With all 6 slots full, the build's spells still missing drop below a line: they can no
    longer be taken.
  - The game does not tell addons what you banished: click a banish row once you have banished
    it and it fades and is struck through (click again to undo). Each run starts unmarked.
  JEWELRY
  - Every ring, trinket and amulet you wear with what it gives right now, short
    (+61% DMG, +32% LUCK, -14% CD...), read from its tooltip. A tick marks the build's pieces; dimmed ones are
    not in the build. With a target value: yellow until reached, green once reached
    ("+48% DMG /60").
  - The build's pieces you still miss, in gray. When that kind's slots are full with other
    pieces, they show no "missing".

GAME DATA AND UPDATES
  - Data.lua and Names.lua are generated from the game itself (AzerothSurvivors.exe):
    classes, spells and their icons, rings, trinkets, amulets, legendary amulets, and the
    names of every piece of jewelry in the game's 14 languages.
  - After a game update: double-click tools\Update-Data.cmd, then /reload in the game.
    New spells and jewelry are in the planner. It uses the co-op's Python if it is there,
    else a Python 3 from python.org. It only reads the game; it changes nothing there.
  - If the game's layout changes so much that the extractor cannot find a table, it says
    so instead of writing anything.

NOTES
  - Spell ranks come from the game (AZS_SPELLS). Jewelry values come from each worn piece's
    tooltip, read every second while playing.
  - Jewelry is recognised in every language the game ships.
  - Every amulet shows its base stats in the planner, and every legendary amulet what it
    does to its spell. The game keeps these in its code, not as text, so they live in
    Stats.lua, which the update tool never overwrites. An amulet added by a game update
    shows what it gave once you have worn it; the update tool names any that Stats.lua lacks.
  - Talents are spent between runs and cannot be read, so write your talent plan in Notes.
