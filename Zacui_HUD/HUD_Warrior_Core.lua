-- HUD_Warrior_Core - state engine for the Warrior HUD (WeakAura-style class
-- pack port): cooldowns, auras, stance, swing timers, dodge window,
-- queued swings, items, nameplate counts. Rendering: HUD_Warrior_Display.
-- Part of ZacUI; load order is set by the TOC.
-- Storage: ZacUIDB.hud.warrior. Perf: event handlers only set dirty
-- flags/timestamps; every scan runs in the core ticker (0.2s while there
-- is something to show, about once a second idle); the combat log comes
-- through ZacUI's shared reader (ns.CLEU), the player's auras through
-- ns.PlayerAuras and the dodge window through ns.Misses.
local ADDON_NAME = ...
-- Zacui_HUD is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end
if not ns.HUD then return end   -- (the part stands down on this game version: HUD_Shared, Core_Flavor)
local HUD = ns.HUD
local UI = ns.UI
local Print = ns.Print

ns.WarriorHUD = ns.WarriorHUD or {}
local WH = ns.WarriorHUD

-- API compatibility (Interface 11509 / 20506): HUD_Shared carries the
-- shims every HUD used to duplicate privately.
local GetSpellInfo       = HUD.GetSpellInfo
local CompatUnitAura     = HUD.UnitAura

-- Container API (still needed directly here: ScanBags caches bag/slot
-- pairs for the whole tracked-item set, a wider net than the shared
-- per-item tracker).
local GetContainerNumSlots_C     = HUD.GetContainerNumSlots
local GetContainerItemID_C       = HUD.GetContainerItemID
local GetContainerItemCooldown_C = HUD.GetContainerItemCooldown

local GetSpellCooldown_C = HUD.GetSpellCooldown
local IsUsableSpell_C    = HUD.IsUsableSpell
local IsSpellInRange_C   = HUD.IsSpellInRange
local GetSpellTexture_C  = HUD.GetSpellTexture
local IsCurrentSpell_C   = HUD.IsCurrentSpell

