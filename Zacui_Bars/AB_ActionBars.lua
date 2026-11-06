-- AB_ActionBars - the ten action bars: headers, Blizzard-template buttons,
-- paging, layout, text, bindings and the hotkey corner.
-- Part of ZacUI; load order is set by the TOC.
--
-- THE BUTTON is the stock action button in everything but its wiring: the
-- same art template, the same secure click handler and the same mixin
-- methods (cooldown, count, usability, drag, tooltip, Quick Keybind), with
-- its ID left at 0 so the client reads the slot from the "action"
-- attribute the header's page driver rewrites - securely, in combat too.
--
-- WHY NOT "ActionBarButtonTemplate" OUTRIGHT. That template's OnLoad puts
-- every button into Blizzard's shared dispatcher tables
-- (ActionBarButtonEventsFrame.frames and friends). Those tables are walked
-- by SECURE code - ActionBarController_UpdateAll on every stance change -
-- and a table an addon has inserted into is walked tainted, which turned
-- Blizzard's own hidden ActionButton1:SetAttribute() into an
-- ADDON_ACTION_BLOCKED the first time a stance flipped in combat. So the
-- buttons are assembled here from the template's parts, the one line that
-- registers them is left out, and this file dispatches their events itself.
-- Nothing of Blizzard's is ever written to.
--
-- BINDINGS. Bars 1, 3, 4, 5 and 6 answer to the client's own binding
-- names (ACTIONBUTTONn, MULTIACTIONBARxBUTTONn) through override bindings
-- on their headers, so keys set in Blizzard's Key Bindings window keep
-- working and nothing has to be re-bound. Bars 2 and 7-10 have no
-- Blizzard names; their keys bind straight to the buttons as
-- "CLICK ZacUIActionButtonN:LeftButton", listed under ZacUI in the Key
-- Bindings window (Bindings.xml).

local ADDON_NAME = ...
-- Zacui_Bars is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local AB = ns.Bars
local Print = ns.Print
local SkinSecureIcon = ns.SkinSecureIcon
local ZUI = ns.ZUI

-- Blizzard binding names per bar; the rest bind by CLICK.
local BLIZZ_BINDS = {
    [1] = "ACTIONBUTTON%d",
    [3] = "MULTIACTIONBAR3BUTTON%d",
    [4] = "MULTIACTIONBAR4BUTTON%d",
    [5] = "MULTIACTIONBAR2BUTTON%d",
    [6] = "MULTIACTIONBAR1BUTTON%d",
}
AB.BLIZZ_BINDS = BLIZZ_BINDS

-- Runs on the header whenever its page state changes. page 0 = the bar's
-- own slots; page N = Blizzard page N. offset rotates the buttons.
local PAGE_SNIPPET = [[
    local page = tonumber(newstate) or 0
    local base = self:GetAttribute("barslot") or 0
    if page > 0 then base = (page - 1) * 12 end
    local off = self:GetAttribute("offset") or 0
    for i = 1, 12 do
        local b = self:GetFrameRef("btn" .. i)
        if b then
            local idx = ((i + off - 1) % 12) + 1
            b:SetAttribute("action", base + idx)
        end
    end
]]

local bars = {}        -- [n] = header
AB.actionBars = bars

-- What the Key Bindings window shows for the CLICK names in Bindings.xml.
BINDING_HEADER_ZACUIBARS = "ZacUI action bars"
for _, n in ipairs({ 2, 7, 8, 9, 10 }) do
    for i = 1, AB.PER_BAR do
        _G["BINDING_NAME_CLICK ZacUIActionButton" .. ((n - 1) * AB.PER_BAR + i) .. ":LeftButton"] =
            "Bar " .. n .. " button " .. i
    end
end

local function ButtonName(absid) return "ZacUIActionButton" .. absid end
AB.ButtonName = ButtonName

function AB.BindingNameFor(n, i)
    local absid = (n - 1) * AB.PER_BAR + i
    if BLIZZ_BINDS[n] then return BLIZZ_BINDS[n]:format(i), absid end
    return "CLICK " .. ButtonName(absid) .. ":LeftButton", absid
end

-- First key bound to a button, through whichever name it answers to.
function AB.KeyFor(n, i)
    local name = AB.BindingNameFor(n, i)
    local key = GetBindingKey(name)
    if not key and BLIZZ_BINDS[n] then
        key = GetBindingKey("CLICK " .. ButtonName((n - 1) * AB.PER_BAR + i) .. ":LeftButton")
    end
    return key
end

local function UpdateAction(btn)
    if btn.UpdateAction then btn:UpdateAction(true)
    elseif ActionButton_UpdateAction then ActionButton_UpdateAction(btn, true) end
end

-- ============================================================
-- TEXT
-- ============================================================
-- Font, colour and corner of the three texts: AB.ApplyText (AB_Core),
-- shared with the preview's sample buttons.
local ApplyText = AB.ApplyText

