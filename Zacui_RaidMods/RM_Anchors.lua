-- RM_Anchors - where the Raid Mods widgets go: the engine's anchors (the
-- movable spots the packs' timers, icons, texts and lists grow from),
-- the packs' own layout groups, and the widgets that ride on a raid
-- frame or a nameplate.
-- Part of ZacUI; load order is set by the TOC.
--
-- ANCHORS. Seventeen frames on screen that every raid group hangs on
-- (the layout the raid packs used); here each is a
-- small frame with a ZacUI mover (Movers page / Edit Mode), defaulting
-- to where Zac's own anchors were.
--
-- GROUPS. A pack's dynamic group becomes a container that arranges the
-- widgets of its member units the way the group did: grow direction,
-- spacing, sort by time left, a limit. A static group is just a point
-- its children offset from. A group with no anchor of its own gets a
-- mover too, when it draws anything.
--
-- PERF. Layout runs once per changed container, coalesced to the next
-- frame; nothing is laid out per event.

local ns = _G.ZacUI
if not ns then return end
local RM = ns.RaidMods
if not RM then return end

local L = {}
RM.Layout = L

local Print = RM.Print

-- ============================================================
-- THE ANCHORS
-- ============================================================
-- point = the anchor's own point; relPoint = the UIParent point it is
-- measured from; x, y = the offset. w, h = the size of what hangs there
-- (for the mover's handle).
local ANCHORS = {
    { key = "BossTimers",           label = "Raid mods: boss timers",        point = "BOTTOM", relPoint = "CENTER", x = 384, y = 74,  w = 220, h = 20 },
    { key = "BossTimersEmphasize",  label = "Raid mods: emphasized timers",  point = "TOP",    relPoint = "BOTTOM", x = 384, y = 62,  w = 220, h = 21 },
    { key = "BerserkTimers",        label = "Raid mods: berserk timer",      point = "TOP",    relPoint = "TOP",    x = 0,   y = -18, w = 200, h = 18 },
    { key = "BossSpecials",         label = "Raid mods: boss specials",      point = "BOTTOM", relPoint = "CENTER", x = 384, y = 224, w = 220, h = 30 },
    { key = "SpecialWarnings",      label = "Raid mods: special warnings",   point = "TOP",    relPoint = "CENTER", x = 0,   y = 168, w = 300, h = 20 },
    { key = "SpecialAlerts",        label = "Raid mods: special alerts",     point = "TOP",    relPoint = "CENTER", x = 0,   y = 116, w = 180, h = 26 },
    { key = "TextVertical",         label = "Raid mods: text alerts",        point = "TOP",    relPoint = "CENTER", x = 0,   y = 218, w = 300, h = 20 },
    { key = "TextHorizontal",       label = "Raid mods: target texts",       point = "CENTER", relPoint = "CENTER", x = 0,   y = 232, w = 300, h = 20 },
    { key = "Icons",                label = "Raid mods: icons",              point = "RIGHT",  relPoint = "CENTER", x = -134, y = -75, w = 53, h = 53 },
    { key = "LargeIcons",           label = "Raid mods: large icons",        point = "RIGHT",  relPoint = "CENTER", x = -134, y = 15,  w = 60, h = 60 },
    { key = "TankIcons",            label = "Raid mods: tank icons",         point = "RIGHT",  relPoint = "CENTER", x = -306, y = -80, w = 60, h = 60 },
    { key = "CoTankIcons",          label = "Raid mods: co-tank icons",      point = "TOP",    relPoint = "CENTER", x = -404, y = -50, w = 60, h = 60 },
    { key = "Lists",                label = "Raid mods: lists",              point = "TOP",    relPoint = "CENTER", x = -442.4, y = -11.9, w = 140, h = 20 },
    { key = "ProgressCenter",       label = "Raid mods: progress bars",      point = "TOP",    relPoint = "CENTER", x = 0,   y = 300, w = 220, h = 26 },
    { key = "ProgressTop",          label = "Raid mods: top progress bars",  point = "TOP",    relPoint = "TOP",    x = 0,   y = -60, w = 260, h = 26 },
    { key = "Reminders",            label = "Raid mods: reminders",          point = "TOP",    relPoint = "CENTER", x = 0,   y = 60,  w = 42,  h = 42 },
    { key = "Circles",              label = "Raid mods: circles",            point = "CENTER", relPoint = "CENTER", x = 0,   y = -10, w = 110, h = 110 },
}
L.anchorFrames = {}

-- a point's position on UIParent, from its bottom-left
local function PointPos(point)
    local W, H = UIParent:GetWidth() or 1920, UIParent:GetHeight() or 1080
    local x, y = W / 2, H / 2
    if point:find("LEFT") then x = 0 elseif point:find("RIGHT") then x = W end
    if point:find("TOP") then y = H elseif point:find("BOTTOM") then y = 0 end
    return x, y
end
-- "my POINT sits at UIParent's RELPOINT + (x, y)" as "my POINT at
-- UIParent's POINT + (x', y')", which is the shape the movers keep
local function SamePointOffset(point, relPoint, x, y)
    if point == relPoint then return x, y end
    local ax, ay = PointPos(relPoint)
    local sx, sy = PointPos(point)
    return x + (ax - sx), y + (ay - sy)
end

local function MoverKey(key) return "raidmods_" .. key end

local function PlaceDefault(f, point, relPoint, x, y, moverKey)
    local pos = ZacUIDB and ZacUIDB.movers and ZacUIDB.movers[moverKey]
    f:ClearAllPoints()
    if pos then
        f:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)
    else
        f:SetPoint(point, UIParent, relPoint, x, y)
    end
