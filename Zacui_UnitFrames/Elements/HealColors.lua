-- ============================================================================
-- ZacUF - HealColors.lua
-- Maps a healer's casterGUID to a stable, identifying color for the incoming-
-- heal segments and the healer legend dot.
--
-- Two modes (ns.db.heal.colorMode, default "class"):
--
-- CLASS mode - every healer draws in their class color (Priest white, Paladin
-- pink, Druid orange, Shaman blue), read from the client's RAID_CLASS_COLORS so
-- class-color addons are respected, with per-class user overrides on top.
-- Deterministic: the same healer is the same color on everyone's screen.
-- Same-class healers are told apart by the segment marker, not by color.
--
-- SLOT mode - the per-healer model, for telling same-class healers apart by
-- color alone. Every healer belongs to one of three ROLES derived from class +
-- faction:
--   Raid Healer    = Alliance Priest  / Horde Shaman   (the most numerous)
--   Tank Healer    = Alliance Paladin / Horde Priest
--   Support Healer = Druid (either faction)
-- Within a role each player gets a stable SLOT (0..7, in order of first
-- appearance, persisted per name; a rare 9th+ healer recycles via slot % ROWS).
-- Colors are slot-based, NOT person-based: "Raid Healer 3" is whoever currently
-- holds raid-slot 3.
--
-- On Era the role model is faction-asymmetric (Horde has no Paladins, so
-- Priests take the tank-healer niche). On TBC-era clients Blood Elf Paladins and
-- Draenei Shamans exist, so the mapping collapses to class-only. The saved slot
-- keys ("raid"/"tank"/"support") are identical either way, so no migration.
--
-- Ported from the HealVision addon, which ZacUF now supersedes.
-- ============================================================================
local ADDON, ns = ...

local HealColors = {}
ns.HealColors = HealColors

HealColors.ROLES = { "tank", "raid", "support" }   -- config display order
HealColors.ROWS  = 8                               -- color slots shown per role
HealColors.CLASSES = { "PRIEST", "PALADIN", "DRUID", "SHAMAN" }

local ROLE_OF
if WOW_PROJECT_ID == (WOW_PROJECT_CLASSIC or 2) then
    ROLE_OF = {
        Alliance = { PRIEST = "raid", PALADIN = "tank", DRUID = "support" },
        Horde    = { SHAMAN = "raid", PRIEST  = "tank", DRUID = "support" },
    }
else
    local ANY = { PRIEST = "raid", SHAMAN = "raid", PALADIN = "tank", DRUID = "support" }
    ROLE_OF = { Alliance = ANY, Horde = ANY }
end

local RACE_FACTION = {   -- playable races -> faction (Era + TBC)
    Human = "Alliance", Dwarf = "Alliance", NightElf = "Alliance", Gnome = "Alliance",
    Draenei = "Alliance",
    Orc = "Horde", Scourge = "Horde", Tauren = "Horde", Troll = "Horde",
    BloodElf = "Horde",
}

-- ----------------------------------------------------------------------------
-- Default colors
-- ----------------------------------------------------------------------------
-- Raid role: a distinct palette - each healer a clearly different color. Six to
-- eight shades of one hue are not tellable apart at raid-frame size.
local RAID_PALETTE = {
    { 0.25, 0.80, 0.35 },  -- 1 green
    { 0.10, 0.45, 0.18 },  -- 2 dark green
    { 0.55, 0.80, 0.95 },  -- 3 light blue
    { 0.12, 0.25, 0.75 },  -- 4 dark blue
    { 0.90, 0.18, 0.18 },  -- 5 red
    { 0.50, 0.08, 0.08 },  -- 6 dark red
    { 0.62, 0.62, 0.62 },  -- 7 grey
    { 0.32, 0.32, 0.32 },  -- 8 dark grey
}
-- Tank and support roles get one flat color each: there are only a few of them
-- and subtle shade differences proved hard to read in raid. Users can recolor
-- individual slots if they want the distinction back.
local TANK_COLOR    = { 0.96, 0.55, 0.73 }  -- pink   (Paladins / Horde Priests)
local SUPPORT_COLOR = { 1.00, 0.49, 0.04 }  -- orange (Druids)

local NEUTRAL = { 0.85, 0.85, 0.85 }        -- unresolved GUID / non-healing class

local CLASS_FALLBACK = {
    PRIEST  = { 1.00, 1.00, 1.00 },  -- white
    PALADIN = { 0.96, 0.55, 0.73 },  -- pink
    DRUID   = { 1.00, 0.49, 0.04 },  -- orange
    SHAMAN  = { 0.00, 0.44, 0.87 },  -- blue
}