-- THE HOTKEY CORNER. The client's UpdateHotkeys builds its binding name
-- from the button id ("ACTIONBUTTON0" for ours) and finds nothing, so our
-- buttons carry a replacement that knows the real name. It also sets
-- bindingAction (the binding-highlight registry) and commandName (what
-- Quick Keybind Mode binds a pressed key to), so hovering a button in
-- that mode binds the right command for every bar.
function AB.UpdateHotkeys(self)
    local n, i = self.zBar, self.zIndex
    local name = AB.BindingNameFor(n, i)
    self.bindingAction = name
    self.commandName = name
    local fs = self.zHotkey
    if not fs then return end
    local key = AB.KeyFor(n, i)
    local text = AB.ShortKey(key)
    if text == "" then
        fs:SetText(RANGE_INDICATOR or "")
        fs:Hide()
    else
        fs:SetText(text)
        fs:Show()
    end
    local cfg = self.zCfg
    fs:SetAlpha((cfg and cfg.hideHotkey) and 0 or 1)
end
AB.RefreshHotkey = AB.UpdateHotkeys

-- EMPTY SLOTS. On this client a button never hides itself: its BAR hides
-- the ones with no action unless a grid is wanted. That is a protected
-- show/hide the bar does from secure code; ours is alpha, which is not
-- protected and so also follows paging in combat. The grid is up while
-- something is on the cursor (ACTIONBAR_SHOWGRID), in Quick Keybind Mode,
-- while the bars are unlocked, or when the bar asks for it.
AB.gridShown = false
function AB.RefreshEmpty(self)
    local cfg = self.zCfg
    local action = self.action or self:GetAttribute("action")
    local has = action and C_ActionBar and C_ActionBar.HasAction and C_ActionBar.HasAction(action)
    if not has and action and HasAction then has = HasAction(action) end
    local show = has or AB.gridShown or AB.unlocked or (cfg and cfg.showgrid)
    self:SetAlpha(show and 1 or 0)
    -- the equipped-item cue moves onto our border; the stock ring is gone
    if self._zui_borderTex then
        AB.TintButtonBorder(self, (has and IsEquippedAction and IsEquippedAction(action)) and true or false)
    end
    AB.UpdateGlow(self, has and action or nil)
end

-- ZacUI's glow (or none) instead of the game's spell alert: the slot's
-- spell, and whether the game says its alert is up. "game" leaves the
-- button entirely to the client.
local function ActionSpell(action)
    if not (action and GetActionInfo) then return nil end
    local kind, id = GetActionInfo(action)
    if kind == "spell" then return id end
    return nil
end
function AB.UpdateGlow(btn, action)
    local mode = AB.CoreCfg().glow or "game"
    if mode == "game" then
        if btn.zGlow then AB.SetGlow(btn, false) end
        return
    end
    AB.HideStockAlert(btn)
    local spell = ActionSpell(action)
    if mode ~= "zacui" or not spell then
        if btn.zGlow then AB.SetGlow(btn, false) end
        return
    end
    -- a client that cannot be asked leaves the glow to the alert events
    if IsSpellOverlayed then
        AB.SetGlow(btn, IsSpellOverlayed(spell) and true or false)
    elseif btn.zGlowSpell ~= spell and btn.zGlow then
        AB.SetGlow(btn, false)
    end
end

function AB.RefreshAllEmpty()
    for _, header in pairs(bars) do
        for _, btn in ipairs(header.buttons or {}) do AB.RefreshEmpty(btn) end
    end
end

local gridWatch = CreateFrame("Frame")
gridWatch:RegisterEvent("ACTIONBAR_SHOWGRID")
gridWatch:RegisterEvent("ACTIONBAR_HIDEGRID")
gridWatch:SetScript("OnEvent", function(_, event)
    AB.gridShown = (event == "ACTIONBAR_SHOWGRID")
    AB.RefreshAllEmpty()
end)
if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("QuickKeybindFrame.QuickKeybindModeEnabled", function()
        AB.gridShown = true
        AB.RefreshAllEmpty()
    end, AB)
    EventRegistry:RegisterCallback("QuickKeybindFrame.QuickKeybindModeDisabled", function()
        AB.gridShown = false
        AB.RefreshAllEmpty()
    end, AB)
end

-- ============================================================
-- BUTTONS
-- ============================================================
-- A repeating glow ends when its button hides (Motion stops what is not
-- on screen); a button that comes back with its alert still up picks
-- the animation up again.
local function GlowBack(self)
    if self.zGlow and self.zGlow:IsShown() then AB.SetGlow(self, true, true) end
end

-- The game's range check and countdown switch, followed: the range state
-- is remembered for ZacUI's colours, and a bar that says "always" or
-- "never" for countdown numbers keeps its word after every cooldown.
if ActionButton_UpdateRangeIndicator then
    hooksecurefunc("ActionButton_UpdateRangeIndicator", function(self, checksRange, inRange)
        if not (self and self.zBar) then return end
        local oor
        if checksRange == nil and IsActionInRange and self.action then
            local r = IsActionInRange(self.action)
            oor = (r == false or r == 0)
        else
            oor = (checksRange and not inRange) and true or false
        end
        self.zOutOfRange = oor
        AB.ColorButton(self)
    end)
end
if ActionButton_UpdateCooldownNumberHidden then
    hooksecurefunc("ActionButton_UpdateCooldownNumberHidden", function(self)
        local look = self and self.zLook
        local cd = look and AB.Region(self, "cooldown", "Cooldown")
        if not (cd and cd.SetHideCountdownNumbers) then return end
        if look.cdText == "show" then cd:SetHideCountdownNumbers(false)
        elseif look.cdText == "hide" then cd:SetHideCountdownNumbers(true) end
        if look.cdSwipe == false and cd.SetDrawSwipe then cd:SetDrawSwipe(false) end
    end)
end