end

for _, a in ipairs(ANCHORS) do
    local f = CreateFrame("Frame", "ZacUIRaidMods_" .. a.key, UIParent)
    f:SetSize(a.w, a.h)
    f.anchorDef = a
    PlaceDefault(f, a.point, a.relPoint, a.x, a.y, MoverKey(a.key))
    L.anchorFrames[a.key] = f
    if ns.RegisterMover then
        local dx, dy = SamePointOffset(a.point, a.relPoint, a.x, a.y)
        -- reset: back where the packs had it
        ns.RegisterMover(MoverKey(a.key), a.label, function() return f end, a.point, dx, dy, nil,
            { reset = function() PlaceDefault(f, a.point, a.relPoint, a.x, a.y, MoverKey(a.key)) end })
    end
end

-- ============================================================
-- UNIT FRAMES AND NAMEPLATES
-- ============================================================
function L.UnitFrame(unit)
    if not unit then return nil end
    local get = _G.ZacUF_GetUnitFrame
    if get then
        local ok, f = pcall(get, unit)
        if ok and f then return f end
    end
    return nil
end
function L.NamePlate(unit)
    if not unit then return nil end
    local NP = ns.Nameplates
    if NP and NP.activePlates and NP.activePlates[unit] then return NP.activePlates[unit] end
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local p = C_NamePlate.GetNamePlateForUnit(unit)
        if p then return p.UnitFrame or p end
    end
    return nil
end

-- ============================================================
-- CONTAINERS
-- ============================================================
local containers = {}      -- key -> container frame (group key, or group key .. "|" .. unit)
local dirty = {}
local flushQueued = false

local function GroupDef(key) return key and RM.groups[key] end

local function ResolveAnchorTo(name)
    if not name then return nil end
    if RM.groups[name] then return L.Container(name) end
    local inst = RM.loaded[name]
    if inst and inst.widgets then
        local w = inst.widgets[""]
        if not w then for _, x in pairs(inst.widgets) do w = x break end end
        if w then return w end
        return nil
    end
    local f = _G[name]
    if type(f) == "table" and f.GetObjectType then return f end
    return nil
end

-- ZacUI's plate strip: every pack widget that rides a nameplate (Disarm,
-- Enrage, Captain Whirlwind, the Razuvious Taunt...) lands in one row at
-- one spot on ZacUI's plate, set on Nameplates > Debuffs, instead of
-- each pack's own offsets - so it sits with the plate's debuff groups
-- and clear of the BT/WW row. A synthetic dynamic group, one container
-- per plate.
local PLATE_STRIP = "ZUI:PlateStrip"
if RM.groups and not RM.groups[PLATE_STRIP] then
    RM.groups[PLATE_STRIP] = { key = PLATE_STRIP, name = "ZacUI plate strip", kind = "dynamicgroup",
        grow = "RIGHT", align = "CENTER", space = 2, sort = "none", zuiPlate = true,
        anchorFrameType = "NAMEPLATE", selfPoint = "LEFT", anchorPoint = "CENTER" }
end
local function PlateStripSpot()
    local NPD = ns.Nameplates and ns.Nameplates.Debuffs
    local c = NPD and NPD.PackStrip and NPD.PackStrip()
    if not c then return nil end
    -- hanging from the bar's bottom-right corner the strip grows left,
    -- so its first icon sits on the corner whatever else arrives
    local grp = RM.groups[PLATE_STRIP]
    if grp then grp.grow = (c.at == "bottomright") and "LEFT" or "RIGHT" end
    return c
end
-- how far below the health bar the first free line starts (past a cast
-- bar or the threat strip), from the nameplate module
local function PlateDrop(f)
    local NP = ns.Nameplates
    return (NP and NP.CastDrop and NP.CastDrop(f)) or 0
end
local HookUnderBar            -- defined under PositionContainer; run on first use

