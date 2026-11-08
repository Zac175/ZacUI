-- HUD_Paladin - the Paladin HUD: native port of the "Paladin Class Pack -
-- Classic Era" WeakAura (same author/template as the Warrior Class Pack).
-- State engine + display + settings page in one file, reusing the
-- Warrior HUD's widget factory (ns.WarriorHUD.Widgets) so both HUDs
-- share one look.
-- Part of ZacUI; load order is set by the TOC.
-- Perf rules: events set dirty flags / record timestamps only; scans
-- run in the 0.2s core ticker; countdown texts on a 0.1s text ticker.
local ADDON_NAME = ...
-- Zacui_HUD is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end
if not ns.HUD then return end   -- (the part stands down on this game version: HUD_Shared, Core_Flavor)

-- a value WoW Forever hands back hidden (a secret value: no maths on it)
local function Hidden(v) return ns.IsSecret ~= nil and ns.IsSecret(v) or false end
local HUD = ns.HUD
local UI = ns.UI
local Print = ns.Print

ns.PaladinHUD = ns.PaladinHUD or {}
local PH = ns.PaladinHUD

-- API compat shims come from HUD_Shared.
local GetSpellInfo       = HUD.GetSpellInfo
local GetSpellCooldown_C = HUD.GetSpellCooldown
local IsUsableSpell_C    = HUD.IsUsableSpell
local IsSpellInRange_C   = HUD.IsSpellInRange
local GetSpellTexture_C  = HUD.GetSpellTexture
local GetItemCount_C     = HUD.GetItemCount

-- Storage: ZacUIDB.hud.paladin
local DEFAULTS = {
    enabled = false,
    mainRow = {
        x = 0, y = -208, scale = 1,
        -- The WA's custom grid overrides child sizes per row.
        rows = {
            { limit = 7, w = 30, h = 30 },
            { limit = 9, w = 25, h = 25 },
            { limit = 8, w = 25, h = 25 },
        },
        spacing = 4,
        hidden = {},                 -- key -> true
        potionChoice = 13,           -- his export config: Major Mana Potion
    },
    auraRow = {
        x = 0, y = -150, scale = 1,
        iconSize = 25, spacing = 4,
        hidden = {},
    },
    resources = {
        swingTimer = true,
        manaBar    = true,
        mp5Bar     = true,
        rfText     = false,          -- available, off by default
        blessingText = false,        -- "Blessing" missing (WA use_never)
        swing = { x = 0, y = -183, w = 316, h = 2 },
        mana  = { x = 0, y = -188, w = 234, h = 4 },
        texts = { x = 0, y = 180, size = 20 },
    },
    aux = {
        enabled = false,             -- WA "Paladin Aux" is use_never
        x = 0, y = -400, iconSize = 30, spacing = 4,
        trinket1 = true, trinket2 = true, racial = true,
    },
}

function PH.Store()
    local db = HUD.Store("paladin", DEFAULTS)
    if not db then return nil end
    -- Migration: drop the first cut's dead flat iconW/iconH/perRow keys.
    local m = db.mainRow
    if m and m.iconW then
        m.iconW, m.iconH, m.perRow = nil, nil, nil
    end
    -- Migration: rfText briefly shipped default-ON; one-time flip to off.
    if not db._rfDefaultFlipped then
        db._rfDefaultFlipped = true
        if db.resources then db.resources.rfText = false end
    end
    return db
end

