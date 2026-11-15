-- AE_Groups - groups and dynamic groups.
-- Part of ZacUI (Zacui_Auras). Written for ZacUI.
--
-- A group is a frame its children hang from: move the group and they all
-- move. A dynamic group also lays its showing children out itself - in a
-- row (left, right, up, down, centred), a grid, a circle either way, or by
-- its own code - sorted (in order, by time left, marked-first, by code),
-- limited, and (anchored per unit) one cluster on each unit's raid frame
-- or nameplate. The layout follows the WeakAuras format's rules: each
-- child's point (the group's selfPoint) sits at an offset from the group's
-- same point, and that offset is what the grow rule works out.
--
-- Custom sort / grow / anchor code sees what the format gives it:
-- regionData = { region, data, id, cloneId, dataIndex, dimensions }.
local ns = _G.ZacUI
if not ns then return end
local E = ns.AuraEngine
if not E then return end

local Gp = {}
E.Groups = Gp
local R = E.Regions
local Color = E.Color
local min, max, abs = math.min, math.max, math.abs

local groups = {}           -- id -> group object
Gp.list = groups

local function V(d, k) return R.Value(d, k) end
local function N(d, k, def) return tonumber(V(d, k)) or def or 0 end

-- ============================================================
-- THE GROUP FRAME
-- ============================================================
function Gp.Get(id)
    local g = groups[id]
    if g then return g end
    local d = E.data[id]
    if not (d and E.IsGroup(d)) then return nil end
    g = { id = id, d = d, dynamic = d.regionType == "dynamicgroup", members = {}, dirty = false }
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(1, 1)
    g.frame = f
    g.border = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    g.border:Hide()
    groups[id] = g
    Gp.Modify(g)
    return g
end

local function GroupPoint(d)
    if d.regionType == "group" then
        return (type(d.information) == "table" and d.information.groupOffset) and "BOTTOMLEFT" or "CENTER"
    end
    return d.selfPoint or "TOP"
end
Gp.GroupPoint = GroupPoint

function Gp.Modify(g)
    local d, f = g.d, g.frame
    local strata = R.Strata(d.frameStrata)
    if strata then f:SetFrameStrata(strata) end
    f:SetAlpha(N(d, "alpha", 1))
    local sc = N(d, "scale", 1)
    f:SetScale((sc > 0 and sc <= 10) and sc or 1)
    f:ClearAllPoints()
    local point = GroupPoint(d)
    local parent = d.parent and E.data[d.parent] and Gp.Get(d.parent)
    if parent then
        f:SetParent(parent.frame)
        f:SetPoint(point, parent.frame, d.anchorPoint or "CENTER", N(d, "xOffset"), N(d, "yOffset"))
        g.parent = parent
    else
        local frame = R.AnchorFrame(f, d, nil) or UIParent
        f:SetParent(UIParent)
        f:SetPoint(point, frame, d.anchorPoint or "CENTER", N(d, "xOffset"), N(d, "yOffset"))
    end
    f:Show()
    g.border:Hide()
end

-- a child region joins (it hangs from the group from now on)
function Gp.Join(groupId, region)
    local g = Gp.Get(groupId)
    if not g then return end
    region.group = g
    region.groupFrame = g.frame
    region:SetParent(g.frame)
    g.members[region] = true
    if not g.dynamic then
        R.Place(region, region.baseD or region.d, region.state)
    end
end

-- a member shown or hidden: the group lays out again next frame
local pending = {}
local layout = CreateFrame("Frame")
layout:Hide()
function Gp.Changed(region)
    local g = region.group
    if not g then return end
    if g.dynamic or V(g.d, "border") then
        pending[g] = true
        layout:Show()
    end
end

-- ============================================================
-- SORTING (comparators that may answer "no opinion": nil)
-- ============================================================
local function AscendingValues(a, b)
    -- nil first, then by value; mixed types by type name
    if a == nil and b == nil then return nil end
    if a == nil then return true end
    if b == nil then return false end
    if a == b then return nil end
    if type(a) ~= type(b) then return type(a) > type(b) end
    if type(a) == "number" then
        if abs(b - a) < 0.001 then return nil end
        return a < b
    elseif type(a) == "string" then
        return a < b
    end
    return nil
end

local function Path(rd, path)
    local v = rd
    for _, k in ipairs(path) do
        if type(v) ~= "table" then return nil end
        v = v[k]
    end
    return v
