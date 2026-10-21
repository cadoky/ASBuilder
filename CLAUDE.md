# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

ASBuilder is a WoW addon for **Azeroth Survivors**, a fan game running on the WoW 1.12.1 client (benilla). It is a build planner (`/asb`) plus an in-run tracker. Files sit at the repo root; the repo root is the addon folder.

## No build, no tests

There is no build step, linter or test suite, and no Lua interpreter is assumed. Changes can only be verified in the game (`/reload` for Lua changes; new texture/font files need a full game restart). Say when a change is untested in game.

## Platform constraints

- Lua 5.0 / WoW 1.12 API: no `#`, no `string.match`/`gmatch` (use `string.find`/`gfind`), no `select`, no `_G`; `this`/`arg1` globals in handlers; at most 32 upvalues per function. Blizzard templates need named frames, so UI is built from a tinted `WHITE8X8` texture (see `Widgets.lua`). Keep the flat dark look.
- The game exposes run state through globals: `AZS_SPELLS`, `AZS_RUN`, `AZS_STATS`, `AZS_GetPhase()` (`ready`/`playing`/`choosing`/`paused`/`dead`/`victory`). The level-up card screen's contents are NOT readable by addons; do not build features on card data.

## Architecture

Load order is set in `ASBuilder.toc` and matters: each file adds to the shared `ASBuilder` table (`local AB = ASBuilder`).

- `Data.lua`, `Names.lua`: **generated** by `tools/extract.py` from `AzerothSurvivors.exe`. Never hand-edit. `Data.lua` = classes, spells, rings, trinkets, amulets, legendary amulets (`ASBuilder_Data`); `Names.lua` = jewelry names in 14 languages mapped to English, so worn items are recognised in any client language.
- `Stats.lua`: hand-maintained amulet base stats (the exe keeps them in code, the extractor cannot read them).
- `Defaults.lua`: ready-made example builds, added to a player's DB once by `key` and never overwritten.
- `Core.lua`: SavedVariables (`ASBuilderDB`), reading the run (spells, worn jewelry from tooltips), computing what a build still needs, `ASB2:` export/import (still imports `ASB1:`), events and slash commands. Slot limits live in `AB.MAX`/`AB.MAIN`/`AB.ALTS`/`AB.MAX_BAN`.
- `Widgets.lua` (`AB.W`): shared flat widgets.
- `Planner.lua`: build editor window (builds list, icon palette, per-stage priority lists, targets, notes).
- `Tracker.lua`: in-run windows (next pick, spells, jewelry panels, choice boxes while phase is `choosing`).

A build has stages (`variants`), each with its own picks (`{ t = kind, k = key, r = target, ban = bool }`), notes and recommended stats.

## Regenerating game data

After a game update: `python3 -I tools/extract.py <path\to\AzerothSurvivors.exe>` (standard library only, read-only on the exe). It rewrites `Data.lua` and `Names.lua` and names any new amulet missing from `Stats.lua`. Game updates often break its string-table parsing (e.g. CRLF changes); fix the parser rather than editing the output.

## Releasing

`.github/workflows/release.yml` runs on a push to `main` that changes `*.toc`: it reads `## Version:`, and if tag `vX.Y.Z` does not exist, zips the repo as `ASBuilder-vX.Y.Z.zip` (excluding `.git`, `.github`, `RELEASE_NOTES.md`) and creates a release with `RELEASE_NOTES.md` as the body. So a release = bump the `.toc` version + update `RELEASE_NOTES.md` + push to `main`; only do this when the owner explicitly asks. `README.md` (GitHub) and `README.txt` (shipped in the zip) are user docs; keep both in sync with feature changes.
