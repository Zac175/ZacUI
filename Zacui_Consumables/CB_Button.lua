-- CB_Button - one bar button and its look: the icon, its edge, the three
-- cooldown swirls, every text (count, cooldown, global cooldown, eating /
-- casting, running out, minutes left, weapon slot, item name), the
-- weapon's stone badge and enchant border, the expiry glow. And the pass
-- that keeps it current (CB.Tick): cooldown > cast > global cooldown >
-- eating > running out, the same order Readycheck's bars use.
-- The live bars dress secure buttons with it; the settings preview
-- plain ones. Both read the same settings, so they look the same.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end
local D, CB = ns.ConsData, ns.ConsBars
if not (D and CB) then return end

local FLAT = ns.FLAT or "Interface\\Buttons\\WHITE8X8"
local math_floor, math_max, math_ceil, math_abs = math.floor, math.max, math.ceil, math.abs
local string_format, tonumber, type, pairs, ipairs = string.format, tonumber, type, pairs, ipairs

local B = {}
CB.Button = B

-- ============================================================
-- THE LOOK'S DEFAULTS (what each piece always looked like)
-- ============================================================
-- text: size max(min, floor(button * k)) or fixed, shadow depth
B.TEXT = {
    count = { min = 8, k = 0.33, sh = 1, label = "Stack count", sample = "12" },
    cooldown = { min = 12, k = 0.55, sh = 2, label = "Cooldown", sample = "47" },
    gcd = { min = 14, k = 0.6, sh = 3, label = "Global cooldown", sample = "1" },
    duration = { min = 14, k = 0.6, sh = 3, label = "Eating and casting", sample = "18" },
    expiry = { min = 12, k = 0.5, sh = 2, label = "Running out", sample = "42" },
    timer = { min = 10, k = 0.33, sh = 1, label = "Minutes left", sample = "28" },
    slot = { min = 7, k = 0.25, sh = 1, label = "Weapon slot", sample = "MH  OH" },
    name = { fixed = 7, sh = 1, label = "Item names", sample = "Mongoose" },
}
B.ELEMS = { "count", "cooldown", "gcd", "duration", "expiry", "timer", "slot", "name" }
B.FIELD = { count = "count", cooldown = "cooldownText", gcd = "gcdText", duration = "durationText",
    expiry = "expiryText", timer = "timeText", slot = "slotLabel", name = "nameLabel" }
B.DESC = {
    count = "How many you carry, in the bottom corner.",
    cooldown = "Seconds left on the item's own cooldown, in the middle.",
    gcd = "The short countdown right after you click a button.",
    duration = "The countdown while you eat, drink or put on a stone or oil.",
    expiry = "The big seconds once a buff is inside its warning time; red in the last half.",
    timer = "The minutes left on a weapon's stone or oil, in the top corner.",
    slot = "MH, OH or B on the weapon buttons.",
    name = "The short item name across the top, when names are on.",
}
-- the text colours (style.<key>; nil = these)
B.COLOR_DEFAULTS = {
    countColor = { r = 1, g = 1, b = 1, a = 1 }, emptyColor = { r = 1, g = 0.2, b = 0.2, a = 1 },
    cooldownColor = { r = 1, g = 1, b = 1, a = 1 }, gcdColor = { r = 1, g = 1, b = 1, a = 1 },
    durationColor = { r = 1, g = 1, b = 0, a = 1 },
    expirySoonColor = { r = 1, g = 0.82, b = 0, a = 1 }, expiryUrgentColor = { r = 1, g = 0.4, b = 0.4, a = 1 },
    timerGoodColor = { r = 0.4, g = 1, b = 0.4, a = 1 }, timerMidColor = { r = 1, g = 0.82, b = 0, a = 1 },
    timerLowColor = { r = 1, g = 0.4, b = 0.4, a = 1 },
    nameColor = { r = 1, g = 1, b = 1, a = 1 }, slotColor = { r = 1, g = 1, b = 1, a = 1 },
    bagSlotColor = { r = 0.3, g = 0.6, b = 1, a = 1 },
    glowColor = { r = 1, g = 0.5, b = 0, a = 1 },
}
B.TEXT_COLORS = {
    count = { { "countColor", "Count colour" }, { "emptyColor", "Colour when you have none" } },
    cooldown = { { "cooldownColor", "Cooldown colour" } }, gcd = { { "gcdColor", "Global cooldown colour" } },
    duration = { { "durationColor", "Eating and casting colour" } },
    expiry = { { "expirySoonColor", "Running low colour" }, { "expiryUrgentColor", "Nearly gone colour" } },
    timer = { { "timerGoodColor", "Plenty left colour" }, { "timerMidColor", "Under five minutes colour" },
        { "timerLowColor", "Under a minute colour" } },
    name = { { "nameColor", "Item name colour" } },
    slot = { { "slotColor", "Weapon slot colour" }, { "bagSlotColor", "Bag weapon colour" } },
}
-- the bar's own colours (colors.<key>; nil = these, or the theme's)
B.BAR_COLOR_DEFAULTS = {
    frameBorder = { r = 0.5, g = 0.8, b = 1, a = 0.3 },
    accentLine = { r = 0.5, g = 0.8, b = 1, a = 0.5 },
    buttonBorder = { r = 0, g = 0, b = 0, a = 1 },
    activeBorder = { r = 0.3, g = 0.9, b = 0.3, a = 1 },
    conflictBackground = { r = 0.3, g = 0.15, b = 0.1, a = 0.9 },
    conflictBorder = { r = 0.8, g = 0.4, b = 0.2, a = 1 },
    elementalStone = { r = 0.2, g = 0.7, b = 1, a = 1 },
    consecratedStone = { r = 1, g = 0.85, b = 0.4, a = 1 },
    denseStone = { r = 0.7, g = 0.7, b = 0.7, a = 1 },
    frostOil = { r = 0.4, g = 0.8, b = 1, a = 1 },
    enchanted = { r = 0, g = 1, b = 0.5, a = 1 },
}
function B.BarColor(cfg, key)
    local c = CB.T(cfg, "colors") and cfg.colors[key]
    if type(c) == "table" then return ns.ColorOf(c) end
    if key == "frameBackground" then
        local t = ns.GetColor and ns.GetColor("ui", "windowBg") or { r = 0.08, g = 0.08, b = 0.08, a = 0.95 }
        return t.r, t.g, t.b, t.a or 0.95
    end
    return ns.ColorOf(B.BAR_COLOR_DEFAULTS[key] or { r = 1, g = 1, b = 1, a = 1 })