local function PositionContainer(c)
    local grp = c.grp
    c:ClearAllPoints()
    local target
    if c.unit and grp.zuiPlate then
        local f = L.NamePlate(c.unit)
        local spot = PlateStripSpot()
        if not (f and f.health and spot) then c:Hide() return end
        c:SetParent(f)
        f._zuiPackStrip = c          -- the nameplate module reads its reach
        local sc = tonumber(spot.scale) or 1
        if sc <= 0 then sc = 1 end
        if c._zuiScale ~= sc then c._zuiScale = sc c:SetScale(sc) end
        -- offsets are in the plate's units; the container is scaled, so
        -- they are divided back out
        local x, y = (tonumber(spot.x) or 0) / sc, (tonumber(spot.y) or 0) / sc
        if spot.at == "after" then
            -- straight after the debuff row under the bar (it moves with
            -- the row's end); no row yet: from the bar's bottom-left
            HookUnderBar()
            if f.dbUnderEnd then
                c:SetPoint("TOPLEFT", f.dbUnderEnd, "TOPLEFT", x, y)
            else
                c:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT", x, y - (2 + PlateDrop(f)) / sc)
            end
        elseif spot.at == "bottomright" then
            HookUnderBar()
            -- the right corner is the threat strip's side: under all of it
            local NPm = ns.Nameplates
            local full = (NPm and NPm.UnderDrop and NPm.UnderDrop(f)) or 0
            c:SetPoint("TOPRIGHT", f.health, "BOTTOMRIGHT", x, y - (3 + full) / sc)
        else
            c:SetPoint("LEFT", f.health, "CENTER", x, y)
        end
        c:Show()
        return
    end
    if c.unit then
        target = L.UnitFrame(c.unit)
        if not target then c:Hide() return end
        c:SetParent(target)
        c:SetPoint(grp.selfPoint or "CENTER", target, grp.anchorPoint or "CENTER", tonumber(grp.xOffset) or 0, tonumber(grp.yOffset) or 0)
        c:Show()
        return
    end
    if grp.anchor and L.anchorFrames[grp.anchor] then
        target = L.anchorFrames[grp.anchor]
        c:SetParent(UIParent)
        c:SetPoint(grp.selfPoint or "CENTER", target, grp.anchorPoint or "CENTER", tonumber(grp.xOffset) or 0, tonumber(grp.yOffset) or 0)
    elseif grp.anchorTo then
        target = ResolveAnchorTo(grp.anchorTo)
        if not target then c:Hide() return end
        c:SetParent(UIParent)
        c:SetPoint(grp.selfPoint or "CENTER", target, grp.anchorPoint or "CENTER", tonumber(grp.xOffset) or 0, tonumber(grp.yOffset) or 0)
    elseif grp.parent and RM.groups[grp.parent] then
        target = L.Container(grp.parent)
        c:SetParent(UIParent)
        c:SetPoint(grp.selfPoint or "CENTER", target, grp.anchorPoint or "CENTER", tonumber(grp.xOffset) or 0, tonumber(grp.yOffset) or 0)
    else
        c:SetParent(UIParent)
        PlaceDefault(c, grp.selfPoint or "CENTER", grp.anchorPoint or "CENTER", tonumber(grp.xOffset) or 0, tonumber(grp.yOffset) or 0, MoverKey("g_" .. grp.key))
    end
    c:Show()
end

-- a cast starting or ending on a plate: that plate's strip re-anchors
-- to the new lowest bar (hooked once, the first time a strip hangs there)
local underBarHooked = false
HookUnderBar = function()
    if underBarHooked then return end
    local NP = ns.Nameplates
    if not (NP and NP.OnUnderBarChange) then return end
    underBarHooked = true
    NP.OnUnderBarChange(function(f)
        local unit = f.unit
        if not unit then return end
        local c = containers[PLATE_STRIP .. "|" .. unit]
        if c and c:IsShown() then c:ClearAllPoints() PositionContainer(c) end
    end)
end

local function IsDynamic(grp) return grp and grp.kind == "dynamicgroup" end

function L.Container(key, unit)
    local ck = unit and (key .. "|" .. unit) or key
    local c = containers[ck]
    if c then return c end
    local grp = GroupDef(key)
    if not grp then return nil end
    c = CreateFrame("Frame", nil, UIParent)
    c.key, c.grp, c.unit, c.gkey = ck, grp, unit, key
    c.members = {}
    c:SetSize(1, 1)
    -- a group standing on its own needs a handle you can grab even when empty
    c.minW, c.minH = 1, 1
    if not grp.anchor and not grp.anchorTo and not grp.parent and not unit then c.minW, c.minH = 120, 20 end
    c:SetSize(c.minW, c.minH)
    c:SetFrameStrata("MEDIUM")
    if grp.scale and tonumber(grp.scale) and tonumber(grp.scale) ~= 1 then c:SetScale(tonumber(grp.scale)) end
    containers[ck] = c
    PositionContainer(c)
    return c
end

-- the per-unit groups: one container per (group, unit) on that unit's frame
local function PerUnit(grp) return grp and grp.useAnchorPerUnit and grp.anchorPerUnit == "UNITFRAME" end

-- ============================================================
-- ARRANGING A DYNAMIC CONTAINER
-- ============================================================
local function Visible(w)
    return w:IsShown() and w.state ~= nil or w.finishing
end
local function Expiry(w)
    local st = w.state
    if st and st.expirationTime and st.expirationTime < math.huge then return st.expirationTime end
    return math.huge
end

local function AlignPoint(base, align)
    if base == "TOP" or base == "BOTTOM" then
        if align == "LEFT" then return base .. "LEFT" elseif align == "RIGHT" then return base .. "RIGHT" end
        return base
    end
    if align == "LEFT" or align == "TOP" then return "TOP" .. base elseif align == "RIGHT" or align == "BOTTOM" then return "BOTTOM" .. base end
    return base
end

local function SetPlace(w, point, rel, relPoint, x, y)
    w.place = w.place or {}
    local p = w.place
    p[1], p[2], p[3], p[4], p[5] = point, rel, relPoint, x, y
    w:ClearAllPoints()
    w:SetPoint(point, rel, relPoint, x + (w.animX or 0), y + (w.animY or 0))
end
function L.Nudge(w)
    local p = w.place
    if not p then return end
    w:ClearAllPoints()
    w:SetPoint(p[1], p[2], p[3], p[4] + (w.animX or 0), p[5] + (w.animY or 0))
end

-- A LIST'S LAYOUT (db.layouts.<group key>, ZacUI's layout shape): which
-- way the list grows (down / up / left / right), the gap between entries
-- (spacingY for a list going down or up, spacingX across), how many at
-- most, reversed. The pack's own grow / space / limit are the defaults;
-- nothing saved = the pack's list exactly.
local LIST_GROWS = { DOWN = true, UP = true, LEFT = true, RIGHT = true }
L.LIST_GROWS = { "DOWN", "UP", "LEFT", "RIGHT" }
local function ListSpec(c)
    local db = RM.DB and RM.DB()
    local all = db and type(db.layouts) == "table" and db.layouts or nil
    local s = all and c.gkey and all[c.gkey] or nil
    if type(s) ~= "table" or next(s) == nil then return nil end
    return s
