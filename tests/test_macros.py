# /// script
# requires-python = ">=3.10"
# dependencies = ["lupa"]
# ///
"""Loads WeaponSwap.lua against a stubbed WoW API and checks the macro bodies and the
out-of-combat swaps for each weapon setup. Run: uv run tests/test_macros.py [-v]

It checks what the addon writes, not what the game does with it: client behaviour
(does /equipslot swap hands in combat?) still needs a test in game.
"""
import pathlib
import sys

ADDON = pathlib.Path(__file__).resolve().parent.parent / "WeaponSwap.lua"
VERBOSE = "-v" in sys.argv

try:
    from lupa import lua51 as L
except ImportError:
    import lupa as L

DAGGER, SWORD = 100, 200
STUBS = r"""
format, tinsert, tremove, strmatch = string.format, table.insert, table.remove, string.match
date = os.date
function GetTime() return 0 end
NUM_BAG_SLOTS = 4
state = { bags = {}, inv = {}, combat = false, stealth = false, macros = {}, picked = {}, names = {} }
function InCombatLockdown() return state.combat end
function IsStealthed() return state.stealth end
function CursorHasItem() return false end
function ClearCursor() end
function GetInventoryItemLink() return nil end
function GetInventoryItemID(_, slot) return state.inv[slot] end
function PickupInventoryItem(slot) tinsert(state.picked, "inv " .. slot) end
function UnitIsDeadOrGhost() return false end
function GetCursorInfo() end
C_Container = {
  GetContainerNumSlots = function(bag) return 16 end,
  GetContainerItemID = function(bag, i) return state.bags[bag .. " " .. i] end,
  PickupContainerItem = function(bag, i) tinsert(state.picked, "bag " .. bag .. " " .. i) end,
  GetContainerItemLink = function() end,
  UseContainerItem = function() end,
}
C_Item = {
  GetItemInfo = function(id) return state.names[id] end,
  GetItemIconByID = function(id) return "icon" .. id end,
  EquipItemByName = function() end,
}
C_Spell = { GetSpellInfo = function(id) return { name = "spell" .. id } end }
function GetMacroIndexByName(name) return 1 end
function GetMacroInfo(i) return nil, nil, nil end
edited = {}
function EditMacro(i, name, icon, body) edited[name] = body end
function CreateMacro() return 1 end
function hooksecurefunc() end
SlashCmdList = {}
UISpecialFrames = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) end }
handlers = {}
local function stubFrame()
  local f = {}
  setmetatable(f, { __index = function(t, k)
    if k == "SetScript" then
      return function(self, what, fn) if what == "OnEvent" then tinsert(handlers, fn) end end
    end
    return function() return stubFrame() end
  end })
  return f
end
function CreateFrame() return stubFrame() end
"""

lua = L.LuaRuntime(unpack_returned_tuples=True)
lua.execute(STUBS)
lua.execute(ADDON.read_text(encoding="utf-8"))
g = lua.globals()
on_event = g.handlers[2]  # 1 = energy glow, 2 = main events, 3 = debug
on_event(None, "ADDON_LOADED", "WeaponSwap")
g.WeaponSwapDB.dagger, g.WeaponSwapDB.sword = DAGGER, SWORD


def run(title, bags, inv, names=True, opts=()):
    st = g.state
    st.bags = lua.table_from(bags)
    st.inv = lua.table_from(inv)
    st.names = lua.table_from({DAGGER: "Edward's Knife", SWORD: "Vileblood Scimitar of the 100% Monkey"} if names else {})
    for k in ("pickPocket", "startAttack"):
        g.WeaponSwapDB[k] = True if k in opts else None
    g.edited = lua.table()
    on_event(None, "BAG_UPDATE_DELAYED")
    if VERBOSE:
        print("=" * 8, title)
    for name in sorted(g.edited):
        body = g.edited[name]
        if VERBOSE:
            print(f"-- {name} ({len(body)} chars)")
            print(body)
        assert len(body) <= 255, name
        assert "%s" not in body, name
    return {n: g.edited[n] for n in g.edited}


