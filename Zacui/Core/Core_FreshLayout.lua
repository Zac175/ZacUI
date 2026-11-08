-- Core_FreshLayout - a fresh install keeps the player's layout.
-- Part of ZacUI; load order is set by the TOC (before the parts).
--
-- On a FRESH install (ns.freshInstall: nothing saved on this account) and
-- after "Reset ZacUI" (ns.openSetupAfterReset), ZacUI's action bars and
-- unit frames would otherwise appear on their own defaults the moment they
-- replace Blizzard's - six bars stacked in one spot, the player frame
-- leaping from the top left to under the character. Instead, just before
-- each part puts Blizzard's frames away, where they are is read and ZacUI's
-- matching part is placed there (centred on it, the same way up):
--
--   action bars   bar 1 <- the main bar's buttons; bars 3 / 4 / 5 / 6 <-
--                 the right, left, bottom right and bottom left bars (the
--                 pages ZacUI's bars already share with them); bar 2 (no
--                 Blizzard bar of its own) just above the bottom ones; the
--                 pet and stance bars <- Blizzard's. A Blizzard bar that
--                 stands upright makes its ZacUI bar one button wide.
--   unit frames   player, target, target of target, pet, focus <- their
--                 Blizzard frames; party <- the first party frame - but
--                 only a frame the player had moved off Blizzard's own
--                 default spot (Edit Mode's IsInDefaultPosition, or a
--                 user-placed frame); one still on Blizzard's default
--                 keeps ZacUI's designed HUD spot.
--
-- Read from the frames themselves (what is on the screen, whatever placed
-- it), at the last moment before they are hidden: each part calls in just
-- before it puts Blizzard's away (AB.HideBlizzard, just before the bars
-- are first built; the unit frames' Init, right after it reads its
-- settings and before it builds a frame). No frame, event or timer of its
-- own. An existing install is never touched, a frame that is not there is
-- skipped, and nothing is written that the part would not have written
-- anyway (its own spot keys, once). Nothing prints.

local ADDON_NAME, ns = ...

local FL = {}
ns.FreshLayout = FL
FL.done = {}            -- what was placed this login (for /zui and tests)

local function Fresh()
    return ns.freshInstall == true or ns.openSetupAfterReset == true
end

-- a frame's box in UIParent units: left, bottom, right, top (nil when it
-- has none)
local function Rect(f)
    if type(f) ~= "table" or not f.GetRect then return nil end
    local ok, l, b, w, h = pcall(f.GetRect, f)
    if not (ok and l and b and w and h) or w <= 0 or h <= 0 then return nil end
    local us = UIParent:GetEffectiveScale() or 1
    local s = (f.GetEffectiveScale and f:GetEffectiveScale() or us) / (us > 0 and us or 1)
    return l * s, b * s, (l + w) * s, (b + h) * s
end

-- one box round the shown buttons of a bar (prefix1..n); all of them when
-- none is shown (a bar the player has switched off still has its place)
local function ButtonsRect(prefix, n)
    local function Union(onlyShown)
        local L, B, R, T
        for i = 1, n do
            local f = _G[prefix .. i]
            if f and (not onlyShown or (f.IsShown and f:IsShown())) then
                local l, b, r, t = Rect(f)
                if l then
                    L = (L and math.min(L, l)) or l
                    B = (B and math.min(B, b)) or b
                    R = (R and math.max(R, r)) or r
                    T = (T and math.max(T, t)) or t
                end
            end
        end
        return L, B, R, T
    end
    local l, b, r, t = Union(true)
    if l then return l, b, r, t end
    return Union(false)
end

-- ============================================================
-- ACTION BARS
-- ============================================================
local BARS = {
    { key = 1, prefix = "ActionButton", n = 12 },
    { key = 6, prefix = "MultiBarBottomLeftButton", n = 12 },
    { key = 5, prefix = "MultiBarBottomRightButton", n = 12 },
    { key = 3, prefix = "MultiBarRightButton", n = 12 },
    { key = 4, prefix = "MultiBarLeftButton", n = 12 },
    { key = "pet", prefix = "PetActionButton", n = 10, size = "PET_BUTTON" },
    { key = "stance", prefix = "StanceButton", n = 10, size = "PET_BUTTON" },
}

-- the header spot (AB's own convention: nearest screen anchor by thirds,
-- UIParent units) that puts the bar's buttons centred on cx, cy
local function BarSpot(AB, cfg, cx, cy, count, size)
    local s = cfg.scale or 1
    if s <= 0 then s = 1 end
    local perRow, rows, padX, padY = AB.LayoutShape(cfg, count)
    local w = (perRow * size + (perRow - 1) * padX) * s
    local h = (rows * size + (rows - 1) * padY) * s
    local _, v, hz = AB.AnchorOf(cfg)
    -- the first button sits 5 / -3 in from the header's corner (AB.LayoutButtons)
    local ox = (hz == "LEFT") and 5 or -3
    local oy = (v == "TOP") and -3 or 5
    local px = ((hz == "LEFT") and (cx - w / 2) or (cx + w / 2)) - ox * s
    local py = ((v == "TOP") and (cy + h / 2) or (cy - h / 2)) - oy * s
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    local H = (px < uw / 3) and "LEFT" or (px > uw * 2 / 3) and "RIGHT" or ""
    local V = (py < uh / 3) and "BOTTOM" or (py > uh * 2 / 3) and "TOP" or ""
    local x = (H == "LEFT") and px or (H == "RIGHT") and (px - uw) or (px - uw / 2)
    local y = (V == "BOTTOM") and py or (V == "TOP") and (py - uh) or (py - uh / 2)
    local point = V .. H
    if point == "" then point = "CENTER" end
    return point, math.floor(x + 0.5), math.floor(y + 0.5)