end
function L.ListDefaults(grp)
    grp = grp or {}
    local space = tonumber(grp.space) or 0
    local d = { grow = LIST_GROWS[grp.grow or "DOWN"] and (grp.grow or "DOWN") or nil, spacingX = space, spacingY = space }
    if grp.useLimit and tonumber(grp.limit) then d.max = tonumber(grp.limit) end
    return d
end

local function Arrange(c)
    local grp = c.grp
    local lay = ListSpec(c)
    local list = {}
    for i = #c.members, 1, -1 do
        local w = c.members[i]
        if w.container ~= c then table.remove(c.members, i)
        elseif Visible(w) then list[#list + 1] = w end
    end
    local sort = grp.sort
    if sort == "ascending" then
        table.sort(list, function(a, b)
            local ea, eb = Expiry(a), Expiry(b)
            if ea ~= eb then return ea < eb end
            return a.seq < b.seq
        end)
    elseif sort == "descending" then
        table.sort(list, function(a, b)
            local ea, eb = Expiry(a), Expiry(b)
            if ea ~= eb then return ea > eb end
            return a.seq < b.seq
        end)
    elseif sort == "custom" and type(grp.customSort) == "function" then
        -- the pack's own order (WeakAuras' customSort: a.region.state,
        -- a.dataIndex), made total so table.sort can never be handed an
        -- inconsistent order: where the pack has no opinion (it returns
        -- nil both ways), first come first served
        local cs = grp.customSort
        local function P(w)
            local p = w._sortProxy
            if not p then p = {} w._sortProxy = p end
            p.region, p.dataIndex = w, w.seq
            return p
        end
        local function Before(a, b)
            local ok, r = pcall(cs, P(a), P(b))
            return ok and r and true or false
        end
        local okSort = pcall(table.sort, list, function(a, b)
            if Before(a, b) then return true end
            if Before(b, a) then return false end
            return a.seq < b.seq
        end)
        if not okSort then table.sort(list, function(a, b) return a.seq < b.seq end) end
    else
        table.sort(list, function(a, b)
            local oa, ob = a.inst and a.inst.def.order or 0, b.inst and b.inst.def.order or 0
            if oa ~= ob then return oa < ob end
            return a.seq < b.seq
        end)
    end
    if lay and lay.reverse then
        local n0 = #list
        for i = 1, math.floor(n0 / 2) do list[i], list[n0 + 1 - i] = list[n0 + 1 - i], list[i] end
    end
    local limit = grp.useLimit and tonumber(grp.limit) or nil
    if lay and tonumber(lay.max) and tonumber(lay.max) >= 1 then limit = math.floor(tonumber(lay.max)) end
    for i, w in ipairs(list) do
        if limit and i > limit then w:SetAlpha(0) w.overLimit = true
        elseif w.overLimit then w.overLimit = nil w:SetAlpha(tonumber(w.props and w.props.alpha) or tonumber(w.D and w.D.alpha) or 1) end
    end
    if limit then
        local cut = {}
        for i = 1, math.min(limit, #list) do cut[i] = list[i] end
        list = cut
    end
    local grow = grp.grow or "DOWN"
    if lay and LIST_GROWS[lay.grow] then grow = lay.grow end
    local space = tonumber(grp.space) or 0
    if lay then
        local across = (grow == "LEFT" or grow == "RIGHT" or grow == "HORIZONTAL")
        local v = tonumber(across and lay.spacingX or lay.spacingY)
        if v then space = v end
    end
    local align = grp.align or "CENTER"
    local maxW, maxH, x, y = 0, 0, 0, 0
    local n = #list
    if grow == "DOWN" or grow == "UP" then
        local base = grow == "DOWN" and "TOP" or "BOTTOM"
        local pt = AlignPoint(base, align)
        for _, w in ipairs(list) do
            local h = w:GetHeight() or 0
            SetPlace(w, pt, c, pt, 0, grow == "DOWN" and -y or y)
            y = y + h + space
            maxW = math.max(maxW, w:GetWidth() or 0)
        end
        c:SetSize(math.max(maxW, c.minW or 1), math.max(y - space, c.minH or 1))
    elseif grow == "LEFT" or grow == "RIGHT" then
        local base = grow == "LEFT" and "RIGHT" or "LEFT"
        local pt = AlignPoint(base, align)
        for _, w in ipairs(list) do
            local wd = w:GetWidth() or 0
            SetPlace(w, pt, c, pt, grow == "LEFT" and -x or x, 0)
            x = x + wd + space
            maxH = math.max(maxH, w:GetHeight() or 0)
        end
        c:SetSize(math.max(x - space, c.minW or 1), math.max(maxH, c.minH or 1))
    elseif grow == "HORIZONTAL" then
        local total = 0
        for _, w in ipairs(list) do total = total + (w:GetWidth() or 0) + space maxH = math.max(maxH, w:GetHeight() or 0) end
        total = total - space
        x = -total / 2
        for _, w in ipairs(list) do
            SetPlace(w, "LEFT", c, "CENTER", x, 0)
            x = x + (w:GetWidth() or 0) + space
        end
        c:SetSize(math.max(total, c.minW or 1), math.max(maxH, c.minH or 1))
    elseif grow == "VERTICAL" then
        local total = 0
        for _, w in ipairs(list) do total = total + (w:GetHeight() or 0) + space maxW = math.max(maxW, w:GetWidth() or 0) end
        total = total - space
        y = total / 2
        for _, w in ipairs(list) do
            SetPlace(w, "TOP", c, "CENTER", 0, y)
            y = y - (w:GetHeight() or 0) - space
        end
        c:SetSize(math.max(maxW, c.minW or 1), math.max(total, c.minH or 1))
    elseif grow == "GRID" then
        local cols = tonumber(grp.gridWidth) or 5
        local cw, ch = 0, 0
        for _, w in ipairs(list) do cw = math.max(cw, w:GetWidth() or 0) ch = math.max(ch, w:GetHeight() or 0) end
        local rs, cs = tonumber(grp.rowSpace) or 1, tonumber(grp.columnSpace) or 1
        if lay then rs, cs = tonumber(lay.spacingY) or rs, tonumber(lay.spacingX) or cs end
        local rows = math.ceil(n / cols)
        for i, w in ipairs(list) do
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            SetPlace(w, "TOPLEFT", c, "TOPLEFT", col * (cw + cs), -row * (ch + rs))
        end
        c:SetSize(math.max(math.min(n, cols) * (cw + cs) - cs, 1), math.max(rows * (ch + rs) - rs, 1))
    else
        -- CIRCLE and friends: a ring
        local r = tonumber(grp.radius) or 100
        for i, w in ipairs(list) do
            local a = (i - 1) / math.max(n, 1) * 2 * math.pi
            SetPlace(w, "CENTER", c, "CENTER", math.sin(a) * r, math.cos(a) * r)
        end
        c:SetSize(1, 1)
    end
    c.dirty = nil
    -- a plate strip that grew or emptied on my target's plate: the
    -- crosshair re-measures the plate's reach
    if grp.zuiPlate and c._zuiN ~= n then
        c._zuiN = n
        local NP = ns.Nameplates
        local f = c.unit and L.NamePlate(c.unit)
        if f and NP and NP.UnderContentChanged then NP.UnderContentChanged(f) end
    end
end

-- The settings page's sample list: a plain frame with .grp / .members (its
-- own sample widgets: .container = it, .state, .seq), laid out by the very
-- code above. (`gkey`: the group whose saved layout it shows.)
function L.ArrangeSample(c, gkey)
    c.gkey = gkey
    c.minW, c.minH = c.minW or 1, c.minH or 1
    Arrange(c)