end
-- per-state looks (states.<id>, ZacUI's state shape): the button's fill
-- (color), the icon's opacity (alpha), grey (desat), its edge (border)
B.STATES = { { id = "normal", label = "Ready" }, { id = "unavailable", label = "None in the bags" },
    { id = "active", label = "Buff up" }, { id = "conflict", label = "A clashing buff is up" } }
function B.StateDefaults(cfg)
    local function C(k) local r, g, b, a = B.BarColor(cfg, k) return { r = r, g = g, b = b, a = a } end
    return {
        normal = { color = { r = 0, g = 0, b = 0, a = 1 }, alpha = 1, desat = false, border = C("buttonBorder") },
        unavailable = { color = { r = 0.6, g = 0.1, b = 0.1, a = 1 }, alpha = 0.4, desat = true, border = C("buttonBorder") },
        active = { color = { r = 0.1, g = 0.5, b = 0.1, a = 1 }, alpha = 1, desat = false, border = C("activeBorder") },
        conflict = { color = C("conflictBackground"), alpha = 0.7, desat = false, border = C("conflictBorder") },
    }
end
B.GLOW_ANIM = { style = "flash", duration = 1.6, loop = true }
B.BAR_ANIM = { style = "none", duration = 0.3 }
B.GLOW_SCALE, B.FADE_IN, B.FADE_OUT = 1.5, 0.18, 0.30
-- where each text sits on its button (anchors.<elem> on top)
local function A(p, x, y, j) return { point = p, relPoint = p, x = x, y = y, to = "button", justify = j } end
B.ANCHOR_DEFAULTS = {
    count = A("BOTTOMRIGHT", -1, 1), cooldown = A("CENTER", 3, 0), gcd = A("CENTER", 0, 0),
    duration = A("CENTER", 0, 0), expiry = A("CENTER", 0, 0), timer = A("TOPRIGHT", -1, -1),
    slot = A("TOPLEFT", 2, -2),
    name = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 2, y = -2, to = "button", justify = "CENTER",
        point2 = "TOPRIGHT", relPoint2 = "TOPRIGHT", x2 = -2, y2 = -2, to2 = "button" },
    glow = A("CENTER", 0, 0), badge = A("BOTTOMLEFT", 2, 2),
}
local NAME_WEAPON = A("TOPLEFT", 2, -12, "LEFT")
function B.AnchorDefault(elem, data)
    if elem == "name" and data and (data.slot or data.bagWeapon or data.unified) then return NAME_WEAPON end
    return B.ANCHOR_DEFAULTS[elem]
