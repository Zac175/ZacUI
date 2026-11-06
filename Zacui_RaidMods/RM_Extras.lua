-- RM_Extras - extra boss helpers next to the raid modules: things Zac
-- wanted on top of them, with their switches on the Raid mods page.
-- Part of ZacUI; load order is set by the TOC.
--
-- INSTRUCTOR RAZUVIOUS: the moment he targets you, a big icon and an
-- air horn - his Unbalancing Strike kills whoever is not the mind-
-- controlled understudy. Armed by his pull (encounter 1113, from
-- ns.Encounter) only; while
-- armed, UNIT_TARGET from any unit (nameplates, target, raid targets)
-- is checked for him, and a 0.5s poll over the nameplates backs that
-- up for a plate that never raised the event. The alert stays while he
-- is on you, then a short grace, then it goes. Nothing runs outside his
-- fight.
--
-- ANY RAID BOSS (2026-11-04, Zac: "instead of just raz can we make it all
-- bosses"): the same alert and air horn when any raid boss turns on you -
-- by its threat (UnitDetailedThreatSituation isTanking), so a boss
-- pointing a cast at you for a moment (Onyxia's fireballs) does not set
-- it off. Off by default; one switch per boss on each raid's tab. Armed
-- by a raid encounter's pull only; never for whoever tanks that fight (in
-- Defensive Stance, bear form or Righteous Fury at any point of it, or
-- the raid's main tank). The Razuvious alert keeps his own fight.

local ns = _G.ZacUI
if not ns then return end
local RM = ns.RaidMods
if not RM then return end
local UI = ns.UI
local function GetColor(cat, key)
    local c = ns.GetColor and ns.GetColor(cat, key)
    if c then return c end
    return { r = 1, g = 0.25, b = 0.2, a = 1 }
end

local X = {}
RM.Extras = X

local RAZ_ENCOUNTER = 1113
local RAZ_NAME = "Instructor Razuvious"
local RAZ_STRIKE = 26613                  -- Unbalancing Strike (its icon)
local AIR_HORN = "ui:Air horn"                -- the game's raid-warning horn
local POLL = 0.5
local HOLD = 2.0                           -- seconds the alert outlives his target leaving you
local SOUND_GAP = 4.0                      -- never two horns closer than this

local DEFAULTS = {
    razTarget = true,                      -- the alert at all
    razSound = true,                       -- the air horn
    razScale = 1,
    razText = "RAZUVIOUS ON YOU",
    bossTarget = false,                    -- any raid boss (off by default)
    bossSound = true,                      -- its air horn
}
local SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local BOSS_HOLD = 1.5

function X.RazIcon()
    local tex = GetSpellTexture and GetSpellTexture(RAZ_STRIKE)
    return tex or "Interface\\Icons\\Ability_Warrior_DecisiveStrike"
end
-- the words for a boss: "PATCHWERK ON YOU"
function X.BossText(name) return string.upper(name or "BOSS") .. " ON YOU" end

local function DB()
    local db = RM.DB()
    if not db then return nil end
    if type(db.extras) ~= "table" then db.extras = {} end
    local x = db.extras
    for k, v in pairs(DEFAULTS) do if x[k] == nil then x[k] = v end end
    if type(x.bossOff) ~= "table" then x.bossOff = {} end   -- [encounter id] = true: that boss switched off
    return x
end
X.DB = DB

-- ============================================================
-- THE ALERT
-- ============================================================
local alert

local function Paint(f)
    local red = GetColor("text", "red")
    f.text:SetTextColor(red.r, red.g, red.b, 1)
end

local function Pulse(self, elapsed)
    self._t = (self._t or 0) + elapsed
    local a = 0.7 + 0.3 * math.abs(math.sin(self._t * 6))
    self.text:SetAlpha(a)
    if self.plain then self.plain:SetAlpha(a) end
end

-- The alert's look on a frame: the big icon with its glow, the words and
-- the pulse. The live alert and the settings page's sample are both made
-- by this.
local function Dress(f, cfg)
    local size = 56
    local W = ns.WarriorHUD and ns.WarriorHUD.Widgets
    local icon
    if W and W.CreateIcon then
        icon = W.CreateIcon(f, { width = size, height = size, zoom = W.ICON_ZOOM or 0.12,
            keepAspect = true, noCooldown = true })
        local red = GetColor("text", "red")
        icon:AddGlow("alert", "Pixel", { color = { red.r, red.g, red.b, 1 }, thickness = 3 })
    else
        icon = CreateFrame("Frame", nil, f)
        icon:SetSize(size, size)
        local t = icon:CreateTexture(nil, "ARTWORK")
        t._zui_own = true
        t:SetAllPoints()
        t:SetTexCoord(0.06, 0.94, 0.06, 0.94)
        f.plain = t
        function icon:SetIconTexture(tex) t:SetTexture(tex) end
        function icon:SetGlow() end
    end
    icon:SetPoint("LEFT", f, "LEFT", 4, 0)
    f.icon = icon
    icon:SetIconTexture(X.RazIcon())

    local text = ns.HUD and ns.HUD.Text and ns.HUD.Text(f, 26, "THICKOUTLINE")
    if not text then
        text = f:CreateFontString(nil, "OVERLAY")
        if ns.ApplyFont then ns.ApplyFont(text, 26, "THICKOUTLINE") else text:SetFontObject(GameFontNormalHuge) end
    end
    text:SetPoint("LEFT", icon, "RIGHT", 12, 0)
    text:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    text:SetJustifyH("LEFT")
    text:SetText(cfg and cfg.razText or DEFAULTS.razText)
    f.text = text

    f:SetScript("OnUpdate", Pulse)
    f:HookScript("OnShow", function(self)
        self._t = 0
        self.icon:SetGlow("alert", false)
        self.icon:SetGlow("alert", true)
    end)
end

local function Build()
    if alert then return alert end
    local cfg = DB()
    local holder = CreateFrame("Frame", "ZacUIRM_RazTarget_Holder", UIParent)
    holder:SetSize(260, 84)
    holder:SetFrameStrata("HIGH")
    if ns.HUD and ns.HUD.PlaceAnchor then ns.HUD.PlaceAnchor("rmRazTarget", holder, { x = 0, y = 240 })
    else holder:SetPoint("CENTER", UIParent, "CENTER", 0, 240) end

    local f = CreateFrame("Frame", "ZacUIRM_RazTarget", holder)
    f:SetAllPoints()
    f:SetFrameStrata("HIGH")
    f:Hide()
    f.holder = holder
    Dress(f, cfg)
    f:SetScale(cfg and cfg.razScale or 1)
    if ns.HUD and ns.HUD.RegisterMover then
        ns.HUD.RegisterMover("rmRazTarget", "Boss on you", holder, { x = 0, y = 240 })
    end
    if UI and UI.HudHandle then
        f.handle = UI.HudHandle(f, {
            getLocked = function() return not (ns.IsMoverShown and ns.IsMoverShown("rmRazTarget")) end,
            setLocked = function() if ns.ToggleMover then ns.ToggleMover("rmRazTarget") end end,
            getScale = function() return tonumber(DB().razScale) or 1 end,
            setScale = function(v) DB().razScale = v f:SetScale(v) end,
            minScale = 0.6, maxScale = 2.0,
        })
    end
    alert = f
    Paint(f)
    return f
end

local lastHorn = 0
local function Horn(key)
    local db, cfg = RM.DB(), DB()
    if not (db and db.sounds and cfg and cfg[key or "razSound"]) then return end
    local now = GetTime()
    if now - lastHorn < SOUND_GAP then return end
    lastHorn = now
    RM.RaidSound(AIR_HORN, "Master")
end

function X:ShowRaz()
    local f = Build()
    local cfg = DB()
    f.text:SetText(cfg and cfg.razText or DEFAULTS.razText)
    f.icon:SetIconTexture(X.RazIcon())
    if not f:IsShown() then f:Show() end
end

-- the same alert for any boss: its name, a skull
function X:ShowBoss(name)
    local f = Build()
    f.text:SetText(X.BossText(name))
    f.icon:SetIconTexture(SKULL)
    if not f:IsShown() then f:Show() end
end

function X:HideRaz()
    if alert and alert:IsShown() then alert:Hide() end
end

function X:ApplyAppearance()
    local cfg = DB()
    if alert and cfg then
        alert:SetScale(cfg.razScale or 1)
        if ns.HUD and ns.HUD.PlaceAnchor then ns.HUD.PlaceAnchor("rmRazTarget", alert.holder, { x = 0, y = 240 }) end
        alert.text:SetText(cfg.razText or DEFAULTS.razText)
    end
end

-- The settings page's sample: the same alert (Dress), parented to the
-- preview's canvas - no name, no spot of its own, no mover, no handle, no
-- sound. Its pulse runs on its own OnUpdate, so it stops with the strip.
X.RAZ_W, X.RAZ_H = 260, 84
function X.NewRazSample(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(X.RAZ_W, X.RAZ_H)
    f:Hide()
    f.sample = true
    Dress(f, DB())
    Paint(f)
    return f
end
-- the sample follows the card: its words and its size, as ApplyAppearance does for the live one
function X.FillRazSample(f)
    local cfg = DB()
    f.text:SetText(cfg and cfg.razText or DEFAULTS.razText)
    f:SetScale(cfg and cfg.razScale or 1)
    Paint(f)
end
-- the "any boss" sample: the same alert with a boss's name and the skull
X.SAMPLE_BOSS = "Patchwerk"
function X.FillBossSample(f)
    local cfg = DB()
    f.text:SetText(X.BossText(X.SAMPLE_BOSS))
    f.icon:SetIconTexture(SKULL)
    f:SetScale(cfg and cfg.razScale or 1)
    Paint(f)
end
function X.RazScale()
    local cfg = DB()
    return cfg and tonumber(cfg.razScale) or 1
end

-- the page's Test button: three seconds of it
function X:PreviewRaz()
    self:ShowRaz()
    lastHorn = 0
    Horn()
    C_Timer.After(3, function() if not X.onMe then X:HideRaz() end end)
end
function X:PreviewBoss()
    self:ShowBoss(X.SAMPLE_BOSS)
    lastHorn = 0
    Horn("bossSound")
    C_Timer.After(3, function() if not (X.onMe or X.bossOnMe) then X:HideRaz() end end)
end

-- ============================================================
-- THE WATCH
-- ============================================================
X.armed = false
X.onMe = false
local poll, offAt

-- is this unit him, and is he on me?
local function RazOnMe(unit)
    if not UnitExists(unit) then return nil end
    if UnitName(unit) ~= RAZ_NAME then return nil end
    return UnitIsUnit(unit .. "target", "player") and true or false
end

local function SetOnMe(on)
    local now = GetTime()
    if on then
        offAt = nil
        if not X.onMe then
            X.onMe = true
            X:ShowRaz()
            Horn()
        end
    elseif X.onMe then
        -- a short hold: his target flickers during the understudy swaps
        offAt = offAt or (now + HOLD)
        if now >= offAt then
            X.onMe = false
            offAt = nil
            X:HideRaz()
        end
    end
end

-- the poll: him on any nameplate, or under my own target
local PLATES = {}
for i = 1, 40 do PLATES[i] = "nameplate" .. i end
local function Scan()
    local hit = nil
    for i = 1, 40 do
        local r = RazOnMe(PLATES[i])
        if r ~= nil then hit = r if r then break end end
    end
    if not hit then
        local r = RazOnMe("target")
        if r then hit = true end
    end
    if hit == nil and X.onMe then hit = false end
    if hit ~= nil then SetOnMe(hit) end
end

local function Arm()
    if X.armed then return end
    local cfg = DB()
    if not (cfg and cfg.razTarget) then return end
    local db = RM.DB()
    if not (db and db.enabled) then return end
    X.armed = true
    X.onMe = false
    offAt = nil
    X.ev:RegisterEvent("UNIT_TARGET")
    if ns.HUD and ns.HUD.Ticker then poll = ns.HUD.Ticker(POLL, Scan, "rm.raz")
    else
        poll = C_Timer.NewTicker(POLL, Scan)
        if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(poll, "rm.raz") end
    end
end

local function Disarm()
    if not X.armed then return end
    X.armed = false
    X.onMe = false
    offAt = nil
    X.ev:UnregisterEvent("UNIT_TARGET")
    if poll then poll:Cancel() poll = nil end
    X:HideRaz()
end

-- ============================================================
-- ANY RAID BOSS
-- ============================================================
X.bossArmed, X.bossOnMe, X.tanked = false, false, false
local bossPoll, bossOffAt, lastBossScan = nil, nil, 0
local BOSS_POLL, BOSS_GAP = 0.25, 0.05
local BOSS_UNITS = { "boss1", "boss2", "boss3", "boss4", "boss5", "target", "focus" }
local _, myClass = UnitClass("player")

-- tanking this fight: in the form you tank in, or the raid's main tank
local function TankForm()
    if myClass == "WARRIOR" then return GetShapeshiftForm and GetShapeshiftForm() == 2 or false end
    if myClass == "DRUID" then return GetShapeshiftForm and GetShapeshiftForm() == 1 or false end
    if myClass == "PALADIN" then
        local A = ns.PlayerAuras
        return (A and A.Buff and A.Buff(25780)) and true or false
    end
    return false
end
local function Tank()
    if TankForm() then return true end
    return (GetPartyAssignment and GetPartyAssignment("MAINTANK", "player")) and true or false
end
X.Tank = Tank

-- a raid boss with you at the top of its threat (nil when it is not a boss)
local function BossOnMe(u)
    if not UnitExists(u) or UnitClassification(u) ~= "worldboss" then return nil end
    if not UnitCanAttack("player", u) then return nil end
    local isTanking = UnitDetailedThreatSituation("player", u)
    return isTanking and true or false
end

local function SetBossOnMe(name)
    local now = GetTime()
    if name then
        bossOffAt = nil
        if not X.bossOnMe then
            X.bossOnMe = true
            X:ShowBoss(name)
            Horn("bossSound")
        end
    elseif X.bossOnMe then
        bossOffAt = bossOffAt or (now + BOSS_HOLD)
        if now >= bossOffAt then
            X.bossOnMe = false
            bossOffAt = nil
            X:HideRaz()
        end
    end
end

local seen = {}
local function BossScan()
    if not X.bossArmed then return end
    lastBossScan = GetTime()
    if not X.tanked and Tank() then X.tanked = true end
    if X.tanked then
        if X.bossOnMe then X.bossOnMe = false bossOffAt = nil X:HideRaz() end
        return
    end
    for k in pairs(seen) do seen[k] = nil end
    local hit
    for i = 1, #BOSS_UNITS do
        local u = BOSS_UNITS[i]
        if BossOnMe(u) then hit = UnitName(u) break end
        local g = UnitGUID(u)
        if g then seen[g] = true end
    end
    if not hit then
        for i = 1, 40 do
            local u = PLATES[i]
            local g = UnitGUID(u)
            if g and not seen[g] then
                seen[g] = true
                if BossOnMe(u) then hit = UnitName(u) break end
            end
        end
    end
    SetBossOnMe(hit)
end
X.BossScan = BossScan

local function ArmBoss(id)
    if X.bossArmed then return end
    local cfg = DB()
    if not (cfg and cfg.bossTarget) or cfg.bossOff[id] then return end
    local db = RM.DB()
    if not (db and db.enabled) then return end
    local _, kind = IsInInstance()
    if kind ~= "raid" then return end
    X.bossArmed, X.bossOnMe, X.tanked = true, false, Tank()
    bossOffAt = nil
    X.ev:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    if ns.HUD and ns.HUD.Ticker then bossPoll = ns.HUD.Ticker(BOSS_POLL, BossScan, "rm.boss")
    else
        bossPoll = C_Timer.NewTicker(BOSS_POLL, BossScan)
        if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(bossPoll, "rm.boss") end
    end
end
X.ArmBoss = ArmBoss

local function DisarmBoss()
    if not X.bossArmed then return end
    X.bossArmed, X.bossOnMe, X.tanked = false, false, false
    bossOffAt = nil
    X.ev:UnregisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    if bossPoll then bossPoll:Cancel() bossPoll = nil end
    X:HideRaz()
end
X.DisarmBoss = DisarmBoss

-- his pull and its end (a kill, a wipe, or the group simply out of
-- combat with no ENCOUNTER_END) come from ZacUI's encounter tracker
ns.Encounter.On("RaidMods.raz", function(event, id)
    if event == "start" then
        local cfg = DB()
        if id == RAZ_ENCOUNTER and cfg and cfg.razTarget then Arm()
        else ArmBoss(id) end
    else
        Disarm()
        DisarmBoss()
    end
end)

local ev = CreateFrame("Frame")
X.ev = ev
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, event, a1)
    if event == "PLAYER_ENTERING_WORLD" then
        Disarm()
        DisarmBoss()
    elseif event == "UNIT_THREAT_SITUATION_UPDATE" then
        -- your threat standing changed somewhere: look now (at most every 0.05 s)
        if a1 == "player" and GetTime() - lastBossScan >= BOSS_GAP then BossScan() end
    elseif event == "UNIT_TARGET" then
        local r = RazOnMe(a1)
        if r ~= nil then SetOnMe(r) end
    end
end)

-- ============================================================
-- SETTINGS CARD (on the Raid mods page, General tab)
-- ============================================================
function X.BuildCard(L, Check, Button, Slider)
    local cfg = DB()
    if not cfg then return end
    -- the alert's own controls show it in the strip (the change that follows draws it)
    local function Show()
        if ns.ConfigPreview and ns.ConfigPreview.UseMode then ns.ConfigPreview.UseMode("raidmods.bars", "raz") end
    end
    L:Card("Extras")
    L:Desc("Hand-made helpers on top of the packs.")
    Check(L, "Instructor Razuvious: when he targets me", cfg.razTarget, function(v)
        cfg.razTarget = v and true or false
        Show()
        if not v then Disarm() end
    end, "A big icon and \"" .. (cfg.razText or DEFAULTS.razText) .. "\" the moment he turns on you, "
        .. "with an air horn (needs \"Sounds and voice\" on). Only during his fight; moves with the Movers page.")
    Check(L, "Air horn", cfg.razSound, function(v) cfg.razSound = v and true or false end, nil, true)
    if Slider then
        Slider(L, { width = 200, min = 0.6, max = 2, step = 0.1, value = cfg.razScale or 1, label = "Size",
            format = function(v) return math.floor(v * 100 + 0.5) .. "%" end,
            onChange = function(v) cfg.razScale = v Show() X:ApplyAppearance() end })
    end
    Button(L, "Test", function() X:PreviewRaz() end, 100)
    local function ShowBoss()
        if ns.ConfigPreview and ns.ConfigPreview.UseMode then ns.ConfigPreview.UseMode("raidmods.bars", "boss") end
    end
    Check(L, "Any raid boss: when it turns on me", cfg.bossTarget, function(v)
        cfg.bossTarget = v and true or false
        ShowBoss()
        if not v then DisarmBoss() end
    end, "The same big icon and air horn, with the boss's name, the moment any raid boss has you at the top of "
        .. "its threat (a spell it points at you for a moment does not count). Never for whoever tanks the fight. "
        .. "Switch single bosses off on each raid's tab. Shares the size and spot above.")
    Check(L, "Air horn", cfg.bossSound, function(v) cfg.bossSound = v and true or false end, nil, true)
    Button(L, "Test", function() X:PreviewBoss() end, 100)
    L:EndCard()
end

-- each raid's tab: one switch per boss for the "any raid boss" alert
-- (one per name: a boss the packs file under two encounter ids is one).
-- The packs' encounter names are short hands (and one typo); the card
-- shows the boss's full name.
local FULL_NAME = {
    ["4HM"] = "Four Horsemen", ["Anub"] = "Anub'Rekhan", ["Grand Widow"] = "Grand Widow Faerlina",
    ["Broodlord"] = "Broodlord Lashlayer", ["Vael"] = "Vaelastrasz", ["Majordomo"] = "Majordomo Executus",
    ["Sulfuron"] = "Sulfuron Harbinger", ["Skeram"] = "The Prophet Skeram", ["Bug Trio"] = "Silithid Royalty",
    ["Sartura"] = "Battleguard Sartura", ["Fankriss"] = "Fankriss the Unyielding", ["Huhuran"] = "Princess Huhuran",
    ["C'thun"] = "C'Thun", ["Venoxis"] = "High Priest Venoxis", ["Jeklik"] = "High Priestess Jeklik",
    ["Mar'li"] = "High Priestess Mar'li", ["Thekal"] = "High Priest Thekal", ["Arlokk"] = "High Priestess Arlokk",
    ["Jin'do"] = "Jin'do the Hexxer", ["Razuvious"] = "Instructor Razuvious", ["Noth"] = "Noth the Plaguebringer",
    ["Heigan"] = "Heigan the Unclean", ["Gothik"] = "Gothik the Harvester", ["Golemagg"] = "Golemagg the Incinerator",
    ["Razorgore"] = "Razorgore the Untamed",
}
-- ZG's 787 is filed as "Broodlord" by the pack: it is Bloodlord Mandokir
local FULL_BY_ID = { [787] = "Bloodlord Mandokir" }
X.FULL_NAME, X.FULL_BY_ID = FULL_NAME, FULL_BY_ID
function X.BuildBossCard(L, raidKey, Check)
    local cfg = DB()
    local raid = RM.raids and RM.raids[raidKey]
    if not (cfg and raid and raid.encounters and next(raid.encounters)) then return end
    local ids, byName, order = {}, {}, {}
    for id in pairs(raid.encounters) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local name = FULL_BY_ID[id] or FULL_NAME[raid.encounters[id]] or raid.encounters[id]
        if not byName[name] then byName[name] = {} order[#order + 1] = name end
        table.insert(byName[name], id)
    end
    L:Card("Boss on you")
    L:Desc(cfg.bossTarget and "The big icon and air horn when one of these turns on you. Untick a boss to leave it out."
        or "Switched off: tick \"Any raid boss: when it turns on me\" on the General tab's Extras card to use these.")
    for _, name in ipairs(order) do
        local list = byName[name]
        local on = true
        for _, id in ipairs(list) do if cfg.bossOff[id] then on = false end end
        Check(L, name, on, function(v)
            for _, id in ipairs(list) do cfg.bossOff[id] = (not v) and true or nil end
            if ns.ConfigPreview and ns.ConfigPreview.UseMode then ns.ConfigPreview.UseMode("raidmods.bars", "boss") end
        end)
    end
    L:EndCard()
end
