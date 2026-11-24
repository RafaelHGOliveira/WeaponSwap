-- WeaponSwap: keeps one dagger and one sword per character and puts either in the
-- main hand (slot 16) on demand. /ws opens a window where the items are dragged in.
-- What Forever allows (tested in game 2026-11-15):
--   * C_Item.EquipItemByName works from a key press (macro or click) and is blocked
--     when an addon calls it from an event.
--   * Picking the item up from the bags and dropping it on the slot works from an
--     event out of combat, and is blocked in combat.
--   * In combat, C_Item.EquipItemByName from addon code is blocked even from a key
--     press (the /ws slash command is addon code). Only Blizzard's secure macro
--     commands can swap in combat.
--   * In combat, "/use <bag> <slot>" on a one-hander puts it in the OFF hand (debug
--     log 2026-11-15: the sword swapped with the off-hand copy, main hand kept the
--     dagger, and each swap started the global cooldown, so Sinister Strike failed).
-- So the macros use "/equipslot 16 <bag> <slot>": the weapon not in the main hand always sits
-- in the same bag slot (equipping swaps it with the one coming out), and a bag slot
-- names one exact copy, which matters with two swords of the same item id. The addon
-- rewrites the macros with that slot out of combat. The automatic swaps run only out
-- of combat: dagger on entering stealth, sword when combat ends or after a stealth opener,
-- and whichever the options want after login, a loading screen or a resurrection.
-- With the dagger in the off hand and no weapon in the bags there is no bag slot, and
-- [equipped:Daggers] is true in either hand, so the macros use "/equipslot 16 <name>":
-- equipping the off-hand weapon in the main hand swaps the two hands. Not yet confirmed
-- in game (1.3.1, 2026-11-20): that it swaps in combat, and that pressing it with the
-- weapon already in the main hand neither errors nor starts the global cooldown.

local MAIN_HAND = 16
local ROLES = { "dagger", "sword" }
local EMPTY_ICON = "Interface\\PaperDoll\\UI-PaperDoll-Slot-MainHand"

local GetItemInfo = GetItemInfo or C_Item.GetItemInfo
local GetItemIcon = GetItemIcon or C_Item.GetItemIconByID

-- Debug log: /ws debug toggles it. Lines go only to WeaponSwapDB.log (cleared at each
-- login or /reload), which
-- the game writes to WTF\...\SavedVariables\WeaponSwap.lua on /reload or logout.
local LOG_MAX = 2000
local function log(fmt, ...)
  if not (WeaponSwapDB and WeaponSwapDB.debug) then return end
  local mh = GetInventoryItemLink("player", 16)
  local line = format("%s %.2f [%s%s%s mh=%s] " .. fmt, date("%H:%M:%S"), GetTime(),
    InCombatLockdown() and "combat" or "nocombat", IsStealthed() and " stealth" or "",
    CursorHasItem() and " CURSOR" or "", mh and mh:match("%[(.-)%]") or "none", ...)
  WeaponSwapDB.log = WeaponSwapDB.log or {}
  tinsert(WeaponSwapDB.log, line)
  while #WeaponSwapDB.log > LOG_MAX do tremove(WeaponSwapDB.log, 1) end
end

-- Picks the item up from the bags and drops it on the slot.
local function cursorEquip(id, slot)
  local Container = C_Container or _G
  for bag = 0, NUM_BAG_SLOTS or 4 do
    for i = 1, Container.GetContainerNumSlots(bag) do
      if Container.GetContainerItemID(bag, i) == id then
        log("cursorEquip %s from bag %d slot %d", tostring(id), bag, i)
        ClearCursor()
        Container.PickupContainerItem(bag, i)
        PickupInventoryItem(slot)
        return true
      end
    end
  end
  -- Dagger in the off hand: dropping it on the main hand swaps the two hands.
  if slot == 16 and GetInventoryItemID("player", 17) == id then
    log("cursorEquip %s from the off hand", tostring(id))
    ClearCursor()
    PickupInventoryItem(17)
    PickupInventoryItem(16)
    return true
  end
end

