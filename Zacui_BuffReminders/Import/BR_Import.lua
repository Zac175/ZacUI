-- BR_Import - Readycheck's Battle Shout reminder and party tracker
-- settings brought over, and Readycheck's own switched off.
-- Part of ZacUI; load order is set by the TOC.
--
-- ns.BuffRem.ImportFromReadycheck() copies what THIS character's
-- Readycheck has now (Readycheck.db.battleShoutReminder,
-- .battleShoutPartyTracker, the two colour groups in .customColors and
-- the voice switch), read defensively: a value of the wrong type is left
-- out, never guessed. -> true, "what was copied" | false, "why not".
-- Readycheck's tables are only read; nothing in Readycheck changes.
--
-- ns.BuffRem.TurnOffReadycheck() is the one write into Readycheck: its
-- own two switches off and its own stop calls, each under pcall.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local BR = ns.BuffRem
if not BR then return end

local function Num(v) return type(v) == "number" and v or nil end
local function Bool(v) if type(v) == "boolean" then return v end return nil end
local function Str(v) return type(v) == "string" and v or nil end
local function Copy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = Copy(v) end
    return o
end
-- a colour table: { r, g, b, a } numbers only
local function Col(c)
    if type(c) ~= "table" then return nil end
    local r, g, b = Num(c.r), Num(c.g), Num(c.b)
    if not (r and g and b) then return nil end
    return { r = r, g = g, b = b, a = Num(c.a) or 1 }