end

local function Flush()
    flushQueued = false
    for c in pairs(dirty) do
        dirty[c] = nil
        if c.dirty then Arrange(c) end
    end
end
local function MarkDirty(c)
    if not c then return end
    c.dirty = true
    dirty[c] = true
    if not flushQueued then
        flushQueued = true
        C_Timer.After(0, Flush)
    end
end
L.MarkDirty = MarkDirty

-- a list's saved layout changed: every container of that group (all when nil) looks again
function L.ReArrange(gkey)
    for _, c in pairs(containers) do
        if gkey == nil or c.gkey == gkey then MarkDirty(c) end
    end
end

-- ============================================================
-- PLACING A WIDGET
-- ============================================================
local seq = 0
local unitAnchored = {}     -- widget -> "unit" (a raid frame) or "plate" (a nameplate): re-anchored on roster or plate changes

local function Detach(w)
    if w.container then
        local c = w.container
        w.container = nil
        MarkDirty(c)
    end
    unitAnchored[w] = nil
end

function L.Place(w)
    local def = w.inst.def
    local D = w.D or def.display or {}
    local grp = GroupDef(def.group)
    seq = seq + 1
    w.seq = seq
    w.placedUnit = w.state and w.state.unit
    w.animX, w.animY = 0, 0
    w:SetParent(UIParent)
    local selfPoint, anchorPoint = D.selfPoint or "CENTER", D.anchorPoint or "CENTER"
    local x, y = tonumber(D.xOffset) or 0, tonumber(D.yOffset) or 0
    -- 1. the leaf names its own anchor
    if def.anchor and L.anchorFrames[def.anchor] then
        SetPlace(w, selfPoint, L.anchorFrames[def.anchor], anchorPoint, x, y)
        return
    end
    if def.anchorTo then
        local target = ResolveAnchorTo(def.anchorTo)
        if target then SetPlace(w, selfPoint, target, anchorPoint, x, y) w:Show() else w:Hide() end
        return
    end
    local unit = w.state and w.state.unit
    -- 2. a per-unit group: one cluster per raid frame
    if PerUnit(grp) then
        if not unit then w:Hide() return end
        local c = L.Container(def.group, unit)
        if not c then w:Hide() return end
        PositionContainer(c)
        w.container = c
        w:SetParent(c)
        c.members[#c.members + 1] = w
        unitAnchored[w] = "unit"
        MarkDirty(c)
        return
    end
    -- 3. riding a raid frame or a nameplate
    if D.anchorFrameType == "UNITFRAME" then
        local f = L.UnitFrame(unit)
        unitAnchored[w] = "unit"
        if not f then w:Hide() return end
        w:SetParent(f)
        SetPlace(w, selfPoint, f, anchorPoint, x, y)
        w:Show()
        return
    elseif D.anchorFrameType == "NAMEPLATE" then
        local f = L.NamePlate(unit)
        unitAnchored[w] = "plate"
        if not f then w:Hide() return end
        -- ZacUI's plate: into the plate strip, one row at one spot
        if f.health and PlateStripSpot() and RM.groups[PLATE_STRIP] then
            local c = L.Container(PLATE_STRIP, unit)
            if c then
                PositionContainer(c)
                w.container = c
                w:SetParent(c)
                c.members[#c.members + 1] = w
                MarkDirty(c)
                w:Show()
                return
            end
        end
        w:SetParent(f)
        SetPlace(w, selfPoint, f, anchorPoint, x, y)
        w:Show()
        return
    end
    -- 4. its group
    if grp then
        local c = L.Container(def.group)
        if IsDynamic(grp) then
            w.container = c
            c.members[#c.members + 1] = w
            MarkDirty(c)
        else
            SetPlace(w, selfPoint, c, "CENTER", x, y)
        end
        return
    end
    -- 5. nowhere in particular: its own screen offsets
    SetPlace(w, selfPoint, UIParent, anchorPoint, x, y)
end

function L.Remove(w)
    Detach(w)
    w.place = nil
end

-- the widget changed size or unit: a dynamic container must look again
function L.Changed(w)
    if w.container then
        -- a plate-strip widget follows its unit: a recycled plate token
        -- means another mob, so it moves to that plate's strip
        if w.container.grp and w.container.grp.zuiPlate then
            local unit = w.state and w.state.unit
            if unit ~= w.placedUnit then
                w.placedUnit = unit
                Detach(w)
                L.Place(w)
                return
            end
        end
        local wd, h = w:GetWidth(), w:GetHeight()
        if w.lastW ~= wd or w.lastH ~= h or w.container.dirty then
            w.lastW, w.lastH = wd, h
            MarkDirty(w.container)
        end
        return
    end
    if unitAnchored[w] then
        local unit = w.state and w.state.unit
        if unit ~= w.placedUnit then
            w.placedUnit = unit
            L.Place(w)
        end
    end
end

-- roster or plates moved: what rides on a unit frame ("unit") or on a
-- nameplate ("plate") is re-placed - only that kind, or both (nil)
local replacing = {}
local function Replace(kind)
    -- L.Place rewrites unitAnchored while this walks it: walk a copy
    wipe(replacing)
    for w, k in pairs(unitAnchored) do
        if not kind or k == kind then replacing[#replacing + 1] = w end
    end
    for i = 1, #replacing do
        local w = replacing[i]
        if w.inst and w.state then
            if w.container then
                Detach(w)
            end
            L.Place(w)
        end
    end
    wipe(replacing)
    for _, c in pairs(containers) do
        if c.unit and (not kind or (kind == "plate") == (c.grp.zuiPlate and true or false)) then PositionContainer(c) end
    end
end
L.Replace = function() Replace() end

-- after a mover drag the container keeps following its anchor frame;
-- a screen-positioned group reads its own mover
function L.ApplyMovers()
    for _, c in pairs(containers) do
        if not c.unit and not c.grp.anchor and not c.grp.anchorTo and not c.grp.parent then PositionContainer(c) end
    end
end

-- ============================================================
-- MOVERS FOR THE GROUPS THAT STAND ON THEIR OWN
-- ============================================================
local function RegisterGroupMovers()
    if not ns.RegisterMover then return end
    for _, key in ipairs(RM.groupOrder) do
        local grp = RM.groups[key]
        if grp.visible and not grp.anchor and not grp.anchorTo and not grp.parent and not PerUnit(grp) and grp.anchorFrameType ~= "UNITFRAME" and grp.anchorFrameType ~= "NAMEPLATE" then
            local label = "Raid mods: " .. (grp.name or key):gsub("^%[[^%]]*%]:?%s*", "")
            local raid = RM.raids[grp.raid]
            if raid then label = label .. " (" .. raid.name .. ")" end
            local point = grp.selfPoint or "CENTER"
            local dx, dy = SamePointOffset(point, grp.anchorPoint or "CENTER", tonumber(grp.xOffset) or 0, tonumber(grp.yOffset) or 0)
            ns.RegisterMover(MoverKey("g_" .. key), label, function() return L.Container(key) end, point, dx, dy, nil,
                { reset = function()
                    local c = L.Container(key)
                    if c and c.grp then PositionContainer(c) end
                end })
        end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "Zacui_RaidMods" then
            RegisterGroupMovers()
            frame:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        for _, a in ipairs(ANCHORS) do
            PlaceDefault(L.anchorFrames[a.key], a.point, a.relPoint, a.x, a.y, MoverKey(a.key))
            -- the mover handle's default spot, now that the screen has a size
            local m = ns.MOVERS and ns.MOVERS[MoverKey(a.key)]
            if m then m.defX, m.defY = SamePointOffset(a.point, a.relPoint, a.x, a.y) end
        end
        L.ApplyMovers()
        Replace()
    else
        -- plates come and go all fight: one pass a little later, and only
        -- for what rides on a nameplate
        if next(unitAnchored) then L.ReplacePlatesSoon() end
    end
end)
L.ReplacePlatesSoon = ns.Coalescer(function() Replace("plate") end, 0.2)
-- the group changed (ns.Roster, once per burst): what rides on a raid
-- frame follows its unit to the new frame
ns.Roster.On("RaidMods.anchors", function()
    if next(unitAnchored) then Replace("unit") end
end)

-- The mover system moves the frames it is given directly: the anchor
-- frames, and the screen groups' containers (their getFrame hands the
-- container itself over), so a drag lands without any help from here.

-- ============================================================
-- THE HANDLES
-- ============================================================
-- The preview's move handles: one translucent, labelled, draggable plate
-- over each anchor's content (and over each group that stands on its
-- own), sized to what is actually drawn there right now. Drag it and the
-- anchor underneath moves with it, content and all, live; drop it and
-- the position is saved in the same place ZacUI's movers keep theirs
-- (ZacUIDB.movers[key]), so the Movers page and Edit Mode agree. Right-
-- click puts that one back where the packs had it. Arrow keys or the
-- mouse wheel nudge the handle under the cursor (Shift: ten) - all of it
-- through ZacUI's handle kit (ns.MoverKit), like every other box.
local handles = {}          -- moverKey -> plate
local handleTicker

local function Short(label)
    return (label:gsub("^Raid mods: ", ""))
end

-- the rectangle the content of an anchor covers right now (its
-- containers that have something in them), in UIParent coordinates
local function ContentRect(anchorKey)
    local l, b, r, t
    for _, c in pairs(containers) do
        if c.grp.anchor == anchorKey and c:IsShown() and (c:GetWidth() or 0) > 2 and (c:GetHeight() or 0) > 2 then
            local cl, cb, cr, ct = c:GetLeft(), c:GetBottom(), c:GetRight(), c:GetTop()
            if cl and cb then
                l = l and math.min(l, cl) or cl
                b = b and math.min(b, cb) or cb
                r = r and math.max(r, cr) or cr
                t = t and math.max(t, ct) or ct
            end
        end
    end
    return l, b, r, t
end

local function FitHandle(h)
    local target = h.target()
    if not target then h:Hide() return end
    local l, b, r, t
    if h.anchorKey then l, b, r, t = ContentRect(h.anchorKey) end
    if not l then l, b, r, t = target:GetLeft(), target:GetBottom(), target:GetRight(), target:GetTop() end
    if not l then h:Hide() return end
    local w, ht = math.max(r - l, 120), math.max(t - b, 22)
    -- keep the plate centred on the content when it had to grow
    local cx, cy = (l + r) / 2, (b + t) / 2
    if not h.dragging then
        h:ClearAllPoints()
        h:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
        h:SetSize(w, ht)
    end
    h:Show()
    if ns.MoverKit then ns.MoverKit.Refresh(h) end
end

local function SaveHandle(h)
    local target = h.target()
    if not target then return end
    ZacUIDB.movers = ZacUIDB.movers or {}
    ZacUIDB.movers[h.moverKey] = { point = "BOTTOMLEFT", x = target:GetLeft() or 0, y = target:GetBottom() or 0 }
end

-- the anchor follows the plate while it is dragged
local function Follow(h)
    local target = h.target()
    if not target then return end
    local dx, dy = (h:GetLeft() or 0) - h.startL, (h:GetBottom() or 0) - h.startB
    target:ClearAllPoints()
    target:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", h.targetL + dx, h.targetB + dy)
end

local function Nudge(h, dx, dy)
    local target = h.target()
    if not target then return end
    local l, b = target:GetLeft() or 0, target:GetBottom() or 0
    target:ClearAllPoints()
    target:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l + dx, b + dy)
    SaveHandle(h)
    FitHandle(h)
