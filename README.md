# WeaponSwap

A rogue addon for [WoW Forever](https://www.wowhead.com/forever) that keeps a dagger
in your main hand for the opener and a sword for the rest of the fight. You pick the
two weapons once; after that, macros and automatic swaps move them in and out.

On Forever, Backstab and Ambush need a dagger in the main hand. WeaponSwap puts the
dagger in when you stealth and brings the sword back right after the opener. In the
middle of a fight, one key press swaps for you.

```
 Stealth ──► dagger in ── Ambush ──► sword back ── Sinister Strike, Slice and Dice ...
              (auto)                  (auto)
```

## Install

1. Download this repository (or a release zip).
2. Copy the `WeaponSwap` folder to
   `World of Warcraft\_forever_\Interface\AddOns\WeaponSwap`.
3. Log in, or `/reload` if you are already in game.

## Setup

1. Type `/ws` to open the window.
2. Drag your dagger onto the top slot and your sword onto the bottom one.
3. Click Create / update. This creates five character macros.
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

Left-click a slot to equip that weapon, right-click to clear it.

## Macros

| Macro | One press |
|---|---|
| WS Backstab | puts the dagger in if it is not there, then Backstab |
| WS Ambush | puts the dagger in if it is not there, then Ambush |
| WS Sinister | Sinister Strike, then puts the sword back if the dagger is in |
| WS Slice | Slice and Dice, then puts the sword back if the dagger is in |
| WS Sword | puts the sword back |

All five work in combat. Sinister Strike and Slice and Dice do not need a sword, so
those macros hit first and swap after, on the same press. Backstab and Ambush need the
dagger first. If the sword is in, the first press swaps and starts the global
cooldown, and the next press hits.

## Automatic swaps

| Option | Swaps when |
|---|---|
| Dagger when entering stealth | you stealth |
| Sword when leaving stealth | stealth drops without a fight |
| Sword after Backstab / Ambush | the opener lands from stealth |
| Sword when combat ends | the fight is over |

These only run out of combat, because the game does not let an addon swap gear in
combat on its own. "Sword after Backstab / Ambush" still fires after an opener from
stealth: the game reports the cast a moment before it flags you as in combat. If a mob
pulls you first, it cannot fire. Press WS Sinister or WS Slice then, or let "Sword when
combat ends" bring the sword back.

## How it works

WoW Forever blocks addon code from equipping items in combat, even from a key press.
The game's own macro commands are allowed, so the macros never call the addon. Each
one holds a plain `/equipslot` line:

```
#showtooltip Sinister Strike
/cast Sinister Strike
/equipslot [equipped:Daggers] 16 0 7
```

`16` is the main hand, and `0 7` is the bag slot of the weapon that is not in your
hand. When one weapon goes in, the other drops into the slot it left, so the slot
stays the same from swap to swap. `[equipped:Daggers]` stops the macro from swapping
when you already hold the right weapon.

A bag slot points at one exact item. With two copies of the same sword in main hand
and off hand, equipping by name could grab the off-hand one; the bag slot can't. When
your bags change, WeaponSwap rewrites the slot in the macros as soon as you are out of
combat.

## Commands

| Command | |
|---|---|
| `/ws` | open or close the window (`/WS` works too) |
| `/ws dagger`, `/ws sword` | equip one, out of combat |
| `/ws debug` | turn the debug log on or off |
| `/ws help` | list the commands |

## Debug log

Tick Debug log (or type `/ws debug`) and WeaponSwap records combat and stealth
changes, each swap and the bag slot it came from, casts, failed casts and the red
error text. It writes nothing to chat. After a `/reload`, the last 500 lines are in
`WTF\Account\<account>\<realm>\<character>\SavedVariables\WeaponSwap.lua`. Paste them
in an issue when something goes wrong.

## Compatibility

Built and tested on WoW Forever (interface 16001) in November 2026. It assumes one
dagger and one or two swords, since `[equipped:Daggers]` is how it tells the two modes
apart. Other Classic clients may work after bumping the interface number in the
`.toc`, but the combat rules above were only checked on Forever.

## License

MIT. See [LICENSE](LICENSE).