end

function FL.Bars(AB)
    if FL.done.bars or not Fresh() then return end
    FL.done.bars = 0
    local ok, p = pcall(AB.Profile)
    if not (ok and type(p) == "table") then return end
    local placed, stackTop, mainX = 0, nil, nil
    for _, spec in ipairs(BARS) do
        local cfg = (type(spec.key) == "number") and p.bars and p.bars[spec.key] or p[spec.key]
        local l, b, r, t = ButtonsRect(spec.prefix, spec.n)
        if type(cfg) == "table" and cfg.point == nil and l then
            -- upright on Blizzard's side: one button wide on ours
            if (t - b) > (r - l) * 1.5 then cfg.rows = cfg.buttons or 12 end
            local size = cfg.buttonSize or AB[spec.size or "BUTTON"] or 36
            local count = (spec.key == "stance" or spec.key == "pet") and spec.n or (cfg.buttons or 12)
            cfg.point, cfg.x, cfg.y = BarSpot(AB, cfg, (l + r) / 2, (b + t) / 2, count, size)
            placed = placed + 1
            if spec.key == 1 then mainX = (l + r) / 2 end
            if spec.key == 1 or spec.key == 5 or spec.key == 6 then
                stackTop = math.max(stackTop or t, t)
            end
        end
    end
    -- bar 2 has no Blizzard bar: just above the bottom ones, in the middle
    local cfg2 = p.bars and p.bars[2]
    if type(cfg2) == "table" and cfg2.point == nil and stackTop and mainX then
        local size = cfg2.buttonSize or AB.BUTTON or 36
        local s = cfg2.scale or 1
        local _, rows, _, padY = AB.LayoutShape(cfg2, cfg2.buttons or 12)
        local h = (rows * size + (rows - 1) * padY) * s
        cfg2.point, cfg2.x, cfg2.y = BarSpot(AB, cfg2, mainX, stackTop + 6 + h / 2, cfg2.buttons or 12, size)
        placed = placed + 1
    end
    FL.done.bars = placed
end

-- ============================================================
-- UNIT FRAMES
-- ============================================================
local UNITS = {
    player = { "PlayerFrame" },
    target = { "TargetFrame" },
    targettarget = { "TargetFrameToT" },
    pet = { "PetFrame" },
    focus = { "FocusFrame" },
}

-- Did the player move this Blizzard frame off Blizzard's own default spot?
-- Blizzard's Edit Mode says so (IsInDefaultPosition false); on the older
-- clients a frame dragged with its Unlock option is user-placed.
local function MovedByPlayer(f)
    if type(f) ~= "table" then return false end
    if f.IsInDefaultPosition then
        local ok, v = pcall(f.IsInDefaultPosition, f)
        if ok and v == false then return true end
    end
    if f.IsUserPlaced then
        local ok, v = pcall(f.IsUserPlaced, f)
        if ok and v == true then return true end
    end
    return false
end
FL.MovedByPlayer = MovedByPlayer

-- where Blizzard's unit frames are now, the ones the player moved only:
-- a frame still on Blizzard's default spot leaves ZacUI's own designed
-- spot in place (the unit frames are laid out as a HUD, not as Blizzard's)
function FL.ReadUnits()
    local out = {}
    for key, names in pairs(UNITS) do
        for _, name in ipairs(names) do
            local f = _G[name]
            local l, b, r, t = Rect(f)
            if l then
                if MovedByPlayer(f) then out[key] = { l, b, r, t } end
                break
            end
        end
    end
    local first = _G.PartyMemberFrame1 or (_G.PartyFrame and _G.PartyFrame.MemberFrame1) or _G.PartyFrame
    local l, b, r, t = Rect(first)
    if l and (MovedByPlayer(first) or MovedByPlayer(_G.PartyFrame)) then out.party = { l, b, r, t } end
    return out
end

function FL.Units(UF)
    if FL.done.units or not Fresh() then return end
    local db = UF and UF.db
    if type(db) ~= "table" or type(db.frames) ~= "table" then return end
    FL.done.units = 0
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    local rects = FL.ReadUnits()
    local n = 0
    for key in pairs(UNITS) do
        local cfg = db.frames[key]
        local rc = rects[key]
        local l, b, r, t
        if rc then l, b, r, t = rc[1], rc[2], rc[3], rc[4] end
        if type(cfg) == "table" and l then
            cfg.point = "CENTER"
            cfg.x = math.floor((l + r) / 2 - uw / 2 + 0.5)
            cfg.y = math.floor((b + t) / 2 - uh / 2 + 0.5)
            n = n + 1
        end
    end
    -- party: the block's top left on the first party frame's
    local pr = rects.party
    local l, t = pr and pr[1], pr and pr[4]
    if l and type(db.party) == "table" then
        db.party.point, db.party.x, db.party.y = "TOPLEFT", math.floor(l + 0.5), math.floor(t - uh + 0.5)
        n = n + 1
    end
    FL.done.units = n
end