-- Static data (verbatim from the decoded WeakAura)
-- Tracked spells (WA trigger ids; name lookups pick up the player's rank).
local SPELL_IDS = {
    loh          = 10310, divineShield = 1020,  hoj         = 853,
    freedom      = 1044,  bop          = 10278, judgement   = 20271,
    divineFavor  = 20216, consecration = 26573, intervention = 19752,
    divineProt   = 5573,  exorcism     = 10314, holyWrath   = 10318,
    righteousFury = 25780,
}

-- Active-buff row (WA "Paladin Aura Bar" order). Classic Era buffs only.
local AURA_BUFF_IDS = {
    { key = "divineFavor",  id = 20216 },
    { key = "sealCrusader", id = 20306 },
    { key = "divineShield", id = 1020 },
    { key = "zhc",          id = 24659, label = "Zandalarian Hero Charm" },
    { key = "eyeOfDead",    id = 28780, label = "Eye of the Dead" },
    { key = "blindingLight", id = 23733, label = "Blinding Light" },
    { key = "divineProt",   id = 498 },
    { key = "holyShield",   id = 20925 },
    { key = "sealWisdom",   id = 20351 },
    { key = "sealRight",    id = 20438 },
    { key = "sealLight",    id = 20456 },
    { key = "sealJustice",  id = 20164 },
    { key = "sealCommand",  id = 20944 },
}

-- Any of these buffs counts as "blessed" (WA "Text - Blessing" list).
local BLESSING_IDS = {
    25291, 1044, 10278, 25916, 25290, 25899, 25895, 25894, 1038,
    20911, 19977, 25898, 20217, 25890, 425600,
}

local RUNE_LIST = {
    { id = 12662, icon = 134417 }, -- Demonic Rune
    { id = 20520, icon = 136192 }, -- Dark Rune
}

-- One spell id per race; only the id matching the player's own race
-- resolves a name, so ResolveSpells' first hit is the only hit.
local RACIAL_IDS = { 20594, 20589, 20600, 20580, 7744, 20572, 20549, 20554 }

local RED_OOR = { 1, 0.2431, 0.2275 }          -- WA out-of-range tint
local GOLD_COUNT = { 1, 0.82, 0, 1 }
local PINK_TEXT = { 0.9569, 0.5490, 0.7294, 1 } -- WA reminder text color
local MANA_BLUE = { 0, 0.44, 0.87 }
local MP5_BLUE  = { 0, 0.24, 1 }

local HUD_STRATA = "MEDIUM"

-- Live state
PH.State = {
    isPaladin = false,
    inCombat  = false,
    spells    = {},        -- key -> { name, known, icon }
    cds       = {},        -- key -> { start, duration, real }
    usable    = {},        -- key -> { usable, noPower }
    inRange   = {},        -- key -> 1 / 0 / nil
    buffs     = {},        -- player HELPFUL by lower(name)
    auraNames = {},        -- aura-row key -> resolved name
    auraIcons = {},        -- aura-row key -> icon
    blessingNames = {},    -- lower(name) set
    targetAttackable = false,
    swing     = { start = 0, duration = 0 },
    mp5       = { start = 0, duration = 0 },   -- tick/five-second-rule window
    items     = {},        -- itemId -> count (potions/runes only)
    trinkets  = {},        -- slot -> { texture, start, duration }
    racial    = nil,       -- { name, icon } first known racial
    manaPct   = 1,
}
local S = PH.State

local dirty = { auras = true, bags = true, spells = true }
local playerGUID = nil

-- Spell/buff resolution
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
    for _, def in ipairs(AURA_BUFF_IDS) do
        if GetSpellInfo then
            local name, _, icon = GetSpellInfo(def.id)
            S.auraNames[def.key] = name
            S.auraIcons[def.key] = icon
        end
    end
    -- Trinket buffs come from items; keep the WA's literal names.
    S.auraNames.zhc = S.auraNames.zhc or "Zandalarian Hero Charm"
    wipe(S.blessingNames)
    for _, id in ipairs(BLESSING_IDS) do
        local name = GetSpellInfo and GetSpellInfo(id) or nil
        if name then S.blessingNames[name:lower()] = true end
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

-- Scans (core ticker only)
-- The entry for a buff name is kept between scans and its fields
-- rewritten; the scan runs up to five times a second in a fight and used
-- to make a fresh table per buff. Entries not seen this pass are dropped
-- afterwards, so a reader finds exactly what a rebuilt table would hold.
local scanPass = 0
-- the player's buffs come from ZacUI's shared read (ns.PlayerAuras)
local function ScanPlayerBuffs()
    scanPass = scanPass + 1
    local pass = scanPass
    local list = ns.PlayerAuras.Buffs()
    for i = 1, #list do
        local a = list[i]
        local name = a.name
        if name then
            local lname = name:lower()
            local existing = S.buffs[lname]
            if existing and existing.pass == pass then
                existing.matches = (existing.matches or 1) + 1
            else
                if not existing then
                    existing = {}
                    S.buffs[lname] = existing
                end
                existing.pass = pass
                existing.name, existing.icon, existing.count = name, a.icon, a.count
                existing.duration, existing.expirationTime = a.duration, a.expirationTime
                existing.matches = 1
            end
        end
    end
    for lname, e in pairs(S.buffs) do
        if e.pass ~= pass then S.buffs[lname] = nil end
    end
end

-- Plain GetItemCount for the tracked potion/rune items - cheaper than a bag scan.
local WH = ns.WarriorHUD
local function ScanItems()
    wipe(S.items)
    local lists = { RUNE_LIST }
    if WH and WH.POTION_LIST then lists[#lists + 1] = WH.POTION_LIST end
    for _, list in ipairs(lists) do
        for _, e in ipairs(list) do
            if S.items[e.id] == nil and GetItemCount_C then
                S.items[e.id] = GetItemCount_C(e.id) or 0
            end
        end
    end
end

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
            local start, duration, _, _, durObj = GetSpellCooldown_C(sp.name)
            start, duration = start or 0, duration or 0
            local cd = S.cds[key]
            if not cd then cd = {} S.cds[key] = cd end
            cd.start, cd.duration = start, duration
            cd.durObj = durObj   -- (WoW Forever: a hidden cooldown's swipe)
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
    local mana, manaMax = UnitPower("player", 0), UnitPowerMax("player", 0)
    if Hidden(mana) or Hidden(manaMax) then
        -- hidden (WoW Forever): keep the last known share
        S.manaPct = S.manaPct or 1
    else
        S.manaPct = (manaMax and manaMax > 0) and (mana / manaMax) or 1
    end
    -- Inventory slots 13/14 are Blizzard's fixed Trinket 1/2 slots.
    for slotIdx = 13, 14 do
        local t = S.trinkets[slotIdx]
        if not t then t = {} S.trinkets[slotIdx] = t end
        t.texture = GetInventoryItemTexture and GetInventoryItemTexture("player", slotIdx) or nil
        if GetInventoryItemCooldown then
            local start, duration = HUD.PlainCD(GetInventoryItemCooldown("player", slotIdx))
            t.start, t.duration = start or 0, duration or 0
        end
    end
end

-- Events: MP5 window + swing timer (timestamp writes only)
-- MP5 rules (reworked from the WA, which restarted on every mana event
-- and jumped between 2s and 6.45s while chain-casting):
--  * Spending mana on a cast -> one clean 5s five-second-rule drain.
--  * Mana gains start a 2s tick window only once the 5s rule elapsed and
--    nothing is hardcast, so JoW/Wisdom/seal procs can't hijack the bar.
local lastMana = 0
local fsrCastAt = -10

local function OnManaEvent(event)
    local cur = UnitPower("player", 0) or 0
    -- hidden (WoW Forever): the five-second-rule reading sits out
    if Hidden(cur) then lastMana = nil return end
    if event == "UNIT_POWER_FREQUENT" then
        local mx = UnitPowerMax("player", 0)
        if Hidden(mx) then mx = nil end
        if cur >= (mx or 0) then
            lastMana = cur
            return
        end
        if lastMana and cur > lastMana
            and GetTime() >= fsrCastAt + 5
            and not (UnitCastingInfo and UnitCastingInfo("player")) then
            S.mp5.start, S.mp5.duration = GetTime(), 2
        end
        lastMana = cur
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if lastMana and cur < lastMana then
            S.mp5.start, S.mp5.duration = GetTime(), 5
            fsrCastAt = GetTime()
        end
        lastMana = cur
    end
end

-- through ZacUI's shared combat-log reader (ns.CLEU)
local SWING_SUBS = { "SWING_DAMAGE", "SWING_MISSED" }
local function OnCombatLogEvent(_, subevent, _, sourceGUID)
    if sourceGUID ~= playerGUID then return end
    if subevent == "SWING_DAMAGE" or subevent == "SWING_MISSED" then
        local mhSpeed = UnitAttackSpeed("player")
        S.swing.start = GetTime()
        S.swing.duration = mhSpeed or 0
    end
end

-- WoW Forever: the game's own swing event instead (ns.Swings)
local function OnSwing(hand, now, dur, durObj)
    if hand ~= "mh" then return end
    S.swing.start = now
    S.swing.duration = dur or 0
    S.swing.durObj = durObj   -- (WoW Forever: the hidden swing time on the game's clock)
end

-- Display: anchors. Each anchor sits centred on an UNSCALED holder; the
-- holder is what ZacUI's mover registry positions, so a scaled anchor
-- still reports plain UIParent offsets when dragged.
local W        -- warrior widget factory, bound at build time

local holders = {}
local function MakeAnchor(key, w, h)
    local holder = CreateFrame("Frame", "ZacUIHUD_Paladin_" .. key .. "_Holder", UIParent)
    holder:SetSize(w or 26, h or 26)
    holder:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    local f = CreateFrame("Frame", "ZacUIHUD_Paladin_" .. key, holder)
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
    timer = { r = 1, g = 1, b = 1, a = 1 }, text = HUD.RGBA(PINK_TEXT),
    barText = { r = 1, g = 1, b = 1, a = 1 },
    mana = HUD.RGBA(MANA_BLUE), mp5 = HUD.RGBA(MP5_BLUE), swing = { r = 1, g = 1, b = 1, a = 1 },
}
DEFAULTS.colors = COLOR_DEFAULTS

-- A VIEW is one drawn copy of the HUD: its anchors, icons, bars and the
-- state it draws from. LIVE is the one on screen; the settings preview
-- makes another on its canvas (V.sample) from made-up state, through the
-- very same Build / Refresh functions below.
local function NewView(state)
    return {
        S = state,
        memo = { main = {}, aura = {}, aux = {} },
        mainIcons = {}, mainActive = {}, auraIcons = {}, auraActive = {}, auxIcons = {},
    }
end
local LIVE = NewView(S)
PH.LIVE = LIVE

-- The named anchor frames exist only for paladins: on any other class
-- nothing in this file ever shows, so creating them would just park
-- named frames in the frame census forever.
local IS_PALADIN = select(2, UnitClass("player")) == "PALADIN"
if IS_PALADIN then
    LIVE.Main    = MakeAnchor("Main", 36, 28)
    LIVE.AuraRow = MakeAnchor("AuraRow", 25, 25)
    LIVE.Swing   = MakeAnchor("Swing", 316, 2)
    LIVE.Mana    = MakeAnchor("Mana", 234, 10)     -- mana bar + mp5 bar
    LIVE.Texts   = MakeAnchor("Texts", 240, 30)    -- RF/Blessing reminders
    LIVE.Aux     = MakeAnchor("Aux", 30, 30)
    -- Invisible handle: dragging it in the UI mover moves the WHOLE HUD.
    LIVE.GroupHandle = MakeAnchor("GroupHandle", 170, 24)
end

local function ApplyAnchorPositions()
    if not LIVE.Main then return end      -- non-paladin: no anchors exist
    local cfg = PH.Store()
    if not cfg then return end
    HUD.PlaceAnchor("phMainRow", holders.Main, cfg.mainRow)
    HUD.PlaceAnchor("phAuraRow", holders.AuraRow, cfg.auraRow)
    HUD.PlaceAnchor("phSwing", holders.Swing, cfg.resources.swing)
    HUD.PlaceAnchor("phMana", holders.Mana, cfg.resources.mana)
    HUD.PlaceAnchor("phTexts", holders.Texts, cfg.resources.texts)
    HUD.PlaceAnchor("phAux", holders.Aux, cfg.aux)
    if cfg.group then HUD.PlaceAnchor("phGroup", holders.GroupHandle, cfg.group) end
    LIVE.Main:SetScale(cfg.mainRow.scale or 1)
    LIVE.AuraRow:SetScale(cfg.auraRow.scale or 1)
end

local function RegisterMovers()
    -- No paladin mover entries cluttering move mode on other classes.
    local _, playerClass = UnitClass("player")
    if playerClass ~= "PALADIN" then return end
    local cfg = PH.Store()
    if not cfg then
        C_Timer.After(1, RegisterMovers)   -- saved vars not ready yet
        return
    end
    HUD.RegisterMover("phMainRow", "Paladin HUD Cooldown Grid", holders.Main, cfg.mainRow)
    HUD.RegisterMover("phAuraRow", "Paladin HUD Active Buffs", holders.AuraRow, cfg.auraRow)
    HUD.RegisterMover("phSwing", "Paladin HUD Swing Timer", holders.Swing, cfg.resources.swing)
    HUD.RegisterMover("phMana", "Paladin HUD Mana + MP5", holders.Mana, cfg.resources.mana)
    HUD.RegisterMover("phTexts", "Paladin HUD Reminder Texts", holders.Texts, cfg.resources.texts)
    HUD.RegisterMover("phAux", "Paladin HUD Trinkets/Racial", holders.Aux, cfg.aux)

    -- Whole-HUD mover: dragging the handle shifts every member anchor by
    -- the same delta (HUD_Shared carries the delta to the members).
    cfg.group = cfg.group or { x = (cfg.mainRow.x or 0),
                               y = (cfg.mainRow.y or -208) + 50 }
    HUD.PlaceAnchor("phGroup", holders.GroupHandle, cfg.group)
    HUD.RegisterGroup("phGroup", "Paladin HUD: move all", holders.GroupHandle, cfg.group, {
        { key = "phMainRow", holder = holders.Main },
        { key = "phAuraRow", holder = holders.AuraRow },
        { key = "phSwing",   holder = holders.Swing },
        { key = "phMana",    holder = holders.Mana },
        { key = "phTexts",   holder = holders.Texts },
        { key = "phAux",     holder = holders.Aux },
    })
    HUD.Debug("PaladinHUD anchors registered with the mover registry")
end
C_Timer.After(2, function()
    ApplyAnchorPositions()
    RegisterMovers()
end)

-- Main grid definitions (order = WA child order)
local MAIN_DEFS = {
    { key = "loh",          kind = "spell", spell = "loh",          label = "Lay on Hands" },
    { key = "divineShield", kind = "spell", spell = "divineShield", label = "Divine Shield", noRange = true },
    { key = "hoj",          kind = "spell", spell = "hoj",          label = "Hammer of Justice" },
    { key = "freedom",      kind = "spell", spell = "freedom",      label = "Blessing of Freedom", noRange = true },
    { key = "bop",          kind = "spell", spell = "bop",          label = "Blessing of Protection" },
    { key = "judgement",    kind = "spell", spell = "judgement",    label = "Judgement" },
    { key = "divineFavor",  kind = "spell", spell = "divineFavor",  label = "Divine Favor", noRange = true },
    { key = "consecration", kind = "spell", spell = "consecration", label = "Consecration", noRange = true },
    { key = "intervention", kind = "spell", spell = "intervention", label = "Divine Intervention" },
    { key = "divineProt",   kind = "spell", spell = "divineProt",   label = "Divine Protection", noRange = true },
    { key = "exorcism",     kind = "spell", spell = "exorcism",     label = "Exorcism" },
    { key = "holyWrath",    kind = "spell", spell = "holyWrath",    label = "Holy Wrath" },
    { key = "potion",       kind = "itemPotion", label = "Potion" },
    { key = "rune",         kind = "itemRune",   label = "Rune" },
}
PH.MainIconList = MAIN_DEFS

-- The colour settings as { r, g, b, a } arrays, onto every piece of one
-- view that carries one; re-read whenever any setting changed.
local function Colors(V)
    if V.col and V._serial == HUD.serial then return V.col end
    local cfg = PH.Store()
    local src = (cfg and cfg.colors) or COLOR_DEFAULTS
    local col = {}
    for k, d in pairs(COLOR_DEFAULTS) do
        local r, g, b, a = HUD.Col(src[k], d)
        col[k] = { r, g, b, a }
    end
    V.col, V._serial = col, HUD.serial
    if V.built then
        local function bar(b, c) if b then b:SetBarColor(c[1], c[2], c[3], c[4]) end end
        bar(V.swingBar, col.swing)
        bar(V.manaBar, col.mana)
        bar(V.mp5Bar, col.mp5)
        if V.manaBar then V.manaBar.text:SetTextColor(unpack(col.barText)) end
        for _, set in ipairs({ V.mainIcons, V.auraIcons, V.auxIcons }) do
            for _, icon in pairs(set) do
                local t = icon.texts
                if t.p then t.p:SetTextColor(unpack(col.timer)) end
                if t.s then t.s:SetTextColor(unpack(col.timer)) end
                if t.count then t.count:SetTextColor(unpack(col.count)) end
            end
        end
        if V.rfText then V.rfText:SetTextColor(unpack(col.text)) end
        if V.blessText then V.blessText:SetTextColor(unpack(col.text)) end
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
        if def.kind ~= "spell" then
            icon:AddText("count", "INNER_BOTTOMRIGHT", 12, GOLD_COUNT, 0, 0)
        end
        V.mainIcons[def.key] = icon
    end
end

local function BuildAuraIcons(V)
    local cfg = PH.Store()
    local size = (cfg and cfg.auraRow.iconSize) or 25
    for _, def in ipairs(AURA_BUFF_IDS) do
        local icon = W.CreateIcon(V.AuraRow, {
            width = size, height = size, zoom = W.ICON_ZOOM, keepAspect = true,
            inverse = true,
        })
        icon:SetFrameStrata(HUD_STRATA)
        icon:Hide()
        icon.def = def
        -- "p" remaining time below, "s" stacks flush top-right (warrior HUD look).
        icon:AddText("p", "BELOW", 14, { 1, 1, 1, 1 }, 0, 0)
        icon:AddText("s", "INNER_TOPRIGHT", 14, { 1, 1, 1, 1 }, 0, 0)
        V.auraIcons[def.key] = icon
    end
end

local function BuildAux(V)
    local defs = {
        { key = "trinket1", slot = 13, label = "Trinket 1" },
        { key = "trinket2", slot = 14, label = "Trinket 2" },
        { key = "racial",   label = "Racial" },
    }
    local cfg = PH.Store()
    local size = (cfg and cfg.aux.iconSize) or 30
    for _, def in ipairs(defs) do
        local icon = W.CreateIcon(V.Aux, {
            width = size, height = size, zoom = W.ICON_ZOOM, keepAspect = true,
            inverse = true,
        })
        icon:SetFrameStrata(HUD_STRATA)
        icon:Hide()
        icon.def = def
        icon:AddText("p", "CENTER", 12, { 1, 1, 1, 1 })
        V.auxIcons[def.key] = icon
    end
end

local function BuildBars(V)
    local cfg = PH.Store()
    local r = cfg and cfg.resources or DEFAULTS.resources
    local VS = V.S
    local col = Colors(V)

    local swingBar = W.CreateBar(V.Swing, { width = r.swing.w, height = r.swing.h,
        spark = true, barColor = col.swing })
    swingBar:SetFrameStrata(HUD_STRATA)
    swingBar:SetPoint("CENTER", V.Swing, "CENTER", 0, 0)
    swingBar:Hide()
    V.swingBar = swingBar

    local manaBar = W.CreateBar(V.Mana, { width = r.mana.w, height = r.mana.h,
        barColor = col.mana })
    manaBar:SetFrameStrata(HUD_STRATA)
    manaBar:SetPoint("CENTER", V.Mana, "CENTER", 0, 2)
    -- Created on the StatusBar so it draws above the fill texture.
    local mt = HUD.Text(manaBar.bar, 10, "OUTLINE", "OVERLAY", "text")
    mt:SetPoint("CENTER", manaBar, "CENTER", 0, 0)
    mt:SetTextColor(1, 1, 1)
    manaBar.text = mt
    if HUD.BarText then HUD.BarText(mt, manaBar) end
    -- the raw mana value on the bar, not a percent (WA)
    if V.sample then manaBar.readMana = function() return VS.mana or 0, VS.manaMax or 1 end end
    manaBar:SetScript("OnUpdate", HUD.ManaBarOnUpdate)
    manaBar:Hide()
    V.manaBar = manaBar

    -- MP5 bar: drains over the current tick / five-second-rule window.
    local mp5Bar = W.CreateBar(V.Mana, { width = r.mana.w, height = r.mana.h,
        barColor = col.mp5 })
    mp5Bar:SetFrameStrata(HUD_STRATA)
    mp5Bar:SetPoint("CENTER", V.Mana, "CENTER", 0, -3)
    mp5Bar:SetScript("OnUpdate", function(self)
        local dur = VS.mp5.duration or 0
        if V.preview then
            self.bar:SetValue(0.65)
            return
        end
        if dur <= 0 then
            self.bar:SetValue(0)
            return
        end
        local remaining = VS.mp5.start + dur - GetTime()
        -- the preview's sample runs its made-up window round and round
        if V.sample and remaining <= 0 then
            VS.mp5.start = GetTime()
            remaining = dur
        end
        if remaining <= 0 then
            self.bar:SetValue(0)
        else
            self.bar:SetValue(remaining / dur)
        end
    end)
    mp5Bar:Hide()
    V.mp5Bar = mp5Bar

    -- Reminder texts (WA pink; sized down from the WA's 32px per feedback).
    local rfText = HUD.Text(V.Texts, r.texts.size or 20, "OUTLINE", "OVERLAY", "alert")
    rfText:SetPoint("CENTER", V.Texts, "CENTER", 0, 8)
    rfText:SetTextColor(unpack(col.text))
    rfText:SetText("Righteous Fury")
    rfText:Hide()
    V.rfText = rfText

    local blessText = HUD.Text(V.Texts, r.texts.size or 20, "OUTLINE", "OVERLAY", "alert")
    blessText:SetPoint("CENTER", V.Texts, "CENTER", 0, -14)
    blessText:SetTextColor(unpack(col.text))
    blessText:SetText("Blessing")
    blessText:Hide()
    V.blessText = blessText

    -- Swing driver (only while the swing bar is shown)
    local driver = CreateFrame("Frame", nil, V.sample and V.Swing or nil)
    driver:Hide()
    driver:SetScript("OnUpdate", function()
        if not swingBar:IsShown() then driver:Hide() return end
        if V.preview then
            swingBar.bar:SetValue(0.65)
            if swingBar.UpdateSpark then swingBar:UpdateSpark(0.65) end
            return
        end
        local dur = VS.swing.duration or 0
        local remaining = dur > 0 and (VS.swing.start + dur - GetTime()) or 0
        if V.sample and dur > 0 and remaining <= 0 then
            VS.swing.start = GetTime()
            remaining = dur
        end
        -- (WoW Forever: a hidden swing time runs on the game's clock)
        if not V.sample and HUD.TimedSwing(swingBar, VS.swing.durObj) then return end
        HUD.UntimedSwing(swingBar)
        local frac = (remaining > 0 and dur > 0) and (remaining / dur) or 0
        swingBar.bar:SetValue(frac)
        if swingBar.UpdateSpark then swingBar:UpdateSpark(frac) end
    end)
    V.swingDriver = driver
    if V == LIVE then PH.swingDriver = driver end
end

-- Layouts: HUD.LayoutGrid (the WA's custom grow: fixed per-row limits,
-- per-row icon sizes, every row centred, rows stacked down) and
-- HUD.LayoutRow (HUD_Shared), laid out again only on a change.

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

-- Refresh (0.2s core tick)
local function UpdateMainIcon(V, icon, def)
    local VS = V.S
    if def.kind == "spell" then
        local sp = VS.spells[def.spell]
        if not (sp and sp.known) then return false end
        local cd = VS.cds[def.spell]
        local us = VS.usable[def.spell] or {}
        local inRange = (not def.noRange) and VS.inRange[def.spell] or nil
        icon:SetIconTexture(sp.icon)
        if cd then icon:SetSwipe(cd.start, cd.duration, cd.durObj) end
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
    elseif def.kind == "itemPotion" then
        local cfg = PH.Store()
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
    elseif def.kind == "itemRune" then
        local item, count = FirstIn(V, RUNE_LIST)
        icon.curItem = item
        if not item or count == 0 then return false end
        icon:SetIconTexture(item.icon)
        icon:SetText("count", tostring(count))
        local start, duration = ItemCD(V, item.id)
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
                    or (def.kind == "itemPotion" and 134856)
                    or (def.kind == "itemRune" and 134417) or 134400)
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

local function RefreshAuraRow(V, cfg)
    local VS = V.S
    wipe(V.auraActive)
    local a = cfg.auraRow
    for _, def in ipairs(AURA_BUFF_IDS) do
        local icon = V.auraIcons[def.key]
        local shown = false
        if On(V, cfg) and a.enabled ~= false and not a.hidden[def.key] then
            if V.preview then
                icon:SetIconTexture(VS.auraIcons[def.key] or 134400)
                icon:ClearSwipe()
                shown = VS.auraNames[def.key] ~= nil
            else
                local name = VS.auraNames[def.key]
                local b = name and VS.buffs[name:lower()] or nil
                if b then
                    icon:SetIconTexture(b.icon or VS.auraIcons[def.key])
                    if (b.duration or 0) > 0 then
                        icon:SetSwipe(b.expirationTime - b.duration, b.duration)
                    else
                        icon:ClearSwipe()
                    end
                    icon.buffRef = b
                    shown = true
                end
            end
        end
        W.SetShownAnimated(icon, shown)
        if shown then V.auraActive[#V.auraActive + 1] = icon end
    end
    local size = a.iconSize or 25
    HUD.LayoutRow(V.memo.aura, V.auraActive, V.AuraRow, size, size, a.spacing or 4)
end

-- Class HUD v2: the active seal as an icon by the mana bar (off until
-- turned on: cfg.resources.sealIcon; the icon is made only then). Classic
-- Era / TBC read the seal from your buffs by name; WoW Forever, which
-- hides your buffs in a fight, asks for each seal by the rank you know
-- (C_UnitAuras.GetPlayerAuraBySpellID) and keeps the last state when the
-- game answers nothing there; its time runs on the game's clock.
local SEAL_KEYS = { "sealCommand", "sealRight", "sealWisdom", "sealLight", "sealJustice", "sealCrusader" }
local SEAL_SIZE = 24

local function SealIcon(V, cfg)
    local icon = V.sealIcon
    local size = cfg.resources.sealIconSize or SEAL_SIZE
    if not icon then
        icon = W.CreateIcon(V.Mana, { width = size, height = size, zoom = W.ICON_ZOOM, keepAspect = true, inverse = true })
        icon:SetFrameStrata(HUD_STRATA)
        icon:SetPoint("RIGHT", V.manaBar, "LEFT", -4, 0)
        icon:AddText("p", "CENTER", 11, { 1, 1, 1, 1 })
        icon:Hide()
        icon._size = size
        V.sealIcon = icon
    elseif icon._size ~= size then
        icon._size = size
        icon:SetSize(size, size)
    end
    return icon
end

local function ForeverSeal(VS)
    local UA = C_UnitAuras
    local get = UA and UA.GetPlayerAuraBySpellID
    if not (get and ns.ModernClient and ns.ModernClient()) then return nil end
    for _, key in ipairs(SEAL_KEYS) do
        local name = VS.auraNames[key]
        local id = name and GetSpellInfo and select(7, GetSpellInfo(name))
        if type(id) == "number" and not Hidden(id) then
            local ok, a = pcall(get, id)
            if ok and type(a) == "table" then return a end
        end
    end
    return nil
end

local function RefreshSeal(V, cfg)
    local r = cfg.resources
    if not (r.sealIcon and V.manaBar) then
        if V.sealIcon then V.sealIcon:Hide() end
        return
    end
    local icon = SealIcon(V, cfg)
    local VS = V.S
    local shown = false
    if On(V, cfg) then
        local b
        for _, key in ipairs(SEAL_KEYS) do
            local name = VS.auraNames[key]
            b = name and VS.buffs[name:lower()]
            if b then break end
        end
        if b then
            V.sealHidden = nil
            V.sealRef = b
            icon:SetIconTexture(b.icon or 134400)
            if (b.duration or 0) > 0 then icon:SetSwipe(b.expirationTime - b.duration, b.duration) else icon:ClearSwipe() end
            shown = true
        elseif not V.sample then
            local a = ForeverSeal(VS)
            if a then
                V.sealHidden, V.sealRef = a, nil
                icon:SetHiddenTexture(a.icon)
                icon:SetHiddenSwipe("player", a)
                shown = true
            elseif V.sealHidden and VS.inCombat then
                shown = true   -- (nothing answered in a fight: as it was)
            else
                V.sealHidden, V.sealRef = nil, nil
            end
        end
        if not shown and V.preview then
            V.sealRef = nil
            icon:SetIconTexture(VS.auraIcons.sealRight or 134400)
            icon:ClearSwipe()
            shown = true
        end
    end
    icon:SetShown(shown)
end

local function SealText(V)
    local icon = V.sealIcon
    if not (icon and icon:IsShown()) then return end
    local b = V.sealRef
    if b and (b.expirationTime or 0) > 0 then
        icon:SetText("p", W.FormatTime(math.max(0, b.expirationTime - GetTime()), 0))
    elseif V.sealHidden then
        local left = ns.AuraTimeLeft and ns.AuraTimeLeft("player", V.sealHidden)
        if left ~= nil then icon:SetHiddenText("p", "%.0f", left) else icon:SetText("p", "") end
    else
        icon:SetText("p", "")
    end
end

local function RefreshResources(V, cfg)
    local VS = V.S
    local r = cfg.resources
    local show = On(V, cfg)

    local now = GetTime()
    local swingActive = VS.swing.duration > 0 and (VS.swing.start + VS.swing.duration) > now
    local swingShow = show and r.swingTimer and (V.preview or (VS.inCombat and (swingActive or V.sample)))
    V.swingBar:SetShown(swingShow or false)
    if swingShow and not V.swingDriver:IsShown() then V.swingDriver:Show() end

    V.manaBar:SetShown(show and r.manaBar or false)
    V.mp5Bar:SetShown(show and r.mp5Bar or false)

    -- Righteous Fury missing (only when RF is known - prot toggle)
    local rfShow = false
    if show and r.rfText then
        if V.preview or V.sample then
            rfShow = true
        else
            local rf = VS.spells.righteousFury
            local name = rf and rf.name
            rfShow = (rf and rf.known and name and not VS.buffs[name:lower()]) and true or false
        end
    end
    V.rfText:SetShown(rfShow)

    local blessShow = false
    if show and r.blessingText then
        if V.preview or V.sample then
            blessShow = true
        else
            local found = false
            for lname in pairs(VS.buffs) do
                if VS.blessingNames[lname] then found = true break end
            end
            blessShow = not found
        end
    end
    V.blessText:SetShown(blessShow)
    RefreshSeal(V, cfg)
end

local auxShown = {}
local function RefreshAux(V, cfg)
    local VS = V.S
    local a = cfg.aux
    local shownList = auxShown
    wipe(shownList)
    for _, key in ipairs({ "trinket1", "trinket2", "racial" }) do
        local icon = V.auxIcons[key]
        local def = icon.def
        local shown = false
        if On(V, cfg) and a.enabled and a[key] then
            if def.slot then
                local t = VS.trinkets[def.slot]
                if t and t.texture then
                    icon:SetIconTexture(t.texture)
                    icon:SetSwipe(t.start, t.duration)
                    icon:SetDesat((t.duration or 0) > GCD_MAX)
                    shown = true
                end
            elseif VS.racial then
                icon:SetIconTexture(VS.racial.icon)
                local start, duration = RacialCD(V)
                icon:SetSwipe(start, duration)
                icon:SetDesat(duration > GCD_MAX)
                shown = true
            end
        end
        W.SetShownAnimated(icon, shown)
        if shown then shownList[#shownList + 1] = icon end
    end
    local size = a.iconSize or 30
    HUD.LayoutRow(V.memo.aux, shownList, V.Aux, size, size, a.spacing or 4)
end

-- Builds a view the first time, then redraws it from its state.
local function RefreshView(V)
    if not V.Main then return end         -- non-paladin: no anchors exist
    if not W then
        W = ns.WarriorHUD and ns.WarriorHUD.Widgets or nil
        if not W then return end
    end
    if not V.built then
        V.built = true
        BuildMainIcons(V)
        BuildAuraIcons(V)
        BuildBars(V)
        BuildAux(V)
        V.col = nil
        if V == LIVE then ApplyAnchorPositions() end
    end
    local cfg = PH.Store()
    if not cfg then return end
    Colors(V)
    RefreshMainRow(V, cfg)
    RefreshAuraRow(V, cfg)
    RefreshResources(V, cfg)
    RefreshAux(V, cfg)
end

-- Sizes after settings changes (frames persist; only sizes move).
local function ApplyViewSizes(V, cfg)
    -- Main-grid sizes are applied per row inside HUD.LayoutGrid; only bars/texts need updates here.
    local a = cfg.auraRow
    for _, def in ipairs(AURA_BUFF_IDS) do
        V.auraIcons[def.key]:SetSize(a.iconSize or 25, a.iconSize or 25)
    end
    local r = cfg.resources
    -- Holders follow the bar size too: the mover proxy is sized from them.
    if V.swingBar then
        V.swingBar:SetSize(r.swing.w or 316, r.swing.h or 2)
        V.Swing:SetSize(r.swing.w or 316, r.swing.h or 2)
        if V == LIVE then holders.Swing:SetSize(r.swing.w or 316, r.swing.h or 2) end
    end
    if V.manaBar then
        V.manaBar:SetSize(r.mana.w or 234, r.mana.h or 4)
        V.mp5Bar:SetSize(r.mana.w or 234, r.mana.h or 4)
        V.Mana:SetSize(r.mana.w or 234, (r.mana.h or 4) * 2 + 2)
        if V == LIVE then holders.Mana:SetSize(r.mana.w or 234, (r.mana.h or 4) * 2 + 2) end
    end
    if V.rfText then
        HUD.ApplyFont(V.rfText, r.texts.size or 20, "OUTLINE", "alert")
        HUD.ApplyFont(V.blessText, r.texts.size or 20, "OUTLINE", "alert")
    end
end

-- Display facade
PH.Display = {}

function PH.Display:Refresh()
    RefreshView(LIVE)
end

function PH.Display:HideAll()
    local V = LIVE
    if not V.built then return end
    for _, m in pairs(V.memo) do HUD.ForgetLayout(m) end
    for _, icon in pairs(V.mainIcons) do icon:Hide() end
    for _, icon in pairs(V.auraIcons) do icon:Hide() end
    for _, icon in pairs(V.auxIcons) do icon:Hide() end
    if V.swingBar then V.swingBar:Hide() end
    if V.manaBar then V.manaBar:Hide() end
    if V.mp5Bar then V.mp5Bar:Hide() end
    if V.rfText then V.rfText:Hide() end
    if V.blessText then V.blessText:Hide() end
    if V.sealIcon then V.sealIcon:Hide() end
end

-- Rebuild sizes after settings changes (frames persist; only sizes/positions move).
function PH.Display:ApplySizes()
    if not LIVE.built then return end
    local cfg = PH.Store()
    if not cfg then return end
    ApplyViewSizes(LIVE, cfg)
    ApplyAnchorPositions()
    PH.Display:Refresh()
end

-- Text ticker (0.1s): cooldown countdowns
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
        end
    end
    for _, icon in ipairs(V.auraActive) do
        local b = icon.buffRef
        if b and (b.expirationTime or 0) > 0 then
            icon:SetText("p",
                W.FormatTime(math.max(0, b.expirationTime - GetTime()), 0))
        else
            icon:SetText("p", "")
        end
        icon:SetText("s", (b and (b.count or 0) > 1) and tostring(b.count) or "")
    end
    for key, icon in pairs(V.auxIcons) do
        if icon:IsShown() then
            local remaining = 0
            local def = icon.def
            if def.slot then
                local t = VS.trinkets[def.slot]
                if t and (t.duration or 0) > GCD_MAX then
                    remaining = math.max(0, t.start + t.duration - GetTime())
                end
            elseif VS.racial then
                local start, duration = RacialCD(V)
                if duration > GCD_MAX then
                    remaining = math.max(0, start + duration - GetTime())
                end
            end
            icon:SetText("p", remaining > 0 and W.FormatTime(remaining, 0) or "")
        end
    end
    SealText(V)
end

local function TextTick()
    if not PH:IsActive() then return end
    TextTickView(LIVE)
end

-- ------------------------------------------------------------
-- The settings preview's sample: a view on the dock's canvas, made-up
-- state, stacked top to bottom (texts, buffs, swing, mana, grid, trinkets).
-- ------------------------------------------------------------
local SAMPLE_W, SAMPLE_H = 500, 112   -- the fitting sizes the canvas to the sample

local function NewSampleView(canvas)
    local VS = {
        inCombat = true, spells = {}, cds = {}, usable = {}, inRange = {}, buffs = {},
        auraNames = {}, auraIcons = {}, blessingNames = {}, targetAttackable = true,
        swing = { start = 0, duration = 0 }, mp5 = { start = 0, duration = 0 },
        items = {}, itemCDs = {}, trinkets = {}, racial = nil,
    }
    local V = NewView(VS)
    V.sample, V.canvas = true, canvas
    V.Main = HUD.SampleAnchor(canvas, 36, 28)
    V.AuraRow = HUD.SampleAnchor(canvas, 25, 25)
    V.Swing = HUD.SampleAnchor(canvas, 316, 2)
    V.Mana = HUD.SampleAnchor(canvas, 234, 10)
    V.Texts = HUD.SampleAnchor(canvas, 240, 30)
    V.Aux = HUD.SampleAnchor(canvas, 30, 30)
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
    for _, def in ipairs(MAIN_DEFS) do
        if def.kind == "spell" then
            i = i + 1
            local id = SPELL_IDS[def.spell]
            local name, _, icon = GetSpellInfo and GetSpellInfo(id)
            VS.spells[def.spell] = { name = name or def.label, known = true,
                icon = icon or (GetSpellTexture_C and GetSpellTexture_C(id)) or 134400 }
            local onCd = combat and i % 3 == 2
            VS.cds[def.spell] = { start = onCd and (now - 4 * i) or 0, duration = onCd and (30 + 20 * i) or 0, real = onCd }
            VS.usable[def.spell] = { usable = true, noPower = combat and i == 4 }
            VS.inRange[def.spell] = (combat and i == 5) and 0 or nil
        end
    end
    wipe(VS.buffs)
    for k, def in ipairs(AURA_BUFF_IDS) do
        local name, _, icon = GetSpellInfo and GetSpellInfo(def.id)
        VS.auraNames[def.key] = name or def.label or def.key
        VS.auraIcons[def.key] = icon or 134400
        if combat and k <= 4 then
            local n = VS.auraNames[def.key]
            VS.buffs[n:lower()] = { name = n, icon = VS.auraIcons[def.key], count = (k == 2) and 3 or 0,
                duration = 30, expirationTime = now + 30 - 6 * k }
        end
    end
    wipe(VS.items)
    wipe(VS.itemCDs)
    local pot = WH and WH.POTION_DROPDOWN and WH.POTION_DROPDOWN[13] or (WH and WH.POTION_LIST and WH.POTION_LIST[1])
    if pot then
        VS.items[pot.id] = 5
        if combat then VS.itemCDs[pot.id] = { start = now - 30, duration = 120 } end
    end
    VS.items[RUNE_LIST[1].id] = 3
    VS.mana, VS.manaMax = combat and 4300 or 6900, 7500
    VS.swing.start, VS.swing.duration = now - 0.9, 3.4
    VS.mp5.start, VS.mp5.duration = now - 1.5, combat and 5 or 2
    VS.trinkets[13] = { texture = 133447, start = combat and (now - 40) or 0, duration = combat and 120 or 0 }
    VS.trinkets[14] = { texture = 133434, start = 0, duration = 0 }
    VS.racial = { name = "Racial", icon = 136225, start = combat and (now - 20) or 0, duration = combat and 180 or 0 }
end

-- the pieces exactly where the HUD puts them on screen (HUD.RealSample)
local function LayoutSample(V, cfg)
    local r = cfg.resources
    local nT = (r.rfText and 1 or 0) + (r.blessingText and 1 or 0)
    HUD.RealSample(V.canvas, {
        { a = V.Main, mover = "phMainRow", store = cfg.mainRow, scale = cfg.mainRow.scale or 1, on = true },
        { a = V.AuraRow, mover = "phAuraRow", store = cfg.auraRow, scale = cfg.auraRow.scale or 1, on = cfg.auraRow.enabled ~= false },
        { a = V.Swing, mover = "phSwing", store = r.swing, on = r.swingTimer },
        { a = V.Mana, mover = "phMana", store = r.mana, on = r.manaBar or r.mp5Bar },
        { a = V.Texts, mover = "phTexts", store = r.texts, on = nT > 0 },
        { a = V.Aux, mover = "phAux", store = cfg.aux, on = cfg.aux.enabled },
    })
end

local function PreviewSpec()
    return {
        key = "hud.paladin", title = "Paladin HUD",
        width = SAMPLE_W, height = SAMPLE_H,
        modes = { { id = "combat", label = "In combat" }, { id = "ready", label = "Out of combat" } },
        build = function(canvas, P) P.store.view = NewSampleView(canvas) end,
        update = function(canvas, P)
            local V = P.store.view
            local cfg = PH.Store()
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
            HUD.ReplayIcons({ V.mainIcons, V.auraIcons, V.auxIcons }, true)
        end,
    }
end

local function EnsureTextTicker()
    if textTicker then return end
    textTicker = HUD.Ticker(0.1, TextTick)
end

-- Core ticker (0.2s)
local coreTicker = nil

-- High-frequency events (CLEU, mana ticks, casts, bag updates) are only
-- registered while the HUD actually runs; bound below the event frame.
local RegisterHotEvents, UnregisterHotEvents

local function CoreTick()
    local cfg = PH.Store()
    if not cfg or not cfg.enabled or not S.isPaladin then return end
    if dirty.spells then dirty.spells = false ResolveSpells() end
    if dirty.bags then dirty.bags = false ScanItems() end
    if dirty.auras then dirty.auras = false ScanPlayerBuffs() end
    UpdateMisc()
    UpdateSpellSnapshot()
    PH.Display:Refresh()
end

local function StartTicker()
    if coreTicker then return end
    coreTicker = HUD.Ticker(0.2, CoreTick)
    EnsureTextTicker()
    if RegisterHotEvents then RegisterHotEvents() end
    -- The world moved on while the HUD was off; rescan everything.
    dirty.auras, dirty.bags, dirty.spells = true, true, true
    itemCD.MarkDirty()
end

local function StopTicker()
    if coreTicker then coreTicker:Cancel() coreTicker = nil end
    if textTicker then textTicker:Cancel() textTicker = nil end
    if UnregisterHotEvents then UnregisterHotEvents() end
end

function PH:SetEnabled(on)
    local cfg = PH.Store()
    if cfg then cfg.enabled = on and true or false end
    if on and S.isPaladin then
        StartTicker()
    else
        StopTicker()
        PH.Display:HideAll()
    end
end

function PH:IsActive()
    local cfg = PH.Store()
    return (cfg and cfg.enabled and S.isPaladin) and true or false
end

-- Event wiring
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")

-- Hot events live only while the HUD runs (see StartTicker/StopTicker).
RegisterHotEvents = function()
    lastMana = UnitPower("player", 0) or 0
    if Hidden(lastMana) then lastMana = nil end
    ns.CLEU.On("PaladinHUD", SWING_SUBS, OnCombatLogEvent)
    ns.Swings.On("PaladinHUD", OnSwing)
    ev:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    ev:RegisterEvent("BAG_UPDATE_DELAYED")
end
UnregisterHotEvents = function()
    ns.CLEU.Off("PaladinHUD")
    ns.Swings.On("PaladinHUD", nil)
    ev:UnregisterEvent("UNIT_POWER_FREQUENT")
    ev:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    ev:UnregisterEvent("BAG_UPDATE_DELAYED")
end
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        local _, class = UnitClass("player")
        S.isPaladin = class == "PALADIN"
        if not S.isPaladin then
            ev:UnregisterAllEvents()
            return
        end
        playerGUID = UnitGUID("player")
        lastMana = UnitPower("player", 0) or 0
        if Hidden(lastMana) then lastMana = nil end
        S.inCombat = InCombatLockdown() or UnitAffectingCombat("player")

        ev:RegisterEvent("PLAYER_ENTERING_WORLD")
        -- the player's auras: ZacUI's shared read says when they moved
        ns.PlayerAuras.On("PaladinHUD", function() dirty.auras = true end)
        ev:RegisterEvent("SPELLS_CHANGED")
        ev:RegisterEvent("PLAYER_REGEN_DISABLED")
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
        -- the combat log / UNIT_POWER_FREQUENT / UNIT_SPELLCAST_SUCCEEDED /
        -- BAG_UPDATE_DELAYED register in StartTicker, only while enabled.

        local cfg = PH.Store()
        if cfg and cfg.enabled then StartTicker() end
        HUD.Debug("PaladinHUD core initialized")
    elseif event == "UNIT_POWER_FREQUENT"
        or event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnManaEvent(event)
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
        dirty.auras, dirty.bags, dirty.spells = true, true, true
        itemCD.MarkDirty()
    end
end)

-- Settings page: General | Look | Text | Animation | Position | Advanced,
-- with the HUD drawn in the preview dock beside it.
local M = UI.M
local Check, SliderPair, CheckGrid = HUD.CheckIndent, HUD.SliderPair, HUD.CheckGrid
local function Px(v) return v .. " px" end
local function Refresh() PH.Display:Refresh() end

local function Tab_General(L, cfg)
    L:Card("Paladin HUD")
    L:Desc("Native port of the Paladin Class Pack WeakAura, styled like the "
        .. "Warrior HUD. Cooldown grid, active-buff row, swing timer, mana "
        .. "+ MP5 tick bars and reminder texts. Paladin characters only.")
    Check(L, "Enable Paladin HUD", cfg.enabled, function(v)
        PH:SetEnabled(v)
    end)
    Check(L, "Show every element on screen (test)", PH.preview and true or false, function(v)
        PH.preview = v
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

    L:Card("Active buff row")
    Check(L, "Show the active buff row", cfg.auraRow.enabled ~= false, function(v)
        cfg.auraRow.enabled = v
        Refresh()
    end)
    CheckGrid(L, AURA_BUFF_IDS,
        function(def) return def.label or S.auraNames[def.key] or def.key end,
        function(def) return not cfg.auraRow.hidden[def.key] end,
        function(def, v)
            cfg.auraRow.hidden[def.key] = (not v) and true or nil
            Refresh()
        end)
    L:EndCard()

    L:Card("Bars and reminders")
    local r = cfg.resources
    Check(L, "Swing timer bar (combat only)", r.swingTimer, function(v) r.swingTimer = v Refresh() end)
    Check(L, "Mana bar", r.manaBar, function(v) r.manaBar = v Refresh() end)
    Check(L, "MP5 tick bar (drink / five-second rule)", r.mp5Bar, function(v) r.mp5Bar = v Refresh() end)
    Check(L, "\"Righteous Fury\" missing text", r.rfText, function(v) r.rfText = v Refresh() end)
    Check(L, "\"Blessing\" missing text", r.blessingText, function(v) r.blessingText = v Refresh() end)
    Check(L, "Active seal icon by the mana bar", r.sealIcon or false, function(v)
        r.sealIcon = v or nil
        Refresh()
        HUD.RefreshPage()
    end, nil, "Your seal and its time left, next to the mana bar.")
    if r.sealIcon then
        HUD.Slider(L, "Seal icon size", 14, 48, r.sealIconSize or SEAL_SIZE, function(v)
            r.sealIconSize = (v ~= SEAL_SIZE) and v or nil
            Refresh()
        end, { width = 240, format = Px })
    end
    L:EndCard()

    L:Card("Trinkets and racial")
    Check(L, "Show the trinket and racial row", cfg.aux.enabled, function(v) cfg.aux.enabled = v Refresh() end)
    Check(L, "Trinket slot 1", cfg.aux.trinket1, function(v) cfg.aux.trinket1 = v Refresh() end, 16)
    Check(L, "Trinket slot 2", cfg.aux.trinket2, function(v) cfg.aux.trinket2 = v Refresh() end, 16)
    Check(L, "Racial ability", cfg.aux.racial, function(v) cfg.aux.racial = v Refresh() end, 16)
    L:EndCard()
end

local COLOR_LABELS = {
    { "oor", "Out of range tint" }, { "timer", "Timer text" }, { "count", "Count text" },
    { "text", "Reminder text" }, { "barText", "Mana value text" },
    { "mana", "Mana bar" }, { "mp5", "MP5 tick bar" }, { "swing", "Swing timer" },
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
        { "Active buff icon size", 14, 48, cfg.auraRow.iconSize, function(v) cfg.auraRow.iconSize = v PH.Display:ApplySizes() end, Px },
        { "Active buff spacing", 0, 12, cfg.auraRow.spacing, function(v) cfg.auraRow.spacing = v Refresh() end, Px })
    SliderPair(L,
        { "Mana bar width", 100, 500, r.mana.w, function(v) r.mana.w = v PH.Display:ApplySizes() end, Px },
        { "Mana bar height", 2, 16, r.mana.h, function(v) r.mana.h = v PH.Display:ApplySizes() end, Px })
    SliderPair(L,
        { "Swing bar width", 100, 500, r.swing.w, function(v) r.swing.w = v PH.Display:ApplySizes() end, Px },
        { "Swing bar height", 1, 12, r.swing.h or 2, function(v) r.swing.h = v PH.Display:ApplySizes() end, Px })
    SliderPair(L,
        { "Trinket icon size", 16, 56, cfg.aux.iconSize or 30, function(v) cfg.aux.iconSize = v Refresh() end, Px },
        { "Trinket spacing", 0, 12, cfg.aux.spacing or 4, function(v) cfg.aux.spacing = v Refresh() end, Px })
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

local function Tab_Text(L, cfg)
    local r = cfg.resources
    HUD.SharedTextCards(L, { label = "Reminder text", defaultSize = 20, sample = "Righteous Fury",
        getSize = function() return r.texts.size or 20 end,
        setSize = function(v) r.texts.size = v PH.Display:ApplySizes() end })
end

local function Tab_Position(L, cfg)
    L:Card("Position")
    L:Desc("Every piece of the HUD is its own anchor: drag them to line up with your unit frames.")
    HUD.UnlockButton(L, "ph")
    L:Gap(4)
    HUD.ScaleSlider(L, "Cooldown grid scale", cfg.mainRow, "scale", ApplyAnchorPositions)
    HUD.ScaleSlider(L, "Active buff row scale", cfg.auraRow, "scale", ApplyAnchorPositions)
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
    L:Header("Paladin HUD",
        "WeakAura port: cooldown grid, active-buff row, swing timer, mana "
        .. "+ MP5 bars and reminder texts")
    local cfg = PH.Store()
    if not cfg then
        L:Notice("missing", "The HUD settings are not available yet.")
        return
    end
    -- fitted after every update: in the dock's strata, inside the canvas
    L:Preview(HUD.FitSpec(PreviewSpec()))
    L:Tabs({
        { id = "general", label = "General",   build = function(L2) Tab_General(L2, cfg) end },
        { id = "look",    label = "Look",      build = function(L2) Tab_Look(L2, cfg) end },
        { id = "text",    label = "Text",      build = function(L2) Tab_Text(L2, cfg) end },
        { id = "anim",    label = "Animation", build = function(L2) HUD.SharedAnimCards(L2) end },
        { id = "pos",     label = "Position",  build = function(L2) Tab_Position(L2, cfg) end },
        { id = "adv",     label = "Advanced",  build = function(L2) Tab_Advanced(L2, cfg) end },
    })
end

HUD.RegisterPage("paladin", "Paladin HUD",
    "paladin hud pally class pack weakaura cooldown grid seals seal judgement "
    .. "blessing swing timer mana bar mp5 righteous fury trinkets racial "
    .. "active buffs potion rune " .. HUD.PAGE_KEYWORDS,
    { PALADIN = true },
    BuildPage)
