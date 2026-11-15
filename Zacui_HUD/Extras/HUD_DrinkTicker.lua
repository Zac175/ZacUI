-- HUD_DrinkTicker - a bar synced to the server's 2-second mana tick
-- clock: native port of the "Drink & Walk" WeakAura (wago 51IGxmwQJ).
-- Drink-walking: stand up right as the bar fills and you keep the big
-- drink tick. Works for every mana class.
-- Part of ZacUI; load order is set by the TOC.
-- Unlike the WA (whose one-shot energize flag mis-fired on coalesced
-- events and which re-anchored on every gain), energizes record a
-- timestamp - gains within ENERGIZE_WINDOW of one are ignored - and the
-- anchor only snaps when drift exceeds SNAP_TOLERANCE, so event latency
-- cannot jitter a locked clock.
-- Perf: hot handlers do UnitPower reads + timestamp math only; the
-- energize watch rides ZacUI's shared combat-log reader (ns.CLEU) and
-- early-outs on destGUID; the drink buff is read from ns.PlayerAuras; the fill
-- OnUpdate runs only while shown.
local ADDON_NAME = ...
-- Zacui_HUD is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end
if not ns.HUD then return end   -- (the part stands down on this game version: HUD_Shared, Core_Flavor)
if ns.HUD.RETAIL then return end   -- (Retail: its own class HUD, HUD_Retail.lua; this Classic one never loads there)

-- a value WoW Forever hands back hidden (a secret value: no maths on it)
local function Hidden(v) return ns.IsSecret ~= nil and ns.IsSecret(v) or false end
local HUD = ns.HUD
local UI = ns.UI
local Print = ns.Print

ns.DrinkTicker = ns.DrinkTicker or {}
local DT = ns.DrinkTicker


local TICK = 2                       -- server mana tick period (s)
local ENERGIZE_WINDOW = 0.25         -- ignore gains this close to an energize
local SNAP_TOLERANCE = 0.3           -- re-anchor only past this drift

-- Storage: ZacUIDB.hud.drinkTicker
local DEFAULTS = {
    enabled = false,
    x = -212, y = -146,
    w = 176, h = 10,
    showMode = "smart",              -- smart | always | combatHide
    label = true,
    -- look (2026-11: settings for what it always drew)
    color = { r = 0.25, g = 0.65, b = 1, a = 1 },
    labelText = "Drink",
    labelColor = { r = 1, g = 1, b = 1, a = 1 },
    labelSize = 10,
    labelPos = "LEFT",               -- LEFT | CENTER | RIGHT
    showAnim = { style = "none", duration = 0.2, delay = 0, easing = "easeOutQuad" },
    hideAnim = { style = "none", duration = 0.2, delay = 0, easing = "easeOutQuad" },
}

function DT.Store()
    return HUD.Store("drinkTicker", DEFAULTS)
end

-- Tick clock state
local isManaUser = false
local playerGUID = nil
local anchor = 0                     -- GetTime() of a known tick
local lastMana = 0
local lastEnergize = -10             -- GetTime() of last CLEU energize on us
local hasDrinkBuff = false

local ENERGIZE_EVENTS = {
    "SPELL_ENERGIZE", "SPELL_DRAIN", "SPELL_LEECH",
    "SPELL_PERIODIC_ENERGIZE", "SPELL_PERIODIC_DRAIN", "SPELL_PERIODIC_LEECH",
}

local function OnPowerUpdate()
    local cur = UnitPower("player", 0) or 0
    -- hidden (WoW Forever): no maths on it, so the tick clock waits for a
    -- reading it can use
    if Hidden(cur) then lastMana = nil return end
    if lastMana and cur > lastMana then
        local now = GetTime()
        -- Non-regen gain? The drink's own periodic energize is ALSO on the
        -- tick clock, so gains while drinking are trusted.
        local suspicious = (now - lastEnergize) < ENERGIZE_WINDOW and not hasDrinkBuff
        if not suspicious then
            -- Snap the clock only when prediction and reality disagree.
            local phase = (now - anchor) % TICK
            local drift = math.min(phase, TICK - phase)
            if anchor == 0 or drift > SNAP_TOLERANCE then
                anchor = now
            else
                -- Gentle correction: nudge the anchor onto this tick.
                anchor = now - ((phase > TICK / 2) and (phase - TICK) or phase)
            end
        end
    end
    lastMana = cur
