--------------------------------------------------------------------------------
-- OldRaidFrames
-- Faithful recreation of the pre-1.15.9 Classic Era compact raid frames
-- (the Wrath-derived CompactUnitFrame look), with an options panel modeled
-- on the old Raid Profiles config, pullout-style Main Tank target/ToT rows,
-- pet frames, combined (flow) mode, and burial of Blizzard's replacement
-- raid frames.
--
-- /orf          - options panel (checkboxes, sliders, everything clickable)
-- /orf unlock   - move mode (drag the green overlay)
-- /orf help     - full command list
--
-- Hardened for the 1.15.9 (Midnight-UI) client:
--   * per-group SecureGroupHeaderTemplate, groupFilter per subgroup/role
--   * cardinal-only header point attribute
--   * negative startingIndex trick: full child pre-instantiation at spawn
--   * unfiltered RegisterEvent (no RegisterUnitEvent token drops)
--   * C_UnitAuras.GetAuraDataByIndex preferred, UnitAura fallback
--   * combat-deferred layout ops via PLAYER_REGEN_ENABLED queue
--   * oUF-style hidden-parent burial of Blizzard frames with SetParent
--     defense against Edit Mode re-parenting
--
-- Every game version (Classic Era, TBC Anniversary, WoW Forever, Retail):
--   * party frames: the same frames for a 5-player group (a secure header
--     of its own, showParty), under a "Party" title where Group 1 sits
--   * the modern clients (Forever, Retail) hide health, power and aura
--     values from addons in combat ("secret" values: no maths, no compare).
--     Every read below that can be hidden is handed to the game as it is
--     (status bars, formatted text, cooldown objects) instead of computed.
--------------------------------------------------------------------------------

-- (ZacUI) this file is built from the OldRaidFrames addon's main file by
-- tools/orf/embed.py: change the addon, then build again. Here it is a
-- part of ZacUI's unit frames with a namespace of its own, and nothing in
-- it runs until ns.Start (the foot of this file) is called.
local HOST_ADDON, UF = ...
local ADDON_NAME, ns = "OldRaidFrames", {}
UF.OldRaid = ns
local VERSION = "1.0.0"
local db   -- active profile table; re-pointed by ns.SetDB on a profile switch

-- the modern clients (WoW Forever, Retail) have issecretvalue; Era and TBC
-- do not, and nothing is ever hidden there
local MODERN = type(issecretvalue) == "function"
local function Secret(v) return MODERN and issecretvalue(v) or false end

local NUM_GROUPS        = 8
local MEMBERS_PER_GROUP = 5
local MAX_RAID          = 40
local MAX_PETS          = 10
local TITLE_HEIGHT      = 14
local RANGE_ALPHA       = 0.55   -- classic CUF out-of-range alpha
local MAX_BUFFS         = 3
local MAX_DEBUFFS       = 3
local AURA_SCAN_CAP     = 40
local TANK_TARGET_H     = 13     -- target row height (pullout grew 25->40)
local TANK_TOT_H        = 12     -- target-of-target row height
local TANK_TICK         = 0.25   -- pullout target refresh cadence (source: .25)
local HEAL_WINDOW       = 8      -- seconds ahead to count incoming heals; HoT /
                                 -- channel ticks landing later are excluded so a
                                 -- full Rejuv doesn't lump into the bar at once

local TEX_HP_FILL   = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill"
local TEX_HP_BG     = "Interface\\RaidFrame\\Raid-Bar-Hp-Bg"
local TEX_RES_FILL  = "Interface\\RaidFrame\\Raid-Bar-Resource-Fill"
local TEX_STATUSBAR = "Interface\\TargetingFrame\\UI-StatusBar"  -- pullout bar tex
local TEX_LEADER    = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
local TEX_ASSIST    = "Interface\\GroupFrame\\UI-Group-AssistantIcon"
local TEX_REZ       = "Interface\\RaidFrame\\Raid-Icon-Rez"
local TEX_RC_READY  = "Interface\\RaidFrame\\ReadyCheck-Ready"
local TEX_RC_NO     = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local TEX_RC_WAIT   = "Interface\\RaidFrame\\ReadyCheck-Waiting"
local TEX_DEBUFF_BORDER = "Interface\\Buttons\\UI-Debuff-Overlays"
local TEX_SELECTION = "Interface\\RaidFrame\\Raid-FrameHighlights"
-- the white "Raid-TargetFrame" region of Raid-FrameHighlights (CUF
-- selectionHighlight texcoords)
local SEL_COORDS = { 0.0078125, 0.5546875, 0.0078125, 0.2734375 }

-- old raid-profile option set, opinionated defaults matching the screenshot
local DEFAULTS = {
    point        = "CENTER",
    x            = 0,
    y            = 0,
    locked       = true,
    hideBlizzard = true,        -- bury Blizzard's raid container + manager
    grouped      = true,        -- "Keep Groups Together" (false = combined flow)
    sortMode     = "group",     -- combined mode "Sort By": group | name
    perColumn    = 5,           -- combined mode units per column
    classColor   = true,        -- "Use Class Colors"
    showRealm    = true,        -- Name-Realm on cross-realm players (old look);
                                -- false = bare names for everyone
    healthText   = "percent",   -- "Health Text": none | percent | value | lost
    powerBars    = true,        -- "Display Power Bars"
    border       = true,        -- "Display Border"
    displayTanks = true,        -- "Display Main Tank and Assist"
    tankTarget   = true,        -- pullout "Show Target" (MT + MA)
    tankToT      = true,        -- pullout "Show Target of Target" (MT only)
    displayPets  = false,       -- "Display Pets"
    showParty    = true,        -- the frames for a 5-player party too
    partyPlayer  = true,        -- yourself among the party frames
    buffFilter   = "mine",      -- CUF-faithful: mine | all (world buffs/boons)
    dispelOnly   = false,       -- "Display Only Dispellable Debuffs"
    aggro        = false,       -- "Display Aggro Highlight" (existed as an
                                -- old option, but not the everyday look)
    tankIcons    = true,        -- assistant badge + MT/MA shields (stock-ish)
    leaderIcons  = false,       -- leader crown (not on stock frames)
    rows         = 2,           -- groups per column (2 = the classic 4x2 grid)
    width        = 72,          -- native CUF frame width
    height       = 36,          -- native CUF frame height
    frameGap     = 2,           -- vertical gap between frames in a group
    groupGap     = 4,           -- gap between group columns/rows
    showBuffs    = true,
    showDebuffs  = true,
    buffSize     = 0,           -- 0 = auto (scales with frame size)
    debuffSize   = 0,           -- 0 = auto (scales with frame size)
    buffNameMode   = "off",     -- off | block (hide listed) | only (show listed)
    debuffNameMode = "off",
    buffNames    = {},          -- [lowercased spell name] = true
    debuffNames  = {},
    auraTooltips = true,        -- hover tooltips on buff/debuff icons
    auraSwipe    = true,        -- duration spiral on aura icons
    cdText       = "small",     -- countdown text: off | small (built-in,
                                -- scales with icon) | omnicc (leave it to
                                -- OmniCC-style addons at their own size)
    rangeFade    = true,        -- "Fade out-of-range"
    healPredict  = true,        -- LibHealPredict-1.0 incoming heal overlay
    healPredictHots = true,     -- count HoT ticks toward the overlay
    healPredictAoE  = true,     -- count group heals (PoH, Tranquility, ...)
    _cfgVersion  = 9,
}

-- shared with Profiles.lua (AceDB profile manager)
ns.VERSION  = VERSION
ns.DEFAULTS = DEFAULTS

-- replacement for the removed DebuffTypeColor global
local DISPEL_COLORS = {
    Magic   = { 0.20, 0.60, 1.00 },
    Curse   = { 0.60, 0.00, 1.00 },
    Disease = { 0.60, 0.40, 0.00 },
    Poison  = { 0.00, 0.60, 0.00 },
    none    = { 0.80, 0.00, 0.00 },
}

local POWER_COLORS = {
    MANA        = { 0.00, 0.00, 1.00 },
    RAGE        = { 1.00, 0.00, 0.00 },
    ENERGY      = { 1.00, 1.00, 0.00 },
    FOCUS       = { 1.00, 0.50, 0.25 },
    RUNIC_POWER = { 0.00, 0.82, 1.00 },
}

local THREAT_COLORS = {
    [1] = { 1.0, 1.0, 0.47 },
    [2] = { 1.0, 0.6, 0.00 },
    [3] = { 1.0, 0.0, 0.00 },
}

local GRAY  = { 0.5, 0.5, 0.5 }
local GREEN = { 0.0, 1.0, 0.0 }

local HasThreatAPI = type(UnitThreatSituation) == "function"

--------------------------------------------------------------------------------
-- state
--------------------------------------------------------------------------------

local container
local groupHeaders = {}   -- [1..8]
local groupTitles  = {}   -- [1..8]
local headerAll           -- combined flow header
local headerMT, headerMA, headerPets
local headerParty         -- the 5-player party (showParty, never in a raid)
local titleMT, titleMA, titlePets, titleParty
local allButtons   = {}   -- every styled secure unit button
local tankButtons  = {}   -- mt/ma buttons only (target/ToT ticker)
local unitMap      = {}   -- unit token -> { button, ... }
local guidMap      = {}   -- guid -> { button, ... } (heal-prediction routing)
local unitMapDirty = true
local HealPredict         -- LibHealPredict-1.0 (embedded), resolved at PLAYER_LOGIN
local mockFrames   = {}
local dragOverlay
local optionsPanel

local pendingOps   = {}
local layoutQueued = false

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffFFD100OldRaidFrames:|r " .. tostring(msg))
end
ns.Print = Print

-- Profiles.lua swaps the whole settings table under us when the player picks
-- another profile; every read goes through this upvalue, so re-pointing it is
-- all the addon needs (followed by ns.ApplyAll, defined below).
function ns.SetDB(profile)
    if type(profile) == "table" then db = profile end
end

-- version-gated fixups, applied to whichever profile becomes active (including
-- ones imported from another player or an older install)
function ns.MigrateProfile(t)
    if type(t) ~= "table" then return end
    if (t._cfgVersion or 0) < 7 then
        t.aggro = false
    end
    t._cfgVersion = DEFAULTS._cfgVersion
end