end
B.ANCHOR_TARGETS = { { value = "button", text = "The button" }, { value = "count", text = "Stack count" },
    { value = "cooldown", text = "Cooldown" }, { value = "timer", text = "Minutes left" },
    { value = "slot", text = "Weapon slot" }, { value = "name", text = "Item names" } }
-- the words for the times (formats.<cooldown|expiry|timer>; nil = these)
B.FORMAT_DEFAULTS = { cooldown = { time = "short" }, expiry = { time = "seconds" }, timer = { time = "short" } }
-- only the consumables bar has a glow until it is switched on
B.GLOW_BARS = { main = true }

local EMPTY = {}
local function Style(cfg) return CB.T(cfg, "style") or EMPTY end
B.Style = Style
function B.FontDefaults(elem, size)
    local t = B.TEXT[elem]
    local s = t.fixed or math_max(t.min, math_floor((size or 36) * t.k))
    return { size = s, outline = "outline", shadow = true, shadowX = t.sh, shadowY = -t.sh }
end
function B.Color(cfg, key)
    local c = Style(cfg)[key]
    if type(c) == "table" then return ns.ColorOf(c) end
    return ns.ColorOf(B.COLOR_DEFAULTS[key] or EMPTY)
end
function B.GlowOn(key, cfg)
    local v = Style(cfg).glowEnabled
    if v == nil then return B.GLOW_BARS[key] == true end
    return v and true or false
end
function B.Spec(cfg, which)
    local s = Style(cfg)[which]
    local d = (which == "glowAnim") and B.GLOW_ANIM or B.BAR_ANIM
    if ns.Motion and ns.Motion.Normalize then return ns.Motion.Normalize(type(s) == "table" and s or nil, d) end
    return type(s) == "table" and s or d
end
function B.FadeTimes(cfg)
    local s = Style(cfg)
    return tonumber(s.fadeIn) or B.FADE_IN, tonumber(s.fadeOut) or B.FADE_OUT
end

-- ============================================================
-- BUILDING A BUTTON
-- ============================================================
local function Font(parent, layer, sub)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    -- a font from the start: the game refuses text on a string without one
    if ns.ApplyFontSpec then ns.ApplyFontSpec(fs, nil, { size = 12, outline = "outline" })
    else fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "OUTLINE") end
    if sub and fs.SetDrawLayer then fs:SetDrawLayer(layer or "OVERLAY", sub) end
    return fs
end
local function Strips(frame, layer, sub)
    local s = {}
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
        local t = frame:CreateTexture(nil, layer or "OVERLAY", nil, sub)
        t:SetTexture(FLAT)
        if side == "top" or side == "bottom" then
            local p = side:upper()
            t:SetPoint(p .. "LEFT") t:SetPoint(p .. "RIGHT") t:SetHeight(1)
        else
            local p = side:upper()
            t:SetPoint("TOP" .. p) t:SetPoint("BOTTOM" .. p) t:SetWidth(1)
        end
        s[side] = t
    end
    return s
end
B.Strips = Strips
local function EachStrip(s, fn) for _, k in ipairs({ "top", "bottom", "left", "right" }) do if s[k] then fn(s[k], k) end end end
B.EachStrip = EachStrip
local function Cooldown(button, level)
    local c = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    c:SetAllPoints(button.icon)
    if c.SetDrawSwipe then c:SetDrawSwipe(true) end
    if c.SetHideCountdownNumbers then c:SetHideCountdownNumbers(true) end
    c:SetFrameLevel(button:GetFrameLevel() + level)
    c:Hide()
    return c
end

