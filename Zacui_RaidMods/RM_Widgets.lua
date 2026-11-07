-- RM_Widgets - what the Raid Mods engine draws: texts, icons, bars,
-- progress circles and plain textures, built from the display spec each
-- unit carries, plus the text substitution, the conditions, the actions
-- (sound, chat, glow, custom) and the small animations the packs use.
-- Part of ZacUI; load order is set by the TOC.
--
-- ONE WIDGET PER SHOWN STATE. The core hands RM.Render(inst) the unit's
-- live states; this file keeps one widget per clone id, pooled by kind,
-- and asks RM.Layout (RM_Anchors) to place it in the unit's group. A
-- state that goes away plays its finish animation (usually a short fade)
-- and the widget returns to the pool.
--
-- PERF LAWS. No OnUpdate: everything that moves - bar fill, "%p" texts,
-- cooldown swipes, glow pulses, animations - is driven by ONE ticker at
-- 20 Hz that runs only while something timed or animated is on screen.
-- Conditions are re-evaluated on state change, on the ticker for timed
-- checks, and at the exact instant a timer check crosses its value.

local ns = _G.ZacUI
if not ns then return end
local RM = ns.RaidMods
if not RM then return end

local W = {}
RM.Widgets = W

local FLAT = ns.FLAT or "Interface\\Buttons\\WHITE8X8"
local GetTime = GetTime
local floor, abs, max, min = math.floor, math.abs, math.max, math.min
local SafeCall = RM.SafeCall

local function LSM() return LibStub and LibStub("LibSharedMedia-3.0", true) end
-- ONE FONT, ONE BAR TEXTURE. The font is ZacUI's (Fonts & Textures); with
-- none chosen, the pack's own per text (Barlow Semi Condensed Black nearly
-- everywhere). db.barTexture: every bar ("ZacUI Flat" to begin with, which
-- is what ZacUI uses elsewhere).
local function FontPath(name)
    -- one font: ZacUI's, whenever one is chosen - the pack's own faces only
    -- while ZacUI has none (db.font, a face picked on the Raid mods page
    -- before, is kept and ignored)
    local one = ns.OneFace and ns.OneFace()
    if one then return one end
    local p = ns.ResolveFontPath and ns.ResolveFontPath(name)
    if p and p ~= name then return p end
    if type(name) == "string" and name:find("\\") then return name end
    return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end
local function BarTexture(name, source)
    local db = RM.DB()
    if db and db.barTexture and db.barTexture ~= "" then name = db.barTexture end
    name = ns.NewMediaName and ns.NewMediaName(name) or name
    if type(name) == "string" and name:find("\\") then return name end
    local lsm = LSM()
    local t = lsm and name and lsm:Fetch("statusbar", name, true)
    if t then return t end
    if ns.Media and ns.Media.BarPath then return ns.Media.BarPath(FLAT) end
    return FLAT
end
W.FontPath, W.BarTexture = FontPath, BarTexture

-- the Fonts & Textures page pushes its choices here like everywhere else
if ns.Media and ns.Media.RegisterTarget then
    ns.Media.RegisterTarget("raidmods", {
        label = "Raid mods",
        desc = "The boss mods' bars (always) and texts (unless the Raid mods page picks a font of its own).",
        order = 60,
        -- following ZacUI's font, still on the pack's own
        untouched = function()
            local db = RM.DB()
            return db ~= nil and db.fontFromZacUI == true and (db.font == nil or db.font == "")
        end,
        apply = function(font, bar, cleared)
            local db = RM.DB()
            if not db then return end
            if bar and bar ~= "" then db.barTexture = bar end
            -- (un-ticked, it is only restyled: nothing written)
            if db.fontFromZacUI and (font or cleared) then db.font = font end
            if W.RefreshAll then W.RefreshAll() end
        end,
    })
end

local STRATA = { "BACKGROUND", "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }
local function Strata(n)
    return STRATA[tonumber(n) or 1] or "MEDIUM"
end

local function Color4(c, dr, dg, db, da)
    if type(c) == "table" then return c[1] or dr, c[2] or dg, c[3] or db, c[4] or da end
    return dr, dg, db, da
end

-- ============================================================
-- TEXT: numbers, times and the %tokens
-- ============================================================
local function Round(x) return floor(x + 0.5) end
local function FormatTime(rem, fmt)
    if rem == nil then return "" end
    if rem == math.huge then return "" end
    if rem < 0 then rem = 0 end
    local thr = fmt and tonumber(fmt.time_dynamic_threshold) or 60
    local prec = fmt and tonumber(fmt.time_precision) or 1
    local legacy = fmt and fmt.time_legacy_floor
    if rem >= 3600 then
        return string.format("%d:%02d:%02d", floor(rem / 3600), floor(rem % 3600 / 60), floor(rem % 60))
    elseif rem >= 60 then
        return string.format("%d:%02d", floor(rem / 60), floor(rem % 60))
    elseif rem < thr and prec > 0 then
        return string.format("%." .. prec .. "f", rem)
    else
        return string.format("%d", legacy and floor(rem) or Round(rem))
    end
end
W.FormatTime = FormatTime

local function ClassColored(name, class)
    local c = class and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
    if c and name then return string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name) end
    return name or ""
end

local function FormatUnit(v, fmt)
    local name, class
    if type(v) == "string" and UnitExists(v) then
        name = UnitName(v)
        local _, c = UnitClass(v)
        class = c
    elseif type(v) == "string" and v:match("^Player%-") then
        name = RM.NameForGUID(v)
        if GetPlayerInfoByGUID then class = select(2, GetPlayerInfoByGUID(v)) end
    elseif type(v) == "string" then
        name = v
        -- a plain name: colour it when that player is in the group
        for unit in RM.IterateGroup() do
            local n = UnitName(unit)
            if n == v or (n and (n .. "-" .. (GetRealmName() or "")) == v) then
                local _, c = UnitClass(unit)
                class = c
                break
            end
        end
    else
        return v ~= nil and tostring(v) or ""
    end
    if not name then return "" end
    if not fmt or fmt.realm_name ~= "always" then name = name:gsub("%-.*$", "") end
    if fmt and fmt.abbreviate and fmt.abbreviate_max then name = RM.Utf8Sub(name, 1, tonumber(fmt.abbreviate_max) or 8) end
    if fmt and fmt.color == "class" then return ClassColored(name, class) end
    return name
end

local function FormatValue(v, fmt, w)
    local f = fmt and fmt.format
    if f == "timed" then
        if type(v) == "number" then return FormatTime(v, fmt) end
        return v ~= nil and tostring(v) or ""
    elseif f == "Unit" or f == "guid" then
        return FormatUnit(v, fmt)
    elseif f == "BigNumber" then
        if type(v) == "number" then
            if AbbreviateLargeNumbers and fmt.big_number_format ~= "AbbreviateNumbers" then return AbbreviateLargeNumbers(Round(v)) end
            if v >= 1e6 then return string.format("%.1fm", v / 1e6) end
            if v >= 1e3 then return string.format("%.1fk", v / 1e3) end
            return tostring(Round(v))
        end
    elseif f == "Number" then
        if type(v) == "number" then
            local dec = tonumber(fmt.decimal_precision) or 1
            if dec == 0 or v == floor(v) then return string.format("%d", Round(v)) end
            return string.format("%." .. dec .. "f", v)
        end
    end
    if v == nil then return "" end
    if type(v) == "number" then
        if v == floor(v) then return string.format("%d", v) end
        return string.format("%.1f", v)
    end
    if type(v) == "boolean" then return v and "true" or "" end
    return tostring(v)
end

local function IconString(icon, size)
    if not icon or icon == "" then return "" end
    size = size or 12
    return string.format("|T%s:%d:%d:0:0:64:64:4:60:4:60|t", tostring(icon), size, size)
end

-- progress numbers of a state, right now
local function Progress(st, now)
    if not st then return nil, nil end
    if st.progressType == "static" then
        return st.value or 0, st.total or 0
    end
    if st.expirationTime and st.expirationTime < math.huge and st.duration and st.duration > 0 then
        local rem = st.expirationTime - now
        if rem < 0 then rem = 0 end
        return rem, st.duration
    end
    return nil, st.duration
end

-- YOUR TIME FORMAT. The settings' raid-mod timer format (db.formats.timer,
-- ZacUI's text format shape) replaces the packs' own "%p" times once one
-- is saved; nothing saved = each pack's own format, exactly as before.
local timerSpec
function W.TimerSpec()
    local db = RM.DB()
    local f = db and type(db.formats) == "table" and db.formats.timer
    return type(f) == "table" and f or nil
end
W.TIMER_FORMAT_DEFAULTS = { time = "mmss", timeDecimalsUnder = 5 }

local SINGLE = { p = true, t = true, n = true, i = true, s = true, c = true }
local FMT_TIMED = { format = "timed" }
local FMT_GUID = { format = "guid", color = "class" }
-- Substitute runs ten times a second for every shown widget with a %p
-- text, so its two helpers are file-level closures reading from these
-- upvalues (set per call) instead of two new closures per call.
local S_w, S_inst, S_st, S_fmts, S_fontSize, S_now
local function Lookup(tok)
    local w, inst, st, fmts = S_w, S_inst, S_st, S_fmts
    -- "%2.name": a field of another trigger's state
    local n, field = tok:match("^(%d+)%.([%w_]+)$")
    if n then
        local ts = inst.tstates[tonumber(n)]
        local s = ts and (ts[w.cloneId] or ts[""])
        if not s then
            for _, x in pairs(ts or {}) do s = x break end
        end
        if not s then return "" end
        return FormatValue(s[field], fmts and fmts[tok], w)
    end
    if tok == "p" then
        local v = Progress(st, S_now)
        if v == nil then return "" end
        local f = fmts and fmts.p or FMT_TIMED
        if timerSpec and f.format == "timed" and type(v) == "number" and ns.FormatTime then
            if v == math.huge then return "" end
            return ns.FormatTime(v, timerSpec, W.TIMER_FORMAT_DEFAULTS)
        end
        return FormatValue(v, f, w)
    elseif tok == "t" then
        local _, tot = Progress(st, S_now)
        return FormatValue(tot, fmts and fmts.t or FMT_TIMED, w)
    elseif tok == "n" then
        return FormatValue(st and st.name, fmts and fmts.n, w)
    elseif tok == "i" then
        return IconString(st and st.icon or w.D.displayIcon, S_fontSize)
    elseif tok == "s" then
        local v = st and (st.stacks or st.count)
        if v == nil or v == 0 then return "" end
        return FormatValue(v, fmts and fmts.s, w)
    elseif tok == "c" then
        local c = w.custom
        return FormatValue(c and c[1], fmts and fmts.c, w)
    elseif tok:match("^c%d+$") then
        local c = w.custom
        return FormatValue(c and c[tonumber(tok:sub(2))], fmts and fmts[tok], w)
    elseif tok == "unit" then
        return FormatValue(st and st.unit, fmts and fmts.unit, w)
    elseif tok == "guid" then
        return FormatValue(st and (st.GUID or st.guid), fmts and fmts.guid or FMT_GUID, w)
    elseif st and st[tok] ~= nil then
        return FormatValue(st[tok], fmts and fmts[tok], w)
    end
    return nil
