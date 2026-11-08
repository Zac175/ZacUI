-- UIF_EditSession - what Edit Mode remembers while it is open, and the
-- links it can make between frames. No UI here (UIF_EditMode draws it).
-- Part of ZacUI; load order is set by the TOC (after UIF_Movers, before
-- UIF_EditMode).
--
-- THE SESSION. Entering Edit Mode takes a copy of every movable's spot of
-- record (each movable says how: snapshot() / restore(v)). From then on
-- every change - a drag, a nudge, a reset, a size match, an attach - is
-- noticed by comparing those copies (Check: called by the handle kit after
-- each move, and twice a second by Edit Mode for the frames that drag
-- themselves) and the spot it replaced is kept:
--   * Undo (Ctrl+Z) puts back the last move. Changes that land within a
--     moment of each other are one move (a "move all" handle and the
--     pieces it carries; a burst of arrow keys).
--   * Cancel puts back every movable that differs from its copy at entry.
--   * Save & Exit keeps everything (it was written as it happened).
-- Nothing is kept between passes and nothing new is saved.
--
-- LINKS ("Attach to..."). A ZacUI mover can follow another movable: the
-- link (ZacUIDB.editMode.links[follower], so it rides the Positions
-- section of a profile) keeps which point of the other frame it follows -
-- the side it sits beside, or the centre - and where that point was. When
-- that point moves, the follower is moved by the same amount through the
-- normal mover record, so the record stays a plain { point, x, y } that
-- everything else reads unchanged. Following happens when the other frame
-- is put in place by the mover registry (ApplyMover, for ZacUI movers)
-- and all the time while Edit Mode is open (a frame whose own settings
-- moved it catches up there). Nothing of this runs at login.

local ADDON_NAME, ns = ...

local Kit = ns.MoverKit
local MOVERS = ns.MOVERS

local ES = {}

-- ============================================================
-- HELPERS
-- ============================================================
-- a stable text of a spot (sorted keys, numbers to the hundredth), to
-- compare two copies
local function Ser(v)
    local t = type(v)
    if t == "number" then return ("%.2f"):format(v) end
    if t ~= "table" then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. Ser(v[k]) end
    return "{" .. table.concat(out, ",") .. "}"
end
ES.Ser = Ser

local function Copy(v)
    if type(v) ~= "table" then return v end
    local c = {}
    for k, x in pairs(v) do c[k] = Copy(x) end
    return c
end
ES.Copy = Copy

-- a frame's box in UIParent units (left, bottom, right, top), shown or not
local function Rect(f)
    if not (f and f.GetRect) then return nil end
    local l, b, w, h = f:GetRect()
    if not (l and b and w and h) or w <= 0 or h <= 0 then return nil end
    local us = UIParent:GetEffectiveScale() or 1
    local s = (f.GetEffectiveScale and f:GetEffectiveScale() or us) / (us > 0 and us or 1)
    return l * s, b * s, (l + w) * s, (b + h) * s
end
ES.Rect = Rect

-- one box round every frame in a movable's list ({ union = {...} } items
-- included); onlyShown: frames on screen only
local function ListRect(list, onlyShown)
    local L, B, R, T
    local function Add(f)
        if onlyShown and not (f.IsVisible and f:IsVisible()) then return end
        local l, b, r, t = Rect(f)
        if not l then return end
        if not L or l < L then L = l end
        if not B or b < B then B = b end
        if not R or r > R then R = r end
        if not T or t > T then T = t end
    end
    for _, item in ipairs(list or {}) do
        if type(item) == "table" and rawget(item, "union") then
            for _, f in ipairs(item.union) do Add(f) end
        elseif item then
            Add(item)
        end
    end
    return L, B, R, T
end

local function Call(fn)
    if not fn then return nil end
    local ok, v = pcall(fn)
    if ok then return v end
    return nil
end

-- the box Edit Mode draws for a movable (its handles), on screen
function ES.ScreenRect(m)
    return ListRect(Call(m.frames), true)
end

-- the box a link follows: the real frames (the same in and out of Edit
-- Mode), else the handles
local function FollowRect(m)
    local l, b, r, t = ListRect(Call(m.content), false)
    if l then return l, b, r, t end
    return ListRect(Call(m.frames), false)
end
ES.FollowRect = FollowRect

