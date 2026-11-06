-- AE_Text - the %codes in a display's text: %p, %t, %n, %i, %s, %c,
-- any state field (%unit, %destName...), a trigger's own (%2.p,
-- %{1.raidTargetIndex}), and how each is formatted.
-- Part of ZacUI (Zacui_Auras). Written for ZacUI.
--
-- A text's options sit beside it in the display table, keyed
--   <prefix>_format_<symbol>_format          "none", "timed", "Number", ...
--   <prefix>_format_<symbol>_<option>        that format's options
-- where prefix is "displayText" for a text display and "text_text" for a
-- text inside a sub-element.
local ns = _G.ZacUI
if not ns then return end
local E = ns.AuraEngine
if not E then return end

local T = {}
E.Text = T

local floor, ceil, abs = math.floor, math.ceil, math.abs
local format = string.format

-- ============================================================
-- TIME
-- ============================================================
-- How the format's time formats read (time_format): 0, its own: "63:42",
-- "3:07", "10" (whole seconds rounded up; time_legacy_floor rounds down);
-- 1, the game's short form: "2h", "3m", "10s"; 2 only exists on the
-- modern client and falls back to 0 here. Below the threshold a time
-- shows `precision` decimals; a threshold of 0 never does.
local function Clock(sec)
    if sec > 60 then return format("%i:", floor(sec / 60)) .. format("%02i", sec % 60) end
    return format("%d", sec)
end

local function Short(sec)
    if SecondsToTimeAbbrev then
        local ok, fmt, v = pcall(SecondsToTimeAbbrev, sec)
        if ok and type(fmt) == "string" then return (fmt:gsub(" ", "")):format(v) end
    end
    if sec >= 86400 then return format("%dd", ceil(sec / 86400)) end
    if sec >= 3600 then return format("%dh", ceil(sec / 3600)) end
    if sec >= 60 then return format("%dm", ceil(sec / 60)) end
    return format("%ds", floor(sec))
end

function T.Time(sec, precision, threshold, style, legacyFloor)
    sec = tonumber(sec)
    if not sec or sec == math.huge or sec <= 0 then return "" end
    precision = tonumber(precision) or 1
    threshold = tonumber(threshold) or 60
    style = tonumber(style) or 0
    if threshold > 0 and sec < threshold then
        return format("%." .. precision .. "f", sec)
    end
    if style == 1 then return Short(sec) end
    if legacyFloor and style == 0 then return Clock(sec) end
    return Clock(ceil(sec))
end

-- ============================================================
-- NUMBERS
-- ============================================================
local function Round(n, kind)
    if kind == "ceil" then return ceil(n) end
    if kind == "round" then return floor(n + 0.5) end
    return floor(n)
end

-- "Number": precision decimals (1 if not set); none: rounded the chosen way
function T.Number(n, places, kind)
    local v = tonumber(n)
    if not v then return n == nil and "" or tostring(n) end
    places = tonumber(places) or 1
    if places <= 0 then return tostring(Round(v, kind or "floor")) end
    return format("%." .. places .. "f", v)
end