end

-- ns.CLEU hands only the ENERGIZE_EVENTS sub-events here
local function OnCombatLogEvent(_, _, _, _, _, _, _, destGUID)
    if destGUID ~= playerGUID then return end
    lastEnergize = GetTime()
end

-- Bar. It hangs off an UNSCALED holder that ZacUI's mover registry
-- positions; the store's { x, y } is the default until it is dragged.
local bar = nil

-- The fill follows the tick clock bar.clock() hands it (the live clock's
-- anchor; the settings preview's sample keeps its own). Runs only while
-- the bar is shown.
local function FillOnUpdate(self)
    local a = self.clock and self.clock() or 0
    if a == 0 then
        self.bar:SetValue(0)
        if self.UpdateSpark then self:UpdateSpark(0) end
        return
    end
    local frac = ((GetTime() - a) % TICK) / TICK
    self.bar:SetValue(frac)
    if self.UpdateSpark then self:UpdateSpark(frac) end
end

-- One Drink Ticker bar on `parent` (the live holder, or the preview's
-- canvas): the HUD bar widget, its label, the fill driver.
function DT.MakeBar(parent, clock)
    local W = ns.WarriorHUD and ns.WarriorHUD.Widgets
    if not W then return nil end
    local b = W.CreateBar(parent, { width = DEFAULTS.w, height = DEFAULTS.h,
        spark = true, barColor = { 0.25, 0.65, 1, 1 } })
    b:SetPoint("CENTER", parent, "CENTER", 0, 0)
    -- Created on the StatusBar so it draws above the fill texture.
    local label = HUD.Text(b.bar, 10, "OUTLINE", "OVERLAY", "text")
    label:SetPoint("LEFT", b, "LEFT", 3, 0)
    label:SetTextColor(1, 1, 1)
    label:SetText("Drink")
    b.label = label
    if HUD.BarText then HUD.BarText(label, b) end
    b.clock = clock
    b:SetScript("OnUpdate", FillOnUpdate)
    return b
end

-- Size, colour and label from the settings (the live bar and the sample).
local LABEL_X = { LEFT = 3, CENTER = 0, RIGHT = -3 }
function DT.StyleBar(b, cfg)
    b:SetSize(cfg.w or DEFAULTS.w, cfg.h or DEFAULTS.h)
    b:SetBarColor(HUD.Col(cfg.color, DEFAULTS.color))
    local lab = b.label
    local pos = LABEL_X[cfg.labelPos or "LEFT"] and (cfg.labelPos or "LEFT") or "LEFT"
    lab:ClearAllPoints()
    lab:SetPoint(pos, b, pos, LABEL_X[pos], 0)
    lab:SetText(cfg.labelText or "Drink")
    lab:SetTextColor(HUD.Col(cfg.labelColor, DEFAULTS.labelColor))
    HUD.ApplyFont(lab, tonumber(cfg.labelSize) or 10, "OUTLINE", "text")
    lab:SetShown(cfg.label and true or false)
end

local function BuildBar()
    if bar then return end
    local cfg = DT.Store()
    if not cfg then return end
    if not (ns.WarriorHUD and ns.WarriorHUD.Widgets) then return end

    local holder = CreateFrame("Frame", "ZacUIHUD_DrinkTicker_Holder", UIParent)
    holder:SetSize(cfg.w, cfg.h)
    holder:SetFrameStrata("MEDIUM")
    holder:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    HUD.PlaceAnchor("drinkTicker", holder, cfg)

    bar = DT.MakeBar(holder, function() return anchor end)
    bar.holder = holder
    DT.StyleBar(bar, cfg)
    bar:Hide()

    HUD.RegisterMover("drinkTicker", "Drink Ticker", holder, cfg)
end

function DT.ApplySizes()
    local cfg = DT.Store()
    if not (bar and cfg) then return end
    DT.StyleBar(bar, cfg)
    bar.holder:SetSize(cfg.w, cfg.h)
end

-- Shows or hides the bar through its appear / go animations (instant by
-- default). The 0.5 s tick asks the same thing most of the time; only a
-- change does anything.
local function SetBarShown(on)
    local cfg = DT.Store()
    local M = ns.Motion
    if on then
        if bar._leaving then
            bar._leaving = nil
            if M then M.Stop(bar) end
            bar:Show()
        elseif not bar:IsShown() then
            if M and cfg then M.Play(bar, cfg.showAnim, "in") else bar:Show() end
        end
    elseif bar:IsShown() and not bar._leaving then
        if M and cfg and cfg.hideAnim and cfg.hideAnim.style ~= "none" then
            bar._leaving = true
            M.Play(bar, cfg.hideAnim, "out", function() bar._leaving = nil end)
            if not bar:IsShown() then bar._leaving = nil end
        else
            bar:Hide()
        end
    end
end

-- Visibility (0.5s ticker; also refreshes the drink-buff flag)
-- Both aura paths return spellIds, so match those first - that works on
-- every locale. The English name check stays as a safety net for any
-- drink aura id the list misses.
local DRINK_NAME = "Drink"
local DRINK_SPELL_IDS = {              -- Classic Era "Drink" aura ids
    [430] = true, [431] = true, [432] = true, [1133] = true,
    [1135] = true, [1137] = true, [10250] = true, [22734] = true,
    [24355] = true, [25696] = true, [29007] = true,
}

-- Read only after the player's auras moved (auraDirty, set by the
-- ns.PlayerAuras notice), never on the bare 0.5 s tick, from ZacUI's shared
-- read of the player's buffs (no client calls of its own).
local auraDirty = true
local function ScanDrinkBuff()
    if not auraDirty then return end
    auraDirty = false
    hasDrinkBuff = false
    local list = ns.PlayerAuras.Buffs()
    for i = 1, #list do
        local a = list[i]
        if (a.spellId and DRINK_SPELL_IDS[a.spellId]) or a.name == DRINK_NAME then
            hasDrinkBuff = true
            break
        end
    end