-- Out of combat, take the item from the bags: with two copies of the same sword
-- (same item id), equipping by id may grab the one already in the off hand.
-- In combat the bag route is blocked, so fall back to equipping by id.
-- Forever has no global EquipItemByName.
local function equipItem(id, slot)
  if not InCombatLockdown() and cursorEquip(id, slot) then return true end
  local equipByName = EquipItemByName or (C_Item and C_Item.EquipItemByName)
  if equipByName then
    equipByName(id, slot)
    return true
  end
  return cursorEquip(id, slot)
end

-- Event-driven swap: only out of combat, and never while you hold something.
local function autoEquip(role)
  local id = WeaponSwapDB[role]
  if not id or InCombatLockdown() or CursorHasItem() then
    log("autoEquip %s skipped", role)
    return
  end
  if GetInventoryItemID("player", MAIN_HAND) ~= id then
    log("autoEquip %s", role)
    cursorEquip(id, MAIN_HAND)
  end
end

local function say(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99WeaponSwap|r " .. msg)
end

local function itemName(id)
  return id and (GetItemInfo(id) or ("item " .. id)) or "not set"
end

local function equip(role)
  local id = WeaponSwapDB[role]
  if not id then
    say(role .. " not set. Type /ws and drag it into the window.")
    return
  end
  if GetInventoryItemID("player", MAIN_HAND) ~= id then
    if not equipItem(id, MAIN_HAND) then
      say(itemName(id) .. " is not in your bags.")
    end
  end
end

-- Macros -----------------------------------------------------------------------

-- "%s" is the bag slot of the weapon not in the main hand. [equipped:Daggers] tells
-- the modes apart: the setup is two swords and one dagger.
-- alt: the body, fallback and /startattack used while option alt.key is ticked.
local MACROS = {
  -- A failed "/cast Ambush" out of stealth stops the macro on Forever (Rafael, 2026-11-18:
  -- "must be in stealth", no Backstab), so the stealth check is a conditional, not a fallthrough.
  -- Its /startattack is [nostealth]: in stealth an auto attack swing would break it before Ambush.
  { name = "WS Backstab", body = "#showtooltip\n/equipslot [noequipped:Daggers] 16 %s\n/cast [stealth] Ambush; Backstab", fallback = "dagger", startAttack = "[nostealth]" },
  { name = "WS Ambush", body = "#showtooltip Ambush\n/equipslot [noequipped:Daggers] 16 %s\n/cast Ambush", fallback = "dagger", pickPocket = true },
  { name = "WS Sword", body = "/equipslot [equipped:Daggers] 16 %s", fallback = "sword", iconFrom = "sword" },
  -- riposte: "/cast Riposte" goes first (asked by a CurseForge user, 2026-11-24). Not confirmed
  -- in game: if a failed /cast stops the macro here too, Riposte not lit up would stop
  -- Sinister Strike and the swap on that press.
  { name = "WS Sinister", body = "#showtooltip Sinister Strike\n/cast Sinister Strike\n/equipslot [equipped:Daggers] 16 %s", fallback = "sword", startAttack = true, riposte = true },
  { name = "WS Hemorrhage", body = "#showtooltip Hemorrhage\n/cast Hemorrhage\n/equipslot [equipped:Daggers] 16 %s", fallback = "sword", startAttack = true },
  { name = "WS Slice", body = "#showtooltip Slice and Dice\n/cast Slice and Dice\n/equipslot [equipped:Daggers] 16 %s", fallback = "sword" },
  -- Out of stealth: Ghostly Strike lets the next Ambush skip Stealth (7 s). Macro conditionals
  -- cannot see the buff, so a cast sequence does it: Ghostly Strike, then Ambush, back to
  -- Ghostly Strike after 7 s without a press. Ghostly Strike comes before the swap, like
  -- WS Sinister, so it and the swap share a press. In stealth it is a plain Ambush, so its
  -- /startattack is [nostealth], as in WS Backstab.
  -- ghostlyAlone: solo the target faces you, and Ambush needs you behind it even with the
  -- Ghostly Strike buff, so it is Ghostly Strike alone and the sword back, like WS Sinister.
  { name = "WS Ghostly", body = "#showtooltip\n/cast [stealth] Ambush\n/castsequence [nostealth] reset=7 Ghostly Strike, Ambush\n/equipslot [noequipped:Daggers] 16 %s", fallback = "dagger", startAttack = "[nostealth]",
    alt = { key = "ghostlyAlone", fallback = "sword", startAttack = true,
      body = "#showtooltip Ghostly Strike\n/cast Ghostly Strike\n/equipslot [equipped:Daggers] 16 %s" } },
}

local function macroIcon(m)
  local id = m.iconFrom and WeaponSwapDB[m.iconFrom]
  return id and GetItemIcon(id) or "INV_MISC_QUESTIONMARK"
end

local function findInBags(id)
  if not id then return end
  local Container = C_Container or _G
  for bag = 0, NUM_BAG_SLOTS or 4 do
    for i = 1, Container.GetContainerNumSlots(bag) do
      if Container.GetContainerItemID(bag, i) == id then return bag .. " " .. i end
    end
  end
end

-- The bag slot holding the dagger (sword mode) or the spare sword (dagger mode).
local function swapSlot()
  return findInBags(WeaponSwapDB.dagger) or findInBags(WeaponSwapDB.sword)
end

-- Dagger and sword both equipped, one per hand, neither in the bags: the names the
-- macros equip by. Nil while an item name has not loaded yet.
local function handNames()
  local d, s = WeaponSwapDB.dagger, WeaponSwapDB.sword
  if not d or not s or findInBags(d) or findInBags(s) then return end
  local mh, oh = GetInventoryItemID("player", 16), GetInventoryItemID("player", 17)
  if not ((mh == d and oh == s) or (mh == s and oh == d)) then return end
  local dagger, sword = GetItemInfo(d), GetItemInfo(s)
  if dagger and sword then return { dagger = dagger, sword = sword } end
end

-- Pick Pocket before Ambush, on one press: it has no global cooldown, and the debug log
-- (2026-11-16) shows "/cast Pick Pocket" + "/cast Sap" landing both on the same press.
-- Ambush still needs you behind the target, Pick Pocket does not. [nocombat] skips it
-- after Vanish, where it fails.
local function macroBody(m, slot, names)
  if m.alt and WeaponSwapDB[m.alt.key] then m = m.alt end
  local body, startAttack = m.body, m.startAttack
  if m.pickPocket and WeaponSwapDB.pickPocket then
    body = body:gsub("\n/cast Ambush", "\n/cast [nocombat] Pick Pocket\n/cast Ambush")
  end
  if m.riposte and WeaponSwapDB.riposte then
    body = body:gsub("\n/cast Sinister Strike", "\n/cast Riposte\n/cast Sinister Strike")
  end
  -- Before the /cast: a failed /cast stops the macro, and auto attack should start anyway.
  if startAttack and WeaponSwapDB.startAttack then
    local cond = startAttack == true and "" or " " .. startAttack
    body = body:gsub("\n/cast ", "\n/startattack" .. cond .. "\n/cast ", 1)
  end
  if slot then return body:format(slot) end
  -- One weapon per hand: no conditional, since equipping the weapon already in the main
  -- hand there changes nothing.
  local name = names and names[m.fallback]
  if name then
    return (body:gsub("/equipslot %b[] 16 %%s", function() return "/equipslot 16 " .. name end))
  end
  -- No weapon in the bags: /ws works out of combat only.
  return (body:gsub("/equipslot %b[] 16 %%s", "/ws " .. m.fallback))
end

-- Rewrites existing macros whose bag slot changed. Out of combat only.
local function updateMacros()
  if not WeaponSwapDB or InCombatLockdown() then return end
  local slot, names = swapSlot(), handNames()
  for _, m in ipairs(MACROS) do
    local index = GetMacroIndexByName(m.name)
    local body = macroBody(m, slot, names)
    if index > 0 and select(3, GetMacroInfo(index)) ~= body then
      EditMacro(index, m.name, macroIcon(m), body)
    end
  end
end

-- Creates the macros as character macros, or rewrites them if they already exist.
local function createMacros()
  if InCombatLockdown() then
    say("cannot create macros in combat.")
    return
  end
  local slot, names = swapSlot(), handNames()
  for _, m in ipairs(MACROS) do
    local index = GetMacroIndexByName(m.name)
    local body = macroBody(m, slot, names)
    if index > 0 then
      EditMacro(index, m.name, macroIcon(m), body)
    elseif not CreateMacro(m.name, macroIcon(m), body, true) then
      say("could not create " .. m.name .. ": character macro slots are full.")
    end
  end
  for _, m in ipairs(MACROS) do
    if m.button then m.button:GetScript("OnShow")(m.button) end
  end
  if names then
    say("dagger and sword both equipped: the macros swap your hands.")
  elseif not slot then
    say("no dagger or spare sword found in your bags, and they are not one in each hand; the macros will only swap out of combat.")
  end
  say("macros ready. Drag them from the window to your action bar.")
end

-- Window -----------------------------------------------------------------------

local window, slots, checks

-- now(): the weapon the option wants in the current state, applied when it is ticked
-- and by settle().
local function daggerIfStealthed() return IsStealthed() and "dagger" or nil end
local function swordIfNotStealthed() return not IsStealthed() and "sword" or nil end
local adoptSword -- defined below setRole
-- Options added after 1.3.1 are off until ticked, so an update keeps the old behaviour.
local OPTIONS = {
  { key = "stealthDagger", label = "Dagger when entering stealth", now = daggerIfStealthed },
  { key = "swordLeaveStealth", label = "Sword when leaving stealth", now = swordIfNotStealthed },
  { key = "swordAfterCombat", label = "Sword when combat ends", now = swordIfNotStealthed },
  { key = "swordAfterOpener", label = "Sword after the opener" },
  { key = "pickPocket", label = "Pick Pocket before Ambush", macros = true },
  { key = "startAttack", label = "/startattack in the strike macros", macros = true },
  { key = "ghostlyAlone", label = "WS Ghostly: Ghostly Strike alone, no dagger", macros = true },
  { key = "riposte", label = "WS Sinister: Riposte first", macros = true },
  { key = "adoptSword", label = "A sword you equip by hand becomes the sword", onTick = function() adoptSword() end },
  { key = "debug", label = "Debug log (/reload saves it)", clearLog = true },
}

-- Puts in the weapon the ticked options want right now: after login, /reload, a
-- loading screen or a resurrection.
local function settle()
  if UnitIsDeadOrGhost("player") then return end
  for _, opt in ipairs(OPTIONS) do
    local role = opt.now and WeaponSwapDB[opt.key] and opt.now()
    if role then
      autoEquip(role)
      return
    end
  end
end

-- Stealth openers. Cheap Shot and Garrote do not need the dagger (Wowhead tooltips,
-- 2026-11-16), but stealth put it in, so the sword comes back after them too.
local SWAP_BACK_AFTER = { Backstab = true, Ambush = true, ["Cheap Shot"] = true, Garrote = true }

local function spellName(id)
  if GetSpellInfo then return (GetSpellInfo(id)) end
  local info = C_Spell.GetSpellInfo(id)
  return info and info.name
end

local function refresh()
  if not window then return end
  for role, button in pairs(slots) do
    local id = WeaponSwapDB[role]
    button.icon:SetTexture(id and GetItemIcon(id) or EMPTY_ICON)
    button.name:SetText(id and itemName(id) or "|cff808080drag here|r")
  end
  for key, check in pairs(checks) do
    check:SetChecked(WeaponSwapDB[key])
  end
end

local function setRole(role, id)
  WeaponSwapDB[role] = id
  if id then say(role .. " = " .. itemName(id)) end
  refresh()
  updateMacros()
end

-- A one-hand weapon other than a dagger put in the main hand, not by WeaponSwap (its
-- swaps only put the saved weapons there), becomes the sword. 2 = weapon, 15 = dagger.
local GetItemInfoInstant = GetItemInfoInstant or C_Item.GetItemInfoInstant
local ONE_HAND = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true }
function adoptSword()
  local id = GetInventoryItemID("player", MAIN_HAND)
  if not WeaponSwapDB.adoptSword or not id or id == WeaponSwapDB.dagger or id == WeaponSwapDB.sword then return end
  local _, _, _, equipLoc, _, classID, subclassID = GetItemInfoInstant(id)
  if classID == 2 and subclassID ~= 15 and ONE_HAND[equipLoc] then
    log("adoptSword %s", tostring(id))
    setRole("sword", id)
  end