-- Settings storage (ZacUIDB.hud.warrior)
local DEFAULTS = {
    enabled = true,

    -- Row/group toggles + saved anchor offsets (WA group offsets, all
    -- relative to screen CENTER). hidden = { [key] = true } removes an
    -- icon; custom = { { input = "name or spellId", kind = "cd"|"buff",
    -- stance = 0 (any)|1|2|3 } }; rows = per-row icon dims/capacity
    -- (WA: 8/9/8 at 26/24/26, 3px spacing), overflow fills the last row.
    mainRow   = { enabled = true, x = 7.44, y = -219.21, scale = 1,
                  spacing = 3,
                  rows = { { limit = 8, w = 26, h = 26 },
                           { limit = 9, w = 24, h = 24 },
                           { limit = 8, w = 26, h = 26 } },
                  -- macroBind: icon key -> smart macro name. A bound icon
                  -- draws whatever that macro currently resolves to instead
                  -- of picking from its own item list.
                  hidden = {}, custom = {}, macroBind = {} },
    -- Each resources element is independently movable/sizable (defaults
    -- are the WA group offset + child offset from screen CENTER).
    resources = { enabled = true,
                  stanceHud = true, executeHelper = true,
                  rageBar = true, swingTimer = true,
                  rageQueue = true,    -- the rage a queued Heroic Strike / Cleave will spend, on the bar
                  rageMarks = true,    -- marks at what Bloodthirst and Whirlwind cost
                  stance  = { x = -140.44, y = -222.97, scale = 1 },
                  execute = { x = 157.41,  y = -183.06, scale = 1 },
                  rage    = { x = 7.44,    y = -199.67, w = 229, h = 4 },
                  swing   = { x = 7.44,    y = -185,    w = 229, h = 3 } },
    auraRow   = { enabled = true, x = 7.44, y = -146, scale = 1,
                  iconW = 30, iconH = 30, spacing = 4,
                  hidden = {}, custom = {} },

    -- WA custom options (the pack's config); defaults = exported aura values.
    potionChoice   = 16,    -- Mighty Rage Potion (dropdown index)
    sapperThreshold = 7,    -- nameplates in range before the sapper glows
    sapperTTS      = false, -- speak "Sapper Now" when threshold met
    wwCount        = true,  -- Whirlwind icon: how many mobs are in reach
    wwFlashAt      = 4,     -- ...and it flashes from this many, while WW is ready

    -- Appearance (settings page)
    textSizes  = { timer = 14, count = 12 },
    borderSize = 1,
    -- the HUD's own colours (Look tab); the defaults are the WeakAura's
    colors = {
        rage        = { r = 0.7804, g = 0.2510, b = 0.2510, a = 1 },
        rageLow     = { r = 0.9961, g = 0.2980, b = 0.3098, a = 1 },
        rageText    = { r = 1, g = 1, b = 1, a = 1 },
        queueHS     = { r = 1, g = 0.8, b = 0.25, a = 0.9 },
        queueCleave = { r = 0.35, g = 0.95, b = 0.35, a = 0.9 },
        swingMH     = { r = 1, g = 1, b = 1, a = 1 },
        swingOH     = { r = 0.56, g = 0.71, b = 0.85, a = 1 },
        oor         = { r = 1, g = 0.2431, b = 0.2275, a = 1 },
        timer       = { r = 1, g = 1, b = 1, a = 1 },
    },
}
WH.COLOR_DEFAULTS = DEFAULTS.colors

function WH.Store()
    local cfg = HUD.Store("warrior", DEFAULTS)
    if not cfg then return nil end
    -- Migration: monolithic resources x/y replaced by per-element offsets.
    local r = cfg.resources
    if r then r.x, r.y = nil, nil end
    -- Migration: Blizzard styling option removed; always flat style now.
    cfg.blizzStyle = nil
    return cfg
end

-- Static data (verbatim from the decoded WeakAura)
-- Potion priority (WA aura_env.itemIds of the "Potion" aura): first
-- item with count > 0 is shown when no priority potion is picked.
WH.POTION_LIST = {
    { id = 13444, icon = 134856 }, -- Major Mana Potion
    { id = 13443, icon = 134854 }, -- Superior Mana Potion
    { id = 6149,  icon = 134853 }, -- Greater Mana Potion
    { id = 3827,  icon = 134852 }, -- Mana Potion
    { id = 3385,  icon = 134851 }, -- Lesser Mana Potion
    { id = 2455,  icon = 134850 }, -- Minor Mana Potion
    { id = 3387,  icon = 134842 }, -- Limited Invulnerability Potion
    { id = 5634,  icon = 134715 }, -- Free Action Potion
    { id = 13442, icon = 134821 }, -- Mighty Rage Potion
    { id = 5633,  icon = 134801 }, -- Great Rage Potion
    { id = 5631,  icon = 134804 }, -- Rage Potion
    { id = 13455, icon = 134849 }, -- Greater Stoneshield Potion
    { id = 4623,  icon = 134847 }, -- Lesser Stoneshield Potion
    { id = 13446, icon = 134834 }, -- Major Healing Potion
    { id = 3928,  icon = 134833 }, -- Superior Healing Potion
    { id = 1710,  icon = 134832 }, -- Greater Healing Potion
    { id = 929,   icon = 134831 }, -- Healing Potion
    { id = 858,   icon = 134830 }, -- Lesser Healing Potion
    { id = 118,   icon = 134829 }, -- Minor Healing Potion
}

-- TBC and Forever (the client, or the game-version override): that game's
-- potions join the list (from the consumables catalogue,
-- zui_tests/consumes), so the Automatic icon finds them; Classic Era's
-- stay, they are still in both games. The picker keeps Era's entries.
-- The icon is the game's, or an Era potion's look on a client that does
-- not know the item. Classic Era: nothing changes.
do
    local fl = ns.Flavor and ns.Flavor()
    local MANA, BURST, HEAL = 134856, 134821, 134834
    local MORE = {
        tbc = { before = {
            { 31677, MANA },  -- Fel Mana Potion
            { 22832, MANA },  -- Super Mana Potion
            { 32948, MANA },  -- Auchenai Mana Potion
            { 32902, MANA },  -- Bottled Nethergon Energy
            { 22838, BURST }, -- Haste Potion
            { 22828, BURST }, -- Insane Strength Potion
            { 22837, BURST }, -- Heroic Potion
            { 22839, BURST }, -- Destruction Potion
            { 22849, BURST }, -- Ironshield Potion
            { 22829, HEAL },  -- Super Healing Potion
            { 32947, HEAL },  -- Auchenai Healing Potion
            { 32905, HEAL },  -- Bottled Nethergon Vapor
        } },
        forever = { before = {
            { 250943, BURST }, -- Major Frenzy Potion
            { 250942, BURST }, -- Superior Frenzy Potion
            { 250937, MANA },  -- Major Spellblasting Potion
            { 250936, MANA },  -- Superior Spellblasting Potion
            { 250949, HEAL },  -- Major Mender's Potion
            { 250948, HEAL },  -- Superior Mender's Potion
        }, after = {
            { 247242, HEAL },  -- Superior Discolored Healing Potion
            { 274935, HEAL },  -- Tessa's Tonic
        } },
    }
    local m = fl and MORE[fl]
    if m then
        local function Row(e) return { id = e[1], icon = (GetItemIcon and GetItemIcon(e[1])) or e[2] } end
        local list = {}
        for _, e in ipairs(m.before or {}) do list[#list + 1] = Row(e) end
        for _, e in ipairs(WH.POTION_LIST) do list[#list + 1] = e end
        for _, e in ipairs(m.after or {}) do list[#list + 1] = Row(e) end
        WH.POTION_LIST = list
    end
end

-- Dropdown index -> item (aura_env.dropdownMap). Index 1 = automatic.
WH.POTION_DROPDOWN = {
    [1]  = nil,                            -- Automatic Icon
    [2]  = { id = 118,   icon = 134829, label = "Minor Healing Potion" },
    [3]  = { id = 858,   icon = 134830, label = "Lesser Healing Potion" },
    [4]  = { id = 929,   icon = 134831, label = "Healing Potion" },
    [5]  = { id = 1710,  icon = 134832, label = "Greater Healing Potion" },
    [6]  = { id = 3928,  icon = 134833, label = "Superior Healing Potion" },
    [7]  = { id = 13446, icon = 134834, label = "Major Healing Potion" },
    [8]  = { id = 2455,  icon = 134850, label = "Minor Mana Potion" },
    [9]  = { id = 3385,  icon = 134851, label = "Lesser Mana Potion" },
    [10] = { id = 3827,  icon = 134852, label = "Mana Potion" },
    [11] = { id = 6149,  icon = 134853, label = "Greater Mana Potion" },
    [12] = { id = 13443, icon = 134854, label = "Superior Mana Potion" },
    [13] = { id = 13444, icon = 134856, label = "Major Mana Potion" },
    [14] = { id = 5631,  icon = 134804, label = "Rage Potion" },
    [15] = { id = 5633,  icon = 134801, label = "Great Rage Potion" },
    [16] = { id = 13442, icon = 134821, label = "Mighty Rage Potion" },
    [17] = { id = 5634,  icon = 134715, label = "Free Action Potion" },
    [18] = { id = 3387,  icon = 134842, label = "Limited Invulnerability Potion" },
    [19] = { id = 13455, icon = 134849, label = "Greater Stoneshield Potion" },
    [20] = { id = 4623,  icon = 134847, label = "Lesser Stoneshield Potion" },
}

-- Dynamite/grenade priority list (the "Dense" aura).
WH.DENSE_LIST = {
    { id = 18641, icon = 133714 }, -- Dense Dynamite
    { id = 15993, icon = 133716 }, -- Thorium Grenade
    { id = 4390,  icon = 133716 }, -- Iron Grenade
    { id = 10507, icon = 133714 }, -- Solid Dynamite
    { id = 4378,  icon = 133714 }, -- Heavy Dynamite
    { id = 4365,  icon = 133714 }, -- Coarse Dynamite
    { id = 4358,  icon = 133714 }, -- Rough Dynamite
}

WH.SAPPER_ID = 10646        -- Goblin Sapper Charge (icon 135826)
WH.DUMMY_LIST = {
    { id = 16023, icon = 132762 }, -- Masterwork Target Dummy
}

-- On-next-swing rank chains (highest known rank is what gets queued).
local HS_RANKS     = { 25286, 11567, 11566, 11565, 11564, 1608, 285, 284, 78 }
local CLEAVE_RANKS = { 20569, 11609, 11608, 7369, 845 }

-- Trinket buffs tracked by the "Trinket 1 full" aura (name match).
WH.TRINKET_BUFFS = {
    "Earthstrike", "Diamond Flask", "Insight of the Qiraji",
    "Badge of the Swarmguard", "Kiss of the Spider", "Slayer's Crest",
}

-- Tracked spells (WA trigger ids), resolved once per spellbook change.
-- Keys are stable display-layer ids; lookups go through the spell NAME,
-- so the player's actual rank is used.
local SPELL_IDS = {
    mortalStrike  = 21553, deathWish   = 12328, reck        = 1719,
    retaliation   = 20230, shieldWall  = 871,   bloodthirst = 23881,
    whirlwind     = 1680,  overpower   = 7384,  revenge     = 11601,
    charge        = 11578, intercept   = 20617, bloodrage   = 2687,
    berserkerRage = 18499, taunt       = 355,   lastStand   = 12976,
    challShout    = 1161,  shieldBlock = 2565,  shieldBash  = 1672,
    thunderClap   = 6343,  sweeping    = 12292, pummel      = 6554,
    mockingBlow   = 20560, intimShout  = 5246,  disarm      = 676,
    execute       = 5308,  heroicStrike = 78,   cleave      = 845,
    battleShout   = 6673,
}

-- Player buff names resolved from the WA aura ids ("Active" row).
local BUFF_IDS = {
    shieldBlock = 2565,  enrage     = 13046, flurry     = 12970,
    reck        = 1719,  retaliation = 20230, shieldWall = 871,
    deathWish   = 12328, crusader   = 20007, mightyRage = 17528,
    stoneshield = 17540, fap        = 6615,  lip        = 3169,
    oil         = 11350, bloodrage  = 29131, lastStand  = 12976,
    sweeping    = 12292, hamstring  = 1715,  squawk     = 23060,
    salv        = 1038,  greaterSalv = 25895,
}

-- Live state (read by the display layer every refresh)
WH.State = {
    isWarrior   = false,
    stance      = 0,          -- GetShapeshiftForm(): 1 battle, 2 def, 3 zerk
    inCombat    = false,
    spells      = {},         -- key -> { name, known, icon }
    buffNames   = {},         -- key -> resolved localized name
    buffIcons   = {},         -- key -> spell icon (for settings preview)
    cds         = {},         -- key -> { start, duration, real } (real = not just GCD)
    usable      = {},         -- key -> { usable, noPower }
    keyByName   = {},         -- spell name -> key (Hesitation reads through it)
    inRange     = {},         -- key -> 1 / 0 / nil (IsSpellInRange on target)
    buffs       = {},         -- player HELPFUL by lower(name)
    selfDebuffs = {},         -- player HARMFUL by lower(name)
    hamstring   = nil,        -- my Hamstring on target { duration, expirationTime }
    targetAttackable = false,
    targetHPpct = 100,
    ap          = 0,
    lastDodge   = 0,          -- GetTime() of last enemy dodge of my attack
    hsQueued    = false,
    cleaveQueued = false,
    swing       = { mh = { start = 0, duration = 0 },
                    oh = { start = 0, duration = 0 }, hasOH = false },
    items       = {},         -- itemId -> { count, bag, slot }
    trinket13   = { texture = nil, start = 0, duration = 0, enable = 0 },
    plateCount  = 0,          -- attackable nameplates near the player (sapper)
}
local S = WH.State

-- Dirty flags (set by events, consumed by the core ticker)
local dirty = {
    auras = true, targetAuras = true, bags = true, spells = true,
}

local playerGUID = nil

-- Spellbook resolution
local function ResolveSpells()
    wipe(S.spells)          -- drop stale custom entries on rebuild
    wipe(S.keyByName)
    for key, id in pairs(SPELL_IDS) do
        local name = GetSpellInfo and GetSpellInfo(id) or nil
        local known, icon = false, nil
        if name then
            -- GetSpellInfo(name) only resolves spellbook spells: rank-free "known".
            local n2, _, tex = GetSpellInfo(name)
            known = n2 ~= nil
            icon = tex or (GetSpellTexture_C and GetSpellTexture_C(id))
        end
        S.spells[key] = { name = name, known = known, icon = icon }
        if known then S.keyByName[name] = key end
    end
    for key, id in pairs(BUFF_IDS) do
        if GetSpellInfo then
            local name, _, icon = GetSpellInfo(id)
            S.buffNames[key] = name
            S.buffIcons[key] = icon
        end
    end
    -- Name fallbacks for item-granted auras (WA matched by name string).
    S.buffNames.squawk = S.buffNames.squawk or "Battle Squawk"
    S.buffNames.crusader = S.buffNames.crusader or "Holy Strength"
    -- User-added cooldown icons, tracked like built-ins. Grid keys are
    -- "cust<i>", top-row "tcust<i>"; buff-kind resolves in the display.
    local function ResolveCustomList(list, prefix, defaultKind)
        if not list then return end
        for i, entry in ipairs(list) do
            if (entry.kind or defaultKind) == "cd" then
                local input, name = entry.input, nil
                local id = tonumber(input)
                if id then
                    name = GetSpellInfo and GetSpellInfo(id) or nil
                else
                    name = input
                end
                local known, icon = false, nil
                if name and GetSpellInfo then
                    local n2, _, tex = GetSpellInfo(name)
                    known, icon = n2 ~= nil, tex
                end
                S.spells[prefix .. i] = { name = name, known = known, icon = icon }
            end
        end
    end
    local cfg = WH.Store()
    if cfg then
        ResolveCustomList(cfg.mainRow.custom, "cust", "cd")
        ResolveCustomList(cfg.auraRow.custom, "tcust", "buff")
    end
    -- Highest known on-next-swing rank: IsCurrentSpell needs the exact id.
    S.hsRankId, S.cleaveRankId = nil, nil
    for _, id in ipairs(HS_RANKS) do
        if IsPlayerSpell and IsPlayerSpell(id) then S.hsRankId = id break end
    end
    for _, id in ipairs(CLEAVE_RANKS) do
        if IsPlayerSpell and IsPlayerSpell(id) then S.cleaveRankId = id break end
    end
    -- what each costs in rage, talents included (Improved Heroic Strike),
    -- read once here - spells or talents changing land here again
    local function Cost(id, fallback)
        return HUD.RageCost(id) or fallback
    end
    -- Heroic Strike: 15 rage, less 1 per point in Improved Heroic Strike
    -- (Arms, 3 points = 12). Read from the talent itself - the client's
    -- spell cost may or may not already have it folded in, so a cost the
    -- client reports below the base is taken as already reduced.
    local hsBase = 15
    local api = Cost(S.hsRankId, nil)
    if api and api < hsBase then
        S.hsCost = api
    else
        S.hsCost = hsBase - (WH.ImpHSRank and WH.ImpHSRank() or 0)
    end
    S.cleaveCost = Cost(S.cleaveRankId, 20)
    local function IdOf(key)
        local sp = S.spells[key]
        local id = sp and sp.name and select(7, GetSpellInfo(sp.name))
        return id
    end
    S.btCost = Cost(IdOf("bloodthirst"), 30)
    S.wwCost = Cost(IdOf("whirlwind"), 25)
end

-- Aura scanning (player buffs/debuffs + my Hamstring on target)
-- The entry for an aura name is kept between scans and its fields
-- rewritten; a scan runs up to five times a second in a fight and used
-- to make a fresh table per aura. Entries not seen this pass are dropped
-- afterwards, so a reader finds exactly what a rebuilt table would hold.
-- The player's own auras come from ZacUI's shared read (ns.PlayerAuras), one
-- read per change for every part.
local scanPass = 0
local function ScanAuraList(list, out)
    scanPass = scanPass + 1
    local pass = scanPass
    for i = 1, #list do
        local aura = list[i]
        local name = aura.name
        if name then
            local icon, count = aura.icon, aura.count
            local duration, expirationTime = aura.duration, aura.expirationTime
            local key = name:lower()
            local existing = out[key]
            if existing and existing.pass == pass then
                -- Track multiple applications (Crusader can be up twice).
                existing.matches = (existing.matches or 1) + 1
                -- and each one's own timer, for one icon per application
                local apps = existing.apps
                local a = apps[existing.matches]
                if not a then a = {}; apps[existing.matches] = a end
                a.icon, a.count = icon, 0
                a.duration, a.expirationTime = duration or 0, expirationTime or 0
                if (expirationTime or 0) > (existing.expirationTime or 0) then
                    existing.duration = duration
                    existing.expirationTime = expirationTime
                    existing.icon = icon
                end
            else
                if not existing then
                    existing = {}
                    out[key] = existing
                end
                existing.pass = pass
                existing.name, existing.icon, existing.count = name, icon, count or 0
                existing.duration, existing.expirationTime = duration or 0, expirationTime or 0
                existing.matches = 1
                existing.apps = existing.apps or {}
                local a = existing.apps[1]
                if not a then a = {}; existing.apps[1] = a end
                a.icon, a.count = icon, 0
                a.duration, a.expirationTime = existing.duration, existing.expirationTime
            end
        end
    end
    for key, e in pairs(out) do
        if e.pass ~= pass then out[key] = nil end
    end
end

local hamstringEntry = { duration = 0, expirationTime = 0 }
local function ScanTargetHamstring()
    S.hamstring = nil
    if not UnitExists("target") then return end
    local wanted = S.buffNames.hamstring
    if not wanted then return end
    if HUD.HIDDEN_AURAS then
        -- WoW Forever: found by its name while the game shows it; a
        -- hidden timer is shown as it is (hamstringEntry.hidden). With
        -- the name hidden too it can't be told from your other debuffs.
        HUD.EachMyTargetDebuff(function(name, a)
            if S.hamstring or name ~= wanted then return end
            if ns.AuraFieldsHidden(a) then
                hamstringEntry.duration, hamstringEntry.expirationTime, hamstringEntry.hidden = 0, 0, a
            else
                hamstringEntry.duration, hamstringEntry.expirationTime = a.duration or 0, a.expirationTime or 0
                hamstringEntry.hidden = nil
            end
            S.hamstring = hamstringEntry
        end)
        return
    end
    for i = 1, 40 do
        local name, _, _, _, duration, expirationTime, source = CompatUnitAura("target", i, "HARMFUL")
        if not name then break end
        if name == wanted and (source == "player" or source == nil) then
            hamstringEntry.duration, hamstringEntry.expirationTime = duration or 0, expirationTime or 0
            S.hamstring = hamstringEntry
            return
        end
    end
end

-- Bag scanning (counts + a bag/slot for cooldown polling)
local TRACKED_ITEMS = {}     -- itemId -> true (built below)
do
    for _, e in ipairs(WH.POTION_LIST) do TRACKED_ITEMS[e.id] = true end
    for _, e in ipairs(WH.DENSE_LIST) do TRACKED_ITEMS[e.id] = true end
    for _, e in ipairs(WH.DUMMY_LIST) do TRACKED_ITEMS[e.id] = true end
    TRACKED_ITEMS[WH.SAPPER_ID] = true
end

-- Items the HUD did not know about at load, added at runtime because a
-- smart macro resolved to one. GetItemCD reads S.items, so an id only has
-- to reach this set for cooldown polling to work on it.
local EXTRA_ITEMS = {}
function WH.TrackExtraItem(itemId)
    itemId = tonumber(itemId)
    if not itemId or TRACKED_ITEMS[itemId] or EXTRA_ITEMS[itemId] then return end
    EXTRA_ITEMS[itemId] = true
    dirty.bags = true
end

local function ScanBags()
    for id in pairs(EXTRA_ITEMS) do
        local entry = S.items[id]
        if not entry then entry = {} S.items[id] = entry end
        entry.count = GetItemCount and GetItemCount(id) or 0
        entry.bag, entry.slot = nil, nil
    end
    for id in pairs(TRACKED_ITEMS) do
        local entry = S.items[id]
        if not entry then entry = {} S.items[id] = entry end
        entry.count = GetItemCount and GetItemCount(id) or 0
        entry.bag, entry.slot = nil, nil
    end
    if not (GetContainerNumSlots_C and GetContainerItemID_C) then return end
    for bag = 0, 4 do
        local slots = GetContainerNumSlots_C(bag) or 0
        for slot = 1, slots do
            local itemId = GetContainerItemID_C(bag, slot)
            if itemId and (TRACKED_ITEMS[itemId] or EXTRA_ITEMS[itemId]) then
                local entry = S.items[itemId]
                if entry and not entry.bag then
                    entry.bag, entry.slot = bag, slot
                end
            end
        end
    end
end

-- Item cooldown via container slot (GetItemCooldown is retail-only).
-- The 0.1 s text tick and the 0.2 s core tick both ask; one read per
-- item per 0.2 s serves both (a cooldown's start/duration do not move
-- between reads, only the remaining time, which the caller derives).
local itemCdCache = {}
function WH.GetItemCD(itemId)
    local entry = S.items[itemId]
    if not (entry and entry.bag and GetContainerItemCooldown_C) then return 0, 0 end
    local now = GetTime()
    local c = itemCdCache[itemId]
    if c and (now - c.t) < 0.2 then return c.s, c.d end
    -- Re-check the slot still holds the item; bags may have shifted.
    if GetContainerItemID_C and GetContainerItemID_C(entry.bag, entry.slot) ~= itemId then
        dirty.bags = true
        return 0, 0
    end
    local start, duration = GetContainerItemCooldown_C(entry.bag, entry.slot)
    start, duration = start or 0, duration or 0
    if not c then c = {} itemCdCache[itemId] = c end
    c.s, c.d, c.t = start, duration, now
    return start, duration
end

function WH.FirstAvailable(list)
    for _, e in ipairs(list) do
        local entry = S.items[e.id]
        if entry and (entry.count or 0) > 0 then
            return e, entry.count
        end
    end
    return nil, 0
end

-- Nameplate scan for the sapper glow (WA: CheckRange 10yd on plates).
-- CheckInteractDistance index 3 (duel, ~9.9yd) is the classic-safe
-- stand-in; if the client protects it, degrade to any attackable plate.
local function ScanNameplates()
    local count = 0
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) and UnitCanAttack("player", unit) and not UnitIsDead(unit) then
            local ok, inRange = pcall(CheckInteractDistance, unit, 3)
            if not ok then
                count = count + 1          -- API protected: count all plates
            elseif inRange then
                count = count + 1
            end
        end
    end
    S.plateCount = count
end

-- Cooldown/usable/range snapshot (cheap C calls). One spell is read at a
-- time and stamped, so the Hesitation tick (10 Hz in combat) can ask for
-- the few it watches through WH.SpellState and only re-read what this
-- ticker has not just read: one snapshot for the HUD and Hesitation.
local GCD_MAX = 1.51
local FRESH = 0.08              -- a read younger than this is current
local spellStamp = {}           -- key -> GetTime() of its last read

local function ReadSpell(key, sp, now, attackable)
    local start, duration, enable, _, durObj = GetSpellCooldown_C(sp.name)
    -- (hidden on WoW Forever: read as ready)
    if ns.Hidden(start, duration, enable) then start, duration, enable = 0, 0, 1 end
    start, duration = start or 0, duration or 0
    local cd = S.cds[key]
    if not cd then cd = {} S.cds[key] = cd end
    cd.start, cd.duration, cd.enable = start, duration, enable
    cd.durObj = durObj   -- (WoW Forever: a hidden cooldown's swipe, on the game's clock)
    cd.real = duration > GCD_MAX               -- ignore pure GCD
    local us = S.usable[key]
    if not us then us = {} S.usable[key] = us end
    if IsUsableSpell_C then
        local usable, noPower = IsUsableSpell_C(sp.name)
        if ns.Hidden(usable, noPower) then usable, noPower = true, false end   -- (WoW Forever)
        us.usable, us.noPower = usable and true or false, noPower and true or false
    else
        us.usable, us.noPower = true, false
    end
    if attackable and IsSpellInRange_C then
        S.inRange[key] = IsSpellInRange_C(sp.name, "target")
    else
        S.inRange[key] = nil
    end
    spellStamp[key] = now
end

local queuedStamp = 0
local function ReadQueued(now)
    S.hsQueued = (S.hsRankId and IsCurrentSpell_C and IsCurrentSpell_C(S.hsRankId)) and true or false
    S.cleaveQueued = (S.cleaveRankId and IsCurrentSpell_C and IsCurrentSpell_C(S.cleaveRankId)) and true or false
    queuedStamp = now
end

local function UpdateSpellSnapshot()
    local now = GetTime()
    local attackable = S.targetAttackable
    for key, sp in pairs(S.spells) do
        if sp.known and sp.name then ReadSpell(key, sp, now, attackable) end
    end
    ReadQueued(now)
end

-- For Hesitation: the HUD's reading of a spell by NAME, re-read only when
-- older than FRESH. Returns cd { start, duration, real }, usable
-- { usable, noPower } and the range answer (1/0/nil; read here when the
-- caller has an attackable target and the stored reading had none).
-- nil when the HUD does not track that spell or is not running.
function WH.SpellState(name, attackable)
    if not WH.running then return nil end
    local key = name and S.keyByName[name]
    local sp = key and S.spells[key]
    if not (sp and sp.known) then return nil end
    local now = GetTime()
    if not spellStamp[key] or now - spellStamp[key] > FRESH then
        -- the HUD's own target reading too: a re-read here must not drop
        -- the range the grid's out-of-range tint shows
        ReadSpell(key, sp, now, attackable or S.targetAttackable)
    elseif attackable and S.inRange[key] == nil and IsSpellInRange_C then
        S.inRange[key] = IsSpellInRange_C(sp.name, "target")
    end
    return S.cds[key], S.usable[key], S.inRange[key]
end

-- For Hesitation: Heroic Strike / Cleave queued right now (nil when the
-- HUD is not running).
function WH.SwingQueued()
    if not WH.running then return nil end
    local now = GetTime()
    if now - queuedStamp > FRESH then ReadQueued(now) end
    return (S.hsQueued or S.cleaveQueued) and true or false
end

local function UpdateTargetSnapshot()
    S.targetAttackable = HUD.TargetAttackable()
    if S.targetAttackable then
        S.targetHPpct = HUD.TargetHealthFrac() * 100
    else
        S.targetHPpct = 100
    end
end

local function UpdateMisc()
    S.stance = GetShapeshiftForm and (GetShapeshiftForm() or 0) or 0
    -- NB: bare calls only - `and`-wrapping truncates multiple returns.
    local base, posBuff, negBuff
    if UnitAttackPower then base, posBuff, negBuff = UnitAttackPower("player") end
    -- WoW Forever can hand your attack power back hidden (secret values):
    -- no maths on it, so the last plain reading stays
    if issecretvalue ~= nil and (issecretvalue(base) or issecretvalue(posBuff) or issecretvalue(negBuff)) then
        S.ap = S.ap or 0
    else
        S.ap = (base or 0) + (posBuff or 0) + (negBuff or 0)
    end

    local t = S.trinket13
    t.texture = GetInventoryItemTexture and GetInventoryItemTexture("player", 13) or nil
    if GetInventoryItemCooldown then
        local start, duration, enable = GetInventoryItemCooldown("player", 13)
        -- (hidden on WoW Forever: read as ready)
        if ns.Hidden(start, duration, enable) then start, duration, enable = 0, 0, 1 end
        t.start, t.duration, t.enable = start or 0, duration or 0, enable or 0
    end
    -- Offhand weapon present? (second return of UnitAttackSpeed)
    if UnitAttackSpeed then
        local _, ohSpeed = UnitAttackSpeed("player")
        -- (WoW Forever may hide it: a hidden speed still means an offhand; no test on it)
        if ns.IsSecret(ohSpeed) then S.swing.hasOH = true else S.swing.hasOH = ohSpeed ~= nil end
    else
        S.swing.hasOH = false
    end
end

-- Combat log: swing timers + dodge window. Flag/timestamp writes only.
local HS_NAME, CLEAVE_NAME = nil, nil

-- A swing already under way when your attack speed changes (Flurry,
-- Enrage, a haste item running out) keeps its place: what is left is
-- stretched or shrunk to the new speed, so the bar changes pace instead
-- of jumping when the swing lands early or late.
local function RescaleSwing()
    if not UnitAttackSpeed then return end
    local mhSpeed, ohSpeed = UnitAttackSpeed("player")
    -- (WoW Forever may hide your attack speed: the swing keeps its pace)
    if ns.Hidden(mhSpeed, ohSpeed) then return end
    local now = GetTime()
    local sw = S.swing
    for i = 1, 2 do
        local t, new = (i == 1) and sw.mh or sw.oh, (i == 1) and mhSpeed or ohSpeed
        local old = t.duration or 0
        if new and new > 0 and old > 0 and math.abs(new - old) > 0.001 then
            local left = t.start + old - now
            if left > 0 then
                local newLeft = left * new / old
                t.start = now + newLeft - new
            end
            t.duration = new
        end
    end
end

-- Parry haste: when you parry, your next main-hand swing comes 40% of
-- your speed sooner, but never sooner than 20% of it left.
local function ParryHaste(now)
    local t = S.swing.mh
    local dur = t.duration or 0
    if dur <= 0 then return end
    local left = t.start + dur - now
    if left > 0.2 * dur then
        local newLeft = left - 0.4 * dur
        if newLeft < 0.2 * dur then newLeft = 0.2 * dur end
        t.start = t.start - (left - newLeft)
    end
end

-- The combat log through ZacUI's shared reader: fn gets the values of
-- CombatLogGetCurrentEventInfo() (dest = 8th, arg12.. after that).
local SWING_SUBS = { "SWING_DAMAGE", "SWING_MISSED", "SPELL_DAMAGE", "SPELL_MISSED" }
local function OnCombatLogEvent(_, subevent, _, sourceGUID, _, _, _, destGUID, _, _, _,
                                arg12, arg13, _, arg15, _, _, _, _, _, arg21)
    if sourceGUID ~= playerGUID then
        if destGUID == playerGUID and ((subevent == "SWING_MISSED" and arg12 == "PARRY")
            or (subevent == "SPELL_MISSED" and arg15 == "PARRY")) then
            ParryHaste(GetTime())
        end
        return
    end

    local now = GetTime()
    if subevent == "SWING_DAMAGE" or subevent == "SWING_MISSED" then
        -- SWING_DAMAGE: amount(12) ... isOffHand(21); SWING_MISSED:
        -- missType(12), isOffHand(13). (Dodges: ns.Misses, see below.)
        local isOffHand
        if subevent == "SWING_DAMAGE" then isOffHand = arg21 else isOffHand = arg13 end
        local mhSpeed, ohSpeed = UnitAttackSpeed("player")
        if isOffHand then
            S.swing.oh.start = now
            S.swing.oh.duration = ohSpeed or 0
        else
            S.swing.mh.start = now
            S.swing.mh.duration = mhSpeed or 0
        end
    else
        -- SPELL_DAMAGE / SPELL_MISSED: spellName(13)
        -- Heroic Strike / Cleave replace the main-hand swing.
        local spellName = arg13
        if spellName and (spellName == HS_NAME or spellName == CLEAVE_NAME) then
            local mhSpeed = UnitAttackSpeed("player")
            S.swing.mh.start = now
            S.swing.mh.duration = mhSpeed or 0
        end
    end
end

-- WoW Forever: no combat log, so your swings come from the game's own
-- swing event (ns.Swings, PLAYER_SWING). Each one starts that hand's
-- bar over at the game's swing time; Heroic Strike and Cleave are a
-- main-hand swing there too. A parry of yours brings the next main-hand
-- swing sooner, as the combat log's parry did.
local function OnSwing(hand, now, dur, durObj)
    if hand == "parry" then ParryHaste(now) return end
    if hand ~= "mh" and hand ~= "oh" then return end
    local t = (hand == "oh") and S.swing.oh or S.swing.mh
    t.start, t.duration = now, dur or 0
    t.durObj = durObj   -- (WoW Forever: the hidden swing time on the game's clock)
end

-- The Overpower window: the last time any target dodged one of your
-- swings or abilities (ZacUI's shared miss tracker, same rule as before:
-- SWING_MISSED / SPELL_MISSED with DODGE, any target).
local function OnMiss(kind, _, now)
    if kind == "DODGE" then S.lastDodge = now end
end

-- Core ticker (0.2s): consumes dirty flags, refreshes the snapshot and
-- repaints the display. Only runs for warriors with the HUD enabled.
-- Out of combat with no attackable target nothing is moving, so the work
-- runs about once a second; any dirty flag, a target, combat, a cooldown
-- or stance change, or the settings preview brings it straight back.
local coreTicker = nil
local plateClock = 0
local IDLE_EVERY = 1.0
local lastWork, wake = 0, true

function WH.Wake() wake = true end

-- High-frequency events (CLEU, auras, bags, target changes) are only
-- registered while the HUD actually runs; bound below the event frame.
local RegisterHotEvents, UnregisterHotEvents

local function CoreTick()
    local cfg = WH.Store()
    if not cfg or not cfg.enabled or not S.isWarrior then return end
    local now = GetTime()
    if not (wake or S.inCombat or S.targetAttackable or dirty.spells or dirty.bags
            or dirty.auras or dirty.targetAuras or (WH.Display and WH.Display.preview))
        and now - lastWork < IDLE_EVERY then
        return
    end
    wake, lastWork = false, now

    if dirty.spells then dirty.spells = false ResolveSpells() end
    if dirty.bags then dirty.bags = false ScanBags() end
    if dirty.auras then
        dirty.auras = false
        local A = ns.PlayerAuras
        ScanAuraList(A.Buffs(), S.buffs)
        ScanAuraList(A.Debuffs(), S.selfDebuffs)
    end
    UpdateTargetSnapshot()
    if dirty.targetAuras then dirty.targetAuras = false ScanTargetHamstring() end
    UpdateMisc()
    UpdateSpellSnapshot()

    -- Nameplate scan every other tick (0.4s), in combat only, and only
    -- when someone reads the count: the sapper icon (item in bags) or
    -- the Whirlwind mob count. One scan serves both.
    plateClock = plateClock + 1
    local sapper = S.items[WH.SAPPER_ID]
    local wantPlates = false
    if S.inCombat then
        if sapper and (sapper.count or 0) > 0 then wantPlates = true end
        if not wantPlates then
            local ww = S.spells.whirlwind
            local cfg = WH.Store()
            if ww and ww.known and cfg and cfg.wwCount ~= false then wantPlates = true end
        end
    end
    if wantPlates then
        if plateClock % 2 == 0 then ScanNameplates() end
    else
        S.plateCount = 0
    end

    if WH.Display and WH.Display.Refresh then
        WH.Display:Refresh()
    end
end

local function StartTicker()
    if coreTicker then return end
    coreTicker = HUD.Ticker(0.2, CoreTick, "hud.warrior")
    WH.running = true
    wake = true
    if RegisterHotEvents then RegisterHotEvents() end
    -- The world moved on while the HUD was off; rescan everything.
    dirty.auras, dirty.targetAuras, dirty.bags, dirty.spells =
        true, true, true, true
end

local function StopTicker()
    if coreTicker then coreTicker:Cancel() coreTicker = nil end
    WH.running = false
    if UnregisterHotEvents then UnregisterHotEvents() end
end

function WH:SetEnabled(on)
    local cfg = WH.Store()
    if cfg then cfg.enabled = on and true or false end
    if on and S.isWarrior then
        StartTicker()
    else
        StopTicker()
        if WH.Display and WH.Display.HideAll then WH.Display:HideAll() end
    end
end

function WH:IsActive()
    local cfg = WH.Store()
    return (cfg and cfg.enabled and S.isWarrior) and true or false
end

-- Settings UI hook: re-resolve tracked spells after custom add/remove.
function WH.MarkSpellsDirty()
    dirty.spells = true
end

-- Event wiring (flags only)
-- Points in Improved Heroic Strike (Arms): found by name, or by the
-- Heroic Strike icon it shares, on the Arms tab; 0 when not taken.
local IMP_HS_ICON = 132282
function WH.ImpHSRank()
    if not (GetNumTalents and GetTalentInfo) then return 0 end
    local want = "Improved Heroic Strike"
    for i = 1, (GetNumTalents(1) or 0) do
        local name, icon, _, _, rank = GetTalentInfo(1, i)
        if name == want or icon == IMP_HS_ICON
            or (type(icon) == "string" and icon:lower():find("ability_rogue_ambush", 1, true)) then
            return tonumber(rank) or 0
        end
    end
    return 0
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")

-- Hot events live only while the HUD runs (see StartTicker/StopTicker).
local function OnPlayerAuras() dirty.auras = true end
RegisterHotEvents = function()
    S.inCombat = InCombatLockdown() or UnitAffectingCombat("player")
    ns.CLEU.On("WarriorHUD.core", SWING_SUBS, OnCombatLogEvent)
    ns.Swings.On("WarriorHUD.core", OnSwing)
    ns.Misses.On("WarriorHUD.dodge", OnMiss)
    -- the player's auras: ZacUI's shared read tells us when they moved
    ns.PlayerAuras.On("WarriorHUD.auras", OnPlayerAuras)
    ev:RegisterUnitEvent("UNIT_AURA", "target")
    ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    ev:RegisterEvent("BAG_UPDATE_DELAYED")
    -- wake the idle ticker: a cooldown or the stance moved
    ev:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    ev:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    pcall(ev.RegisterUnitEvent, ev, "UNIT_ATTACK_SPEED", "player")
end
UnregisterHotEvents = function()
    ns.CLEU.Off("WarriorHUD.core")
    ns.Swings.On("WarriorHUD.core", nil)
    ns.Misses.On("WarriorHUD.dodge", nil)
    ns.PlayerAuras.On("WarriorHUD.auras", nil)
    ev:UnregisterEvent("UNIT_AURA")
    ev:UnregisterEvent("PLAYER_TARGET_CHANGED")
    ev:UnregisterEvent("BAG_UPDATE_DELAYED")
    ev:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
    ev:UnregisterEvent("UPDATE_SHAPESHIFT_FORM")
    ev:UnregisterEvent("UNIT_ATTACK_SPEED")
end

ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        local _, class = UnitClass("player")
        S.isWarrior = class == "WARRIOR"
        if not S.isWarrior then
            ev:UnregisterAllEvents()
            return
        end
        playerGUID = UnitGUID("player")
        HS_NAME = GetSpellInfo and GetSpellInfo(78) or "Heroic Strike"
        CLEAVE_NAME = GetSpellInfo and GetSpellInfo(845) or "Cleave"
        S.inCombat = InCombatLockdown() or UnitAffectingCombat("player")

        ev:RegisterEvent("PLAYER_ENTERING_WORLD")
        -- SPELLS_CHANGED covers learning/rank changes on all clients
        -- (LEARNED_SPELL_IN_TAB no longer exists on 1.15.x).
        ev:RegisterEvent("SPELLS_CHANGED")
        -- a talent point spent or reset changes Heroic Strike's cost
        ev:RegisterEvent("CHARACTER_POINTS_CHANGED")
        pcall(ev.RegisterEvent, ev, "PLAYER_TALENT_UPDATE")
        ev:RegisterEvent("PLAYER_REGEN_DISABLED")
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
        -- the combat log, auras, target and bag events register in
        -- StartTicker, only while the HUD is enabled.

        local cfg = WH.Store()
        if cfg and cfg.enabled then StartTicker() end
        HUD.Debug("WarriorHUD core initialized")
    elseif event == "UNIT_AURA" then
        dirty.targetAuras = true           -- target only; the player's come via ns.PlayerAuras
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "UPDATE_SHAPESHIFT_FORM" then
        wake = true
    elseif event == "PLAYER_TARGET_CHANGED" then
        dirty.targetAuras = true
    elseif event == "BAG_UPDATE_DELAYED" then
        dirty.bags = true
    elseif event == "UNIT_ATTACK_SPEED" then
        RescaleSwing()
    elseif event == "SPELLS_CHANGED" or event == "CHARACTER_POINTS_CHANGED"
        or event == "PLAYER_TALENT_UPDATE" then
        dirty.spells = true
    elseif event == "PLAYER_REGEN_DISABLED" then
        S.inCombat = true
        wake = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        S.inCombat = false
        wake = true
    elseif event == "PLAYER_ENTERING_WORLD" then
        dirty.auras, dirty.targetAuras, dirty.bags, dirty.spells = true, true, true, true
    end
end)

-- Sapper TTS ("Sapper Now"), throttled like the WA (3s)
local ttsThrottle = 0
function WH.SapperTTS()
    local cfg = WH.Store()
    if not (cfg and cfg.sapperTTS) then return end
    if GetTime() - ttsThrottle < 3 then return end
    ttsThrottle = GetTime()
    -- (was SpeakText(1, text, LocalPlayback, 1.2, 75): on this client arg 4
    -- is the VOLUME and arg 5 the rate, and LocalPlayback is the quiet
    -- route - so it said "Sapper Now" at 1% volume, 75x speed. Now the
    -- shape proven everywhere else: destination 0, volume 100, rate 1, in
    -- the voice Readycheck and the raid packs use.)
    if C_VoiceChat and C_VoiceChat.SpeakText then
        local Z = _G.ZacUI
        local RMv = Z and Z.RaidMods and Z.RaidMods.VoiceId
        local voice = (Z and Z.VoiceId and Z.VoiceId()) or (RMv and RMv()) or 0
        pcall(C_VoiceChat.SpeakText, voice, "Sapper Now", 0, 100, 1)
    end
end