local function TooltipGate(self)
    local core = AB.Profile().core
    local mode = core and core.tooltip or "enabled"
    if mode == "disabled" or (mode == "nocombat" and InCombatLockdown()) then
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end
end

-- ------------------------------------------------------------
-- OUR OWN DISPATCH, standing in for the four Blizzard frames the stock
-- button would have joined. Same events, same per-button entry points.
-- ------------------------------------------------------------
local function Nop() end

-- Which buttons want range / usability news for which slot. Blizzard
-- keeps this per action too; ours never disables a slot's range check,
-- because the hidden stock button for the same slot may still be the one
-- the client thinks is listening.
local checkers = {}   -- [action] = { [btn] = true }
local function RegisterCheck(self, action)
    local set = checkers[action]
    if not set then set = {} checkers[action] = set end
    if set[self] then return end
    set[self] = true
    if C_ActionBar and C_ActionBar.EnableActionRangeCheck then
        C_ActionBar.EnableActionRangeCheck(action, true)
    end
end
local function UnregisterCheck(self, action)
    local set = checkers[action]
    if set then set[self] = nil end
end
-- The stock buttons switch range checks OFF for a slot they page away
-- from (bar 1 on a stance change, say) even when one of ours still shows
-- it. Re-asserting ours is cheap, so it happens after every page flip.
local function ReassertRangeChecks()
    if not (C_ActionBar and C_ActionBar.EnableActionRangeCheck) then return end
    for action, set in pairs(checkers) do
        if next(set) then C_ActionBar.EnableActionRangeCheck(action, true) end
    end
end

-- Buttons that need OnUpdate (flash, dirty state): one driver, not one
-- OnUpdate per button, exactly as the client does it.
local needsUpdate = {}
local updater = CreateFrame("Frame")
updater:Hide()
updater:SetScript("OnUpdate", function(_, elapsed)
    for btn in pairs(needsUpdate) do btn:OnUpdate(elapsed) end
end)
local function CheckNeedsUpdate(self)
    local needs = (self.stateDirty or self.flashDirty or self:IsFlashing()) and self:IsVisible() or false
    if needs ~= (self.needsUpdate or false) then
        if needs then
            needsUpdate[self] = true
            updater:Show()
        else
            needsUpdate[self] = nil
            if not next(needsUpdate) then updater:Hide() end
        end
        self.needsUpdate = needs
    end
end

-- Every button on an enabled bar.
local function EachLiveButton(fn, ...)
    for _, header in pairs(bars) do
        if header.cfg and header.cfg.enabled then
            for _, btn in ipairs(header.buttons) do fn(btn, ...) end
        end
    end
end

local BUTTON_EVENTS = {
    -- ActionBarButtonEventsFrame's set
    "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS",
    "GAME_PAD_ACTIVE_CHANGED", "UPDATE_SHAPESHIFT_FORM", "ACTIONBAR_UPDATE_COOLDOWN",
    "PET_BAR_UPDATE", "PLAYER_MOUNT_DISPLAY_CHANGED",
    -- ActionBarActionEventsFrame's set
    "SPELL_UPDATE_CHARGES", "UPDATE_INVENTORY_ALERTS", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE",
    "ARCHAEOLOGY_CLOSED", "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT", "START_AUTOREPEAT_SPELL",
    "STOP_AUTOREPEAT_SPELL", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "COMPANION_UPDATE",
    "UNIT_INVENTORY_CHANGED", "UNIT_SPELLCAST_SENT", "LEARNED_SPELL_IN_SKILL_LINE",
    "PET_STABLE_UPDATE", "PET_STABLE_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW",
    "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "UPDATE_SUMMONPETS_ACTION", "SPELL_UPDATE_ICON",
    -- page flips, for the range re-assert
    "UPDATE_BONUS_ACTIONBAR", "ACTIONBAR_PAGE_CHANGED",
}
local UNIT_EVENTS = {
    pet = { "UNIT_FLAGS", "UNIT_AURA" },
    player = { "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
               "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_START",
               "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_RETICLE_TARGET", "UNIT_SPELLCAST_RETICLE_CLEAR",
               "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_STOP",
               "LOSS_OF_CONTROL_ADDED", "LOSS_OF_CONTROL_UPDATE" },
}
local SPELLCAST = {}
for _, ev in ipairs(UNIT_EVENTS.player) do
    if ev:find("^UNIT_SPELLCAST_") then SPELLCAST[ev] = true end
end
SPELLCAST.UNIT_SPELLCAST_SENT = true
local PAGE_FLIP = { UPDATE_BONUS_ACTIONBAR = true, ACTIONBAR_PAGE_CHANGED = true,
                    UPDATE_SHAPESHIFT_FORM = true, PLAYER_ENTERING_WORLD = true }

local function SendEvent(btn, event, ...)
    btn:OnEvent(event, ...)
end

-- THE COALESCED SWEEPS. ACTIONBAR_UPDATE_COOLDOWN arrives two or three
-- times a frame in a fight and each copy used to walk all 120 buttons
-- (GetActionCooldown and a cooldown frame write apiece); a stance change
-- ran a full Update on every one. The events whose arguments the button
-- never reads are folded into one sweep on the next frame, in a fixed
-- order (the full Update first, so a later cooldown pass is the cheap
-- one). The sweep leaves buttons that are not on screen alone - a bar
-- hidden by its visibility driver, a button past the bar's count - and
-- marks them stale; they catch up with one Update in OnShow. Nothing
-- protected is touched here: these are display updates only.
local SWEEP_ORDER = { "UPDATE_SHAPESHIFT_FORM", "ACTIONBAR_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES",
                      "PLAYER_MOUNT_DISPLAY_CHANGED", "UNIT_FLAGS", "UNIT_AURA" }