end
local function Token(esc, tok)
    if esc == "%" then return "%" .. tok end
    if tok == "" then return "%" end
    local v = Lookup(tok)
    if v ~= nil then return v end
    -- a variable the text declares (it has a format entry) but the
    -- state does not carry right now is blank, as in WeakAuras - not
    -- the raw "%name" (the AQ40 Anubisath icons showed "%optionsText")
    local fmts = S_fmts
    if fmts and fmts[tok] ~= nil then return "" end
    -- "%players" with no such field: the one-letter token and the rest
    local first = tok:sub(1, 1)
    if SINGLE[first] then
        local v1 = Lookup(first)
        if v1 ~= nil then return v1 .. tok:sub(2) end
    end
    return "%" .. tok
end
-- replace the %tokens of one text for one widget
local function Substitute(text, w, fmts, fontSize, now)
    if type(text) ~= "string" or not text:find("%%") then return text or "" end
    S_w, S_inst, S_st, S_fmts, S_fontSize, S_now = w, w.inst, w.state, fmts, fontSize, now
    timerSpec = W.TimerSpec()
    local out = text:gsub("%%(%%?)(%d*%.?[%w_]*)", Token)
    S_w, S_inst, S_st, S_fmts = nil, nil, nil, nil
    return out
end

-- ============================================================
-- SMALL PIECES: borders and glows
-- ============================================================
local function Edges(parent)
    local e = {}
    for i = 1, 4 do
        local t = parent:CreateTexture(nil, "OVERLAY")
        t:SetTexture(FLAT)
        e[i] = t
    end
    return e