-- every part on a button (a secure live one or a plain sample); preview
-- tags the parts for "pick in the preview"
function B.Dress(button, preview)
    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints()
    button.bg:SetTexture(FLAT)
    button.bg:SetVertexColor(0, 0, 0, 1)
    local icon = button:CreateTexture(nil, "BORDER")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.icon = icon
    local hl = button:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -1) hl:SetPoint("BOTTOMRIGHT", -1, 1)
    hl:SetTexture(FLAT) hl:SetVertexColor(1, 1, 1, 0.12)
    if hl.SetBlendMode then hl:SetBlendMode("ADD") end
    if button.SetHighlightTexture then button:SetHighlightTexture(hl) end
    local pushed = button:CreateTexture(nil, "ARTWORK")
    pushed:SetPoint("TOPLEFT", 1, -1) pushed:SetPoint("BOTTOMRIGHT", -1, 1)
    pushed:SetTexture(FLAT) pushed:SetVertexColor(0, 0, 0, 0.5)
    if button.SetPushedTexture then button:SetPushedTexture(pushed) end
    -- the edge, on a frame of its own above the swirls
    local ef = CreateFrame("Frame", nil, button)
    ef:SetAllPoints()
    ef:SetFrameLevel(button:GetFrameLevel() + 2)
    button.edgeFrame = ef
    button.edge = Strips(ef, "OVERLAY", 1)
    -- the global cooldown (with its edge), the item's cooldown, the cast
    -- (reversed, on top): three swirls that can run at once
    button.gcdFrame = Cooldown(button, 2)
    if button.gcdFrame.SetDrawEdge then button.gcdFrame:SetDrawEdge(true) end
    button.cooldownFrame = Cooldown(button, 2)
    button.castFrame = Cooldown(button, 3)
    if button.castFrame.SetReverse then button.castFrame:SetReverse(true) end
    -- every text sits on this, above the swirls
    local over = CreateFrame("Frame", nil, button)
    over:SetAllPoints(button)
    over:SetFrameLevel(button:GetFrameLevel() + 5)
    button.over = over
    for _, e in ipairs(B.ELEMS) do
        local fs = Font(over, "OVERLAY", 6)
        fs:Hide()
        button[B.FIELD[e]] = fs
        if preview and ns.TagElement then ns.TagElement(fs, "consbars.text." .. e) end
    end
    button.nameLabel:SetWordWrap(false)
    if button.nameLabel.SetJustifyV then button.nameLabel:SetJustifyV("TOP") end
    -- the weapon's stone badge, bottom left
    local badge = CreateFrame("Frame", nil, button)
    badge:SetFrameLevel(button:GetFrameLevel() + 4)
    badge.bg = badge:CreateTexture(nil, "OVERLAY")
    badge.bg:SetAllPoints() badge.bg:SetTexture(FLAT) badge.bg:SetVertexColor(0, 0, 0, 0.8)
    badge.icon = badge:CreateTexture(nil, "OVERLAY", nil, 1)
    badge.icon:SetPoint("TOPLEFT", 1, -1) badge.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    badge.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    badge:Hide()
    button.badge = badge
    if preview and ns.TagElement then ns.TagElement(badge.icon, "consbars.part.badge") end
    -- the enchant border (a weapon with a stone on, coloured by the stone)
    local ab = CreateFrame("Frame", nil, button)
    ab:SetAllPoints()
    ab:SetFrameLevel(button:GetFrameLevel() + 4)
    button.applied = Strips(ab, "OVERLAY", 7)
    EachStrip(button.applied, function(t) t:Hide() end)
    -- the hover ring
    local hf = CreateFrame("Frame", nil, button)
    hf:SetAllPoints()
    hf:SetFrameLevel(button:GetFrameLevel() + 5)
    button.hover = Strips(hf, "OVERLAY", 7)
    EachStrip(button.hover, function(t) t:Hide() end)
    -- the expiry glow: a ring on its own frame, from its centre
    local gf = CreateFrame("Frame", nil, button)
    gf:SetPoint("CENTER", button, "CENTER", 0, 0)
    gf:SetFrameLevel(button:GetFrameLevel() + 4)
    gf.tex = gf:CreateTexture(nil, "OVERLAY")
    gf.tex:SetPoint("CENTER")
    gf.tex:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
    gf.tex:SetTexCoord(0.0078125, 0.5078125, 0.27734375, 0.52734375)
    if gf.tex.SetBlendMode then gf.tex:SetBlendMode("ADD") end
    gf:Hide()
    button.glow = gf
    if preview and ns.TagElement then
        ns.TagElement(icon, "consbars.button") ns.TagElement(gf.tex, "consbars.part.glow")
    end
    button.anchorTo = function(k)
        if k == "button" then return button elseif k == "glow" then return gf end
        local f = B.FIELD[k]
        return f and button[f] or nil
    end
    return button
end

-- one hover ring colour for every button
function B.SetHover(button, on)
    local c = ns.GetColor and ns.GetColor("ui", "borderHover") or { r = 0.85, g = 0.65, b = 0.25 }
    EachStrip(button.hover, function(t)
        t:SetVertexColor(c.r, c.g, c.b, 1)
        t:SetShown(on and true or false)
    end)
end