HealColors.DEFAULT_OWN = { 0.95, 0.95, 0.95 }   -- white  (own heals)
HealColors.DEFAULT_HOT = { 0.30, 0.55, 0.95 }   -- blue   (uniform HoT)

local function defaultClassColor(class)
    local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)
    c = c and c[class]
    if c and c.r then return c.r, c.g, c.b end
    local f = CLASS_FALLBACK[class]
    if f then return f[1], f[2], f[3] end
    return NEUTRAL[1], NEUTRAL[2], NEUTRAL[3]
end

local function defaultRoleColor(role, slot)
    if role == "raid" then
        local c = RAID_PALETTE[(slot % #RAID_PALETTE) + 1]
        return c[1], c[2], c[3]
    elseif role == "support" then
        return SUPPORT_COLOR[1], SUPPORT_COLOR[2], SUPPORT_COLOR[3]
    end
    return TANK_COLOR[1], TANK_COLOR[2], TANK_COLOR[3]   -- tank
end

-- ----------------------------------------------------------------------------
-- State (session caches; cleared whenever a color setting changes)
-- ----------------------------------------------------------------------------
local cache = {}          -- casterGUID -> { r, g, b }
local initialsCache = {}  -- casterGUID -> 3-letter abbreviation
local playerGUID

local function cfg() return ns.db and ns.db.heal end

local function playerFaction()
    return (UnitFactionGroup("player")) or "Alliance"
end

local function roleOf(class, faction)
    local m = ROLE_OF[faction or playerFaction()]
    return m and m[class]
end

-- Color for (role, slot): the user's override for that row, else the default.
-- Recycles past ROWS so a 9th healer reuses row 1 rather than going colorless.
local function colorForSlot(role, slot)
    local db = cfg()
    local row = slot % HealColors.ROWS                 -- 0-based, recycled
    local roleOv = db and db.roleColors and db.roleColors[role]
    local ov = roleOv and roleOv[row + 1]              -- stored 1-indexed
    if ov then return ov[1], ov[2], ov[3] end
    return defaultRoleColor(role, row)
end

-- Stable slot for a (role, name), assigned in order of first appearance and
-- persisted, so "Raid Healer 3" keeps their color across sessions.
local function slotFor(role, name)
    local db = cfg()
    if not db then return 0 end
    db.slots = db.slots or {}
    local s = db.slots[role]
    if not s then s = {}; db.slots[role] = s end
    local slot = s[name]
    if slot == nil then
        local used = 0
        for _ in pairs(s) do used = used + 1 end
        slot = used
        s[name] = slot
    end
    return slot
end

-- ----------------------------------------------------------------------------
-- Public API
-- ----------------------------------------------------------------------------
function HealColors:Init()
    local db = cfg()
    if db then
        db.colorMode  = db.colorMode or "class"
        db.classColors = db.classColors or {}
        db.roleColors  = db.roleColors  or {}
        db.slots       = db.slots       or {}
    end
    playerGUID = UnitGUID("player")
    wipe(cache); wipe(initialsCache)
end

-- The healer's own identifying color. Returns r, g, b (alpha is applied by the
-- renderer, which dims HoTs itself).
function HealColors:GetColor(casterGUID)
    if not casterGUID then return NEUTRAL[1], NEUTRAL[2], NEUTRAL[3] end
    -- Init can run before UnitGUID("player") resolves; retry lazily so the
    -- player never falls through to the slot engine (and never claims a slot).
    if not playerGUID then playerGUID = UnitGUID("player") end
    local db = cfg()

    -- The player (if a healing class) uses the own-heal color everywhere - chips
    -- and dot - and never occupies a role slot. Checked before the cache, and
    -- deliberately not cached, so a live color change shows up immediately.
    if casterGUID == playerGUID and db and db.ownHeal and db.ownHeal.enabled then
        local _, class = GetPlayerInfoByGUID(casterGUID)
        if class and roleOf(class) then
            local c = db.ownHeal.color
            return c[1], c[2], c[3]
        end
    end

    local hit = cache[casterGUID]
    if hit then return hit[1], hit[2], hit[3] end

    local _, class, _, race, _, name = GetPlayerInfoByGUID(casterGUID)
    if not class or not name then
        -- Unit info not cached yet; stay neutral and do not persist a slot.
        return NEUTRAL[1], NEUTRAL[2], NEUTRAL[3]
    end

    local r, g, b
    if db and db.colorMode == "slot" then
        local role = roleOf(class, RACE_FACTION[race] or playerFaction())
        if not role then return NEUTRAL[1], NEUTRAL[2], NEUTRAL[3] end
        r, g, b = colorForSlot(role, slotFor(role, name))
    else
        if not CLASS_FALLBACK[class] then return NEUTRAL[1], NEUTRAL[2], NEUTRAL[3] end
        r, g, b = self:ClassColor(class)
    end
    cache[casterGUID] = { r, g, b }
    return r, g, b
end

-- First 3 letters of a healer's name for the "initials" segment marker.
-- Returns "" while the unit's info is still uncached.
function HealColors:GetInitials(casterGUID)
    if not casterGUID then return "" end
    local hit = initialsCache[casterGUID]
    if hit ~= nil then return hit end
    local _, _, _, _, _, name = GetPlayerInfoByGUID(casterGUID)
    if not name then return "" end
    local ab = name:sub(1, 3)
    initialsCache[casterGUID] = ab
    return ab
end

-- True only when the GUID resolves to a healing class. Gates the legend dot so
-- non-healing classes (and not-yet-cached units) never get a stray dot just
-- because the heal provider attributed something to them.
function HealColors:IsHealer(guid)
    if not guid then return false end
    local _, class = GetPlayerInfoByGUID(guid)
    return class ~= nil and roleOf(class) ~= nil
end

function HealColors:GetMode()
    local db = cfg()
    return (db and db.colorMode) or "class"
end

function HealColors:SetMode(mode)
    local db = cfg()
    if not db then return end
    db.colorMode = (mode == "slot") and "slot" or "class"
    wipe(cache)
end

-- Class-mode color for a healing class: the user's override or the default.
function HealColors:ClassColor(class)
    local db = cfg()
    local ov = db and db.classColors and db.classColors[class]
    if ov then return ov[1], ov[2], ov[3] end
    return defaultClassColor(class)
end

function HealColors:SetClassColor(class, r, g, b)
    local db = cfg()
    if not db then return end
    db.classColors = db.classColors or {}
    db.classColors[class] = { r, g, b }
    wipe(cache)
end

-- Slot-mode color for a (role, slot). Used by the config pickers and previews.
function HealColors:RoleColor(role, slot)
    return colorForSlot(role, slot or 0)
end

function HealColors:SetRoleColor(role, slot, r, g, b)
    local db = cfg()
    if not db then return end
    db.roleColors = db.roleColors or {}
    db.roleColors[role] = db.roleColors[role] or {}
    db.roleColors[role][(slot % HealColors.ROWS) + 1] = { r, g, b }
    wipe(cache)
end

-- The colour a healer of `class` holding `slot` gets right now, without a
-- GUID - for the settings preview's made-up healers. Follows the colour
-- mode, the class / slot overrides and the own-heal rule (`own`) exactly
-- like GetColor does for a real one.
function HealColors:PreviewColor(class, slot, own)
    local db = cfg()
    if own and db and db.ownHeal and db.ownHeal.enabled and roleOf(class) then
        local c = db.ownHeal.color
        return c[1], c[2], c[3]
    end
    if db and db.colorMode == "slot" then
        local role = roleOf(class)
        if not role then return NEUTRAL[1], NEUTRAL[2], NEUTRAL[3] end
        return colorForSlot(role, slot or 0)
    end
    if not CLASS_FALLBACK[class] then return NEUTRAL[1], NEUTRAL[2], NEUTRAL[3] end
    return self:ClassColor(class)
end

-- The english class filling a role for the player's faction (for config labels).
function HealColors:RoleClass(role)
    local m = ROLE_OF[playerFaction()]
    if m then
        for class, r in pairs(m) do
            if r == role then return class end
        end
    end
end

function HealColors:ResetClassColors()
    local db = cfg()
    if db then wipe(db.classColors) end
    wipe(cache)
end

function HealColors:ResetRoleColors()
    local db = cfg()
    if db then wipe(db.roleColors) end
    wipe(cache)
end

-- Forget who held which slot (start slot assignment fresh).
function HealColors:ResetAssignments()
    local db = cfg()
    if db then wipe(db.slots) end
    wipe(cache)
end

-- Reset every color choice: class overrides, role slots, own-heal and HoT.
-- The two color tables are refilled IN PLACE, never reassigned: the options page
-- captures them by reference when it builds its swatches, so replacing the table
-- would leave those swatches reading and writing a detached copy.
local function refill(t, src)
    if type(t) ~= "table" then return end
    t[1], t[2], t[3] = src[1], src[2], src[3]
end

function HealColors:ResetAll()
    local db = cfg()
    self:ResetClassColors()
    self:ResetRoleColors()
    if db then
        refill(db.ownHeal and db.ownHeal.color, HealColors.DEFAULT_OWN)
        refill(db.hot and db.hot.color, HealColors.DEFAULT_HOT)
        refill(db.segment and db.segment.uniformColor, { 0.50, 0.50, 0.50 })
    end
    wipe(cache); wipe(initialsCache)
end

-- Forget computed colors so they re-derive (after any color/mode change).
function HealColors:Flush()
    wipe(cache); wipe(initialsCache)
end