end
local function LayoutEdges(e, frame, size, offset, r, g, b, a)
    size = size or 1
    offset = offset or 0
    for i = 1, 4 do
        e[i]:SetVertexColor(r, g, b, a)
        e[i]:ClearAllPoints()
        e[i]:Show()
    end
    e[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", -offset, offset)
    e[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", offset, offset)
    e[1]:SetHeight(size)
    e[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -offset, -offset)
    e[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", offset, -offset)
    e[2]:SetHeight(size)
    e[3]:SetPoint("TOPLEFT", frame, "TOPLEFT", -offset, offset)
    e[3]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -offset, -offset)
    e[3]:SetWidth(size)
    e[4]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", offset, offset)
    e[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", offset, -offset)
    e[4]:SetWidth(size)
end
local function HideEdges(e) for i = 1, 4 do e[i]:Hide() end end

-- A glow around a target frame. With LibCustomGlow (the aura engine's
-- copy rides along in Libs) it is the real thing - pixel, autocast or
-- button glow, as the pack asked; without it, a pulsing frame of edges.
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
local glows = {}       -- live edge glows, for the pulse
local glowPool = {}
local function AcquireGlow()
    local g = table.remove(glowPool)
    if not g then
        g = CreateFrame("Frame", nil, UIParent)
        g.edges = Edges(g)
        g.inner = Edges(g)
    end
    return g
end
local function GlowColor(spec)
    local r, g, b, a = 0.95, 0.95, 0.32, 1
    local col = spec and (spec.glowColor or spec.glow_color)
    if (spec and (spec.useGlowColor or spec.use_glow_color)) and type(col) == "table" then r, g, b, a = Color4(col, r, g, b, a) end
    return r, g, b, a
end
local function Num(spec, a, b, dflt)
    local v = spec and (spec[a] or spec[b])
    return tonumber(v) or dflt
end
local glowSeq = 0
function W.ShowGlow(owner, key, target, spec)
    owner.glowFrames = owner.glowFrames or {}
    local old = owner.glowFrames[key]
    if old then W.HideGlow(owner, key) end
    local r, g, b, a = GlowColor(spec)
    local kind = spec and (spec.glowType or spec.glow_type) or "Pixel"
    local freq = Num(spec, "glowFrequency", "glow_frequency", 0.25)
    local x, y = Num(spec, "glowXOffset", "glow_XOffset", 0), Num(spec, "glowYOffset", "glow_YOffset", 0)
    if LCG and target.GetObjectType then
        glowSeq = glowSeq + 1
        local lcgKey = "zrm" .. glowSeq
        local ok
        if kind == "ACShine" then
            ok = pcall(LCG.AutoCastGlow_Start, target, { r, g, b, a }, Num(spec, "glowLines", "glow_lines", 4), freq,
                Num(spec, "glowScale", "glow_scale", 1), x, y, lcgKey)
        elseif kind == "buttonOverlay" then
            ok = pcall(LCG.ButtonGlow_Start, target, { r, g, b, a }, freq)
        else
            kind = "Pixel"
            ok = pcall(LCG.PixelGlow_Start, target, { r, g, b, a }, Num(spec, "glowLines", "glow_lines", 8), freq,
                Num(spec, "glowLength", "glow_length", 10), Num(spec, "glowThickness", "glow_thickness", 1), x, y,
                (spec and (spec.glowBorder or spec.glow_border)) and true or false, lcgKey)
        end
        if ok then
            owner.glowFrames[key] = { lcg = true, kind = kind, target = target, key = lcgKey }
            return
        end
    end
    local gf = AcquireGlow()
    owner.glowFrames[key] = gf
    -- a settings-page sample pulses its own glow from its own clock
    -- (W.TickSample); only the live widgets' glows keep the draw loop up
    if not owner.sample then glows[gf] = true end
    gf:SetParent(target)
    gf:SetFrameStrata(target.GetFrameStrata and target:GetFrameStrata() or "HIGH")
    gf:SetFrameLevel((target.GetFrameLevel and target:GetFrameLevel() or 1) + 5)
    gf:ClearAllPoints()
    gf:SetPoint("TOPLEFT", target, "TOPLEFT", -1 - x, 1 + y)
    gf:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 1 + x, -1 - y)
    local th = Num(spec, "glowThickness", "glow_thickness", 2)
    LayoutEdges(gf.edges, gf, th, 0, r, g, b, a)
    LayoutEdges(gf.inner, gf, 1, -th, r, g, b, a * 0.5)
    gf.freq = freq ~= 0 and freq or 0.25
    gf.t0 = GetTime()
    gf:Show()
    if not owner.sample then W.StartTicker() end
end
function W.HideGlow(owner, key)
    local g = owner.glowFrames and owner.glowFrames[key]
    if not g then return end
    owner.glowFrames[key] = nil
    if g.lcg then
        if g.kind == "ACShine" then pcall(LCG.AutoCastGlow_Stop, g.target, g.key)
        elseif g.kind == "buttonOverlay" then pcall(LCG.ButtonGlow_Stop, g.target)
        else pcall(LCG.PixelGlow_Stop, g.target, g.key) end
        return
    end
    glows[g] = nil
    g:Hide()
    g:ClearAllPoints()
    g:SetParent(UIParent)
    glowPool[#glowPool + 1] = g
end
function W.HideAllGlows(owner)
    if not owner.glowFrames then return end
    for key in pairs(owner.glowFrames) do W.HideGlow(owner, key) end
end
local function GlowAlpha(g, now)
    local period = abs(g.freq) * 4
    if period < 0.2 then period = 0.2 end
    local ph = ((now - g.t0) % period) / period
    return 0.55 + 0.45 * math.sin(ph * 2 * math.pi)
end
local function PulseGlows(now)
    for g in pairs(glows) do
        g:SetAlpha(GlowAlpha(g, now))
    end
end

-- ============================================================
-- SUB TEXTS
-- ============================================================
-- where a sub text hangs on its region
local OPPOSITE = { TOP = "BOTTOM", BOTTOM = "TOP", LEFT = "RIGHT", RIGHT = "LEFT", TOPLEFT = "BOTTOMRIGHT", BOTTOMRIGHT = "TOPLEFT",
    TOPRIGHT = "BOTTOMLEFT", BOTTOMLEFT = "TOPRIGHT", CENTER = "CENTER" }
local function MirrorOuter(point)
    -- OUTER_TOP: the text's BOTTOM sits on the region's TOP (and so on)
    if point == "TOP" then return "BOTTOM" elseif point == "BOTTOM" then return "TOP"
    elseif point == "LEFT" then return "RIGHT" elseif point == "RIGHT" then return "LEFT"
    elseif point == "TOPLEFT" then return "BOTTOMLEFT" elseif point == "TOPRIGHT" then return "BOTTOMRIGHT"
    elseif point == "BOTTOMLEFT" then return "TOPLEFT" elseif point == "BOTTOMRIGHT" then return "TOPRIGHT" end
    return "CENTER"
end
-- {rt1}..{rt8} in a text become the raid mark icons, as the aura engine
-- draws them (the packs write "{rt8}" and mean the skull)
local MARKS = {}
for i = 1, 8 do MARKS["{rt" .. i .. "}"] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i .. ":0|t" end
local function Marks(t)
    if type(t) ~= "string" or not t:find("{", 1, true) then return t end
    return (t:gsub("{rt%d}", MARKS))
end

-- WHERE A BAR'S TEXTS SIT. A timer bar's texts take a role from the side
-- the pack put them on: the label (left), the time (right) and the middle
-- text. The settings' anchor for that role (db.anchors.<barLabel|barTimer|
-- barCenter>, ZacUI's anchor shape) goes on top of where the pack put
-- it - any corner of the bar, its icon or the whole region. Nothing saved =
-- the pack's own SetPoint, exactly.
W.BAR_ROLES = { "barLabel", "barTimer", "barCenter" }
W.BAR_TARGETS = { bar = "The bar", icon = "The bar's icon", region = "The whole timer" }
local function BarRole(w, ap)
    if w.kind ~= "aurabar" then return nil end
    local side = ap:gsub("^INNER_", ""):gsub("^OUTER_", ""):gsub("^ICON_", "")
    if ap:sub(1, 5) == "ICON_" then return nil end
    if side:find("LEFT") then return "barLabel" elseif side:find("RIGHT") then return "barTimer" end
    return "barCenter"
end
W.BarRole = BarRole
local function RoleSpec(role)
    local db = role and RM.DB()
    local a = db and type(db.anchors) == "table" and db.anchors[role]
    return type(a) == "table" and a or nil
end
-- what the picker shows as "where it sits now" for a role: the usual
-- pack bar (label left + 5, time right, middle text centred)
function W.RoleDefaults(role)
    if role == "barLabel" then return { point = "LEFT", relPoint = "LEFT", x = 5, y = 0, justify = "LEFT" }
    elseif role == "barTimer" then return { point = "RIGHT", relPoint = "RIGHT", x = 0, y = 0, justify = "RIGHT" } end
    return { point = "CENTER", relPoint = "CENTER", x = 0, y = 0, justify = "CENTER" }
end
local function BarTarget(w)
    if not w.anchorTo then
        w.anchorTo = function(k)
            if k == "bar" then return w.bar or w elseif k == "icon" then return w.iconFrame or w
            elseif k == "region" then return w end
        end
    end
    return w.anchorTo
end

local function AnchorSubText(fs, w, sub)
    local ap = sub.anchor_point or sub.text_anchorPoint or "CENTER"
    local self = sub.text_selfPoint or "AUTO"
    local x = tonumber(sub.text_anchorXOffset) or tonumber(sub.anchorXOffset) or 0
    local y = tonumber(sub.text_anchorYOffset) or tonumber(sub.anchorYOffset) or 0
    local target = w
    local point, relPoint
    if ap:sub(1, 5) == "ICON_" then
        target = w.iconFrame or w
        relPoint = ap:sub(6)
        point = self ~= "AUTO" and self or relPoint
    elseif ap:sub(1, 6) == "INNER_" then
        relPoint = ap:sub(7)
        point = self ~= "AUTO" and self or relPoint
        target = w.bar or w
    elseif ap:sub(1, 6) == "OUTER_" then
        relPoint = ap:sub(7)
        point = self ~= "AUTO" and self or MirrorOuter(relPoint)
    else
        relPoint = ap
        if self ~= "AUTO" then
            point = self
        elseif w.kind == "aurabar" then
            point = ap                       -- a bar's texts sit inside it
        elseif w.kind == "icon" then
            point = "CENTER"
        else
            -- anything else (progress textures, textures, texts): a text
            -- on LEFT hangs outside, its RIGHT on the region's LEFT - the
            -- aura engine's own rule, so ">{rt8}" stays off the icon
            point = OPPOSITE[ap] or "CENTER"
        end
        if w.bar then target = w.bar end
    end
    -- justification follows the side it sits on when the author left it
    local j = sub.text_justify
    if not j then
        if relPoint:find("LEFT") then j = "LEFT" elseif relPoint:find("RIGHT") then j = "RIGHT" else j = "CENTER" end
    end
    local spec = RoleSpec(BarRole(w, ap))
    if spec and ns.ApplyAnchor then
        -- the pack's spot is the default; the saved anchor on top
        local d = fs.rmDef
        if not d then d = {} fs.rmDef = d end
        d.point, d.to, d.relPoint, d.x, d.y, d.justify = point, target, relPoint, x, y, j
        ns.ApplyAnchor(fs, spec, d, BarTarget(w))
        return
    end
    fs:ClearAllPoints()
    fs:SetPoint(point, target, relPoint, x, y)
    fs:SetJustifyH(j)
end

local function RedoFont(fs)
    pcall(fs.SetFont, fs, FontPath(rawget(fs, "_zRmFont")), rawget(fs, "_zRmSize") or 12, rawget(fs, "_zRmFlags") or "")
end
local function StyleFontString(fs, font, size, flags, shadow, sx, sy)
    local path = FontPath(font)
    size = tonumber(size) or 12
    if size < 1 then size = 1 end
    local f = flags
    if f == "None" or f == "NONE" then f = "" end
    if f == "MONOCHROMEOUTLINE" then f = "MONOCHROME, OUTLINE" end
    fs:SetFont(path, size, f or "")
    -- kept up by ZacUI's font keeper: a change of ZacUI's font reaches it
    if ns.TrackHouseFont then
        rawset(fs, "_zRmFont", font) rawset(fs, "_zRmSize", size) rawset(fs, "_zRmFlags", f or "")
        ns.TrackHouseFont(fs, RedoFont)
    end
    if shadow then
        fs:SetShadowColor(Color4(shadow, 0, 0, 0, 1))
        fs:SetShadowOffset(tonumber(sx) or 1, tonumber(sy) or -1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

local function BuildSubTexts(w)
    w.texts = w.texts or {}
    w.chain = nil
    for _, fs in pairs(w.texts) do fs:Hide() end
    local subs = w.D.subRegions
    if not subs then return end
    local chain = {}
    for i, sub in ipairs(subs) do
        if sub.type == "subtext" then
            local fs = w.texts[i]
            if not fs then
                fs = w.top:CreateFontString(nil, "OVERLAY")
                w.texts[i] = fs
            end
            StyleFontString(fs, sub.text_font, sub.text_fontSize, sub.text_fontType, sub.text_shadowColor, sub.text_shadowXOffset, sub.text_shadowYOffset)
            if sub.text_automaticWidth == "Fixed" and tonumber(sub.text_fixedWidth) then
                fs:SetWidth(tonumber(sub.text_fixedWidth))
                fs:SetWordWrap(sub.text_wordWrap ~= "WordWrap" and false or true)
            else
                fs:SetWidth(0)
                fs:SetWordWrap(false)
            end
            fs:SetTextColor(Color4(sub.text_color, 1, 1, 1, 1))
            AnchorSubText(fs, w, sub)
            fs:Show()
            -- texts hanging off the right edge one after another: kept in
            -- a row so a long one never runs over the next (see ChainTexts)
            local ap = sub.anchor_point or sub.text_anchorPoint or "CENTER"
            if ap == "RIGHT" and w.kind ~= "aurabar" and w.kind ~= "icon" then
                chain[#chain + 1] = { i = i, x = tonumber(sub.text_anchorXOffset) or tonumber(sub.anchorXOffset) or 0,
                    y = tonumber(sub.text_anchorYOffset) or tonumber(sub.anchorYOffset) or 0, sub = sub }
            end
        end
    end
    if #chain >= 2 then
        table.sort(chain, function(a, b) return a.x < b.x end)
        w.chain = chain
    end
end

-- The right-hand texts in a row: each starts where it was put, or just
-- past the one before it when that one runs long (an ability name and a
-- note at +56 px used to sit on top of each other). Runs only when the
-- texts were rewritten, and only for regions that have two or more.
local function ChainTexts(w)
    local chain = w.chain
    if not chain then return end
    local prev, prevEnd
    for _, c in ipairs(chain) do
        local fs = w.texts[c.i]
        if fs and fs:IsShown() and (fs:GetText() or "") ~= "" then
            local width = fs:GetStringWidth() or 0
            local fixed = c.sub.text_automaticWidth == "Fixed" and tonumber(c.sub.text_fixedWidth)
            if fixed and fixed < width then width = fixed end
            local x = c.x
            if prev and prevEnd and x < prevEnd + 6 then x = prevEnd + 6 end
            if x ~= c.placed then
                c.placed = x
                AnchorSubText(fs, w, setmetatable({ text_anchorXOffset = x }, { __index = c.sub }))
            end
            prev, prevEnd = fs, x + width
        end
    end
end

local function BuildBorders(w)
    w.borders = w.borders or {}
    for _, e in pairs(w.borders) do HideEdges(e) end
    local subs = w.D.subRegions
    if not subs then return end
    for i, sub in ipairs(subs) do
        if sub.type == "subborder" and sub.border_visible ~= false then
            local e = w.borders[i]
            if not e then e = Edges(w.top) w.borders[i] = e end
            local target = w
            if sub.anchor_area == "icon" and w.iconFrame then target = w.iconFrame
            elseif sub.anchor_area == "bar" and w.bar then target = w.bar end
            local r, g, b, a = Color4(sub.border_color, 0, 0, 0, 1)
            LayoutEdges(e, target, tonumber(sub.border_size) or 1, tonumber(sub.border_offset) or 0, r, g, b, a)
            if target == w.iconFrame and not w.iconShown then HideEdges(e) end
        end
    end
end

local function BuildSubGlows(w)
    local subs = w.D.subRegions
    if not subs then return end
    for i, sub in ipairs(subs) do
        if sub.type == "subglow" then
            local on = sub.glow
            local over = w.props and w.props["sub." .. i .. ".glow"]
            if over ~= nil then on = over end
            if on then
                local spec = sub
                local col = w.props and w.props["sub." .. i .. ".glowColor"]
                if col then spec = setmetatable({ glowColor = col, useGlowColor = true }, { __index = sub }) end
                W.ShowGlow(w, "sub" .. i, (sub.anchor_area == "icon" and w.iconFrame) or (sub.anchor_area == "bar" and w.bar) or w, spec)
            else
                W.HideGlow(w, "sub" .. i)
            end
        end
    end
end

-- ============================================================
-- THE WIDGET KINDS
-- ============================================================
local Build = {}     -- [kind] = function(w)  one-time construction
local Setup = {}     -- [kind] = function(w)  per-state restyle from w.D (and w.props)
local Tick = {}      -- [kind] = function(w, now, rem, total)

-- -------- text --------
Build.text = function(w)
    w.text = w.top:CreateFontString(nil, "OVERLAY")
    w.text:SetPoint("CENTER")
end
-- WHERE AN ALERT TEXT SITS (db.anchors.alertText, ZacUI's anchor shape):
-- every pack's text displays at once - the warnings, call-outs and list
-- lines - round the spot their group or anchor gives them. The default is
-- the middle of its own region (where it always sat); nothing saved =
-- never touched.
W.ALERT_TEXT_DEFAULTS = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }
local function PlaceAlertText(w)
    local db = RM.DB()
    local a = db and type(db.anchors) == "table" and db.anchors.alertText or nil
    if type(a) ~= "table" or next(a) == nil then a = nil end
    if not (a or w.text.rmPlaced) then return end
    local d = w.text.rmDef
    if not d then d = {} w.text.rmDef = d end
    -- (the pack's justify stays unless the spot names one)
    d.point, d.relPoint, d.x, d.y, d.to, d.keepJustify = "CENTER", "CENTER", 0, 0, w.top, true
    ns.ApplyAnchor(w.text, a, d)
    w.text.rmPlaced = a and true or nil
end
Setup.text = function(w)
    local D = w.D
    StyleFontString(w.text, D.font, D.fontSize, D.outline, D.shadowColor, D.shadowXOffset, D.shadowYOffset)
    w.text:SetJustifyH(D.justify or "CENTER")
    if D.automaticWidth == "Fixed" and tonumber(D.fixedWidth) then
        w.text:SetWidth(tonumber(D.fixedWidth))
        w.text:SetWordWrap(D.wordWrap ~= "WordWrap" and false or true)
    else
        w.text:SetWidth(0)
        w.text:SetWordWrap(false)
    end
    local col = w.props and w.props.color or w.forcedColor or D.color
    w.text:SetTextColor(Color4(col, 1, 1, 1, 1))
    PlaceAlertText(w)
end
local function SizeToText(w)
    local t = w.text
    local tw, th = t:GetStringWidth() or 0, t:GetStringHeight() or 0
    if w.D.automaticWidth == "Fixed" and tonumber(w.D.fixedWidth) then tw = tonumber(w.D.fixedWidth) end
    w:SetSize(max(tw, 1), max(th, 1))
end

-- -------- icon --------
Build.icon = function(w)
    w.icon = w:CreateTexture(nil, "ARTWORK")
    w.icon:SetAllPoints(w)
    w.cd = CreateFrame("Cooldown", nil, w, "CooldownFrameTemplate")
    w.cd:SetAllPoints(w)
    w.cd:SetDrawBling(false)
    w.cd:SetDrawEdge(false)
    if w.cd.SetHideCountdownNumbers then w.cd:SetHideCountdownNumbers(true) end
    w.cd:Hide()
end
local function IconTexture(tex, icon, zoom, keepAspect)
    if icon == nil or icon == "" then icon = 134400 end
    if type(icon) == "string" and tonumber(icon) then icon = tonumber(icon) end
    tex:SetTexture(icon)
    local z = (tonumber(zoom) or 0) / 2
    tex:SetTexCoord(z, 1 - z, z, 1 - z)
end
-- The icon a display shows, the WeakAuras way: iconSource -1 (automatic)
-- = the trigger's own icon, 0 (manual) = the display's set icon, n = the
-- trigger's icon too (one state per display here); the set icon is the
-- fallback either way. (This used to put the set icon first for anything
-- but manual, so every automatic bar wore the pack's placeholder.)
local function PickIcon(w, D, st)
    local icon = w.props and w.props.displayIcon
    if icon ~= nil and icon ~= "" then return icon end
    if D.iconSource == 0 then icon = D.displayIcon
    else icon = st and st.icon end
    if icon == nil or icon == "" then icon = D.displayIcon end
    if (icon == nil or icon == "") and st then icon = st.icon end
    return icon
end

Setup.icon = function(w)
    local D = w.D
    w:SetSize(tonumber(D.width) or 32, tonumber(D.height) or 32)
    local st = w.state
    local icon = PickIcon(w, D, st)
    IconTexture(w.icon, icon, D.zoom)
    w.icon:SetVertexColor(Color4(w.props and w.props.color or w.forcedColor or D.color, 1, 1, 1, 1))
    local desat = D.desaturate
    if w.props and w.props.desaturate ~= nil then desat = w.props.desaturate end
    w.icon:SetDesaturated(desat and true or false)
    local inverse = D.inverse
    if w.props and w.props.inverse ~= nil then inverse = w.props.inverse end
    w.cd:SetReverse(inverse and true or false)
    if w.cd.SetSwipeColor then w.cd:SetSwipeColor(0, 0, 0, 0.8) end
    w.cd:SetDrawEdge(D.cooldownEdge and true or false)
    w.cdOn = D.cooldown and D.cooldownSwipe ~= false
end
Tick.icon = function(w, now, rem, total)
    local st = w.state
    if w.cdOn and st and st.progressType == "timed" and total and total > 0 and st.expirationTime and st.expirationTime < math.huge then
        local start = st.expirationTime - total
        if w.cdStart ~= start or w.cdDur ~= total then
            w.cdStart, w.cdDur = start, total
            w.cd:SetCooldown(start, total)
            w.cd:Show()
        end
    elseif w.cdStart then
        w.cdStart, w.cdDur = nil, nil
        w.cd:Clear()
        w.cd:Hide()
    end
end

-- -------- aurabar --------
Build.aurabar = function(w)
    w.bar = CreateFrame("StatusBar", nil, w)
    w.bar:SetMinMaxValues(0, 1)
    w.bg = w.bar:CreateTexture(nil, "BACKGROUND")
    w.bg:SetAllPoints(w.bar)
    w.bg:SetTexture(FLAT)
    w.iconFrame = CreateFrame("Frame", nil, w)
    w.icon = w.iconFrame:CreateTexture(nil, "ARTWORK")
    w.icon:SetAllPoints(w.iconFrame)
    w.spark = w.bar:CreateTexture(nil, "OVERLAY")
    w.spark:SetBlendMode("ADD")
    w.spark:Hide()
end
Setup.aurabar = function(w)
    local D = w.D
    local width, height = tonumber(D.width) or 200, tonumber(D.height) or 20
    w:SetSize(width, height)
    local vertical = D.orientation == "VERTICAL" or D.orientation == "VERTICAL_INVERSE"
    local showIcon = D.icon and true or false
    w.iconShown = showIcon
    w.bar:ClearAllPoints()
    w.iconFrame:ClearAllPoints()
    if showIcon then
        local side = D.icon_side or "LEFT"
        local isz = vertical and width or height
        w.iconFrame:SetSize(isz, isz)
        if vertical then
            if side == "LEFT" then w.iconFrame:SetPoint("BOTTOM", w, "BOTTOM") w.bar:SetPoint("TOPLEFT", w, "TOPLEFT") w.bar:SetPoint("BOTTOMRIGHT", w.iconFrame, "TOPRIGHT")
            else w.iconFrame:SetPoint("TOP", w, "TOP") w.bar:SetPoint("TOPLEFT", w.iconFrame, "BOTTOMLEFT") w.bar:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT") end
        else
            if side == "LEFT" then w.iconFrame:SetPoint("LEFT", w, "LEFT") w.bar:SetPoint("TOPLEFT", w.iconFrame, "TOPRIGHT") w.bar:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT")
            else w.iconFrame:SetPoint("RIGHT", w, "RIGHT") w.bar:SetPoint("TOPLEFT", w, "TOPLEFT") w.bar:SetPoint("BOTTOMRIGHT", w.iconFrame, "BOTTOMLEFT") end
        end
        local st = w.state
        local icon = PickIcon(w, D, st)
        IconTexture(w.icon, icon, D.zoom)
        w.icon:SetVertexColor(Color4(D.icon_color, 1, 1, 1, 1))
        local desat = D.desaturate
        if w.props and w.props.desaturate ~= nil then desat = w.props.desaturate end
        w.icon:SetDesaturated(desat and true or false)
        w.iconFrame:Show()
    else
        w.iconFrame:Hide()
        w.bar:SetAllPoints(w)
    end
    w.bar:SetStatusBarTexture(BarTexture(D.texture, D.textureSource))
    w.bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
    local rev = D.orientation == "HORIZONTAL_INVERSE" or D.orientation == "VERTICAL_INVERSE"
    if w.bar.SetReverseFill then w.bar:SetReverseFill(rev) end
    local barColor = (w.props and w.props.barColor) or w.forcedColor or D.barColor
    w.bar:SetStatusBarColor(Color4(barColor, 1, 1, 1, 1))
    local bgc = (w.props and w.props.backgroundColor) or D.backgroundColor
    w.bg:SetVertexColor(Color4(bgc, 0, 0, 0, 0.5))
    w.inverse = D.inverse and true or false
    if w.props and w.props.inverse ~= nil then w.inverse = w.props.inverse and true or false end
    w.adjMax = nil
    if D.useAdjustededMax and tonumber(D.adjustedMax) then w.adjMax = tonumber(D.adjustedMax) end
    if w.props and w.props.adjustedMax then w.adjMax = tonumber(w.props.adjustedMax) end
    if D.spark then
        w.spark:SetTexture(D.sparkTexture or "Interface\\CastingBar\\UI-CastingBar-Spark")
        w.spark:SetSize(tonumber(D.sparkWidth) or 10, tonumber(D.sparkHeight) or (height * 1.4))
        w.spark:SetVertexColor(Color4(D.sparkColor, 1, 1, 1, 1))
        w.spark:Show()
    else
        w.spark:Hide()
    end
end
Tick.aurabar = function(w, now, rem, total)
    local st = w.state
    local v
    if st and st.progressType == "static" then
        local tot = w.adjMax or (st.total or 0)
        v = tot > 0 and (st.value or 0) / tot or 0
    elseif rem and total and total > 0 then
        local tot = w.adjMax or total
        v = tot > 0 and rem / tot or 0
    else
        v = 1
    end
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    if w.inverse then v = 1 - v end
    w.bar:SetValue(v)
    if w.spark:IsShown() then
        w.spark:ClearAllPoints()
        if w.bar:GetOrientation() == "VERTICAL" then
            w.spark:SetPoint("CENTER", w.bar, "BOTTOM", 0, v * w.bar:GetHeight())
        else
            w.spark:SetPoint("CENTER", w.bar, "LEFT", v * w.bar:GetWidth(), 0)
        end
    end
end

-- -------- progresstexture --------
Build.progresstexture = function(w)
    w.bgTex = w:CreateTexture(nil, "BACKGROUND")
    w.bgTex:SetAllPoints(w)
    -- a full circle drawn plainly (a cooldown swipe parked at 100% is not
    -- a picture: the AQ40 ability icons came out as black squares)
    w.fgTex = w:CreateTexture(nil, "ARTWORK")
    w.fgTex:SetAllPoints(w)
    w.fgTex:Hide()
    w.cd = CreateFrame("Cooldown", nil, w, "CooldownFrameTemplate")
    w.cd:SetAllPoints(w)
    w.cd:SetDrawBling(false)
    w.cd:SetDrawEdge(false)
    if w.cd.SetHideCountdownNumbers then w.cd:SetHideCountdownNumbers(true) end
    if w.cd.SetUseCircularEdge then w.cd:SetUseCircularEdge(true) end
    w.bar = CreateFrame("StatusBar", nil, w)
    w.bar:SetAllPoints(w)
    w.bar:SetMinMaxValues(0, 1)
    w.bar:Hide()
end
Setup.progresstexture = function(w)
    local D = w.D
    w:SetSize(tonumber(D.width) or 64, tonumber(D.height) or 64)
    local fg = D.foregroundTexture or FLAT
    local bg = D.backgroundTexture or (D.sameTexture ~= false and fg) or FLAT
    -- the trigger's own texture wins, as in WeakAuras (the AQ40 ability
    -- icons set one per ability); "same texture" puts it behind too
    local stTex = w.state and w.state.texture
    if stTex ~= nil and stTex ~= "" then
        fg = stTex
        if D.sameTexture then bg = stTex end
    end
    -- file ids arrive as strings ("136010"); a string is read as a path
    if type(fg) == "string" and tonumber(fg) then fg = tonumber(fg) end
    if type(bg) == "string" and tonumber(bg) then bg = tonumber(bg) end
    local fgc = (w.props and w.props.foregroundColor) or D.foregroundColor
    local bgc = (w.props and w.props.backgroundColor) or D.backgroundColor
    w.bgTex:SetTexture(bg)
    w.bgTex:SetVertexColor(Color4(bgc, 0.5, 0.5, 0.5, 0.5))
    w.bgTex:SetDesaturated(D.desaturateBackground and true or false)
    local o = D.orientation or "CLOCKWISE"
    w.circular = (o == "CLOCKWISE" or o == "ANTICLOCKWISE")
    w.inverse = D.inverse and true or false
    if w.props and w.props.inverse ~= nil then w.inverse = w.props.inverse and true or false end
    w.adjMax = nil
    if D.useAdjustededMax and tonumber(D.adjustedMax) then w.adjMax = tonumber(D.adjustedMax) end
    if w.props and w.props.adjustedMax then w.adjMax = tonumber(w.props.adjustedMax) end
    w.fgTex:SetTexture(fg)
    w.fgTex:SetVertexColor(Color4(fgc, 1, 1, 1, 1))
    w.fgTex:SetDesaturated(D.desaturateForeground and true or false)
    w.fgTex:Hide()
    w.fgFull = nil
    w.cdKey, w.cdStart, w.cdDur = nil, nil, nil
    if w.circular then
        w.bar:Hide()
        if w.cd.SetSwipeTexture then w.cd:SetSwipeTexture(fg) end
        if w.cd.SetSwipeColor then w.cd:SetSwipeColor(Color4(fgc, 1, 1, 1, 1)) end
        -- the swipe covers what is LEFT: that is the foreground of a
        -- non-inverse progress texture
        w.cd:SetReverse((o == "ANTICLOCKWISE") ~= (w.inverse and true or false))
        w.cd:Show()
    else
        w.cd:Hide()
        w.bar:SetStatusBarTexture(fg)
        w.bar:SetStatusBarColor(Color4(fgc, 1, 1, 1, 1))
        local vertical = o == "VERTICAL" or o == "VERTICAL_INVERSE"
        w.bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
        if w.bar.SetReverseFill then w.bar:SetReverseFill(o == "HORIZONTAL_INVERSE" or o == "VERTICAL_INVERSE") end
        w.bar:Show()
    end
end
local STATIC_SPAN = 100000
Tick.progresstexture = function(w, now, rem, total)
    local st = w.state
    if w.circular then
        if st and st.progressType == "static" then
            local tot = w.adjMax or (st.total or 0)
            local v = tot > 0 and (st.value or 0) / tot or 0
            if v < 0 then v = 0 elseif v > 1 then v = 1 end
            -- full (or empty, inverted): the plain texture, no swipe
            local full = (v >= 0.999) ~= w.inverse
            local empty = (v <= 0.001) ~= w.inverse
            if full or empty then
                if w.fgFull ~= full then
                    w.fgFull = full
                    w.cdKey = nil
                    w.cd:Hide()
                    if full then w.fgTex:Show() else w.fgTex:Hide() end
                end
                return
            end
            if w.fgFull ~= nil then w.fgFull = nil w.fgTex:Hide() w.cd:Show() end
            -- a paused cooldown drawn to the fraction
            local key = floor(v * 1000)
            if w.cdKey ~= key then
                w.cdKey = key
                w.cd:SetCooldown(now - (1 - v) * STATIC_SPAN, STATIC_SPAN)
                if w.cd.Pause then w.cd:Pause() end
            end
        elseif rem and total and total > 0 and st.expirationTime < math.huge then
            if w.fgFull ~= nil then w.fgFull = nil w.fgTex:Hide() w.cd:Show() end
            local tot = w.adjMax or total
            local start = st.expirationTime - tot
            if w.cdStart ~= start or w.cdDur ~= tot then
                w.cdStart, w.cdDur, w.cdKey = start, tot, nil
                if w.cd.Resume then w.cd:Resume() end
                w.cd:SetCooldown(start, tot)
            end
        else
            if w.fgFull ~= nil then w.fgFull = nil w.fgTex:Hide() w.cd:Show() end
            if w.cdKey ~= "full" then
                w.cdKey, w.cdStart = "full", nil
                w.cd:SetCooldown(now - 1, STATIC_SPAN)
                if w.cd.Pause then w.cd:Pause() end
            end
        end
    else
        local v
        if st and st.progressType == "static" then
            local tot = w.adjMax or (st.total or 0)
            v = tot > 0 and (st.value or 0) / tot or 0
        elseif rem and total and total > 0 then
            local tot = w.adjMax or total
            v = rem / tot
        else v = 1 end
        if v < 0 then v = 0 elseif v > 1 then v = 1 end
        if w.inverse then v = 1 - v end
        w.bar:SetValue(v)
    end
end

-- -------- texture --------
Build.texture = function(w)
    w.tex = w:CreateTexture(nil, "ARTWORK")
    w.tex:SetAllPoints(w)
end
Setup.texture = function(w)
    local D = w.D
    w:SetSize(tonumber(D.width) or 64, tonumber(D.height) or 64)
    w.tex:SetTexture(D.texture or FLAT)
    w.tex:SetVertexColor(Color4((w.props and w.props.color) or D.color, 1, 1, 1, 1))
    w.tex:SetBlendMode(D.blendMode or "BLEND")
    w.tex:SetDesaturated(D.desaturate and true or false)
    if w.tex.SetRotation then w.tex:SetRotation(math.rad(tonumber(D.rotation) or tonumber(D.discrete_rotation) or 0)) end
    if D.mirror then w.tex:SetTexCoord(1, 0, 0, 1) else w.tex:SetTexCoord(0, 1, 0, 1) end
end

-- -------- empty --------
Build.empty = function(w) end
Setup.empty = function(w) w:SetSize(1, 1) end

-- ============================================================
-- POOL
-- ============================================================
local pools = {}
local shown = {}          -- every widget currently on screen (incl. finishing)
local function Acquire(kind)
    if not Build[kind] then kind = "empty" end
    local pool = pools[kind]
    if not pool then pool = {} pools[kind] = pool end
    local w = table.remove(pool)
    if not w then
        w = CreateFrame("Frame", nil, UIParent)
        w.kind = kind
        -- texts and borders live on a frame ABOVE the bar / cooldown
        -- children, or the bar's fill would paint over its own label
        w.top = CreateFrame("Frame", nil, w)
        w.top:SetAllPoints(w)
        Build[kind](w)
        w.top:SetFrameLevel(w:GetFrameLevel() + 5)
    end
    return w
end
local function ReleaseNow(w)
    shown[w] = nil
    W.HideAllGlows(w)
    if RM.Layout and RM.Layout.Remove then RM.Layout.Remove(w) end
    w:Hide()
    w:ClearAllPoints()
    w:SetParent(UIParent)
    w:SetAlpha(1)
    w:SetScale(1)
    w.inst, w.state, w.cloneId, w.D, w.props, w.anim, w.custom, w.condActive, w.condKey = nil, nil, nil, nil, nil, nil, nil, nil, nil
    w.forcedColor, w.nextCheck, w.lastCond, w.lastW, w.lastH, w.placedUnit, w.overLimit = nil, nil, nil, nil, nil, nil, nil
    w.cdStart, w.cdDur, w.cdKey, w.place, w.animX, w.animY = nil, nil, nil, nil, nil, nil
    w.finishing = nil
    if w.cd then w.cd:Clear() w.cd:Hide() end
    for _, fs in pairs(w.texts or {}) do fs:Hide() end
    for _, e in pairs(w.borders or {}) do HideEdges(e) end
    pools[w.kind][#pools[w.kind] + 1] = w
end

-- ============================================================
-- CONDITIONS
-- ============================================================
local function CondValue(w, check)
    local trig = check.trigger
    local inst = w.inst
    if trig == -1 then
        if check.variable == "customcheck" then
            if not check.fn then return false end
            inst.env.state = w.state
            local ok = SafeCall(inst, "condition", check.fn, inst.env)
            return ok and true or false
        elseif check.variable == "alwaystrue" then
            return true
        end
        return false
    end
    if trig == -2 or check.checks then
        local isOr = check.variable == "OR"
        for _, c in ipairs(check.checks or {}) do
            local v = CondValue(w, c)
            if isOr and v then return true end
            if not isOr and not v then return false end
        end
        return not isOr
    end
    local ts = inst.tstates[trig or 1]
    local st = ts and (ts[w.cloneId] or ts[""])
    if not st and ts then for _, x in pairs(ts) do st = x break end end
    local var = check.variable
    if var == "show" then
        local want = check.value
        local shownNow = st and st.show and true or false
        if want == 0 or want == false then return not shownNow end
        return shownNow
    end
    if not st then return false end
    if var == "expirationTime" then
        if not st.expirationTime or st.expirationTime == math.huge then return false end
        local rem = st.expirationTime - GetTime()
        local v = tonumber(check.value) or 0
        local op = check.op
        if op == "==" then return abs(rem - v) < 0.1 end
        if op == "<=" then return rem <= v end
        if op == "<" then return rem < v end
        if op == ">=" then return rem >= v end
        if op == ">" then return rem > v end
        if op == "~=" then return abs(rem - v) >= 0.1 end
        return false
    end
    local sv = st[var]
    if var == "stacks" and sv == nil then sv = st.count end
    local op = check.op
    local cv = check.value
    if op == nil or op == "" then
        -- a boolean check: value 1 wants true, 0 wants false
        if cv == 0 or cv == false then return not sv end
        return sv and true or false
    end
    if op == "find('%s')" then return type(sv) == "string" and type(cv) == "string" and sv:find(cv, 1, true) ~= nil end
    if op == "match('%s')" then return type(sv) == "string" and type(cv) == "string" and sv:match(cv) ~= nil end
    if type(sv) == "number" then cv = tonumber(cv) if cv == nil then return false end
    elseif type(sv) == "boolean" then cv = (cv == 1 or cv == true or cv == "1" or cv == "true")
    elseif type(sv) == "string" then cv = tostring(cv)
    elseif sv == nil then
        if op == "==" then return cv == nil or cv == "" end
        if op == "~=" then return not (cv == nil or cv == "") end
        return false
    end
    if op == "==" then return sv == cv end
    if op == "~=" then return sv ~= cv end
    if type(sv) ~= "number" then return false end
    if op == ">=" then return sv >= cv end
    if op == "<=" then return sv <= cv end
    if op == ">" then return sv > cv end
    if op == "<" then return sv < cv end
    return false
end

-- when does a timer check change its mind? -> the earliest such instant
local function NextTimerCheck(w, check, soonest)
    if check.checks then
        for _, c in ipairs(check.checks) do soonest = NextTimerCheck(w, c, soonest) end
        return soonest
    end
    if check.variable ~= "expirationTime" then return soonest end
    local ts = w.inst.tstates[check.trigger or 1]
    local st = ts and (ts[w.cloneId] or ts[""])
    if not st or not st.expirationTime or st.expirationTime == math.huge then return soonest end
    local at = st.expirationTime - (tonumber(check.value) or 0)
    local now = GetTime()
    if check.op == "==" then
        if at > now - 0.05 and (not soonest or at < soonest) then soonest = at end
    else
        if at > now and (not soonest or at < soonest) then soonest = at end
    end
    return soonest
end

local ONE_SHOT = { sound = true, chat = true, customcode = true }
local function FireChange(w, i, chg)
    local inst = w.inst
    local db = RM.DB()
    if chg.property == "sound" then
        if db and db.sounds and type(chg.value) == "table" then
            RM.RaidSound(chg.value.sound, chg.value.sound_channel)
        end
    elseif chg.property == "chat" then
        if type(chg.value) == "table" then W.SendMessage(w, chg.value.message, chg.value.message_type, chg.value.message_dest) end
    elseif chg.property == "customcode" then
        if chg.value then
            inst.env.state = w.state
            inst.curWidget = w
            SafeCall(inst, "condition code", chg.value, inst.env)
        end
    end
end

local function EvalConditions(w, now)
    local conds = w.inst.def.conditions
    if not conds then return end
    local active = w.condActive
    if not active then active = {} w.condActive = active end
    -- Ten times a second per widget: nothing is built unless a
    -- condition actually flipped; the property table is rebuilt only then.
    local moved = false
    local soonest
    for i, c in ipairs(conds) do
        local on = c.check and CondValue(w, c.check) or false
        if c.check then soonest = NextTimerCheck(w, c.check, soonest) end
        local was = active[i]
        if on ~= (was and true or false) then moved = true end
        if on then
            for _, chg in ipairs(c.changes) do
                if ONE_SHOT[chg.property] then
                    if not was then FireChange(w, i, chg) end
                elseif chg.property == "glowexternal" then
                    if not was then
                        local spec = chg.value or {}
                        local target
                        if spec.glow_frame_type == "UNITFRAME" then
                            target = RM.Layout and RM.Layout.UnitFrame and RM.Layout.UnitFrame(w.state and w.state.unit)
                        elseif spec.glow_frame_type == "NAMEPLATE" then
                            target = RM.Layout and RM.Layout.NamePlate and RM.Layout.NamePlate(w.state and w.state.unit)
                        else
                            target = w
                        end
                        if target then
                            if spec.glow_action == "hide" then W.HideGlow(w, "ext" .. i) else W.ShowGlow(w, "ext" .. i, target, spec) end
                        end
                    end
                end
            end
        elseif was then
            for _, chg in ipairs(c.changes) do
                if chg.property == "glowexternal" then W.HideGlow(w, "ext" .. i) end
            end
        end
        active[i] = on
    end
    if soonest then
        local delay = soonest - now
        if delay < 0 then delay = 0 end
        local inst, cid = w.inst, w.cloneId
        local stamp = floor(soonest * 100)
        if w.nextCheck ~= stamp then
            w.nextCheck = stamp
            C_Timer.After(delay + 0.01, function()
                if inst.widgets and inst.widgets[cid] == w then W.Refresh(w, true) end
            end)
        end
    end
    if moved then
        local newProps
        for i, c in ipairs(conds) do
            if active[i] then
                for _, chg in ipairs(c.changes) do
                    local prop = chg.property
                    if not ONE_SHOT[prop] and prop ~= "glowexternal" then
                        -- a boolean change saved without a value means false
                        -- (an unticked box); anything else carries its value
                        local v = chg.value
                        if v == nil then v = false end
                        newProps = newProps or {}
                        newProps[prop] = v
                    end
                end
            end
        end
        w.condKey = (tonumber(w.condKey) or 0) + 1
        w.props = newProps
        return true
    end
    return false
end

-- ============================================================
-- ANIMATIONS
-- ============================================================
local function AnimSpec(w, phase)
    local an = w.D.animation and w.D.animation[phase]
    if not an then return nil end
    local dur = tonumber(an.duration) or 0.2
    if an.duration_type == "relative" and w.state and w.state.duration and w.state.duration > 0 then dur = dur * w.state.duration end
    local spec = { preset = an.preset or "fade", dur = dur, custom = an.custom }
    if an.custom then
        -- A custom animation (the author's own functions, which the port
        -- does not carry) moves only what its use_* switches turn on; the
        -- preset name it keeps is just where the author started from.
        -- Nothing switched on (the AQ40 Anubisath icons: colour only) =
        -- no animation at all - it used to orbit forever.
        spec.useA, spec.useS, spec.useT = an.use_alpha and true or false, an.use_scale and true or false,
            an.use_translate and true or false
        if not (spec.useA or spec.useS or spec.useT) then return nil end
        spec.alpha = an.use_alpha and tonumber(an.alpha)
        spec.scalex, spec.scaley = an.use_scale and tonumber(an.scalex), an.use_scale and tonumber(an.scaley)
        spec.x, spec.y = an.use_translate and tonumber(an.x), an.use_translate and tonumber(an.y)
    end
    return spec
end

local function ApplyAnimFrame(w, alphaMul, scale, dx, dy)
    local baseAlpha = tonumber(w.props and w.props.alpha) or tonumber(w.D.alpha) or 1
    w:SetAlpha(baseAlpha * alphaMul)
    if scale and scale > 0 and abs((w:GetScale() or 1) - scale) > 0.001 then w:SetScale(scale) end
    if (dx or 0) ~= (w.animX or 0) or (dy or 0) ~= (w.animY or 0) then
        w.animX, w.animY = dx or 0, dy or 0
        if RM.Layout and RM.Layout.Nudge then RM.Layout.Nudge(w) end
    end
end

local function StartAnim(w, phase)
    local spec = AnimSpec(w, phase)
    if not spec or spec.dur <= 0 then
        w.anim = nil
        if phase == "start" then
            local m = AnimSpec(w, "main")
            if m then w.anim = { phase = "main", spec = m, t0 = GetTime() } end
        end
        ApplyAnimFrame(w, 1, 1, 0, 0)
        return phase == "finish" and false or true
    end
    w.anim = { phase = phase, spec = spec, t0 = GetTime() }
    W.StartTicker()
    return true
end

local function TickAnim(w, now)
    local a = w.anim
    if not a then return end
    local spec = a.spec
    local p = (now - a.t0) / spec.dur
    local phase = a.phase
    if phase == "main" then
        local pr = spec.preset
        local ph = ((now - a.t0) % max(spec.dur, 0.1)) / max(spec.dur, 0.1)
        local s = math.sin(ph * 2 * math.pi)
        -- a custom loop keeps only the kinds of motion it switched on
        if spec.custom then
            if (pr == "bounce" or pr == "orbit") and not spec.useT then pr = nil end
            if pr == "pulse" and not spec.useS then pr = nil end
            if pr == "alphaPulse" and not spec.useA then pr = nil end
        end
        if pr == "alphaPulse" then ApplyAnimFrame(w, 0.75 + 0.25 * s, 1, 0, 0)
        elseif pr == "pulse" then ApplyAnimFrame(w, 1, 1 + 0.08 * s, 0, 0)
        elseif pr == "bounce" then ApplyAnimFrame(w, 1, 1, 0, 8 * abs(s))
        elseif pr == "orbit" then ApplyAnimFrame(w, 1, 1, 10 * math.cos(ph * 2 * math.pi), 10 * s)
        else ApplyAnimFrame(w, 1, 1, 0, 0) end
        return
    end
    if p >= 1 then
        if phase == "start" then
            ApplyAnimFrame(w, 1, 1, 0, 0)
            local m = AnimSpec(w, "main")
            w.anim = m and { phase = "main", spec = m, t0 = now } or nil
        else
            w.anim = nil
            w.animDone = true
        end
        return
    end
    -- 0..1 of the way through; "out" for finish presets
    local pr = spec.preset
    local inV = phase == "start" and p or (1 - p)      -- how "present" the region is
    local al, sc, dx, dy = 1, 1, 0, 0
    if pr == "fade" then al = inV
    elseif pr == "grow" then sc = 0.2 + 0.8 * inV al = inV
    elseif pr == "shrink" then sc = 1 + (1 - inV) * 0.5 al = inV
    elseif pr == "slideleft" then dx = -200 * (1 - inV) al = inV
    elseif pr == "slideright" then dx = 200 * (1 - inV) al = inV
    elseif pr == "slidetop" then dy = 200 * (1 - inV) al = inV
    elseif pr == "slidebottom" then dy = -200 * (1 - inV) al = inV
    elseif pr == "bounceDecay" then dy = 20 * abs(math.sin(p * math.pi * 3)) * (1 - p) al = 1
    elseif pr == "spiral" or pr == "spiralandpulse" then sc = inV al = inV
    elseif pr == "starShakeDecay" then dx = 6 * math.sin(p * 40) * (1 - p)
    else al = inV end
    if spec.custom then
        -- the preset's own motion only where the author kept that kind on
        if not spec.useA then al = 1 end
        if not spec.useS then sc = 1 end
        if not spec.useT then dx, dy = 0, 0 end
        if spec.alpha then al = spec.alpha + (1 - spec.alpha) * inV end
        if spec.scalex then sc = spec.scalex + (1 - spec.scalex) * inV end
        if spec.x then dx = spec.x * (1 - inV) end
        if spec.y then dy = spec.y * (1 - inV) end
    end
    ApplyAnimFrame(w, al, sc, dx, dy)
end

-- ============================================================
-- APPLY: everything about one widget from its state
-- ============================================================
-- WeakAuras hands a custom text function (expirationTime, duration,
-- progress, name, icon, stacks); the packs' functions read those
local function CustomText(w, now)
    local fn = w.inst.def.text
    if not fn then w.custom = nil return end
    local inst = w.inst
    local st = w.state or {}
    inst.env.state = w.state
    inst.curWidget = w
    local rem = Progress(st, now)
    local a, b, c = SafeCall(inst, "custom text", fn, inst.env, st.expirationTime, st.duration, rem, st.name, st.icon, st.stacks or st.count)
    w.custom = { a, b, c }
end

local function Moves(txt)
    -- a text that changes with time: a %p / %t, or the custom text
    return type(txt) == "string" and txt:find("%%[ptc]") ~= nil
end
-- the "sub.N.*" property names, built once per sub-region index
local SUBKEYS = {}
local function SubKeys(i)
    local k = SUBKEYS[i]
    if not k then
        k = { vis = "sub." .. i .. ".text_visible", text = "sub." .. i .. ".text_text",
            color = "sub." .. i .. ".text_color", size = "sub." .. i .. ".text_fontSize", fsz = "fsz" .. i }
        SUBKEYS[i] = k
    end
    return k
end

local function ApplyTexts(w, now, tickOnly)
    local D = w.D
    local size = tonumber(D.fontSize) or 12
    if w.kind == "text" then
        local txt = (w.props and w.props.displayText) or D.displayText or ""
        if not tickOnly or Moves(txt) then
            w.text:SetText(Marks(Substitute(txt, w, D.fmt, size, now)))
            SizeToText(w)
        end
    end
    local subs = D.subRegions
    if subs and w.texts then
        for i, sub in ipairs(subs) do
            if sub.type == "subtext" then
                local fs = w.texts[i]
                if fs then
                    local K, props = SubKeys(i), w.props
                    local vis = sub.text_visible ~= false
                    local pv = props and props[K.vis]
                    if pv ~= nil then vis = pv and true or false end
                    if vis then
                        local txt = (props and props[K.text]) or sub.text_text or ""
                        if not tickOnly or Moves(txt) then
                            fs:SetText(Marks(Substitute(txt, w, sub.fmt, tonumber(sub.text_fontSize) or size, now)))
                        end
                        local col = props and props[K.color]
                        if col then fs:SetTextColor(Color4(col, 1, 1, 1, 1)) else fs:SetTextColor(Color4(sub.text_color, 1, 1, 1, 1)) end
                        local fsz = props and props[K.size]
                        if fsz and fsz ~= w[K.fsz] then
                            w[K.fsz] = fsz
                            StyleFontString(fs, sub.text_font, fsz, sub.text_fontType, sub.text_shadowColor, sub.text_shadowXOffset, sub.text_shadowYOffset)
                        elseif not fsz and w[K.fsz] then
                            w[K.fsz] = nil
                            StyleFontString(fs, sub.text_font, sub.text_fontSize, sub.text_fontType, sub.text_shadowColor, sub.text_shadowXOffset, sub.text_shadowYOffset)
                        end
                        fs:Show()
                    else
                        fs:Hide()
                    end
                end
            end
        end
        if w.chain then ChainTexts(w) end
    end
end

local function NeedsTick(w)
    local st = w.state
    if w.anim then return true end
    if st and st.progressType == "timed" and st.expirationTime and st.expirationTime < math.huge then return true end
    -- a static value only moves with a new or changed state, and that
    -- comes with a full Refresh; nothing to do every frame
    if w.D.customTextUpdate == "update" then return true end
    return false
end

-- full restyle (state changed, or conditions changed)
function W.Refresh(w, condOnly)
    if not w.inst or not w.state then return end
    local now = GetTime()
    local condChanged = EvalConditions(w, now)
    if condOnly and not condChanged then
        -- a timer check that did not change anything visible: still a
        -- fresh look at the texts, since %p moved
        return
    end
    local D = w.D
    w:SetFrameStrata(Strata(D.frameStrata))
    w.top:SetFrameLevel(w:GetFrameLevel() + 5)
    Setup[w.kind](w)
    BuildSubTexts(w)
    CustomText(w, now)
    ApplyTexts(w, now)
    BuildBorders(w)
    BuildSubGlows(w)
    local rem, total = Progress(w.state, now)
    if Tick[w.kind] then Tick[w.kind](w, now, rem, total) end
    local baseAlpha = tonumber(w.props and w.props.alpha) or tonumber(D.alpha) or 1
    if not w.anim then w:SetAlpha(baseAlpha) end
    if RM.Layout and RM.Layout.Changed then RM.Layout.Changed(w) end
    if NeedsTick(w) then W.StartTicker() end
end

-- the per-tick refresh: progress, %p texts, animations
-- every frame: the bar fill, the swipe, the animation. Ten times a
-- second (slow = true): the texts, the conditions, the preview loop.
local function TickWidget(w, now, slow)
    local st = w.state
    if not st then return end
    local rem, total = Progress(st, now)
    if Tick[w.kind] then Tick[w.kind](w, now, rem, total) end
    if w.anim then TickAnim(w, now) end
    if not slow then return end
    -- a preview sample runs its timer round and round
    if st.preview and st.progressType == "timed" and st.expirationTime and st.expirationTime <= now and st.duration and st.duration > 0 then
        st.expirationTime = now + st.duration
        W.Refresh(w)
        return
    end
    -- texts with a %p (or an update-every-frame custom text) move
    if w.D.customTextUpdate == "update" then CustomText(w, now) end
    if rem ~= nil or w.D.customTextUpdate == "update" then
        if w.inst.def.conditions then
            if EvalConditions(w, now) then W.Refresh(w) return end
        end
        ApplyTexts(w, now, true)
    end
end

-- ============================================================
-- THE DRAW LOOP
-- ============================================================
-- One frame's OnUpdate, alive only while something timed or animated is
-- on screen: bars have to move every frame to look smooth (a 20 Hz tick
-- shows as a stutter on a 220 px bar). What does not need to be smooth -
-- text, conditions, glow pulses - runs on a 0.1 s beat inside it.
local driver = CreateFrame("Frame", nil, UIParent)
driver:Hide()
local lastSlow = 0
local function OnTick()
    local now = GetTime()
    local slow = (now - lastSlow) >= 0.1
    if slow then lastSlow = now end
    local any = false
    for w in pairs(shown) do
        if w.finishing then
            TickAnim(w, now)
            if not w.anim then
                ReleaseNow(w)
            else
                any = true
            end
        elseif w.inst then
            TickWidget(w, now, slow)
            if NeedsTick(w) then any = true end
        end
    end
    if next(glows) then
        if slow then PulseGlows(now) end
        any = true
    end
    if not any then driver:Hide() end
end
driver:SetScript("OnUpdate", OnTick)
function W.StartTicker()
    if driver:IsShown() then return end
    driver:Show()
end

-- ============================================================
-- ACTIONS
-- ============================================================
local function Channel(mtype)
    if mtype == "SAY" or mtype == "YELL" or mtype == "PARTY" or mtype == "RAID" or mtype == "RAID_WARNING" or mtype == "GUILD" or mtype == "WHISPER" or mtype == "EMOTE" then return mtype end
    if mtype == "SMARTRAID" then return IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil) end
    return nil
end
function W.SendMessage(w, text, mtype, dest)
    if type(text) ~= "string" or text == "" then return end
    local db = RM.DB()
    local msg = Substitute(text, w, w.D and w.D.fmt, 12, GetTime())
    msg = msg:gsub("|T[^|]*|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    if mtype == "PRINT" or mtype == nil then
        RM.Print(msg)
        return
    end
    if mtype == "ERROR" then
        if UIErrorsFrame then UIErrorsFrame:AddMessage(msg, 1, 0.1, 0.1) end
        return
    end
    if mtype == "COMBAT" then
        -- ZacUI's own scrolling text first. The game's combat text only with
        -- a real scroll function: a nil one makes its update throw every
        -- frame and freezes every line it shows ("-Combat" stuck on screen).
        local sbt = ns.SBT
        local scroll = COMBAT_TEXT_SCROLL_FUNCTION or CombatText_StandardScroll
        local ok, shown = false, nil
        if sbt and sbt.Display then ok, shown = pcall(sbt.Display, "notification", msg, { r = 1, g = 1, b = 1 }) end
        if ok and shown then
            -- shown
        elseif CombatText_AddMessage and type(scroll) == "function" then
            CombatText_AddMessage(msg, scroll, 1, 1, 1)
        else
            RM.Print(msg)
        end
        return
    end
    if mtype == "TTS" then
        RM.Speak(msg)
        return
    end
    if not (db and db.chat) then return end
    local ch = Channel(mtype)
    if not ch then return end
    if (ch == "SAY" or ch == "YELL") and not IsInInstance() then return end
    if ch == "RAID_WARNING" and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then ch = "RAID" end
    if ch == "RAID" and not IsInRaid() then ch = IsInGroup() and "PARTY" or nil end
    if not ch then return end
    if ch == "WHISPER" then
        local who = dest
        if type(who) == "string" then who = Substitute(who, w, nil, 12, GetTime()) end
        if not who or who == "" then return end
        pcall(SendChatMessage, msg, ch, nil, who)
    else
        pcall(SendChatMessage, msg, ch)
    end
end

-- what the core calls when a state appears (start) or goes (finish)
function RM.RunActions(inst, act, state, cloneId, isFinish)
    if not act then return end
    local db = RM.DB()
    local w = inst.widgets and inst.widgets[cloneId]
    inst.env.state = state
    inst.curWidget = w
    if act.sound and db and db.sounds then
        if act.sound_type == "Stop" then
            if StopSound and inst.soundHandle then StopSound(inst.soundHandle) end
        else
            -- "tts:..." speaks, "ui:..." is a game sound, a path a file
            local ok, h = RM.RaidSound(act.sound, act.sound_channel)
            if ok and h then inst.soundHandle = h end
        end
    end
    if act.stop_sound and StopSound and inst.soundHandle then StopSound(inst.soundHandle) end
    if act.message then
        local proxy = w or { inst = inst, state = state, cloneId = cloneId, D = inst.def.display or {} }
        W.SendMessage(proxy, act.message, act.message_type, act.message_dest)
    end
    if act.glow and act.glow.glow_action then
        local spec = act.glow
        local target
        if spec.glow_frame_type == "UNITFRAME" then
            target = RM.Layout and RM.Layout.UnitFrame and RM.Layout.UnitFrame(state and state.unit)
        elseif spec.glow_frame_type == "NAMEPLATE" then
            target = RM.Layout and RM.Layout.NamePlate and RM.Layout.NamePlate(state and state.unit)
        elseif spec.glow_frame_type == "FRAMESELECTOR" and type(spec.glow_frame) == "string" then
            target = _G[spec.glow_frame]
        else
            target = w
        end
        local owner = w or inst
        if target then
            if spec.glow_action == "hide" then W.HideGlow(owner, "act") else W.ShowGlow(owner, "act", target, spec) end
        end
    end
    if act.custom then
        SafeCall(inst, isFinish and "finish action" or "start action", act.custom, inst.env)
    end
    if isFinish then W.HideAllGlows(inst) end
end

-- ============================================================
-- RENDER: states -> widgets
-- ============================================================
local function Finish(w)
    -- play the finish animation, then release
    w.inst.widgets[w.cloneId] = nil
    if StartAnim(w, "finish") and w.anim then
        w.finishing = true
        W.StartTicker()
    else
        ReleaseNow(w)
    end
end

-- a text unit with nothing to say and no conditions (a controller)
-- never needs a frame
local function Silent(def)
    if def.silent ~= nil then return def.silent end
    local D = def.display
    local s = false
    if D and D.regionType == "text" and (D.displayText == nil or D.displayText == "") and not def.conditions then
        s = true
        for _, sub in ipairs(D.subRegions or {}) do
            if sub.type == "subtext" and sub.text_text and sub.text_text ~= "" then s = false break end
        end
    end
    def.silent = s
    return s
end
RM.IsSilent = Silent

function RM.Render(inst)
    local D = inst.def.display
    if not D or inst.def.kind == "none" or Silent(inst.def) then return end
    inst.widgets = inst.widgets or {}
    for cid, st in pairs(inst.states) do
        local w = inst.widgets[cid]
        if not w then
            w = Acquire(D.regionType or inst.def.kind)
            w.inst, w.cloneId, w.D = inst, cid, D
            w.state = st
            w.props, w.condActive, w.condKey = nil, nil, nil
            inst.widgets[cid] = w
            shown[w] = true
            w:Show()
            if RM.Layout and RM.Layout.Place then RM.Layout.Place(w) end
            W.Refresh(w)
            StartAnim(w, "start")
        elseif w.state ~= st or st.changed or w.finishing then
            -- A clone whose state table is the same object and carries no
            -- change flag is left alone: one raider's debuff moving used
            -- to restyle every clone of a raid-frame unit (fonts, anchors,
            -- borders), inline from the event. The core clears .changed
            -- after this pass, so the next change is seen.
            w.state = st
            W.Refresh(w)
        end
    end
    for cid, w in pairs(inst.widgets) do
        if not inst.states[cid] then Finish(w) end
    end
end

function RM.Release(inst)
    if not inst.widgets then return end
    for cid, w in pairs(inst.widgets) do
        inst.widgets[cid] = nil
        ReleaseNow(w)
    end
    W.HideAllGlows(inst)
end

-- every widget of a unit, restyled (the config page changed an option)
function W.RefreshAll()
    for w in pairs(shown) do
        if w.inst and not w.finishing then W.Refresh(w) end
    end
end

-- ============================================================
-- SAMPLES for the settings page's preview strip: a widget drawn by the
-- very Build / Setup / sub-text code above, from a display spec and a
-- made-up state - parented to the canvas, never pooled, never in the
-- layout, the draw loop or the conditions. The page's sample ticks it
-- from its own OnUpdate (which stops when the strip hides).
local SAMPLE_INST = { tstates = {}, def = {} }
function W.NewSample(parent, kind)
    local w = CreateFrame("Frame", nil, parent)
    w.kind = Build[kind] and kind or "empty"
    w.top = CreateFrame("Frame", nil, w)
    w.top:SetAllPoints(w)
    Build[w.kind](w)
    w.top:SetFrameLevel(w:GetFrameLevel() + 5)
    w.sample = true
    return w
end
-- A condition a sample may wear: one whose check reads only the made-up
-- states (time left, stacks, a field) - never a pack's own check code -
-- and only what it changes in the look: never a sound, a chat line, code
-- or a glow on another frame. So a sample bar dims and brightens with its
-- time left exactly as the pack's own does, and nothing else happens.
local function PureCheck(check)
    if check.trigger == -1 and check.variable == "customcheck" then return false end
    for _, c in ipairs(check.checks or {}) do
        if not PureCheck(c) then return false end
    end
    return true
end
local function SampleProps(w)
    local conds = w.inst and w.inst.def and w.inst.def.conditions
    if not conds then return nil end
    local props
    for _, c in ipairs(conds) do
        if c.check and PureCheck(c.check) and CondValue(w, c.check) then
            for _, chg in ipairs(c.changes or {}) do
                local prop = chg.property
                if prop and not ONE_SHOT[prop] and prop ~= "glowexternal" then
                    local v = chg.value
                    if v == nil then v = false end
                    props = props or {}
                    props[prop] = v
                end
            end
        end
    end
    return props
end
local function SameProps(a, b)
    if a == b then return true end
    if not (a and b) then return false end
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
-- inst (optional): the sample's own made-up unit - { tstates = { [n] =
-- { [""] = state } }, def = { order, conditions } } - for texts that read
-- another trigger ("%1.unitName"), the list order and the conditions.
function W.StyleSample(w, D, state, custom, inst)
    w.D, w.state, w.inst, w.custom = D, state, inst or SAMPLE_INST, custom
    w.props = SampleProps(w)
    local now = GetTime()
    Setup[w.kind](w)
    BuildSubTexts(w)
    ApplyTexts(w, now)
    BuildBorders(w)
    BuildSubGlows(w)
    local rem, total = Progress(state, now)
    if Tick[w.kind] then Tick[w.kind](w, now, rem, total) end
    if not w.anim then w:SetAlpha(tonumber(w.props and w.props.alpha) or tonumber(D.alpha) or 1) end
    -- the pick hook: an alert text, and each bar text by its role
    if ns.TagElement and w.kind == "text" and w.text then ns.TagElement(w.text, "raidmods.alertText") ns.TagElement(w, "raidmods.alertText") end
    if ns.TagElement and w.texts then
        for i, sub in ipairs(D.subRegions or {}) do
            local fs = w.texts[i]
            local role = fs and BarRole(w, sub.anchor_point or sub.text_anchorPoint or "CENTER")
            if role then ns.TagElement(fs, "raidmods." .. role) end
        end
    end
end
-- fast = true: what moves every frame (the bar fill, the swipe, the
-- animation); otherwise also the texts, the conditions and the glow pulse
-- (the live draw loop's 0.1 s beat)
function W.TickSample(w, fast)
    if not (w.D and w.state) then return end
    local now = GetTime()
    local rem, total = Progress(w.state, now)
    if Tick[w.kind] then Tick[w.kind](w, now, rem, total) end
    if w.anim then TickAnim(w, now) end
    if fast then return end
    if w.inst ~= SAMPLE_INST and w.inst.def and w.inst.def.conditions and not SameProps(SampleProps(w), w.props) then
        W.StyleSample(w, w.D, w.state, w.custom, w.inst)
        return
    end
    ApplyTexts(w, now, true)
    if w.glowFrames then
        for _, g in pairs(w.glowFrames) do
            if not g.lcg then g:SetAlpha(GlowAlpha(g, now)) end
        end
    end
end
-- The sample's arrival, as a live widget arrives: its start animation,
-- then its main loop (the pulse, the bounce) for as long as it shows.
-- Ticked by W.TickSample; the live draw loop never sees it.
function W.PlaySample(w)
    if not (w.D and w.state) then return end
    local now = GetTime()
    local spec = AnimSpec(w, "start")
    if spec and spec.dur > 0 then
        w.anim = { phase = "start", spec = spec, t0 = now }
    else
        local m = AnimSpec(w, "main")
        w.anim = m and { phase = "main", spec = m, t0 = now } or nil
        ApplyAnimFrame(w, 1, 1, 0, 0)
    end
    if w.anim then TickAnim(w, now) end
end
-- At rest for a moment (the page measures it); its animation carries on
-- from the next tick.
function W.RestSample(w)
    if w.anim then ApplyAnimFrame(w, 1, 1, 0, 0) end
end
-- A sample put away: at rest, no glow left on it.
function W.StopSample(w)
    if w.anim then
        w.anim = nil
        ApplyAnimFrame(w, 1, 1, 0, 0)
    end
    W.HideAllGlows(w)
end

-- ============================================================
-- THE REGION PROXY the ported code sees as aura_env.region
-- ============================================================
local dummyFrame = CreateFrame("Frame", nil, UIParent)
dummyFrame:Hide()
local dummyTex = dummyFrame:CreateTexture(nil, "ARTWORK")
RM.SetRegionFactory(function(inst)
    local proxy = {}
    local function Cur() return inst.curWidget or (inst.widgets and next(inst.widgets) and select(2, next(inst.widgets))) end
    proxy.Color = function(_, r, g, b, a)
        local w = Cur()
        if not w then return end
        w.forcedColor = { r, g, b, a }
        if w.bar and w.kind == "aurabar" then w.bar:SetStatusBarColor(r or 1, g or 1, b or 1, a or 1)
        elseif w.icon then w.icon:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
        elseif w.text then w.text:SetTextColor(r or 1, g or 1, b or 1, a or 1)
        elseif w.tex then w.tex:SetVertexColor(r or 1, g or 1, b or 1, a or 1) end
    end
    proxy.GetColor = function()
        local w = Cur()
        if w and w.forcedColor then return unpack(w.forcedColor) end
        return 1, 1, 1, 1
    end
    proxy.SetDesaturated = function(_, v)
        local w = Cur()
        if w and w.icon then w.icon:SetDesaturated(v and true or false) end
    end
    proxy.bar = setmetatable({}, { __index = function(_, k)
        local w = Cur()
        local bar = w and w.bar
        if k == "spark" then return w and w.spark or dummyTex end
        if k == "SetVertexColor" or k == "SetForegroundColor" then
            return function(_, r, g, b, a) if bar then bar:SetStatusBarColor(r or 1, g or 1, b or 1, a or 1) end end
        end
        if k == "SetBackgroundColor" then
            return function(_, r, g, b, a) if w and w.bg then w.bg:SetVertexColor(r or 1, g or 1, b or 1, a or 1) end end
        end
        if k == "SetTexture" or k == "SetStatusBarTexture" then
            return function(_, t) if bar then bar:SetStatusBarTexture(t) end end
        end
        if k == "SetBackgroundTexture" then
            return function(_, t) if w and w.bg then w.bg:SetTexture(t) end end
        end
        if k == "bg" then return w and w.bg or dummyTex end
        if k == "fg" then return bar and bar:GetStatusBarTexture() or dummyTex end
        if bar and type(bar[k]) == "function" then return function(_, ...) return bar[k](bar, ...) end end
        if type(k) == "string" and k:match("^%u") then return function() end end
        return nil
    end })
    setmetatable(proxy, { __index = function(_, k)
        local w = Cur()
        if k == "width" then return w and w:GetWidth() or (inst.def.display and inst.def.display.width) or 0 end
        if k == "height" then return w and w:GetHeight() or (inst.def.display and inst.def.display.height) or 0 end
        if k == "icon" then return w and w.icon or dummyTex end
        if k == "bg" or k == "texture" then return w and (w.bg or w.tex or w.bgTex) or dummyTex end
        if k == "text" then return w and w.text end
        if k == "state" then return w and w.state end
        if k == "states" then return inst.states end
        if k == "id" then return inst.id end
        if w and type(w[k]) == "function" then return function(_, ...) return w[k](w, ...) end end
        if w then return w[k] end
        return nil
    end })
    return proxy
end)