local SWEEP_ARG = { UNIT_FLAGS = "pet", UNIT_AURA = "pet" }
local COALESCED = {}
for _, ev in ipairs(SWEEP_ORDER) do COALESCED[ev] = true end
local pendingSweep, sweepQueued = {}, false
local function SendIfVisible(btn, event, ...)
    if btn:IsVisible() then
        btn:OnEvent(event, ...)
    else
        btn.zStale = true
    end
end
local function RunSweeps()
    sweepQueued = false
    for _, ev in ipairs(SWEEP_ORDER) do
        if pendingSweep[ev] then
            pendingSweep[ev] = nil
            EachLiveButton(SendIfVisible, ev, SWEEP_ARG[ev])
        end
    end
end
local function QueueSweep(event)
    pendingSweep[event] = true
    if sweepQueued then return end
    sweepQueued = true
    C_Timer.After(0, RunSweeps)
end
-- A button a sweep skipped while it was off screen: one full Update the
-- moment it is back, so its cooldown, count and icon are current.
local function CatchUp(self)
    if not self.zStale then return end
    self.zStale = nil
    if self.Update then self:Update() end
end

-- Every player cast fires several of these (and a key held on the global
-- cooldown fires FAILED again and again), so only buttons that can care
-- are asked: an empty slot is skipped (the stock client only walks
-- filled buttons too) and one that is off screen is marked stale and
-- catches up with one Update when it shows (CatchUp).
local function SendSpellcast(btn, event, ...)
    if btn.zDerived and not btn.eventsRegistered then return end
    if not btn:IsVisible() then btn.zStale = true return end
    local unit = ...
    local spellID = (event == "UNIT_SPELLCAST_SENT") and select(4, ...) or select(3, ...)
    if unit == "player" and btn.MatchesActiveButtonSpellID and btn:MatchesActiveButtonSpellID(spellID) then
        btn:OnEvent(event, ...)
    end
end

-- A spell alert going up or down: the buttons showing that spell follow
-- it with ZacUI's glow, or with none, when the game's is not wanted.
local GLOW_EVENT = { SPELL_ACTIVATION_OVERLAY_GLOW_SHOW = true, SPELL_ACTIVATION_OVERLAY_GLOW_HIDE = true }
local function SendGlow(btn, event, spellID)
    if (AB.CoreCfg().glow or "game") == "game" then return end
    if ActionSpell(btn.action) ~= spellID then return end
    AB.HideStockAlert(btn)
    local on = event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" and AB.CoreCfg().glow == "zacui"
    btn.zGlowSpell = on and spellID or nil
    AB.SetGlow(btn, on)
end

local dispatch = CreateFrame("Frame")
for _, ev in ipairs(BUTTON_EVENTS) do pcall(dispatch.RegisterEvent, dispatch, ev) end
for unit, list in pairs(UNIT_EVENTS) do
    for _, ev in ipairs(list) do pcall(dispatch.RegisterUnitEvent, dispatch, ev, unit) end
end
pcall(dispatch.RegisterEvent, dispatch, "ACTION_RANGE_CHECK_UPDATE")
pcall(dispatch.RegisterEvent, dispatch, "ACTION_USABLE_CHANGED")
dispatch:SetScript("OnEvent", function(_, event, ...)
    if event == "ACTION_RANGE_CHECK_UPDATE" then
        local action, inRange, checksRange = ...
        local set = checkers[action]
        if set then
            for btn in pairs(set) do
                btn:OnEvent(event, ...)
                -- remembered for ZacUI's range colour, which goes on last
                btn.zOutOfRange = (checksRange and not inRange) and true or false
                AB.ColorButton(btn)
            end
        end
        return
    elseif event == "ACTION_USABLE_CHANGED" then
        local changes = ...
        if type(changes) == "table" then
            for _, change in ipairs(changes) do
                local set = checkers[change.slot]
                if set then
                    for btn in pairs(set) do btn:UpdateUsable(change.slot, change.usable, change.noMana) end
                end
            end
        end
        return
    elseif event == "UNIT_INVENTORY_CHANGED" then
        -- the client only refreshes the tooltip under the mouse for this one
        local owner = GameTooltip:GetOwner()
        if (...) == "player" and owner and owner.zAbs and owner.SetTooltip then owner:SetTooltip() end
        return
    elseif event == "UPDATE_BONUS_ACTIONBAR" or event == "ACTIONBAR_PAGE_CHANGED" then
        C_Timer.After(0, ReassertRangeChecks)
        return
    end
    if COALESCED[event] then
        QueueSweep(event)
    elseif SPELLCAST[event] then
        EachLiveButton(SendSpellcast, event, ...)
    else
        EachLiveButton(SendEvent, event, ...)
        if GLOW_EVENT[event] then EachLiveButton(SendGlow, event, ...) end
    end
    if PAGE_FLIP[event] then C_Timer.After(0, ReassertRangeChecks) end
end)