bag_sword = run("bag mode: sword MH, dagger in bag 0 7", {"0 7": DAGGER}, {16: SWORD, 17: SWORD})
assert all("16 0 7" in b for b in bag_sword.values())
assert "[noequipped:Daggers] 16 0 7" in bag_sword["WS Ambush"]

two = run("bag mode: dagger MH, sword OH, spare sword in bag 1 3", {"1 3": SWORD}, {16: DAGGER, 17: SWORD})
assert all("16 1 3" in b for b in two.values())

hand = run("hand mode: sword MH, dagger OH", {}, {16: SWORD, 17: DAGGER}, opts=("pickPocket", "startAttack"))
assert hand["WS Ambush"] == "#showtooltip Ambush\n/equipslot 16 Edward's Knife\n/cast [nocombat] Pick Pocket\n/cast Ambush"
assert hand["WS Sword"] == "/equipslot 16 Vileblood Scimitar of the 100% Monkey"
assert hand["WS Sinister"].endswith("/equipslot 16 Vileblood Scimitar of the 100% Monkey")
assert "/startattack\n/cast Sinister Strike" in hand["WS Sinister"]
assert "/equipslot 16 Edward's Knife\n/startattack [nostealth]\n/cast Ambush\n/cast Backstab" in hand["WS Backstab"]
assert hand["WS Ghostly"] == "#showtooltip Ghostly Strike\n/startattack\n/cast Ghostly Strike\n/equipslot 16 Vileblood Scimitar of the 100% Monkey"
assert "Ambush" not in bag_sword["WS Ghostly"] and "[equipped:Daggers] 16 0 7" in bag_sword["WS Ghostly"]
assert "/startattack" not in hand["WS Slice"]
assert "/startattack" not in bag_sword["WS Backstab"]
assert not any("equipped:Daggers" in b for b in hand.values())

hand2 = run("hand mode after a swap: dagger MH, sword OH (same bodies)", {}, {16: DAGGER, 17: SWORD}, opts=("pickPocket", "startAttack"))
assert hand2 == hand

noname = run("hand mode, names not loaded: /ws fallback", {}, {16: SWORD, 17: DAGGER}, names=False)
assert "/ws dagger" in noname["WS Ambush"] and "/ws sword" in noname["WS Sword"]
g.state.names = lua.table_from({DAGGER: "Edward's Knife", SWORD: "Vileblood Scimitar of the 100% Monkey"})
g.edited = lua.table()
on_event(None, "GET_ITEM_INFO_RECEIVED", 999)
assert len(list(g.edited)) == 0, "unrelated item must not rewrite"
on_event(None, "GET_ITEM_INFO_RECEIVED", DAGGER)
assert g.edited["WS Ambush"].startswith("#showtooltip Ambush\n/equipslot 16 Edward's Knife")


none = run("nothing in bags, dagger not equipped: /ws fallback", {}, {16: SWORD})
assert "/ws dagger" in none["WS Ambush"]

# Out-of-combat automatic swap: stealth with the dagger in the off hand.
g.WeaponSwapDB.stealthDagger = True
g.state.inv = lua.table_from({16: SWORD, 17: DAGGER})
g.state.bags = lua.table()
g.state.picked = lua.table()
g.state.stealth = True
on_event(None, "UPDATE_STEALTH")
picked = list(g.state.picked.values())

assert picked == ["inv 17", "inv 16"]

# Same, in combat: nothing may be touched.
g.state.picked = lua.table()
g.state.combat = True
on_event(None, "UPDATE_STEALTH")
assert len(list(g.state.picked.values())) == 0
g.state.combat = False

# Two identical swords, dagger MH, spare in the bag: the bag copy still wins.
g.state.stealth = False
g.WeaponSwapDB.swordLeaveStealth = True
g.state.inv = lua.table_from({16: DAGGER, 17: SWORD})
g.state.bags = lua.table_from({"1 3": SWORD})
g.state.picked = lua.table()
on_event(None, "UPDATE_STEALTH")
picked = list(g.state.picked.values())

assert picked == ["bag 1 3", "inv 16"]
print("ALL OK")