end

local ticker = nil

-- The hot events (mana updates + CLEU energize watch) only feed the tick
-- clock, which only matters while the bar runs; bound below the event frame.
local RegisterHotEvents, UnregisterHotEvents

local function Tick()
    local cfg = DT.Store()
    if not cfg or not cfg.enabled or not isManaUser then
        if bar then bar:Hide() end
        return
    end
    BuildBar()
    if not bar then return end
    -- a setting changed since the last pass: restyle
    if bar._serial ~= HUD.serial then
        bar._serial = HUD.serial
        DT.StyleBar(bar, cfg)
    end
    ScanDrinkBuff()

    local show
    if cfg.showMode == "always" then
        show = true
    elseif cfg.showMode == "combatHide" then
        show = not (InCombatLockdown() or UnitAffectingCombat("player"))
    else -- smart: show while drinking or mana not full
        local cur, max = UnitPower("player", 0), UnitPowerMax("player", 0)
        if Hidden(cur) or Hidden(max) then
            show = true   -- hidden (WoW Forever): can't tell full from not, so show it
        else
            show = hasDrinkBuff or (max > 0 and cur < max)
        end
    end
    SetBarShown(show and true or false)
end

local function StartTicker()
    if ticker then return end
    ticker = HUD.Ticker(0.5, Tick)
    if RegisterHotEvents then RegisterHotEvents() end
end

local function StopTicker()
    if ticker then ticker:Cancel() ticker = nil end
    if UnregisterHotEvents then UnregisterHotEvents() end
    if bar then bar:Hide() end
end

function DT:SetEnabled(on)
    local cfg = DT.Store()
    if cfg then cfg.enabled = on and true or false end
    if on and isManaUser then StartTicker() else StopTicker() end
end

-- Events
local MANA_CLASSES = {
    PALADIN = true, PRIEST = true, MAGE = true, WARLOCK = true,
    DRUID = true, SHAMAN = true, HUNTER = true,
}

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")

-- Hot events live only while the ticker runs (StartTicker/StopTicker).
local function OnPlayerAuras() auraDirty = true end   -- the 0.5 s tick reads it
RegisterHotEvents = function()
    lastMana = UnitPower("player", 0) or 0
    if Hidden(lastMana) then lastMana = nil end
    auraDirty = true
    ev:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    ns.PlayerAuras.On("DrinkTicker", OnPlayerAuras)
    ns.CLEU.On("DrinkTicker", ENERGIZE_EVENTS, OnCombatLogEvent)
