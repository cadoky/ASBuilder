# ASBuilder

A build planner and in-run tracker addon for **Azeroth Survivors** (WoW 1.12.1 client, benilla).

Plan a build for any class before the run, then let a small window tell you what to take next while you play.

## Features

- **Planner**: pick spells, rings, trinkets and amulets for your class and put them in priority order. Spells get a target rank; jewelry gets a target value (for example "30% cooldown reduction").
- **Banish list**: mark spells to banish when their card shows up.
- **Amulets**: one main amulet plus two backups. Every amulet shows its base stats, and legendary amulets show what they do to their spell.
- **Stages**: Early, Mid, End and Endless by default (renamable). The tracker moves to the next stage once you hit every target. It warns you if a later stage drops something you already took.
- **Tracker**: the next spell and jewelry to take or upgrade. The Spells panel shows your build's spells (faded until taken, green dot once taken), off-build spells you took (purple dot) and spells to banish, with a slot counter (3/6). The Jewelry panel shows what each worn piece gives right now.
- **Share builds**: export a build as a short code (`ASB2:...`) and import a friend's.
- **Transfer current build**: turn what you have mid-run into a new build.
- Works in every language the game ships.

## Install

1. Download `ASBuilder-vX.Y.Z.zip` from [Releases](../../releases).
2. Put the `ASBuilder` folder into `benilla-config/AddOns/`.
3. Restart the game.

Type `/asb` or click the minimap button to open the planner. See `README.txt` for all commands and details.

## After a game update

New spells and jewelry come from the game itself: double-click `tools/Update-Data.cmd`, then `/reload` in the game. It only reads `AzerothSurvivors.exe`; it changes nothing there. Amulet stats live in `Stats.lua`, which the tool never overwrites. The tool names any new amulet that `Stats.lua` doesn't cover yet.

## Author

Ulaş Çolaker (Cadoky)

Azeroth Survivors is a fan game by Aethus. This addon is not affiliated with Blizzard Entertainment.
