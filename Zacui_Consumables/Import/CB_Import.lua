-- CB_Import - Readycheck's three bars brought over: this character's
-- live Readycheck settings for the consumables, potion and weapon bars
-- (on / off, items, order, spot, look, every option) copied into ZacUI's
-- bars, and Readycheck's own copy of a bar switched off on request.
-- Readycheck is never required: every read is guarded, and nothing in
-- Readycheck changes except the one "enabled" switch TurnOffReadycheck
-- writes.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end
local D, CB = ns.ConsData, ns.ConsBars
if not (D and CB) then return end

local pairs, ipairs, type = pairs, ipairs, type

local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end

-- the per-bar settings that carry over under the same name
local SAME = { "enabled", "locked", "hideInCombat", "buttonSize", "buttonsPerRow", "iconSpacing", "growDirection",
    "showBackground", "showCount", "showItemNames", "showTooltips", "showExpiryTimer", "showBeforeExpiry",
    "visibilityMode", "visibilityRaids", "mouseoverFade", "mouseoverFadeAlpha", "scale",
    "showOnlyAvailable", "hideWhenActive", "hideConflictingBuffs", "groupConflictButtons", "selfCastJujus",
    "petrificationCampMode", "hideUsedInCombat", "showBagWeapons", "showEquippedWeapons", "hordeByFaction",
    "hiddenItems", "hiddenWeapons", "itemOrder", "customItems", "conflictGroupPreferences",
    "conflictGroupQuickUse", "clickActions", "style", "anchors", "formats", "visibility", "chrome" }
CB.IMPORT_SAME = SAME
-- the bars' colours: Readycheck's colour category for each bar
local COLOR_CAT = { main = "consumablesBar", potions = "potionsBar", weapons = "weaponBar" }
local COLOR_KEYS = { "frameBackground", "frameBorder", "accentLine", "buttonBorder", "activeBorder",
    "conflictBackground", "conflictBorder" }
local STONE_KEYS = { "elementalStone", "consecratedStone", "denseStone", "frostOil" }
-- Readycheck's bar frames (their spot when nothing is saved)
local RC_FRAME = { main = "ReadycheckConsumablesHelper", potions = "ReadycheckPotionsBar", weapons = "ReadycheckWeaponsBar" }

local function Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for _, k in ipairs({ "r", "g", "b", "a" }) do
        if math.abs((tonumber(a[k]) or 1) - (tonumber(b[k]) or 1)) > 0.001 then return false end
    end
    return true
end
local function DefaultColor(key)
    local B = CB.Button
    local r, g, b, a = B.BarColor({}, key)
    return { r = r, g = g, b = b, a = a }
end

-- A Readycheck spot (the bar's pinned point x, y from the screen's
-- centre once converted; an old save: that point at the same point of
-- the screen) as a ZacUI mover spot (a point at the same point of the screen).
local function Spot(s)
    local x, y = tonumber(s.xOffset), tonumber(s.yOffset)
    if not (x and y) then return nil end
    local p = type(s.anchorPoint) == "string" and s.anchorPoint or "TOPLEFT"
    if not s.centred then return { point = p, x = x, y = y } end
    local W, H = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
    local px = p:find("LEFT") and 0 or (p:find("RIGHT") and W or W / 2)
    local py = p:find("BOTTOM") and 0 or (p:find("TOP") and H or H / 2)
    return { point = p, x = x - (px - W / 2), y = y - (py - H / 2) }