local function PointOf(l, b, r, t, ref)
    local pp = Kit.POINTS[ref] or Kit.POINTS.CENTER
    return l + (r - l) * pp[1], b + (t - b) * pp[2]
end

-- ============================================================
-- LINKS
-- ============================================================
local function Links(create)
    if type(ZacUIDB) ~= "table" then return nil end
    local d = ZacUIDB.editMode
    if type(d) ~= "table" then
        if not create then return nil end
        d = {}
        ZacUIDB.editMode = d
    end
    if type(d.links) ~= "table" then
        if not create then return nil end
        d.links = {}
    end
    return d.links
end
ES.Links = function() return Links(false) end

function ES.LinkOf(key)
    local links = Links(false)
    return links and links[key] or nil
end

-- the movables of the open pass, by key (UIF_EditMode hands them over)
local current = {}
function ES.SetMovables(list)
    wipe(current)
    for _, m in ipairs(list or {}) do current[m.key] = m end
end
function ES.Movable(key) return current[key] end

-- the box of a link's target by key: a ZacUI mover's frame (always), any
-- other movable while Edit Mode has it
local function TargetRect(key)
    if MOVERS[key] then
        local m = current[key]
        if m then return FollowRect(m) end
        local l, b, w, h = ns.MoverRect(key)
        if l then return l, b, l + w, b + h end
        return nil
    end
    local m = current[key]
    if m then return FollowRect(m) end
    return nil
end

local suspended = false
local following = {}

-- every follower of `key` catches up with it (and theirs with them)
local function Follow(key, depth)
    if suspended or following[key] or (depth or 0) > 8 then return end
    local links = Links(false)
    if not links then return end
    local l, b, r, t
    for fkey, link in pairs(links) do
        if link.to == key then
            if not l then
                l, b, r, t = TargetRect(key)
                if not l then return end
            end
            local x, y = PointOf(l, b, r, t, link.ref)
            local dx, dy = x - (link.x or x), y - (link.y or y)
            if math.abs(dx) > 0.01 or math.abs(dy) > 0.01 then
                following[key] = true
                local moved = ns.MoverShift and ns.MoverShift(fkey, dx, dy)
                following[key] = nil
                if moved then link.x, link.y = x, y end
                if moved then Follow(fkey, (depth or 0) + 1) end
            end
        end
    end
end
ES.Follow = Follow

function ES.FollowAll()
    local links = Links(false)
    if not links or next(links) == nil then return end
    local seen = {}
    for _, link in pairs(links) do
        if link.to and not seen[link.to] then
            seen[link.to] = true
            Follow(link.to)
        end
    end
end