-- the game's number shorteners where the client has them
function T.Big(n, places)
    n = tonumber(n)
    if not n then return "" end
    places = tonumber(places) or 1
    local a = abs(n)
    local units = { { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }
    for _, u in ipairs(units) do
        if a >= u[1] then
            local s = format("%." .. places .. "f", n / u[1])
            s = s:gsub("%.?0+$", "")
            return s .. u[2]
        end
    end
    return tostring(floor(n + 0.5))
end

local function Abbr(n)
    if AbbreviateNumbers then
        local ok, s = pcall(AbbreviateNumbers, n)
        if ok and s then return s end
    end
    return T.Big(n, 1)
end

local function BigNumber(value, how)
    local n = tonumber(value)
    if not n then return value == nil and "" or tostring(value) end
    if how == "BreakUpLargeNumbers" then
        if BreakUpLargeNumbers then
            local ok, s = pcall(BreakUpLargeNumbers, n)
            if ok and s then return s end
        end
        local s = tostring(floor(n))
        local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
        return (out:gsub("^,", ""):gsub("^%-,", "-"))
    elseif how == "AbbreviateLargeNumbers" then
        if AbbreviateLargeNumbers then
            local ok, s = pcall(AbbreviateLargeNumbers, floor(n + 0.5))
            if ok and s then return s end
        end
        return T.Big(n, 1)
    end
    return Abbr(n)
end

local function Pad(s, mode, width)
    s = tostring(s or "")
    width = tonumber(width) or 8
    local len = 0
    for _ in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do len = len + 1 end
    local fill = string.rep(" ", math.max(0, width - len))
    if mode == "right" then return s .. fill end
    return fill .. s
end
T.Pad = Pad

local COIN = { gold = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t", silver = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
    copper = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t" }
local function Money(value, how, precision)
    local v = tonumber(value)
    if not v then return "" end
    local gold = floor(v / 1e4)
    local silver = floor(v / 100 % 100)
    local copper = v % 100
    local g
    if how == "BreakUpLargeNumbers" or how == "AbbreviateLargeNumbers" or how == "AbbreviateNumbers" then
        g = BigNumber(gold, how)
    else
        g = tostring(gold)
    end
    precision = tonumber(precision) or 3
    if precision == 1 then return g .. COIN.gold end
    if precision == 2 then return format("%s%s %d%s", g, COIN.gold, silver, COIN.silver) end
    return format("%s%s %d%s %d%s", g, COIN.gold, silver, COIN.silver, copper, COIN.copper)
end

-- ============================================================
-- NAMES
-- ============================================================
local function ClassColored(name, class)
    if not class then return name end
    local c = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
    if not c then return name end
    return format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name)
end

local function Shorten(s, max)
    max = tonumber(max) or 8
    if type(s) ~= "string" then return s end
    -- by characters, not bytes (names can be accented)
    local out, n = {}, 0
    for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        n = n + 1
        if n > max then break end
        out[n] = ch
    end
    return table.concat(out)
end

local function UnitNameOf(v, opts, prefix)
    if v == nil or v == "" then return "" end
    local name, realm = tostring(v), nil
    local class
    if UnitExists and UnitExists(name) then
        local n, r = UnitName(name)
        class = select(2, UnitClass(name))
        name, realm = n or name, r
    end
    local dash = name:find("-", 1, true)
    if dash then
        realm = realm or name:sub(dash + 1)
        name = name:sub(1, dash - 1)
    end
    if opts(prefix .. "abbreviate") then name = Shorten(name, opts(prefix .. "abbreviate_max")) end
    local rn = opts(prefix .. "realm_name")
    if realm and realm ~= "" then
        local mine = GetRealmName and (GetRealmName() or ""):gsub("%s", "") or ""
        local other = realm:gsub("%s", "") ~= mine
        if rn == "always" then name = name .. "-" .. realm
        elseif rn == "star" and other then name = name .. "*"
        elseif rn == "differentServer" and other then name = name .. "-" .. realm end
    end
    if opts(prefix .. "color") == "class" then name = ClassColored(name, class) end
    return name
end

local function GuidName(v, opts, prefix)
    if type(v) ~= "string" or v == "" then return "" end
    local class, name, realm
    if GetPlayerInfoByGUID then
        local ok, c, _, _, _, _, n, r = pcall(GetPlayerInfoByGUID, v)
        if ok then class, name, realm = c, n, r end
    end
    if not name then return v end
    -- GetPlayerInfoByGUID gives the localised class first, the token
    -- second; the token is what the colours are keyed by
    if GetPlayerInfoByGUID then
        local ok, _, token = pcall(GetPlayerInfoByGUID, v)
        if ok and token then class = token end
    end
    if opts(prefix .. "abbreviate") then name = Shorten(name, opts(prefix .. "abbreviate_max")) end
    if realm and realm ~= "" and opts(prefix .. "realm_name") == "always" then name = name .. "-" .. realm end
    if opts(prefix .. "color") == "class" then name = ClassColored(name, class) end
    return name
end

-- ============================================================
-- ONE VALUE IN ITS FORMAT
-- ============================================================
local function Apply(value, kind, opts, prefix)
    local function O(k) return opts(prefix .. k) end
    local out
    if kind == "timed" then
        return T.Time(value, O("time_precision"), O("time_dynamic_threshold"), O("time_format"), O("time_legacy_floor"))
    elseif kind == "Number" then
        out = T.Number(value, O("decimal_precision"), O("round_type"))
    elseif kind == "BigNumber" then
        out = BigNumber(value, O("big_number_format"))
    elseif kind == "AbbreviateNumbers" then
        local n = tonumber(value)
        return n and Abbr(n) or tostring(value or "")
    elseif kind == "Money" then
        return Money(value, O("money_format") or "AbbreviateNumbers", O("money_precision"))
    elseif kind == "GCDTime" then
        local n = tonumber(value)
        if not n or n <= 0 then return O("gcd_hide_zero") and "" or "0" end
        out = T.Number(n / 1.5, O("decimal_precision"), O("round_type") or "ceil")
    elseif kind == "Unit" then
        return UnitNameOf(value, opts, prefix)
    elseif kind == "guid" then
        return GuidName(value, opts, prefix)
    elseif kind == "string" then
        local s = value == nil and "" or tostring(value)
        if O("abbreviate") then s = Shorten(s, O("abbreviate_max")) end
        out = s
    else
        if value == nil then return "" end
        return tostring(value)
    end
    if O("pad") then out = Pad(out, O("pad_mode"), O("pad_max")) end
    return out
end
T.Apply = Apply

-- ============================================================
-- THE STANDARD SYMBOLS
-- ============================================================
-- what %p / %t mean for a state
local function Progress(state, now)
    if state.progressType == "timed" then
        if state.paused then return state.remaining or 0 end
        local exp = tonumber(state.expirationTime)
        if not exp or exp == math.huge then return nil end
        local mod = tonumber(state.modRate) or 1
        return math.max(0, (exp - now) / mod)
    end
    return state.value
end

local function Total(state)
    if state.progressType == "timed" then return state.duration end
    return state.total
end

local function Symbol(state, sym, now)
    if not state then return nil end
    if sym == "p" then return Progress(state, now) end
    if sym == "t" then return Total(state) end
    if sym == "n" then return state.name end
    if sym == "i" then
        local icon = state.icon
        if not icon then return "" end
        return "|T" .. tostring(icon) .. ":12:12:0:0:64:64:4:60:4:60|t"
    end
    if sym == "s" then
        local s = state.stacks
        if s == nil or s == 0 then return "" end
        return s
    end
    return state[sym]
end
T.Symbol = Symbol

-- ============================================================
-- A WHOLE TEXT
-- ============================================================
-- text      the template
-- d         the display (or sub-element) table its options live in
-- prefix    "displayText" / "text_text"
-- ctx       { state = main state, triggers = { [n] = state }, custom = { c1, c2, ... } }
function T.Format(text, d, prefix, ctx)
    if type(text) ~= "string" or not text:find("%%") then return text or "" end
    local now = GetTime()
    local function opts(key) return d[prefix .. "_format_" .. key] end
    local function Value(trig, sym)
        local full = trig and (trig .. "." .. sym) or sym
        local kind = d[prefix .. "_format_" .. full .. "_format"]
        local raw, st
        if sym:match("^c%d*$") and not trig then
            local n = tonumber(sym:sub(2)) or 1
            raw = ctx.custom and ctx.custom[n]
            if raw == nil then return "" end
            if kind == nil or kind == "none" then return tostring(raw) end
        else
            st = trig and ctx.triggers and ctx.triggers[tonumber(trig)] or ctx.state
            raw = Symbol(st, sym, now)
        end
        if kind == nil then
            -- %p / %t of a timer read as time even when nothing was chosen
            if (sym == "p" or sym == "t") and type(raw) == "number" and st and st.progressType == "timed" then
                kind = "timed"
            else
                kind = "none"
            end
        end
        return Apply(raw, kind, function(k) return opts(full .. "_" .. k) end, "")
    end
    local out = text:gsub("%%(%b{})", function(b)
        local inner = b:sub(2, -2)
        local trig, sym = inner:match("^(%d+)%.([%w_]+)$")
        if not trig then sym = inner end
        return "\1" .. Value(trig, sym)
    end)
    out = out:gsub("%%%%", "\2")
    out = out:gsub("%%(%d*)%.?([%a_][%w_]*)", function(trig, sym)
        if trig == "" then trig = nil end
        return Value(trig, sym)
    end)
    out = out:gsub("\1", ""):gsub("\2", "%%")
    return out
end

-- does a text need re-drawing as time passes (it shows %p or %t of a
-- timer)?
function T.IsTimed(text)
    if type(text) ~= "string" then return false end
    return text:find("%%%d*%.?p") ~= nil or text:find("%%{%d*%.?p}") ~= nil
        or text:find("%%%d*%.?t") ~= nil
end