-- ============================================================
-- STYLE - size, fonts, colours, where the texts sit (once per change)
-- ============================================================
B.gen = 0
function B.Restyle() B.gen = B.gen + 1 end
local defs = setmetatable({}, { __mode = "k" })
function B.Apply(button, key, cfg, size)
    size = size or CB.Geo(cfg)
    local sig = size .. ":" .. B.gen
    local data = button.data or EMPTY
    local weaponish = (data.slot or data.bagWeapon or data.unified) and true or false
    sig = sig .. (weaponish and "w" or "")
    if button._zSig == sig then return end
    button._zSig = sig
    local st = Style(cfg)
    local anchors = CB.T(cfg, "anchors")
    for _, e in ipairs(B.ELEMS) do
        local fs = button[B.FIELD[e]]
        ns.ApplyFontSpec(fs, type(st[e .. "Font"]) == "table" and st[e .. "Font"] or nil, B.FontDefaults(e, size))
        fs._cachedText, fs._ck = nil, nil
        local d = defs[fs]
        if not d then d = {} defs[fs] = d end
        local src = B.AnchorDefault(e, data)
        for k in pairs(d) do d[k] = nil end
        for k, v in pairs(src) do d[k] = v end
        local _, two = ns.ApplyAnchor(fs, anchors and anchors[e], d, button.anchorTo)
        if e == "name" and not two then fs:SetWidth(math_max(10, size - 4)) end
    end
    button.nameLabel:SetHeight(10)
    button.cooldownText:SetTextColor(B.Color(cfg, "cooldownColor"))
    button.gcdText:SetTextColor(B.Color(cfg, "gcdColor"))
    button.durationText:SetTextColor(B.Color(cfg, "durationColor"))
    button.nameLabel:SetTextColor(B.Color(cfg, "nameColor"))
    button.slotLabel:SetTextColor(B.Color(cfg, data.bagWeapon and "bagSlotColor" or "slotColor"))
    -- the badge and the glow follow the size
    local bs = math_max(10, math_floor(size * 0.33))
    button.badge:SetSize(bs, bs)
    local bd = defs[button.badge] or {}
    defs[button.badge] = bd
    for k, v in pairs(B.ANCHOR_DEFAULTS.badge) do bd[k] = v end
    ns.ApplyAnchor(button.badge, anchors and anchors.badge, bd, button.anchorTo)
    local k = tonumber(st.glowScale) or B.GLOW_SCALE
    button.glow:SetSize(size, size)
    button.glow.tex:SetSize(size * k, size * k)
    button.glow.tex:SetVertexColor(B.Color(cfg, "glowColor"))
    local gd = defs[button.glow] or {}
    defs[button.glow] = gd
    for kk, v in pairs(B.ANCHOR_DEFAULTS.glow) do gd[kk] = v end
    ns.ApplyAnchor(button.glow, anchors and anchors.glow, gd, button.anchorTo)
    button._zStateKey = nil
end

-- ============================================================
-- WHAT A BUTTON SHOWS
-- ============================================================
-- the face: a bag weapon's own icon, a hand button's weapon (or its stone)
function B.IconFor(id, data, w, weaponIcons)
    if data.bagWeapon and data.weaponTexture then return data.weaponTexture end
    if data.unified then
        if weaponIcons ~= false and data.weaponTexture then return data.weaponTexture end
        return w.ItemIcon(data.baseItemId) or 134400
    end
    return w.ItemIcon(data.baseItemId or id) or data.icon or 134400
end

-- once per rebuild: the item it is, its face, the labels and badge
function B.Fill(button, e, key, cfg, w)
    local data = e.data
    local changedKind = (button.data and ((button.data.slot ~= nil) ~= (data.slot ~= nil))) or false
    button.itemId, button.data, button.entry, button.barKey = e.id, data, e, key
    if changedKind then button._zSig = nil end
    B.Apply(button, key, cfg)
    local tex = B.IconFor(e.id, data, w, CB.Cfg().weaponIcons)
    if button.icon:GetTexture() ~= tex then button.icon:SetTexture(tex) end
    -- the hand / bag tag and which stone goes on
    if data.slot then
        button.slotLabel:SetText(data.bagWeapon and "B" or (data.slot == "mainhand" and "MH") or (data.slot == "offhand" and "OH")
            or data.slot:upper():sub(1, 2))
        button.slotLabel:SetTextColor(B.Color(cfg, data.bagWeapon and "bagSlotColor" or "slotColor"))
        button.slotLabel:Show()
        local si = w.ItemIcon(data.baseItemId)
        if si then button.badge.icon:SetTexture(si) button.badge:Show() else button.badge:Hide() end
    else
        button.slotLabel:Hide()
        button.badge:Hide()
    end
    -- the name across the top (the weapon buttons of the consumables bar never)
    local name = D.ShortName(data.displayName or data.name)
    local fmt = CB.T(cfg, "formats") and cfg.formats.name
    if fmt and ns.FormatName then name = ns.FormatName(data.displayName or data.name or "", fmt) end
    button.nameLabel:SetText(name or "")
    local showName = cfg.showItemNames and true or false
    if key == "main" and (data.unified or data.bagWeapon) then showName = false end
    button.nameLabel:SetShown(showName)
    -- the count
    B.PaintCount(button, cfg, e.count)
    button.count:SetShown(cfg.showCount ~= false)
    B.PaintState(button, key, cfg, e)
