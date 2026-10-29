# ASBuilder

A build planner and in-run tracker addon for **Azeroth Survivors** (WoW 1.12.1 client, benilla).

Plan a build for any class before the run, then let a small window tell you what to take next while you play.

## Features

- **Planner**: pick spells, rings, trinkets and amulets for your class and put them in priority order. Spells get a target rank; jewelry gets a target value (for example "30% cooldown reduction").
- **Banish list**: mark spells to banish when their card shows up.
- **Alternatives**: rings and trinkets take 2 main picks plus 2 alternatives, the amulet 1 main plus 3. Wearing an alternative fills the slot just as well. Every amulet shows its base stats, and legendary amulets show what they do to their spell.
- **Example builds**: every class comes with a working example build. Each is added once; updates never touch your own builds or the examples you changed or deleted.
- **Talent screenshot link**: addons can't read talent data, so each build has a box for a screenshot link (imgur, prnt.sc, Discord). Click it, press Ctrl+C and open it in your browser.
- **Stages**: Early, Mid, End and Endless by default (renamable). The tracker moves to the next stage once you hit every target. It warns you if a later stage drops something you already took.
- **Tracker**: the next spell and jewelry to take or upgrade. The Spells panel shows your build's spells (faded until taken, green dot once taken), off-build spells you took (purple dot) and spells to banish, with a slot counter (3/6). The Jewelry panel shows what each worn piece gives right now. A priority strip lists your build's spells in order.
- **Card screen** (game 0.126.0+): your build's spells, jewelry and a spell priority bar show above the level-up, lair and cache cards. Drag and resize each box, and switch each one on or off in the planner's top bar.
- **Share builds**: export a build as a short code (`ASB2:...`) and import a friend's.
- **Transfer current build**: turn what you have mid-run into a new build.
- Works in every language the game ships.

## Install

1. Download `ASBuilder-vX.Y.Z.zip` from [Releases](../../releases).
2. Put the `ASBuilder` folder into `benilla-config/AddOns/`.
3. Restart the game.

Type `/asb` or click the book button on the tracker to open the planner. See `README.txt` for all commands and details.

## After a game update

New spells and jewelry come from the game itself: `tools/extract.py` (dev only, not in the release zip) reads `AzerothSurvivors.exe` and rewrites `Data.lua` and `Names.lua`. Amulet stats live in `Stats.lua`, which it never overwrites; it names any new amulet that `Stats.lua` doesn't cover yet.

## Author

Cadoky

Azeroth Survivors is a fan game by Aethus. This addon is not affiliated with Blizzard Entertainment.