-- Quick Keybind Mode: the stock button skips its cast when the mode is
-- up; ours has the client's secure click handler, which cannot be told
-- to. So for the duration the buttons simply have no click type.
local function SetKeybindMode(on)
    if InCombatLockdown() then
        AB.AfterCombat("qkb", function() SetKeybindMode(on) end)
        return
    end
    for _, header in pairs(bars) do
        for _, btn in ipairs(header.buttons) do
            if on then btn:SetAttribute("type", nil) else btn:SetAttribute("type", "action") end
        end
    end
end
if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("QuickKeybindFrame.QuickKeybindModeEnabled", function() SetKeybindMode(true) end, bars)
    EventRegistry:RegisterCallback("QuickKeybindFrame.QuickKeybindModeDisabled", function() SetKeybindMode(false) end, bars)
end

local function PostClick(self, button, down)
    if KeybindFrames_InQuickKeybindMode and KeybindFrames_InQuickKeybindMode() then
        if GetCursorInfo() then
            if not down and C_ActionBar and C_ActionBar.PutActionInSlot then
                C_ActionBar.PutActionInSlot(self.action)
            end
        elseif QuickKeybindButtonTemplateMixin then
            QuickKeybindButtonTemplateMixin.QuickKeybindButtonOnClick(self, button, down)
        end
    end
    self:UpdateState()
end

-- NOT set: btn.bar. The client's button code treats .bar as one of its
-- own ActionBarMixin frames (GetSpellFlyoutDirection, UpdateShownButtons)
-- and only guards on it being nil. The id stays 0 so the slot comes from
-- the "action" attribute; OnAttributeChanged calls UpdateAction when the
-- page driver rewrites it.
local warnedClick = false
local function CreateButton(header, n, i)
    local absid = (n - 1) * AB.PER_BAR + i
    local name = ButtonName(absid)
    local btn
    local Derived, BarMixin = _G.ActionBarActionButtonDerivedMixin, _G.ActionBarButtonMixin
    if Derived and BarMixin and Mixin then
        -- the stock template's three parents, in an order that leaves the
        -- secure click handler on top; the stock mixins; no stock OnLoad
        btn = CreateFrame("CheckButton", name, header,
            "ActionButtonTemplate, QuickKeybindButtonTemplate, SecureActionButtonTemplate")
        Mixin(btn, Derived, BarMixin)
        btn.zBar, btn.zIndex, btn.zAbs = n, i, absid
        btn.zDerived = true                         -- eventsRegistered is ours to read

        -- ours before the stock setup runs, so the setup already uses them
        btn.UpdateHotkeys = AB.UpdateHotkeys
        btn.UpdatePressAndHoldAction = Nop          -- SetAttribute in combat, and no such spells here
        btn.RegisterActionBarButtonCheckFrames = RegisterCheck
        btn.UnregisterActionBarButtonCheckFrames = UnregisterCheck
        btn.CheckNeedsUpdate = CheckNeedsUpdate
        -- Update() keeps the stock button in ActionBarActionEventsFrame's
        -- table while the slot is filled. Pre-setting its flag to what the
        -- stock code expects makes it skip both the insert and the removal;
        -- the events it would have received come from the dispatcher above.
        local StockUpdate = btn.Update
        btn.Update = function(self)
            local action = self.action
            self.eventsRegistered = (action and C_ActionBar.HasAction(action)) and true or nil
            return StockUpdate(self)
        end

        -- ActionBarActionButtonMixin:OnLoad, minus its registry line
        btn.SetButtonStateBase = btn.SetButtonState
        btn.SetButtonState = btn.SetButtonStateOverride
        btn.flashing, btn.flashtime = 0, 0
        btn:SetAttribute("type", "action")
        btn:SetAttribute("typerelease", "actionrelease")
        btn:SetAttribute("checkselfcast", true)
        btn:SetAttribute("checkfocuscast", true)
        btn:SetAttribute("checkmouseovercast", true)
        btn:SetAttribute("useparent-unit", true)
        btn:SetAttribute("useparent-actionpage", true)
        btn:SetAttribute("pressAndHoldAction", false)
        btn:RegisterForDrag("LeftButton", "RightButton")
        btn:RegisterForClicks("AnyUp", "LeftButtonDown", "RightButtonDown")

        -- the stock template's script wiring, OnClick excepted: that one
        -- stays the secure handler SecureActionButtonTemplate installed
        btn:SetScript("OnAttributeChanged", btn.ActionBarActionButtonDerivedMixin_OnAttributeChanged)
        btn:SetScript("OnEvent", btn.ActionBarActionButtonDerivedMixin_OnEvent)
        btn:SetScript("OnDragStart", btn.ActionBarButtonMixin_OnDragStart)
        btn:SetScript("OnReceiveDrag", btn.ActionBarActionButtonDerivedMixin_OnReceiveDrag)
        btn:SetScript("OnDragStop", btn.ActionBarActionButtonDerivedMixin_OnDragStop)
        btn:SetScript("OnEnter", btn.ActionBarButtonMixin_OnEnter)
        btn:SetScript("OnLeave", btn.ActionBarButtonMixin_OnLeave)
        btn:SetScript("OnShow", btn.ActionBarActionButtonDerivedMixin_OnShow)
        btn:SetScript("OnHide", btn.ActionBarActionButtonDerivedMixin_OnHide)
        btn:SetScript("PostClick", PostClick)
        if not warnedClick and btn:GetScript("OnClick") ~= SecureActionButton_OnClick then
            warnedClick = true
            Print("Bars: the click handler is not the secure one - report this with your client build.")
        end

        btn:SetAttribute("action", absid)      -- OnAttributeChanged -> UpdateAction
        btn:UpdateAction()
        btn:UpdateHotkeys()
        if btn.QuickKeybindHighlightTexture then
            btn.QuickKeybindHighlightTexture:ClearAllPoints()
            btn.QuickKeybindHighlightTexture:SetPoint("CENTER")
            btn.QuickKeybindHighlightTexture:SetSize(46, 45)
        end
        if ActionButton_UpdateCooldownNumberHidden then ActionButton_UpdateCooldownNumberHidden(btn) end
    else
        -- a client without the mixins: the stock template, as before
        btn = CreateFrame("CheckButton", name, header, "ActionBarButtonTemplate")
        btn.zBar, btn.zIndex, btn.zAbs = n, i, absid
        btn.UpdateHotkeys = AB.UpdateHotkeys
        btn:SetAttribute("type", "action")
        btn:SetAttribute("action", absid)
    end
    header:SetFrameRef("btn" .. i, btn)

    btn.zHotkey = AB.Region(btn, "HotKey", "HotKey")
    btn.zCount  = AB.Region(btn, "Count", "Count")
    btn.zName   = AB.Region(btn, "Name", "Name")

    SkinSecureIcon(btn)
    local cd = AB.Region(btn, "cooldown", "Cooldown")
    if cd and cd.SetDrawEdge then cd:SetDrawEdge(false) end

    if type(btn.Update) == "function" then
        hooksecurefunc(btn, "Update", AB.RefreshEmpty)
    end
    -- ZacUI's range and usability colours go on after the game's own
    if type(btn.UpdateUsable) == "function" then
        hooksecurefunc(btn, "UpdateUsable", function(self, _, usable, noMana) AB.ColorButton(self, usable, noMana) end)
    end
    btn:HookScript("OnEnter", TooltipGate)
    btn:HookScript("OnShow", CatchUp)
    btn:HookScript("OnShow", GlowBack)
    return btn