end

function B.PaintCount(button, cfg, n)
    local fs = button.count
    local t = (n and n > 0) and tostring(n) or "0"
    if fs._cachedText ~= t then fs:SetText(t) fs._cachedText = t fs._ck = nil end
    local ck = (n and n > 0) and "have" or "none"
    if fs._ck ~= ck then
        fs:SetTextColor(B.Color(cfg, ck == "have" and "countColor" or "emptyColor"))
        fs._ck = ck
    end
end

-- the four states: none in the bags, buff up, a clashing buff up, ready
function B.StateOf(e)
    if (e.count or 0) == 0 and not e.hasBuff then return "unavailable" end
    if e.hasBuff then return "active" end
    if e.hasConflictBuff and e.conflictItemId ~= e.id then return "conflict" end
    return "normal"
end
local SV = function(st, name, f, d) return ns.StateValue(st, name, f, d) end
function B.PaintState(button, key, cfg, e)
    local name = B.StateOf(e)
    -- the weapon bar has no clash state
    if key == "weapons" and name == "conflict" then name = "normal" end
    if button._zStateKey == name then return end
    button._zStateKey = name
    local states, dflt = CB.T(cfg, "states"), B.StateDefaults(cfg)
    button.bg:SetVertexColor(ns.ColorOf(SV(states, name, "color", dflt)))
    button.icon:SetDesaturated(SV(states, name, "desat", dflt) and true or false)
    button._zIconAlpha = tonumber(SV(states, name, "alpha", dflt)) or 1
    button.icon:SetAlpha(button._zHidden and 0 or button._zIconAlpha)
    local r, g, b, a = ns.ColorOf(SV(states, name, "border", dflt))
    EachStrip(button.edge, function(t) t:SetVertexColor(r, g, b, a) end)
    local an = SV(states, name, "anim", dflt)
    if button._zLastState and button._zLastState ~= name and type(an) == "table" and ns.Motion and ns.Motion.Play
        and button.over then
        ns.Motion.Play(button.over, an, "update")
    end
    button._zLastState = name
end

-- hidden for the rest of the fight (used up, or on its cooldown): only
-- alpha moves - the button is a secure one
function B.SetHidden(button, on)
    button._zHidden = on and true or nil
    local a = on and 0 or 1
    button:SetAlpha(a)
    button.icon:SetAlpha(on and 0 or (button._zIconAlpha or 1))
end

-- ============================================================
-- TEXTS THAT TICK
-- ============================================================
local fmtValues, fmtKinds = {}, { value = "time" }
local function Fmt(cfg, elem, sec)
    local f = CB.T(cfg, "formats") and cfg.formats[elem]
    if not f then return nil end
    fmtValues.value = sec
    return ns.FormatText(f, B.FORMAT_DEFAULTS[elem], fmtValues, fmtKinds, "value")
end
B.FormatTime = Fmt
local function SetText(fs, t) if fs._cachedText ~= t then fs:SetText(t) fs._cachedText = t end end
local function Clear(fs) fs:Hide() fs._cachedText, fs._ck = nil, nil end

function B.CooldownText(button, cfg, rem)
    local t = Fmt(cfg, "cooldown", rem)
    if not t then t = rem > 60 and string_format("%dm", math_ceil(rem / 60)) or string_format("%d", math_ceil(rem)) end
    SetText(button.cooldownText, t)
    button.cooldownText:Show()
end
function B.ExpiryText(button, cfg, rem, thr, chargeText)
    local fs = button.expiryText
    SetText(fs, chargeText or Fmt(cfg, "expiry", rem) or string_format("%d", math_ceil(rem)))
    local ck = rem < (thr or 60) * 0.5 and "urgent" or "soon"
    if fs._ck ~= ck then fs:SetTextColor(B.Color(cfg, ck == "urgent" and "expiryUrgentColor" or "expirySoonColor")) fs._ck = ck end
    fs:Show()
