-- SCT_PlateText - your damage on the enemy's nameplate.
-- Part of ZacUI (Zacui_SBT). Written for ZacUI.
--
-- Zac (2026-10-24): Blizzard's own damage numbers off, "i kinda like the
-- damage numbers coming from the nameplates but it cant overlap the noob
-- stuff that is very imporatant that that doenst oerlap".
--
-- What it draws: each hit you land, as a small number with the ability's
-- icon in front of it, in a column that drifts gently up off the TOP-RIGHT
-- of the mob's nameplate and fades - no pop, no bounce (Zac, 01:03:
-- "smaller numbers that pop off nameplates with icons for the ability etc.
-- in a non intrustive annimation"). Crits a little bigger and gold, your
-- white swings smaller and grey, Dodge / Parry / Miss in words, damage over
-- time small. The target's column full size, other mobs' (a Whirlwind, a
-- Cleave) a size down and one at a time.
--
-- NEVER OVER THE NOOB ROW. The Bloodthirst / Whirlwind / Overpower /
-- Execute row (HUD > Hesitation) sits centred over the target's health
-- bar and grows when an ability is ignored (up to plateGrowMax). The
-- column's left edge is kept right of the widest that row can ever get
-- (every icon it can show, one at its biggest, the glow round it) - a
-- fixed spot, so the numbers never jump when the row grows - and it starts
-- just above the bar, clear of the Sunder count beside it. The crosshair's
-- line runs up the middle, so the side keeps it clear too.
--
-- How it gets the hits: SCT_Events already reads the combat log and asks
-- this file first about each hit you land (PT.Take); a hit taken here
-- does not also scroll in the Outgoing area, so nothing shows twice. A
-- hit on a mob whose nameplate is not on screen is NOT taken and scrolls
-- as before - nothing is lost.
--
-- Cost: no combat-log handler of its own. Per hit: two table lookups, one
-- pooled frame. One OnUpdate, running only while a number is on screen.
local ns = _G.ZacUI
if not ns then return end
local S = ns.SBT
if not S then return end
local PT = {}
S.PlateText = PT

local GetTime = GetTime
local UnitGUID = UnitGUID
local UnitIsUnit = UnitIsUnit
local math_floor, math_max, math_min = math.floor, math.max, math.min
local string_format = string.format