end

-- the anchor's spot in the movers' numbers: what is saved, else where
-- the packs put it (while dragging: where it is now)
local function HandleCoords(h)
    local target = h.target()
    local text
    if h.dragging or not (ZacUIDB and ZacUIDB.movers and ZacUIDB.movers[h.moverKey]) then
        if target and target:GetLeft() then
            local m = ns.MOVERS and ns.MOVERS[h.moverKey]
            if not h.dragging and m and m.defPoint then
                text = ns.MoverKit.Format(m.defPoint, m.defX, m.defY)
            else
                text = ns.MoverKit.Format("BOTTOMLEFT", target:GetLeft(), target:GetBottom())
            end
        end
    else
        local pos = ZacUIDB.movers[h.moverKey]
        text = ns.MoverKit.Format(pos.point or "CENTER", pos.x, pos.y)
    end
    if not text then return nil end
    return text .. string.format("   %d x %d", math.floor((h:GetWidth() or 0) + 0.5), math.floor((h:GetHeight() or 0) + 0.5))
end

local function ResetHandle(h)
    ZacUIDB.movers = ZacUIDB.movers or {}
    ZacUIDB.movers[h.moverKey] = nil
    if h.anchorKey then
        local a = L.anchorFrames[h.anchorKey].anchorDef
        PlaceDefault(L.anchorFrames[h.anchorKey], a.point, a.relPoint, a.x, a.y, h.moverKey)
    else
        local t = h.target()
        if t and t.grp then PositionContainer(t) end
    end
    FitHandle(h)