end
-- the corner minutes on a weapon: green, gold under five minutes, red under one
function B.TimerText(button, cfg, rem)
    local fs = button.timeText
    local t = Fmt(cfg, "timer", rem)
    if not t then
        -- (the consumables bar's hand buttons count hours past an hour)
        if button.barKey == "main" and rem >= 3600 then t = tostring(math_floor(rem / 3600))
        else t = tostring(math_ceil(rem / 60)) end
    end
    SetText(fs, t)
    local ck = (rem < 60 and "low") or (rem < 300 and "mid") or "good"
    if fs._ck ~= ck then
        fs:SetTextColor(B.Color(cfg, ck == "low" and "timerLowColor" or ck == "mid" and "timerMidColor" or "timerGoodColor"))
        fs._ck = ck
    end
    fs:Show()
end

function B.Glow(button, key, cfg, on)
    local f = button.glow
    local M = ns.Motion
    if on and B.GlowOn(key, cfg) then
        if not f:IsShown() then
            f:Show()
            if M then M.Play(f, B.Spec(cfg, "glowAnim"), "update") end
        elseif M and not M.IsPlaying(f) then
            local spec = B.Spec(cfg, "glowAnim")
            if spec.loop and spec.style ~= "none" then M.Play(f, spec, "update") end
        end
    elseif f:IsShown() then
        if M then M.Stop(f) end
        f:Hide()
    end
end

-- the stone-coloured border of an enchanted weapon
local STONE_COLOR = { [18262] = "elementalStone", [23122] = "consecratedStone", [12404] = "denseStone", [3829] = "frostOil" }
function B.Applied(button, cfg, on, enchantId)
    if not on then
        if button._zApplied then
            button._zApplied = nil
            EachStrip(button.applied, function(t) t:Hide() end)
        end
        return
    end
    local stone = enchantId and D.ENCHANT_TO_STONE[enchantId]
    local k = (stone and STONE_COLOR[stone]) or "enchanted"
    if button._zApplied ~= k then
        button._zApplied = k
        local r, g, b, a = B.BarColor(cfg, k)
        EachStrip(button.applied, function(t) t:SetVertexColor(r, g, b, a) t:Show() end)
    end
end

-- ============================================================
-- THE TICK - one button, now. ctx: { now, eating, eatLeft, gcdLeft,
-- gcdDur, lastUse, lastUseId, cast = { name, start, stop } }
-- ============================================================
local function Swirl(cd, start, dur, field, button)
    if not cd:IsShown() or button[field] ~= start then
        cd:SetCooldown(start, dur)
        cd:Show()
        button[field] = start
    end
end

-- what this button's buff / enchant is doing: has, seconds left, enchant id, charges low
local function OwnState(button, w)
    local data = button.data or EMPTY
    local cid = data.baseItemId or button.itemId
    if data.bagWeapon then
        local h, r = w.BagEnchant(data.bag, data.bagSlot)
        return h, r
    elseif data.slot == "mainhand" or data.slot == "offhand" then
        local h, r, eid, ch, low = w.Enchant(data.slot)
        return h, r, eid, low and ch
    end
    local it = D.BY_ID[cid] or data
    if it.buffId then return w.Buff(it.buffId) end
    return false, 0
end
B.OwnState = OwnState

function B.Tick(button, key, cfg, w, ctx, force)
    local data = button.data or EMPTY
    local id = button.itemId
    local now = ctx.now
    local cid = data.baseItemId or id
    local cs, cd = w.Cooldown(cid)
    -- idle buttons are skipped: nothing live now, nothing live last time
    if not force then
        local live = (cs > 0 and cd > 1.5 and cs + cd - now > 0)
            or (ctx.lastUse and now - ctx.lastUse < 1.7)
            or button.gcdFrame:IsShown() or button.castFrame:IsShown()
            or (ctx.eating and id == ctx.lastUseId)
        if not live then live = (OwnState(button, w)) and true or false end
        if not live and not button._zLive and not button._zCdHidden then return end
        button._zLive = live
    end

    -- the enchant border on the hand / bag buttons
    if data.slot then
        local h, _, eid = OwnState(button, w)
        B.Applied(button, cfg, h, eid)
    end

    -- the item's own cooldown (over 15 s) or the global one right after a click
    local cdLeft, gLeft, gDur = 0, 0, 0
    if cs > 0 and cd > 0 then
        local r = cs + cd - now
        if r > 0 then
            if cd > 15 then cdLeft = r
            elseif button._zGcdStart == cs then gLeft, gDur = r, cd
            elseif ctx.lastUse and math_abs(cs - ctx.lastUse) < 1.6 then
                gLeft, gDur = r, cd
                button._zGcdStart = cs
            end
        else button._zGcdStart = nil end
    else button._zGcdStart = nil end

    -- an item on its cooldown leaves the consumables bar for the fight
    if key == "main" and cfg.hideUsedInCombat ~= false then
        if cdLeft > 0 and w.InCombat() then
            if not button._zCdHidden then button._zCdHidden = true B.SetHidden(button, true) end
        elseif button._zCdHidden then
            button._zCdHidden = nil
            if not button._zSpent then B.SetHidden(button, false) end
        end
    end

    if cdLeft > 0 then
        Swirl(button.cooldownFrame, cs, cd, "_zCdStart", button)
        B.CooldownText(button, cfg, cdLeft)
        Clear(button.gcdText) button.gcdFrame:Hide() Clear(button.durationText) Clear(button.expiryText)
        return
    end
    button.cooldownFrame:Hide()
    Clear(button.cooldownText)

    -- a cast this button started (a stone going on, a displacer, eating)
    local c = ctx.cast
    if c and c.name then
        local sl = c.name:lower()
        local mine = false
        if data.slot and (sl:find("sharpen weapon", 1, true) or sl:find("consecrated", 1, true)) then mine = true end
        if button.entry and button.entry.category == "chronoboon" and sl:find("chronoboon", 1, true) then mine = true end
        local cat = button.entry and button.entry.category
        if (cat == "food" or cat == "drinks") and ctx.eating then mine = true end
        local left, dur = c.stop - now, c.stop - c.start
        if mine and left > 0 and dur > 0 then
            Swirl(button.castFrame, c.start, dur, "_zCastStart", button)
            SetText(button.durationText, string_format("%d", math_ceil(left)))
            button.durationText:Show()
            button.gcdFrame:Hide() Clear(button.gcdText) Clear(button.expiryText)
            return
        end
    end
    if button.castFrame:IsShown() then button.castFrame:Hide() button._zCastStart = nil end

    if gLeft > 0 then
        if not button.gcdFrame:IsShown() then
            button.gcdFrame:SetCooldown(now - (gDur - gLeft), gDur)
            button.gcdFrame:Show()
        end
        SetText(button.gcdText, string_format("%d", math_ceil(gLeft)))
        button.gcdText:Show()
        Clear(button.durationText) Clear(button.expiryText)
        return
    end
    button.gcdFrame:Hide()
    Clear(button.gcdText)

    -- the eating countdown, on the food that was eaten only
    local cat = button.entry and button.entry.category
    if cat == "food" and ctx.eating and (ctx.eatLeft or 0) > 0 and not D.INSTANT[id] and id == ctx.lastUseId then
        SetText(button.durationText, string_format("%.0f", math_ceil(ctx.eatLeft)))
        button.durationText:Show()
        Clear(button.expiryText)
        return
    end
    Clear(button.durationText)

    -- running out: the big seconds inside the warning time; a weapon's
    -- minutes in the corner before that
    local thr = tonumber(cfg.showBeforeExpiry) or 60
    local has, rem, _, lowCharges = OwnState(button, w)
    local hasG, gt, gi = false, 0, nil
    local g = (not D.OWN_TIMER[cid]) and D.GROUP_OF[cid] or nil
    if g and key ~= "weapons" then hasG, gt, gi = w.GroupBuff(g) end
    local show = has and rem or (hasG and gi ~= cid and gt) or 0
    B.Glow(button, key, cfg, has and rem > 0 and rem <= thr)
    if cfg.showExpiryTimer == false then
        Clear(button.expiryText) Clear(button.timeText)
        return
    end
    local chargeText = lowCharges and string_format("%dc", lowCharges) or nil
    if data.slot then
        if show > 0 then
            if show <= thr then
                Clear(button.timeText)
                B.ExpiryText(button, cfg, show, thr, chargeText)
            else
                Clear(button.expiryText)
                B.TimerText(button, cfg, show)
            end
        else
            Clear(button.timeText) Clear(button.expiryText)
        end
    else
        Clear(button.timeText)
        if show > 0 and show <= thr then B.ExpiryText(button, cfg, show, thr, chargeText)
        else Clear(button.expiryText) end
    end
end

-- the swirls and their numbers off (the fast pass stopped)
function B.ClearLive(button, eating)
    Clear(button.gcdText) button.gcdFrame:Hide() button._zGcdStart = nil
    Clear(button.cooldownText) button.cooldownFrame:Hide()
    if not eating then Clear(button.durationText) end
    if button.castFrame:IsShown() then button.castFrame:Hide() button._zCastStart = nil end
end
