-- HUD_Priest - the Priest HUD: native port of a Priest UI
-- WeakAura pack (a different author), re-expressed in the Warrior/Paladin
-- HUD framework: the WA's per-spec bars become one cooldown grid with
-- per-icon toggles, plus target debuffs (own only), reminders, and
-- mana / five-second-rule / wand bars.
-- Part of ZacUI; load order is set by the TOC.
-- Perf rules: events set flags/timestamps only; scans in the 0.2s core
-- ticker; countdown texts on the 0.1s text ticker.
local ADDON_NAME = ...
-- Zacui_HUD is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end
local HUD = ns.HUD
local UI = ns.UI
local Print = ns.Print

ns.PriestHUD = ns.PriestHUD or {}
local PR = ns.PriestHUD

-- API compat shims come from HUD_Shared.
local GetSpellInfo       = HUD.GetSpellInfo
local CompatUnitAura     = HUD.UnitAura
local GetSpellCooldown_C = HUD.GetSpellCooldown
local IsUsableSpell_C    = HUD.IsUsableSpell
local IsSpellInRange_C   = HUD.IsSpellInRange
local GetSpellTexture_C  = HUD.GetSpellTexture
local GetItemCount_C     = HUD.GetItemCount

-- Storage: ZacUIDB.hud.priest
local DEFAULTS = {
    enabled = false,
    mainRow = {
        x = 0, y = -208, scale = 1,
        rows = {
            { limit = 7, w = 30, h = 30 },
            { limit = 9, w = 25, h = 25 },
            { limit = 8, w = 25, h = 25 },
        },
        spacing = 4,
        hidden = {},
        potionChoice = 1,
    },
    debuffRow = {
        enabled = true,
        x = 0, y = -120, iconSize = 26, spacing = 4,
        hidden = {},
    },
    reminders = {
        enabled = true,
        x = 0, y = 150, iconSize = 40, spacing = 6,
        innerFire = true, fort = true, spirit = true,
        shadowform = false, candles = true,
    },
    resources = {
        manaBar = true,
        fsrBar  = true,
        wandBar = true,
        mana = { x = 0, y = -183, w = 300, h = 8 },
        wand = { x = 0, y = -196, w = 300, h = 8 },
    },
}

function PR.Store()
    return HUD.Store("priest", DEFAULTS)
end

-- Static data (from the decoded WA)
local SPELL_IDS = {
    pws          = 17,    innerFocus  = 14751, fade         = 586,
    psychicScream = 8122, mindBlast   = 8092,  silence      = 15487,
    vampiric     = 15286, devouring   = 2944,  desperate    = 13908,
    fearWard     = 6346,  feedback    = 13896, powerInfusion = 10060,
    lightwell    = 724,   shackle     = 9484,  swp          = 589,
    hexWeakness  = 9035,  innerFire   = 588,   fortitude    = 1243,
    divineSpirit = 14752, shadowform  = 15473, mindFlay     = 15407,
}

-- Target debuff row (WA "Priest - Debuffs", own debuffs only)
local DEBUFF_DEFS = {
    { key = "swp",          id = 589,   label = "Shadow Word: Pain" },
    { key = "hexWeakness",  id = 9035,  label = "Hex of Weakness" },
    { key = "devouring",    id = 2944,  label = "Devouring Plague" },
    { key = "psychicScream", id = 8122, label = "Psychic Scream" },
    { key = "vampiric",     id = 15286, label = "Vampiric Embrace" },
    { key = "shackle",      id = 9484,  label = "Shackle Undead" },
}

-- Grenade priority (WA Engi Nade custom list)
local NADE_LIST = {
    { id = 18641, icon = 133714 }, -- Dense Dynamite
    { id = 15993, icon = 133716 }, -- Thorium Grenade
    { id = 4390,  icon = 133716 }, -- Iron Grenade
    { id = 10507, icon = 133714 }, -- Solid Dynamite
}
local SAPPER_ID = 10646
local CANDLE_LOW  = 17028          -- Holy Candle
local CANDLE_HIGH = 17029          -- Sacred Candle
local SHOOT_ID = 5019              -- wand Shoot

-- One spell id per race; only the id matching the player's own race
-- resolves a name, so ResolveSpells' first hit is the only hit.
local RACIAL_IDS = { 20594, 20589, 20600, 20580, 7744, 20554 }

local RED_OOR = { 1, 0.2431, 0.2275 }
local GOLD_COUNT = { 1, 0.82, 0, 1 }
local MANA_BLUE = { 0, 0.44, 0.87 }
local FSR_RED   = { 1, 0, 0 }               -- WA five-second-rule color
local WAND_CYAN = { 0.7373, 1, 0.9765 }     -- WA wand bar color

local HUD_STRATA = "MEDIUM"

-- Live state
PR.State = {
    isPriest  = false,
    inCombat  = false,
    spells    = {},
    cds       = {},
    usable    = {},
    inRange   = {},
    buffs     = {},        -- player HELPFUL by lower(name)
    targetDebuffs = {},    -- MY debuffs on target by lower(name)
    targetAttackable = false,
    fsr       = { start = 0, duration = 0 },  -- five-second rule / tick
    wand      = { start = 0, duration = 0, active = false },
    items     = {},
    racial    = nil,
    candles   = 0,
}
local S = PR.State

local dirty = { auras = true, targetAuras = true, bags = true, spells = true }
local playerGUID = nil

-- Resolution + scans
local WH = ns.WarriorHUD

local function ResolveSpells()
    for key, id in pairs(SPELL_IDS) do
        local name = GetSpellInfo and GetSpellInfo(id) or nil
        local known, icon = false, nil
        if name then
            local n2, _, tex = GetSpellInfo(name)
            known = n2 ~= nil
            icon = tex or (GetSpellTexture_C and GetSpellTexture_C(id))
        end
        S.spells[key] = { name = name, known = known, icon = icon }
    end
    S.racial = nil
    for _, id in ipairs(RACIAL_IDS) do
        local name = GetSpellInfo and GetSpellInfo(id) or nil
        if name then
            local n2, _, tex = GetSpellInfo(name)
            if n2 then
                S.racial = { name = name, icon = tex }
                break
            end
        end
    end
end

-- The entry for an aura name is kept between scans and its fields
-- rewritten (first application wins, as before); a scan runs up to five
-- times a second in a fight and used to make a fresh table per aura.
-- Entries not seen this pass are dropped afterwards, so a reader finds
-- exactly what a rebuilt table would hold.
local scanPass = 0
local function PutAura(out, lname, pass, name, icon, count, duration, expirationTime)
    local e = out[lname]
    if e and e.pass == pass then return end
    if not e then
        e = {}
        out[lname] = e
    end
    e.pass = pass
    e.name, e.icon, e.count, e.duration, e.expirationTime = name, icon, count, duration, expirationTime
end
local function DropUnseen(out, pass)
    for lname, e in pairs(out) do
        if e.pass ~= pass then out[lname] = nil end
    end
end

