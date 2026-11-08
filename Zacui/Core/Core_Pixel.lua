-- Core_Pixel - edges that land on ONE PHYSICAL PIXEL, at any UI scale.
-- Part of ZacUI; load order is set by the TOC (after Core_Look, before the
-- UI framework, so every primitive can draw through it).
--
-- WHY. A border drawn SetHeight(1) is one UI unit tall, and one UI unit is
-- only one screen pixel when the UI scale happens to be 768 / screen
-- height. At 1440p and a 0.71 scale it is 1.33 pixels: the engine rounds
-- each strip to 1 or 2 pixels depending on where it sits, so a box's four
-- sides come out different widths and change as the frame moves. That is
-- the soft, uneven edge that reads "amateur" next to a pixel-perfect UI.
--
-- THE SUM. One physical pixel, in a frame's own units, is
--     (768 / physical screen height) / frame:GetEffectiveScale()
-- so a strip of exactly that height covers exactly one pixel row. The
-- engine's own pixel snapping is left ON for these strips on purpose: our
-- frames' positions are not all on the pixel grid, and a strip exactly one
-- pixel thick that is rounded at both edges stays exactly one pixel thick
-- wherever it lands (only a strip THINNER than a pixel can round to
-- nothing, and these never are).
--
-- WHEN. The ZacUI look only. Under the Classic, Blizzard and Forever looks
-- (and on a client or test stub with no GetPhysicalScreenSize) every call
-- here does exactly what the code did before: SetHeight(n) / SetWidth(n),
-- values unchanged. So those looks are byte-identical.
--
-- API
--   ns.Pixel.On()                 true while edges are pixel-exact
--   ns.Pixel.One(frame)           one physical pixel in frame's units (1 when off)
--   ns.Pixel.Snap(v, frame)       v rounded to whole physical pixels (v when off)
--   ns.Snap(v, frame)             the same
--   ns.Pixel.Size(f, w, h)        SetSize with both snapped
--   ns.Pixel.Edge(tex, side, owner, px)
--                                 a border strip: side "TOP"/"BOTTOM" sets its
--                                 height, "LEFT"/"RIGHT" its width, to px (1)
--                                 physical pixels measured on `owner` (default
--                                 the strip's parent). Remembered (weakly) and
--                                 re-measured after layout, on a UI scale or
--                                 resolution change, and on ns.Pixel.Resnap().
--   ns.Pixel.SetEdgeSize(tex, px) change a remembered strip's thickness
--   ns.Pixel.Border(frame, r, g, b, a, layer, sub, target)
--                                 four strips round `target` (default frame),
--                                 drawn on `frame`; returns the list (each strip
--                                 has ._zSide). Corners: top/bottom span the
--                                 width, left/right are inset by the strip so no
--                                 corner pixel is drawn twice (matters for alpha).
--   ns.Pixel.Resnap()             re-measure every remembered strip (soon, once)
--
-- Nothing here runs per frame: the measuring happens when a strip is made,
-- once on the next frame after, and on the rare events above.

local ADDON_NAME, ns = ...

local Pixel = {}
ns.Pixel = Pixel

local floor, max = math.floor, math.max
local IsSecret = function(v) return issecretvalue ~= nil and issecretvalue(v) end

-- ============================================================
-- THE PHYSICAL SCREEN
-- ============================================================
local perfect          -- one physical pixel in 768-space (nil: unknown)

local function RefreshPhysical()
    local f = _G.GetPhysicalScreenSize
    if type(f) ~= "function" then perfect = nil return end
    local ok, _, h = pcall(f)
    if ok and type(h) == "number" and not IsSecret(h) and h > 0 and h == h then
        perfect = 768 / h
    end
    -- (a 0 mid display-mode change keeps the last good answer)
end
RefreshPhysical()

local function Num(n)
    return type(n) == "number" and not IsSecret(n) and n == n and n ~= math.huge and n ~= -math.huge
end

-- The ZacUI look, read through the latched global look (Core_Look reads it
-- once a session; every change is reload-gated, so this never flips live).
function Pixel.On()
    if not perfect then return false end
    local L = ns.Look
    if L and L.Active and L.Active() ~= "zacui" then return false end
    return true
end

local function EffScale(frame)
    if frame and frame.GetEffectiveScale then
        local ok, es = pcall(frame.GetEffectiveScale, frame)
        if ok and Num(es) and es > 0.01 then return es end
    end
    local up = _G.UIParent
    if up and up.GetEffectiveScale then
        local ok, es = pcall(up.GetEffectiveScale, up)
        if ok and Num(es) and es > 0.01 then return es end
    end
    return 1
end

function Pixel.One(frame)
    if not Pixel.On() then return 1 end
    return perfect / EffScale(frame)
end

function Pixel.Snap(v, frame)
    if not Num(v) or v == 0 or not Pixel.On() then return v end
    local one = perfect / EffScale(frame)
    -- epsilon: a value sitting on a half pixel rounds the same way every time
    local px = floor(v / one + 0.5 + 0.001)
    if px == 0 and v ~= 0 then px = v > 0 and 1 or -1 end
    return px * one
end
ns.Snap = Pixel.Snap

function Pixel.Size(f, w, h)
    if not (f and f.SetSize) then return end
    f:SetSize(Pixel.Snap(w, f), Pixel.Snap(h or w, f))
end

-- ============================================================
-- STRIPS
-- ============================================================
-- tex -> { side, owner, px }   (weak: a strip that goes away is forgotten)
local strips = setmetatable({}, { __mode = "k" })
local fresh = {}                -- made since the last settle pass
local settleArmed = false

-- Only frames under UIParent: a nameplate (under WorldFrame) is scaled by
-- the camera distance after it is measured, and a strip measured at one
-- scale can fall under a pixel at another and vanish; plates keep their
-- one-unit edges (the nameplates' own polish handles them).
local underUI = setmetatable({}, { __mode = "k" })
local function UnderUIParent(f)
    if not f then return false end
    if underUI[f] then return true end
    local up, p, hops = _G.UIParent, f, 0
    local yes = false
    while p and hops < 40 do
        if p == up then yes = true break end
        p = p.GetParent and p:GetParent() or nil
        hops = hops + 1
    end
    -- (only a yes is kept: a frame made loose and parented later asks again)
    if yes then underUI[f] = true end
    return yes
end
Pixel.UnderUIParent = UnderUIParent

-- A HOLDER for the edges of a frame that is NOT under UIParent (a
-- nameplate's bars): a child frame that ignores its parents' scale (so its
-- own effective scale stays 1 whatever the camera does to the plate) laid
-- over the frame's rect by anchors. Strips drawn on it are a fixed number
-- of physical pixels while the plate grows and shrinks round them - the
-- plate's own scale never reaches their thickness. nil where the client
-- has no SetIgnoreParentScale or pixel mode is off (the caller then draws
-- on the frame itself, as before).
local holders = setmetatable({}, { __mode = "k" })
local holderOf = setmetatable({}, { __mode = "k" })
function Pixel.Holder(frame)
    if not (frame and Pixel.On()) then return nil end
    local h = holderOf[frame]
    if h then return h end
    if not (CreateFrame and frame.GetFrameLevel) then return nil end
    local ok, c = pcall(CreateFrame, "Frame", nil, frame)
    if not (ok and c and c.SetIgnoreParentScale) then return nil end
    c:SetIgnoreParentScale(true)
    c:SetScale(1)
    c:SetAllPoints(frame)
    c:SetFrameLevel(frame:GetFrameLevel() + 1)
    holders[c] = true
    holderOf[frame] = c
    return c
end

local function Measure(tex, e)
    local px = e.px or 1
    local t
    local owner = e.owner or (tex.GetParent and tex:GetParent())
    if Pixel.On() and (holders[owner] or UnderUIParent(owner)) then
        t = (px <= 0) and 0 or max(1, floor(px + 0.5)) * (perfect / EffScale(owner))
    else
        t = px
    end
    if e.side == "TOP" or e.side == "BOTTOM" then
        tex:SetHeight(t)
    else
        tex:SetWidth(t)
    end
end

local function SettleFresh()
    settleArmed = false
    local list = fresh
    fresh = {}
    for i = 1, #list do
        local tex = list[i]
        local e = strips[tex]
        if e then pcall(Measure, tex, e) end
    end
end

local function ArmSettle()
    if settleArmed then return end
    if not (C_Timer and C_Timer.After) then return end
    settleArmed = true
    -- the next frame: the strip's frame has its parent and scale by then
    C_Timer.After(0, SettleFresh)
end

function Pixel.Edge(tex, side, owner, px)
    if not (tex and tex.SetHeight) then return tex end
    local e = strips[tex]
    if not e then
        e = {}
        strips[tex] = e
    end
    e.side, e.owner, e.px = side, owner or e.owner, px or e.px or 1
    Measure(tex, e)
    if Pixel.On() then
        fresh[#fresh + 1] = tex
        ArmSettle()
        Pixel.Watch()
    end
    return tex
end

-- true when the strip is one of ours (remembered by Edge) and was resized
function Pixel.SetEdgeSize(tex, px)
    local e = tex and strips[tex]
    if not e then return false end
    e.px = px or 1
    Measure(tex, e)
    return true
end

local resnapArmed = false
local function ResnapNow()
    resnapArmed = false
    RefreshPhysical()
    for tex, e in pairs(strips) do pcall(Measure, tex, e) end
end
function Pixel.Resnap()
    if resnapArmed then return end
    if not (C_Timer and C_Timer.After) then ResnapNow() return end
    resnapArmed = true
    C_Timer.After(0, ResnapNow)
end

-- the four strips round `target`, drawn on `frame`
function Pixel.Border(frame, r, g, b, a, layer, sub, target)
    if not (frame and frame.CreateTexture) then return nil end
    target = target or frame
    local list = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = frame:CreateTexture(nil, layer or "OVERLAY", nil, sub or 7)
        t._zui_own = true
        t._zSide = side
        t:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT", target, side .. "LEFT", 0, 0)
            t:SetPoint(side .. "RIGHT", target, side .. "RIGHT", 0, 0)
        else
            t:SetPoint("TOP" .. side, target, "TOP" .. side, 0, 0)
            t:SetPoint("BOTTOM" .. side, target, "BOTTOM" .. side, 0, 0)
        end
        Pixel.Edge(t, side, target)
        list[#list + 1] = t
    end
    return list
end

-- ============================================================
-- WHEN THE PIXEL GRID MOVES
-- ============================================================
-- UI_SCALE_CHANGED: the UI scale slider; DISPLAY_SIZE_CHANGED: the
-- resolution; PLAYER_ENTERING_WORLD: once, after everything first laid
-- out (the scale CVar is applied by then). The watcher is made with the
-- first pixel-exact strip, so under any other look nothing is made at all.
local watching = false
function Pixel.Watch()
    if watching or not CreateFrame then return end
    watching = true
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("UI_SCALE_CHANGED")
    pcall(f.RegisterEvent, f, "DISPLAY_SIZE_CHANGED")
    f:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_ENTERING_WORLD" then
            self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        end
        Pixel.Resnap()
    end)
    -- a settings change can rescale a part (its own Scale slider)
    if ns.OnSettingsChanged then
        ns.OnSettingsChanged(function() Pixel.Resnap() end)
    end
end

-- ============================================================
-- HD CLASS ICONS
-- ============================================================
-- ns.ClassIcon(tex, classFile[, zoom]) puts a class's icon on `tex` from
-- the client's own art: the modern "classicon-<class>" atlas where the
-- client has it (Forever, Retail), else the character-create class sheet
-- every Classic client ships, cut by CLASS_ICON_TCOORDS (the client's own
-- table; a copy of its numbers below for a client without it) and cropped
-- by `zoom` (0.06 of each cell edge: the sheet's bevel off, the art kept).
-- Returns true when it drew one. Nothing third-party, nothing shipped.
local CLASS_SHEET = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local SHEET_COORDS = {
    WARRIOR = { 0, 0.25, 0, 0.25 },     MAGE = { 0.25, 0.49609375, 0, 0.25 },
    ROGUE = { 0.49609375, 0.7421875, 0, 0.25 }, DRUID = { 0.7421875, 0.98828125, 0, 0.25 },
    HUNTER = { 0, 0.25, 0.25, 0.5 },    SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
    PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 },
    PALADIN = { 0, 0.25, 0.5, 0.75 },
}
local atlasOK = {}
local function HasAtlas(name)
    local v = atlasOK[name]
    if v ~= nil then return v end
    local info = C_Texture and C_Texture.GetAtlasInfo
    v = false
    if info then
        local ok, r = pcall(info, name)
        v = ok and r ~= nil or false
    end
    atlasOK[name] = v
    return v
end
function ns.ClassIcon(tex, classFile, zoom)
    if not (tex and tex.SetTexture and type(classFile) == "string") then return false end
    if issecretvalue and issecretvalue(classFile) then return false end
    local cf = classFile:upper()
    local atlas = "classicon-" .. cf:lower()
    if tex.SetAtlas and HasAtlas(atlas) then
        tex:SetAtlas(atlas)
        local z = zoom or 0.06
        tex:SetTexCoord(z, 1 - z, z, 1 - z)
        return true
    end
    local c = (_G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[cf]) or SHEET_COORDS[cf]
    if not c then return false end
    tex:SetTexture(CLASS_SHEET)
    local z = zoom or 0.06
    local w, h = c[2] - c[1], c[4] - c[3]
    tex:SetTexCoord(c[1] + w * z, c[2] - w * z, c[3] + h * z, c[4] - h * z)
    return true
end
