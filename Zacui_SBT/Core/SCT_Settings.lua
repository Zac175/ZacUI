-- SCT_Settings - ZacUI's scrolling combat text: its settings, and the
-- small lookups every other file of the part shares.
-- Part of ZacUI (Zacui_SBT). Written for ZacUI; the first file of the part.
--
-- Everything lives in ZacUIDB.sct, so it rides in ZacUI profiles, in
-- profile strings and in ZacLayout's copies like any other module. A
-- profile that predates this engine simply has no "sct" table; Cfg()
-- builds one from the defaults below, which are Zac's own setup: hits
-- you take drift left out of a box left of your character, hits you
-- land drift right out of one on the right, notices sit in a small
-- stack above.
--
-- Only what differs from the catalogue is stored for events (sct.events)
-- so a later change to an event's default reaches everyone who never
-- touched it.
local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local S = ns.SBT or {}
ns.SBT = S
S.addon = ADDON_NAME
-- Forever's rules (no combat log): on that client, and under the game-
-- version override's Forever (Core_Flavor), which only switches the
-- combat log off - the hits you take still come from UNIT_COMBAT
S.FOREVER = (_G.ZACUI_MODERN or (ns.NoCombatLog and ns.NoCombatLog())) and true or false

-- ============================================================
-- DEFAULTS
-- ============================================================
-- An area is a box on the screen: its bottom-left corner sits x, y from
-- the middle of the screen, and text moves inside its w x h.
--   style   "horizontal" slides sideways; rows stack in the box
--           "up" / "down" scrolls the height of the box
--           "arc"        scrolls up on a curve out to one side
--           "static"     a stack of lines that hold, then fade
--   dir     horizontal: "left", "right" or "alt" (each line the other way)
--           arc: "left", "right" or "alt"
--   grow    horizontal/static: which way new rows are added ("up"/"down")
--   align   "LEFT", "CENTER", "RIGHT" - where in the box a line starts
--   iconSide "LEFT" / "RIGHT" - which side of the number the icon sits
--   size / critSize / font: nil = the part's own
--   alpha / critAlpha: 0-100
local AREA_DEFAULTS = {
    incoming = { name = "Incoming", on = true, x = -240, y = -40, w = 40, h = 75,
        style = "horizontal", dir = "left", grow = "up", align = "CENTER",
        iconSide = "RIGHT", alpha = 90, critAlpha = 100 },
    outgoing = { name = "Outgoing", on = true, x = 210, y = -70, w = 40, h = 75,
        style = "horizontal", dir = "right", grow = "up", align = "CENTER",
        iconSide = "RIGHT", alpha = 90, critAlpha = 100 },
    notification = { name = "Notification", on = true, x = -174, y = 292, w = 350, h = 60,
        style = "static", dir = "up", grow = "up", align = "CENTER",
        iconSide = "LEFT", size = 10, critSize = 12, alpha = 75, critAlpha = 100 },
    static = { name = "Static", on = false, x = -22, y = 338, w = 40, h = 50,
        style = "static", dir = "down", grow = "down", align = "CENTER",
        iconSide = "LEFT", size = 12, critSize = 14, alpha = 100, critAlpha = 100 },
}
S.AREA_DEFAULTS = AREA_DEFAULTS
S.AREA_ORDER = { "incoming", "outgoing", "notification", "static" }

