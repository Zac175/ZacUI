-- Core_Numbers - one number formatter for every part: 12.3k / 1.2m / 1.0b,
-- separators in the client's own locale (12,345 or 12.345), the whole
-- number, and the house styles each part grew (the meter's Details-style
-- K/M/B, the plate text's "1.2k", the raid summary's "1.50M"), each
-- reproduced to the byte so a part that switches to this draws exactly
-- what it drew before.
-- Part of ZacUI; load order is set by the TOC (right after Core_Flavor:
-- it asks ns.IsSecret; before everything that shows a number).
--
-- WOW FOREVER AND RETAIL hide many numbers from addons in combat (secret
-- values: no maths, no compare, no string.format). A secret number still
-- formats here: the client's own C function AbbreviateNumbers takes one
-- and hands back a text (which may itself be secret - a FontString takes
-- it as it is), and where that is missing the value goes back untouched
-- for SetText to show. Nothing here ever does arithmetic on a value it
-- has not first found to be plain. On Classic Era and TBC nothing is
-- secret, so every call takes the plain path and the output is the
-- style's, byte for byte.
--
--   ns.Numbers.Format(v, style, decimals)   the text for v in a style
--   ns.Numbers.Comma(v)                     12,345 in the client's separator
--   ns.Numbers.Short(v, decimals)           12.3k / 1.2m / 1.0b (ZacUI's text-format "short")
--   ns.Numbers.Plain(v)                     the whole number
--   ns.Numbers.Secret(v)                    what to show for a hidden value
--   ns.Numbers.STYLES                       { id, label } for a picker
--   ns.FormatNumber(v, "short")             the text-format helper (UIF_Custom)
--                                           takes a style name as well as a spec
-- Styles:
--   short     12.3k, 1.2m, 1.0b from ten thousand (ZacUI's text formats)
--   comma     12,345 - the client's thousands separator
--   plain     12345
--   details   the meter's: 12.3K from a thousand, 1.23M, 1.23B (> bounds)
--   details1  the meter's no-abbreviation "12345.0"
--   details2  the meter's second K style (whole K from a hundred thousand)
--   details0  the meter's whole-K style
--   plate     the scrolling text on plates: 1.2k under ten thousand, 12k above
--   summary   the raid summary's: 1.50M, 12.3K from ten thousand

local ADDON_NAME, ns = ...

local type, tostring, tonumber, pcall = type, tostring, tonumber, pcall
local math_floor, math_abs = math.floor, math.abs
local string_format = string.format

local N = {}
ns.Numbers = N

-- is this a value the client hides from us?
local function Hidden(v)
    local f = ns.IsSecret
    if f then return f(v) end
    if issecretvalue ~= nil then return issecretvalue(v) and true or false end
    return false
end
N.Hidden = Hidden

-- the client's separators ("," and "." on an English client; the
-- globals are the game's own, so a German client reads "." and ",")
local function Sep()
    local s = _G.LARGE_NUMBER_SEPERATOR
    if type(s) ~= "string" then s = "," end
    return s
end
local function Dec()
    local s = _G.DECIMAL_SEPERATOR
    if type(s) ~= "string" then s = "." end
    return s
end
N.Separator, N.Decimal = Sep, Dec

-- what a hidden value becomes: the client's own abbreviation when it
-- takes the value, else the value itself (a text widget shows it)
function N.Secret(v)
    local ab = _G.AbbreviateNumbers
    if ab then
        local ok, s = pcall(ab, v)
        if ok and s ~= nil then return s end
    end
    return v
end

-- a plain number, or nil for anything that is not one (a hidden value
-- included: tonumber on one throws on the real client)
local function Plain(v)
    if v == nil or Hidden(v) then return nil end
    if type(v) == "number" then return v end
    local ok, n = pcall(tonumber, v)
    if ok then return n end
    return nil
end
N.ToNumber = Plain

-- ============================================================
-- THE STYLES (each one is a part's old function, kept to the byte)
-- ============================================================
-- ZacUI's text-format "short" (UIF_Custom): from ten thousand
function N.Short(v, dec)
    dec = tonumber(dec) or 1
    local a = math_abs(v)
    local fmt = "%." .. dec .. "f"
    if a >= 1e9 then return string_format(fmt .. "b", v / 1e9)
    elseif a >= 1e6 then return string_format(fmt .. "m", v / 1e6)
    elseif a >= 1e4 then return string_format(fmt .. "k", v / 1e3) end
    return tostring(math_floor(v + 0.5))
end

function N.Plain(v)
    return tostring(math_floor(v + 0.5))
end

-- 12,345 in the client's separator
function N.Comma(v)
    local s = tostring(math_floor(math_abs(v) + 0.5))
    local sep = Sep()
    local out = s:reverse():gsub("(%d%d%d)", "%1" .. sep):reverse()
    if out:sub(1, #sep) == sep then out = out:sub(#sep + 1) end
    return (v < 0 and "-" or "") .. out
end

-- the meter's Details-style family (Meter_Data: ps_abbreviation 1-4;
-- bounds use > exactly as the original: 1000000 reads "1000.0K")
local function Details(n)
    if n > 999999999 then return string_format("%.2f", n / 1000000000) .. "B"
    elseif n > 1000000 then return string_format("%.2f", n / 1000000) .. "M"
    elseif n > 999 then return string_format("%.1f", n / 1000) .. "K" end
    return string_format("%.0f", n)
end
local function Details1(n) return string_format("%.1f", n) end
local function Details2(n)
    if n > 999999999 then return string_format("%.2f", n / 1000000000) .. "B"
    elseif n > 999999 then return string_format("%.2f", n / 1000000) .. "M"
    elseif n > 99999 then return math_floor(n / 1000) .. "K"
    elseif n > 999 then return string_format("%.1f", n / 1000) .. "K" end
    return string_format("%.0f", n)
end
local function Details0(n)
    if n > 999999999 then return string_format("%.1f", n / 1000000000) .. "B"
    elseif n > 999999 then return string_format("%.1f", n / 1000000) .. "M"
    elseif n > 999 then return math_floor(n / 1000) .. "K" end
    return string_format("%.0f", n)
end

-- the scrolling text on plates (SCT_PlateText)
local function Plate(n)
    if n < 1000 then return tostring(math_floor(n + 0.5)) end
    if n < 10000 then
        local s = string_format("%.1fk", n / 1000)
        return (s:gsub("%.0k$", "k"))
    end
    return string_format("%dk", math_floor(n / 1000 + 0.5))
end

-- the raid summary's page (Meter_RaidSummary)
local function Summary(v)
    if v >= 1e6 then return string_format("%.2fM", v / 1e6) end
    if v >= 1e4 then return string_format("%.1fK", v / 1e3) end
    return tostring(math_floor(v + 0.5))
end

local STYLE_FN = {
    short = function(v, dec) return N.Short(v, dec) end,
    comma = function(v) return N.Comma(v) end,
    plain = function(v) return N.Plain(v) end,
    full = function(v) return N.Plain(v) end,
    details = Details, details1 = Details1, details2 = Details2, details0 = Details0,
    plate = Plate,
    summary = Summary,
}
N.STYLE_FN = STYLE_FN

N.STYLES = {
    { id = "short", label = "Short (12.3k)" },
    { id = "comma", label = "With separators (12,345)" },
    { id = "plain", label = "Whole number (12345)" },
}

-- the text for v. A hidden value is handed to the client's own
-- abbreviation (or back as it is); nil and anything not a number read
-- as the style's zero, as the old code read them.
function N.Format(v, style, dec)
    if v ~= nil and Hidden(v) then return N.Secret(v) end
    local n = Plain(v) or 0
    local fn = STYLE_FN[style] or STYLE_FN.short
    return fn(n, dec)
end