end

local function dropOnSlot(button)
  local kind, id = GetCursorInfo()
  if kind == "item" then
    setRole(button.role, id)
    ClearCursor()
    return true
  end
end

local function buildWindow()
  window = CreateFrame("Frame", "WeaponSwapFrame", UIParent, "BasicFrameTemplateWithInset")
  window:SetSize(360, 412)
  window:SetPoint("CENTER")
  window:Hide() -- frames start shown; /ws toggles it right after building
  window:SetMovable(true)
  window:EnableMouse(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", window.StartMoving)
  window:SetScript("OnDragStop", window.StopMovingOrSizing)
  window:SetScript("OnShow", refresh)
  tinsert(UISpecialFrames, "WeaponSwapFrame") -- Esc closes it

  local title = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOP", 0, -5)
  title:SetText("WeaponSwap")

  slots = {}
  for i, role in ipairs(ROLES) do
    local b = CreateFrame("Button", nil, window)
    b.role = role
    b:SetSize(36, 36)
    b:SetPoint("TOPLEFT", 16, -34 - (i - 1) * 44)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    local label = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", b, "TOPRIGHT", 8, -2)
    label:SetText(role == "dagger" and "Dagger (Backstab / Ambush)" or "Sword")
    b.name = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.name:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)

    b:SetScript("OnReceiveDrag", dropOnSlot)
    b:SetScript("OnClick", function(self, mouse)
      if mouse == "RightButton" then
        setRole(self.role, nil)
      elseif not dropOnSlot(self) then
        equip(self.role)
      end
    end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      local id = WeaponSwapDB[self.role]
      if id then GameTooltip:SetItemByID(id) else GameTooltip:SetText("Drag a " .. self.role .. " here") end
      GameTooltip:AddLine("Left-click: equip  ·  Right-click: clear", 0.6, 0.6, 0.6)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    slots[role] = b
  end

  local create = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
  create:SetSize(116, 22)
  create:SetPoint("TOPLEFT", 16, -130)
  create:SetText("Create / update")
  create:SetScript("OnClick", createMacros)

  -- One icon per macro: drag it to the action bar.
  for i, m in ipairs(MACROS) do
    local b = CreateFrame("Button", nil, window)
    b:SetSize(26, 26)
    b:SetPoint("LEFT", create, "RIGHT", 6 + (i - 1) * 30, 0)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnShow", function(self)
      local _, texture = GetMacroInfo(m.name)
      self.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    end)
    b:SetScript("OnDragStart", function()
      if GetMacroIndexByName(m.name) > 0 then PickupMacro(m.name) else say("click Create / update first.") end
    end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(m.name)
      GameTooltip:AddLine("Drag to your action bar", 0.6, 0.6, 0.6)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    m.button = b
  end

  checks = {}
  for i, opt in ipairs(OPTIONS) do
    local c = CreateFrame("CheckButton", nil, window, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    c:SetPoint("TOPLEFT", 12, -158 - (i - 1) * 24)
    c:SetScript("OnClick", function(self)
      WeaponSwapDB[opt.key] = self:GetChecked() and true or nil
      if opt.clearLog and WeaponSwapDB[opt.key] then WeaponSwapDB.log = {} end
      if opt.macros then updateMacros() end
      if opt.onTick and WeaponSwapDB[opt.key] then opt.onTick() end
      local role = opt.now and WeaponSwapDB[opt.key] and opt.now()
      if role then autoEquip(role) end
    end)
    local label = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", c, "RIGHT", 2, 0)
    label:SetText(opt.label)
    checks[opt.key] = c
  end
end

-- Energy glow ------------------------------------------------------------------
-- With the sword in, the game greys out WS Backstab and WS Ambush (no dagger), even
-- though the macro swaps first. Forever gives addons the player's energy as a secret
-- value: addon code cannot compare it, but a StatusBar can display it. So each such
-- button gets a highlight drawn as a status bar running from cost - 1 to cost: the
-- game fills it (the button lights up) once energy reaches the opener's cost.
-- Blizzard's action bars only.

local OPENERS = { ["WS Backstab"] = "Backstab", ["WS Ambush"] = "Ambush" }
local ENERGY = Enum and Enum.PowerType and Enum.PowerType.Energy or 3
local BAR_PREFIXES = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
  "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }
local glows = {} -- button -> status bar
local glowBroken -- set when the game refuses, so it fails once instead of every tick

local function energyCost(spell)
  local GetCost = (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost
  local costs = GetCost and GetCost(spell)
  for _, c in ipairs(costs or {}) do
    if c.type == ENERGY then return c.cost end
  end
end

local function createGlows()
  for _, prefix in ipairs(BAR_PREFIXES) do
    for i = 1, 12 do
      local button = _G[prefix .. i]
      if button and button.icon and not glows[button] then
        local bar = CreateFrame("StatusBar", nil, button)
        bar:SetAllPoints(button.icon)
        bar:SetFrameLevel(button:GetFrameLevel() + 2)
        bar:SetStatusBarTexture("Interface\\Buttons\\ButtonHilight-Square")
        bar:GetStatusBarTexture():SetBlendMode("ADD")
        bar:Hide()
        glows[button] = bar
      end
    end
  end
end

-- Shows the glow on WS Backstab / WS Ambush while the sword is in.
local function updateGlow(button, bar)
  local action = button.action
  local spell = action and GetActionInfo(action) == "macro" and OPENERS[GetActionText(action) or ""]
  local cost = spell and energyCost(spell)
  if not cost or not WeaponSwapDB or GetInventoryItemID("player", MAIN_HAND) == WeaponSwapDB.dagger
      or (spell == "Ambush" and not IsStealthed()) then
    bar:Hide()
    return
  end
  bar:SetMinMaxValues(cost - 1, cost)
  bar:SetValue(UnitPower("player", ENERGY))
  bar:Show()
end

local function updateGlows()
  if glowBroken then return end
  for button, bar in pairs(glows) do
    local ok, err = pcall(updateGlow, button, bar)
    if not ok then
      glowBroken = true
      for _, b in pairs(glows) do b:Hide() end
      log("energy glow disabled: %s", tostring(err))
      return
    end
  end
end

local glowEvents = CreateFrame("Frame")
glowEvents:RegisterEvent("PLAYER_LOGIN")
glowEvents:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
glowEvents:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
glowEvents:RegisterEvent("UPDATE_STEALTH")
glowEvents:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
glowEvents:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
glowEvents:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
glowEvents:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then createGlows() end
  updateGlows()
end)

-- Slash command ----------------------------------------------------------------

SLASH_WEAPONSWAP1 = "/ws"
SLASH_WEAPONSWAP2 = "/WS"
SLASH_WEAPONSWAP3 = "/Ws"
SLASH_WEAPONSWAP4 = "/wS"
SlashCmdList.WEAPONSWAP = function(input)
  local cmd = input:match("^%s*(%S*)"):lower()
  if cmd == "dagger" or cmd == "sword" then
    equip(cmd)
  elseif cmd == "debug" then
    WeaponSwapDB.debug = not WeaponSwapDB.debug or nil
    if WeaponSwapDB.debug then WeaponSwapDB.log = {} end
    say("debug " .. (WeaponSwapDB.debug and "ON (log cleared; /reload saves it to disk)" or "OFF"))
    refresh()
  elseif cmd == "help" then
    say("/ws opens the window  ·  /ws dagger | /ws sword equips it  ·  /ws debug toggles the log")
  else
    if not window then buildWindow() end
    window:SetShown(not window:IsShown())
  end
end

-- Events -----------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED") -- names load lazily from the server
events:RegisterEvent("UPDATE_STEALTH")
events:RegisterEvent("PLAYER_REGEN_ENABLED") -- combat ended
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:RegisterEvent("BAG_UPDATE_DELAYED") -- bag slots moved: rewrite the macros
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED") -- a weapon moved to or from the off hand
events:RegisterEvent("PLAYER_ENTERING_WORLD") -- login, /reload, loading screens
events:RegisterEvent("PLAYER_ALIVE") -- resurrected without releasing
events:RegisterEvent("PLAYER_UNGHOST") -- back from ghost
events:SetScript("OnEvent", function(_, event, arg1, _, spellID)
  if event == "ADDON_LOADED" then
    if arg1 == "WeaponSwap" then
      WeaponSwapDB = WeaponSwapDB or {}
      WeaponSwapDB.auto = nil -- removed option
      WeaponSwapDB.openerOnly = nil -- removed before any release (2026-11-22)
      -- Each session starts a fresh log: the file on disk keeps the previous session
      -- until the next /reload or logout writes this one.
      WeaponSwapDB.log = {}
    end
  elseif event == "UPDATE_STEALTH" then
    if IsStealthed() then
      if WeaponSwapDB.stealthDagger then autoEquip("dagger") end
    elseif WeaponSwapDB.swordLeaveStealth then
      autoEquip("sword") -- skips in combat, e.g. after an opener
    end
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    -- autoEquip skips in combat (Forever blocks it there); swordAfterCombat covers that.
    if WeaponSwapDB.swordAfterOpener and SWAP_BACK_AFTER[spellName(spellID) or ""] then
      autoEquip("sword")
    end
  elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_EQUIPMENT_CHANGED" then
    if event == "PLAYER_EQUIPMENT_CHANGED" and arg1 == MAIN_HAND then adoptSword() end
    updateMacros()
  elseif event == "GET_ITEM_INFO_RECEIVED" then
    -- The hand-swap macros need the item names.
    if arg1 == WeaponSwapDB.dagger or arg1 == WeaponSwapDB.sword then updateMacros() end
    if window and window:IsShown() then refresh() end
  elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
    settle()
  elseif event == "PLAYER_REGEN_ENABLED" then
    updateMacros()
    if WeaponSwapDB.stealthDagger and IsStealthed() then
      autoEquip("dagger")
    elseif WeaponSwapDB.swordAfterCombat then
      autoEquip("sword")
    end
  elseif window and window:IsShown() then
    refresh()
  end
end)

-- Debug events: only logged while /ws debug is on.
local debug = CreateFrame("Frame")
debug:RegisterEvent("PLAYER_REGEN_DISABLED")
debug:RegisterEvent("PLAYER_REGEN_ENABLED")
debug:RegisterEvent("UPDATE_STEALTH")
debug:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
debug:RegisterEvent("UI_ERROR_MESSAGE")
debug:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
debug:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
debug:SetScript("OnEvent", function(_, event, a, b, c)
  if not (WeaponSwapDB and WeaponSwapDB.debug) then return end
  if event == "PLAYER_EQUIPMENT_CHANGED" then
    if a == 16 or a == 17 then log("%s slot %d", event, a) end
  elseif event == "UI_ERROR_MESSAGE" then
    log("%s %s", event, tostring(b))
  elseif event == "ITEM_LOCK_CHANGED" then
    log("%s bag %s slot %s", event, tostring(a), tostring(b))
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_FAILED" then
    log("%s %s", event, tostring(c and spellName(c) or c))
  else
    log("%s", event)
  end
end)

-- What the macros call (hooks run after the call and do not taint it).
if C_Container and C_Container.UseContainerItem then
  hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
    local link = C_Container.GetContainerItemLink(bag, slot)
    log("UseContainerItem %s %s %s", tostring(bag), tostring(slot), link and link:match("%[(.-)%]") or "empty")
  end)
end
if C_Item and C_Item.EquipItemByName then
  hooksecurefunc(C_Item, "EquipItemByName", function(item, slot)
    log("EquipItemByName %s %s", tostring(item), tostring(slot))
  end)
end