local DEFAULTS = {
    enabled     = false,      -- off on a fresh install (2026-11-08, Zac); Fill only writes missing keys, so a save that has it keeps it
    font        = false,      -- false: the font ZacUI wears
    outline     = "OUTLINE",  -- "", "OUTLINE", "THICKOUTLINE", "MONOCHROME"
    shadow      = true,
    size        = 10,
    critSize    = 12,
    speed       = 100,        -- percent; 100 is the pace Zac plays at
    icons       = true,       -- the ability's icon beside the number
    names       = false,      -- the ability's name as well
    shortNames  = true,       -- names as initials ("Heroic Strike" -> "HS")
    groupDigits = true,       -- 12,345
    healMin     = 700,        -- heals smaller than this are not shown
    damageMin   = 0,          -- nor hits smaller than this
    merge       = true,       -- one line for a spell that hits several times at once
    partials    = true,       -- "(120 resisted)" after a partly-resisted hit
    overheal    = false,      -- show only the part of a heal that landed
    stickyCrits = false,      -- crits pop in the middle of their area instead of moving
    sounds      = true,       -- alerts that have a sound play it
    areas       = {},         -- filled from AREA_DEFAULTS
    events      = {},         -- per-event changes over the catalogue
    alerts      = {},         -- per-alert changes over SCT_Alerts' catalogue
    auraAlerts  = {           -- your own "this aura went up" lines
        { name = "Improved Hamstring", text = "Improved Hamstring", unit = "target",
          on = false, sticky = true, size = 26, r = 1, g = 1, b = 0 },
    },
    hide        = {},         -- [ability name] = true: never shown
    plates      = {},         -- your hits on nameplates (SCT_PlateText)
    -- the shadow behind the text, when shadow is on
    shadowX     = 1,
    shadowY     = -1,
    -- MOTION (the Animation tab). Every default is the timing the part
    -- has always had, so nothing moves differently until it is changed.
    fadeIn      = 0.06,       -- seconds a new line takes to appear
    fadeOut     = 20,         -- percent: a moving line fades over the last part of its life
    fadeOutStatic = 25,       -- the same for a line stacked in place
    ease        = "linear",   -- how a moving line travels (an easing id)
    stackSpeed  = 14,         -- how quickly a stack slides to make room
    stickyHold  = 1.6,        -- seconds a sticky line holds (at speed 100)
    stickyFade  = 0.4,        -- seconds it takes to fade
    stickyScale = 160,        -- percent: the size a pop starts from
    stickyIn    = { style = "pop", duration = 0.14, delay = 0, easing = "linear",
                    dir = "up", distance = 20 },
}
S.DEFAULTS = DEFAULTS

-- Per area, nil means "the same as the General settings": font, size,
-- crit size, outline, shadow and speed.

local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end
S.Copy = Copy

-- The stored table, with every default filled in. Done once per table:
-- a profile switch or an import puts a new table at ZacUIDB.sct, and the
-- next call fills that one.
local filled
local function Fill(c)
    for k, v in pairs(DEFAULTS) do
        if c[k] == nil then c[k] = Copy(v) end
    end
    for key, def in pairs(AREA_DEFAULTS) do
        local a = c.areas[key]
        if type(a) ~= "table" then
            a = {}
            c.areas[key] = a
        end
        for k, v in pairs(def) do
            if a[k] == nil then a[k] = v end
        end
    end
    -- the first version kept the nameplate numbers outside every profile
    if not c._platesFrom1 then
        c._platesFrom1 = true
        local old = type(ZacUIDB) == "table" and rawget(ZacUIDB, "sbtPlates")
        if type(old) == "table" then
            for k, v in pairs(old) do
                if c.plates[k] == nil and type(k) == "string" and k:sub(1, 1) ~= "_" then
                    c.plates[k] = Copy(v)
                end
            end
        end
    end
end

function S.Cfg()
    if type(ZacUIDB) ~= "table" then
        if not S._loose then
            S._loose = Copy(DEFAULTS)
            Fill(S._loose)
        end
        return S._loose
    end
    local c = ZacUIDB.sct
    if c ~= nil and c == filled then return c end
    if type(c) ~= "table" then
        c = {}
        ZacUIDB.sct = c
    end
    Fill(c)
    filled = c
    if S.OnNewSettings then S.OnNewSettings() end
    return c
end

-- Everything back to the defaults (the Restore button).
function S.ResetAll()
    if type(ZacUIDB) ~= "table" then return end
    ZacUIDB.sct = {}
    filled = nil
    S.Cfg()
    if S.Rebuild then S.Rebuild() end
end

-- ============================================================
-- AREAS
-- ============================================================
function S.Area(key)
    local a = S.Cfg().areas[key]
    return type(a) == "table" and a or nil
end

