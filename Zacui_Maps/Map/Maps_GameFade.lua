-- Maps_GameFade - two of the game's own map settings, as switches on the
-- Maps page (Look > "The game's own map"): the game's fade while you move
-- (its mapFade CVar, which no options panel of this client shows), and a
-- dim behind the maximized map (the game's BlackoutFrame).
-- Part of ZacUI; load order is set by the TOC (after Maps_Frame).
--
-- OFF BY DEFAULT: nothing is written until one is changed. ZacUI's map
-- already has a fade of its own (Look > "Fade while you are moving") and
-- already takes the black backing away, so the world shows behind the
-- big map in full; these are for the player who wants the game's fade
-- held one way, or some of the dim back.
--
-- THE CVAR goes through ZacUI's CVar helper (ns.CVar.Hold / Release):
-- the player's own value is recorded the first time and handed back when
-- the switch goes back to "as the game has it", when the Maps module is
-- off, or when ZacUI is uninstalled. A client without the CVar never sees
-- the setting. The world-map part holds the same CVar off while its own
-- fade runs; while it is loaded the setting is its, and this one says so.
--
-- COST: no events of its own; applied with the rest of the maps and on a
-- change; the dim is a texture colour set when the map shows.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local Maps = ns.Maps
if not (Maps and Maps.DB) then return end

local GF = {}
ns.MapsGameFade = GF

local OWNER = "maps"
local CVAR = "mapFade"
GF.DIM_DEFAULT = 0.2

-- ============================================================
-- SETTINGS (ZacUIDB.maps: gameFade "on" / "off" / nil, dimBehind,
-- dimAlpha) - read without writing
-- ============================================================
local function D()
    local d = ZacUIDB and ZacUIDB.maps
    return type(d) == "table" and d or {}
end
local function ModuleOn() return ZacUIDB and ZacUIDB.modules and ZacUIDB.modules.maps and true or false end

-- the client has the CVar at all
function GF.HasCVar()
    if ns.CVar and ns.CVar.Get then return ns.CVar.Get(CVAR) ~= nil end
    if GetCVar then
        local ok, v = pcall(GetCVar, CVAR)
        return ok and v ~= nil
    end
    return false
end
-- the world-map part holds the CVar itself while it runs
function GF.WorldMapOwns()
    return (ns.AddonLoaded and ns.AddonLoaded("Zacui_WorldMap")) and true or false
end
function GF.Mode()
    local m = D().gameFade
    if m == "on" or m == "off" then return m end
    return nil
end
function GF.DimOn() return D().dimBehind == true end
function GF.DimAlpha()
    local a = tonumber(D().dimAlpha) or GF.DIM_DEFAULT
    return math.max(0, math.min(1, a))
end

-- ============================================================
-- APPLYING
-- ============================================================
local holding = false
local function Hold(value)
    if ns.CVar and ns.CVar.Hold then
        ns.CVar.Hold(CVAR, value, OWNER)
    elseif SetCVar then
        -- (no helper on this core: remember the player's value ourselves)
        if GF._before == nil and GetCVar then GF._before = GetCVar(CVAR) end
        pcall(SetCVar, CVAR, value)
    end
    holding = true
end
-- (always asked of the helper: a hold from before a /reload is in its
-- record, not in this file's memory; a release with no hold does nothing)
local function Release()
    if ns.CVar and ns.CVar.Release then
        ns.CVar.Release(CVAR, OWNER)
    elseif SetCVar and GF._before ~= nil then
        pcall(SetCVar, CVAR, GF._before)
        GF._before = nil
    end
    holding = false
end
GF.Holding = function() return holding end

function GF.ApplyFade()
    local mode = ModuleOn() and GF.Mode() or nil
    if ns.FeatureOn and not ns.FeatureOn("maps_game_fade") then mode = nil end
    if not GF.HasCVar() or GF.WorldMapOwns() then mode = nil end
    if mode == "on" then Hold("1")
    elseif mode == "off" then Hold("0")
    else Release() end
end

-- the dim behind the maximized map: ZacUI's map takes the texture away
-- (Maps_Frame); with this on it comes back as plain black at the alpha
local function DimTexture()
    local map = _G.WorldMapFrame
    local bf = map and map.BlackoutFrame
    return bf and bf.Blackout, bf
end
function GF.ApplyDim()
    local tex = DimTexture()
    if not tex then return end
    if ModuleOn() and GF.DimOn() then
        if tex.SetColorTexture then
            tex:SetColorTexture(0, 0, 0, GF.DimAlpha())
        elseif tex.SetTexture then
            tex:SetTexture(0, 0, 0, GF.DimAlpha())
        end
        GF._dimmed = true
    elseif GF._dimmed then
        -- back to ZacUI's own: no backing at all
        if tex.SetTexture then tex:SetTexture(nil) end
        GF._dimmed = nil
    end
end

function GF.Apply()
    pcall(GF.ApplyFade)
    pcall(GF.ApplyDim)
end

-- with the rest of the maps (the module's apply, the map's first show)
local hooked = false
local function Hook()
    if hooked then return end
    local map = _G.WorldMapFrame
    if not (map and map.HookScript) then return end
    hooked = true
    -- (the game re-dresses the backing when the map changes size)
    map:HookScript("OnShow", function() if GF._dimmed or GF.DimOn() then pcall(GF.ApplyDim) end end)
end
if ns.Modules then
    local base = ns.Modules.maps
    if type(base) == "function" then
        ns.Modules.maps = function(...)
            base(...)
            Hook()
            GF.Apply()
        end
    end
end

-- ============================================================
-- THE PAGE: Maps > Look
-- ============================================================
GF.MODES = {
    { value = "keep", text = "As the game has it" },
    { value = "on", text = "Always fade" },
    { value = "off", text = "Never fade" },
}
local function ModeText(v)
    for _, m in ipairs(GF.MODES) do if m.value == v then return m.text end end
    return GF.MODES[1].text
end

if ns.AddPageTab then
    ns.AddPageTab("maps", "look", "Look", function(L)
        local UI = ns.UI
        local hasCVar = GF.HasCVar()
        if not (hasCVar or DimTexture() ~= nil) then return end
        L:Card("The game's own map")
        if hasCVar then
            if GF.WorldMapOwns() then
                L:Desc("The game's fade while you move: the world map part holds it off while its own fade runs "
                    .. "(World map > its fade setting).")
            else
                local dd = UI.Field(L.current, "The game's fade while you move", function(h)
                    return UI.Dropdown(h, { width = 200,
                        items = function() return GF.MODES end,
                        selectedValue = function() return GF.Mode() or "keep" end,
                        selected = function() return ModeText(GF.Mode() or "keep") end,
                        onSelect = function(v)
                            ZacUIDB.maps.gameFade = (v ~= "keep") and v or nil
                            GF.ApplyFade()
                        end })
                end, { width = 200 })
                L:Row(dd, 46)
                L:Desc("A separate fade from ZacUI's above: the game's own, which its options do not show. "
                    .. "\"As the game has it\" leaves it alone; the other two hold it, and your own setting comes "
                    .. "back when this is set back (or the Maps module is off).")
            end
        end
        if DimTexture() ~= nil then
            local on = UI.Checkbox(L.current, "Dim the world behind the maximized map", GF.DimOn(), function(v)
                ZacUIDB.maps.dimBehind = v or nil
                GF.ApplyDim()
                if ns.RefreshConfig then ns.RefreshConfig() end
            end, { tooltip = "ZacUI's map takes away the game's black backing, so the world shows in full behind "
                .. "the big map. Tick this to have some of it back." })
            L:Row(on, 17)
            local s = UI.Slider(L.current, { width = 220, min = 0, max = 100, step = 5,
                value = math.floor(GF.DimAlpha() * 100 + 0.5), label = "How dark",
                format = function(v) return v .. "%" end,
                onChange = function(v)
                    local a = v / 100
                    ZacUIDB.maps.dimAlpha = (math.abs(a - GF.DIM_DEFAULT) > 0.001) and a or nil
                    GF.ApplyDim()
                end })
            L:Dependent({ s }, GF.DimOn(), 1, nil, "Dim the world behind the maximized map")
        end
        L:EndCard()
    end)
end
if ns.AddMenuKeywords then
    ns.AddMenuKeywords("maps", "mapfade game fade moving blackout dim behind maximized big map")
end