local DEFAULTS = {
    enabled = false,     -- your hits on the nameplate instead of the Outgoing area
                         -- (off since 2026-10-24, Zac: "change my msbt back to what it was
                         -- before the nameplate stuff ... i like the other one much more")
    others = true,       -- on other mobs' plates too (a size down)
    misses = true,       -- Dodge / Parry / Miss ...
    dots = true,         -- damage over time ticks, small
    size = 13,           -- an ability hit on the target; crits 1.3x, white swings 0.85x
    lines = 4,           -- numbers at once on the target's plate (others: 1)
    icons = true,        -- the ability's icon in front of the number
    -- look (the Text tab); face nil = the scrolling text's font
    outline = "OUTLINE",
    shadow = true,
    critScale = 130,     -- percent: a crit's size against a hit's
    colors = {},         -- [kind] = { r, g, b }; nil = the palette's colour
    -- motion (the Animation tab), the timings it always had
    life = 1.1,          -- seconds on screen
    fadeIn = 0.08,
    fadeOut = 0.35,
    rise = 14,           -- pixels it drifts up
    drift = 5,           -- ... and right
}
PT.DEFAULTS = DEFAULTS
-- the palette colour each kind of number wears unless you pick one
PT.KINDS = {
    { key = "hit",   label = "Ability hits",  pal = "normal", r = 0.9, g = 0.9, b = 0.9 },
    { key = "crit",  label = "Crits",         pal = "gold",   r = 1,   g = 0.82, b = 0 },
    { key = "white", label = "Swings",        pal = "gray",   r = 0.6, g = 0.6, b = 0.6 },
    { key = "dot",   label = "Damage over time", pal = "gray", r = 0.6, g = 0.6, b = 0.6 },
    { key = "dodge", label = "Dodges",        pal = "orange", r = 1,   g = 0.6, b = 0.2 },
    { key = "miss",  label = "Other misses",  pal = "gray",   r = 0.6, g = 0.6, b = 0.6 },
}
local KIND_BY = {}
for _, k in ipairs(PT.KINDS) do KIND_BY[k.key] = k end

-- The settings live in the scrolling text's own table (sct.plates), so a
-- profile carries them; SCT_Settings moved the first version's copy in.
-- Defaults are filled once per stored table.
local cfgFor
function PT.Cfg()
    local c = S.Cfg().plates
    if c == cfgFor then return c end
    for k, v in pairs(DEFAULTS) do
        if c[k] == nil then c[k] = (S.Copy and S.Copy(v)) or v end
    end
    cfgFor = c
    return c
end

-- ============================================================
-- GUID -> NAMEPLATE
-- ============================================================
-- ZacUI's own nameplates already keep a GUID -> plate map; while they run
-- that one answers and this file keeps none of its own. With them off
-- (or another nameplate addon), this tracks the plates itself.
local unitOf = {}          -- guid -> nameplate unit token (own plates only)
local function ZuiPlates()
    local NP = ns.Nameplates
    return NP and NP.enabled and NP.PlateByGUID and NP or nil
end

local function Rebuild()
    for k in pairs(unitOf) do unitOf[k] = nil end
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local u = plate.namePlateUnitToken
        local g = u and UnitGUID(u)
        if g then unitOf[g] = u end
    end
end

-- off where there is no combat log to feed it (Forever, or the game-
-- version override's Forever; Core_Flavor): it listens to nothing
local plateOn = not (ns.FeatureOn and not ns.FeatureOn("sbt_plates"))
local ev = CreateFrame("Frame")
if plateOn then
    ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    ev:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
end
local ownMap = false        -- unitOf is being kept (ZacUI plates off)
ev:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        if not ownMap then return end
        local g = unit and UnitGUID(unit)
        if g then unitOf[g] = unit end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if ownMap then
            for g, u in pairs(unitOf) do if u == unit then unitOf[g] = nil end end
        end
        PT.DropPlate(unit)
    else
        ownMap = not ZuiPlates()
        if ownMap then Rebuild() else wipe(unitOf) end
    end
end)

-- ============================================================
-- WHERE THE COLUMN GOES
-- ============================================================
-- In the plate holder's units: x from the health bar's centre to the
-- column's left edge, and y from the bar's centre to the column's floor.
local function Spot(plate, holder)
    local zf = rawget(plate, "_zuiNP")
    local bar = (type(zf) == "table" and zf.health and zf.health:IsShown()) and zf.health or nil
    local hs = holder:GetEffectiveScale() or 1
    local barW, barH = 100, 10
    if bar then
        local k = (bar:GetEffectiveScale() or 1) / hs
        barW, barH = (bar:GetWidth() or 100) * k, (bar:GetHeight() or 10) * k
    end
    local x = barW / 2 + 8
    -- the NOOB row's widest, in the bar's units, converted to the holder's
    local H = ns.Hesitation
    if bar and H and H.PlateRowHalfWidth then
        local half, off = H.PlateRowHalfWidth(zf)
        if half and half > 0 then
            local k = (bar:GetEffectiveScale() or 1) / hs
            x = math_max(x, (half + (off or 0)) * k + 6)
        end
    end
    -- above the bar (and the box round it), clear of the Sunder count
    local y = barH / 2 + 7
    return bar or plate, x, y
end

-- ============================================================
-- THE NUMBERS
-- ============================================================
-- A "column set": its own pool, its own numbers on screen and one driver
-- that runs only while a number is up. The live one draws on real plates;
-- the settings preview runs another on its canvas through the same code.
local holders = {}         -- unit token -> holder frame on that plate

-- on screen `life` seconds (1.1): in over fadeIn (0.08s), a slow drift up
-- (rise) and a little right (drift), eased so it starts moving and
-- settles, out over the last fadeOut (0.35s)
local function Timing(c)
    local on = true
    if S.MotionOn then on = S.MotionOn() end
    local ms = S.MotionSpeed and S.MotionSpeed() or 1
    local life = math_max(0.2, tonumber(c.life) or 1.1)
    local fin = on and math_max(0, tonumber(c.fadeIn) or 0.08) / ms or 0
    local fout = on and math_max(0, tonumber(c.fadeOut) or 0.35) / ms or 0
    return life, math_min(fin, life), math_min(fout, life),
        tonumber(c.rise) or 14, tonumber(c.drift) or 5
end

local function FontFor(c)
    return S.FontPath(c and c.face or S.Cfg().font)
end

local function Short(n)
    if not n then return "" end
    if n < 1000 then return tostring(math_floor(n + 0.5)) end
    if n < 10000 then
        local s = string_format("%.1fk", n / 1000)
        return (s:gsub("%.0k$", "k"))
    end
    return string_format("%dk", math_floor(n / 1000 + 0.5))
end
PT.Short = Short

-- the colour of one kind of number: yours, else the palette's
local function KindColor(kind)
    local own = PT.Cfg().colors
    own = type(own) == "table" and own[kind] or nil
    if type(own) == "table" and own.r then return own.r, own.g, own.b end
    local k = KIND_BY[kind] or KIND_BY.hit
    local c = ns.GetColor and ns.GetColor("text", k.pal)
    if c then return c.r, c.g, c.b end
    return k.r, k.g, k.b
end
PT.KindColor = KindColor

local Cols = {}
Cols.__index = Cols

function PT.NewColumns(root, preview)
    local e = setmetatable({ live = {}, pool = {}, preview = preview and true or false, root = root }, Cols)
    local d = CreateFrame("Frame", nil, preview and root or nil)
    d:Hide()
    d:SetScript("OnUpdate", function(self, elapsed) e:Step(self, elapsed) end)
    e.driver = d
    return e
end

function Cols:GetNum()
    local n = table.remove(self.pool)
    if not n then
        n = CreateFrame("Frame", nil, self.preview and self.root or nil)
        n:SetSize(1, 1)
        n.ic = n:CreateTexture(nil, "ARTWORK")
        n.ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        n.ic:SetPoint("BOTTOMLEFT", n, "BOTTOMLEFT", 0, 0)
        n.fs = n:CreateFontString(nil, "OVERLAY")
        n.fs:SetJustifyH("LEFT")
    end
    return n
end

function Cols:Free(n)
    n:Hide()
    n:ClearAllPoints()
    n.holder = nil
    self.pool[#self.pool + 1] = n
end

function Cols:DropHolder(h)
    for i = #h.nums, 1, -1 do
        local n = h.nums[i]
        h.nums[i] = nil
        for j = #self.live, 1, -1 do if self.live[j] == n then table.remove(self.live, j) end end
        self:Free(n)
    end
end

-- one hit -> one number in holder h (newest at the bottom of the
-- column). h carries anchor, ax, ay (where the column's floor is) and nums.
-- SetFont that says whether the face took: pcall catches a nil path, the
-- return value a font file that would not load - which leaves the string
-- with no font, so its next SetText errors ("Font not set")
local function TrySetFont(fs, path, size, flags)
    local ok, set = pcall(fs.SetFont, fs, path, size, flags)
    return (ok and set) and true or false
end
function Cols:Add(h, isTarget, text, size, r, g, b, crit, icon)
    local c = PT.Cfg()
    local maxN = isTarget and (tonumber(c.lines) or 4) or 1
    local k = isTarget and 1 or 0.85
    local n = self:GetNum()
    n:SetParent(h)
    n.holder = h
    local px = math_max(8, math_floor(size * k + 0.5))
    if not TrySetFont(n.fs, FontFor(c), px, S.Flags and S.Flags(c.outline) or "OUTLINE") then
        pcall(n.fs.SetFont, n.fs, STANDARD_TEXT_FONT, px, "OUTLINE")
    end
    if c.shadow ~= false then
        n.fs:SetShadowOffset(1, -1)
        n.fs:SetShadowColor(0, 0, 0, 0.9)
    else
        n.fs:SetShadowOffset(0, 0)
    end
    n.fs:SetText(text)
    n.fs:SetTextColor(r, g, b, 1)
    n.fs:ClearAllPoints()
    if icon and c.icons ~= false then
        n.ic:SetTexture(icon)
        n.ic:SetSize(px, px)
        n.ic:Show()
        local spec = type(c.anchors) == "table" and c.anchors.icon or nil
        if spec and ns.ApplyAnchor then
            -- the saved icon spot (anchors.icon, ZacUI's anchor shape): the
            -- number holds the column's corner, the icon goes wherever the
            -- spot puts it round the number; in front of it is the default
            n.fs:SetPoint("BOTTOMLEFT", n, "BOTTOMLEFT", 0, 0)
            local d = n.icDef
            if not d then d = {} n.icDef = d end
            d.point, d.relPoint, d.x, d.y, d.to = "RIGHT", "LEFT", -2, 0, n.fs
            ns.ApplyAnchor(n.ic, spec, d)
            n.icMoved = true
        else
            if n.icMoved then
                -- (back where the number frame always kept it)
                n.ic:ClearAllPoints()
                n.ic:SetPoint("BOTTOMLEFT", n, "BOTTOMLEFT", 0, 0)
                n.icMoved = nil
            end
            n.fs:SetPoint("LEFT", n.ic, "RIGHT", 2, 0)
        end
    else
        n.ic:Hide()
        n.fs:SetPoint("BOTTOMLEFT", n, "BOTTOMLEFT", 0, 0)
    end
    n.h = math_max(px, n.fs:GetStringHeight() or px) + 2
    n.t0 = GetTime()
    n.life, n.fin, n.fout, n.rise, n.drift = Timing(c)
    n.crit = crit
    n.y = 0
    n:SetScale(1)
    n:SetAlpha(0)
    n:ClearAllPoints()
    n:SetPoint("BOTTOMLEFT", h.anchor, "CENTER", h.ax, h.ay)
    n:Show()
    table.insert(h.nums, 1, n)
    self.live[#self.live + 1] = n
    -- too many: the oldest goes now
    while #h.nums > maxN do
        local old = table.remove(h.nums)
        for j = #self.live, 1, -1 do if self.live[j] == old then table.remove(self.live, j) end end
        self:Free(old)
    end
    if not self.driver:IsShown() then self.driver:Show() end
    return n
end

function Cols:Step(driver, elapsed)
    local now = GetTime()
    local live = self.live
    for i = #live, 1, -1 do
        local n = live[i]
        local age = now - n.t0
        local h = n.holder
        if age >= n.life or not h then
            table.remove(live, i)
            if h then
                for j = #h.nums, 1, -1 do if h.nums[j] == n then table.remove(h.nums, j) end end
            end
            self:Free(n)
        else
            -- where it belongs in the column: above every newer number
            local want = 0
            for j = 1, #h.nums do
                local o = h.nums[j]
                if o == n then break end
                want = want + o.h
            end
            -- eased drift: quick to start, settling as it fades
            local p = age / n.life
            local ease = 1 - (1 - p) * (1 - p)
            want = want + n.rise * ease
            n.y = n.y + (want - n.y) * math_min(1, elapsed * 12)
            n:SetPoint("BOTTOMLEFT", h.anchor, "CENTER", h.ax + n.drift * ease, h.ay + n.y)
            local a = 1
            if n.fin > 0 and age < n.fin then a = age / n.fin
            elseif age > n.life - n.fout then a = (n.fout > 0) and (n.life - age) / n.fout or 0 end
            n:SetAlpha(a)
        end
    end
    if #live == 0 then driver:Hide() end
end

local cols = PT.NewColumns(nil, false)

local function Holder(unit, plate)
    local h = holders[unit]
    if h and h.plate == plate then return h end
    if not h then
        h = CreateFrame("Frame", nil, plate)
        h.nums = {}
        holders[unit] = h
    end
    h:SetParent(plate)
    h:SetFrameStrata("HIGH")
    h:SetAllPoints(plate)
    h.plate = plate
    h:Show()
    return h
end

function PT.DropPlate(unit)
    local h = holders[unit]
    if not h then return end
    cols:DropHolder(h)
    h:Hide()
end

local function Place(h)
    local anchor, x, y = Spot(h.plate, h)
    h.anchor, h.ax, h.ay = anchor, x, y
end

local function Add(unit, plate, text, size, r, g, b, crit, icon)
    local h = Holder(unit, plate)
    Place(h)
    return cols:Add(h, UnitIsUnit(unit, "target"), text, size, r, g, b, crit, icon)
end

-- How one hit looks: text, size and colour. kind: "white" (a swing),
-- "hit" (an ability), "dot", or the word for a miss ("Dodge", "Parry"...).
-- nil when that kind is switched off.
function PT.Look(kind, amount, crit)
    local c = PT.Cfg()
    local size = tonumber(c.size) or 13
    local critK = (tonumber(c.critScale) or 130) / 100
    if kind == "white" or kind == "hit" then
        local r, g, b
        if crit then r, g, b = KindColor("crit")
        elseif kind == "white" then r, g, b = KindColor("white")
        else r, g, b = KindColor("hit") end
        local sz = crit and size * critK or (kind == "white" and size * 0.85 or size)
        return Short(amount), sz, r, g, b
    elseif kind == "dot" then
        if not c.dots then return nil end
        local r, g, b = KindColor("dot")
        return Short(amount), size * 0.75, r, g, b
    end
    if not c.misses then return nil end
    -- a dodge is an Overpower: orange; the rest grey
    local r, g, b = KindColor(kind == "Dodge" and "dodge" or "miss")
    return tostring(kind), size * 0.85, r, g, b
end

-- ============================================================
-- THE HOOK - SCT_Events asks before it shows a hit you landed
-- ============================================================
-- kind: "white" (a swing), "hit" (an ability), "dot", or the word for a
-- miss ("Dodge", "Parry"...). true = drawn here, nothing else shows it.
function PT.Take(kind, guid, amount, crit, icon)
    if not plateOn then return false end
    local c = PT.Cfg()
    if not c.enabled or not guid then return false end
    local NP = ZuiPlates()
    if not NP ~= ownMap then
        -- ZacUI's plates were switched on or off since the last load
        ownMap = not NP
        if ownMap then Rebuild() else wipe(unitOf) end
    end
    local unit
    if NP then
        local f = NP.PlateByGUID(guid)
        unit = f and f.unit
    else
        unit = unitOf[guid]
    end
    if not unit then return false end
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if not (plate and plate:IsVisible()) then return false end
    if not c.others and not UnitIsUnit(unit, "target") then return false end
    crit = (kind == "white" or kind == "hit") and (crit and true or false) or false
    local text, size, r, g, b = PT.Look(kind, amount, crit)
    -- a kind switched off is still taken: it never scrolls instead
    if text then Add(unit, plate, text, size, r, g, b, crit, icon) end
    return true
end

-- The settings preview: a few numbers on the target's plate (or nothing
-- when there is no target plate up).
-- The four sample hits the test and the settings preview both show.
local tex = function(id) return GetSpellTexture and GetSpellTexture(id) or nil end
PT.SAMPLES = {
    { kind = "hit", amount = 1310, icon = 1680 },            -- Whirlwind
    { kind = "white", amount = 487 },
    { kind = "hit", amount = 4120, crit = true, icon = 23881 }, -- Bloodthirst
    { kind = "Dodge", icon = 11567 },                        -- Heroic Strike
}
function PT.SampleHit(i, into)
    local s = PT.SAMPLES[i]
    if not s then return end
    local text, size, r, g, b = PT.Look(s.kind, s.amount, s.crit)
    if not text then return end
    into(text, size, r, g, b, s.crit and true or false, s.icon and tex(s.icon) or nil)
end

-- On the target's plate (or nothing when there is no target plate up).
function PT.Test()
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target")
    if not plate then return false end
    -- keyed by the plate's own unit token (as real hits are), so the
    -- holder goes with the plate when it is removed
    local unit = plate.namePlateUnitToken or "target"
    for i = 1, #PT.SAMPLES do
        C_Timer.After((i - 1) * 0.25, function()
            PT.SampleHit(i, function(...) Add(unit, plate, ...) end)
        end)
    end
    return true
end