end
CB.RCSpot = Spot
-- where Readycheck's frame actually is (when it exists)
local function FrameSpot(key)
    local f = _G[RC_FRAME[key]]
    if not (type(f) == "table" and f.GetLeft) then return nil end
    local l, t = f:GetLeft(), f:GetTop()
    if not (l and t) then return nil end
    local k = (f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    return { point = "TOPLEFT", x = l * k, y = t * k - (UIParent:GetHeight() or 0) }
end

local function ImportBar(RC, key, out)
    local src = RC.db[CB.RC_KEYS[key]]
    if type(src) ~= "table" then return false end
    local dst = CB.Bar(key)
    for _, k in ipairs(SAME) do
        -- what Readycheck leaves unset reads as its default: ZacUI's
        -- default for that bar (none, for a table)
        if src[k] ~= nil then dst[k] = Copy(src[k]) else dst[k] = Copy(CB.DEFAULTS[key][k]) end
    end
    -- layer / level / keep on screen (its scale is the bar's own)
    if type(src.framePos) == "table" then
        local p = {}
        for _, k in ipairs({ "strata", "level", "clamp" }) do p[k] = src.framePos[k] end
        dst.position = next(p) and p or nil
    else
        dst.position = nil
    end
    dst.tts = (key == "main") and (src.consumableTTSEnabled and true or false) or (src.ttsEnabled and true or false)
    -- the colours the bar wears in Readycheck (only those not ZacUI's own)
    local colors = {}
    if type(RC.GetColor) == "function" then
        local keys = {}
        for _, k in ipairs(COLOR_KEYS) do keys[#keys + 1] = { COLOR_CAT[key], k } end
        if key ~= "potions" then for _, k in ipairs(STONE_KEYS) do keys[#keys + 1] = { "weaponBar", k } end end
        -- (the clash colours are the consumables bar's in Readycheck)
        for _, ck in ipairs(keys) do
            local cat = ck[1]
            if ck[2] == "conflictBackground" or ck[2] == "conflictBorder" then cat = "consumablesBar" end
            local ok, c = pcall(RC.GetColor, RC, cat, ck[2])
            if ok and type(c) == "table" and c.r and not Same(c, DefaultColor(ck[2])) then
                colors[ck[2]] = { r = c.r, g = c.g, b = c.b, a = c.a or 1 }
            end
        end
    end
    dst.colors = next(colors) and colors or nil
    -- the spot: Readycheck's saved one, else where its frame is
    local spot = Spot(src) or FrameSpot(key)
    if spot then
        ZacUIDB.movers = ZacUIDB.movers or {}
        ZacUIDB.movers[CB.MoverKey(key)] = spot
    end
    out[#out + 1] = CB.LABELS[key]:lower()
    return true
end

-- Copies this character's Readycheck consumables, potion and weapon bar
-- settings into ZacUI's bars. -> true / false, and a short reason.
function CB.ImportFromReadycheck()
    if type(ZacUIDB) ~= "table" then return false, "ZacUI's settings are not loaded yet" end
    local RC = CB.RC()
    if not RC then return false, "Readycheck is not loaded" end
    local done = {}
    local ok, err = pcall(function()
        CB.Cfg()
        for _, key in ipairs(CB.BARS) do ImportBar(RC, key, done) end
        local ch = RC.db.consumablesHelper
        if type(ch) == "table" then
            local c = CB.Cfg()
            if ch.selectedStoneType ~= nil then c.stone = ch.selectedStoneType end
            c.stoneBySlot = (type(ch.selectedStoneBySlot) == "table" and next(ch.selectedStoneBySlot)) and Copy(ch.selectedStoneBySlot) or nil
            if ch.showWeaponIcons ~= nil then c.weaponIcons = ch.showWeaponIcons and true or false end
            c.potionReadyTTS = ch.potionReadyTTS and true or false
            c.ttsRepeat = ch.consumableTTSRepeatEnabled and true or false
            if ch.consumableTTSRepeatCount ~= nil then c.ttsRepeatCount = ch.consumableTTSRepeatCount end
            if ch.consumableTTSRepeatInterval ~= nil then c.ttsRepeatInterval = ch.consumableTTSRepeatInterval end
            c.itemTTS = (type(ch.consumableTTSSettings) == "table" and next(ch.consumableTTSSettings)) and Copy(ch.consumableTTSSettings) or nil
        end
    end)
    if not ok then return false, "Readycheck's settings could not be read (" .. tostring(err) .. ")" end
    if #done == 0 then return false, "Readycheck has no bar settings on this character" end
    if CB.Button then CB.Button.Restyle() end
    if CB.Live then
        for _, key in ipairs(CB.BARS) do if CB.Live.Place then pcall(CB.Live.Place, key) end end
        pcall(CB.Live.Refresh)
    end
    if ns.SettingsChanged then ns.SettingsChanged("consbars.import") end
    return true, "copied the " .. table.concat(done, ", ")
end

-- Readycheck's own copy of a bar off: its saved switch, then its own
-- visibility pass (it hides the bar; in combat it does so when the fight
-- ends). -> true / false, and a short reason.
local RC_REFRESH = { main = "UpdateConsumablesVisibility", potions = "UpdatePotionsVisibility",
    weapons = "UpdateWeaponsVisibility" }
function CB.TurnOffReadycheck(key)
    local RC = CB.RC()
    if not RC then return false, "Readycheck is not loaded" end
    if not CB.RC_KEYS[key] then return false, "no such bar" end
    local ok, err = pcall(function()
        local d = RC.db[CB.RC_KEYS[key]]
        if type(d) ~= "table" then error("no settings for that bar") end
        d.enabled = false
        local fn = RC[RC_REFRESH[key]]
        if type(fn) == "function" then fn(RC) end
        if type(RC.SaveConfigurationToProfile) == "function" then RC:SaveConfigurationToProfile() end
    end)
    if not ok then return false, "Readycheck's bar could not be switched off (" .. tostring(err) .. ")" end
    if ns.SettingsChanged then ns.SettingsChanged("consbars.rcoff") end
    return true, "Readycheck's " .. CB.LABELS[key]:lower() .. " is off"
end