end

-- built through ZacUI's handle kit: the same name, readout, nudge (arrow
-- keys / wheel), right-click reset and stacking as every other box
local function Handle(moverKey, label, target, anchorKey, color)
    local h = handles[moverKey]
    if h then return h end
    h = CreateFrame("Frame", nil, UIParent)
    handles[moverKey] = h
    h.moverKey, h.label, h.target, h.anchorKey = moverKey, label, target, anchorKey
    ns.MoverKit.Dress(h, {
        label = function(self) return Short(self.label) end,
        color = color,
        coords = HandleCoords,
        dragStart = function(self)
            local t = self.target()
            if not t then return end
            self.dragging = true
            self.startL, self.startB = self:GetLeft() or 0, self:GetBottom() or 0
            self.targetL, self.targetB = t:GetLeft() or 0, t:GetBottom() or 0
            self:StartMoving()
        end,
        onDrag = function(self) if self.dragging then Follow(self) end end,
        dragStop = function(self)
            if not self.dragging then return end
            self.dragging = nil
            SaveHandle(self)
            FitHandle(self)
        end,
        nudge = function(dx, dy, self) Nudge(self, dx, dy) end,
        reset = function(self) ResetHandle(self) end,
    })
    h:Hide()
    return h
end

local ANCHOR_COLOR = { 0.2, 0.75, 0.55 }
local GROUP_COLOR = { 0.75, 0.55, 0.2 }