-- the player's buffs come from ZacUI's shared read (ns.PlayerAuras)
local function ScanPlayerBuffs()
    scanPass = scanPass + 1
    local pass = scanPass
    local list = ns.PlayerAuras.Buffs()
    for i = 1, #list do
        local a = list[i]
        if a.name then
            PutAura(S.buffs, a.name:lower(), pass, a.name, a.icon, a.count, a.duration, a.expirationTime)
        end
    end
    DropUnseen(S.buffs, pass)
end

local function ScanTargetDebuffs()
    scanPass = scanPass + 1
    local pass = scanPass
    if UnitExists("target") then
        for i = 1, 40 do
            local name, icon, count, _, duration, expirationTime, source =
                CompatUnitAura("target", i, "HARMFUL")
            if not name then break end
            if source == "player" then
                PutAura(S.targetDebuffs, name:lower(), pass, name, icon, count, duration, expirationTime)
            end
        end
    end
    DropUnseen(S.targetDebuffs, pass)
end

local function ScanItems()
    wipe(S.items)
    local lists = { NADE_LIST }
    if WH and WH.POTION_LIST then lists[#lists + 1] = WH.POTION_LIST end
    for _, list in ipairs(lists) do
        for _, e in ipairs(list) do
            if S.items[e.id] == nil and GetItemCount_C then
                S.items[e.id] = GetItemCount_C(e.id) or 0
            end
        end
    end
    if GetItemCount_C then
        S.items[SAPPER_ID] = GetItemCount_C(SAPPER_ID) or 0
        S.candles = (GetItemCount_C(CANDLE_HIGH) or 0) + (GetItemCount_C(CANDLE_LOW) or 0)
    end
end

-- First item in the list with count > 0 wins; list order is priority.
local function FirstAvailable(list)
    for _, e in ipairs(list) do
        if (S.items[e.id] or 0) > 0 then return e, S.items[e.id] end
    end
    return nil, 0
end

-- GetItemCooldown is retail-only; Classic Era reads item cooldowns by
-- bag/slot. Shared cached tracker (same idea as the Warrior HUD core's
-- ScanBags cache): slots are found once and reused every tick, and the
-- cache is invalidated on BAG_UPDATE_DELAYED instead of re-scanning all
-- bags per icon per tick.
local itemCD = HUD.NewItemCDTracker()
local FindItemCooldown = itemCD.Get

-- Classic's GCD is ~1.5s; the small margin excludes pure-GCD cooldowns
-- from the desat/swipe/text logic below.
local GCD_MAX = 1.51

local function UpdateSpellSnapshot()
    for key, sp in pairs(S.spells) do
        if sp.known and sp.name then
            local start, duration = GetSpellCooldown_C(sp.name)
            start, duration = start or 0, duration or 0
            local cd = S.cds[key]
            if not cd then cd = {} S.cds[key] = cd end
            cd.start, cd.duration = start, duration
            cd.real = duration > GCD_MAX
            local us = S.usable[key]
            if not us then us = {} S.usable[key] = us end
            if IsUsableSpell_C then
                local usable, noPower = IsUsableSpell_C(sp.name)
                us.usable, us.noPower = usable and true or false, noPower and true or false
            else
                us.usable, us.noPower = true, false
            end
            if S.targetAttackable and IsSpellInRange_C then
                S.inRange[key] = IsSpellInRange_C(sp.name, "target")
            else
                S.inRange[key] = nil
            end
        end
    end
end

local function UpdateMisc()
    S.targetAttackable = (UnitExists("target") and UnitCanAttack("player", "target")
        and not UnitIsDeadOrGhost("target")) and true or false
end

-- Events: five-second rule + wand (timestamp writes only)
local lastMana = 0
local fsrCastAt = -10

local function OnManaEvent(event, spellId)
    local cur = UnitPower("player", 0) or 0
    if event == "UNIT_POWER_FREQUENT" then
        if cur >= (UnitPowerMax("player", 0) or 0) then
            lastMana = cur
            return
        end
        -- Regen ticks only after the 5s rule, not while hardcasting (same rule as the paladin bar).
        if cur > lastMana and GetTime() >= fsrCastAt + 5
            and not (UnitCastingInfo and UnitCastingInfo("player")) then
            S.fsr.start, S.fsr.duration = GetTime(), 2
        end
        lastMana = cur
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Wand tracking (Shoot restarts the swing bar at ranged speed)
        if spellId == SHOOT_ID then
            local speed = UnitRangedDamage and UnitRangedDamage("player") or 0
            if S.wand.active and speed and speed > 0 then
                S.wand.start, S.wand.duration = GetTime(), speed
            end
        end
        if cur < lastMana then
            S.fsr.start, S.fsr.duration = GetTime(), 5
            fsrCastAt = GetTime()
        end
        lastMana = cur
    end
end

-- Display: anchors. Each anchor sits centred on an UNSCALED holder; the
-- holder is what ZacUI's mover registry positions, so a scaled anchor
-- still reports plain UIParent offsets when dragged.
local W

local holders = {}
local function MakeAnchor(key, w, h)
    local holder = CreateFrame("Frame", "ZacUIHUD_Priest_" .. key .. "_Holder", UIParent)
    holder:SetSize(w or 26, h or 26)
    holder:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    local f = CreateFrame("Frame", "ZacUIHUD_Priest_" .. key, holder)
    f:SetSize(w or 26, h or 26)
    f:SetFrameStrata(HUD_STRATA)
    f:SetPoint("CENTER", holder, "CENTER", 0, 0)
    holders[key] = holder
    return f
end

-- The colours the HUD draws with, as settings (Look tab); the defaults
-- are the WeakAura's.
local COLOR_DEFAULTS = {
    oor = HUD.RGBA(RED_OOR), count = HUD.RGBA(GOLD_COUNT),
    timer = { r = 1, g = 1, b = 1, a = 1 }, barText = { r = 1, g = 1, b = 1, a = 1 },
    mana = HUD.RGBA(MANA_BLUE), fsr = HUD.RGBA(FSR_RED), wand = HUD.RGBA(WAND_CYAN),
}
DEFAULTS.colors = COLOR_DEFAULTS

-- A VIEW is one drawn copy of the HUD: its anchors, icons, bars and the
-- state it draws from. LIVE is the one on screen; the settings preview
-- makes another on its canvas (V.sample) from made-up state, through the
-- very same Build / Refresh functions below.
local function NewView(state)
    return {
        S = state,
        memo = { main = {}, debuff = {}, remind = {} },
        mainIcons = {}, mainActive = {}, debuffIcons = {}, debuffActive = {}, remindIcons = {},
    }
end
local LIVE = NewView(S)
PR.LIVE = LIVE

-- The named anchor frames exist only for priests: on any other class
-- nothing in this file ever shows, so creating them would just park
-- named frames in the frame census forever.
local IS_PRIEST = select(2, UnitClass("player")) == "PRIEST"
if IS_PRIEST then
    LIVE.Main      = MakeAnchor("Main", 30, 30)
    LIVE.Debuffs   = MakeAnchor("Debuffs", 26, 26)
    LIVE.Reminders = MakeAnchor("Reminders", 40, 40)
    LIVE.Mana      = MakeAnchor("Mana", 300, 8)
    LIVE.Wand      = MakeAnchor("Wand", 300, 8)
    -- Invisible handle: dragging it in the UI mover moves the WHOLE HUD.
    LIVE.GroupHandle = MakeAnchor("GroupHandle", 170, 24)
end

local function ApplyAnchorPositions()
    if not LIVE.Main then return end      -- non-priest: no anchors exist
    local cfg = PR.Store()
    if not cfg then return end
    HUD.PlaceAnchor("prMainRow", holders.Main, cfg.mainRow)
    HUD.PlaceAnchor("prDebuffs", holders.Debuffs, cfg.debuffRow)
    HUD.PlaceAnchor("prReminders", holders.Reminders, cfg.reminders)
    HUD.PlaceAnchor("prMana", holders.Mana, cfg.resources.mana)
    HUD.PlaceAnchor("prWand", holders.Wand, cfg.resources.wand)
    if cfg.group then HUD.PlaceAnchor("prGroup", holders.GroupHandle, cfg.group) end
    LIVE.Main:SetScale(cfg.mainRow.scale or 1)
end

local function RegisterMovers()
    -- No priest mover entries cluttering move mode on other classes.
    local _, playerClass = UnitClass("player")
    if playerClass ~= "PRIEST" then return end
    local cfg = PR.Store()
    if not cfg then
        C_Timer.After(1, RegisterMovers)   -- saved vars not ready yet
        return
    end
    HUD.RegisterMover("prMainRow", "Priest HUD Cooldown Grid", holders.Main, cfg.mainRow)
    HUD.RegisterMover("prDebuffs", "Priest HUD Target Debuffs", holders.Debuffs, cfg.debuffRow)
    HUD.RegisterMover("prReminders", "Priest HUD Reminders", holders.Reminders, cfg.reminders)
    HUD.RegisterMover("prMana", "Priest HUD Mana + FSR", holders.Mana, cfg.resources.mana)
    HUD.RegisterMover("prWand", "Priest HUD Wand Bar", holders.Wand, cfg.resources.wand)

    -- Whole-HUD mover: dragging the handle shifts every member anchor by
    -- the same delta (HUD_Shared carries the delta to the members).
    cfg.group = cfg.group or { x = (cfg.mainRow.x or 0),
                               y = (cfg.mainRow.y or -208) + 50 }
    HUD.PlaceAnchor("prGroup", holders.GroupHandle, cfg.group)
    HUD.RegisterGroup("prGroup", "Priest HUD: move all", holders.GroupHandle, cfg.group, {
        { key = "prMainRow",   holder = holders.Main },
        { key = "prDebuffs",   holder = holders.Debuffs },
        { key = "prReminders", holder = holders.Reminders },
        { key = "prMana",      holder = holders.Mana },
        { key = "prWand",      holder = holders.Wand },
    })
    HUD.Debug("PriestHUD anchors registered with the mover registry")
end
C_Timer.After(2, function()
    ApplyAnchorPositions()
    RegisterMovers()
end)

-- Main grid definitions
-- Order here matches the WA's child order, which sets fill order in the grid.
local MAIN_DEFS = {
    { key = "pws",          kind = "spell", spell = "pws",          label = "Power Word: Shield" },
    { key = "innerFocus",   kind = "spell", spell = "innerFocus",   label = "Inner Focus", noRange = true },
    { key = "fade",         kind = "spell", spell = "fade",         label = "Fade", noRange = true },
    { key = "psychicScream", kind = "spell", spell = "psychicScream", label = "Psychic Scream", noRange = true },
    { key = "mindBlast",    kind = "spell", spell = "mindBlast",    label = "Mind Blast" },
    { key = "silence",      kind = "spell", spell = "silence",      label = "Silence" },
    { key = "vampiric",     kind = "spell", spell = "vampiric",     label = "Vampiric Embrace" },
    { key = "devouring",    kind = "spell", spell = "devouring",    label = "Devouring Plague" },
    { key = "desperate",    kind = "spell", spell = "desperate",    label = "Desperate Prayer", noRange = true },
    { key = "fearWard",     kind = "spell", spell = "fearWard",     label = "Fear Ward" },
    { key = "feedback",     kind = "spell", spell = "feedback",     label = "Feedback", noRange = true },
    { key = "powerInfusion", kind = "spell", spell = "powerInfusion", label = "Power Infusion" },
    { key = "lightwell",    kind = "spell", spell = "lightwell",    label = "Lightwell", noRange = true },
    { key = "racial",       kind = "racial", label = "Racial" },
    { key = "potion",       kind = "itemPotion", label = "Potion" },
    { key = "nade",         kind = "itemNade",   label = "Dynamite/Grenade" },
    { key = "sapper",       kind = "itemSapper", label = "Sapper" },
}
PR.MainIconList = MAIN_DEFS

-- The colour settings as { r, g, b, a } arrays, onto every piece of one
-- view that carries one; re-read whenever any setting changed.
local function Colors(V)
    if V.col and V._serial == HUD.serial then return V.col end
    local cfg = PR.Store()
    local src = (cfg and cfg.colors) or COLOR_DEFAULTS
    local col = {}
    for k, d in pairs(COLOR_DEFAULTS) do
        local r, g, b, a = HUD.Col(src[k], d)
        col[k] = { r, g, b, a }
    end
    V.col, V._serial = col, HUD.serial
    if V.built then
        if V.manaBar then
            V.manaBar:SetBarColor(unpack(col.mana))
            V.manaBar.text:SetTextColor(unpack(col.barText))
        end
        if V.fsrBar then V.fsrBar:SetBarColor(unpack(col.fsr)) end
        if V.wandBar then V.wandBar:SetBarColor(unpack(col.wand)) end
        for _, set in ipairs({ V.mainIcons, V.remindIcons }) do
            for _, icon in pairs(set) do
                local t = icon.texts
                if t.p then t.p:SetTextColor(unpack(col.timer)) end
                if t.count then t.count:SetTextColor(unpack(col.count)) end
            end
        end
    end
    return col
end

local function BuildMainIcons(V)
    for _, def in ipairs(MAIN_DEFS) do
        local icon = W.CreateIcon(V.Main, {
            width = 30, height = 30, zoom = W.ICON_ZOOM, keepAspect = true,
            inverse = true,
        })
        icon:SetFrameStrata(HUD_STRATA)
        icon:Hide()
        icon.def = def
        icon:AddText("p", "CENTER", 14, { 1, 1, 1, 1 })
        icon:SetText("p", "")
        if def.kind == "itemPotion" or def.kind == "itemNade" or def.kind == "itemSapper" then
            icon:AddText("count", "INNER_BOTTOMRIGHT", 12, GOLD_COUNT, 0, 0)
        end
        V.mainIcons[def.key] = icon
    end
end

local function BuildDebuffIcons(V)
    local cfg = PR.Store()
    local size = (cfg and cfg.debuffRow.iconSize) or 26
    for _, def in ipairs(DEBUFF_DEFS) do
        local icon = W.CreateIcon(V.Debuffs, {
            width = size, height = size, zoom = W.ICON_ZOOM, keepAspect = true,
            inverse = true,
        })
        icon:SetFrameStrata(HUD_STRATA)
        icon:Hide()
        icon.def = def
        V.debuffIcons[def.key] = icon
    end
end

-- Reminder icons: shown when something is missing (the WA's 46x46 reminder group).
local REMIND_DEFS = {
    { key = "innerFire",  option = "innerFire",  spell = "innerFire",
      label = "Inner Fire missing/expiring" },
    { key = "fort",       option = "fort",       spell = "fortitude",
      label = "Fortitude missing (self)" },
    { key = "spirit",     option = "spirit",     spell = "divineSpirit",
      label = "Divine Spirit missing (self)" },
    { key = "shadowform", option = "shadowform", spell = "shadowform",
      label = "Shadowform reminder" },
    { key = "candles",    option = "candles",
      label = "Low on candles (<10)" },
}
PR.ReminderList = REMIND_DEFS

local function BuildReminders(V)
    local cfg = PR.Store()
    local size = (cfg and cfg.reminders.iconSize) or 40
    for _, def in ipairs(REMIND_DEFS) do
        local icon = W.CreateIcon(V.Reminders, {
            width = size, height = size, zoom = W.ICON_ZOOM, keepAspect = true,
            noCooldown = true,
        })
        icon:SetFrameStrata(HUD_STRATA)
        icon:Hide()
        icon.def = def
        if def.key == "candles" then
            icon:AddText("count", "INNER_BOTTOMRIGHT", 12, GOLD_COUNT, 0, 0)
        end
        V.remindIcons[def.key] = icon
    end
end

local function BuildBars(V)
    local cfg = PR.Store()
    local r = cfg and cfg.resources or DEFAULTS.resources
    local VS = V.S
    local col = Colors(V)

    local manaBar = W.CreateBar(V.Mana, { width = r.mana.w, height = r.mana.h,
        barColor = col.mana })
    manaBar:SetFrameStrata(HUD_STRATA)
    manaBar:SetPoint("CENTER", V.Mana, "CENTER", 0, 0)
    -- Created on the StatusBar so it draws above the fill texture.
    local mt = HUD.Text(manaBar.bar, 10, "OUTLINE", "OVERLAY", "text")
    mt:SetPoint("CENTER", manaBar, "CENTER", 0, 0)
    mt:SetTextColor(1, 1, 1)
    manaBar.text = mt
    if HUD.BarText then HUD.BarText(mt, manaBar) end
    if V.sample then manaBar.readMana = function() return VS.mana or 0, VS.manaMax or 1 end end
    manaBar:SetScript("OnUpdate", HUD.ManaBarOnUpdate)
    manaBar:Hide()
    V.manaBar = manaBar

    -- FSR/tick bar: thin red drain directly under the mana bar
    local fsrBar = W.CreateBar(V.Mana, { width = r.mana.w, height = 3,
        barColor = col.fsr })
    fsrBar:SetFrameStrata(HUD_STRATA)
    fsrBar:SetPoint("TOP", manaBar, "BOTTOM", 0, -1)
    fsrBar:SetScript("OnUpdate", function(self)
        if V.preview then
            self.bar:SetValue(0.65)
            return
        end
        local dur = VS.fsr.duration or 0
        if dur <= 0 then
            self.bar:SetValue(0)
            return
        end
        local remaining = VS.fsr.start + dur - GetTime()
        -- the preview's sample runs its made-up window round and round
        if V.sample and remaining <= 0 then
            VS.fsr.start = GetTime()
            remaining = dur
        end
        self.bar:SetValue(remaining > 0 and (remaining / dur) or 0)
    end)
    fsrBar:Hide()
    V.fsrBar = fsrBar

    local wandBar = W.CreateBar(V.Wand, { width = r.wand.w, height = r.wand.h,
        spark = true, barColor = col.wand })
    wandBar:SetFrameStrata(HUD_STRATA)
    wandBar:SetPoint("CENTER", V.Wand, "CENTER", 0, 0)
    wandBar:SetScript("OnUpdate", function(self)
        if V.preview then
            self.bar:SetValue(0.65)
            if self.UpdateSpark then self:UpdateSpark(0.65) end
            return
        end
        local dur = VS.wand.duration or 0
        local remaining = dur > 0 and (VS.wand.start + dur - GetTime()) or 0
        if V.sample and dur > 0 and remaining <= 0 then
            VS.wand.start = GetTime()
            remaining = dur
        end
        local frac = (remaining > 0 and dur > 0) and (remaining / dur) or 0
        self.bar:SetValue(frac)
        if self.UpdateSpark then self:UpdateSpark(frac) end
    end)
    wandBar:Hide()
    V.wandBar = wandBar
end

-- Layouts: HUD.LayoutGrid / HUD.LayoutRow (HUD_Shared), laid out again
-- only when the shown icons or the sizes change.

-- The reads a sample answers from its own made-up state.
local function ItemCD(V, id)
    if V.sample then
        local c = V.S.itemCDs and V.S.itemCDs[id]
        if c then return c.start, c.duration end
        return 0, 0
    end
    return FindItemCooldown(id)
end

local function RacialCD(V)
    local rc = V.S.racial
    if not rc then return 0, 0 end
    if V.sample then return rc.start or 0, rc.duration or 0 end
    local start, duration = GetSpellCooldown_C(rc.name)
    return start or 0, duration or 0
end

local function FirstIn(V, list)
    for _, e in ipairs(list) do
        if (V.S.items[e.id] or 0) > 0 then return e, V.S.items[e.id] end
    end
    return nil, 0
end

-- Refresh
local function UpdateMainIcon(V, icon, def)
    local VS = V.S
    if def.kind == "spell" then
        local sp = VS.spells[def.spell]
        if not (sp and sp.known) then return false end
        local cd = VS.cds[def.spell]
        local us = VS.usable[def.spell] or {}
        local inRange = (not def.noRange) and VS.inRange[def.spell] or nil
        icon:SetIconTexture(sp.icon)
        if cd then icon:SetSwipe(cd.start, cd.duration) end
        local desat = (cd and cd.real) or us.noPower or false
        local tint = nil
        if inRange == 0 then
            desat = true
            tint = Colors(V).oor
        end
        icon:SetDesat(desat)
        if tint then
            icon:SetIconColor(tint[1], tint[2], tint[3], tint[4])
        else
            icon:SetIconColor(1, 1, 1, 1)
        end
        return true
    elseif def.kind == "racial" then
        if not VS.racial then return false end
        icon:SetIconTexture(VS.racial.icon)
        local start, duration = RacialCD(V)
        icon:SetSwipe(start, duration)
        icon:SetDesat(duration > GCD_MAX)
        return true
    elseif def.kind == "itemPotion" then
        local cfg = PR.Store()
        local item, count
        local sel = (WH and WH.POTION_DROPDOWN) and WH.POTION_DROPDOWN[cfg.mainRow.potionChoice or 1] or nil
        if sel and (VS.items[sel.id] or 0) > 0 then
            item, count = sel, VS.items[sel.id]
        elseif WH and WH.POTION_LIST then
            item, count = FirstIn(V, WH.POTION_LIST)
        end
        icon.curItem = item
        if not item or count == 0 then return false end
        icon:SetIconTexture(item.icon)
        icon:SetText("count", tostring(count))
        local start, duration = ItemCD(V, item.id)
        icon:SetSwipe(start, duration)
        icon:SetDesat(duration > GCD_MAX)
        return true
    elseif def.kind == "itemNade" then
        local item, count = FirstIn(V, NADE_LIST)
        icon.curItem = item
        if not item or count == 0 then return false end
        icon:SetIconTexture(item.icon)
        icon:SetText("count", tostring(count))
        local start, duration = ItemCD(V, item.id)
        icon:SetSwipe(start, duration)
        icon:SetDesat(duration > GCD_MAX)
        return true
    elseif def.kind == "itemSapper" then
        local count = VS.items[SAPPER_ID] or 0
        if count == 0 then return false end
        icon.curItem = { id = SAPPER_ID }
        icon:SetIconTexture(135826)
        icon:SetText("count", tostring(count))
        local start, duration = ItemCD(V, SAPPER_ID)
        icon:SetSwipe(start, duration)
        icon:SetDesat(duration > GCD_MAX)
        return true
    end
    return false
end

-- the HUD's pieces show while it is on - or always, on the preview's sample
local function On(V, cfg) return (cfg.enabled or V.sample) and true or false end

local function RefreshMainRow(V, cfg)
    local VS = V.S
    wipe(V.mainActive)
    local m = cfg.mainRow
    for _, def in ipairs(MAIN_DEFS) do
        local icon = V.mainIcons[def.key]
        local shown = false
        if On(V, cfg) and not m.hidden[def.key] then
            if V.preview then
                local sp = def.spell and VS.spells[def.spell]
                icon:SetIconTexture((sp and sp.icon)
                    or (def.kind == "racial" and VS.racial and VS.racial.icon)
                    or (def.kind == "itemPotion" and 134856)
                    or (def.kind == "itemNade" and 133714)
                    or (def.kind == "itemSapper" and 135826) or 134400)
                icon:SetDesat(false)
                icon:ClearSwipe()
                shown = (not def.spell) or (sp and sp.known) or false
            else
                shown = UpdateMainIcon(V, icon, def)
            end
        end
        W.SetShownAnimated(icon, shown)
        if shown then V.mainActive[#V.mainActive + 1] = icon end
    end
    HUD.LayoutGrid(V.memo.main, V.mainActive, V.Main, m.rows or DEFAULTS.mainRow.rows,
        m.spacing or 4)
end

local function RefreshDebuffRow(V, cfg)
    local VS = V.S
    wipe(V.debuffActive)
    local d = cfg.debuffRow
    for _, def in ipairs(DEBUFF_DEFS) do
        local icon = V.debuffIcons[def.key]
        local shown = false
        if On(V, cfg) and d.enabled and not d.hidden[def.key] then
            if V.preview then
                local sp = VS.spells[def.key]
                icon:SetIconTexture(sp and sp.icon or 134400)
                icon:ClearSwipe()
                shown = true
            else
                local sp = VS.spells[def.key]
                local name = sp and sp.name
                local b = name and VS.targetDebuffs[name:lower()] or nil
                if b then
                    icon:SetIconTexture(b.icon or (sp and sp.icon))
                    if (b.duration or 0) > 0 then
                        icon:SetSwipe(b.expirationTime - b.duration, b.duration)
                    else
                        icon:ClearSwipe()
                    end
                    shown = true
                end
            end
        end
        W.SetShownAnimated(icon, shown)
        if shown then V.debuffActive[#V.debuffActive + 1] = icon end
    end
    local size = d.iconSize or 26
    HUD.LayoutRow(V.memo.debuff, V.debuffActive, V.Debuffs, size, size, d.spacing or 4)
end

local function BuffUp(V, spellKey)
    local VS = V.S
    local sp = VS.spells[spellKey]
    local name = sp and sp.name
    return name and VS.buffs[name:lower()] or nil
end

local remindShown = {}
local function RefreshReminders(V, cfg)
    local VS = V.S
    local r = cfg.reminders
    local shownList = remindShown
    wipe(shownList)
    for _, def in ipairs(REMIND_DEFS) do
        local icon = V.remindIcons[def.key]
        local shown = false
        if On(V, cfg) and r.enabled and r[def.option] then
            if V.preview or V.sample then
                local sp = def.spell and VS.spells[def.spell]
                icon:SetIconTexture((sp and sp.icon) or 133750)
                shown = (not def.spell) or (sp and sp.known) or false
                if def.key == "candles" then icon:SetText("count", tostring(V.sample and VS.candles or 5)) end
            elseif def.key == "candles" then
                -- Only reminds when the spells that consume candles exist
                local fort = VS.spells.fortitude
                shown = (fort and fort.known and VS.candles > 0 and VS.candles < 10)
                    and true or false
                if shown then
                    icon:SetIconTexture(133750)   -- candle icon
                    icon:SetText("count", tostring(VS.candles))
                end
            else
                local sp = VS.spells[def.spell]
                if sp and sp.known then
                    local b = BuffUp(V, def.spell)
                    if def.key == "innerFire" then
                        -- missing, or expiring under 2 minutes
                        shown = (not b) or ((b.expirationTime or 0) > 0
                            and (b.expirationTime - GetTime()) < 120)
                    elseif def.key == "fort" then
                        local pray = VS.buffs["prayer of fortitude"]
                        shown = not (b or pray)
                    elseif def.key == "spirit" then
                        local pray = VS.buffs["prayer of spirit"]
                        shown = not (b or pray)
                    elseif def.key == "shadowform" then
                        shown = not b
                    end
                    if shown then icon:SetIconTexture(sp.icon) end
                end
            end
        end
        W.SetShownAnimated(icon, shown and true or false)
        if shown then shownList[#shownList + 1] = icon end
    end
    local size = r.iconSize or 40
    HUD.LayoutRow(V.memo.remind, shownList, V.Reminders, size, size, r.spacing or 6)
end

local function RefreshResources(V, cfg)
    local VS = V.S
    local r = cfg.resources
    local show = On(V, cfg)
    V.manaBar:SetShown(show and r.manaBar or false)
    V.fsrBar:SetShown(show and r.fsrBar or false)
    local wandShow = show and r.wandBar and (V.preview or VS.wand.active)
    V.wandBar:SetShown(wandShow or false)
end

-- Builds a view the first time, then redraws it from its state.
local function RefreshView(V)
    if not V.Main then return end         -- non-priest: no anchors exist
    if not W then
        W = ns.WarriorHUD and ns.WarriorHUD.Widgets or nil
        if not W then return end
    end
    if not V.built then
        V.built = true
        BuildMainIcons(V)
        BuildDebuffIcons(V)
        BuildReminders(V)
        BuildBars(V)
        V.col = nil
        if V == LIVE then ApplyAnchorPositions() end
    end
    local cfg = PR.Store()
    if not cfg then return end
    Colors(V)
    RefreshMainRow(V, cfg)
    RefreshDebuffRow(V, cfg)
    RefreshReminders(V, cfg)
    RefreshResources(V, cfg)
end

local function ApplyViewSizes(V, cfg)
    local r = cfg.resources
    -- Holders follow the bar size too: the mover proxy is sized from them.
    if V.manaBar then
        V.manaBar:SetSize(r.mana.w or 300, r.mana.h or 8)
        V.fsrBar:SetSize(r.mana.w or 300, 3)
        V.Mana:SetSize(r.mana.w or 300, (r.mana.h or 8) + 4)
        if V == LIVE then holders.Mana:SetSize(r.mana.w or 300, (r.mana.h or 8) + 4) end
    end
    if V.wandBar then
        V.wandBar:SetSize(r.wand.w or 300, r.wand.h or 8)
        V.Wand:SetSize(r.wand.w or 300, r.wand.h or 8)
        if V == LIVE then holders.Wand:SetSize(r.wand.w or 300, r.wand.h or 8) end
    end
end

-- Display facade
PR.Display = {}

function PR.Display:Refresh()
    RefreshView(LIVE)
end

function PR.Display:HideAll()
    local V = LIVE
    if not V.built then return end
    for _, m in pairs(V.memo) do HUD.ForgetLayout(m) end
    for _, icon in pairs(V.mainIcons) do icon:Hide() end
    for _, icon in pairs(V.debuffIcons) do icon:Hide() end
    for _, icon in pairs(V.remindIcons) do icon:Hide() end
    if V.manaBar then V.manaBar:Hide() end
    if V.fsrBar then V.fsrBar:Hide() end
    if V.wandBar then V.wandBar:Hide() end
end

function PR.Display:ApplySizes()
    if not LIVE.built then return end
    local cfg = PR.Store()
    if not cfg then return end
    ApplyViewSizes(LIVE, cfg)
    ApplyAnchorPositions()
    PR.Display:Refresh()
end

-- Tickers
local textTicker = nil

local function CdRemaining(cd)
    if not cd or not cd.real then return 0 end
    return math.max(0, cd.start + cd.duration - GetTime())
end

local function TextTickView(V)
    local VS = V.S
    for _, icon in ipairs(V.mainActive) do
        local def = icon.def
        if def.kind == "spell" then
            local remaining = CdRemaining(VS.cds[def.spell])
            icon:SetText("p", remaining > 0 and W.FormatTime(remaining, 0) or "")
        elseif def.kind == "racial" and VS.racial then
            local start, duration = RacialCD(V)
            local remaining = 0
            if duration > GCD_MAX then
                remaining = math.max(0, start + duration - GetTime())
            end
            icon:SetText("p", remaining > 0 and W.FormatTime(remaining, 0) or "")
        end
    end
end

local function TextTick()
    if not PR:IsActive() then return end
    TextTickView(LIVE)
end

-- ------------------------------------------------------------
-- The settings preview's sample: a view on the dock's canvas, made-up
-- state, stacked top to bottom (reminders, debuffs, mana, wand, grid).
-- ------------------------------------------------------------
local SAMPLE_W, SAMPLE_H = 500, 112   -- the fitting sizes the canvas to the sample

local function NewSampleView(canvas)
    local VS = {
        inCombat = true, spells = {}, cds = {}, usable = {}, inRange = {}, buffs = {},
        targetDebuffs = {}, targetAttackable = true,
        fsr = { start = 0, duration = 0 }, wand = { start = 0, duration = 0, active = false },
        items = {}, itemCDs = {}, racial = nil, candles = 6,
    }
    local V = NewView(VS)
    V.sample, V.canvas = true, canvas
    V.Main = HUD.SampleAnchor(canvas, 30, 30)
    V.Debuffs = HUD.SampleAnchor(canvas, 26, 26)
    V.Reminders = HUD.SampleAnchor(canvas, 40, 40)
    V.Mana = HUD.SampleAnchor(canvas, 300, 8)
    V.Wand = HUD.SampleAnchor(canvas, 300, 8)
    local tick = CreateFrame("Frame", nil, canvas)
    tick._acc = 0
    tick:SetScript("OnUpdate", function(f, el)
        f._acc = f._acc + (el or 0)
        if f._acc < 0.1 then return end
        f._acc = 0
        if V.built and W then TextTickView(V) end
    end)
    return V
end

local function FillSample(V, mode)
    local VS = V.S
    local now = GetTime()
    local combat = mode ~= "ready"
    VS.inCombat, VS.targetAttackable = combat, combat
    local i = 0
    for key, id in pairs(SPELL_IDS) do
        local name, _, icon = GetSpellInfo and GetSpellInfo(id)
        VS.spells[key] = { name = name or key, known = true,
            icon = icon or (GetSpellTexture_C and GetSpellTexture_C(id)) or 134400 }
    end
    for _, def in ipairs(MAIN_DEFS) do
        if def.kind == "spell" then
            i = i + 1
            local onCd = combat and i % 3 == 2
            VS.cds[def.spell] = { start = onCd and (now - 3 * i) or 0, duration = onCd and (20 + 10 * i) or 0, real = onCd }
            VS.usable[def.spell] = { usable = true, noPower = combat and i == 4 }
            VS.inRange[def.spell] = (combat and i == 5) and 0 or nil
        end
    end
    wipe(VS.targetDebuffs)
    if combat then
        for k, def in ipairs(DEBUFF_DEFS) do
            if k > 3 then break end
            local sp = VS.spells[def.key]
            local n = sp and sp.name or def.label
            VS.targetDebuffs[n:lower()] = { name = n, icon = sp and sp.icon, count = 0,
                duration = 24, expirationTime = now + 24 - 5 * k }
        end
    end
    wipe(VS.items)
    wipe(VS.itemCDs)
    local pot = WH and WH.POTION_LIST and WH.POTION_LIST[1]
    if pot then
        VS.items[pot.id] = 4
        if combat then VS.itemCDs[pot.id] = { start = now - 30, duration = 120 } end
    end
    VS.items[NADE_LIST[1].id] = 6
    VS.items[SAPPER_ID] = 2
    VS.candles = 6
    VS.racial = { name = "Racial", icon = 136225, start = combat and (now - 20) or 0, duration = combat and 180 or 0 }
    VS.mana, VS.manaMax = combat and 3900 or 6400, 7000
    VS.fsr.start, VS.fsr.duration = now - 1.5, combat and 5 or 2
    VS.wand.active = combat
    VS.wand.start, VS.wand.duration = now - 0.6, 1.7
end

-- the pieces exactly where the HUD puts them on screen (HUD.RealSample)
local function LayoutSample(V, cfg)
    local r = cfg.resources
    HUD.RealSample(V.canvas, {
        { a = V.Main, mover = "prMainRow", store = cfg.mainRow, scale = cfg.mainRow.scale or 1, on = true },
        { a = V.Debuffs, mover = "prDebuffs", store = cfg.debuffRow, on = cfg.debuffRow.enabled },
        { a = V.Reminders, mover = "prReminders", store = cfg.reminders, on = cfg.reminders.enabled },
        { a = V.Mana, mover = "prMana", store = r.mana, on = r.manaBar or r.fsrBar },
        { a = V.Wand, mover = "prWand", store = r.wand, on = r.wandBar },
    })
end

local function PreviewSpec()
    return {
        key = "hud.priest", title = "Priest HUD",
        width = SAMPLE_W, height = SAMPLE_H,
        modes = { { id = "combat", label = "In combat" }, { id = "ready", label = "Out of combat" } },
        build = function(canvas, P) P.store.view = NewSampleView(canvas) end,
        update = function(canvas, P)
            local V = P.store.view
            local cfg = PR.Store()
            if not (V and cfg) then return end
            HUD.CheckLook()
            FillSample(V, P.mode or "combat")
            RefreshView(V)
            if not V.built then return end
            V.col = nil
            Colors(V)
            ApplyViewSizes(V, cfg)
            LayoutSample(V, cfg)
            RefreshView(V)
            TextTickView(V)
        end,
        replay = function(canvas, P)
            local V = P.store.view
            if not (V and V.built) then return end
            HUD.ReplayIcons({ V.mainIcons, V.debuffIcons, V.remindIcons }, true)
        end,
    }
end

local function EnsureTextTicker()
    if textTicker then return end
    textTicker = HUD.Ticker(0.1, TextTick)
end

local coreTicker = nil

-- High-frequency events (mana ticks, casts, bag updates) are only
-- registered while the HUD actually runs; bound below the event frame.
local RegisterHotEvents, UnregisterHotEvents

local function CoreTick()
    local cfg = PR.Store()
    if not cfg or not cfg.enabled or not S.isPriest then return end
    if dirty.spells then dirty.spells = false ResolveSpells() end
    if dirty.bags then dirty.bags = false ScanItems() end
    if dirty.auras then dirty.auras = false ScanPlayerBuffs() end
    UpdateMisc()
    if dirty.targetAuras then dirty.targetAuras = false ScanTargetDebuffs() end
    UpdateSpellSnapshot()
    PR.Display:Refresh()
end

local function StartTicker()
    if coreTicker then return end
    coreTicker = HUD.Ticker(0.2, CoreTick)
    EnsureTextTicker()
    if RegisterHotEvents then RegisterHotEvents() end
    -- The world moved on while the HUD was off; rescan everything.
    dirty.auras, dirty.targetAuras, dirty.bags, dirty.spells =
        true, true, true, true
    itemCD.MarkDirty()
end

local function StopTicker()
    if coreTicker then coreTicker:Cancel() coreTicker = nil end
    if textTicker then textTicker:Cancel() textTicker = nil end
    if UnregisterHotEvents then UnregisterHotEvents() end
end

function PR:SetEnabled(on)
    local cfg = PR.Store()
    if cfg then cfg.enabled = on and true or false end
    if on and S.isPriest then
        StartTicker()
    else
        StopTicker()
        PR.Display:HideAll()
    end
end

function PR:IsActive()
    local cfg = PR.Store()
    return (cfg and cfg.enabled and S.isPriest) and true or false
end

-- Event wiring
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")

-- Hot events live only while the HUD runs (see StartTicker/StopTicker).
RegisterHotEvents = function()
    lastMana = UnitPower("player", 0) or 0
    ev:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    ev:RegisterEvent("BAG_UPDATE_DELAYED")
end
UnregisterHotEvents = function()
    ev:UnregisterEvent("UNIT_POWER_FREQUENT")
    ev:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    ev:UnregisterEvent("BAG_UPDATE_DELAYED")
end

ev:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if event == "PLAYER_LOGIN" then
        local _, class = UnitClass("player")
        S.isPriest = class == "PRIEST"
        if not S.isPriest then
            ev:UnregisterAllEvents()
            return
        end
        playerGUID = UnitGUID("player")
        lastMana = UnitPower("player", 0) or 0
        S.inCombat = InCombatLockdown() or UnitAffectingCombat("player")

        ev:RegisterEvent("PLAYER_ENTERING_WORLD")
        -- the player's auras: ZacUI's shared read says when they moved;
        -- the target's stay on UNIT_AURA
        ns.PlayerAuras.On("PriestHUD", function() dirty.auras = true end)
        ev:RegisterUnitEvent("UNIT_AURA", "target")
        ev:RegisterEvent("PLAYER_TARGET_CHANGED")
        ev:RegisterEvent("SPELLS_CHANGED")
        ev:RegisterEvent("PLAYER_REGEN_DISABLED")
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
        ev:RegisterEvent("START_AUTOREPEAT_SPELL")
        ev:RegisterEvent("STOP_AUTOREPEAT_SPELL")
        -- UNIT_POWER_FREQUENT / UNIT_SPELLCAST_SUCCEEDED /
        -- BAG_UPDATE_DELAYED register in StartTicker, only while enabled.

        local cfg = PR.Store()
        if cfg and cfg.enabled then StartTicker() end
        HUD.Debug("PriestHUD core initialized")
    elseif event == "UNIT_POWER_FREQUENT" then
        OnManaEvent(event)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- (unit, castGUID, spellId)
        OnManaEvent(event, arg3)
    elseif event == "START_AUTOREPEAT_SPELL" then
        S.wand.active = true
        local speed = UnitRangedDamage and UnitRangedDamage("player") or 0
        -- WA-style short wind-up: the first Shoot lands quickly, then real swings take over.
        S.wand.start = GetTime()
        S.wand.duration = (speed and speed > 0) and math.min(speed, 0.6) or 0.6
    elseif event == "STOP_AUTOREPEAT_SPELL" then
        S.wand.active = false
        S.wand.duration = 0
    elseif event == "UNIT_AURA" then
        dirty.targetAuras = true           -- target only; the player's come via ns.PlayerAuras
    elseif event == "PLAYER_TARGET_CHANGED" then
        dirty.targetAuras = true
    elseif event == "BAG_UPDATE_DELAYED" then
        dirty.bags = true
        itemCD.MarkDirty()
    elseif event == "SPELLS_CHANGED" then
        dirty.spells = true
    elseif event == "PLAYER_REGEN_DISABLED" then
        S.inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        S.inCombat = false
    elseif event == "PLAYER_ENTERING_WORLD" then
        dirty.auras, dirty.targetAuras, dirty.bags, dirty.spells =
            true, true, true, true
        itemCD.MarkDirty()
    end
end)

-- Settings page: General | Look | Animation | Position | Advanced (the
-- Priest HUD draws no text that is not a timer or a count, so its Text
-- tab is the shared HUD text), with the HUD in the preview dock.
local Check, SliderPair, CheckGrid = HUD.CheckIndent, HUD.SliderPair, HUD.CheckGrid
local function Px(v) return v .. " px" end
local function Refresh() PR.Display:Refresh() end

local function Tab_General(L, cfg)
    L:Card("Priest HUD")
    L:Desc("Native port of a Priest UI WeakAura pack, styled like the Warrior and "
        .. "Paladin HUDs. Cooldown grid, target debuffs, reminders, mana + "
        .. "five-second-rule bars and a wand swing bar. Priest characters only.")
    Check(L, "Enable Priest HUD", cfg.enabled, function(v)
        PR:SetEnabled(v)
    end)
    Check(L, "Show every element on screen (test)", PR.preview and true or false, function(v)
        PR.preview = v
        LIVE.preview = v
        Refresh()
    end, nil, "Forces every enabled piece visible where it sits, to line things up. Not saved.")
    L:EndCard()

    L:Card("Cooldown grid")
    L:Desc("Untick an icon to remove it from the grid.")
    CheckGrid(L, MAIN_DEFS,
        function(def) return def.label end,
        function(def) return not cfg.mainRow.hidden[def.key] end,
        function(def, v)
            cfg.mainRow.hidden[def.key] = (not v) and true or nil
            Refresh()
        end)
    HUD.Label(L, "Potion icon")
    HUD.Dropdown(L, 220, HUD.PotionItems(),
        function() return HUD.PotionLabel(cfg.mainRow.potionChoice) end,
        function(value)
            cfg.mainRow.potionChoice = value
            Refresh()
        end, "Which potion the grid's potion icon tracks. Automatic shows the first one in your "
            .. "bags, in the standard priority order.")
    L:EndCard()

    L:Card("Target debuffs")
    Check(L, "Show my debuffs on the target", cfg.debuffRow.enabled, function(v)
        cfg.debuffRow.enabled = v
        Refresh()
    end)
    for _, def in ipairs(DEBUFF_DEFS) do
        Check(L, def.label, not cfg.debuffRow.hidden[def.key], function(v)
            cfg.debuffRow.hidden[def.key] = (not v) and true or nil
            Refresh()
        end, 16)
    end
    L:EndCard()

    L:Card("Reminders")
    Check(L, "Show reminders", cfg.reminders.enabled, function(v)
        cfg.reminders.enabled = v
        Refresh()
    end)
    for _, def in ipairs(REMIND_DEFS) do
        Check(L, def.label, cfg.reminders[def.option], function(v)
            cfg.reminders[def.option] = v
            Refresh()
        end, 16)
    end
    L:EndCard()

    L:Card("Mana, five-second rule and wand")
    local r = cfg.resources
    Check(L, "Mana bar", r.manaBar, function(v) r.manaBar = v Refresh() end)
    Check(L, "Five-second rule / tick bar", r.fsrBar, function(v) r.fsrBar = v Refresh() end)
    Check(L, "Wand swing bar (while wanding)", r.wandBar, function(v) r.wandBar = v Refresh() end)
    L:EndCard()
end

local COLOR_LABELS = {
    { "oor", "Out of range tint" }, { "timer", "Timer text" }, { "count", "Count text" },
    { "barText", "Mana value text" }, { "mana", "Mana bar" }, { "fsr", "Five-second rule bar" },
    { "wand", "Wand bar" },
}

local function Tab_Look(L, cfg)
    local r = cfg.resources
    L:Card("Cooldown grid")
    local rows = cfg.mainRow.rows
    SliderPair(L,
        { "Row 1 icon size", 16, 48, rows[1].w, function(v) rows[1].w, rows[1].h = v, v Refresh() end, Px },
        { "Row 1 icon count", 4, 14, rows[1].limit, function(v) rows[1].limit = v Refresh() end })
    SliderPair(L,
        { "Row 2+ icon size", 16, 48, rows[2].w, function(v)
            rows[2].w, rows[2].h = v, v
            rows[3].w, rows[3].h = v, v
            Refresh()
        end, Px },
        { "Spacing", 0, 12, cfg.mainRow.spacing, function(v) cfg.mainRow.spacing = v Refresh() end, Px })
    L:EndCard()

    L:Card("Rows and bars")
    SliderPair(L,
        { "Target debuff icon size", 16, 48, cfg.debuffRow.iconSize, function(v) cfg.debuffRow.iconSize = v Refresh() end, Px },
        { "Target debuff spacing", 0, 12, cfg.debuffRow.spacing or 4, function(v) cfg.debuffRow.spacing = v Refresh() end, Px })
    SliderPair(L,
        { "Reminder icon size", 20, 64, cfg.reminders.iconSize, function(v) cfg.reminders.iconSize = v Refresh() end, Px },
        { "Reminder spacing", 0, 16, cfg.reminders.spacing or 6, function(v) cfg.reminders.spacing = v Refresh() end, Px })
    SliderPair(L,
        { "Mana bar width", 100, 500, r.mana.w, function(v) r.mana.w = v PR.Display:ApplySizes() end, Px },
        { "Mana bar height", 4, 20, r.mana.h, function(v) r.mana.h = v PR.Display:ApplySizes() end, Px })
    SliderPair(L,
        { "Wand bar width", 100, 500, r.wand.w, function(v) r.wand.w = v PR.Display:ApplySizes() end, Px },
        { "Wand bar height", 4, 20, r.wand.h, function(v) r.wand.h = v PR.Display:ApplySizes() end, Px })
    L:EndCard()

    L:Card("Colours")
    local entries = {}
    for _, c in ipairs(COLOR_LABELS) do
        local key = c[1]
        entries[#entries + 1] = { c[2],
            get = function() return HUD.Col(cfg.colors[key], COLOR_DEFAULTS[key]) end,
            set = function(rr, g, b, a)
                cfg.colors[key] = { r = rr, g = g, b = b, a = a or 1 }
                LIVE.col = nil
                Colors(LIVE)
            end }
    end
    HUD.ColorGrid(L, entries)
    L:EndCard()

    HUD.SharedLookCards(L)
end

local function Tab_Position(L, cfg)
    L:Card("Position")
    L:Desc("Every piece of the HUD is its own anchor: drag them to line up with your unit frames.")
    HUD.UnlockButton(L, "pr")
    L:Gap(4)
    HUD.ScaleSlider(L, "Cooldown grid scale", cfg.mainRow, "scale", ApplyAnchorPositions)
    L:EndCard()
end

local function Tab_Advanced(L, cfg)
    L:Card("Reset")
    HUD.Button(L, "Reset colours", 150, function()
        cfg.colors = ns.CopySetting(COLOR_DEFAULTS)
        LIVE.col = nil
        Colors(LIVE)
        ns.SettingsChanged("reset")
        HUD.RefreshPage()
    end, "Puts this HUD's colours back to the defaults.")
    HUD.ResetLookButton(L)
    L:EndCard()
end

local function BuildPage(L)
    L:Header("Priest HUD",
        "WeakAura port: cooldown grid, target debuffs, reminders, mana + "
        .. "five-second-rule bars and a wand swing bar")
    local cfg = PR.Store()
    if not cfg then
        L:Notice("missing", "The HUD settings are not available yet.")
        return
    end
    -- fitted after every update: in the dock's strata, inside the canvas
    L:Preview(HUD.FitSpec(PreviewSpec()))
    L:Tabs({
        { id = "general", label = "General",   build = function(L2) Tab_General(L2, cfg) end },
        { id = "look",    label = "Look",      build = function(L2) Tab_Look(L2, cfg) end },
        { id = "text",    label = "Text",      build = function(L2) HUD.SharedTextCards(L2) end },
        { id = "anim",    label = "Animation", build = function(L2) HUD.SharedAnimCards(L2) end },
        { id = "pos",     label = "Position",  build = function(L2) Tab_Position(L2, cfg) end },
        { id = "adv",     label = "Advanced",  build = function(L2) Tab_Advanced(L2, cfg) end },
    })
end

HUD.RegisterPage("priest", "Priest HUD",
    "priest hud class pack weakaura cooldown grid shield power word "
    .. "inner fire fortitude spirit shadowform wand five second rule fsr "
    .. "mana bar candles debuffs reminders potion grenade sapper " .. HUD.PAGE_KEYWORDS,
    { PRIEST = true },
    BuildPage)