local function RunOrQueue(fn)
    if InCombatLockdown() then
        pendingOps[#pendingOps + 1] = fn
    else
        fn()
    end
end

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

local function DeepFill(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            DeepFill(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function PowerColor(unit)
    if not UnitIsConnected(unit) then
        return GRAY[1], GRAY[2], GRAY[3]
    end
    local _, token = UnitPowerType(unit)
    local c = token and POWER_COLORS[token]
    if not c and PowerBarColor and token and PowerBarColor[token] then
        local p = PowerBarColor[token]
        return p.r, p.g, p.b
    end
    if c then return c[1], c[2], c[3] end
    return 0, 0, 1
end

-- dual-path aura shim (C_UnitAuras preferred, UnitAura fallback)
-- returns icon, count, dispelName, sourceUnit, duration, name,
--         expirationTime, canApplyAura, spellId, auraTable, hidden
-- On the modern clients an aura's fields can be hidden in combat: then the
-- first return is plain `true`, the rest nil, and the aura's own table and
-- hidden = true follow (ShowHiddenAura draws it straight from the table).
local function GetAuraByIndex(unit, index, filter)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local a
        if MODERN then
            local ok, r = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
            if not ok then return nil end
            a = r
        else
            a = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
        end
        if a then
            if MODERN and (Secret(a.name) or Secret(a.icon) or Secret(a.spellId)
                or Secret(a.dispelName) or Secret(a.duration)
                or Secret(a.expirationTime) or Secret(a.applications)
                or Secret(a.sourceUnit) or Secret(a.canApplyAura)) then
                return true, nil, nil, nil, nil, nil, nil, nil, nil, a, true
            end
            return a.icon, a.applications or 0, a.dispelName, a.sourceUnit,
                a.duration, a.name, a.expirationTime, a.canApplyAura, a.spellId, a, false
        end
        return nil
    end
    if UnitAura then
        local name, icon, count, dispelType, duration, expires, source,
            _, _, spellId, canApply = UnitAura(unit, index, filter)
        if name then
            return icon, count or 0, dispelType, source, duration, name,
                expires, canApply, spellId
        end
    end
    return nil
end

local function DisplayedName(unit)
    local name
    if db.showRealm and GetUnitName then
        name = GetUnitName(unit, true)   -- Name-Server, like the old frames
    end
    if not name then
        -- UnitName's first return is the bare name (no realm suffix)
        name = UnitName(unit)
    end
    return name or ""
end

-- auto size: 11px at the native 72x36, scaling with the frame
local function AutoAuraSize()
    local scale = math.min(db.height / 36, db.width / 72)
    return math.max(8, math.floor(11 * scale + 0.5))
end

local function BuffSize()
    if db.buffSize and db.buffSize > 0 then return db.buffSize end
    return AutoAuraSize()
end

local function DebuffSize()
    if db.debuffSize and db.debuffSize > 0 then return db.debuffSize end
    return AutoAuraSize()
end

local function PowerHeight()
    return math.max(4, math.floor(db.height / 6 + 0.5))
end

local function IsTankKind(btn)
    return btn.orfKind == "mt" or btn.orfKind == "ma"
end

local function TankExtraFor(kind)
    local extra = 0
    if db.tankTarget then
        extra = extra + TANK_TARGET_H
        if kind == "mt" and db.tankToT then
            extra = extra + TANK_TOT_H
        end
    end
    return extra
end

local function ButtonHeightFor(btn)
    if IsTankKind(btn) then
        return db.height + TankExtraFor(btn.orfKind)
    end
    return db.height
end

local function CountRole(role)
    if not IsInRaid() then return 0 end
    local c = 0
    for i = 1, GetNumGroupMembers() do
        local _, _, _, _, _, _, _, _, _, r = GetRaidRosterInfo(i)
        if r == role then c = c + 1 end
    end
    return c
end

-- ZacUI's unit frames draw the party (the part is loaded and its party
-- frames are switched on): two sets of party frames is one too many, so
-- ours stand down - no party header, no party pets, Blizzard's party
-- frames left to ZacUI. Read once (ZacUI's own switch needs a reload too).
local zacuiParty
local function ZacUIParty()
    if zacuiParty ~= nil then return zacuiParty end
    zacuiParty = false
    local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if type(f) == "function" then
        local ok, loaded = pcall(f, "Zacui_UnitFrames")
        if ok and loaded then
            local sv = type(ZacUIDB) == "table" and ZacUIDB.unitframes
            local party = type(sv) == "table" and sv.party
            zacuiParty = not (type(party) == "table" and party.enabled == false)
        end
    end
    return zacuiParty
end

-- the party frames are switched on and nothing else draws the party
local function PartyOn()
    return (db and db.showParty and not ZacUIParty()) and true or false
end

-- in a party (never a raid) with the party frames on
local function PartyActive()
    return PartyOn() and IsInGroup() and not IsInRaid() and true or false
end

local function CountPets()
    if not IsInRaid() then
        if not PartyActive() then return 0 end
        local c = 0
        if db.partyPlayer and UnitExists("pet") then c = c + 1 end
        for i = 1, 4 do
            if UnitExists("partypet" .. i) then c = c + 1 end
        end
        return c
    end
    local c = 0
    for i = 1, GetNumGroupMembers() do
        if UnitExists("raidpet" .. i) then c = c + 1 end
    end
    return c
end

local function GroupCounts()
    local counts = { 0, 0, 0, 0, 0, 0, 0, 0 }
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local _, _, sub = GetRaidRosterInfo(i)
            if sub and counts[sub] then counts[sub] = counts[sub] + 1 end
        end
    end
    return counts
end

--------------------------------------------------------------------------------
-- Blizzard frame burial (oUF-style hidden parent + SetParent defense)
--------------------------------------------------------------------------------

local hider = CreateFrame("Frame", nil, UIParent)
hider:Hide()

local burying = false

local function BuryFrame(frame)
    if not frame or frame.orfBuried then return end
    frame.orfBuried = true
    -- 1.15.9 Midnight UI: the raid container is a registered Edit Mode system.
    -- Leaving it registered while it lives under a hidden parent makes Edit
    -- Mode re-show it and throw errors when it lays its systems out, so drop it
    -- from the manager's registry first (the oUF approach).
    if frame.system and EditModeManagerFrame
        and EditModeManagerFrame.UnregisterSystemFrame then
        pcall(EditModeManagerFrame.UnregisterSystemFrame, EditModeManagerFrame, frame)
    end
    RunOrQueue(function()
        burying = true
        frame:UnregisterAllEvents()
        frame:SetParent(hider)
        burying = false
    end)
    -- Edit Mode / managed-frame code may re-parent it later; put it back.
    -- Guard: if some other addon's hidden parent grabbed it (e.g. ZacUF's
    -- own hider), leave it alone -- it is hidden either way.
    hooksecurefunc(frame, "SetParent", function(self, parent)
        if burying or not db or not db.hideBlizzard then return end
        if parent ~= hider and (not parent or parent:IsShown()) then
            RunOrQueue(function()
                burying = true
                self:SetParent(hider)
                burying = false
            end)
        end
    end)
end

-- members laid out by a container we already buried: only their events go
local function SilenceFrame(frame)
    if not frame or frame.orfSilenced then return end
    frame.orfSilenced = true
    if frame.UnregisterAllEvents then frame:UnregisterAllEvents() end
    RunOrQueue(function() frame:Hide() end)
end

local compactPartyHooked = false

local function BuryCompactParty()
    if not _G.CompactPartyFrame then return end
    BuryFrame(_G.CompactPartyFrame)
    for i = 1, 5 do
        SilenceFrame(_G["CompactPartyFrameMember" .. i])
    end
end

-- Blizzard's party frames, every shape the clients have: the numbered
-- member frames (the old UI), the PartyFrame container with its member
-- pool (the 1.15.9 / 2.5.6 / modern UI) and the raid-style party frame
-- (made on demand by CompactPartyFrame_Generate on the newer clients).
local function HideBlizzardPartyFrames()
    for i = 1, 4 do
        BuryFrame(_G["PartyMemberFrame" .. i])
    end
    local pf = _G.PartyFrame
    if pf then
        BuryFrame(pf)
        local pool = pf.PartyMemberFramePool
        if pool and pool.EnumerateActive then
            for member in pool:EnumerateActive() do
                SilenceFrame(member)
            end
        end
    end
    if _G.CompactPartyFrame then
        BuryCompactParty()
    elseif _G.CompactPartyFrame_Generate and not compactPartyHooked then
        compactPartyHooked = true
        hooksecurefunc("CompactPartyFrame_Generate", function()
            if db and db.hideBlizzard and PartyOn() then BuryCompactParty() end
        end)
    end
end

local function HideBlizzardRaidFrames()
    -- re-entrant: frames may not exist yet at login, retried on
    -- PLAYER_ENTERING_WORLD; already-buried frames are skipped
    BuryFrame(_G.CompactRaidFrameManager)
    BuryFrame(_G.CompactRaidFrameContainer)
    -- the party's own frames go only while ours stand in for them
    if PartyOn() then HideBlizzardPartyFrames() end
end

--------------------------------------------------------------------------------
-- unit map
--------------------------------------------------------------------------------

local function RebuildUnitMap()
    for k in pairs(unitMap) do unitMap[k] = nil end
    for k in pairs(guidMap) do guidMap[k] = nil end
    for i = 1, #allButtons do
        local btn = allButtons[i]
        local unit = btn.unit
        btn.guid = unit and UnitGUID(unit) or nil
        if unit then
            local list = unitMap[unit]
            if not list then
                list = {}
                unitMap[unit] = list
            end
            list[#list + 1] = btn
            local guid = btn.guid
            if guid then
                local glist = guidMap[guid]
                if not glist then
                    glist = {}
                    guidMap[guid] = glist
                end
                glist[#glist + 1] = btn
            end
        end
    end
    unitMapDirty = false
end

local function ButtonsForUnit(unit)
    if unitMapDirty then RebuildUnitMap() end
    return unitMap[unit]
end

local function ButtonsForGUID(guid)
    if unitMapDirty then RebuildUnitMap() end
    return guidMap[guid]
end

local function RaidIndexOf(unit)
    local n = unit and unit:match("^raid(%d+)$")
    return n and tonumber(n)
end

--------------------------------------------------------------------------------
-- per-element updates
--------------------------------------------------------------------------------

local UpdateAll   -- forward

local function UpdateHealthColor(btn)
    local unit = btn.unit
    if not UnitIsConnected(unit) then
        -- old CUF: offline = the health bar itself goes 0.5 gray
        btn.health:SetStatusBarColor(GRAY[1], GRAY[2], GRAY[3])
    elseif db.classColor and UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        local c = class and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
        if c then
            btn.health:SetStatusBarColor(c.r, c.g, c.b)
        else
            btn.health:SetStatusBarColor(GREEN[1], GREEN[2], GREEN[3])
        end
    else
        -- pets and class-colors-off: green, like the old frames
        btn.health:SetStatusBarColor(GREEN[1], GREEN[2], GREEN[3])
    end
end

-- THE MODERN CLIENTS' OVERLAY. Health and incoming heals are hidden from
-- addons in combat there, so the green segment is a status bar the game
-- fills itself: as wide as the health bar, starting where the health fill
-- ends, its range the unit's max health and its value the incoming heals.
-- The health bar clips it at its right edge.
local function UpdateNativeHealPrediction(btn)
    local bar = btn.healPredBar
    if not bar then return end
    if not db.healPredict or not btn.unit or type(UnitGetIncomingHeals) ~= "function"
        or not UnitIsConnected(btn.unit) or UnitIsDeadOrGhost(btn.unit) then
        bar:Hide()
        return
    end
    local ok, inc = pcall(UnitGetIncomingHeals, btn.unit)
    if not ok or inc == nil then
        bar:Hide()
        return
    end
    local max = UnitHealthMax(btn.unit)
    if not (pcall(bar.SetMinMaxValues, bar, 0, max) and pcall(bar.SetValue, bar, inc)) then
        bar:Hide()
        return
    end
    bar:Show()
end

-- LibHealPredict-1.0 incoming heal overlay (green segment after current health)
local function UpdateHealPrediction(btn)
    if MODERN then
        if btn.healPred then btn.healPred:Hide() end
        UpdateNativeHealPrediction(btn)
        return
    end
    local hp = btn.healPred
    if not hp then return end
    if not db.healPredict or not HealPredict or not btn.unit or not btn.guid
        or not UnitIsConnected(btn.unit) or UnitIsDeadOrGhost(btn.unit) then
        hp:Hide()
        return
    end
    local cur, max = UnitHealth(btn.unit), UnitHealthMax(btn.unit)
    -- (hidden health: the overlay is placed by maths on it, so none)
    if Secret(cur) or Secret(max) then
        hp:Hide()
        return
    end
    if max <= 0 or cur >= max then
        hp:Hide()
        return
    end
    -- every pending segment (direct, channel, group heal, HoT tick) landing
    -- within the next HEAL_WINDOW seconds; multi-target casts (Prayer of
    -- Healing, Chain Heal, Tranquility) arrive per-target from the lib
    -- already, and HoT/AoE inclusion is governed by the SetTrack* settings
    -- pushed in ApplyHealPredictSettings
    local segments = HealPredict:GetSegments(btn.guid, btn.unit)
    local amount = 0
    if segments then
        local cutoff = GetTime() + HEAL_WINDOW
        for i = 1, #segments do
            local seg = segments[i]
            -- hot_tick segments are already a single tick's worth (the lib
            -- emits one per active HoT, not the remaining total), so they
            -- are never the thing HEAL_WINDOW is guarding against
            if seg.kind == "hot_tick" or (seg.endTime or 0) <= cutoff then
                amount = amount + (seg.amount or 0)
            end
        end
    end
    if amount <= 0 then
        hp:Hide()
        return
    end
    local width = btn.health:GetWidth()
    if not width or width <= 0 then
        hp:Hide()
        return
    end
    local show = math.min(amount, max - cur)
    local x = width * (cur / max)
    hp:ClearAllPoints()
    hp:SetPoint("TOPLEFT", btn.health, "TOPLEFT", x, 0)
    hp:SetPoint("BOTTOMLEFT", btn.health, "BOTTOMLEFT", x, 0)
    hp:SetWidth(math.max(1, width * (show / max)))
    hp:Show()
end

-- the library only learns about HoTs from aura passes the consumer drives, and
-- it never populates that state on its own: sweep the roster whenever HoT
-- tracking is (re)enabled or the group changes, or HoTs already ticking stay
-- invisible until each unit's next aura event
local function SweepHealPredictAuras()
    if not HealPredict or not db or not db.healPredict or not db.healPredictHots then
        return
    end
    for i = 1, #allButtons do
        local btn = allButtons[i]
        if btn:IsShown() and btn.unit and UnitExists(btn.unit) then
            HealPredict:ScanAuras(btn.unit)
        end
    end
end

-- the library owns no saved variables: push our profile's toggles into it
-- whenever they change (option click, slash toggle, profile switch)
local function ApplyHealPredictSettings()
    if not HealPredict or not db then return end
    HealPredict:SetTrackHots(db.healPredict and db.healPredictHots)
    HealPredict:SetTrackAoE(db.healPredict and db.healPredictAoE)
    SweepHealPredictAuras()
end
ns.ApplyHealPredictSettings = ApplyHealPredictSettings

-- a number the game may be hiding, as text: AbbreviateNumbers takes it as
-- it is; SetFormattedText does the same for the font string
local function HiddenNumber(v)
    if type(AbbreviateNumbers) == "function" then
        local ok, s = pcall(AbbreviateNumbers, v)
        if ok and s ~= nil then return "%s", s end
    end
    return "%d", v
end

-- 0-100 from the game for a unit whose health is hidden (UnitHealthPercent
-- with the game's own 0..1 -> 0..100 curve); nil where the client has none
local scale100
local function HiddenHealthPercent(unit)
    if type(UnitHealthPercent) ~= "function" then return nil end
    if scale100 == nil then
        scale100 = false
        local cc = rawget(_G, "CurveConstants")
        if type(cc) == "table" and cc.ScaleTo100 then
            scale100 = cc.ScaleTo100
        elseif C_CurveUtil and C_CurveUtil.CreateCurve then
            local ok, c = pcall(C_CurveUtil.CreateCurve)
            if ok and c and pcall(function()
                local lct = Enum and Enum.LuaCurveType
                if lct and lct.Linear ~= nil then c:SetType(lct.Linear) end
                c:AddPoint(0, 0)
                c:AddPoint(1, 100)
            end) then
                scale100 = c
            end
        end
    end
    if not scale100 then return nil end
    local ok, v = pcall(UnitHealthPercent, unit, true, scale100)
    if ok then return v end
    return nil
end

-- the health bar and its text while the game hides the numbers (in combat
-- on the modern clients): the bar takes the hidden values as they are, the
-- text is formatted by the game. "Health Lost" has no hidden form the
-- frame can hide at full, so it shows nothing until health reads again.
local function UpdateHiddenHealth(btn, unit, cur, max)
    if not (pcall(btn.health.SetMinMaxValues, btn.health, 0, max)
        and pcall(btn.health.SetValue, btn.health, cur)) then
        return
    end
    local st = btn.statusText
    if UnitIsDeadOrGhost(unit) then
        st:SetText(DEAD or "Dead")
        st:SetTextColor(GRAY[1], GRAY[2], GRAY[3])
        st:Show()
    elseif db.healthText == "percent" then
        local pct = HiddenHealthPercent(unit)
        st:SetTextColor(0.9, 0.9, 0.9)
        if pct ~= nil and pcall(st.SetFormattedText, st, "%.0f%%", pct) then
            st:Show()
        else
            st:Hide()
        end
    elseif db.healthText == "value" then
        local fmt, v = HiddenNumber(cur)
        st:SetTextColor(0.9, 0.9, 0.9)
        if pcall(st.SetFormattedText, st, fmt, v) then st:Show() else st:Hide() end
    else
        st:Hide()
    end
end

local function UpdateHealth(btn)
    local unit = btn.unit
    if not UnitIsConnected(unit) then
        -- gray, full bar + "Offline"
        btn.health:SetMinMaxValues(0, 1)
        btn.health:SetValue(1)
        btn.statusText:SetText(PLAYER_OFFLINE or "Offline")
        btn.statusText:SetTextColor(GRAY[1], GRAY[2], GRAY[3])
        btn.statusText:Show()
        UpdateHealPrediction(btn)
        return
    end

    local cur, max = UnitHealth(unit), UnitHealthMax(unit)
    if Secret(cur) or Secret(max) then
        UpdateHiddenHealth(btn, unit, cur, max)
        UpdateHealPrediction(btn)
        return
    end
    if max <= 0 then max = 1 end
    btn.health:SetMinMaxValues(0, max)
    btn.health:SetValue(cur)

    -- status text (the old "Health Text" raid-profile option)
    if UnitIsDeadOrGhost(unit) then
        btn.statusText:SetText(DEAD or "Dead")
        btn.statusText:SetTextColor(GRAY[1], GRAY[2], GRAY[3])
        btn.statusText:Show()
    elseif db.healthText == "percent" then
        btn.statusText:SetText(math.floor(cur / max * 100 + 0.5) .. "%")
        btn.statusText:SetTextColor(0.9, 0.9, 0.9)
        btn.statusText:Show()
    elseif db.healthText == "value" then
        btn.statusText:SetText(cur)
        btn.statusText:SetTextColor(0.9, 0.9, 0.9)
        btn.statusText:Show()
    elseif db.healthText == "lost" then
        -- old CUF "Lost Health": gray "-N", hidden while at full
        local lost = max - cur
        if lost > 0 then
            btn.statusText:SetText("-" .. lost)
            btn.statusText:SetTextColor(GRAY[1], GRAY[2], GRAY[3])
            btn.statusText:Show()
        else
            btn.statusText:Hide()
        end
    else
        btn.statusText:Hide()
    end
    UpdateHealPrediction(btn)
end

local function UpdatePower(btn)
    if not db.powerBars then return end
    local unit = btn.unit
    if not UnitIsConnected(unit) then
        btn.power:SetMinMaxValues(0, 1)
        btn.power:SetValue(1)
        btn.power:SetStatusBarColor(GRAY[1], GRAY[2], GRAY[3])
        return
    end
    local cur, max = UnitPower(unit), UnitPowerMax(unit)
    if Secret(cur) or Secret(max) then
        -- hidden: handed to the bar as it is
        if pcall(btn.power.SetMinMaxValues, btn.power, 0, max) then
            pcall(btn.power.SetValue, btn.power, cur)
        end
        btn.power:SetStatusBarColor(PowerColor(unit))
        return
    end
    if max <= 0 then max = 1 end
    btn.power:SetMinMaxValues(0, max)
    btn.power:SetValue(cur)
    btn.power:SetStatusBarColor(PowerColor(unit))
end

local function UpdateName(btn)
    local unit = btn.unit
    btn.nameText:SetText(DisplayedName(unit))
    if not UnitIsConnected(unit) then
        btn.nameText:SetTextColor(GRAY[1], GRAY[2], GRAY[3])
    else
        btn.nameText:SetTextColor(1, 1, 1)
    end
end

-- icon(s) hug the left side of the name and the pair reads centered, like
-- the reference footage; for long truncated names the name yields space so
-- the icons always stay fully inside the frame
local function UpdateLeaderIcon(btn)
    local unit = btn.unit

    local leaderShown = false
    if db.leaderIcons and UnitIsPlayer(unit) and UnitIsGroupLeader(unit) then
        btn.leaderIcon:SetTexture(TEX_LEADER)
        leaderShown = true
    end
    btn.leaderIcon:SetShown(leaderShown)

    -- shields: MT/MA shield for marked tanks, or the assistant badge
    local roleShown = false
    if db.tankIcons then
        local idx = RaidIndexOf(unit)
        local role = idx and select(10, GetRaidRosterInfo(idx))
        if role == "MAINTANK" then
            btn.roleIcon:SetTexture("Interface\\GroupFrame\\UI-Group-MainTankIcon")
            roleShown = true
        elseif role == "MAINASSIST" then
            btn.roleIcon:SetTexture("Interface\\GroupFrame\\UI-Group-MainAssistIcon")
            roleShown = true
        elseif UnitIsPlayer(unit) and UnitIsGroupAssistant
            and UnitIsGroupAssistant(unit) then
            btn.roleIcon:SetTexture(TEX_ASSIST)
            roleShown = true
        end
    end
    btn.roleIcon:SetShown(roleShown)

    local clusterW = (leaderShown and 12 or 0) + (roleShown and 12 or 0)

    -- name: true center across the full frame width
    btn.nameText:ClearAllPoints()
    btn.nameText:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
    btn.nameText:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -3, -3)
    if clusterW == 0 then return end

    -- IMPORTANT: GetStringWidth ignores "..." truncation and reports the
    -- full untruncated width, so clamp to the actual rendered span
    local span = db.width - 6
    -- (a hidden name has a hidden width: the full span stands in for it)
    local function NameWidth()
        local w = btn.nameText:GetStringWidth() or 0
        if Secret(w) then return span end
        return w
    end
    local half = math.min(NameWidth(), span) / 2
    if (-half - 2) < (clusterW + 2 - db.width / 2) then
        -- name is long enough that icons would poke out: reserve icon
        -- space on the left, name centers in the remaining width
        btn.nameText:ClearAllPoints()
        btn.nameText:SetPoint("TOPLEFT", btn, "TOPLEFT", 3 + clusterW, -3)
        btn.nameText:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -3, -3)
        span = db.width - 6 - clusterW
        half = math.min(NameWidth(), span) / 2
    end

    -- rightmost icon sits immediately left of the visible name text
    local anchor
    if roleShown then
        btn.roleIcon:ClearAllPoints()
        btn.roleIcon:SetPoint("RIGHT", btn.nameText, "CENTER", -half - 2, 0)
        anchor = btn.roleIcon
    end
    if leaderShown then
        btn.leaderIcon:ClearAllPoints()
        if anchor then
            btn.leaderIcon:SetPoint("RIGHT", anchor, "LEFT", -1, 0)
        else
            btn.leaderIcon:SetPoint("RIGHT", btn.nameText, "CENTER", -half - 2, 0)
        end
    end
end

local function UpdateCenterIcon(btn)
    local unit = btn.unit
    local status = GetReadyCheckStatus and GetReadyCheckStatus(unit)
    if status == "ready" then
        btn.centerIcon:SetTexture(TEX_RC_READY)
        btn.centerIcon:Show()
    elseif status == "notready" then
        btn.centerIcon:SetTexture(TEX_RC_NO)
        btn.centerIcon:Show()
    elseif status == "waiting" then
        btn.centerIcon:SetTexture(TEX_RC_WAIT)
        btn.centerIcon:Show()
    elseif UnitHasIncomingResurrection and UnitHasIncomingResurrection(unit) then
        btn.centerIcon:SetTexture(TEX_REZ)
        btn.centerIcon:Show()
    else
        btn.centerIcon:Hide()
    end
end

local function UpdateAggro(btn)
    if not db.aggro or not HasThreatAPI then
        btn.aggro:Hide()
        return
    end
    local status = UnitThreatSituation(btn.unit)
    if Secret(status) then status = nil end
    local c = status and THREAT_COLORS[status]
    if c then
        for i = 1, 4 do
            btn.aggroTex[i]:SetVertexColor(c[1], c[2], c[3])
        end
        btn.aggro:Show()
    else
        btn.aggro:Hide()
    end
end

-- CUF-faithful buff display: the old frames only showed RAID-RELEVANT buffs
-- you cast yourself -- things you can put on other people (Fortitude,
-- Renew, blessings, Rejuvenation), never self-only effects (consumables,
-- food, elixirs, procs). Their in-combat visibility rules additionally
-- suppressed long-duration stuff (world buffs, boons) while fighting.
local function BuffPassesFilter(source, duration, canApply, spellId)
    if db.buffFilter == "all" then return true end
    local mine = source == "player" or source == "pet" or source == "vehicle"
    -- Blizzard's custom visibility table first (Power Infusion style
    -- always-show entries), when the client has it populated
    if spellId and type(SpellGetVisibilityInfo) == "function" then
        local ok, hasCustom, alwaysShowMine, showForMySpec = pcall(
            SpellGetVisibilityInfo, spellId,
            UnitAffectingCombat("player") and "RAID_INCOMBAT" or "RAID_OUTOFCOMBAT")
        if ok and hasCustom then
            return (showForMySpec or (alwaysShowMine and mine)) and true or false
        end
    end
    if not mine then return false end
    -- only buffs you can actually apply to others; self-only stuff
    -- (Mongoose, food, flasks, procs) stays off the frames
    if canApply == false then return false end
    if spellId and type(SpellIsSelfBuff) == "function" and SpellIsSelfBuff(spellId) then
        return false
    end
    if InCombatLockdown() then
        -- in combat: only short "castable" buffs (<= 5 min), like the old
        -- RAID_INCOMBAT visibility rules; world buffs/boons drop out
        return duration and duration > 0 and duration <= 300
    end
    return true
end

-- per-name filter lists: "block" hides listed auras, "only" shows nothing
-- BUT listed auras, "off" (or any other value) shows everything
local function PassesNameFilter(mode, list, name)
    if mode == "block" then
        return not (name and list and list[name:lower()])
    elseif mode == "only" then
        return name ~= nil and list ~= nil and list[name:lower()] == true
    end
    return true
end

-- built-in countdown text (cdText = "small"): scaled to the icon, ticked
-- by a 0.5s timer; white, red in the last 5 seconds, "Nm" above a minute
local function UpdateAuraTimer(f, now)
    local fs = f.timerText
    if not fs then return end
    if db.cdText ~= "small" or not f:IsShown() or not f.cdExpires then
        fs:SetText("")
        return
    end
    local remain = f.cdExpires - now
    if remain <= 0 then
        fs:SetText("")
    elseif remain >= 60 then
        fs:SetTextColor(1, 1, 1)
        fs:SetText(math.ceil(remain / 60) .. "m")
    else
        if remain <= 5 then
            fs:SetTextColor(1, 0.15, 0.15)
        else
            fs:SetTextColor(1, 1, 1)
        end
        fs:SetText(math.floor(remain + 0.5))
    end
end

-- duration spiral + countdown bookkeeping. The spiral is a real Cooldown,
-- so OmniCC-style addons can attach to it in "omnicc" mode; in the other
-- modes our frames carry noCooldownCount (the opt-out flag those addons
-- respect), so their fixed-size text never lands on tiny icons.
local function SetAuraCooldown(f, duration, expires)
    local cd = f.cooldown
    if not cd then return end
    local timed = duration and duration > 0 and expires and expires > 0
    if db.auraSwipe and timed then
        cd:SetCooldown(expires - duration, duration)
    else
        cd:SetCooldown(0, 0)
    end
    f.cdExpires = timed and expires or nil
    UpdateAuraTimer(f, GetTime())
end

-- an aura the game is hiding (in combat on the modern clients): icon,
-- stacks and the spiral come straight from the game - no number of ours
-- touches them. No countdown text (it is arithmetic on the hidden end time).
local function ShowHiddenAura(f, unit, a)
    pcall(f.icon.SetTexture, f.icon, a.icon)
    local shown = false
    local id = a.auraInstanceID
    if id and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
        local ok, s = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, id, 2)
        if ok and s ~= nil and pcall(f.count.SetText, f.count, s) then shown = true end
    end
    f.count:SetShown(shown)
    f.cdExpires = nil
    if f.timerText then f.timerText:SetText("") end
    local cd = f.cooldown
    if cd then
        local set = false
        if db.auraSwipe then
            if id and C_UnitAuras and C_UnitAuras.GetAuraDuration and cd.SetCooldownFromDurationObject then
                local ok, dur = pcall(C_UnitAuras.GetAuraDuration, unit, id)
                if ok and dur and pcall(cd.SetCooldownFromDurationObject, cd, dur) then set = true end
            end
            if not set and cd.SetCooldownFromExpirationTime
                and pcall(cd.SetCooldownFromExpirationTime, cd, a.expirationTime, a.duration) then
                set = true
            end
        end
        if not set then cd:SetCooldown(0, 0) end
    end