end

local function Ascending(path) return function(a, b) return AscendingValues(Path(a, path), Path(b, path)) end end
local function Descending(path)
    local asc = Ascending(path)
    return function(a, b)
        local r = asc(a, b)
        if r == nil then return nil end
        return not r
    end
end
local function Chain(...)
    local list = { ... }
    return function(a, b)
        for _, fn in ipairs(list) do
            local r = fn(a, b)
            if r ~= nil then return r end
        end
        return nil
    end
end

local SORTERS = {}
SORTERS.none = function()
    return Chain(Ascending({ "dataIndex" }), Ascending({ "region", "state", "index" }))
end
SORTERS.ascending = function()
    return Chain(Ascending({ "region", "state", "expirationTime" }), Ascending({ "dataIndex" }))
end
SORTERS.descending = function()
    return Chain(Descending({ "region", "state", "expirationTime" }), Ascending({ "dataIndex" }))
end
SORTERS.hybrid = function(g)
    local d = g.d
    local marked = type(d.sortHybridTable) == "table" and d.sortHybridTable or {}
    local first = d.hybridPosition ~= "hybridLast"
    local byTime = d.hybridSortMode == "descending" and Descending({ "region", "state", "expirationTime" })
        or Ascending({ "region", "state", "expirationTime" })
    return Chain(function(a, b)
        local ma, mb = marked[a.id], marked[b.id]
        if ma and not mb then return first end
        if mb and not ma then return not first end
        return nil
    end, byTime, Ascending({ "dataIndex" }))
end
SORTERS.custom = function(g)
    if not g.customSort then return SORTERS.none() end
    return function(a, b)
        local ok, res = pcall(g.customSort, a, b)
        if ok then return res end
        E.Error(g.id, "custom sort", res)
        return nil
    end
end
Gp.SORTERS = SORTERS

