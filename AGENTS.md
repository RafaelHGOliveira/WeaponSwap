# WeaponSwap

Rogue addon for WoW Forever, published on CurseForge as "Rogue WeaponSwap". The README
says what it does for players; this file is the workflow.

## After each change

1. `uv run tests/test_macros.py` must print `ALL OK` (`-v` prints every macro body).
   When a change adds a macro, an option or a weapon setup, add its case to the test.
2. Commit it, without asking.
3. Copy `WeaponSwap.lua` and `WeaponSwap.toc` to
   `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\WeaponSwap\`.

The test runs the real `WeaponSwap.lua` against a stubbed API, so it checks what the
addon writes into the macros. What the game does with a macro is only known from a test
in game.

## Release

`pwsh -NoProfile -File release.ps1 <version> <changelog.md>`. It runs the test, bumps the `.toc`,
commits "Release X", tags, pushes, uploads the `git archive` zip to CurseForge and copies
the files into the game. Before running anything heavy, check that the game is not
running (see the global instructions).

## Debug log

Ask Rafael to tick Debug log, reproduce the problem and `/reload`, then read the log
yourself:
`C:\Program Files (x86)\World of Warcraft\_forever_\WTF\Account\*\*\<character>\SavedVariables\WeaponSwap.lua`.

## Client rules

What Forever allows and blocks (equipping in combat, `/use` vs `/equipslot`, a failed
`/cast` stopping the macro, energy as a secret value) is written in the comments at the
top of `WeaponSwap.lua`, above `MACROS` and above the energy glow, each with the date of
the debug log that showed it. Read them before changing a macro.