end
UnregisterHotEvents = function()
    ev:UnregisterEvent("UNIT_POWER_UPDATE")
    ns.PlayerAuras.On("DrinkTicker", nil)
    ns.CLEU.Off("DrinkTicker")
end

ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        local _, class = UnitClass("player")
        isManaUser = MANA_CLASSES[class] and true or false
        if not isManaUser then
            ev:UnregisterAllEvents()
            return
        end
        playerGUID = UnitGUID("player")
        -- UNIT_POWER_UPDATE, the aura notice and the energize watch
        -- register in StartTicker, only while enabled.
        local cfg = DT.Store()
        if cfg and cfg.enabled then StartTicker() end
    elseif event == "UNIT_POWER_UPDATE" then
        OnPowerUpdate()
    end
end)

-- Settings page (mana classes only; melee never see it).
local MODE_LABELS = {
    smart = "Smart (drinking or mana missing)",
    always = "Always visible",
    combatHide = "Hide in combat",
}
local MODE_ITEMS = {
    { text = MODE_LABELS.smart,      value = "smart" },
    { text = MODE_LABELS.always,     value = "always" },
    { text = MODE_LABELS.combatHide, value = "combatHide" },
}

-- The preview: one bar on the canvas, made by DT.MakeBar and styled by
-- DT.StyleBar, ticking on its own made-up clock while the dock is shown.
local function PreviewSpec()
    return {
        key = "hud.drinkticker", title = "Drink Ticker",
        width = 300, height = 70,
        build = function(canvas, P)
            local t0 = GetTime() - 0.6
            -- on the stage, so the fitting can shrink a bar wider than the canvas
            P.store.bar = DT.MakeBar(HUD.SampleStage(canvas), function() return t0 end)
        end,
        update = function(canvas, P)
            local b, cfg = P.store.bar, DT.Store()
            if not (b and cfg) then return end
            HUD.CheckLook()
            DT.StyleBar(b, cfg)
            b:Show()
        end,
        replay = function(canvas, P)
            local b, cfg = P.store.bar, DT.Store()
            if not (b and cfg and ns.Motion) then return end
            ns.Motion.Stop(b)
            b:Hide()
            ns.Motion.Play(b, cfg.showAnim, "in")
        end,
    }
end

local POS_ITEMS = {
    { text = "Left", value = "LEFT" }, { text = "Centre", value = "CENTER" }, { text = "Right", value = "RIGHT" },
}
local POS_LABELS = { LEFT = "Left", CENTER = "Centre", RIGHT = "Right" }

local function Tab_General(L, cfg)
    L:Card("Drink Ticker")
    L:Desc("Bar synced to the server's 2-second mana tick. Stand up "
        .. "from drinking right as it fills to keep the final tick "
        .. "(drink-walking). All mana classes.")
    HUD.Check(L, "Enable drink ticker", cfg.enabled, function(v)
        DT:SetEnabled(v)
    end)
    HUD.Dropdown(L, 260, MODE_ITEMS,
        function() return MODE_LABELS[cfg.showMode] or MODE_LABELS.smart end,
        function(value)
            cfg.showMode = value
        end,
        "When the bar is shown.")
    L:EndCard()
end

local function Tab_Look(L, cfg)
    L:Card("Bar")
    HUD.Slider(L, "Width", 80, 400, cfg.w, function(v)
        cfg.w = v
        DT.ApplySizes()
    end, { width = 250, format = function(v) return v .. " px" end })
    HUD.Slider(L, "Height", 4, 30, cfg.h, function(v)
        cfg.h = v
        DT.ApplySizes()
    end, { width = 250, format = function(v) return v .. " px" end })
    local c = UI.ColorPicker(L.current, { label = "Bar colour", alpha = true,
        get = function() return HUD.Col(cfg.color, DEFAULTS.color) end,
        set = function(r, g, b, a) cfg.color = { r = r, g = g, b = b, a = a or 1 } DT.ApplySizes() end })
    L:Add(c, 6)
    L:EndCard()
    HUD.SharedLookCards(L)
end