end

-- Apply one bar's visual settings to a button. Attribute writes here are
-- secure writes: callers are out of combat (ApplyAll guarantees it).
local function ConfigureButton(btn, cfg, core)
    btn.zCfg = cfg
    btn:EnableMouse(not cfg.clickthrough)
    btn:SetAttribute("checkselfcast", core.selfcast and true or nil)
    btn:SetAttribute("checkfocuscast", core.focuscast and true or nil)
    btn:SetAttribute("*unit2", core.rightclickself and "player" or nil)

    local f = cfg.fonts or {}
    ApplyText(btn, btn.zHotkey, f.hotkey, cfg.hideHotkey, "hotkey", cfg)
    ApplyText(btn, btn.zCount,  f.count,  cfg.hideCount, "count", cfg)
    ApplyText(btn, btn.zName,   f.macro,  cfg.hideMacro, "macro", cfg)
    AB.FitText(btn, cfg.buttonSize or AB.BUTTON)
    AB.StyleButton(btn, cfg)

    UpdateAction(btn)
    AB.UpdateHotkeys(btn)
    AB.RefreshEmpty(btn)
end

-- ============================================================
-- BARS
-- ============================================================
local function CreateBar(n)
    local header = AB.NewHeader("bar" .. n, "ZacUIBar" .. n, "Bar " .. n)
    header.n = n
    header:SetAttribute("barslot", (n - 1) * AB.PER_BAR)
    header:SetAttribute("offset", 0)
    header.buttons = {}
    for i = 1, AB.PER_BAR do header.buttons[i] = CreateButton(header, n, i) end
    header:SetAttribute("_onstate-page", PAGE_SNIPPET)
    bars[n] = header
    return header
end

-- Override bindings for the bars that answer to Blizzard names. The
-- client's hidden stock buttons still own those names; an override on
-- the header takes the key first.
function AB.ReassignBindings()
    if InCombatLockdown() then AB.AfterCombat("rebind", AB.ReassignBindings) return end
    for n, header in pairs(bars) do
        ClearOverrideBindings(header)
        local tmpl = BLIZZ_BINDS[n]
        if tmpl and header.cfg and header.cfg.enabled then
            for i = 1, math.min(header.cfg.buttons or 12, AB.PER_BAR) do
                local bname = ButtonName((n - 1) * AB.PER_BAR + i)
                local blizz = tmpl:format(i)
                for k = 1, select("#", GetBindingKey(blizz)) do
                    local key = select(k, GetBindingKey(blizz))
                    if key then SetOverrideBindingClick(header, false, key, bname, "LeftButton") end
                end
            end
        end
        for _, btn in ipairs(header.buttons) do AB.RefreshHotkey(btn) end
    end
end

local function ApplyBar(n, cfg, core)
    local header = bars[n] or CreateBar(n)
    header.cfg = cfg
    if not cfg.enabled then
        UnregisterStateDriver(header, "visibility")
        UnregisterStateDriver(header, "page")
        header:Hide()
        AB.RegisterFade(header, { fade = false, alpha = 1 })
        return
    end
    header:SetAttribute("offset", cfg.offset or 0)
    AB.Place(header, cfg)
    AB.LayoutButtons(header, header.buttons, cfg, cfg.buttonSize or AB.BUTTON, cfg.buttons or 12)
    for _, btn in ipairs(header.buttons) do ConfigureButton(btn, cfg, core) end
    header:SetAlpha(cfg.alpha or 1)
    header:Show()
    -- drivers last: the page driver fires at once and writes every
    -- button's action attribute through the snippet
    UnregisterStateDriver(header, "page")
    RegisterStateDriver(header, "page", AB.PageDriver(cfg))
    UnregisterStateDriver(header, "visibility")
    RegisterStateDriver(header, "visibility", AB.VisibilityDriver(cfg))
    AB.RegisterFade(header, cfg)
    AB.MoverFor(header, cfg, function()
        if ns.RefreshConfig then ns.RefreshConfig() end
    end)