end

-- "from you", for an aura whose caster is hidden: the game's own flag
local function HiddenAuraIsMine(a)
    local m = a.isFromPlayerOrPlayerPet
    return (not Secret(m)) and m == true
end

local function UpdateAuras(btn)
    local unit = btn.unit
    local connected = UnitIsConnected(unit)

    local slot = 0
    if db.showBuffs and connected then
        for index = 1, AURA_SCAN_CAP do
            local icon, count, _, source, duration, name, expires, canApply, spellId, aura, hidden =
                GetAuraByIndex(unit, index, "HELPFUL")
            if not icon then break end
            if hidden then
                -- the name and caster can't be read: "mine" asks the game's
                -- own flag, and an Only Listed filter shows nothing it
                -- can't check
                if (db.buffFilter == "all" or HiddenAuraIsMine(aura))
                    and db.buffNameMode ~= "only" then
                    slot = slot + 1
                    local f = btn.buffs[slot]
                    f.tipIndex, f.tipFilter = index, "HELPFUL"
                    ShowHiddenAura(f, unit, aura)
                    f:Show()
                    if slot == MAX_BUFFS then break end
                end
            elseif BuffPassesFilter(source, duration, canApply, spellId)
                and PassesNameFilter(db.buffNameMode, db.buffNames, name) then
                slot = slot + 1
                local f = btn.buffs[slot]
                f.icon:SetTexture(icon)
                f.tipIndex, f.tipFilter = index, "HELPFUL"
                SetAuraCooldown(f, duration, expires)
                if count and count > 1 then
                    f.count:SetText(count)
                    f.count:Show()
                else
                    f.count:Hide()
                end
                f:Show()
                if slot == MAX_BUFFS then break end
            end
        end
    end
    for i = slot + 1, MAX_BUFFS do
        btn.buffs[i].tipIndex = nil
        btn.buffs[i]:Hide()
    end

    slot = 0
    if db.showDebuffs and connected then
        -- HARMFUL|RAID = only debuffs the player can dispel
        local filter = db.dispelOnly and "HARMFUL|RAID" or "HARMFUL"
        for index = 1, AURA_SCAN_CAP do
            local icon, count, dispelType, _, duration, name, expires, _, _, aura, hidden =
                GetAuraByIndex(unit, index, filter)
            if not icon then break end
            if hidden then
                if db.debuffNameMode ~= "only" then
                    slot = slot + 1
                    local f = btn.debuffs[slot]
                    f.tipIndex, f.tipFilter = index, filter
                    ShowHiddenAura(f, unit, aura)
                    local c = DISPEL_COLORS.none
                    f.border:SetVertexColor(c[1], c[2], c[3])
                    f:Show()
                    if slot == MAX_DEBUFFS then break end
                end
            elseif PassesNameFilter(db.debuffNameMode, db.debuffNames, name) then
                slot = slot + 1
                local f = btn.debuffs[slot]
                f.icon:SetTexture(icon)
                f.tipIndex, f.tipFilter = index, filter
                SetAuraCooldown(f, duration, expires)
                local c = DISPEL_COLORS[dispelType or "none"] or DISPEL_COLORS.none
                f.border:SetVertexColor(c[1], c[2], c[3])
                if count and count > 1 then
                    f.count:SetText(count)
                    f.count:Show()
                else
                    f.count:Hide()
                end
                f:Show()
                if slot == MAX_DEBUFFS then break end
            end
        end
    end
    for i = slot + 1, MAX_DEBUFFS do
        btn.debuffs[i].tipIndex = nil
        btn.debuffs[i]:Hide()
    end
end

local function UpdateSelection(btn)
    local same = btn.unit and UnitExists("target") and UnitIsUnit(btn.unit, "target")
    if Secret(same) then same = false end
    if same then
        btn.selection:Show()
    else
        btn.selection:Hide()
    end
end

-- pullout-style target / target-of-target rows stacked inside MT/MA frames,
-- refreshed on the pullout's own 0.25s cadence.
-- Authentic empty behavior (1.15.8 Blizzard_RaidUI source): the target bar
-- stays visible as a full gray bar when there is no target; the ToT frame
-- hides entirely when empty.
local function UpdateTargetRow(row, watchUnit, hideWhenEmpty)
    if UnitExists(watchUnit) then
        local cur, max = UnitHealth(watchUnit), UnitHealthMax(watchUnit)
        if Secret(cur) or Secret(max) then
            if pcall(row.bar.SetMinMaxValues, row.bar, 0, max) then
                pcall(row.bar.SetValue, row.bar, cur)
            end
        else
            if max <= 0 then max = 1 end
            row.bar:SetMinMaxValues(0, max)
            row.bar:SetValue(cur)
        end
        -- old-client selection colors (per the reference video):
        -- hostile red, friendly green, neutral yellow
        if UnitIsEnemy("player", watchUnit) then
            row.bar:SetStatusBarColor(1, 0, 0)
        elseif UnitIsFriend("player", watchUnit) then
            row.bar:SetStatusBarColor(0, 0.8, 0)
        else
            row.bar:SetStatusBarColor(1, 1, 0)
        end
        row.name:SetText(UnitName(watchUnit) or "")
        row:Show()
    elseif hideWhenEmpty then
        row:Hide()
    else
        -- no target: full gray bar, no name (like the old pullout)
        row.bar:SetMinMaxValues(0, 1)
        row.bar:SetValue(1)
        row.bar:SetStatusBarColor(0.5, 0.5, 0.5)
        row.name:SetText("")
        row:Show()
    end
