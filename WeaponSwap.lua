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
local MACROS = {
  { name = "WS Backstab", body = "#showtooltip Backstab\n/equipslot [noequipped:Daggers] 16 %s\n/cast Backstab", fallback = "dagger" },
  { name = "WS Ambush", body = "#showtooltip Ambush\n/equipslot [noequipped:Daggers] 16 %s\n/cast Ambush", fallback = "dagger", pickPocket = true },
  { name = "WS Sword", body = "/equipslot [equipped:Daggers] 16 %s", fallback = "sword", iconFrom = "sword" },
  { name = "WS Sinister", body = "#showtooltip Sinister Strike\n/cast Sinister Strike\n/equipslot [equipped:Daggers] 16 %s", fallback = "sword" },
  { name = "WS Slice", body = "#showtooltip Slice and Dice\n/cast Slice and Dice\n/equipslot [equipped:Daggers] 16 %s", fallback = "sword" },
  -- Out of stealth: Ghostly Strike lets the next Ambush skip Stealth (7 s). While it is on
  -- cooldown the line fails and Ambush goes; without the buff Ambush fails and Backstab goes.
  { name = "WS Ghostly", body = "#showtooltip\n/equipslot [noequipped:Daggers] 16 %s\n/cast [nostealth] Ghostly Strike\n/cast Ambush\n/cast Backstab", fallback = "dagger" },
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

-- Pick Pocket before Ambush, on one press: it has no global cooldown, and the debug log
-- (2026-11-16) shows "/cast Pick Pocket" + "/cast Sap" landing both on the same press.
-- Ambush still needs you behind the target, Pick Pocket does not. [nocombat] skips it
-- after Vanish, where it fails.
local function macroBody(m, slot)
  local body = m.body
  if m.pickPocket and WeaponSwapDB.pickPocket then
    body = body:gsub("\n/cast Ambush", "\n/cast [nocombat] Pick Pocket\n/cast Ambush")
  end
  if slot then return body:format(slot) end
  -- No weapon in the bags: /ws works out of combat only.
  return (body:gsub("/equipslot %b[] 16 %%s", "/ws " .. m.fallback))
end

-- Rewrites existing macros whose bag slot changed. Out of combat only.
local function updateMacros()
  if not WeaponSwapDB or InCombatLockdown() then return end
  local slot = swapSlot()
  for _, m in ipairs(MACROS) do
    local index = GetMacroIndexByName(m.name)
    local body = macroBody(m, slot)
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
  local slot = swapSlot()
  for _, m in ipairs(MACROS) do
    local index = GetMacroIndexByName(m.name)
    if index > 0 then
      EditMacro(index, m.name, macroIcon(m), macroBody(m, slot))
    elseif not CreateMacro(m.name, macroIcon(m), macroBody(m, slot), true) then
      say("could not create " .. m.name .. ": character macro slots are full.")
    end
  end
  for _, m in ipairs(MACROS) do
    if m.button then m.button:GetScript("OnShow")(m.button) end
  end
  if not slot then say("no dagger or spare sword found in your bags; the macros will only swap out of combat.") end
  say("macros ready. Drag them from the window to your action bar.")
end

-- Window -----------------------------------------------------------------------

local window, slots, checks

-- now(): the weapon the option wants in the current state, applied when it is ticked
-- and by settle().
local function daggerIfStealthed() return IsStealthed() and "dagger" or nil end
local function swordIfNotStealthed() return not IsStealthed() and "sword" or nil end
local OPTIONS = {
  { key = "stealthDagger", label = "Dagger when entering stealth", now = daggerIfStealthed },
  { key = "swordLeaveStealth", label = "Sword when leaving stealth", now = swordIfNotStealthed },
  { key = "swordAfterCombat", label = "Sword when combat ends", now = swordIfNotStealthed },
  { key = "swordAfterOpener", label = "Sword after the opener" },
  { key = "pickPocket", label = "Pick Pocket before Ambush", macros = true },
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
  window:SetSize(330, 316)
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
events:RegisterEvent("PLAYER_ENTERING_WORLD") -- login, /reload, loading screens
events:RegisterEvent("PLAYER_ALIVE") -- resurrected without releasing
events:RegisterEvent("PLAYER_UNGHOST") -- back from ghost
events:SetScript("OnEvent", function(_, event, arg1, _, spellID)
  if event == "ADDON_LOADED" then
    if arg1 == "WeaponSwap" then
      WeaponSwapDB = WeaponSwapDB or {}
      WeaponSwapDB.auto = nil -- removed option
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
  elseif event == "BAG_UPDATE_DELAYED" then
    updateMacros()
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