local function RefitAll()
    for _, h in pairs(handles) do if h:IsShown() then FitHandle(h) end end
end

function L.ShowAnchors(on)
    L.showing = on and true or false
    if on then
        for _, a in ipairs(ANCHORS) do
            local h = Handle(MoverKey(a.key), a.label, function() return L.anchorFrames[a.key] end, a.key, ANCHOR_COLOR)
            FitHandle(h)
        end
        for _, key in ipairs(RM.groupOrder) do
            local mk = MoverKey("g_" .. key)
            if ns.MOVERS and ns.MOVERS[mk] then
                local h = Handle(mk, ns.MOVERS[mk].label or key, function() return L.Container(key) end, nil, GROUP_COLOR)
                FitHandle(h)
            end
        end
        if not handleTicker then
            -- the content under a handle grows and shrinks as the preview
            -- runs; the plates follow it twice a second
            handleTicker = C_Timer.NewTicker(0.5, RefitAll)
        end
    else
        for _, h in pairs(handles) do h:Hide() end
        if handleTicker then handleTicker:Cancel() handleTicker = nil end
        -- the Movers page's own proxies, if any were opened
        if ns.HideMover then
            for _, a in ipairs(ANCHORS) do ns.HideMover(MoverKey(a.key)) end
            for _, key in ipairs(RM.groupOrder) do ns.HideMover(MoverKey("g_" .. key)) end
        end
    end
end
function L.ResetAnchors()
    if not (ZacUIDB and ZacUIDB.movers) then return end
    for k in pairs(ZacUIDB.movers) do
        if k:find("^raidmods_") then ZacUIDB.movers[k] = nil end
    end
    for _, a in ipairs(ANCHORS) do PlaceDefault(L.anchorFrames[a.key], a.point, a.relPoint, a.x, a.y, MoverKey(a.key)) end
    L.ApplyMovers()
    RefitAll()
end
