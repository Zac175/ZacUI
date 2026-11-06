-- AE_Modernize - brings an older aura up to today's format.
-- Part of ZacUI (Zacui_Auras). Written for ZacUI.
--
-- Every saved aura carries the format version it was made with
-- (internalVersion). Over the years the WeakAuras format renamed fields,
-- moved texts and glows into sub-elements, turned single values into lists
-- and so on; an aura string made years ago still holds the old shapes.
-- E.Modernize(d) rewrites such a display, one step per format version it
-- is behind, into the shape this engine (and WeakAuras today) reads, then
-- marks it as version 90. It runs when an aura is imported (E.Install) and
-- on the library at login (E.ReadSaved), only for displays below 90, so a
-- current display is never touched.
--
-- Only steps that change how a display looks or behaves on Classic Era
-- are here. Steps for retail-only features (specs as ids, talent trees,
-- mythic+) and steps that only fixed WeakAuras' own option screens are not.
local ns = _G.ZacUI
if not ns then return end
local E = ns.AuraEngine
if not E then return end

local CURRENT = 90
E.FORMAT_VERSION = CURRENT

-- ============================================================
-- SMALL HELPERS
-- ============================================================
local function T(v) return type(v) == "table" and v or nil end

-- every trigger table of a display (after the version 7 layout)
local function Triggers(d)
    local out = {}
    for i, t in ipairs(T(d.triggers) or {}) do
        if type(t) == "table" and type(t.trigger) == "table" then out[#out + 1] = { i, t.trigger, t } end
    end
    return out
end

-- every condition check, nested ones included
local function EachCheck(d, fn)
    local function Walk(c)
        if type(c) ~= "table" then return end
        fn(c)
        for _, sub in ipairs(T(c.checks) or {}) do Walk(sub) end
    end
    for _, cond in ipairs(T(d.conditions) or {}) do
        if type(cond) == "table" then Walk(cond.check) end
    end
end

-- every condition change
local function EachChange(d, fn)
    for _, cond in ipairs(T(d.conditions) or {}) do
        for _, ch in ipairs(type(cond) == "table" and T(cond.changes) or {}) do
            if type(ch) == "table" then fn(ch) end
        end
    end
end

local function RenameProps(d, map)
    EachChange(d, function(ch)
        if ch.property and map[ch.property] then ch.property = map[ch.property] end
    end)
end

local function Subs(d)
    d.subRegions = T(d.subRegions) or {}
    return d.subRegions
end

local function Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- the %symbols of a text (p, 2.p, unit...)
local function Symbols(text)
    local out, seen = {}, {}
    if type(text) ~= "string" then return out end
    local function Add(s) if not seen[s] then seen[s] = true out[#out + 1] = s end end
    local plain = text:gsub("%%%%", "")
    for inner in plain:gmatch("%%(%b{})") do Add(inner:sub(2, -2)) end
    plain = plain:gsub("%%%b{}", "")
    for trig, sym in plain:gmatch("%%(%d*)%.?([%a_][%w_]*)") do Add(trig ~= "" and (trig .. "." .. sym) or sym) end
    return out
end

-- each text a display formats: { owner table, field prefix, text }
local function Texts(d)
    local out = {}
    if d.regionType == "text" then out[#out + 1] = { d, "displayText", d.displayText } end
    for _, s in ipairs(T(d.subRegions) or {}) do
        if type(s) == "table" and s.type == "subtext" then out[#out + 1] = { s, "text_text", s.text_text } end
    end
    local a = T(d.actions)
    for _, when in ipairs({ "start", "finish" }) do
        local x = a and T(a[when])
        if x then out[#out + 1] = { x, "message", x.message } end
    end
    EachChange(d, function(ch)
        if ch.property == "chat" and T(ch.value) then out[#out + 1] = { ch.value, "message", ch.value.message } end
    end)
    return out
end

local function ToList(t, key)
    if t and t[key] ~= nil and type(t[key]) ~= "table" then t[key] = { t[key] } end
end

-- ============================================================
-- THE STEPS (version they lead to, what they do)
-- ============================================================
local STEPS = {}
local function Step(v, fn) STEPS[#STEPS + 1] = { v, fn } end

-- 3: dynamic group children used to ignore their own offsets
Step(3, function(d, ctx)
    local p = d.parent and ctx.Find(d.parent)
    if p and p.regionType == "dynamicgroup" then d.xOffset, d.yOffset = 0, 0 end
end)

-- 4: a spell cooldown's "stacks" became "charges" (old trigger layout)
Step(4, function(d)
    EachCheck(d, function(c)
        local n = c.trigger
        if not n then return end
        local tr
        if n == 0 then tr = T(d.trigger) else tr = T(d.additional_triggers) and T(d.additional_triggers[n]) and d.additional_triggers[n].trigger end
        if tr and tr.event == "Cooldown Progress (Spell)" and c.variable == "stacks" then c.variable = "charges" end
    end)
end)

-- 5: the marked-children list is keyed by child id
Step(5, function(d)
    if T(d.sortHybridTable) and T(d.controlledChildren) then
        local t = {}
        for i, on in pairs(d.sortHybridTable) do
            local child = d.controlledChildren[i]
            if child then t[child] = on end
        end
        d.sortHybridTable = t
    end
end)

-- 6: showOn split into buffShowOn / genericShowOn
Step(6, function(d)
    for _, x in ipairs(Triggers(d)) do
        local tr = x[2]
        if tr.type == "aura" then
            tr.buffShowOn = tr.showOn == "showOnMissing" and "showOnMissing"
                or (tr.showOn == "showActiveOrMissing" and "showAlways" or "showOnActive")
        else
            tr.genericShowOn = tr.showOn or "showOnActive"
            tr.use_genericShowOn = tr.use_showOn
        end
        tr.showOn = nil
    end
end)

-- 7: triggers became one numbered list; conditions count from 1
Step(7, function(d)
    if T(d.triggers) and d.trigger == nil then return end
    local list = T(d.additional_triggers) or {}
    table.insert(list, 1, { trigger = T(d.trigger) or {}, untrigger = T(d.untrigger) or {} })
    d.triggers = list
    d.additional_triggers, d.trigger, d.untrigger, d.numTriggers = nil, nil, nil, nil
    list.customTriggerLogic = d.customTriggerLogic
    list.disjunctive = d.disjunctive
    local mode = d.activeTriggerMode or -10
    if mode ~= -10 then mode = mode + 1 end
    list.activeTriggerMode = mode
    d.customTriggerLogic, d.disjunctive, d.activeTriggerMode = nil, nil, nil
    EachCheck(d, function(c)
        if c.trigger and c.trigger >= 0 then c.trigger = c.trigger + 1 end
    end)
end)

-- 9: "buffed" checks became "show"
Step(9, function(d)
    EachCheck(d, function(c)
        if c.variable == "buffed" then
            local tr = c.trigger and T(d.triggers) and T(d.triggers[c.trigger]) and d.triggers[c.trigger].trigger
            if tr and tr.buffShowOn == "showOnActive" then
                c.variable = "show"
            elseif tr and tr.buffShowOn == "showOnMissing" then
                c.variable = "show"
                c.value = c.value == 0 and 1 or 0
            end
        end
    end)
end)

-- 12: cooldown numbers: "enabled" became "disabled"
Step(12, function(d)
    if d.cooldownTextEnabled ~= nil then
        d.cooldownTextDisabled = not d.cooldownTextEnabled
        d.cooldownTextEnabled = nil
    end
end)

-- 13: a dynamic group's selfPoint follows its grow and alignment
local DYN_POINT = {
    RIGHT = { LEFT = "TOPLEFT", RIGHT = "BOTTOMLEFT", CENTER = "LEFT" },
    LEFT = { LEFT = "TOPRIGHT", RIGHT = "BOTTOMRIGHT", CENTER = "RIGHT" },
    UP = { LEFT = "BOTTOMLEFT", RIGHT = "BOTTOMRIGHT", CENTER = "BOTTOM" },
    DOWN = { LEFT = "TOPLEFT", RIGHT = "TOPRIGHT", CENTER = "TOP" },
    HORIZONTAL = { LEFT = "TOP", RIGHT = "BOTTOM", CENTER = "CENTER" },
    VERTICAL = { LEFT = "LEFT", RIGHT = "RIGHT", CENTER = "CENTER" },
}
Step(13, function(d)
    if d.regionType ~= "dynamicgroup" then return end
    local g = DYN_POINT[d.grow or "DOWN"]
    if g then d.selfPoint = g[d.align] or g.CENTER
    elseif d.grow == "CIRCLE" or d.grow == "COUNTERCIRCLE" then d.selfPoint = "CENTER"
    else d.selfPoint = d.selfPoint or "CENTER" end
end)

-- 14: debuff class became a set
Step(14, function(d)
    for _, x in ipairs(Triggers(d)) do
        local v = x[2].debuffClass
        if type(v) == "string" and v ~= "" then x[2].debuffClass = { [v] = true } end
    end
end)

-- 15: Spell Known matches the exact id
Step(15, function(d)
    for _, x in ipairs(Triggers(d)) do
        if x[2].type == "status" and x[2].event == "Spell Known" then x[2].use_exact_spellName = true end
    end
end)

-- 16: "not this name/realm" was dropped (it never worked)
Step(16, function(d)
    local ld = T(d.load)
    if not ld then return end
    if ld.use_name == false then ld.use_name = nil end
    if ld.use_realm == false then ld.use_realm = nil end
end)

-- 19: a cast trigger on "multi" units watches nameplates
Step(19, function(d)
    for _, x in ipairs(Triggers(d)) do
        if x[2].type == "status" and x[2].event == "Cast" and x[2].unit == "multi" then x[2].unit = "nameplate" end
    end
end)

-- 20: an icon's two texts and a bar's three became sub-element texts
local function Containment(c, p)
    if not p or p == "CENTER" then return "CENTER" end
    if c == "INSIDE" then return "INNER_" .. p end
    if c == "OUTSIDE" then return "OUTER_" .. p end
    return p
end
Step(20, function(d)
    if d.regionType == "icon" then
        local subs = Subs(d)
        local function Text(n, visible)
            return { type = "subtext", text_visible = visible, text_color = d["text" .. n .. "Color"],
                text_text = d["text" .. n], text_font = d["text" .. n .. "Font"], text_fontSize = d["text" .. n .. "FontSize"],
                text_fontType = d["text" .. n .. "FontFlags"], text_selfPoint = "AUTO",
                text_anchorPoint = Containment(d["text" .. n .. "Containment"], d["text" .. n .. "Point"]),
                anchorXOffset = 0, anchorYOffset = 0, text_shadowColor = { 0, 0, 0, 1 },
                text_shadowXOffset = 0, text_shadowYOffset = 0 }
        end
        local t1, t2 = Text(1, d.text1Enabled ~= false), Text(2, d.text2Enabled or false)
        local use2 = d.text2Enabled
        for _, n in ipairs({ "1", "2" }) do
            for _, f in ipairs({ "Enabled", "Color", "", "Font", "FontSize", "FontFlags", "Containment", "Point" }) do
                d["text" .. n .. f] = nil
            end
        end
        table.insert(subs, t1)
        if use2 then table.insert(subs, t2) end
        RenameProps(d, { text1Color = "sub.1.text_color", text1FontSize = "sub.1.text_fontSize",
            text2Color = "sub.2.text_color", text2FontSize = "sub.2.text_fontSize" })
    elseif d.regionType == "aurabar" then
        local subs = Subs(d)
        local pos = ({ HORIZONTAL_INVERSE = { "INNER_LEFT", "INNER_RIGHT" }, HORIZONTAL = { "INNER_RIGHT", "INNER_LEFT" },
            VERTICAL_INVERSE = { "INNER_BOTTOM", "INNER_TOP" }, VERTICAL = { "INNER_TOP", "INNER_BOTTOM" } })[d.orientation]
            or { "INNER_LEFT", "INNER_RIGHT" }
        local function Text(visible, color, text, font, size, flags, anchor)
            return { type = "subtext", text_visible = visible, text_color = color, text_text = text, text_font = font,
                text_fontSize = size, text_fontType = flags, text_selfPoint = "AUTO", text_anchorPoint = anchor,
                anchorXOffset = 0, anchorYOffset = 0, text_shadowColor = { 0, 0, 0, 1 }, text_shadowXOffset = 1,
                text_shadowYOffset = -1, rotateText = d.rotateText }
        end
        table.insert(subs, Text(d.timer, d.timerColor, d.displayTextRight, d.timerFont, d.timerSize, d.timerFlags, pos[1]))
        table.insert(subs, Text(d.text, d.textColor, d.displayTextLeft, d.textFont, d.textSize, d.textFlags, pos[2]))
        table.insert(subs, Text(d.stacks, d.stacksColor, "%s", d.stacksFont, d.stacksSize, d.stacksFlags, "ICON_CENTER"))
        for _, k in ipairs({ "timer", "textColor", "displayTextRight", "textFont", "textSize", "textFlags", "text",
            "timerColor", "displayTextLeft", "timerFont", "timerSize", "timerFlags", "stacks", "stacksColor",
            "stacksFont", "stacksSize", "stacksFlags", "rotateText" }) do d[k] = nil end
        RenameProps(d, { timerColor = "sub.1.text_color", timerSize = "sub.1.text_fontSize",
            textColor = "sub.2.text_color", textSize = "sub.2.text_fontSize",
            stacksColor = "sub.3.text_color", stacksSize = "sub.3.text_fontSize" })
    end
end)

-- 21: a dynamic group's background became its border settings
Step(21, function(d)
    if d.regionType ~= "dynamicgroup" then return end
    d.border = d.background and d.background ~= "None"
    d.borderEdge = d.border
    d.borderBackdrop = d.background ~= "None" and d.background
    d.borderInset = d.backgroundInset
    d.background, d.backgroundInset = nil, nil
end)

-- 22: a bar's border became a sub-element
Step(22, function(d)
    if d.regionType ~= "aurabar" then return end
    local subs = Subs(d)
    local b = { type = "subborder", border_visible = d.border, border_color = d.borderColor, border_edge = d.borderEdge,
        border_offset = d.borderOffset, border_size = d.borderSize, border_anchor = "bar" }
    local front = d.borderInFront
    d.border, d.borderColor, d.borderEdge, d.borderOffset, d.borderInset, d.borderSize = nil, nil, nil, nil, nil, nil
    if front then table.insert(subs, b) else table.insert(subs, 1, b) end
    RenameProps(d, { borderColor = "sub." .. #subs .. ".border_color" })
end)

-- 23: Stance/Form became a multiselect
Step(23, function(d)
    for _, x in ipairs(Triggers(d)) do
        local tr = x[2]
        if tr.type == "status" and tr.event == "Stance/Form/Aura" and type(tr.form) ~= "table" then
            if tr.use_form == false then tr.form = { multi = tr.form and { [tr.form] = true } or {} }
            elseif tr.use_form then tr.form = { single = tr.form } end
        end
    end
end)

-- 24: Weapon Enchant: inverse became show on missing
Step(24, function(d)
    for _, x in ipairs(Triggers(d)) do
        local tr = x[2]
        if tr.type == "status" and tr.event == "Weapon Enchant" then
            tr.showOn = tr.use_inverse and "showOnMissing" or "showOnActive"
            tr.use_inverse = nil
            if not tr.use_weapon then tr.use_weapon, tr.weapon = "true", "main" end
        end
    end
end)

-- 25: an icon's glow became a sub-element
local GLOW_FIELDS = { "glow", "useGlowColor", "glowColor", "glowType", "glowLines", "glowFrequency", "glowLength",
    "glowThickness", "glowScale", "glowBorder", "glowXOffset", "glowYOffset" }
Step(25, function(d)
    if d.regionType ~= "icon" then return end
    local subs = Subs(d)
    local prefix = "sub." .. (#subs + 1) .. "."
    local map = {}
    for _, f in ipairs(GLOW_FIELDS) do map[f] = prefix .. f end
    local need = d.glow and true or false
    EachChange(d, function(ch) if map[ch.property] then need = true end end)
    if need then
        local g = { type = "subglow" }
        for _, f in ipairs(GLOW_FIELDS) do g[f] = d[f] end
        table.insert(subs, g)
    end
    for _, f in ipairs(GLOW_FIELDS) do d[f] = nil end
    d.useglowColor = nil
    RenameProps(d, map)
end)

-- 26: offset conditions became relative moves
Step(26, function(d)
    EachChange(d, function(ch)
        if ch.property == "xOffset" or ch.property == "yOffset" then
            ch.value = (tonumber(ch.value) or 0) - (tonumber(d[ch.property]) or 0)
            ch.property = ch.property .. "Relative"
        end
    end)
end)

-- 28, 29: action glows name their frame kind and glow kind
Step(29, function(d)
    local a = T(d.actions)
    for _, when in ipairs({ "start", "finish" }) do
        local x = a and T(a[when])
        if x and x.do_glow then
            if (d.internalVersion or 0) < 28 then x.glow_frame_type = "FRAMESELECTOR" end
            if x.glow_type == nil then x.glow_type = "buttonOverlay" end
        end
    end
end)

-- 30: progress/total precision became per-symbol time formats
Step(30, function(d)
    local function Legacy(p)
        if not p then return 1, nil end
        if p < 4 then return p, false end
        return p - 3, true
    end
    for _, x in ipairs(Texts(d)) do
        for _, sym in ipairs(Symbols(x[3])) do
            local s = sym:match("([%a_][%w_]*)$")
            if s == "p" or s == "t" then
                local base = x[2] .. "_format_" .. sym .. "_"
                x[1][base .. "format"] = "timed"
                x[1][base .. "time_precision"], x[1][base .. "time_dynamic"] = Legacy(s == "p" and d.progressPrecision or d.totalPrecision)
            end
        end
    end
    d.progressPrecision, d.totalPrecision = nil, nil
end)

-- 31, 33: name and realm became Name-Realm filters
Step(31, function(d)
    local ld = T(d.load)
    if not ld then return end
    local allow, ignore
    if ld.use_name == true and ld.name then allow = ld.name elseif ld.use_name == false and ld.name then ignore = ld.name end
    if ld.use_realm == true and ld.realm then allow = (allow or "") .. "-" .. ld.realm
    elseif ld.use_realm == false and ld.realm then ignore = (ignore or "") .. "-" .. ld.realm end
    if allow then ld.use_namerealm, ld.namerealm = true, allow end
    if ignore then ld.use_namerealmblack, ld.namerealmblack = true, ignore end
    ld.use_name, ld.name, ld.use_realm, ld.realm = nil, nil, nil, nil
end)

-- 32: unit triggers' name fields became Name-Realm fields
Step(32, function(d)
    for _, x in ipairs(Triggers(d)) do
        local i, tr = x[1], x[2]
        local map
        if tr.type == "status" then
            if tr.event == "Unit Characteristics" or tr.event == "Health" or tr.event == "Power" then
                map = { use_name = "use_namerealm", name = "namerealm" }
            elseif tr.event == "Alternate Power" then
                map = { use_unitname = "use_namerealm", unitname = "namerealm" }
            elseif tr.event == "Cast" then
                map = { use_sourceName = "use_sourceNameRealm", sourceName = "sourceNameRealm",
                    use_destName = "use_destNameRealm", destName = "destNameRealm" }
            end
        end
        if map then
            for old, new in pairs(map) do tr[new], tr[old] = tr[old], nil end
            EachCheck(d, function(c) if c.trigger == i and map[c.variable] then c.variable = map[c.variable] end end)
        end
    end
end)

Step(33, function(d)
    local ld = T(d.load)
    if ld then
        ld.use_ignoreNameRealm, ld.ignoreNameRealm = ld.use_namerealmblack, ld.namerealmblack
        ld.use_namerealmblack, ld.namerealmblack = nil, nil
    end
    for _, x in ipairs(Triggers(d)) do
        local tr = x[2]
        tr.useIgnoreName, tr.ignoreAuraNames = tr.useBlackName, tr.blackauranames
        tr.useIgnoreExactSpellId, tr.ignoreAuraSpellids = tr.useBlackExactSpellId, tr.blackauraspellids
        tr.useBlackName, tr.blackauranames, tr.useBlackExactSpellId, tr.blackauraspellids = nil, nil, nil, nil
    end
end)

-- 34: circles say whether they are whole
Step(34, function(d)
    if d.regionType == "dynamicgroup" and (d.grow == "CIRCLE" or d.grow == "COUNTERCIRCLE") then
        d.fullCircle = d.arcLength == 360
    end
end)

-- 35: older textures clamped their edges
Step(35, function(d)
    if d.regionType == "texture" then d.textureWrapMode = "CLAMP" end
end)

-- 37: aura group role became a set
Step(37, function(d)
    for _, x in ipairs(Triggers(d)) do
        local tr = x[2]
        if tr.type == "aura2" and tr.group_role and type(tr.group_role) ~= "table" then
            tr.group_role = { [tr.group_role] = true }
        end
    end
end)

-- 38: weapon kinds counted from the item class
local function PlusWeapon(t)
    if not T(t) then return end
    if t.single then t.single = t.single + 512 end
    if T(t.multi) then
        local m = {}
        for v, on in pairs(t.multi) do m[v + 512] = on end
        t.multi = m
    end
end
Step(38, function(d)
    for _, x in ipairs(Triggers(d)) do
        if x[2].type == "status" and x[2].event == "Item Type Equipped" then PlusWeapon(x[2].itemTypeName) end
    end
    if T(d.load) then PlusWeapon(d.load.itemtypeequipped) end
end)

-- 39: "automatic icon" became the icon source
Step(39, function(d)
    if d.regionType == "icon" or d.regionType == "aurabar" then d.iconSource = d.auto and -1 or 0 end
end)

-- 40: groups made before this keep their offset way; information table
Step(40, function(d)
    d.information = T(d.information) or {}
    if d.regionType == "group" then d.information.groupOffset = true end
    d.information.ignoreOptionsEventErrors = d.ignoreOptionsEventErrors
    d.ignoreOptionsEventErrors = nil
end)

-- 41: "status" and "event" triggers got their own kinds
local KIND_OF = {
    ["Cooldown Ready (Spell)"] = "spell", ["Queued Action"] = "spell", ["Charges Changed"] = "spell",
    ["Action Usable"] = "spell", ["Chat Message"] = "event", ["Unit Characteristics"] = "unit",
    ["Cooldown Progress (Spell)"] = "spell", ["Power"] = "unit", ["PvP Talent Selected"] = "unit",
    ["Combat Log"] = "combatlog", ["Item Set"] = "item", ["Health"] = "unit", ["Cooldown Progress (Item)"] = "item",
    ["Conditions"] = "unit", ["Spell Known"] = "spell", ["Cooldown Ready (Item)"] = "item",
    ["Faction Reputation"] = "unit", ["Pet Behavior"] = "unit", ["Range Check"] = "unit", ["Character Stats"] = "unit",
    ["Talent Known"] = "unit", ["Threat Situation"] = "unit", ["Equipment Set"] = "item", ["Death Knight Rune"] = "unit",
    ["Cast"] = "unit", ["Item Count"] = "item", ["BigWigs Timer"] = "addons", ["Spell Activation Overlay"] = "spell",
    ["DBM Timer"] = "addons", ["Item Type Equipped"] = "item", ["Alternate Power"] = "unit", ["Item Equipped"] = "item",
    ["Item Bonus Id Equipped"] = "item", ["DBM Announce"] = "addons", ["Swing Timer"] = "unit", ["Totem"] = "spell",
    ["Ready Check"] = "event", ["BigWigs Message"] = "addons", ["Class/Spec"] = "unit", ["Stance/Form/Aura"] = "unit",
    ["Weapon Enchant"] = "item", ["Global Cooldown"] = "spell", ["Experience"] = "unit", ["GTFO"] = "addons",
    ["Cooldown Ready (Equipment Slot)"] = "item", ["Crowd Controlled"] = "unit",
    ["Cooldown Progress (Equipment Slot)"] = "item", ["Combat Events"] = "event",
}
Step(41, function(d)
    for _, x in ipairs(Triggers(d)) do
        local tr = x[2]
        if (tr.type == "status" or tr.type == "event") and KIND_OF[tr.event] then tr.type = KIND_OF[tr.event] end
    end
end)

-- 43: zone ids and zone group ids merged into one list
Step(43, function(d)
    local ld = T(d.load)
    if not ld or (d.internalVersion or 0) == 42 then return end
    if ld.use_zoneId == ld.use_zonegroupId then
        ld.use_zoneIds = ld.use_zoneId
        local ids, groups = Trim(ld.zoneId), Trim(ld.zonegroupId):gsub("(%d+)", "g%1")
        if ids ~= "" and groups ~= "" then ld.zoneIds = ids .. ", " .. groups else ld.zoneIds = ids .. groups end
    elseif ld.use_zoneId then
        ld.use_zoneIds, ld.zoneIds = true, ld.zoneId
    elseif ld.use_zonegroupId then
        ld.use_zoneIds, ld.zoneIds = true, (Trim(ld.zonegroupId):gsub("(%d+)", "g%1"))
    end
    ld.use_zoneId, ld.use_zonegroupId, ld.zoneId, ld.zonegroupId = nil, nil, nil, nil
end)

-- 44: time formats got a style and a threshold
Step(44, function(d)
    for _, x in ipairs(Texts(d)) do
        local owner, prefix = x[1], x[2] .. "_format_"
        local keys = {}
        for k in pairs(owner) do
            local sym = type(k) == "string" and k:sub(1, #prefix) == prefix and k:match("^" .. prefix:gsub("%p", "%%%0") .. "(.+)_format$")
            if sym then keys[#keys + 1] = sym end
        end
        for _, sym in ipairs(keys) do
            local base = prefix .. sym .. "_"
            if owner[base .. "format"] == "timed" then
                owner[base .. "time_format"] = 0
                owner[base .. "time_dynamic_threshold"] = owner[base .. "time_dynamic"] and 3 or 60
            end
            owner[base .. "time_dynamic"] = nil
            if owner[base .. "time_precision"] == 0 then
                owner[base .. "time_precision"] = 1
                owner[base .. "time_dynamic_threshold"] = 0
            end
        end
    end
end)

-- 49: renamed sub-element kinds and model fields
Step(49, function(d)
    if tostring(d.regionType):match("group") then return end
    for _, s in ipairs(Subs(d)) do
        if type(s) == "table" then
            if s.type == "aurabar_bar" then s.type = "subforeground" elseif s.type == "subbarmodel" then s.type = "submodel" end
            if s.bar_model_visible ~= nil then s.model_visible, s.bar_model_visible = s.bar_model_visible, nil end
            if s.bar_model_alpha ~= nil then s.model_alpha, s.bar_model_alpha = s.bar_model_alpha, nil end
        end
    end
    EachChange(d, function(ch)
        local pre, prop = tostring(ch.property or ""):match("^(sub%.%d+%.)(.*)$")
        if prop == "bar_model_visible" then ch.property = pre .. "model_visible"
        elseif prop == "bar_model_alpha" then ch.property = pre .. "model_alpha" end
    end)
end)

-- 51: Threat Situation's unit field
Step(51, function(d)
    for _, x in ipairs(Triggers(d)) do
        local tr = x[2]
        if tr.event == "Threat Situation" then
            tr.unit, tr.use_unit, tr.threatUnit, tr.use_threatUnit = tr.threatUnit, tr.use_threatUnit, nil, nil
        end
    end
end)

-- 52: whispering %t / target became a unit whisper
local function IsTarget(s) return s == "target" or s == "'target'" or s == '"target"' or s == "%t" or s == "'%t'" or s == '"%t"' end
Step(52, function(d)
    EachChange(d, function(ch)
        if ch.property == "chat" and T(ch.value) and IsTarget(ch.value.message_dest) then
            ch.value.message_dest, ch.value.message_dest_isunit = "target", true
        end
    end)
    local a = T(d.actions)
    for _, when in ipairs({ "start", "finish" }) do
        local x = a and T(a[when])
        if x and x.do_message and x.message_type == "WHISPER" and IsTarget(x.message_dest) then
            x.message_dest, x.message_dest_isunit = "target", true
        end
    end
end)

-- 53: old time texts keep rounding seconds down
Step(53, function(d)
    for _, x in ipairs(Texts(d)) do
        for _, sym in ipairs(Symbols(x[3])) do
            local base = x[2] .. "_format_" .. sym .. "_"
            if x[1][base .. "format"] == "timed" and x[1][base .. "time_format"] == 0 then
                x[1][base .. "time_legacy_floor"] = true
            end
        end
    end
end)

-- 54: the first aura trigger kind is gone (it never shows)
Step(54, function(d)
    for _, x in ipairs(Triggers(d)) do
        local tr = x[2]
        if tr.type == "aura" then tr.type, tr.event, tr.use_alwaystrue = "unit", "Conditions", false end
    end
end)

-- 55, 56: forceEvents moved into the information table
Step(56, function(d)
    d.information = T(d.information) or {}
    if (d.internalVersion or 0) < 55 then d.forceEvents = true end
    d.information.forceEvents = d.forceEvents
    d.forceEvents = nil
end)

-- 60, 61, 63: a texture's "discrete" rotation became its rotation
Step(63, function(d)
    if d.regionType ~= "texture" then return end
    local v = d.internalVersion or 0
    if v < 60 then
        if d.rotate then d.legacyZoomOut = true else d.rotation = d.discrete_rotation end
        d.discrete_rotation = nil
    end
    if v < 61 then
        if d.legacyZoomOut then d.rotate = true else d.rotate, d.discrete_rotation = false, d.rotation end
        d.legacyZoomOut = nil
    end
    local atlas = false
    local info = C_Texture and C_Texture.GetAtlasInfo
    if info and type(d.texture) == "string" then
        local ok, res = pcall(info, d.texture)
        atlas = ok and res ~= nil
    end
    if (not d.rotate or atlas) and d.discrete_rotation ~= nil then d.rotation = d.discrete_rotation end
end)

-- 64: custom sort/grow run when something changed
Step(64, function(d)
    if d.regionType ~= "dynamicgroup" then return end
    if (d.sort == "custom" and type(d.sortOn) ~= "string") or d.sortOn == "" then d.sortOn = "changed" end
    if d.grow == "CUSTOM" and type(d.growOn) ~= "string" then d.growOn = "changed" end
end)

-- 65: Item Count with an item id is exact
Step(65, function(d)
    for _, x in ipairs(Triggers(d)) do
        local tr = x[2]
        if tr.type == "item" and tr.event == "Item Count" and type(tr.itemName) == "number" then tr.use_exact_itemName = true end
    end
end)

-- 67, 70: number fields became lists (two entries can be combined)
local LISTS = {
    Cast = { "stage", "stage_operator" },
    Experience = { "level", "level_operator", "currentXP", "currentXP_operator", "totalXP", "totalXP_operator",
        "percentXP", "percentXP_operator", "restedXP", "restedXP_operator", "percentrested", "percentrested_operator" },
    Health = { "health", "health_operator", "percenthealth", "percenthealth_operator", "deficit", "deficit_operator",
        "maxhealth", "maxhealth_operator", "absorb", "absorb_operator", "healabsorb", "healabsorb_operator",
        "healprediction", "healprediction_operator" },
    Power = { "power", "power_operator", "percentpower", "percentpower_operator", "deficit", "deficit_operator",
        "maxpower", "maxpower_operator" },
    ["Threat Situation"] = { "threatpct", "threatpct_operator", "rawthreatpct", "rawthreatpct_operator",
        "threatvalue", "threatvalue_operator" },
    ["Unit Characteristics"] = { "level", "level_operator" },
    ["Combat Log"] = { "spellId", "spellName" },
    ["Spell Cast Succeeded"] = { "spellId" },
}
local STATS = { "mainstat", "strength", "agility", "intellect", "spirit", "stamina", "criticalrating", "criticalpercent",
    "hitrating", "hitpercent", "hasterating", "hastepercent", "meleehastepercent", "expertiserating", "expertisebonus",
    "armorpenrating", "armorpenpercent", "resiliencerating", "resiliencepercent", "spellpenpercent", "masteryrating",
    "masterypercent", "versatilityrating", "versatilitypercent", "attackpower", "resistanceholy", "resistancefire",
    "resistancenature", "resistancefrost", "resistanceshadow", "resistancearcane", "leechrating", "leechpercent",
    "movespeedrating", "movespeedpercent", "runspeedpercent", "avoidancerating", "avoidancepercent", "defense",
    "dodgerating", "dodgepercent", "parryrating", "parrypercent", "blockpercent", "blocktargetpercent", "blockvalue",
    "staggerpercent", "staggertargetpercent", "armorrating", "armorpercent", "armortargetpercent" }
LISTS["Character Stats"] = {}
for _, s in ipairs(STATS) do
    table.insert(LISTS["Character Stats"], s)
    table.insert(LISTS["Character Stats"], s .. "_operator")
end
Step(67, function(d)
    for _, x in ipairs(Triggers(d)) do
        local tr = x[2]
        for _, f in ipairs(LISTS[tr.event] or {}) do ToList(tr, f) end
        if tr.event == "Cast" and tr.type == "unit" then
            if tr.spellId then
                if tr.useExactSpellId then
                    tr.use_spellIds = tr.use_spellId
                    tr.spellIds = T(tr.spellIds) or {}
                    table.insert(tr.spellIds, tr.spellId)
                else
                    tr.use_spellNames = tr.use_spellId
                    tr.spellNames = T(tr.spellNames) or {}
                    table.insert(tr.spellNames, tr.spellId)
                end
            end
            if tr.use_spell and tr.spell then
                tr.use_spellNames = true
                tr.spellNames = T(tr.spellNames) or {}
                table.insert(tr.spellNames, tr.spell)
            end
            tr.use_spellId, tr.spellId, tr.use_spell, tr.spell = nil, nil, nil, nil
        end
    end
    local ld = T(d.load)
    if ld then
        for _, f in ipairs({ "level", "level_operator", "effectiveLevel", "effectiveLevel_operator" }) do ToList(ld, f) end
    end
end)

-- 68: dynamic group children choose not to follow a parent frame
Step(68, function(d, ctx)
    local p = d.parent and ctx.Find(d.parent)
    if p and p.regionType == "dynamicgroup" and d.anchorFrameParent == nil then d.anchorFrameParent = false end
end)

-- 69: worn items became a list
Step(69, function(d) ToList(T(d.load), "itemequiped") end)

Step(70, function(d)
    for _, x in ipairs(Triggers(d)) do
        if x[2].event == "Power" then ToList(x[2], "power") ToList(x[2], "power_operator") end
    end
end)

-- 71: progress sources; tick marks got several placements
Step(71, function(d)
    local rt = d.regionType
    if rt == "icon" or rt == "aurabar" or rt == "progresstexture" or rt == "stopmotion" then d.progressSource = { -1, "" }
    else d.progressSource = nil end
    for _, s in ipairs(T(d.subRegions) or {}) do
        if type(s) == "table" and s.type == "subtick" then
            s.tick_placements = { s.tick_placement }
            s.progressSources = { { -2, "" } }
            s.tick_placement = nil
        end
    end
end)

-- 72: a unit model on Classic named its unit in model_path
Step(72, function(d)
    if d.model_path and d.modelIsUnit then d.model_fileId = d.model_path end
end)

-- 73: tick placement conditions name their placement
Step(73, function(d)
    EachChange(d, function(ch)
        if type(ch.property) == "string" then
            ch.property = ch.property:gsub("(sub.%d.tick_placement)(%d)", "%1s.%2")
        end
    end)
end)

-- 74: an exact spell cooldown ignores overrides
Step(74, function(d)
    for _, x in ipairs(Triggers(d)) do
        if x[2].type == "spell" and x[2].event == "Cooldown Progress (Spell)" and x[2].use_exact_spellName then
            x[2].use_ignoreoverride = true
        end
    end
end)

-- 75: adjusted min/max are text
Step(75, function(d)
    if type(d.adjustedMin) == "number" then d.adjustedMin = tostring(d.adjustedMin) end
    if type(d.adjustedMax) == "number" then d.adjustedMax = tostring(d.adjustedMax) end
end)

-- 76: number lists without holes
local function NoHoles(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    if #keys == #t then return t end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for i, k in ipairs(keys) do out[i] = t[k] end
    return out
end
local HOLES = {
    ["Spell Cast Succeeded"] = { "spellId" }, ["Unit Characteristics"] = { "level" },
    Power = { "power", "percentpower", "deficit", "maxpower" }, ["Combat Log"] = { "spellId", "spellName" },
    Health = { "health", "percenthealth", "deficit", "maxhealth", "absorb", "healabsorb", "healprediction" },
    ["Faction Reputation"] = { "value", "total", "percentRep" }, Location = { "zone", "subzone" },
    ["Threat Situation"] = { "threatpct", "rawthreatpct", "threatvalue" }, ["Character Stats"] = STATS,
    Cast = { "spellNames", "spellIds", "stage" }, ["Alternate Power"] = { "power" },
    Experience = { "level", "currentXP", "totalXP", "percentXP", "restedXP", "percentrested" },
}
Step(76, function(d)
    for _, x in ipairs(Triggers(d)) do
        local tr = x[2]
        for _, f in ipairs(HOLES[tr.event] or {}) do
            if T(tr[f]) then tr[f] = NoHoles(tr[f]) end
        end
    end
end)

-- 77: number keys a web export turned into text
local function NumberKeys(t)
    if not T(t) then return end
    local fix = {}
    for k in pairs(t) do if type(k) == "string" then fix[#fix + 1] = k end end
    for _, k in ipairs(fix) do
        local n = tonumber(k)
        if n then t[n] = t[k] end
        t[k] = nil
    end
end
Step(77, function(d)
    for _, x in ipairs(Triggers(d)) do
        local tr = x[2]
        for _, f in ipairs({ "talent", "herotalent", "form", "specId" }) do if T(tr[f]) then NumberKeys(tr[f].multi) end end
        NumberKeys(tr.actualSpec)
        NumberKeys(tr.arena_spec)
    end
    local ld = T(d.load)
    if ld then
        for _, f in ipairs({ "talent", "talent2", "talent3", "herotalent", "class_and_spec" }) do
            if T(ld[f]) then NumberKeys(ld[f].multi) end
        end
    end
end)

-- 78: Item Type Equipped is always several
Step(78, function(d)
    for _, x in ipairs(Triggers(d)) do
        local tr = x[2]
        if tr.type == "item" and tr.event == "Item Type Equipped" then
            local v = T(tr.itemTypeName) and tr.itemTypeName.single
            if tr.use_itemTypeName and v then
                tr.use_itemTypeName, tr.itemTypeName = false, { multi = { [v] = true } }
            else
                tr.itemTypeName = { multi = {} }
            end
        end
    end
end)

-- 79: "ignore dead" became a dead tristate
Step(79, function(d)
    for _, x in ipairs(Triggers(d)) do
        local tr = x[2]
        if tr.type == "unit" and tr.event == "Unit Characteristics" then
            if tr.use_ignoreDead then
                if tr.unit == "group" or tr.unit == "raid" or tr.unit == "party" then tr.use_dead = false else tr.use_dead = nil end
            end
            tr.use_ignoreDead = nil
        end
    end
end)

-- 80, 81: common anchor names; progressSources -> progressSource
local ANCHOR_NAMES = { subborder = { border_anchor = "anchor_area" }, subglow = { glow_anchor = "anchor_area" },
    subtext = { text_anchorPoint = "anchor_point" } }
local SOURCE_NAMES = { sublineartexture = true, subcirculartexture = true, substopmotion = true }
Step(81, function(d)
    local v = d.internalVersion or 0
    for _, s in ipairs(T(d.subRegions) or {}) do
        if type(s) == "table" then
            if v < 80 and ANCHOR_NAMES[s.type] then
                for old, new in pairs(ANCHOR_NAMES[s.type]) do s[new], s[old] = s[old], nil end
            end
            if SOURCE_NAMES[s.type] then s.progressSource, s.progressSources = s.progressSources, nil end
        end
    end
end)

-- 82: separator options lost their "no merge"
Step(82, function(d)
    for _, o in ipairs(T(d.authorOptions) or {}) do
        if type(o) == "table" and o.type == "header" then o.noMerge = nil end
    end
end)

-- 83: the countdown numbers condition's name
Step(83, function(d) RenameProps(d, { cooldownText = "cooldownTextDisabled" }) end)

-- 84: boss mod timers made before the bar filter show enabled bars only
Step(84, function(d)
    for _, x in ipairs(Triggers(d)) do
        local tr = x[2]
        if tr.type == "addons" and (tr.event == "Boss Mod Timer" or tr.event == "BigWigs Timer" or tr.event == "DBM Timer")
            and not (tr.use_message or tr.use_spellId) then
            tr.use_isBarEnabled = true
        end
    end
end)

-- 85: raid mark fields became selections
Step(85, function(d)
    local kinds = { ["Unit Characteristics"] = true, Health = true, Power = true, ["Alternate Power"] = true, Cast = true }
    for _, x in ipairs(Triggers(d)) do
        local tr = x[2]
        if tr.type == "unit" and kinds[tr.event] then
            if type(tr.raidMarkIndex) == "number" then tr.raidMarkIndex = { single = tr.raidMarkIndex } end
            if tr.use_raidMarkIndex == false then tr.use_raidMarkIndex = nil end
        end
    end
end)

-- 86: a bar model "clips" became "attaches" (and stretches)
Step(86, function(d)
    for _, s in ipairs(T(d.subRegions) or {}) do
        if type(s) == "table" and s.type == "submodel" then
            s.bar_model_attach, s.bar_model_clip = s.bar_model_clip, nil
            if s.bar_model_attach then s.bar_model_stretch = true end
        end
    end
end)

-- 87: the bar icon condition's name
Step(87, function(d) RenameProps(d, { icon_visible = "icon" }) end)

-- 89: custom states that leave show unset count as hidden
Step(89, function(d)
    d.information = T(d.information) or {}
    d.information.showNilIsFalse = true
end)

-- 90: bars show their tooltip over the icon
Step(90, function(d)
    if d.regionType == "aurabar" then d.toolTipArea = "ICON" end
end)

E.ModernizeSteps = STEPS

-- ============================================================
-- RUNNING IT
-- ============================================================
-- ctx.Find(id) answers another display of the same set (an import's
-- other displays, or the library), for the steps that look at a parent.
function E.Modernize(d, ctx)
    if type(d) ~= "table" then return false end
    local v = tonumber(d.internalVersion)
    if v and v >= CURRENT then return false end
    ctx = ctx or { Find = function(id) return E.data[id] end }
    if not v or v < 2 then v = 2 end
    d.internalVersion = v
    for _, s in ipairs(STEPS) do
        if v < s[1] then
            local ok, err = pcall(s[2], d, ctx)
            if not ok then E.Error(tostring(d.id), "updating from format " .. v, err) end
        end
    end
    d.internalVersion = CURRENT
    return true
end

-- every display of an import payload ({ d = top, c = { children } })
function E.ModernizePayload(payload)
    if type(payload) ~= "table" or type(payload.d) ~= "table" then return 0 end
    local byId = {}
    local all = { payload.d }
    byId[payload.d.id or ""] = payload.d
    for _, c in ipairs(T(payload.c) or {}) do
        if type(c) == "table" then
            all[#all + 1] = c
            if c.id then byId[c.id] = c end
        end
    end
    local ctx = { Find = function(id) return byId[id] or E.data[id] end }
    local n = 0
    -- parents first, so a child step that reads its parent sees it as it was
    for _, d in ipairs(all) do
        if E.Modernize(d, ctx) then n = n + 1 end
    end
    return n
end