-- ============================================================
-- GROWING: where each showing child goes (x, y from the group's point)
-- ============================================================
-- which way the stagger leans for the alignment
local function Lean(align, stagger)
    if align == "LEFT" then return stagger < 0 and 1 or 0 end
    if align == "RIGHT" then return stagger > 0 and 1 or 0 end
    return 0.5
end

-- the order a centred row is filled in
local CENTER_FIRST = {
    LR = function(n) return n > 0 and 1 or nil end,
    RL = function(n) return n > 0 and n or nil end,
    CLR = function(n) if n >= 3 then return n - n % 2 end return n > 0 and n or nil end,
    CRL = function(n) if n % 2 == 1 then return n end return n > 0 and n - 1 or nil end,
}
local CENTER_NEXT = {
    LR = function(i, n) i = i + 1 return i <= n and i or nil end,
    RL = function(i, n) i = i - 1 return i > 0 and i or nil end,
    CLR = function(i, n)
        if i % 2 == 0 then i = i - 2 if i == 0 then i = 1 end else i = i + 2 end
        return i <= n and i or nil
    end,
    CRL = function(i, n)
        if i % 2 == 1 then i = i - 2 if i == -1 then i = 2 end else i = i + 2 end
        return i <= n and i or nil
    end,
}

local function Dim(rd, which) return tonumber(rd.dimensions and rd.dimensions[which]) or 0 end

local function Limit(d) return d.useLimit and (tonumber(d.limit) or math.huge) or math.huge end

local GROWERS = {}
GROWERS.LEFT = function(d, list, out)
    local stagger, space = -(tonumber(d.stagger) or 0), tonumber(d.space) or 0
    local n = min(Limit(d), #list)
    local x, y = 0, (n - 1) * stagger * Lean(d.align, tonumber(d.stagger) or 0)
    for i = 1, n do
        out[list[i]] = { x, y, true }
        x = x - Dim(list[i], "width") - space
        y = y - stagger
    end
end
GROWERS.RIGHT = function(d, list, out)
    local stagger, space = tonumber(d.stagger) or 0, tonumber(d.space) or 0
    local n = min(Limit(d), #list)
    local x, y = 0, -(n - 1) * stagger * (1 - Lean(d.align, stagger))
    for i = 1, n do
        out[list[i]] = { x, y, true }
        x = x + Dim(list[i], "width") + space
        y = y + stagger
    end
end
GROWERS.UP = function(d, list, out)
    local stagger, space = tonumber(d.stagger) or 0, tonumber(d.space) or 0
    local n = min(Limit(d), #list)
    local x, y = -(n - 1) * stagger * (1 - Lean(d.align, stagger)), 0
    for i = 1, n do
        out[list[i]] = { x, y, true }
        x = x + stagger
        y = y + Dim(list[i], "height") + space
    end
end
GROWERS.DOWN = function(d, list, out)
    local stagger, space = tonumber(d.stagger) or 0, tonumber(d.space) or 0
    local n = min(Limit(d), #list)
    local x, y = -(n - 1) * stagger * Lean(d.align, stagger), 0
    for i = 1, n do
        out[list[i]] = { x, y, true }
        x = x + stagger
        y = y - Dim(list[i], "height") - space
    end
end
local function Centered(d, list, out, horizontal)
    local stagger, space = tonumber(d.stagger) or 0, tonumber(d.space) or 0
    if not horizontal then stagger = -stagger end
    local n = min(Limit(d), #list)
    local dim = horizontal and "width" or "height"
    local total = (n - 1) * space
    for i = 1, n do total = total + Dim(list[i], dim) end
    local x, y
    if horizontal then x, y = -total / 2, -(stagger * (n - 1) / 2) else x, y = -(stagger * (n - 1) / 2), -total / 2 end
    local ct = CENTER_FIRST[d.centerType] and d.centerType or "LR"
    local i = CENTER_FIRST[ct](n)
    while i do
        local rd = list[i]
        if horizontal then
            x = x + Dim(rd, "width") / 2
            out[rd] = { x, y, true }
            x = x + Dim(rd, "width") / 2 + space
            y = y + stagger
        else
            y = y + Dim(rd, "height") / 2
            out[rd] = { x, y, true }
            x = x + stagger
            y = y + Dim(rd, "height") / 2 + space
        end
        i = CENTER_NEXT[ct](i, n)
    end
end
GROWERS.HORIZONTAL = function(d, list, out) Centered(d, list, out, true) end
GROWERS.VERTICAL = function(d, list, out) Centered(d, list, out, false) end
local function Round(d, list, out, sign)
    local n = min(Limit(d), #list)
    local cf = d.constantFactor or "RADIUS"
    local space = tonumber(d.space) or 0
    local r
    if cf == "RADIUS" or cf == "ANGLE" then r = tonumber(d.radius) or 0
    else r = n <= 1 and 0 or (n * space) / (2 * math.pi) end
    local theta = math.rad(tonumber(d.rotation) or 0)
    local arc = math.rad(d.fullCircle and 360 or (tonumber(d.arcLength) or 0))
    local step
    if n == 1 then step = 0
    elseif cf == "ANGLE" then step = math.rad(tonumber(d.stepAngle) or 0)
    elseif not d.fullCircle then step = arc / (n - 1)
    else step = arc / n end
    step = step * sign
    for i = 1, n do
        out[list[i]] = { r * math.cos(theta), r * math.sin(theta), true }
        theta = theta + step
    end
end
GROWERS.CIRCLE = function(d, list, out) Round(d, list, out, 1) end
GROWERS.COUNTERCIRCLE = function(d, list, out) Round(d, list, out, -1) end
GROWERS.GRID = function(d, list, out)
    local gt = d.gridType or "RD"
    local per = math.max(1, tonumber(d.gridWidth) or 5)
    local rowFirst = gt:find("^[RLH]") ~= nil
    local rowMul = gt:find("D") and -1 or 1
    local colMul = gt:find("L") and -1 or 1
    local p1h, p1v = gt:sub(1, 1) == "H", gt:sub(1, 1) == "V"
    local p2h, p2v = gt:sub(2, 2) == "H", gt:sub(2, 2) == "V"
    local primary = { dim = "width", coord = 1, mul = colMul, space = tonumber(d.columnSpace) or 1, cur = 0 }
    local secondary = { dim = "height", coord = 2, mul = rowMul, space = tonumber(d.rowSpace) or 1, cur = 0, big = 0 }
    if not rowFirst then primary, secondary = secondary, primary secondary.big = 0 end
    local n = min(Limit(d), #list)
    local lineStart, lx0, lx1, ly0, ly1
    local tx0, tx1, ty0, ty1
    local function CentreLine(last)
        if not lineStart then return end
        local ox, oy = (lx1 - lx0) / 2, (ly1 - ly0) / 2
        for j = lineStart, last do
            local p = out[list[j]]
            if p1h then p[1] = p[1] - ox end
            if p1v then p[2] = p[2] - oy end
        end
    end
    for i = 1, n do
        local rd = list[i]
        local pos = { [primary.coord] = primary.cur, [secondary.coord] = secondary.cur, [3] = true }
        out[rd] = pos
        local x, y = pos[1], pos[2]
        if not lineStart then lineStart, lx0, lx1, ly0, ly1 = i, x, x, y, y
        else lx0, lx1, ly0, ly1 = min(lx0, x), max(lx1, x), min(ly0, y), max(ly1, y) end
        if not tx0 then tx0, tx1, ty0, ty1 = x, x, y, y
        else tx0, tx1, ty0, ty1 = min(tx0, x), max(tx1, x), min(ty0, y), max(ty1, y) end
        secondary.big = max(secondary.big or 0, Dim(rd, secondary.dim))
        if i % per == 0 then
            if p1h or p1v then CentreLine(i) end
            primary.cur = 0
            secondary.cur = secondary.cur + (secondary.space + secondary.big) * secondary.mul
            secondary.big = 0
            lineStart = nil
        else
            primary.cur = primary.cur + (primary.space + Dim(rd, primary.dim)) * primary.mul
        end
    end
    if (p1h or p1v) and lineStart then CentreLine(n) end
    if (p2h or p2v) and tx0 then
        local ox, oy = (tx1 - tx0) / 2, (ty1 - ty0) / 2
        for j = 1, n do
            local p = out[list[j]]
            if p2h then p[1] = p[1] - ox end
            if p2v then p[2] = p[2] - oy end
        end
    end
end
Gp.GROWERS = GROWERS

-- ============================================================
-- WHO IS SHOWING, IN WHAT ORDER
-- ============================================================
local function Members(g)
    local index = {}
    for i, child in ipairs(E.children[g.id] or {}) do index[child] = i end
    local list = {}
    for region in pairs(g.members) do
        local live = E.regions[region.id] == region or (E.clones[region.id] and E.clones[region.id][region.cloneId] == region)
        if not live then
            g.members[region] = nil
        elseif (region:IsShown() or region.showing) and not region.finishing or region.previewing then
            local d = region.baseD or region.d
            local dims = d.regionType == "text" and region or { width = (region.width or 0) * abs(region.scalex or 1),
                height = (region.height or 0) * abs(region.scaley or 1) }
            list[#list + 1] = { region = region, data = d, id = region.id, cloneId = region.cloneId or "",
                dataIndex = index[region.id] or 0, dimensions = dims, parent = g.frame }
        end
    end
    local cmp = (SORTERS[g.d.sort] or SORTERS.none)(g)
    table.sort(list, function(a, b)
        local r = cmp(a, b)
        if r == nil then
            -- a steady order for ties: list position, then clone id
            if a.dataIndex ~= b.dataIndex then return a.dataIndex < b.dataIndex end
            return tostring(a.cloneId) < tostring(b.cloneId)
        end
        return r and true or false
    end)
    return list
end

-- the frame a member's unit cluster hangs from
local function UnitFrameOf(g, region)
    local st = region.state
    if not (st and st.unit) then return nil end
    if g.d.anchorPerUnit == "NAMEPLATE" then
        return C_NamePlate and C_NamePlate.GetNamePlateForUnit(st.unit) or nil
    end
    return E.UnitFrame and E.UnitFrame(st.unit) or nil
end

-- members split by the frame they hang from ("" = the group itself)
local function ByFrame(g, list)
    local d = g.d
    local frames = {}
    if not d.useAnchorPerUnit then
        frames[""] = list
        return frames
    end
    if d.anchorPerUnit == "CUSTOM" and g.customAnchor then
        local ok, err = pcall(g.customAnchor, frames, list)
        if not ok then E.Error(g.id, "custom anchor", err) end
        return frames
    end
    for _, rd in ipairs(list) do
        local f = UnitFrameOf(g, rd.region)
        if f then
            frames[f] = frames[f] or {}
            table.insert(frames[f], rd)
        end
    end
    return frames
end

-- ============================================================
-- LAYOUT
-- ============================================================
local slides = {}         -- region -> { from x, from y, start }
local slider = CreateFrame("Frame")
slider:Hide()

local function PlaceChild(g, rd, frame, x, y, show)
    local d, r = g.d, rd.region
    local point = GroupPoint(d)
    local cd = r.baseD or r.d
    local cx, cy = tonumber(cd.xOffset) or 0, tonumber(cd.yOffset) or 0
    local target, relPoint
    if frame == "" then
        target, relPoint = g.frame, point
        r:SetParent(g.frame)
    else
        target = type(frame) == "string" and _G[frame] or frame
        relPoint = d.anchorPoint or "CENTER"
        x, y = x + (tonumber(d.xOffset) or 0), y + (tonumber(d.yOffset) or 0)
        if type(target) == "table" and target.GetObjectType and d.anchorFrameParent ~= false then
            r:SetParent(target)
            if target.GetFrameStrata then r:SetFrameStrata(target:GetFrameStrata()) end
            if target.GetFrameLevel then r:SetFrameLevel(target:GetFrameLevel() + 10) end
        end
    end
    if not (type(target) == "table" and target.GetObjectType) then
        r:SetGroupHidden(true)
        return
    end
    local strata = R.Strata(cd.frameStrata)
    if strata then r:SetFrameStrata(strata) elseif frame == "" and g.frame.GetFrameStrata then r:SetFrameStrata(g.frame:GetFrameStrata()) end
    local nx, ny = x + cx, y + cy
    local prev = r.groupSpot
    if V(d, "animate") and prev and show and prev[3] == target and (abs(prev[1] - nx) > 0.01 or abs(prev[2] - ny) > 0.01) then
        slides[r] = { prev[1], prev[2], nx, ny, GetTime(), point, target, relPoint }
        slider:Show()
    else
        slides[r] = nil
        R.SetAnchor(r, point, target, relPoint, nx, ny)
    end
    r.groupSpot = { nx, ny, target }
    r:SetGroupHidden(not show)
end

slider:SetScript("OnUpdate", function(self)
    local now, any = GetTime(), false
    for r, s in pairs(slides) do
        local t = math.min(1, (now - s[5]) / 0.2)
        R.SetAnchor(r, s[6], s[7], s[8], s[1] + (s[3] - s[1]) * t, s[2] + (s[4] - s[2]) * t)
        if t >= 1 then slides[r] = nil else any = true end
    end
    if not any then self:Hide() end
end)

-- the box round the shown children, and the group's border over it
local function Border(g, boxes)
    local d, b = g.d, g.border
    if not V(d, "border") or d.useAnchorPerUnit or not b.SetBackdrop or #boxes == 0 then
        b:Hide()
        return
    end
    local x0, y0, x1, y1
    for _, bx in ipairs(boxes) do
        x0, y0 = x0 and min(x0, bx[1]) or bx[1], y0 and min(y0, bx[2]) or bx[2]
        x1, y1 = x1 and max(x1, bx[3]) or bx[3], y1 and max(y1, bx[4]) or bx[4]
    end
    local off = N(d, "borderOffset", 4)
    local inset = N(d, "borderInset", 1)
    b:ClearAllPoints()
    b:SetPoint("BOTTOMLEFT", g.frame, "CENTER", x0 - off, y0 - off)
    b:SetPoint("TOPRIGHT", g.frame, "CENTER", x1 + off, y1 + off)
    b:SetBackdrop({ edgeFile = R.Border(V(d, "borderEdge")), edgeSize = N(d, "borderSize", 2),
        bgFile = R.Background(V(d, "borderBackdrop")), insets = { left = inset, right = inset, top = inset, bottom = inset } })
    b:SetBackdropBorderColor(Color(V(d, "borderColor")))
    b:SetBackdropColor(Color(V(d, "backdropColor")))
    b:Show()
end

-- a child's box from its point and size, relative to the group's centre
local function Box(point, x, y, w, h)
    local x0, y0
    if point:find("LEFT") then x0 = x elseif point:find("RIGHT") then x0 = x - w else x0 = x - w / 2 end
    if point:find("BOTTOM") then y0 = y elseif point:find("TOP") then y0 = y - h else y0 = y - h / 2 end
    return { x0, y0, x0 + w, y0 + h }
end

function Gp.Layout(g)
    local d = g.d
    if not g.dynamic then
        -- a plain group only draws its border round what shows
        local boxes = {}
        for r in pairs(g.members) do
            if r:IsShown() or r.showing then
                local cd = r.baseD or r.d
                boxes[#boxes + 1] = Box(cd.selfPoint or "CENTER", tonumber(cd.xOffset) or 0, tonumber(cd.yOffset) or 0,
                    r.width or 0, r.height or 0)
            end
        end
        Border(g, boxes)
        return
    end
    local list = Members(g)
    local placed = {}
    local positions = {}
    local grow = d.grow or "DOWN"
    local boxes = {}
    local point = GroupPoint(d)
    if grow == "CUSTOM" then
        if g.customGrow then
            local ok, err = pcall(g.customGrow, positions, list)
            if not ok then
                E.Error(g.id, "custom grow", err)
                positions = {}
            end
        end
        -- a list by position means "the sorted children, in order"
        if #positions > 0 then
            local keyed = {}
            for i, p in ipairs(positions) do if list[i] then keyed[list[i]] = p end end
            positions = { [""] = keyed }
        else
            local perFrame = false
            for k, v in pairs(positions) do
                if type(k) ~= "table" or k.region == nil then perFrame = true end
                break
            end
            if not perFrame then positions = { [""] = positions } end
        end
    else
        local grower = GROWERS[grow] or GROWERS.DOWN
        for frame, members in pairs(ByFrame(g, list)) do
            local out = {}
            grower(d, members, out)
            positions[frame] = out
        end
    end
    for frame, out in pairs(positions) do
        if type(out) == "table" then
            for rd, p in pairs(out) do
                if type(rd) == "table" and rd.region and type(p) == "table" then
                    local x = type(p[1]) == "number" and p[1] or 0
                    local y = type(p[2]) == "number" and p[2] or 0
                    local show = p[3] ~= false
                    PlaceChild(g, rd, frame, x, y, show)
                    placed[rd.region] = true
                    if show and frame == "" then
                        local w, h = Dim(rd, "width"), Dim(rd, "height")
                        boxes[#boxes + 1] = Box(point, x, y, w, h)
                    end
                end
            end
        end
    end
    -- shown but given no place (beyond the limit, no unit frame): hidden
    for _, rd in ipairs(list) do
        if not placed[rd.region] then rd.region:SetGroupHidden(true) end
    end
    Border(g, boxes)
end

layout:SetScript("OnUpdate", function(self)
    self:Hide()
    for g in pairs(pending) do
        pending[g] = nil
        local ok, err = pcall(Gp.Layout, g)
        if not ok then E.Error(g.id, "group layout", err) end
    end
end)

-- dynamic groups' custom sort / grow / anchor functions
function Gp.Compile(g)
    local d = g.d
    g.customSort, g.customGrow, g.customAnchor = nil, nil, nil
    if d.sort == "custom" and d.customSort then g.customSort = E.Env.Function(g.id, d.customSort, "custom sort") end
    if d.grow == "CUSTOM" and d.customGrow then g.customGrow = E.Env.Function(g.id, d.customGrow, "custom grow") end
    if d.useAnchorPerUnit and d.anchorPerUnit == "CUSTOM" and d.customAnchorPerUnit then
        g.customAnchor = E.Env.Function(g.id, d.customAnchorPerUnit, "custom anchor")
    end
end

-- every unit's frame moved (raid frames rebuilt, a plate came or went)
function Gp.RelayoutUnits()
    for _, g in pairs(groups) do
        if g.dynamic and g.d.useAnchorPerUnit then
            pending[g] = true
            layout:Show()
        end
    end
end
E.On("NAME_PLATE_UNIT_ADDED", "groups.plates", Gp.RelayoutUnits)
E.On("NAME_PLATE_UNIT_REMOVED", "groups.plates", Gp.RelayoutUnits)
E.On("GROUP_ROSTER_UPDATE", "groups.roster", function() C_Timer.After(0.2, Gp.RelayoutUnits) end)

-- a custom sort or grow that asked to run again on its own events
-- (sortOn / growOn / anchorOn, comma separated)
local function Watch(g)
    local d = g.d
    for _, key in ipairs({ "sortOn", "growOn", "anchorOn" }) do
        local s = d[key]
        if type(s) == "string" then
            for ev in s:gmatch("[%w_]+") do
                if ev ~= "changed" then
                    E.On(ev, "groups.watch." .. g.id, function()
                        pending[g] = true
                        layout:Show()
                    end)
                end
            end
        end
    end
end
local Compile = Gp.Compile
Gp.Compile = function(g)
    Compile(g)
    pcall(Watch, g)
end