end

local function UpdateTankTarget(btn)
    if not IsTankKind(btn) or not btn.unit then return end
    if btn.targetRow and db.tankTarget then
        -- no target = no bar (per reference footage); the slot space stays
        -- reserved so frames don't jump around
        UpdateTargetRow(btn.targetRow, btn.unit .. "target", true)
    end
    if btn.totRow then
        if db.tankTarget and db.tankToT and btn.orfKind == "mt" then
            UpdateTargetRow(btn.totRow, btn.unit .. "targettarget", true)
        else
            btn.totRow:Hide()
        end
    end
end

UpdateAll = function(btn)
    local unit = btn.unit
    if not unit or not UnitExists(unit) then return end
    UpdateName(btn)
    UpdateHealthColor(btn)
    UpdateHealth(btn)
    UpdatePower(btn)
    UpdateLeaderIcon(btn)
    UpdateCenterIcon(btn)
    UpdateAggro(btn)
    UpdateAuras(btn)
    UpdateSelection(btn)
    UpdateTankTarget(btn)
end

local function UpdateAllVisible()
    for i = 1, #allButtons do
        local btn = allButtons[i]
        if btn:IsShown() and btn.unit then
            UpdateAll(btn)
        end
    end
end

--------------------------------------------------------------------------------
-- button styling
--------------------------------------------------------------------------------

local function MakeOutline(parent, r, g, b, a)
    local edges = {}
    local function edge()
        local t = parent:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(r, g, b, a)
        return t
    end
    edges[1] = edge()
    edges[1]:SetPoint("TOPLEFT", 0, 0)
    edges[1]:SetPoint("TOPRIGHT", 0, 0)
    edges[1]:SetHeight(1)
    edges[2] = edge()
    edges[2]:SetPoint("BOTTOMLEFT", 0, 0)
    edges[2]:SetPoint("BOTTOMRIGHT", 0, 0)
    edges[2]:SetHeight(1)
    edges[3] = edge()
    edges[3]:SetPoint("TOPLEFT", 0, 0)
    edges[3]:SetPoint("BOTTOMLEFT", 0, 0)
    edges[3]:SetWidth(1)
    edges[4] = edge()
    edges[4]:SetPoint("TOPRIGHT", 0, 0)
    edges[4]:SetPoint("BOTTOMRIGHT", 0, 0)
    edges[4]:SetWidth(1)
    return edges
end

-- a stacked target / ToT row: dark strip, status bar, small name on the bar
local function MakeTargetRow(btn)
    local row = CreateFrame("Frame", nil, btn.overlay)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0, 0, 0, 0.6)
    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetPoint("TOPLEFT", 1, -1)
    row.bar:SetPoint("BOTTOMRIGHT", -1, 1)
    row.bar:SetStatusBarTexture(TEX_STATUSBAR)
    row.barBg = row.bar:CreateTexture(nil, "BACKGROUND")
    row.barBg:SetAllPoints()
    row.barBg:SetColorTexture(0, 0, 0, 0.4)
    local overlay = CreateFrame("Frame", nil, row)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(row.bar:GetFrameLevel() + 5)
    row.name = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("CENTER", row, "CENTER", 0, 0)
    row.name:SetWordWrap(false)
    row:Hide()
    return row
end

local function EnsureTankExtras(btn)
    if not IsTankKind(btn) then return end
    if not btn.targetRow then
        btn.targetRow = MakeTargetRow(btn)
    end
    if btn.orfKind == "mt" and not btn.totRow then
        btn.totRow = MakeTargetRow(btn)
    end
end

local function LayoutButtonInternals(btn)
    local unitH  = db.height
    local powerH = db.powerBars and PowerHeight() or 0

    -- background + border wrap only the unit block; the target/ToT rows
    -- draw their own backing, so hidden rows leave literally nothing
    btn.bg:ClearAllPoints()
    btn.bg:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    btn.bg:SetSize(db.width, unitH)

    local bt = btn.borderTex
    bt[1]:ClearAllPoints()
    bt[1]:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    bt[1]:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    bt[2]:ClearAllPoints()
    bt[2]:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, -(unitH - 1))
    bt[2]:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, -(unitH - 1))
    bt[3]:ClearAllPoints()
    bt[3]:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    bt[3]:SetSize(1, unitH)
    bt[4]:ClearAllPoints()
    bt[4]:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    bt[4]:SetSize(1, unitH)

    btn.health:ClearAllPoints()
    btn.health:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    btn.health:SetSize(db.width - 2, unitH - 2 - powerH)
    if btn.healPredBar then btn.healPredBar:SetWidth(math.max(1, db.width - 2)) end

    btn.power:ClearAllPoints()
    btn.power:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -(unitH - 1 - powerH))
    btn.power:SetSize(db.width - 2, math.max(powerH, 1))
    if db.powerBars then btn.power:Show() else btn.power:Hide() end

    btn.statusText:ClearAllPoints()
    btn.statusText:SetPoint("TOP", btn, "TOP", 0, -(math.floor(unitH / 2) - 3))

    -- selection / aggro borders cover the unit area only
    btn.selection:ClearAllPoints()
    btn.selection:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    btn.selection:SetSize(db.width, unitH)

    btn.aggro:ClearAllPoints()
    btn.aggro:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    btn.aggro:SetSize(db.width, unitH)

    -- independently sizable; both default to auto (old-frame parity:
    -- same size as each other, scaling with the frame)
    local bs = BuffSize()
    local ds = DebuffSize()
    -- stack + countdown text scale with the icon (the stock number font
    -- dwarfs an 11px icon); noCooldownCount keeps OmniCC-style addons off
    -- our cooldowns unless the user picked the omnicc mode
    local function FitAuraText(f, size)
        local fh = math.max(6, math.floor(size * 0.6 + 0.5))
        f.count:SetFont("Fonts\\ARIALN.TTF", fh, "OUTLINE")
        f.timerText:SetFont("Fonts\\ARIALN.TTF", fh, "OUTLINE")
        if f.cooldown then
            if f.cooldown.SetHideCountdownNumbers then
                f.cooldown:SetHideCountdownNumbers(true)
            end
            f.cooldown.noCooldownCount = (db.cdText ~= "omnicc") and true or nil
        end
        if db.cdText ~= "small" then f.timerText:SetText("") end
    end
    for i = 1, MAX_BUFFS do
        local f = btn.buffs[i]
        f:SetSize(bs, bs)
        FitAuraText(f, bs)
        if f.SetMouseClickEnabled then
            f:EnableMouse(db.auraTooltips and true or false)
            f:SetMouseClickEnabled(false)
        end
        f:ClearAllPoints()
        if i == 1 then
            f:SetPoint("BOTTOMRIGHT", btn.health, "BOTTOMRIGHT", -1, 1)
        else
            f:SetPoint("RIGHT", btn.buffs[i - 1], "LEFT", -1, 0)
        end
    end
    for i = 1, MAX_DEBUFFS do
        local f = btn.debuffs[i]
        f:SetSize(ds, ds)
        FitAuraText(f, ds)
        if f.SetMouseClickEnabled then
            f:EnableMouse(db.auraTooltips and true or false)
            f:SetMouseClickEnabled(false)
        end
        f:ClearAllPoints()
        if i == 1 then
            f:SetPoint("BOTTOMLEFT", btn.health, "BOTTOMLEFT", 1, 1)
        else
            f:SetPoint("LEFT", btn.debuffs[i - 1], "RIGHT", 1, 0)
        end
    end

    for i = 1, 4 do
        btn.borderTex[i]:SetShown(db.border)
    end

    -- MT/MA stacked target / ToT rows (inside the frame, nothing overlaps
    -- the neighboring group column)
    if IsTankKind(btn) then
        EnsureTankExtras(btn)
        local row = btn.targetRow
        if db.tankTarget then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, -unitH)
            row:SetSize(db.width, TANK_TARGET_H)
            row:Show()
        else
            row:Hide()
        end
        if btn.totRow then
            local tot = btn.totRow
            if db.tankTarget and db.tankToT then
                -- full width, stacked directly under the target bar
                -- (matches the reference video)
                tot:ClearAllPoints()
                tot:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, -(unitH + TANK_TARGET_H))
                tot:SetSize(db.width, TANK_TOT_H)
                -- shown/hidden by UpdateTankTarget (hides when no ToT exists)
            else
                tot:Hide()
            end
        end
    end
end

local function CreateAuraFrame(btn, isDebuff)
    local f = CreateFrame("Frame", nil, btn.overlay)
    f:SetSize(11, 11)
    f:Hide()
    f.orfBtn = btn
    f.isDebuff = isDebuff
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- duration spiral, like the old CompactAuraTemplate. A real Cooldown
    -- widget, so OmniCC and similar hook its SetCooldown and attach their
    -- countdown text automatically; native number display follows the
    -- client's own countdownForCooldowns setting
    f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cooldown:SetAllPoints(f.icon)
    f.cooldown:SetReverse(true)
    if f.cooldown.SetDrawEdge then f.cooldown:SetDrawEdge(false) end
    -- native countdown text never fits icons this small; always hidden.
    -- Countdown display is either our own scaled text (cdText = small) or
    -- an external OmniCC-style addon (cdText = omnicc).
    if f.cooldown.SetHideCountdownNumbers then
        f.cooldown:SetHideCountdownNumbers(true)
    end

    -- stack count / countdown text / dispel border live on a layer ABOVE
    -- the spiral so they stay readable while the cooldown sweeps
    local top = CreateFrame("Frame", nil, f)
    top:SetAllPoints()
    top:SetFrameLevel(f.cooldown:GetFrameLevel() + 1)
    f.count = top:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    f.count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, 0)
    f.timerText = top:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    f.timerText:SetPoint("CENTER", f, "CENTER", 0, 0)
    if isDebuff then
        f.border = top:CreateTexture(nil, "OVERLAY")
        f.border:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
        f.border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
        f.border:SetTexture(TEX_DEBUFF_BORDER)
        f.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
    end

    -- hover tooltip; clicks stay disabled so they pass through to the
    -- secure unit button (targeting / Clique keep working). Only wired
    -- when the client supports motion-without-clicks.
    if f.SetMouseClickEnabled then
        f:EnableMouse(db.auraTooltips and true or false)
        f:SetMouseClickEnabled(false)
        f:SetScript("OnEnter", function(self)
            if not db.auraTooltips then return end
            local unit = self.orfBtn.unit
            if not unit or not self.tipIndex then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
            if GameTooltip.SetUnitAura then
                GameTooltip:SetUnitAura(unit, self.tipIndex, self.tipFilter)
            elseif self.isDebuff then
                GameTooltip:SetUnitDebuff(unit, self.tipIndex, self.tipFilter)
            else
                GameTooltip:SetUnitBuff(unit, self.tipIndex, self.tipFilter)
            end
            GameTooltip:Show()
        end)
        f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return f
end

