# WeaponSwap

**Dagger for the opener, sword for the rest of the fight.** A rogue addon for
[WoW Forever](https://www.wowhead.com/forever) that swaps your main hand between a
dagger and a sword without typing item names or juggling bags.

On Forever, Backstab and Ambush need a dagger in the main hand, while Sinister Strike
hits harder with a slow sword. WeaponSwap keeps both ready and swaps them for you:
the dagger goes in when you stealth, the sword comes back right after the opener, and
one key press swaps you mid-fight.

```
 Stealth ──► dagger in ── Ambush ──► sword back ── Sinister Strike, Slice and Dice ...
              (auto)                  (auto)
```

## Install

1. Download this repository (or a release zip).
2. Copy the `WeaponSwap` folder to
   `World of Warcraft\_forever_\Interface\AddOns\WeaponSwap`.
3. Log in, or `/reload` if you are already in game.

## Setup (30 seconds)

1. Type `/ws` to open the window.
2. Drag your **dagger** onto the top slot and your **sword** onto the bottom one.
3. Click **Create / update**. Five character macros are created.
4. Drag the macro icons next to the button onto your action bar.
5. Tick the automatic swaps you want.

```
┌──────────── WeaponSwap ────────────┐
│ [D]  Dagger (Backstab / Ambush)    │
│       Edward's Knife               │
│ [S]  Sword                         │
│       Vileblood Scimitar           │
│ [Create / update] [B][A][S][SS][SD]│
│ ☑ Dagger when entering stealth     │
│ ☑ Sword when leaving stealth       │
│ ☑ Sword when combat ends           │
│ ☑ Sword after Backstab / Ambush    │
│ ☐ Debug log (/reload saves it)     │
└────────────────────────────────────┘
```

In the window, left-click a slot to equip that weapon, right-click to clear it.

## The macros

| Macro | What one press does |
|---|---|
| **WS Backstab** | puts the dagger in if it is not there, then Backstab |
| **WS Ambush** | puts the dagger in if it is not there, then Ambush |
| **WS Sinister** | Sinister Strike, then puts the sword back if the dagger is in |
| **WS Slice** | Slice and Dice, then puts the sword back if the dagger is in |
| **WS Sword** | just puts the sword back |

They work **in combat**. Sinister Strike and Slice and Dice do not need a sword, so
those macros hit first and swap after, in the same press. Backstab and Ambush need the
dagger first: if the sword is in, the first press swaps and the next one hits (the swap
starts the global cooldown).

## Automatic swaps

| Option | When |
|---|---|
| Dagger when entering stealth | you stealth |
| Sword when leaving stealth | stealth drops without a fight |
| Sword after Backstab / Ambush | the opener lands from stealth |
| Sword when combat ends | the fight is over |

These run **out of combat only**: the game does not let an addon swap gear in combat
on its own. In practice "Sword after Backstab / Ambush" still fires after an opener
from stealth, because the game reports the cast a moment before it flags combat. If a
mob pulls you first, it cannot fire. Press **WS Sinister** or **WS Slice**, or let
"Sword when combat ends" bring the sword back.

## How it works

WoW Forever blocks addon code from equipping items in combat, even from a key press.
Only the game's own macro commands can. So the macros do not call the addon in
combat. They hold a plain `/equipslot` line:

```
#showtooltip Sinister Strike
/cast Sinister Strike
/equipslot [equipped:Daggers] 16 0 7
```

- `16` is the main hand. `0 7` is the bag slot of the weapon that is not in your hand.
  When one weapon goes in, the other drops into the slot it left, so that slot stays
  the same between swaps.
- `[equipped:Daggers]` keeps the macro from swapping when it does not need to.
- A bag slot points at one exact item. That matters with two copies of the same sword
  (main hand and off hand): equipping by name could grab the off-hand one.
- When your bags change, WeaponSwap rewrites the bag slot in the macros out of combat.

## Commands

| Command | |
|---|---|
| `/ws` | open or close the window (case does not matter: `/WS` works) |
| `/ws dagger`, `/ws sword` | equip one, out of combat |
| `/ws debug` | toggle the debug log |
| `/ws help` | list the commands |

## Debug log

Tick **Debug log** (or `/ws debug`) to record what happens: combat and stealth
changes, every swap and where the item came from, casts, failed casts and the red
error text. Nothing goes to chat. After `/reload` the log is in
`WTF\Account\<account>\<realm>\<character>\SavedVariables\WeaponSwap.lua` (last 500
lines). Paste it in an issue when something misbehaves.

## Compatibility

- Built and tested on **WoW Forever** (interface 16001), 2026-11.
- Assumes one dagger and one or two swords. `[equipped:Daggers]` tells the two
  modes apart.
- Other Classic clients may work with a `.toc` interface bump, but the combat rules
  above were only checked on Forever.

## License

MIT. See [LICENSE](LICENSE).
