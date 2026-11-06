-- ============================================================================
-- ZacUF - Media.lua
-- Resolves LibSharedMedia names to real file paths. LSM is OPTIONAL and never
-- bundled: if present (standalone or embedded by any addon via LibStub) we use
-- it, so the font/texture lists grow with whatever SharedMedia is installed.
-- If absent, a small set of always-present Blizzard files plus the textures
-- shipped in ZacUF\Media are exposed under friendly names.
--
-- The bundled textures below are the ones copied into ZacUF\Media (smooth,
-- flat, minimalist, normTex). They are registered into LSM too, so they show
-- up in every SharedMedia-aware addon's pickers as well.
-- ============================================================================
local ADDON, ns = ...

ns.Media = {}
local M = ns.Media

local PATH = "Interface\\AddOns\\Zacui_UnitFrames\\Media\\"

-- Statusbar textures under friendly names (friendly name -> file). Only
-- normTex ships in the Media folder; the smooth / flat / minimalist files
-- never made the move from ZacUF, and the game (through SharedMedia)
-- complains about a name that points at no file. So those three names
-- point at textures that exist: a saved "Minimalist" or "Flat" bar draws
-- as a flat fill, "Smooth" as the gradient.
local BUNDLED_BAR = {
    ["Smooth"]          = PATH .. "normTex",
    ["Flat"]            = "Interface\\Buttons\\WHITE8X8",
    ["Minimalist"]      = "Interface\\Buttons\\WHITE8X8",
    ["ZacUI Gradient"] = PATH .. "normTex",
}

-- Always-present fallbacks, keyed by the same names LSM uses.
local FALLBACK = {
    font = {
        ["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF",
        ["Arial Narrow"]     = "Fonts\\ARIALN.TTF",
        ["Skurri"]           = "Fonts\\SKURRI.TTF",
        ["Morpheus"]         = "Fonts\\MORPHEUS.TTF",
    },
    statusbar = {
        ["Blizzard"] = "Interface\\TargetingFrame\\UI-StatusBar",
        ["Solid"]    = "Interface\\Buttons\\WHITE8X8",
        ["Raid Bar"] = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
    },
}
for k, v in pairs(BUNDLED_BAR) do FALLBACK.statusbar[k] = v end

local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
local DEFAULT_BAR  = "Interface\\Buttons\\WHITE8X8"

-- Resolve LSM once at load (OptionalDeps load before us) and register our
-- bundled textures into it so they appear everywhere.
local LSM = _G.LibStub and _G.LibStub:GetLibrary("LibSharedMedia-3.0", true) or nil
M.LSM = LSM
if LSM then
    for k, v in pairs(BUNDLED_BAR) do
        LSM:Register("statusbar", k, v)
    end
end

local function fetch(mediatype, name, default)
    if LSM then
        local path = LSM:Fetch(mediatype, name, true) -- true = no error if missing
        if path then return path end
    end
    local tbl = FALLBACK[mediatype]
    if tbl and name and tbl[name] then return tbl[name] end
    if tbl then for _, p in pairs(tbl) do return p end end
    return default
end

function M:Font(name)      return fetch("font", name, DEFAULT_FONT) end
function M:Statusbar(name) return fetch("statusbar", name, DEFAULT_BAR) end

local function listOf(mediatype)
    local set, out = {}, {}
    if LSM then
        for _, k in ipairs(LSM:List(mediatype)) do
            if not set[k] then set[k] = true; out[#out + 1] = k end
        end
    end
    local tbl = FALLBACK[mediatype]
    if tbl then
        for k in pairs(tbl) do
            if not set[k] then set[k] = true; out[#out + 1] = k end
        end
    end
    table.sort(out)
    return out
end

function M:ListFonts()      return listOf("font") end
function M:ListStatusbars() return listOf("statusbar") end
function M:HasLSM()         return LSM ~= nil end