local function StyleButton(btn, kind)
    if btn.orfStyled then return end
    btn.orfStyled = true
    btn.orfKind = kind

    btn:RegisterForClicks("AnyUp")

    -- background
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(0, 0, 0, 0.6)

    -- 1px border (the old "Display Border" option)
    btn.borderTex = {}
    local function edge()
        local t = btn:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0, 0, 0, 0.9)
        return t
    end
    btn.borderTex[1] = edge()
    btn.borderTex[1]:SetPoint("TOPLEFT", 0, 0)
    btn.borderTex[1]:SetPoint("TOPRIGHT", 0, 0)
    btn.borderTex[1]:SetHeight(1)
    btn.borderTex[2] = edge()
    btn.borderTex[2]:SetPoint("BOTTOMLEFT", 0, 0)
    btn.borderTex[2]:SetPoint("BOTTOMRIGHT", 0, 0)
    btn.borderTex[2]:SetHeight(1)
    btn.borderTex[3] = edge()
    btn.borderTex[3]:SetPoint("TOPLEFT", 0, 0)
    btn.borderTex[3]:SetPoint("BOTTOMLEFT", 0, 0)
    btn.borderTex[3]:SetWidth(1)
    btn.borderTex[4] = edge()
    btn.borderTex[4]:SetPoint("TOPRIGHT", 0, 0)
    btn.borderTex[4]:SetPoint("BOTTOMRIGHT", 0, 0)
    btn.borderTex[4]:SetWidth(1)

    -- health bar: the original Raid-Bar-Hp-Fill (round-one look); the
    -- stray line came from the Raid-Bar-Hp-Bg art, which is now a flat
    -- dark fill instead
    btn.health = CreateFrame("StatusBar", nil, btn)
    btn.health:SetStatusBarTexture(TEX_HP_FILL)
    btn.health:GetStatusBarTexture():SetDrawLayer("ARTWORK")
    btn.healthBg = btn.health:CreateTexture(nil, "BACKGROUND")
    btn.healthBg:SetAllPoints()
    btn.healthBg:SetColorTexture(0, 0, 0, 0.4)

    -- incoming heal overlay (LibHealPredict-1.0)
    btn.healPred = btn.health:CreateTexture(nil, "ARTWORK", nil, 1)
    btn.healPred:SetColorTexture(0, 0.85, 0, 0.55)
    btn.healPred:Hide()
    if MODERN then
        -- (see UpdateNativeHealPrediction) starts at the end of the health
        -- fill, as wide as the health bar; the health bar clips the rest
        local hb = CreateFrame("StatusBar", nil, btn.health)
        hb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        hb:SetStatusBarColor(0, 0.85, 0, 0.55)
        local fill = btn.health:GetStatusBarTexture()
        hb:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
        hb:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
        hb:SetWidth(math.max(1, db.width - 2))
        hb:SetFrameLevel(btn.health:GetFrameLevel())
        hb:Hide()
        if btn.health.SetClipsChildren then btn.health:SetClipsChildren(true) end
        btn.healPredBar = hb
    end

    -- power bar (original resource fill)
    btn.power = CreateFrame("StatusBar", nil, btn)
    btn.power:SetStatusBarTexture(TEX_RES_FILL)
    btn.power:GetStatusBarTexture():SetDrawLayer("ARTWORK")
    btn.powerBg = btn.power:CreateTexture(nil, "BACKGROUND")
    btn.powerBg:SetAllPoints()
    btn.powerBg:SetColorTexture(0, 0, 0, 0.5)

    -- overlay for text and icons, above the bars (dedicated icon layer)
    btn.overlay = CreateFrame("Frame", nil, btn)
    btn.overlay:SetAllPoints()
    btn.overlay:SetFrameLevel(btn:GetFrameLevel() + 10)

    -- centered name with automatic "..." truncation, like the old frames
    btn.nameText = btn.overlay:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    btn.nameText:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
    btn.nameText:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -3, -3)
    btn.nameText:SetJustifyH("CENTER")
    btn.nameText:SetWordWrap(false)

    btn.statusText = btn.overlay:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    btn.statusText:SetJustifyH("CENTER")

    btn.leaderIcon = btn.overlay:CreateTexture(nil, "OVERLAY")
    btn.leaderIcon:SetSize(11, 11)
    btn.leaderIcon:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -3)
    btn.leaderIcon:Hide()

    -- MT/MA shield icon (players marked main tank / main assist),
    -- pinned inside the frame's left edge
    btn.roleIcon = btn.overlay:CreateTexture(nil, "OVERLAY")
    btn.roleIcon:SetSize(11, 11)
    btn.roleIcon:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -3)
    btn.roleIcon:Hide()

    btn.centerIcon = btn.overlay:CreateTexture(nil, "OVERLAY")
    btn.centerIcon:SetSize(16, 16)
    btn.centerIcon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.centerIcon:Hide()

    -- aggro highlight (old "Display Aggro Highlight")
    btn.aggro = CreateFrame("Frame", nil, btn.overlay)
    btn.aggro:Hide()
    btn.aggroTex = MakeOutline(btn.aggro, 1, 0, 0, 0.9)

    -- selection highlight: white border on your current target (plain
    -- outline -- the old Raid-FrameHighlights texture no longer ships on
    -- the 1.15.9 client)
    btn.selection = CreateFrame("Frame", nil, btn.overlay)
    btn.selection:SetFrameLevel(btn.overlay:GetFrameLevel() + 1)
    btn.selection:Hide()
    MakeOutline(btn.selection, 1, 1, 1, 0.9)

    -- auras
    btn.buffs = {}
    for i = 1, MAX_BUFFS do btn.buffs[i] = CreateAuraFrame(btn, false) end
    btn.debuffs = {}
    for i = 1, MAX_DEBUFFS do btn.debuffs[i] = CreateAuraFrame(btn, true) end

    -- scripts
    btn:SetScript("OnEnter", function(self)
        if self.unit then
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            GameTooltip:SetUnit(self.unit)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnShow", function(self)
        unitMapDirty = true
        if self.unit then UpdateAll(self) end
    end)
    btn:SetScript("OnHide", function() unitMapDirty = true end)
    btn:SetScript("OnAttributeChanged", function(self, attr, value)
        if attr == "unit" then
            self.unit = value
            self.guid = value and UnitGUID(value) or nil
            unitMapDirty = true
            if value and self:IsShown() then UpdateAll(self) end
        end
    end)

    -- click-cast (Clique etc.) registration; safe here, buttons are
    -- pre-instantiated out of combat at spawn
    _G.ClickCastFrames = _G.ClickCastFrames or {}
    _G.ClickCastFrames[btn] = true

    LayoutButtonInternals(btn)
    allButtons[#allButtons + 1] = btn
    if IsTankKind(btn) then
        tankButtons[#tankButtons + 1] = btn
    end
end

--------------------------------------------------------------------------------
-- headers
--------------------------------------------------------------------------------

local function InitialConfigSnippet(extraH)
    return string.format([[
        self:SetWidth(%d)
        self:SetHeight(%d)
        self:SetAttribute("*type1", "target")
        self:SetAttribute("*type2", "togglemenu")
    ]], db.width, db.height + (extraH or 0))
end

local function CreateHeader(name, isPet, extraH, party)
    local template = isPet and "SecureGroupPetHeaderTemplate" or "SecureGroupHeaderTemplate"
    local h = CreateFrame("Frame", name, container, template)
    if party then
        -- a 5-player group only: the header shows nothing in a raid
        h:SetAttribute("showParty", true)
        h:SetAttribute("showPlayer", db.partyPlayer and true or false)
    else
        h:SetAttribute("showRaid", true)
    end
    h:SetAttribute("point", "TOP")          -- cardinal directions only
    h:SetAttribute("xOffset", 0)
    h:SetAttribute("yOffset", -db.frameGap)
    h:SetAttribute("template", "SecureUnitButtonTemplate")
    h:SetAttribute("templateType", "Button")
    h:SetAttribute("initialConfigFunction", InitialConfigSnippet(extraH))
    if isPet then
        h:SetAttribute("filterOnPet", true)
    end
    return h
end

-- negative startingIndex trick: force the full child complement into
-- existence right now, before any combat can ever happen
local function InstantiateChildren(h, count, kind)
    h:Show()
    h:SetAttribute("startingIndex", -(count - 1))
    h:SetAttribute("startingIndex", 1)
    local name = h:GetName()
    for i = 1, count do
        local btn = _G[name .. "UnitButton" .. i]
        if btn then StyleButton(btn, kind) end
    end
end

--------------------------------------------------------------------------------
-- layout
--------------------------------------------------------------------------------

local function GroupBlockHeight()
    return TITLE_HEIGHT + MEMBERS_PER_GROUP * db.height + (MEMBERS_PER_GROUP - 1) * db.frameGap
end

local function PlaceBlock(title, header, x, y)
    title:ClearAllPoints()
    title:SetPoint("TOPLEFT", container, "TOPLEFT", x, y)
    title:SetSize(db.width, TITLE_HEIGHT)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", container, "TOPLEFT", x, y - TITLE_HEIGHT)
    header:SetWidth(db.width)
    header:SetAttribute("yOffset", -db.frameGap)
end

local function DoApplyLayout()
    local rows   = math.max(1, math.min(NUM_GROUPS, db.rows))
    local cols   = math.ceil(NUM_GROUPS / rows)
    local blockH = GroupBlockHeight()
    local gapX = db.groupGap
    local gapY = db.groupGap + 4
    local step   = db.width + gapX

    -- flow column count for combined mode
    local perCol   = math.max(1, math.min(MAX_RAID, db.perColumn))
    local flowCols = math.ceil(MAX_RAID / perCol)

    local leadCols = db.displayTanks and 1 or 0
    local midCols  = db.grouped and cols or flowCols
    local petCols  = db.displayPets and 1 or 0

    container:SetSize(
        (leadCols + midCols + petCols) * step - gapX,
        math.max(rows * (blockH + gapY) - gapY,
                 TITLE_HEIGHT + perCol * (db.height + db.frameGap)))
    container:ClearAllPoints()
    container:SetPoint(db.point, UIParent, db.point, db.x, db.y)

    local snippet   = InitialConfigSnippet(0)
    local mtSnippet = InitialConfigSnippet(TankExtraFor("mt"))
    local maSnippet = InitialConfigSnippet(TankExtraFor("ma"))
    local mtSlotH   = db.height + TankExtraFor("mt") + db.frameGap

    -- Main Tank / Main Assist side column (stacks dynamically by MT count)
    local counts  = GroupCounts()
    local mtCount = CountRole("MAINTANK")
    local maCount = CountRole("MAINASSIST")
    if db.displayTanks then
        -- the old tank column had no "Main Tank" text -- frames just start
        -- at the top; the labels only appear as an aid while unlocked
        local titleOff = (not db.locked) and TITLE_HEIGHT or 0
        local y = 0
        PlaceBlock(titleMT, headerMT, 0, y)
        headerMT:ClearAllPoints()
        headerMT:SetPoint("TOPLEFT", container, "TOPLEFT", 0, y - titleOff)
        titleMT:SetShown(not db.locked)
        if mtCount > 0 or not db.locked then
            y = y - (titleOff + math.max(mtCount, 1) * mtSlotH + 4)
        end
        PlaceBlock(titleMA, headerMA, 0, y)
        headerMA:ClearAllPoints()
        headerMA:SetPoint("TOPLEFT", container, "TOPLEFT", 0, y - titleOff)
        titleMA:SetShown(not db.locked)
        headerMT:SetAttribute("initialConfigFunction", mtSnippet)
        headerMA:SetAttribute("initialConfigFunction", maSnippet)
        headerMT:Show()
        headerMA:Show()
    else
        titleMT:Hide()
        titleMA:Hide()
        headerMT:Hide()
        headerMA:Hide()
    end

    -- main area: grouped blocks or combined flow
    if db.grouped then
        headerAll:Hide()
        for g = 1, NUM_GROUPS do
            local col = math.floor((g - 1) / rows)
            local row = (g - 1) % rows
            local x = (leadCols + col) * step
            local y = -(row * (blockH + gapY))
            PlaceBlock(groupTitles[g], groupHeaders[g], x, y)
            groupHeaders[g]:SetAttribute("initialConfigFunction", snippet)
            groupHeaders[g]:Show()
        end
    else
        for g = 1, NUM_GROUPS do
            groupTitles[g]:Hide()
            groupHeaders[g]:Hide()
        end
        headerAll:SetAttribute("initialConfigFunction", snippet)
        headerAll:SetAttribute("yOffset", -db.frameGap)
        headerAll:SetAttribute("unitsPerColumn", perCol)
        headerAll:SetAttribute("maxColumns", flowCols)
        headerAll:SetAttribute("columnSpacing", db.groupGap)
        headerAll:SetAttribute("columnAnchorPoint", "LEFT")
        if db.sortMode == "name" then
            headerAll:SetAttribute("groupBy", nil)
            headerAll:SetAttribute("sortMethod", "NAME")
        else
            headerAll:SetAttribute("groupBy", "GROUP")
            headerAll:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8")
            headerAll:SetAttribute("sortMethod", "INDEX")
        end
        headerAll:ClearAllPoints()
        headerAll:SetPoint("TOPLEFT", container, "TOPLEFT", leadCols * step, 0)
        headerAll:Show()
    end

    -- the party: where Group 1 stands (a party never shares the screen
    -- with the raid's groups - its header shows nothing in a raid)
    if headerParty then
        if PartyOn() then
            PlaceBlock(titleParty, headerParty, leadCols * step, 0)
            headerParty:SetAttribute("initialConfigFunction", snippet)
            headerParty:SetAttribute("showPlayer", db.partyPlayer and true or false)
            headerParty:Show()
        else
            titleParty:Hide()
            headerParty:Hide()
        end
    end

    -- pets column (in a party: beside the party, with the party frames on)
    if db.displayPets then
        local party = PartyActive()
        local x = party and ((leadCols + 1) * step) or ((leadCols + midCols) * step)
        local petCount = CountPets()
        PlaceBlock(titlePets, headerPets, x, 0)
        titlePets:SetShown(petCount > 0 or not db.locked)
        headerPets:SetAttribute("initialConfigFunction", snippet)
        headerPets:SetAttribute("showParty", PartyOn())
        headerPets:SetAttribute("showPlayer", (PartyOn() and db.partyPlayer) and true or false)
        headerPets:Show()
    else
        titlePets:Hide()
        headerPets:Hide()
    end

    -- resize every button (MT/MA include the target/ToT rows)
    for i = 1, #allButtons do
        local btn = allButtons[i]
        btn:SetSize(db.width, ButtonHeightFor(btn))
        LayoutButtonInternals(btn)
    end
    UpdateAllVisible()
end

local function QueueLayout()
    if InCombatLockdown() then
        layoutQueued = true
    else
        DoApplyLayout()
    end
end

local function UpdateTitles()
    -- like the old frames: a group (and its title) only appears once
    -- someone is actually in it while the raid fills
    local counts = GroupCounts()
    for g = 1, NUM_GROUPS do
        groupTitles[g]:SetShown(db.grouped
            and ((IsInRaid() and counts[g] > 0) or not db.locked))
    end
    if titleParty then titleParty:SetShown(PartyActive()) end
    if db.locked then
        titleMT:Hide()
        titleMA:Hide()
        if (IsInRaid() or PartyActive()) and CountPets() > 0 then
            -- pets title handled by layout
        else
            titlePets:Hide()
        end
    end
end

--------------------------------------------------------------------------------
-- move mode (drag overlay + solo mock preview)
--------------------------------------------------------------------------------

local MOCK_CLASSES = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "DRUID",
                       "HUNTER", "WARLOCK", "PALADIN", "SHAMAN", "WARRIOR" }

local function BuildMock()
    if mockFrames.built then return end
    mockFrames.built = true
    for g = 1, NUM_GROUPS do
        mockFrames[g] = {}
        for i = 1, MEMBERS_PER_GROUP do
            local f = CreateFrame("Frame", nil, container)
            f:Hide()
            f.bg = f:CreateTexture(nil, "BACKGROUND")
            f.bg:SetAllPoints()
            f.bg:SetColorTexture(0, 0, 0, 0.6)
            f.fill = f:CreateTexture(nil, "ARTWORK")
            f.fill:SetTexture(TEX_HP_FILL)
            f.name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            f.name:SetPoint("TOPLEFT", 3, -3)
            f.name:SetText("Raider" .. ((g - 1) * MEMBERS_PER_GROUP + i))
            f.pct = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            f.pct:SetText("100%")
            mockFrames[g][i] = f
        end
    end
end

local function LayoutMock()
    if not mockFrames.built then return end
    local rows = math.max(1, math.min(NUM_GROUPS, db.rows))
    local blockH = GroupBlockHeight()
    local powerH = db.powerBars and PowerHeight() or 0
    local leadCols = db.displayTanks and 1 or 0
    local gapX = db.groupGap
    local gapY = db.groupGap + 4
    local step = db.width + gapX
    for g = 1, NUM_GROUPS do
        local col = math.floor((g - 1) / rows)
        local row = (g - 1) % rows
        local x = (leadCols + col) * step
        local y = -(row * (blockH + gapY)) - TITLE_HEIGHT
        for i = 1, MEMBERS_PER_GROUP do
            local f = mockFrames[g][i]
            f:SetSize(db.width, db.height)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", container, "TOPLEFT", x, y - (i - 1) * (db.height + db.frameGap))
            local class = MOCK_CLASSES[((g + i - 2) % #MOCK_CLASSES) + 1]
            local c = RAID_CLASS_COLORS[class]
            f.fill:ClearAllPoints()
            f.fill:SetPoint("TOPLEFT", 1, -1)
            f.fill:SetPoint("BOTTOMRIGHT", -1, 1 + powerH)
            if c then f.fill:SetVertexColor(c.r, c.g, c.b) end
            f.pct:ClearAllPoints()
            f.pct:SetPoint("TOP", f, "TOP", 0, -(math.floor(db.height / 2) - 3))
        end
    end
end

local function SetMockShown(show)
    if show then
        BuildMock()
        LayoutMock()
    end
    if mockFrames.built then
        local party = PartyActive()
        for g = 1, NUM_GROUPS do
            for i = 1, MEMBERS_PER_GROUP do
                -- (the real party frames stand where the sample Group 1 is)
                mockFrames[g][i]:SetShown(show and not (party and g == 1))
            end
        end
    end
end

local function BuildDragOverlay()
    if dragOverlay then return end
    dragOverlay = CreateFrame("Button", "OldRF_DragOverlay", container)
    dragOverlay:SetAllPoints()
    dragOverlay:SetFrameStrata("HIGH")
    dragOverlay:EnableMouse(true)
    dragOverlay:RegisterForDrag("LeftButton")
    dragOverlay:Hide()

    local bg = dragOverlay:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 1, 0, 0.15)

    local label = dragOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER")
    label:SetText("OldRaidFrames\n|cffffffffdrag to move  --  right-click: settings|r")

    -- right-click anywhere on the overlay opens the options panel, so the
    -- frames are configurable from inside Edit Mode without typing /orf
    dragOverlay:RegisterForClicks("RightButtonUp")
    dragOverlay:SetScript("OnClick", function(self, button)
        if button == "RightButton" and ns.ToggleOptionsPanel then
            ns.ToggleOptionsPanel()
        end
    end)

    dragOverlay:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        container:StartMoving()
    end)
    dragOverlay:SetScript("OnDragStop", function()
        container:StopMovingOrSizing()
        local point, _, _, x, y = container:GetPoint(1)
        db.point, db.x, db.y = point, x, y
        container:ClearAllPoints()
        container:SetPoint(db.point, UIParent, db.point, db.x, db.y)
    end)
end

local function SetLocked(locked)
    db.locked = locked
    RunOrQueue(function()
        BuildDragOverlay()
        dragOverlay:SetShown(not locked)
        SetMockShown(not locked and not IsInRaid())
        UpdateTitles()
        QueueLayout()
    end)
end

--------------------------------------------------------------------------------
-- Edit Mode integration (1.15.9 Midnight UI)
--
-- The frames are custom secure headers, not Edit Mode systems -- registering
-- those with the manager is not supported, and Edit Mode layout switching
-- would fight the profile system. Instead, opening Edit Mode unlocks them:
-- the green overlay appears, drag to move, right-click it for the options
-- panel. Leaving Edit Mode restores the lock state you had before.
--------------------------------------------------------------------------------

local editModeHooked  = false
local editModeUnlockedByUs = false

local function OnEditModeEnter()
    if not container or not db then return end
    if db.locked then
        editModeUnlockedByUs = true
        SetLocked(false)
        Print("Edit Mode: raid frames unlocked — drag the green overlay, "
            .. "right-click it for settings.")
    end
end

local function OnEditModeExit()
    if editModeUnlockedByUs then
        editModeUnlockedByUs = false
        SetLocked(true)
    end
end

local function HookEditMode()
    if editModeHooked then return true end
    local mgr = _G.EditModeManagerFrame
    if not mgr or not mgr.HookScript then return false end
    mgr:HookScript("OnShow", OnEditModeEnter)
    mgr:HookScript("OnHide", OnEditModeExit)
    editModeHooked = true
    -- already in Edit Mode when we hooked (e.g. Blizzard_EditMode just loaded)
    if mgr:IsShown() then OnEditModeEnter() end
    return true
end

--------------------------------------------------------------------------------
-- option application (shared by slash commands and the options panel)
--------------------------------------------------------------------------------

local RefreshOptionsPanel   -- forward

local OPTION_APPLY = {
    grouped      = "layout",
    displayTanks = "layout",
    tankTarget   = "layout",
    tankToT      = "layout",
    displayPets  = "layout",
    showParty    = "party",
    partyPlayer  = "layout",
    powerBars    = "layout",
    classColor   = "visual",
    showRealm    = "visual",
    healthText   = "visual",
    buffFilter   = "visual",
    dispelOnly   = "visual",
    showBuffs    = "visual",
    showDebuffs  = "visual",
    buffSize     = "border",
    debuffSize   = "border",
    buffNameMode   = "visual",
    debuffNameMode = "visual",
    auraTooltips = "border",
    auraSwipe    = "visual",
    cdText       = "border",
    aggro        = "visual",
    tankIcons    = "visual",
    leaderIcons  = "visual",
    healPredict     = "healpred",
    healPredictHots = "healpred",
    healPredictAoE  = "healpred",
    sortMode     = "layout",
    rows         = "layout",
    width        = "layout",
    height       = "layout",
    frameGap     = "layout",
    groupGap     = "layout",
    perColumn    = "layout",
    border       = "border",
    rangeFade    = "range",
    hideBlizzard = "blizzard",
}

local function ApplyOption(key)
    local mode = OPTION_APPLY[key]
    if mode == "layout" then
        QueueLayout()
        LayoutMock()
        UpdateTitles()
    elseif mode == "visual" then
        UpdateAllVisible()
    elseif mode == "healpred" then
        ApplyHealPredictSettings()
        UpdateAllVisible()
    elseif mode == "border" then
        for i = 1, #allButtons do LayoutButtonInternals(allButtons[i]) end
    elseif mode == "range" then
        if not db.rangeFade then
            for i = 1, #allButtons do allButtons[i]:SetAlpha(1) end
        end
    elseif mode == "party" then
        QueueLayout()
        LayoutMock()
        UpdateTitles()
        if db.showParty and ZacUIParty() then
            Print("ZacUI's party frames are on, so these stay off. Turn ZacUI's off (and reload) to use these.")
        elseif db.showParty then
            if db.hideBlizzard then HideBlizzardRaidFrames() end
        elseif db.hideBlizzard then
            Print("Blizzard party frames will return after /reload.")
        end
    elseif mode == "blizzard" then
        if db.hideBlizzard then
            HideBlizzardRaidFrames()
        else
            Print("Blizzard raid and party frames will return after /reload.")
        end
    end
    if RefreshOptionsPanel then RefreshOptionsPanel() end
end

-- everything at once: used after a profile switch / copy / reset / import,
-- where any option may have changed under us
function ns.ApplyAll()
    if not db then return end
    if db.hideBlizzard then HideBlizzardRaidFrames() end
    ApplyHealPredictSettings()
    if container then
        for i = 1, #allButtons do LayoutButtonInternals(allButtons[i]) end
        if not db.rangeFade then
            for i = 1, #allButtons do allButtons[i]:SetAlpha(1) end
        end
        SetLocked(db.locked)      -- re-syncs the drag overlay, mock and titles
        QueueLayout()
        UpdateAllVisible()
        UpdateTitles()
        LayoutMock()
    end
    if RefreshOptionsPanel then RefreshOptionsPanel() end
end

local function ToggleOption(key)
    db[key] = not db[key]
    ApplyOption(key)
end

local function SetOption(key, value)
    db[key] = value
    ApplyOption(key)
end

-- add/remove a spell name on a filter list (shared by panel edit boxes and
-- /orf buffname | debuffname); names stored lowercased, matching is exact
local function ToggleAuraName(kind, name)
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return end
    local list = (kind == "buff") and db.buffNames or db.debuffNames
    local key = name:lower()
    if list[key] then
        list[key] = nil
        Print(("removed \"%s\" from the %s list."):format(name, kind))
    else
        list[key] = true
        Print(("added \"%s\" to the %s list."):format(name, kind))
    end
    local mode = (kind == "buff") and db.buffNameMode or db.debuffNameMode
    if mode == "off" then
        Print("note: the " .. kind .. " name filter is Off — set it to Hide Listed or Only Listed to take effect.")
    end
    UpdateAllVisible()
    if RefreshOptionsPanel then RefreshOptionsPanel() end
end

--------------------------------------------------------------------------------
-- options panel (modeled on the old Raid Profiles config: everything
-- clickable -- checkboxes, sliders, cycling dropdowns, lock/unlock)
--------------------------------------------------------------------------------

local PANEL_CHECKS = {
    { key = "grouped",      label = "Keep Groups Together" },
    { key = "classColor",   label = "Use Class Colors" },
    { key = "showRealm",    label = "Show Realm on Names" },
    { key = "powerBars",    label = "Display Power Bars" },
    { key = "border",       label = "Display Border" },
    { key = "displayTanks", label = "Display Main Tank / Assist" },
    { key = "tankTarget",   label = "Tank Target Bars" },
    { key = "tankToT",      label = "Main Tank Target of Target" },
    { key = "displayPets",  label = "Display Pets" },
    { key = "showParty",    label = "Display Party Frames" },
    { key = "partyPlayer",  label = "Show Yourself in Party" },
    { key = "aggro",        label = "Display Aggro Highlight" },
    { key = "dispelOnly",   label = "Only Dispellable Debuffs" },
    { key = "showBuffs",    label = "Show Buffs" },
    { key = "showDebuffs",  label = "Show Debuffs" },
    { key = "rangeFade",    label = "Fade Out of Range" },
    { key = "auraTooltips", label = "Aura Tooltips" },
    { key = "auraSwipe",    label = "Aura Duration Spiral" },
    { key = "tankIcons",    label = "Shield Icons (assist / tank)" },
    { key = "leaderIcons",  label = "Leader Crown (not stock)" },
    { key = "healPredict",  label = "Heal Prediction" },
    { key = "healPredictHots", label = "Predict HoT Ticks" },
    { key = "healPredictAoE",  label = "Predict Group Heals" },
    { key = "hideBlizzard", label = "Hide Blizzard Raid / Party Frames" },
}

local PANEL_CYCLES = {
    { key = "healthText", label = "Health Text",
      values = { "none", "percent", "value", "lost" },
      names  = { none = "None", percent = "Percentage", value = "Health Remaining", lost = "Health Lost (missing hp)" } },
    { key = "sortMode", label = "Sort By (combined mode)",
      values = { "group", "name" },
      names  = { group = "Group", name = "Alphabetical" } },
    { key = "buffFilter", label = "Buff Filter",
      values = { "mine", "all" },
      names  = { mine = "My Buffs Only (old behavior)", all = "All (world buffs / boons)" } },
    { key = "buffNameMode", label = "Buff Name Filter", list = "buffNames",
      values = { "off", "block", "only" },
      names  = { off = "Off", block = "Hide Listed", only = "Only Listed" } },
    { key = "debuffNameMode", label = "Debuff Name Filter", list = "debuffNames",
      values = { "off", "block", "only" },
      names  = { off = "Off", block = "Hide Listed", only = "Only Listed" } },
    { key = "cdText", label = "Cooldown Text",
      values = { "off", "small", "omnicc" },
      names  = { off = "Off", small = "Small (scales with icon)",
                 omnicc = "OmniCC / external addon" } },
}

local PANEL_SLIDERS = {
    { key = "width",     label = "Frame Width",     min = 40, max = 150, step = 2 },
    { key = "height",    label = "Frame Height",    min = 24, max = 80,  step = 2 },
    { key = "frameGap",  label = "Frame Spacing",   min = 0,  max = 10,  step = 1 },
    { key = "groupGap",  label = "Group Spacing",   min = 0,  max = 16,  step = 1 },
    { key = "rows",      label = "Groups / Column", min = 1,  max = 8,   step = 1 },
    { key = "perColumn", label = "Flow / Column",   min = 3,  max = 10,  step = 1 },
    { key = "buffSize",   label = "Buff Size",   min = 0, max = 30, step = 1, zeroText = "Auto" },
    { key = "debuffSize", label = "Debuff Size", min = 0, max = 30, step = 1, zeroText = "Auto" },
}

local function SliderText(def, value)
    if value == 0 and def.zeroText then return def.zeroText end
    return value
end

local panelWidgets = { checks = {}, cycles = {}, sliders = {} }

local function BuildOptionsPanel()
    if optionsPanel then return end

    local p = CreateFrame("Frame", "OldRF_Options", UIParent)
    optionsPanel = p
    -- 2 checkbox columns, one 24 px row per 2 PANEL_CHECKS (808 at 22 checks)
    p:SetSize(400, 544 + math.ceil(#PANEL_CHECKS / 2) * 24)
    p:SetPoint("CENTER")
    p:SetFrameStrata("DIALOG")
    p:SetToplevel(true)          -- click-to-front, so it never interleaves with
    p:SetMovable(true)           -- the profile window sharing this strata
    p:EnableMouse(true)
    p:SetClampedToScreen(true)
    p:SetScript("OnMouseDown", function(self) self:Raise() end)
    p:Hide()

    p.bg = p:CreateTexture(nil, "BACKGROUND")
    p.bg:SetAllPoints()
    p.bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
    MakeOutline(p, 0.4, 0.4, 0.4, 1)

    -- title bar (drag handle)
    local titleBar = CreateFrame("Button", nil, p)
    titleBar:SetPoint("TOPLEFT")
    titleBar:SetPoint("TOPRIGHT")
    titleBar:SetHeight(24)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnMouseDown", function() p:Raise() end)
    titleBar:SetScript("OnDragStart", function()
        p:Raise()
        p:StartMoving()
    end)
    titleBar:SetScript("OnDragStop", function() p:StopMovingOrSizing() end)
    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
    title:SetText("OldRaidFrames " .. VERSION)

    local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, 0)

    -- ESC closes it
    table.insert(UISpecialFrames, "OldRF_Options")

    -- checkboxes, two columns
    local colX = { 14, 204 }
    local startY = -34
    local rowH = 24
    for i, def in ipairs(PANEL_CHECKS) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", p, "TOPLEFT", colX[col + 1], startY - row * rowH)
        cb:SetScript("OnClick", function() ToggleOption(def.key) end)
        local label = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        label:SetText(def.label)
        panelWidgets.checks[def.key] = cb
    end

    local afterChecks = startY - math.ceil(#PANEL_CHECKS / 2) * rowH - 8

    -- cycling dropdowns
    for i, def in ipairs(PANEL_CYCLES) do
        local y = afterChecks - (i - 1) * 30
        local label = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", p, "TOPLEFT", 16, y - 6)
        label:SetText(def.label .. ":")
        local btn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        btn:SetSize(210, 22)
        btn:SetPoint("TOPLEFT", p, "TOPLEFT", 176, y)
        btn:SetScript("OnClick", function()
            local cur = db[def.key]
            local idx = 1
            for j, v in ipairs(def.values) do
                if v == cur then idx = j break end
            end
            idx = idx % #def.values + 1
            SetOption(def.key, def.values[idx])
        end)
        panelWidgets.cycles[def.key] = { button = btn, def = def }
    end

    local afterCycles = afterChecks - #PANEL_CYCLES * 30 - 10

    -- sliders, two columns
    local sliderColX = { 16, 206 }
    for i, def in ipairs(PANEL_SLIDERS) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = sliderColX[col + 1]
        local y = afterCycles - row * 40
        local label = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", p, "TOPLEFT", x, y - 4)
        label:SetText(def.label)
        local valText = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        valText:SetPoint("TOPRIGHT", p, "TOPLEFT", x + 172, y - 4)

        local s = CreateFrame("Slider", nil, p)
        s:SetOrientation("HORIZONTAL")
        s:SetSize(170, 12)
        s:SetPoint("TOPLEFT", p, "TOPLEFT", x + 2, y - 20)
        s:SetMinMaxValues(def.min, def.max)
        s:SetValueStep(def.step)
        s:SetObeyStepOnDrag(true)
        s.track = s:CreateTexture(nil, "BACKGROUND")
        s.track:SetPoint("LEFT", 0, 0)
        s.track:SetPoint("RIGHT", 0, 0)
        s.track:SetHeight(4)
        s.track:SetColorTexture(0.25, 0.25, 0.25, 1)
        s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        local thumb = s:GetThumbTexture()
        thumb:SetSize(24, 24)
        s:SetScript("OnValueChanged", function(self, value)
            value = math.floor(value + 0.5)
            valText:SetText(SliderText(def, value))
            if self.orfInit and db[def.key] ~= value then
                db[def.key] = value
                self.orfPending = true
            end
        end)
        -- apply on release (avoids relayout spam while dragging)
        s:SetScript("OnMouseUp", function(self)
            if self.orfPending then
                self.orfPending = nil
                ApplyOption(def.key)
            end
        end)
        panelWidgets.sliders[def.key] = { slider = s, valText = valText, def = def }
    end

    local afterSliders = afterCycles - math.ceil(#PANEL_SLIDERS / 2) * 40 - 8

    -- aura name filter list editors (type a spell name, Enter toggles it)
    local FILTER_BOXES = {
        { kind = "buff",   label = "Buff list add/remove:" },
        { kind = "debuff", label = "Debuff list add/remove:" },
    }
    for i, def in ipairs(FILTER_BOXES) do
        local y = afterSliders - (i - 1) * 26
        local label = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", p, "TOPLEFT", 16, y - 6)
        label:SetText(def.label)
        local eb = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
        eb:SetSize(200, 20)
        eb:SetPoint("TOPLEFT", p, "TOPLEFT", 184, y - 1)
        eb:SetAutoFocus(false)
        eb:SetScript("OnEnterPressed", function(self)
            ToggleAuraName(def.kind, self:GetText())
            self:SetText("")
            self:ClearFocus()
        end)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    end
    local boxHint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    boxHint:SetPoint("TOPLEFT", p, "TOPLEFT", 16, afterSliders - 2 * 26 - 2)
    boxHint:SetText("Enter toggles the name on its list  --  /orf filters to review")

    local afterBoxes = afterSliders - 2 * 26 - 18

    -- bottom buttons
    local lockBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    lockBtn:SetSize(140, 24)
    lockBtn:SetPoint("TOPLEFT", p, "TOPLEFT", 16, afterBoxes)
    lockBtn:SetScript("OnClick", function()
        SetLocked(not db.locked)
        if RefreshOptionsPanel then RefreshOptionsPanel() end
        if not db.locked then
            Print("unlocked — drag the green overlay, then Lock.")
        end
    end)
    panelWidgets.lockBtn = lockBtn

    local resetBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    resetBtn:SetSize(140, 24)
    resetBtn:SetPoint("TOPLEFT", p, "TOPLEFT", 176, afterBoxes)
    resetBtn:SetText("Reset Position")
    resetBtn:SetScript("OnClick", function()
        db.point, db.x, db.y = DEFAULTS.point, DEFAULTS.x, DEFAULTS.y
        QueueLayout()
        Print("position reset.")
    end)

    -- profile manager (AceDB profiles, shared across your characters)
    local profBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    profBtn:SetSize(300, 24)
    profBtn:SetPoint("TOPLEFT", p, "TOPLEFT", 16, afterBoxes - 28)
    profBtn:SetScript("OnClick", function()
        if ns.Profiles then ns.Profiles.Toggle() end
    end)
    panelWidgets.profBtn = profBtn
    if not ns.Profiles then profBtn:Hide() end

    local hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", p, "BOTTOM", 0, 8)
    hint:SetText("/orf toggles this panel  --  /orf help for slash commands")
end

RefreshOptionsPanel = function()
    if not optionsPanel or not optionsPanel:IsShown() then return end
    for key, cb in pairs(panelWidgets.checks) do
        cb:SetChecked(db[key] and true or false)
    end
    for key, w in pairs(panelWidgets.cycles) do
        local names = w.def.names
        local text = names[db[key]] or tostring(db[key])
        if w.def.list and db[key] ~= "off" then
            local n = 0
            for _ in pairs(db[w.def.list] or {}) do n = n + 1 end
            text = text .. "  (" .. n .. " name" .. (n == 1 and "" or "s") .. ")"
        end
        w.button:SetText(text)
    end
    for key, w in pairs(panelWidgets.sliders) do
        w.slider.orfInit = nil
        w.slider:SetValue(db[key])
        w.slider.orfInit = true
        w.valText:SetText(SliderText(w.def, db[key]))
    end
    panelWidgets.lockBtn:SetText(db.locked and "Unlock (move frames)" or "Lock")
    if panelWidgets.profBtn then
        local cur = ns.Profiles and ns.Profiles.Ready() and ns.Profiles.Current()
        panelWidgets.profBtn:SetText(cur and ("Profiles...  (using: " .. cur .. ")")
            or "Profiles...")
    end
    if ns.Profiles then ns.Profiles.Refresh() end
end

local function ToggleOptionsPanel()
    BuildOptionsPanel()
    if optionsPanel:IsShown() then
        optionsPanel:Hide()
    else
        optionsPanel:Show()
        optionsPanel:Raise()
        RefreshOptionsPanel()
    end
end
ns.ToggleOptionsPanel = ToggleOptionsPanel

-- Profiles.lua parks its window beside this one instead of over it
function ns.OptionsPanel() return optionsPanel end

--------------------------------------------------------------------------------
-- events
--------------------------------------------------------------------------------

local UNIT_EVENTS = {
    UNIT_HEALTH          = UpdateHealth,
    UNIT_MAXHEALTH       = UpdateHealth,
    UNIT_HEALTH_FREQUENT = UpdateHealth,
    UNIT_POWER_UPDATE    = UpdatePower,
    UNIT_MAXPOWER        = UpdatePower,
    UNIT_DISPLAYPOWER    = UpdatePower,
    UNIT_NAME_UPDATE     = function(btn) UpdateName(btn) UpdateLeaderIcon(btn) end,
    UNIT_AURA            = UpdateAuras,
    UNIT_CONNECTION      = UpdateAll,
    UNIT_THREAT_SITUATION_UPDATE = UpdateAggro,
}

local driver = CreateFrame("Frame")
-- (ZacUI) no events of its own until ns.Start

local function OnEvent(self, event, arg1)
    if event == "ADDON_LOADED" then
        if false then   -- (ZacUI) the settings come from ns.Start
            OldRaidFramesDB = OldRaidFramesDB or {}
            -- AceDB-3.0 profiles (Profiles.lua): named profiles shared across
            -- every character on the account, one selected per character. A
            -- pre-profile flat saved variable is migrated into profiles.Default.
            local profile = ns.Profiles and ns.Profiles.Init()
            db = profile or OldRaidFramesDB   -- fallback: single flat config
            DeepFill(db, DEFAULTS)
            ns.MigrateProfile(db)
        elseif arg1 == "Blizzard_EditMode" then
            HookEditMode()   -- load-on-demand on some clients
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        driver.Setup()
        if ns.Profiles and ns.Profiles.InitComm then ns.Profiles.InitComm() end
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        local ops = pendingOps
        pendingOps = {}
        for i = 1, #ops do ops[i]() end
        if layoutQueued then
            layoutQueued = false
            DoApplyLayout()
        end
        -- combat-filtered buffs (world buffs/boons) reappear out of combat
        for i = 1, #allButtons do
            local btn = allButtons[i]
            if btn:IsShown() and btn.unit then UpdateAuras(btn) end
        end
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        -- entering combat: long-duration buffs drop off the frames
        for i = 1, #allButtons do
            local btn = allButtons[i]
            if btn:IsShown() and btn.unit then UpdateAuras(btn) end
        end
        return
    end

    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD"
        or event == "UNIT_PET" or event == "PLAYER_ROLES_ASSIGNED" then
        if event == "PLAYER_ENTERING_WORLD" then
            if db.hideBlizzard then HideBlizzardRaidFrames() end
            HookEditMode()
        end
        unitMapDirty = true
        UpdateTitles()
        UpdateAllVisible()
        if not db.locked then
            SetMockShown(not IsInRaid())
        end
        -- the party's own Blizzard frames can be made after login (the
        -- member pool fills as people join)
        if db.hideBlizzard and PartyOn() and event == "GROUP_ROSTER_UPDATE" then
            HideBlizzardPartyFrames()
        end
        -- MT/MA stacking and pet title depend on roster contents
        if db.displayTanks or db.displayPets then
            QueueLayout()
        end
        return
    end

    if event == "UNIT_HEAL_PREDICTION" then
        -- (the modern clients' overlay; LibHealPredict drives the others)
        if MODERN and arg1 then
            local list = ButtonsForUnit(arg1)
            if list then
                for i = 1, #list do
                    if list[i]:IsShown() then UpdateNativeHealPrediction(list[i]) end
                end
            end
        end
        return
    end

    if event == "PARTY_LEADER_CHANGED" then
        for i = 1, #allButtons do
            local btn = allButtons[i]
            if btn:IsShown() and btn.unit then UpdateLeaderIcon(btn) end
        end
        return
    end

    if event == "PLAYER_TARGET_CHANGED" then
        for i = 1, #allButtons do
            local btn = allButtons[i]
            if btn:IsShown() then UpdateSelection(btn) end
        end
        return
    end

    if event == "READY_CHECK" or event == "READY_CHECK_CONFIRM"
        or event == "INCOMING_RESURRECT_CHANGED" then
        for i = 1, #allButtons do
            local btn = allButtons[i]
            if btn:IsShown() and btn.unit then UpdateCenterIcon(btn) end
        end
        return
    end

    if event == "READY_CHECK_FINISHED" then
        if C_Timer and C_Timer.After then
            C_Timer.After(DEFAULT_READY_CHECK_STAY_TIME or 11, function()
                for i = 1, #allButtons do
                    local btn = allButtons[i]
                    if btn:IsShown() and btn.unit then UpdateCenterIcon(btn) end
                end
            end)
        end
        return
    end

    local handler = UNIT_EVENTS[event]
    if handler and arg1 then
        local list = ButtonsForUnit(arg1)
        if list then
            -- LibHealPredict does not register UNIT_AURA itself: HoT tracking
            -- runs off the consumer's aura pass. Only units we actually draw
            -- are scanned, and the library dedupes same-tick rescans, so this
            -- costs one UnitAura loop per real aura change per frame
            if event == "UNIT_AURA" and HealPredict and not MODERN
                and db.healPredict and db.healPredictHots then
                HealPredict:ScanAuras(arg1)
            end
            for i = 1, #list do
                local btn = list[i]
                if btn:IsShown() then handler(btn) end
            end
        end
    end
end

driver:SetScript("OnEvent", OnEvent)

--------------------------------------------------------------------------------
-- setup
--------------------------------------------------------------------------------

function driver.Setup()
    if container then return end

    if db.hideBlizzard then
        HideBlizzardRaidFrames()
    end

    container = CreateFrame("Frame", "OldRF_Container", UIParent)
    container:SetMovable(true)
    container:SetClampedToScreen(true)
    container:SetUserPlaced(false)
    container:SetFrameStrata("LOW")
    container:Show()

    -- plain gold group titles
    local function MakeTitle(text)
        local t = CreateFrame("Frame", nil, container)
        t.text = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t.text:SetPoint("CENTER", t, "CENTER", 0, 0)
        t.text:SetText(text)
        t.text:SetTextColor(1, 0.82, 0)
        t:Hide()
        return t
    end

    for g = 1, NUM_GROUPS do
        groupTitles[g] = MakeTitle((_G.GROUP or "Group") .. " " .. g)
    end
    titleMT   = MakeTitle(_G.MAIN_TANK or "Main Tank")
    titleMA   = MakeTitle(_G.MAIN_ASSIST or "Main Assist")
    titlePets = MakeTitle(_G.PETS or "Pets")
    titleParty = MakeTitle(_G.PARTY or "Party")

    -- per-group headers (grouped mode)
    -- oUF_ frame-name prefix: LibGetFrame (WeakAuras unit-frame anchoring)
    -- matches case-sensitive ^oUF_ patterns; OldRF_ globals kept as aliases
    for g = 1, NUM_GROUPS do
        local h = CreateHeader("oUF_OldRFRaidG" .. g, false, 0)
        h:SetAttribute("groupFilter", tostring(g))
        InstantiateChildren(h, MEMBERS_PER_GROUP, "unit")
        groupHeaders[g] = h
        _G["OldRF_HeaderG" .. g] = h
    end

    -- combined flow header ("Keep Groups Together" off)
    headerAll = CreateHeader("oUF_OldRFRaidAll", false, 0)
    headerAll:SetAttribute("unitsPerColumn", db.perColumn)
    headerAll:SetAttribute("maxColumns", math.ceil(MAX_RAID / math.max(1, db.perColumn)))
    headerAll:SetAttribute("columnSpacing", db.groupGap)
    headerAll:SetAttribute("columnAnchorPoint", "LEFT")
    headerAll:SetAttribute("groupBy", "GROUP")
    headerAll:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8")
    headerAll:SetAttribute("sortMethod", "INDEX")
    InstantiateChildren(headerAll, MAX_RAID, "unit")
    _G.OldRF_HeaderAll = headerAll

    -- Main Tank / Main Assist headers (secure role filters, stacked
    -- pullout-style target / ToT rows)
    headerMT = CreateHeader("oUF_OldRFRaidMT", false, TankExtraFor("mt"))
    headerMT:SetAttribute("groupFilter", "MAINTANK")
    InstantiateChildren(headerMT, MEMBERS_PER_GROUP, "mt")
    _G.OldRF_HeaderMT = headerMT

    headerMA = CreateHeader("oUF_OldRFRaidMA", false, TankExtraFor("ma"))
    headerMA:SetAttribute("groupFilter", "MAINASSIST")
    InstantiateChildren(headerMA, MEMBERS_PER_GROUP, "ma")
    _G.OldRF_HeaderMA = headerMA

    -- the 5-player party (never shown in a raid: showParty only)
    headerParty = CreateHeader("oUF_OldRFParty", false, 0, true)
    InstantiateChildren(headerParty, MEMBERS_PER_GROUP, "unit")
    _G.OldRF_HeaderParty = headerParty

    -- pet header
    headerPets = CreateHeader("oUF_OldRFRaidPets", true, 0)
    headerPets:SetAttribute("unitsPerColumn", MAX_PETS)
    headerPets:SetAttribute("maxColumns", 1)
    InstantiateChildren(headerPets, MAX_PETS, "pet")
    _G.OldRF_HeaderPets = headerPets

    -- Clique / click-cast addons: defensive re-registration in case another
    -- addon replaced the ClickCastFrames table before we ran
    _G.ClickCastFrames = _G.ClickCastFrames or {}
    for i = 1, #allButtons do
        _G.ClickCastFrames[allButtons[i]] = true
    end

    -- WeakAuras custom-anchor helper: OldRF_GetUnitFrame("raid7")
    _G.OldRF_GetUnitFrame = function(unit)
        local list = ButtonsForUnit(unit)
        if not list then return nil end
        for i = 1, #list do
            if list[i]:IsShown() then return list[i] end
        end
        return list[1]
    end

    -- LibHealPredict-1.0 (embedded; LibStub resolves the newest copy if other
    -- addons embed it too): incoming heal overlays derived locally from the
    -- native APIs, so no addon-message traffic and no dependency on what the
    -- rest of the raid is running
    -- (not on the modern clients: the library's tables are worked out from
    -- health, aura and combat-log values those clients hide; their overlay
    -- is the game's own incoming-heal number on a status bar instead)
    if LibStub and not MODERN then
        HealPredict = LibStub:GetLibrary("LibHealPredict-1.0", true)
    end
    if HealPredict then
        ApplyHealPredictSettings()
        local listener = {}
        local function SegmentsChanged(event, guid)
            local list = ButtonsForGUID(guid)
            if list then
                for j = 1, #list do
                    if list[j]:IsShown() then UpdateHealPrediction(list[j]) end
                end
            end
        end
        local function RosterChanged()
            -- units get reassigned under the buttons here, so refresh the
            -- guid map before drawing: UpdateHealPrediction reads btn.guid
            -- directly and would otherwise query the previous occupant
            unitMapDirty = true
            RebuildUnitMap()
            SweepHealPredictAuras()
            for i = 1, #allButtons do
                local btn = allButtons[i]
                if btn:IsShown() and btn.unit then UpdateHealPrediction(btn) end
            end
        end
        HealPredict.RegisterCallback(listener, "HealPredict_SegmentsChanged", SegmentsChanged)
        HealPredict.RegisterCallback(listener, "HealPredict_RosterChanged", RosterChanged)
    end

    DoApplyLayout()
    UpdateTitles()
    HookEditMode()

    -- unfiltered event registration: secure header children fire against
    -- their own tokens; RegisterUnitEvent would silently drop them
    local events = {
        "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD",
        "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
        "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEALTH_FREQUENT",
        "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
        "UNIT_NAME_UPDATE", "UNIT_AURA", "UNIT_CONNECTION", "UNIT_PET",
        "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_ROLES_ASSIGNED",
        "PARTY_LEADER_CHANGED", "PLAYER_TARGET_CHANGED",
        "READY_CHECK", "READY_CHECK_CONFIRM", "READY_CHECK_FINISHED",
        "INCOMING_RESURRECT_CHANGED", "UNIT_HEAL_PREDICTION",
    }
    for i = 1, #events do
        pcall(driver.RegisterEvent, driver, events[i])
    end

    -- 0.3s alpha-only range ticker (UnitInRange + UnitIsVisible tiebreaker)
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(0.3, function()
            if not db.rangeFade or not IsInGroup() then return end
            for i = 1, #allButtons do
                local btn = allButtons[i]
                if btn:IsShown() and btn.unit then
                    local a = 1
                    local me = UnitIsUnit(btn.unit, "player")
                    if Secret(me) then me = true end
                    if not me then
                        local inRange, checked = UnitInRange(btn.unit)
                        -- (the modern clients can hide the range: no fade on it)
                        if Secret(inRange) or Secret(checked) then
                            inRange, checked = true, true
                        end
                        if not checked then inRange = UnitIsVisible(btn.unit) end
                        if not inRange then a = RANGE_ALPHA end
                    end
                    if btn:GetAlpha() ~= a then btn:SetAlpha(a) end
                end
            end
        end)

        -- 0.5s aura countdown text ticker (built-in "small" cdText mode)
        C_Timer.NewTicker(0.5, function()
            if db.cdText ~= "small" then return end
            local now = GetTime()
            for i = 1, #allButtons do
                local btn = allButtons[i]
                if btn:IsShown() then
                    for j = 1, MAX_BUFFS do UpdateAuraTimer(btn.buffs[j], now) end
                    for j = 1, MAX_DEBUFFS do UpdateAuraTimer(btn.debuffs[j], now) end
                end
            end
        end)

        -- 0.25s MT/MA target / ToT ticker (the pullout's own cadence)
        C_Timer.NewTicker(TANK_TICK, function()
            if not db.displayTanks or not db.tankTarget or not IsInRaid() then return end
            for i = 1, #tankButtons do
                local btn = tankButtons[i]
                if btn:IsShown() and btn.unit then
                    UpdateTankTarget(btn)
                end
            end
        end)
    end

    -- (ZacUI) no "loaded" line: ZacUI says it once for all of its parts
end

--------------------------------------------------------------------------------
-- slash commands
--------------------------------------------------------------------------------

local function BoolWord(v) return v and "|cff00ff00on|r" or "|cffff0000off|r" end

local SLASH_TOGGLES = {
    blizzard   = { key = "hideBlizzard", label = "hide Blizzard raid frames" },
    grouped    = { key = "grouped",      label = "keep groups together" },
    tanks      = { key = "displayTanks", label = "main tank/assist frames" },
    tanktarget = { key = "tankTarget",   label = "tank target bars" },
    tanktot    = { key = "tankToT",      label = "main tank target-of-target" },
    pets       = { key = "displayPets",  label = "pet frames" },
    party      = { key = "showParty",    label = "party frames" },
    partyplayer = { key = "partyPlayer", label = "yourself among the party frames" },
    classcolor = { key = "classColor",   label = "class colors" },
    realm      = { key = "showRealm",    label = "realm names (Name-Realm)" },
    powerbars  = { key = "powerBars",    label = "power bars" },
    border     = { key = "border",       label = "border" },
    buffs      = { key = "showBuffs",    label = "buffs" },
    debuffs    = { key = "showDebuffs",  label = "debuffs" },
    dispelonly = { key = "dispelOnly",   label = "only dispellable debuffs" },
    aggro      = { key = "aggro",        label = "aggro highlight" },
    rangefade  = { key = "rangeFade",    label = "range fade" },
    auratooltips = { key = "auraTooltips", label = "aura tooltips" },
    auraswipe    = { key = "auraSwipe",    label = "aura duration spiral" },
    shields    = { key = "tankIcons",    label = "shield icons (assist/tank)" },
    crown      = { key = "leaderIcons",  label = "leader crown" },
    healpredict = { key = "healPredict", label = "heal prediction" },
    healhots    = { key = "healPredictHots", label = "heal prediction: HoT ticks" },
    healaoe     = { key = "healPredictAoE",  label = "heal prediction: group heals" },
}

-- (ZacUI) /orf is registered by ns.Start, only while these frames run
ns.Slash = function(msg)
    -- keep an un-lowercased copy: profile names are case-sensitive
    local raw = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local _, rawRest = raw:match("^(%S*)%s*(.-)$")
    msg = raw:lower()
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")

    if cmd == "" or cmd == "options" or cmd == "config" then
        ToggleOptionsPanel()
        return
    end

    if cmd == "profile" or cmd == "profiles" then
        if ns.Profiles then
            ns.Profiles.Slash(rawRest)
        else
            Print("the profile module did not load.")
        end
        return
    end

    local toggle = SLASH_TOGGLES[cmd]
    if toggle then
        ToggleOption(toggle.key)
        Print(toggle.label .. ": " .. BoolWord(db[toggle.key]))
        return
    end

    if cmd == "unlock" then
        SetLocked(false)
        Print("unlocked — drag to move, /orf lock when done.")
    elseif cmd == "lock" then
        SetLocked(true)
        Print("locked.")
    elseif cmd == "reset" then
        db.point, db.x, db.y = DEFAULTS.point, DEFAULTS.x, DEFAULTS.y
        QueueLayout()
        Print("position reset.")
    elseif cmd == "sort" then
        if rest == "group" or rest == "name" then
            SetOption("sortMode", rest)
            Print("sort (combined mode): " .. rest)
        else
            Print("usage: /orf sort group | name")
        end
    elseif cmd == "percolumn" then
        local n = tonumber(rest)
        if n and n >= 1 and n <= MAX_RAID then
            SetOption("perColumn", n)
            Print("combined mode units per column: " .. n)
        else
            Print("usage: /orf percolumn <1-40>  (default 5)")
        end
    elseif cmd == "bufffilter" then
        if rest == "mine" or rest == "all" then
            SetOption("buffFilter", rest)
            Print("buff filter: " .. rest)
        else
            Print("usage: /orf bufffilter mine | all")
        end
    elseif cmd == "rows" then
        local n = tonumber(rest)
        if n and n >= 1 and n <= 8 then
            SetOption("rows", n)
            Print("groups per column: " .. n)
        else
            Print("usage: /orf rows <1-8>  (2 = classic 4x2 grid)")
        end
    elseif cmd == "width" or cmd == "height" then
        local n = tonumber(rest)
        if n and n >= 20 and n <= 200 then
            SetOption(cmd, n)
            Print(cmd .. ": " .. n)
        else
            Print("usage: /orf " .. cmd .. " <20-200>  (defaults: 72x36)")
        end
    elseif cmd == "framegap" or cmd == "groupgap" then
        local n = tonumber(rest)
        if n and n >= 0 and n <= 20 then
            SetOption(cmd == "framegap" and "frameGap" or "groupGap", n)
            Print(cmd .. ": " .. n)
        else
            Print("usage: /orf " .. cmd .. " <0-20>  (defaults: 2 / 4)")
        end
    elseif cmd == "cdtext" then
        if rest == "off" or rest == "small" or rest == "omnicc" then
            SetOption("cdText", rest)
            Print("cooldown text: " .. (rest == "small" and "small (built-in, scales with icon)"
                or rest == "omnicc" and "OmniCC / external addon" or "off"))
        else
            Print("usage: /orf cdtext off | small | omnicc")
        end
    elseif cmd == "buffmode" or cmd == "debuffmode" then
        local key = (cmd == "buffmode") and "buffNameMode" or "debuffNameMode"
        local v = (rest == "hide") and "block" or rest
        if v == "off" or v == "block" or v == "only" then
            SetOption(key, v)
            Print(cmd .. ": " .. (v == "block" and "hide listed" or
                v == "only" and "only listed" or "off"))
        else
            Print("usage: /orf " .. cmd .. " off | hide | only")
        end
    elseif cmd == "buffname" or cmd == "debuffname" then
        if rest == "" then
            Print("usage: /orf " .. cmd .. " <exact spell name>  (toggles it on the list)")
        else
            ToggleAuraName(cmd == "buffname" and "buff" or "debuff", rest)
        end
    elseif cmd == "filters" then
        local function ListWords(t)
            local names = {}
            for k in pairs(t or {}) do names[#names + 1] = k end
            table.sort(names)
            return #names > 0 and table.concat(names, ", ") or "(empty)"
        end
        Print("buff name filter [" .. db.buffNameMode .. "]: " .. ListWords(db.buffNames))
        Print("debuff name filter [" .. db.debuffNameMode .. "]: " .. ListWords(db.debuffNames))
    elseif cmd == "filterclear" then
        if rest == "buffs" or rest == "all" then wipe(db.buffNames) end
        if rest == "debuffs" or rest == "all" then wipe(db.debuffNames) end
        if rest == "buffs" or rest == "debuffs" or rest == "all" then
            Print("cleared " .. rest .. " name list.")
            UpdateAllVisible()
            if RefreshOptionsPanel then RefreshOptionsPanel() end
        else
            Print("usage: /orf filterclear buffs | debuffs | all")
        end
    elseif cmd == "buffsize" or cmd == "debuffsize" then
        local key = (cmd == "buffsize") and "buffSize" or "debuffSize"
        if rest == "auto" or rest == "0" then
            SetOption(key, 0)
            Print(cmd .. ": auto (scales with frame size)")
        else
            local n = tonumber(rest)
            if n and n >= 5 and n <= 30 then
                SetOption(key, math.floor(n))
                Print(cmd .. ": " .. math.floor(n))
            else
                Print("usage: /orf " .. cmd .. " <5-30> | auto")
            end
        end
    elseif cmd == "healthtext" then
        if rest == "percent" or rest == "value" or rest == "lost" or rest == "none" then
            SetOption("healthText", rest)
            Print("health text: " .. rest
                .. (rest == "lost" and "  (missing hp, shown only when damaged)" or ""))
        else
            Print("usage: /orf healthtext percent | value | lost | none")
        end
    else
        Print("commands:  (or just /orf for the options panel)")
        Print("  /orf unlock | lock | reset")
        Print("  /orf blizzard | grouped | tanks | tanktarget | tanktot | pets")
        Print("  /orf party | partyplayer  - party frames / yourself among them")
        Print("  /orf classcolor | realm | powerbars | border | buffs | debuffs")
        Print("  /orf dispelonly | aggro | rangefade")
        Print("  /orf healpredict | healhots | healaoe  - incoming heal overlay")
        Print("  /orf sort group|name   /orf percolumn <n>   /orf bufffilter mine|all")
        Print("  /orf rows <1-8>   /orf width <n>   /orf height <n>")
        Print("  /orf framegap <n>   /orf groupgap <n>   - spacing between frames/groups")
        Print("  /orf buffsize <5-30|auto>   /orf debuffsize <5-30|auto>")
        Print("  /orf buffmode off|hide|only   /orf debuffmode off|hide|only  - name filters")
        Print("  /orf buffname <spell>   /orf debuffname <spell>  - toggle a name on its list")
        Print("  /orf filters   /orf filterclear buffs|debuffs|all")
        Print("  /orf auratooltips   /orf auraswipe   - aura hover tooltips / duration spiral")
        Print("  /orf cdtext off|small|omnicc  - countdown text (small = built-in, scaled)")
        Print("  /orf healthtext percent | value | lost | none  (lost = missing hp)")
        Print("  /orf profile  - profiles: share one layout across your characters,")
        Print("                  export/import strings, send to another player")
    end
end


--------------------------------------------------------------------------------
-- (ZacUI) THE START. Under Classic WoW UI the raid IS these frames (Zac,
-- 2026-11-10: "if users pick that style it uses those frames"): ZacUI's
-- own raid header is not made (Core.lua) and this file is started in its
-- place, with its settings in the unit frames' save (oldRaid), so they
-- travel in ZacUI's profiles. The OldRaidFrames addon itself, when it is
-- loaded, draws the raid and this copy stays asleep.
--   ns.Start(save, seed)  save: the settings table; seed: { point, x, y }
--                         for a save that has no spot yet
-- In ZacUI the party keeps ZacUI's own Classic party frames and ZacUI hides
-- Blizzard's frames, so both of those start off here.
--------------------------------------------------------------------------------
local EMBED_DEFAULTS = { hideBlizzard = false, showParty = false }

function ns.Standalone()
    local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if type(f) == "function" then
        local ok, loaded = pcall(f, "OldRaidFrames")
        if ok and loaded then return true end
    end
    return (not ns._slash and SlashCmdList and SlashCmdList.OLDRAIDFRAMES ~= nil) and true or false
end

function ns.Started() return ns._started == true end

function ns.Start(save, seed)
    if ns._started then return true end
    if type(save) ~= "table" or ns.Standalone() then return false end
    ns._started = true
    db = save
    if db.point == nil and type(seed) == "table" and seed.point then
        db.point, db.x, db.y = seed.point, seed.x or 0, seed.y or 0
    end
    for k, v in pairs(EMBED_DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    DeepFill(db, DEFAULTS)
    ns.MigrateProfile(db)
    driver.Setup()
    driver:RegisterEvent("ADDON_LOADED")      -- Blizzard_EditMode, loaded on demand
    SLASH_OLDRAIDFRAMES1 = "/orf"
    SLASH_OLDRAIDFRAMES2 = "/oldraidframes"
    SlashCmdList.OLDRAIDFRAMES = ns.Slash
    ns._slash = true
    -- ZacUI's own Edit Mode unlocks them like Blizzard's does
    local Z = _G.ZacUI
    if Z and Z.WatchEditMode then
        Z.WatchEditMode(function(on)
            if on then OnEditModeEnter() else OnEditModeExit() end
        end)
    end
    return true
end

-- Classic WoW UI on the unit frames, this session (latched with the look)
function UF.OldRaidActive()
    local K = UF.Kit
    if not (K and K.Active) then return false end
    local _, look = K.Active()
    return (look and look.id == "classic") and true or false
end

-- started where ZacUI's raid header would have been made; the first time,
-- the frames start in the corner ZacUI's raid has
function UF.OldRaidStart()
    local root = UF.db
    if type(root) ~= "table" then return false end
    if type(root.oldRaid) ~= "table" then root.oldRaid = {} end
    local seed
    local cfg = root.raid
    if root.oldRaid.point == nil and type(cfg) == "table" then
        local probe = CreateFrame("Frame", nil, UIParent)
        probe:SetSize(tonumber(cfg.width) or 70, tonumber(cfg.height) or 30)
        probe:SetPoint(cfg.point or "TOPLEFT", UIParent, cfg.point or "TOPLEFT", tonumber(cfg.x) or 0, tonumber(cfg.y) or 0)
        local l, t = probe:GetLeft(), probe:GetTop()
        local pl, pt = UIParent:GetLeft(), UIParent:GetTop()
        if l and t and pl and pt then
            seed = { point = "TOPLEFT", x = math.floor(l - pl + 0.5), y = math.floor(t - pt + 0.5) }
        end
        probe:Hide()
    end
    return ns.Start(root.oldRaid, seed)
end