-- Every area, built-ins first in their usual order, then your own by name.
function S.Areas()
    local c, out, seen = S.Cfg(), {}, {}
    for _, key in ipairs(S.AREA_ORDER) do
        local a = c.areas[key]
        if type(a) == "table" then
            out[#out + 1] = { key = key, name = a.name or key, area = a }
            seen[key] = true
        end
    end
    local extra = {}
    for key, a in pairs(c.areas) do
        if not seen[key] and type(a) == "table" then
            extra[#extra + 1] = { key = key, name = a.name or key, area = a }
        end
    end
    table.sort(extra, function(p, q) return tostring(p.name) < tostring(q.name) end)
    for _, e in ipairs(extra) do out[#out + 1] = e end
    return out
end

function S.AreaName(key)
    local a = S.Area(key)
    return a and a.name or tostring(key)
end

function S.IsBuiltInArea(key)
    return AREA_DEFAULTS[key] ~= nil
end

function S.AddArea(name)
    name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if name == "" then return nil, "Give the area a name." end
    for _, e in ipairs(S.Areas()) do
        if e.name:lower() == name:lower() then return nil, "There is already an area called " .. name .. "." end
    end
    local c = S.Cfg()
    local n, key = 1, nil
    repeat
        key = "custom" .. n
        n = n + 1
    until c.areas[key] == nil
    c.areas[key] = { name = name, on = true, x = -20, y = 120, w = 40, h = 120,
        style = "up", dir = "left", grow = "up", align = "CENTER", iconSide = "LEFT",
        alpha = 100, critAlpha = 100 }
    if S.Rebuild then S.Rebuild() end
    return key
end

function S.DeleteArea(key)
    if S.IsBuiltInArea(key) then return false end
    local c = S.Cfg()
    c.areas[key] = nil
    -- anything sent there goes back to where it started
    for _, ev in pairs(c.events) do
        if type(ev) == "table" and ev.area == key then ev.area = nil end
    end
    for _, al in pairs(c.alerts) do
        if type(al) == "table" and al.area == key then al.area = nil end
    end
    for _, al in ipairs(c.auraAlerts) do
        if type(al) == "table" and al.area == key then al.area = nil end
    end
    if S.Rebuild then S.Rebuild() end
    return true
end

function S.ResetAreaPosition(key)
    local a, def = S.Area(key), AREA_DEFAULTS[key]
    if not a then return end
    a.x = def and def.x or -20
    a.y = def and def.y or 120
    if S.Rebuild then S.Rebuild() end
end

-- ============================================================
-- FONTS AND SOUNDS
-- ============================================================
S.OUTLINES = {
    { value = "",             text = "None" },
    { value = "OUTLINE",      text = "Outline" },
    { value = "THICKOUTLINE", text = "Thick outline" },
    { value = "MONOCHROME",   text = "Monochrome" },
}

local function LSM()
    return LibStub and LibStub("LibSharedMedia-3.0", true)
end

-- An outline as the settings hold it (the client's flag strings, or the
-- picker's ids) -> the flags SetFont takes.
local FLAG_OF = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE", monochrome = "MONOCHROME" }
function S.Flags(v)
    if v == nil then return "OUTLINE" end
    if FLAG_OF[v] then return FLAG_OF[v] end
    return tostring(v)
end
-- ... and the other way, for the font picker
function S.OutlineId(v)
    if v == nil then return nil end
    if FLAG_OF[v] then return v end
    local u = tostring(v):upper()
    if u == "" or u == "NONE" then return "none" end
    if u:find("MONOCHROME", 1, true) then return "monochrome" end
    if u:find("THICK", 1, true) then return "thick" end
    return "outline"
end

-- The global motion switches (Appearance > Motion): on/off and speed.
-- Read at the moment a line starts, never cached.
function S.MotionOn()
    local M = ns.Motion
    return not (M and M.Enabled and not M.Enabled())
end
function S.MotionSpeed()
    local M = ns.Motion
    local s = M and M.Speed and M.Speed() or 1
    return (s and s > 0) and s or 1
end
-- an easing id -> its curve (straight when none is known)
local function Linear(t) return t end
function S.Ease(id)
    local E = (ns.Motion and ns.Motion.EASE) or ns.EASE
    return (E and id and E[id]) or Linear
end

-- name (or a file path, or false for ZacUI's own) -> a file SetFont takes.
-- One font: ZacUI's whenever one is chosen - a face saved for the text or
-- one area counts only while ZacUI has none.
function S.FontPath(name)
    local one = ns.OneFace and ns.OneFace()
    if one then return one end
    local resolve = ns.ResolveFontPath
    local path
    if type(name) == "string" and name ~= "" and resolve then path = resolve(name) end
    if not path and resolve and type(ZacUIDB) == "table" and type(ZacUIDB.font) == "table" then
        path = resolve(ZacUIDB.font.name)
    end
    return path or ns.MEDIA_FONT_MAIN or STANDARD_TEXT_FONT
end

function S.FontNames()
    local lib, out = LSM(), {}
    if lib then
        for _, n in ipairs(lib:List("font")) do out[#out + 1] = n end
    end
    return out
end

function S.SoundNames()
    local lib, out = LSM(), {}
    if lib then
        for _, n in ipairs(lib:List("sound")) do
            if n ~= "None" then out[#out + 1] = n end
        end
    end
    return out
end

function S.PlaySound(name)
    if type(name) ~= "string" or name == "" then return end
    -- "ui:Pop", "tts:...", an old pack name or path (Core_Sounds)
    if ns.PlaySoundRef then ns.PlaySoundRef(name, "Master") return end
    local lib = LSM()
    local file = lib and lib:Fetch("sound", name, true)
    if not file and (name:find("\\", 1, true) or name:find("/", 1, true)) then file = name end
    if file then pcall(PlaySoundFile, file, "Master") end
end

-- ============================================================
-- BLIZZARD'S OWN NUMBERS
-- ============================================================
-- The game draws its own damage numbers over what you hit. They are a
-- game option, not ours; the page only offers the switch.
local DAMAGE_CVARS = { "floatingCombatTextCombatDamage", "floatingCombatTextCombatLogPeriodicSpells",
    "floatingCombatTextPetMeleeDamage", "floatingCombatTextPetSpellDamage" }
local HEAL_CVARS = { "floatingCombatTextCombatHealing" }

local function CVarGet(name)
    if not GetCVar then return nil end
    local ok, v = pcall(GetCVar, name .. "_v2")
    if ok and v ~= nil then return v end
    ok, v = pcall(GetCVar, name)
    if ok then return v end
    return nil
end

local function CVarSet(name, value)
    if not SetCVar and not (ns and ns.CVar) then return end
    for _, cv in ipairs({ name .. "_v2", name }) do
        local ok, v = pcall(GetCVar, cv)
        if ok and v ~= nil then
            -- SETUP2: through ns.CVar (recorded; put back when the part is off)
            if ns and ns.CVar then ns.CVar.Set(cv, value, "Zacui_SBT") else pcall(SetCVar, cv, value) end
        end
    end
end

function S.BlizzardDamageOn() return CVarGet(DAMAGE_CVARS[1]) == "1" end
function S.BlizzardHealingOn() return CVarGet(HEAL_CVARS[1]) == "1" end
function S.SetBlizzardDamage(on)
    for _, cv in ipairs(DAMAGE_CVARS) do CVarSet(cv, on and "1" or "0") end
end
function S.SetBlizzardHealing(on)
    for _, cv in ipairs(HEAL_CVARS) do CVarSet(cv, on and "1" or "0") end
end

-- ============================================================
-- SMALL SHARED PIECES
-- ============================================================
function S.Say(msg)
    if ns.Print then ns.Print(msg) end
end

function S.IsOn()
    return S.Cfg().enabled ~= false
end

function S.SetOn(on)
    S.Cfg().enabled = on and true or false
    if S.Rebuild then S.Rebuild() end
    -- SETUP2: the part off hands back the game's damage text settings it wrote
    if not on and ns and ns.CVar then pcall(ns.CVar.RestoreOwner, "Zacui_SBT") end
end
-- SETUP2: the CVar record asks whether this part is off (its own switch, not only the AddOns list)
if ns and ns.CVar and ns.CVar.OwnerCheck then
    ns.CVar.OwnerCheck("Zacui_SBT", function() return not S.IsOn() end)
end

local function SortedKeys(t)
    local out = {}
    for k in pairs(t or {}) do out[#out + 1] = k end
    table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
    return out
end
S.SortedKeys = SortedKeys

-- ============================================================
-- THE GAME'S OWN COMBAT TEXT AFTER A LOADING SCREEN
-- ============================================================
-- The game's floating text ("-Combat" when a fight ends) can freeze on
-- screen when a loading screen (a summon, a zone-in, a login) lands while
-- one of its lines is up: the line stays, never fading. After each loading
-- screen its lines are cleared once, so a frozen one goes away. Only the
-- game's own lines; nothing else of the game's text is changed.
local function ClearGameCombatText()
    local n = tonumber(NUM_COMBAT_TEXT_LINES) or 20
    for i = 1, n do
        local s = _G["CombatText" .. i]
        if s and s.Hide then
            if s.SetAlpha then s:SetAlpha(0) end
            s:Hide()
        end
    end
    if type(COMBAT_TEXT_TO_ANIMATE) == "table" then
        for k in pairs(COMBAT_TEXT_TO_ANIMATE) do COMBAT_TEXT_TO_ANIMATE[k] = nil end
    end
end
S.ClearGameCombatText = ClearGameCombatText

-- Every shown text on screen that reads exactly txt (any addon's), with
-- where it hangs: "/zui findtext -Combat" says whose a stuck line is.
-- Each step: the client's debug name when it has one ("Parent.key" or the
-- addon's own name), else the frame's name, else its type; then whose it
-- is, when a frame on the path carries an owner we know. Only runs when
-- something is reported, so it may take its time.
local OWNERS = {
    -- a ZacUI aura display (imported packs' "+ Combat" / "- Combat")
    { "ZacUI auras", function(f)
        local id, rt = rawget(f, "id"), rawget(f, "regionType")
        if type(id) == "string" and type(rt) == "string" then return "ZacUI aura \"" .. id .. "\"" end end },
    { "ZacUI", function(f, name)
        return rawget(f, "_zui_own") or rawget(f, "_zElement") or rawget(f, "zSample")
            or (name and (name:find("^ZacUI") or name:find("^Zacui"))) end },
    { "Readycheck", function(f, name)
        return rawget(f, "WR") or rawget(f, "rcOwner")
            or (name and (name:find("^Readycheck") or name:find("^WarriorReminder") or name:find("^WR_"))) end },
    { "the game's combat text", function(f, name) return name and name:find("^CombatText") end },
}
local function StepName(f)
    local dn
    if f.GetDebugName then
        local ok, v = pcall(f.GetDebugName, f)
        if ok and type(v) == "string" and v ~= "" then dn = v end
    end
    local name = f.GetName and f:GetName()
    return dn or name or ("<" .. (f.GetObjectType and f:GetObjectType() or "?") .. ">"), name or dn
end
local function RegionPath(r)
    local parts, n, f, owner = {}, 0, r, nil
    while f and n < 8 do
        local label, name = StepName(f)
        parts[#parts + 1] = label
        if not owner then
            for _, o in ipairs(OWNERS) do
                local ok, hit = pcall(o[2], f, name)
                if ok and hit then owner = type(hit) == "string" and hit or o[1] break end
            end
        end
        f = f.GetParent and f:GetParent()
        n = n + 1
    end
    local path = table.concat(parts, " < ")
    if owner then path = path .. "  [" .. owner .. "]" end
    return path
end
S.RegionPath = RegionPath
function S.FindShownText(txt)
    local out = {}
    if not EnumerateFrames then return out end
    local f = EnumerateFrames()
    while f do
        if f.GetRegions and f.IsVisible and f:IsVisible() then
            for i = 1, select("#", f:GetRegions()) do
                local r = select(i, f:GetRegions())
                if r and r.GetObjectType and r:GetObjectType() == "FontString" and r:IsVisible()
                    and r.GetText and r:GetText() == txt then
                    out[#out + 1] = r
                end
            end
        end
        f = EnumerateFrames(f)
    end
    return out, RegionPath
end

-- Any shown "-Combat" / "+Combat" that isn't one of our own lines still
-- inside its life is a frozen leftover - hide it. Our own line goes as a
-- whole (its frame), never just its text: a pooled line is reused, and a
-- hidden text would stay hidden in every line after it. The first time a
-- given frame is caught, chat says whose it was (so the source shows itself
-- without anyone typing /findtext).
local reported = {}
-- The two places a combat note can come from, without walking every frame
-- (cheap enough to run in a fight): the game's floating text lines and our
-- engine's lines.
local function KnownShownText(txt)
    local out = {}
    local n = tonumber(NUM_COMBAT_TEXT_LINES) or 20
    for i = 1, n do
        local r = _G["CombatText" .. i]
        if r and r.IsVisible and r:IsVisible() and r.GetText and r:GetText() == txt then out[#out + 1] = r end
    end
    local made = S.engine and S.engine.made
    if made then
        for i = 1, #made do
            local r = made[i].fs
            if r and r:IsVisible() and r:GetText() == txt then out[#out + 1] = r end
        end
    end
    return out, RegionPath
end

local function HideFrozenCombatNotes(txts, cheap)
    local now = GetTime()
    local hidSome = false
    for _, txt in ipairs(txts or { "-Combat", "+Combat" }) do
        local list, path
        if cheap then list, path = KnownShownText(txt) else list, path = S.FindShownText(txt) end
        for _, r in ipairs(list) do
            local p = r.GetParent and r:GetParent()
            local ours = p and p.born and p.fs == r
            local live = ours and p.st and (now - p.born) < ((tonumber(p.life) or 3) + 0.5)
            if not live then
                local where = path and path(r) or "?"
                if ours then
                    if p.SetAlpha then p:SetAlpha(0) end
                    p:Hide()
                    hidSome = true
                else
                    if r.SetAlpha then r:SetAlpha(0) end
                    r:Hide()
                end
                if not reported[where] then
                    reported[where] = true
                    S.Say("hid a stuck \"" .. txt .. "\" (" .. (ours and "ZacUI scrolling text" or where) .. ").")
                end
            end
        end
    end
    if hidSome and S.engine and S.engine.Sweep then pcall(S.engine.Sweep, S.engine) end
end
S.HideFrozenCombatNotes = HideFrozenCombatNotes

local loadWatch = CreateFrame("Frame")
loadWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
-- entering and leaving combat (twice a fight, not a combat-log event): a
-- "+Combat" still up a few seconds into the fight, or a "-Combat" a few
-- seconds after it, is stuck - whoever drew it (Zac 2026-11-02: "+combat
-- stays on screen while im in combat")
loadWatch:RegisterEvent("PLAYER_REGEN_DISABLED")
loadWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
local combatSerial = 0
loadWatch:SetScript("OnEvent", function(_, event)
    if not (C_Timer and C_Timer.After) then return end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        combatSerial = combatSerial + 1
        local mine = combatSerial
        local which = (event == "PLAYER_REGEN_DISABLED") and { "+Combat" } or { "-Combat", "+Combat" }
        local function Check()
            if mine ~= combatSerial then return end
            pcall(HideFrozenCombatNotes, which, InCombatLockdown and InCombatLockdown())
        end
        C_Timer.After(4, Check)
        C_Timer.After(9, Check)
        return
    end
    -- after a loading screen: once now, and once a moment later (the game
    -- can still be finishing the line it started as the screen came down)
    pcall(ClearGameCombatText)
    C_Timer.After(1, function() pcall(ClearGameCombatText) end)
    C_Timer.After(3, function() pcall(HideFrozenCombatNotes) end)
end)

-- /findtext <text>: lists every shown text that reads exactly that, and
-- what it hangs from (finds whose a stuck line is). /findtext clear also
-- hides any frozen "-Combat" / "+Combat" now.
if type(SlashCmdList) == "table" then
SLASH_ZACUIFINDTEXT1 = "/findtext"
SlashCmdList.ZACUIFINDTEXT = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "clear" then
        pcall(ClearGameCombatText)
        pcall(HideFrozenCombatNotes)
        S.Say("Cleared any frozen combat text.")
        return
    end
    if msg == "" then msg = "-Combat" end
    local list, path = S.FindShownText(msg)
    if #list == 0 then S.Say("No shown text reads \"" .. msg .. "\".") return end
    for _, r in ipairs(list) do
        local font = r.GetFont and select(1, r:GetFont()) or "?"
        S.Say("\"" .. msg .. "\": " .. path(r) .. "  (font " .. tostring(font) .. ")")
    end
end
end