-- the registry tells us when a mover was put in place (one table read
-- when nothing is attached: it runs inside the client's reflow hook)
ns.MoverMoved = function(key)
    if suspended then return end
    local d = ZacUIDB and ZacUIDB.editMode
    local links = d and d.links
    if not links or next(links) == nil then return end
    Follow(key)
end

-- would attaching `fkey` to `tkey` make a loop?
local function Loops(fkey, tkey)
    local links = Links(false)
    local k, n = tkey, 0
    while k and n < 50 do
        if k == fkey then return true end
        local link = links and links[k]
        k = link and link.to
        n = n + 1
    end
    return false
end

-- Attach a ZacUI mover to any movable. The point it follows is the side
-- of the target it sits beside (or the middle when it overlaps).
-- -> true, or false + why
function ES.Attach(fkey, target)
    if not MOVERS[fkey] then return false, "only ZacUI's own frames can follow another" end
    if not target or target.key == fkey then return false, "it cannot follow itself" end
    if Loops(fkey, target.key) then return false, target.label .. " already follows it" end
    local tl, tb, tr, tt = FollowRect(target)
    if not tl then return false, target.label .. " is not on screen" end
    local fl, fb, fw, fh = ns.MoverRect(fkey)
    local ref = "CENTER"
    if fl then
        local cx, cy = fl + fw / 2, fb + fh / 2
        local h = (cx < tl) and "LEFT" or (cx > tr) and "RIGHT" or ""
        local v = (cy < tb) and "BOTTOM" or (cy > tt) and "TOP" or ""
        ref = (v .. h ~= "") and (v .. h) or "CENTER"
    end
    local x, y = PointOf(tl, tb, tr, tt, ref)
    Links(true)[fkey] = { to = target.key, ref = ref, x = x, y = y }
    return true
end

function ES.Detach(fkey)
    local links = Links(false)
    if links then links[fkey] = nil end
end

-- the followers of a key, for the menu ("Bars 2 and 3 follow this")
function ES.FollowersOf(key)
    local out = {}
    local links = Links(false)
    for fkey, link in pairs(links or {}) do
        if link.to == key then out[#out + 1] = fkey end
    end
    table.sort(out)
    return out
end

-- ============================================================
-- SIZE MATCHING
-- ============================================================
-- `m` takes `other`'s drawn width (axis "w") or height ("h"), in UIParent
-- units; its own size setter does the rest. -> true, or false + why
function ES.Match(m, other, axis)
    if not (m and m.size and m.size.set) then return false, "its size comes from its own settings" end
    local ol, ob, or_, ot = ES.ScreenRect(other)
    if not ol then ol, ob, or_, ot = FollowRect(other) end
    if not ol then return false, other.label .. " is not on screen" end
    local w, h
    if axis == "w" then w = or_ - ol else h = ot - ob end
    local ok, err = pcall(m.size.set, w, h)
    if not ok then return false, tostring(err) end
    return true
end

-- ============================================================
-- THE SESSION
-- ============================================================
local S   -- nil when Edit Mode is closed
local MERGE = 0.6   -- changes this close together are one undo step

local function Snap(m)
    if not m.snapshot then return nil end
    local ok, v = pcall(m.snapshot)
    if ok then return v end
    return nil
end

local function Restore(key, v)
    if key == "_links" then
        if type(ZacUIDB) ~= "table" then return end
        if v then
            Links(true)
            ZacUIDB.editMode.links = Copy(v)
        elseif type(ZacUIDB.editMode) == "table" then
            ZacUIDB.editMode.links = nil
        end
        return
    end
    local m = current[key]
    if m and m.restore then pcall(m.restore, Copy(v)) end
end

-- the things a session watches: every movable that can snapshot, and the
-- links as one more
local function Each(fn)
    for key, m in pairs(current) do
        if m.snapshot then fn(key, Snap(m)) end
    end
    local links = Links(false)
    fn("_links", (links and next(links)) and Copy(links) or false)
end

function ES.Begin()
    S = { base = {}, baseSer = {}, last = {}, lastSer = {}, undo = {} }
    ES.FollowAll()
    Each(function(key, v)
        local s = Ser(v)
        S.base[key], S.baseSer[key] = v, s
        S.last[key], S.lastSer[key] = v, s
    end)
end

function ES.Active() return S ~= nil end

-- notice what changed since the last look; -> true when something did
function ES.Check()
    if not S then return false end
    local batch
    Each(function(key, v)
        local s = Ser(v)
        if S.lastSer[key] == nil then
            -- a movable that joined mid-pass (a bar switched on): its
            -- first sight is its starting point
            S.base[key], S.baseSer[key] = v, s
            S.last[key], S.lastSer[key] = v, s
        elseif s ~= S.lastSer[key] then
            batch = batch or {}
            batch[key] = { v = S.last[key] }
            S.last[key], S.lastSer[key] = v, s
        end
    end)
    if not batch then return false end
    local now = GetTime and GetTime() or 0
    local top = S.undo[#S.undo]
    if top and now - top.t <= MERGE then
        for key, w in pairs(batch) do
            if top.prev[key] == nil then top.prev[key] = w end
        end
        top.t = now
    else
        S.undo[#S.undo + 1] = { prev = batch, t = now }
    end
    if ES.OnChange then pcall(ES.OnChange) end
    return true
end

local function AfterRestore()
    -- the class HUDs' "move all" handle carries its pieces when its box
    -- moves: told where the box is now, so a put-back is not carried twice
    if ns.HUD and ns.HUD.SyncGroups then pcall(ns.HUD.SyncGroups) end
end

local function Reread(keys)
    Each(function(key, v)
        if keys == nil or keys[key] then
            S.last[key], S.lastSer[key] = v, Ser(v)
        end
    end)
end

function ES.CanUndo()
    return S ~= nil and #S.undo > 0
end

-- put back the last move; -> true when there was one
function ES.Undo()
    if not S then return false end
    ES.Check()
    local top = table.remove(S.undo)
    if not top then return false end
    suspended = true
    -- the links first, so a frame put back is not then carried by one
    if top.prev._links then Restore("_links", top.prev._links.v) end
    for key, w in pairs(top.prev) do
        if key ~= "_links" then Restore(key, w.v) end
    end
    suspended = false
    AfterRestore()
    Reread(nil)
    if ES.OnChange then pcall(ES.OnChange) end
    return true
end

-- is this one moved since Edit Mode opened?
function ES.Moved(key)
    return S ~= nil and S.lastSer[key] ~= nil and S.lastSer[key] ~= S.baseSer[key]
end

function ES.MovedCount()
    if not S then return 0 end
    local n = 0
    for key, s in pairs(S.lastSer) do
        if key ~= "_links" and s ~= S.baseSer[key] then n = n + 1 end
    end
    return n
end

-- everything back as it was when Edit Mode opened; -> how many
function ES.Cancel()
    if not S then return 0 end
    ES.Check()
    local n = 0
    suspended = true
    if S.lastSer._links ~= S.baseSer._links then Restore("_links", S.base._links) end
    for key, s in pairs(S.lastSer) do
        if key ~= "_links" and s ~= S.baseSer[key] then
            Restore(key, S.base[key])
            n = n + 1
        end
    end
    suspended = false
    AfterRestore()
    Reread(nil)
    S.undo = {}
    return n
end

function ES.End()
    S = nil
    wipe(current)
end

-- ============================================================
-- SETTINGS PAGES: which page styles a movable ("Open its settings", and
-- the pages' "Move in Edit Mode" button). A mover may name its own
-- (RegisterMover opts.page / a movable's page); else by its key.
-- ============================================================
local PAGE_BY_KEY = {
    lootroll = "lootroll", buffs = "buffs", minimap = "minimap", tray = "minimap",
    tooltip = "tooltips", privacytag = "chat", flighttimer = "flighttimes",
    raidtimers = "qol", gcdtracker = "qol", snowball = "qol", lootfeed = "qol",
    talentreminder = "qol", unitframes = "unitframes", hesitation = "hesitation",
    qolalerts = "qol", qolstats = "qol", qoljunk = "qol", qolreminders = "qol", qoldistance = "qol",
    platePreview = "nameplates", prioWarn = "nameplates", rmRazTarget = "raidmods",
}
local PAGE_BY_PREFIX = {
    { "^zbar_", "bars" }, { "^sbt_", "sbt" }, { "^meter%d", "meter" },
    { "^raidmods_", "raidmods" }, { "^consbars_", "consbars" }, { "^buffRem", "buffrem" },
    { "^blessings", "blessings" }, { "^wh", "warrior" },
}

-- is there a menu entry with this id? (the ids are gathered once and
-- again only when the menu grows - parts add their rows as they load)
local menuIds, menuSize
local function MenuHas(id)
    local menu = ns.ConfigMenu
    local size = 0
    for _, it in ipairs(menu or {}) do size = size + 1 + #(it.children or {}) end
    if not menuIds or size ~= menuSize then
        menuIds, menuSize = {}, size
        local function Walk(list)
            for _, it in ipairs(list or {}) do
                if it.id then menuIds[it.id] = true end
                if it.children then Walk(it.children) end
            end
        end
        Walk(menu)
    end
    return menuIds[id] == true
end

function ES.PageFor(m)
    if not m then return nil end
    local page = m.page
    if not page then
        local reg = MOVERS[m.key]
        page = reg and reg.page
    end
    if not page then page = PAGE_BY_KEY[m.key] end
    if not page then
        for _, p in ipairs(PAGE_BY_PREFIX) do
            if tostring(m.key):find(p[1]) then page = p[2] break end
        end
    end
    if page and MenuHas(page) then return page end
    return nil
end

-- the keys whose settings live on a page (for the page's own button):
-- the registry's movers, plus the families the parts list by prefix
function ES.KeysForPage(pageId, list)
    local out = {}
    for _, m in ipairs(list or {}) do
        if ES.PageFor(m) == pageId then out[#out + 1] = m.key end
    end
    return out
end

-- shared with later ZacUI files
ns.EditSession = ES
