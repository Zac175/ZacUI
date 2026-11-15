-- NP_Crosshair - ZacUI's host for the crosshair. The crosshair itself is
-- Crosshair_Core.lua, shared word for word with the standalone
-- ZacCrosshair addon; this file only tells it where ZacUI keeps the
-- settings (ZacUIDB.nameplates.crosshair), how to print, how Edit Mode
-- previews it, and how to read a ZacUI nameplate (the health bar and
-- what sticks out past it: target arrows, the name, the cast bar).
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME = ...
-- Zacui_Nameplates is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

local Core = _G.ZacCrosshairCore
if not Core then return end

-- shared state from earlier ZacUI files
local FLAT = ns.FLAT
local NP = ns.Nameplates
local Print = ns.Print

-- ============================================================
-- SETTINGS - ZacUIDB.nameplates.crosshair
-- ============================================================
-- Read on the range tick, every re-measure and by the plate arrows'
-- colour, so the defaults merge (Core.Normalize) runs once per settings
-- table - again after a profile switch, a reset or any settings change
-- (CH.Refresh, below).
local normalized

local function DB()
    if type(ZacUIDB) ~= "table" then return nil end
    local d = NP.DB()
    local c = d.crosshair
    if c ~= nil and c == normalized then return c end
    if type(c) ~= "table" then c = {} d.crosshair = c end
    normalized = Core.Normalize(c)
    return normalized
end

-- A ZacUI plate: the engine's health bar, and how far the visible extras
-- reach past it, in the bar's own units.
local function PlateInfo(plate)
    local z = plate._zuiNP
    if z and z:IsShown() and z.health and z.health:IsShown() then
        local l = (z.arrowL and z.arrowL:IsShown()) and (1 + (z.arrowL:GetWidth() or 0) * 0.4) or 0
        local r = (z.arrowR and z.arrowR:IsShown()) and (1 + (z.arrowR:GetWidth() or 0) * 0.4) or 0
        -- the corner brackets sit 2 outside the bar's edges
        if z._arrowsOn and (z._arrowStyle == "brackets" or z._arrowStyle == "box") then l, r = 3, 3 end
        -- a name inside the bar adds nothing above it
        local t = (z.name and z.name:IsShown() and not z.nameOnly and not z._nameInside
            and (z.name:GetText() or "") ~= "")
            and (2 + (z._iconOverhang or 0) + (z.name:GetStringHeight() or 12)) or 0
        -- the BT/WW row over the target's plate (HUD > Hesitation) while
        -- it is up; it re-measures the crosshair when it comes or goes
        local H = ns.Hesitation
        if H and H.PlateReach then t = math.max(t, H.PlateReach(plate, z)) end
        -- under the bar: the cast bar, the threat strip and its text, then
        -- the icon line - only what is up right now; the modules
        -- re-measure when that changes
        local b = (NP.UnderDrop and NP.UnderDrop(z)) or 0
        local D = NP.Debuffs
        local reach = (D and D.UnderReach and D.UnderReach(z)) or 0
        if reach > 0 then
            -- the icon row sits beside the threat strip (or under it)
            local top = z.dbUnderPad or ((NP.CastDrop and NP.CastDrop(z)) or 0)
            b = math.max(b, top + reach)
        end
        -- beside the bar: the Sunder count and anything else pinned to
        -- its sides, with a little air (the side lines stop short of it)
        if D and D.SideReach then
            local sl, sr = D.SideReach(z)
            if sl > 0 and sl + 3 > l then l = sl + 3 end
            if sr > 0 and sr + 3 > r then r = sr + 3 end
        end
        -- the box round the bar sits 2 + 1 outside it
        if z._arrowsOn and (z._arrowStyle == "box" or z._arrowStyle == "brackets") then
            if t < 3 then t = 3 end
            if b < 3 then b = 3 end
        end
        return z.health, l, r, t, b
    end
    return nil
end

local CH = Core.New({
    name = "ZacUICrosshair",
    DB = DB,
    Print = Print,
    FLAT = FLAT,
    ARROW = NP and NP.TEX_ARROW_CHEVRON or [[Interface\AddOns\ZacUI\Media\Textures\target_chevron]],
    OnColor = function(col) if NP and NP.TintTargetArrows then NP.TintTargetArrows(col) end end,
    IsEditMode = function() return ns.IsEditMode and ns.IsEditMode() end,
    WatchEditMode = ns.WatchEditMode,
    PlateInfo = PlateInfo,
    Misses = ns.Misses,
    CLEU = ns.CLEU,
})
CH.DEFAULTS = Core.DEFAULTS

-- a settings change: normalize the table again on the next read
local coreRefresh = CH.Refresh
function CH.Refresh()
    normalized = nil
    return coreRefresh()
end

NP.Crosshair = CH
-- shared with later ZacUI files
ns.Crosshair = CH