end

local function ApplyActionBars(profile)
    local core = profile.core
    for n = 1, AB.NUM_BARS do ApplyBar(n, profile.bars[n], core) end
    -- Blizzard's own lock: the pickup modifier is theirs too
    if core.buttonlock ~= nil then
        pcall(SetCVar, "lockActionBars", core.buttonlock and "1" or "0")
    end
    AB.ReassignBindings()
end
AB.RegisterApplier(ApplyActionBars)

-- Keys change: re-take the overrides and repaint the corners.
local bindWatch = CreateFrame("Frame")
bindWatch:RegisterEvent("UPDATE_BINDINGS")
bindWatch:SetScript("OnEvent", function()
    if not AB.active then return end
    if AB._bindQueued then return end
    AB._bindQueued = true
    C_Timer.After(0.1, function()
        AB._bindQueued = nil
        AB.ReassignBindings()
    end)
end)

-- ============================================================
-- OLD KEY MIGRATION (Bartender4, Dominos)
-- ============================================================
-- Keys a character had on another bar addon's own binding names live on
-- in the client's binding cache after that addon is gone. Every login
-- (it is cheap, and a binding set can be reloaded from the server under
-- us) each such key is moved onto the matching ZacUI button: bars 1/3-6
-- onto the Blizzard name their buttons already answer to, bars 2 and
-- 7-10 onto the CLICK name. Pet and stance keys follow the same rule.
-- Nothing is saved unless something actually moved.
-- Every name another bar addon ever hung a key on, for bar n button i
-- (absid = (n-1)*12+i). Bartender4 and Dominos number buttons 1-120 the
-- way we do; ElvUI names them by bar and button.
-- (one scratch list, refilled per button: this runs for all 120 buttons
-- at login and again once the bindings have settled)
local oldNames = {}
local function OldNames(n, i, absid)
    oldNames[1] = "CLICK BT4Button" .. absid .. ":Keybind"
    oldNames[2] = "CLICK BT4Button" .. absid .. ":LeftButton"
    oldNames[3] = "CLICK DominosActionButton" .. absid .. ":HOTKEY"
    oldNames[4] = "CLICK DominosActionButton" .. absid .. ":LeftButton"
    oldNames[5] = "ELVUIBAR" .. n .. "BUTTON" .. i
    oldNames[6] = "CLICK ElvUI_Bar" .. n .. "Button" .. i .. ":LeftButton"
    return oldNames
end
function AB.MigrateBartenderKeys(verbose)
    if InCombatLockdown() then AB.AfterCombat("btkeys", function() AB.MigrateBartenderKeys(verbose) end) return end
    local moved = 0
    local function Move(oldNames, newButton, newBlizz)
        local want = "CLICK " .. newButton .. ":LeftButton"
        for _, old in ipairs(oldNames) do
            for k = 1, select("#", GetBindingKey(old)) do
                local key = select(k, GetBindingKey(old))
                if key then
                    local cur = GetBindingAction(key)
                    if cur ~= want and cur ~= newBlizz then
                        local ok
                        if newBlizz then ok = SetBinding(key, newBlizz)
                        else ok = SetBindingClick(key, newButton, "LeftButton") end
                        if ok then moved = moved + 1 end
                    end
                end
            end
        end
    end
    for n = 1, AB.NUM_BARS do
        for i = 1, AB.PER_BAR do
            local absid = (n - 1) * AB.PER_BAR + i
            local blizz = BLIZZ_BINDS[n] and BLIZZ_BINDS[n]:format(i) or nil
            Move(OldNames(n, i, absid), ButtonName(absid), blizz)
        end
    end
    for i = 1, 10 do
        Move({ "CLICK BT4PetButton" .. i .. ":LeftButton", "CLICK DominosPetActionButton" .. i .. ":HOTKEY",
               "CLICK ElvUI_BarPetButton" .. i .. ":LeftButton" },
             "ZacUIPetButton" .. i, "BONUSACTIONBUTTON" .. i)
        Move({ "CLICK BT4StanceButton" .. i .. ":LeftButton", "CLICK DominosStanceButton" .. i .. ":HOTKEY",
               "CLICK ElvUI_StanceBarButton" .. i .. ":LeftButton" },
             "ZacUIStanceButton" .. i, "SHAPESHIFTBUTTON" .. i)
    end
    if moved > 0 then
        SaveBindings(GetCurrentBindingSet())
        Print("Moved " .. moved .. " key" .. (moved == 1 and "" or "s") .. " from old bar addon buttons to ZacUI's.")
    elseif verbose then
        Print("No keys left on Bartender4, Dominos or ElvUI buttons.")
    end
    ZacUICharDB = ZacUICharDB or {}
    ZacUICharDB.barsKeysMigrated = true
    AB.ReassignBindings()