end
-- Readycheck's font: face / outline / shadow in a table, the size on its
-- own key (the size may also sit in the table: the title's)
local function FontOf(spec, size)
    local out = {}
    if type(spec) == "table" then
        out.face = Str(spec.face)
        out.outline = Str(spec.outline)
        out.shadow = Bool(spec.shadow)
        out.size = Num(spec.size)
    end
    out.size = Num(size) or out.size
    if next(out) == nil then return nil end
    return out
end
-- an animation spec (Readycheck's and ZacUI's share the shape)
local function Anim(a)
    if type(a) ~= "table" or type(a.style) ~= "string" then return nil end
    return Copy(a)
end

-- the reminder icon's position: Readycheck's own frame point (CENTER) at
-- (x, y) from the screen's centre, or an old save's point at the same
-- point of the screen -> a ZacUI mover spot
local function IconSpot(a)
    local x, y = Num(a.xOffset), Num(a.yOffset)
    if not (x and y) then return nil end
    local p = Str(a.anchorPoint) or "CENTER"
    if a.centred then p = "CENTER" end
    return { point = p, x = x, y = y }
end
-- the tracker: its TOPLEFT at (x, y) from the centre (in its own scale's
-- units), or an old save's TOPLEFT at (x, y) from the bottom left
local function TrackerSpot(b)
    local x, y = Num(b.xOffset), Num(b.yOffset)
    if not (x and y) then return nil end
    local sc = Num(b.scale) or 1
    if sc <= 0 then sc = 1 end
    local W = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 0
    local H = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 0
    if b.centred then
        return { point = "TOPLEFT", x = x + (W / 2) / sc, y = y - (H / 2) / sc }
    end
    return { point = "TOPLEFT", x = x, y = y - H / sc }
end

-- what Readycheck calls each setting -> where ZacUI keeps it
BR.IMPORT_MAP = {
    icon = {   -- battleShoutReminder -> buffRem.icon
        opacity = "opacity", iconSize = "iconSize", borderSize = "borderSize",
        showMissingNames = "showMissingNames", shortenNames = "shortenNames",
        namesPosition = "namesPosition", namesOffset = "namesOffset",
        hideWhenAllBuffed = "hideWhenAllBuffed", playSound = "playSound", soundKey = "soundKey",
        visibilityMode = "visibilityMode",
    },
    shout = {  -- battleShoutReminder -> buffRem.buffs.battleshout
        enabled = "enabled", trackScope = "scope", buffThreshold = "threshold", rangeCheck = "rangeCheck",
        greedMode = "greedMode", greedSkipIfImpCleave = "greedSkipIfImpCleave", showAPValue = "showAPValue",
    },
    tracker = { -- battleShoutPartyTracker -> buffRem.tracker
        scale = "scale", opacity = "opacity", width = "width", rowHeight = "rowHeight",
        showBackground = "showBackground", showHeader = "showHeader", durationStyle = "durationStyle",
        barMaxDuration = "barMaxDuration", barAlpha = "barAlpha", borderSize = "borderSize",
        showOnlyMissing = "showOnlyMissing", rangeCheck = "rangeCheck", showBloodrage = "showBloodrage",
        bloodrageStyle = "bloodrageStyle", visibilityMode = "visibilityMode",
    },
    -- customColors.battleShoutReminder.<key> -> icon.colors.<key>
    iconColors = { "background", "normalBorder", "missingBorder", "missingText", "allBuffedText" },
    -- customColors.battleShoutPartyTracker.<key> -> tracker.colors.<key>
    trackerColors = { "background", "border", "headerBackground", "titleText", "rowBackground",
        "apGood", "apWarning", "apMissing", "bloodrageActive" },
}

local WANT_TYPE = { enabled = "boolean", threshold = "number", buffThreshold = "number", rangeCheck = "boolean",
    greedMode = "boolean", greedSkipIfImpCleave = "boolean", showAPValue = "boolean" }
for _, sec in ipairs({ "icon", "tracker" }) do
    for k, v in pairs(BR.DEFAULTS[sec]) do
        if type(v) ~= "table" then WANT_TYPE[k] = type(v) end
    end
end
local MODES = { raids = true, instances = true, group = true, always = true, everywhere = true }
local function Valid(field, v)
    if field == "visibilityMode" then return MODES[v] and v or nil end
    if field == "scope" or field == "trackScope" then return (v == "self" or v == "group") and v or nil end
    if field == "namesPosition" then
        return (v == "right" or v == "left" or v == "above" or v == "below") and v or nil
    end
    if field == "durationStyle" then
        return (v == "none" or v == "bar" or v == "timer" or v == "both") and v or nil
    end
    if field == "bloodrageStyle" then return (v == "icon" or v == "color" or v == "both") and v or nil end
    -- the type ZacUI's own default has (a number stays a number)
    local want = WANT_TYPE[field]
    if want then
        if type(v) == want then return v end
        return nil
    end
    local t = type(v)
    if t == "number" or t == "boolean" or t == "string" then return v end
    return nil
end

function BR.ImportFromReadycheck()
    local ok, res, why = pcall(function()
        local RC, a, b, db = BR.ReadycheckTables()
        if not RC then return false, "Readycheck is not loaded." end
        if not (a or b) then return false, "Readycheck has no Battle Shout settings on this character yet." end
        local c = BR.Cfg()
        if not c then return false, "ZacUI's settings are not ready yet." end
        local ic, tc = c.icon, c.tracker
        local n = 0
        local colours = type(db.customColors) == "table" and db.customColors or {}
        if a then
            for from, to in pairs(BR.IMPORT_MAP.icon) do
                local v = Valid(to, a[from])
                if v ~= nil then ic[to] = v n = n + 1 end
            end
            for from, to in pairs(BR.IMPORT_MAP.shout) do
                local v = Valid(from, a[from])
                if v ~= nil then BR.SetOpt("battleshout", to, v) n = n + 1 end
            end
            local f = FontOf(a.countFont, a.fontSize)
            if f then ic.countFont = f n = n + 1 end
            f = FontOf(a.namesFont, a.namesFontSize)
            if f then ic.namesFont = f n = n + 1 end
            if type(a.visibilityRaids) == "table" then ic.visibilityRaids = Copy(a.visibilityRaids) n = n + 1 end
            for _, k in ipairs({ "showAnim", "hideAnim", "alertAnim" }) do
                local s = Anim(a[k])
                if s then ic[k] = s n = n + 1 end
            end
            -- the customization families share ZacUI's shapes: copied as they are
            for _, k in ipairs({ "anchors", "visibility", "chrome", "framePos" }) do
                if type(a[k]) == "table" then ic[k] = Copy(a[k]) n = n + 1 end
            end
            local spot = IconSpot(a)
            if spot then
                ZacUIDB.movers = ZacUIDB.movers or {}
                ZacUIDB.movers.buffRemIcon = spot
                n = n + 1
            end
            local rc = type(colours.battleShoutReminder) == "table" and colours.battleShoutReminder or {}
            for _, k in ipairs(BR.IMPORT_MAP.iconColors) do
                local col = Col(rc[k])
                if col then ic.colors = ic.colors or {} ic.colors[k] = col n = n + 1 end
            end
            if type(db.ttsEnabled) == "boolean" then ic.speak = db.ttsEnabled n = n + 1 end
        end
        if b then
            for from, to in pairs(BR.IMPORT_MAP.tracker) do
                local v = Valid(to, b[from])
                if v ~= nil then tc[to] = v n = n + 1 end
            end
            if type(b.enabled) == "boolean" then BR.SetOpt("battleshout", "tracker", b.enabled) n = n + 1 end
            local f = FontOf(b.rowFont, b.fontSize)
            if f then tc.rowFont = f n = n + 1 end
            local tf = type(b.titleFont) == "table" and b.titleFont or nil
            f = FontOf(tf, (tf and Num(tf.size)) or b.fontSize)
            if f then tc.titleFont = f n = n + 1 end
            if type(b.visibilityRaids) == "table" then tc.visibilityRaids = Copy(b.visibilityRaids) n = n + 1 end
            for _, k in ipairs({ "showAnim", "hideAnim" }) do
                local s = Anim(b[k])
                if s then tc[k] = s n = n + 1 end
            end
            for _, k in ipairs({ "anchors", "layout", "formats", "visibility", "chrome", "framePos" }) do
                if type(b[k]) == "table" then tc[k] = Copy(b[k]) n = n + 1 end
            end
            local spot = TrackerSpot(b)
            if spot then
                ZacUIDB.movers = ZacUIDB.movers or {}
                ZacUIDB.movers.buffRemTracker = spot
                n = n + 1
            end
            local rc = type(colours.battleShoutPartyTracker) == "table" and colours.battleShoutPartyTracker or {}
            for _, k in ipairs(BR.IMPORT_MAP.trackerColors) do
                local col = Col(rc[k])
                if col then tc.colors = tc.colors or {} tc.colors[k] = col n = n + 1 end
            end
        end
        c.importedRC = time and time() or true
        return true, n .. " settings copied from Readycheck."
    end)
    if not ok then return false, "The import stopped: " .. tostring(res) end
    -- the frames read the new settings now
    if res then
        if ns.ApplyMover then pcall(ns.ApplyMover, "buffRemIcon") pcall(ns.ApplyMover, "buffRemTracker") end
        if BR.Restyle then pcall(BR.Restyle) end
        if BR.RunAll then pcall(BR.RunAll) end
        if ns.SettingsChanged then ns.SettingsChanged("import") end
    end
    return res, why
end

-- Readycheck's own Battle Shout reminder and party tracker off: their
-- switches, their stop calls, Readycheck's save. -> true | false, why
function BR.TurnOffReadycheck()
    local RC, a, b = BR.ReadycheckTables()
    if not RC then return false, "Readycheck is not loaded." end
    local done = false
    if a and a.enabled then
        a.enabled = false
        done = true
        if type(RC.StopBattleShoutReminderUpdates) == "function" then pcall(RC.StopBattleShoutReminderUpdates, RC) end
    end
    if b and b.enabled then
        b.enabled = false
        done = true
        if type(RC.StopBattleShoutPartyTrackerUpdates) == "function" then pcall(RC.StopBattleShoutPartyTrackerUpdates, RC) end
    end
    if done and type(RC.SaveConfigurationToProfile) == "function" then pcall(RC.SaveConfigurationToProfile, RC) end
    -- ZacUI's own Battle Shout follows (its default is on once Readycheck's is off)
    if BR.Kick then BR.Kick() end
    if ns.SettingsChanged then ns.SettingsChanged("readycheck") end
    return done, done and "Readycheck's Battle Shout reminder is off." or "Readycheck's was already off."
end