local function Tab_Text(L, cfg)
    L:Card("Label")
    HUD.Check(L, "Show the label", cfg.label, function(v)
        cfg.label = v
        DT.ApplySizes()
    end)
    HUD.Label(L, "Label text")
    local eb = UI.EditBox(L.current, { width = 200, text = cfg.labelText or "Drink", hint = "Drink",
        onEnter = function(text)
            text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
            cfg.labelText = (text ~= "") and text or "Drink"
            DT.ApplySizes()
        end })
    L:Row(eb, UI.M.EDIT_H + 8)
    L:Desc("Press Enter to keep it.")
    HUD.Slider(L, "Label size", 6, 24, tonumber(cfg.labelSize) or 10, function(v)
        cfg.labelSize = v
        DT.ApplySizes()
    end, { width = 250, format = function(v) return v .. " px" end })
    HUD.Dropdown(L, 160, POS_ITEMS,
        function() return POS_LABELS[cfg.labelPos or "LEFT"] or "Left" end,
        function(v) cfg.labelPos = v DT.ApplySizes() end, "Where the label sits on the bar.")
    local c = UI.ColorPicker(L.current, { label = "Label colour", alpha = true,
        get = function() return HUD.Col(cfg.labelColor, DEFAULTS.labelColor) end,
        set = function(r, g, b, a) cfg.labelColor = { r = r, g = g, b = b, a = a or 1 } DT.ApplySizes() end })
    L:Add(c, 6)
    L:EndCard()
    HUD.SharedTextCards(L)
end

local function Tab_Anim(L, cfg)
    L:Card("Showing and hiding")
    L:Desc("How the bar comes up when you start drinking (or lose mana) and goes when it is no "
        .. "longer needed. None is how it has always been.")
    local sp = UI.AnimationPicker(L.current, { label = "When it appears",
        get = function() return cfg.showAnim end, set = function(spec) cfg.showAnim = spec end })
    L:Add(sp, 6)
    local hp = UI.AnimationPicker(L.current, { label = "When it goes", styles = HUD.EXIT_STYLES,
        get = function() return cfg.hideAnim end, set = function(spec) cfg.hideAnim = spec end })
    L:Add(hp, 6)
    L:EndCard()
    L:Card("Polish")
    HUD.MotionCheck(L)
    L:EndCard()
end

local function Tab_Position(L, cfg)
    L:Card("Position")
    HUD.Button(L, "Unlock / lock the bar", 150, function()
        HUD.ToggleMovers("drinkTicker")
    end, "Also on ZacUI's Movers page and in Edit Mode.")
    L:EndCard()
end

local function Tab_Advanced(L, cfg)
    L:Card("Reset")
    HUD.Button(L, "Reset the look", 150, function()
        cfg.color = ns.CopySetting(DEFAULTS.color)
        cfg.labelColor = ns.CopySetting(DEFAULTS.labelColor)
        cfg.labelText, cfg.labelSize, cfg.labelPos = "Drink", 10, "LEFT"
        cfg.showAnim, cfg.hideAnim = ns.CopySetting(DEFAULTS.showAnim), ns.CopySetting(DEFAULTS.hideAnim)
        DT.ApplySizes()
        ns.SettingsChanged("reset")
        HUD.RefreshPage()
    end, "Colours, label and animations back to the defaults (size and place stay).")
    L:EndCard()
end

local function BuildPage(L)
    L:Header("Drink Ticker",
        "A bar synced to the server's 2-second mana tick, for drink-walking")
    local cfg = DT.Store()
    if not cfg then
        L:Notice("missing", "The Drink Ticker settings are not available yet.")
        return
    end
    -- fitted after every update: in the dock's strata, inside the canvas
    L:Preview(HUD.FitSpec(PreviewSpec()))
    L:Tabs({
        { id = "general", label = "General",   build = function(L2) Tab_General(L2, cfg) end },
        { id = "look",    label = "Look",      build = function(L2) Tab_Look(L2, cfg) end },
        { id = "text",    label = "Text",      build = function(L2) Tab_Text(L2, cfg) end },
        { id = "anim",    label = "Animation", build = function(L2) Tab_Anim(L2, cfg) end },
        { id = "pos",     label = "Position",  build = function(L2) Tab_Position(L2, cfg) end },
        { id = "adv",     label = "Advanced",  build = function(L2) Tab_Advanced(L2, cfg) end },
    })
end

HUD.RegisterPage("drinkticker", "Drink Ticker",
    "drink ticker mana tick mp5 drink walk drink walking label " .. HUD.PAGE_KEYWORDS,
    MANA_CLASSES,
    BuildPage)