end

-- ============================================================
-- QUICK KEYBIND MODE (/kb)
-- ============================================================
-- Blizzard's own hover-to-bind mode (Options > Keybindings > Quick
-- Keybind Mode). Our buttons inherit its template, and commandName above
-- tells it what to bind, so it works on every ZacUI bar - including the
-- pet and stance bars, whose buttons carry Blizzard's names. Opened from
-- here it closes cleanly instead of bouncing back to the Settings panel.
function AB.QuickKeybind()
    local f = _G.QuickKeybindFrame
    if not f then Print("Quick Keybind Mode is not available on this client.") return end
    if InCombatLockdown() then Print("Keys cannot be bound in combat.") return end
    if f:IsShown() then f:Hide() return end
    if not f._zHooked then
        f._zHooked = true
        f:HookScript("OnHide", function()
            if AB._kbFromSlash then
                AB._kbFromSlash = nil
                C_Timer.After(0, function()
                    if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then HideUIPanel(SettingsPanel) end
                end)
            end
        end)
    end
    AB._kbFromSlash = true
    if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then HideUIPanel(SettingsPanel) end
    if GameMenuFrame and GameMenuFrame:IsShown() and HideUIPanel then HideUIPanel(GameMenuFrame) end
    f:Show()
end

-- ESCAPE OVER A BUTTON CLEARS IT (2026-10-21, Zac: "i hit esc with my
-- mouse hovered over a action bar ... it cancels out of the keybind
-- mode"). In the mode, Escape over a button now unbinds that button and
-- the mode stays up; Escape with nothing under the mouse still leaves
-- it. A keyboard catcher above the mode's dialog sees each key first,
-- keeps Escape only when a bindable button is hovered, and lets every
-- other key through untouched.
local function HoveredBindable()
    local f
    if GetMouseFoci then
        local foci = GetMouseFoci()
        f = foci and foci[1]
    elseif GetMouseFocus then
        f = GetMouseFocus()
    end
    for _ = 1, 3 do
        if not f then return nil end
        if f.commandName and f.commandName ~= "" then return f end
        f = f.GetParent and f:GetParent() or nil
    end
    return nil
end

local function IsEscape(key)
    if key == "ESCAPE" then return true end
    local k1, k2 = GetBindingKey("TOGGLEGAMEMENU")
    return key ~= nil and (key == k1 or key == k2)
end

local escCatch = CreateFrame("Frame", nil, UIParent)
escCatch:SetFrameStrata("FULLSCREEN_DIALOG")
escCatch:SetSize(1, 1)
escCatch:SetPoint("TOPLEFT")
escCatch:Hide()
-- Propagation goes back on the frame after a kept Escape, so the catcher
-- never sits with it off: SetPropagateKeyboardInput cannot be called in
-- combat, and a catcher left "off" would eat every key of the fight.
local function Repropagate()
    if not InCombatLockdown() then escCatch:SetPropagateKeyboardInput(true) end
end
-- In combat nothing is caught: the catcher steps out of the way (a plain
-- Hide, allowed in combat) and comes back after the fight if the mode is
-- still up.
-- (PLAYER_REGEN_DISABLED runs before lockdown starts, so AfterCombat
-- would run the re-show at once; a one-shot REGEN_ENABLED does it instead.)
local function CombatStepAside()
    escCatch:Hide()
    escCatch:RegisterEvent("PLAYER_REGEN_ENABLED")
end
escCatch:SetScript("OnKeyDown", function(self, key)
    if InCombatLockdown() then CombatStepAside() return end
    local btn = IsEscape(key) and HoveredBindable()
    if not btn then
        self:SetPropagateKeyboardInput(true)
        return
    end
    self:SetPropagateKeyboardInput(false)
    C_Timer.After(0, Repropagate)
    local keys = { GetBindingKey(btn.commandName) }
    if #keys == 0 then
        Print("Nothing bound there.")
        return
    end
    for _, k in ipairs(keys) do SetBinding(k) end
    if AB.UpdateHotkeys and btn.zBar then AB.UpdateHotkeys(btn) end
    Print("Unbound " .. table.concat(keys, ", ") .. ".")
end)
escCatch:RegisterEvent("PLAYER_REGEN_DISABLED")
escCatch:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if KeybindFrames_InQuickKeybindMode and KeybindFrames_InQuickKeybindMode() then
            self:SetPropagateKeyboardInput(true)
            self:Show()
        end
        return
    end
    if self:IsShown() then CombatStepAside() end
end)

local function EscCatchOn(on)
    if not on then
        -- hiding is allowed in combat: the mode closing mid-fight must
        -- never leave a keyboard catcher up
        escCatch:Hide()
        if not InCombatLockdown() then escCatch:EnableKeyboard(false) end
        return
    end
    if InCombatLockdown() then return end
    escCatch:Show()
    escCatch:EnableKeyboard(true)
    escCatch:SetPropagateKeyboardInput(true)
end
if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("QuickKeybindFrame.QuickKeybindModeEnabled", function() EscCatchOn(true) end, escCatch)
    EventRegistry:RegisterCallback("QuickKeybindFrame.QuickKeybindModeDisabled", function() EscCatchOn(false) end, escCatch)
end

SLASH_ZACUIKB1 = "/kb"
SLASH_ZACUIKB2 = "/zkb"
SlashCmdList["ZACUIKB"] = function() AB.QuickKeybind() end
