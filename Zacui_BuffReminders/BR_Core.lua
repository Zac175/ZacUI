-- BR_Core - the buff reminders' settings, who each buff reaches, and the
-- one scan every frame reads.
-- Part of ZacUI; load order is set by the TOC.
--
-- Two things on screen, the same pair Readycheck's Battle Shout reminder
-- always had, now for every class's group buffs (BR_Data):
--   the REMINDER (BR_Icon): an icon per buff that warns when you - or the
--     people the buff reaches - are missing it or it is about to run out;
--   the TRACKER (BR_Tracker): who is missing your buff or has it running
--     low, by raid group, the efficient cast pointed out (the group buff
--     when most of a group needs it, the single rank for one or two), the
--     reagent count, and a click on a row or group to cast it (out of
--     combat; secure buttons placed out of combat only).
--
-- PERFORMANCE. Nothing scans from an event. UNIT_AURA (yours only),
-- roster and zone news set a dirty flag and at most queue one re-check;
-- the scans run on tickers (1.5 s, Readycheck's own pace; the tracker's
-- bars move on a 0.25 s ticker that reads only what the scan stored) and
-- only while something is meant to be on screen.
--
-- SETTINGS: ZacUIDB.buffRem (the "buffRem" profile section)
--   enabled            nil / true = on; false = the whole part off
--   icon   = { the reminder icon's look: Readycheck's battleShoutReminder
--             fields - opacity, iconSize, borderSize, showMissingNames,
--             shortenNames, namesPosition, namesOffset, hideWhenAllBuffed,
--             playSound, soundKey, speak, visibilityMode, visibilityRaids,
--             countFont, namesFont, colors, showAnim, alertAnim, hideAnim,
--             + anchors, layout, visibility, chrome, framePos, sounds }
--   tracker = { Readycheck's battleShoutPartyTracker fields - scale,
--             opacity, width, rowHeight, showBackground, showHeader,
--             durationStyle, barMaxDuration, barAlpha, borderSize,
--             showOnlyMissing, rangeCheck, showBloodrage, bloodrageStyle,
--             visibilityMode, visibilityRaids, rowFont, titleFont, colors,
--             showAnim, hideAnim + clickCast, groupAt, reagentLow,
--             reagentWarn + anchors, layout, formats, visibility, chrome,
--             framePos }
--   buffs = { [key] = { enabled, tracker, scope, threshold, rangeCheck,
--             greedMode, greedSkipIfImpCleave, showAPValue, targets } }
-- enabled / tracker per buff are nil until picked: nil means "on for your
-- class" - except Battle Shout while Readycheck's own Battle Shout
-- reminder (or its party tracker) is on, which leaves ZacUI's off so the
-- two never both warn. The page offers to switch Readycheck's off.
-- Positions are ZacUI movers (ZacUIDB.movers.buffRemIcon / buffRemTracker).

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local D = ns.BuffRemData
if not D then return end

local BR = {}
ns.BuffRem = BR
BR.Data = D

local math_floor, math_max, math_abs = math.floor, math.max, math.abs

-- ============================================================
-- SETTINGS
-- ============================================================
-- Every value is what Readycheck's Battle Shout reminder shipped with;
-- the colours are its theme's defaults.
local function C(r, g, b, a) return { r = r, g = g, b = b, a = a } end
BR.DEFAULTS = {
    icon = {
        opacity = 0.7, iconSize = 40, borderSize = 1,
        showMissingNames = false, shortenNames = false, namesPosition = "right", namesOffset = 5,
        hideWhenAllBuffed = true,
        playSound = false, soundKey = "WR: Warning", speak = false,
        visibilityMode = "raids",
        countFont = { size = 16, outline = "OUTLINE", shadow = true },
        namesFont = { size = 12, outline = "OUTLINE", shadow = true },
        colors = {
            background = C(0.08, 0.08, 0.08, 0.9),
            normalBorder = C(0, 0, 0, 1),
            missingBorder = C(1, 0.3, 0.3, 1),
            missingText = C(1, 0.3, 0.3, 1),
            allBuffedText = C(0.3, 1, 0.3, 1),
        },
    },
    tracker = {
        scale = 1.0, opacity = 0.85, width = 165, rowHeight = 17,
        showBackground = true, showHeader = true,
        durationStyle = "bar", barMaxDuration = 120, barAlpha = 0.45, borderSize = 1,
        showOnlyMissing = false, rangeCheck = false,
        showBloodrage = true, bloodrageStyle = "both",
        visibilityMode = "raids",
        clickCast = true, groupAt = 3, reagentLow = 20, reagentWarn = true,
        rowFont = { size = 11, outline = "OUTLINE", shadow = true },
        titleFont = { size = 11, outline = "OUTLINE", shadow = true },
        colors = {
            background = C(0.06, 0.06, 0.06, 0.95),
            border = C(0, 0, 0, 1),
            headerBackground = C(0.10, 0.10, 0.10, 1),
            rowBackground = C(1, 1, 1, 0.03),
            apGood = C(0.3, 1, 0.3, 1),
            apWarning = C(1, 0.8, 0.1, 1),
            apMissing = C(1, 0.3, 0.3, 1),
            bloodrageActive = C(1, 0.25, 0.25, 1),
        },
    },
}
-- per buff (read through BR.Opt; nothing is written until picked)
BR.BUFF_DEFAULTS = {
    scope = "group", rangeCheck = false,
    greedMode = false, greedSkipIfImpCleave = false, showAPValue = false,
    -- Battle Shout only: shown in the warrior HUD's buff row instead of
    -- its own icon (when the HUD and its buff row are on)
    hudDock = false,
}

local function DB()
    if type(ZacUIDB) ~= "table" then return nil end
    if type(ZacUIDB.buffRem) ~= "table" then ZacUIDB.buffRem = {} end
    return ZacUIDB.buffRem
end
-- (filled once per table: a profile worn or a reset hands over new ones)
local filledIcon, filledTracker
function BR.Cfg()
    local c = DB()
    if not c then return nil end
    if type(c.icon) ~= "table" then c.icon = {} end
    if type(c.tracker) ~= "table" then c.tracker = {} end
    if ns.FillDefaults then
        if filledIcon ~= c.icon then ns.FillDefaults(c.icon, BR.DEFAULTS.icon) filledIcon = c.icon end
        if filledTracker ~= c.tracker then ns.FillDefaults(c.tracker, BR.DEFAULTS.tracker) filledTracker = c.tracker end
    end
    return c
end
local EMPTY = {}
function BR.Icon() local c = BR.Cfg() return c and c.icon or BR.DEFAULTS.icon end
function BR.Tracker() local c = BR.Cfg() return c and c.tracker or BR.DEFAULTS.tracker end
function BR.On()
    local c = DB()
    return not (c and c.enabled == false)
end

-- a buff's own option: saved, else the buff's default, else the shared one
function BR.Opt(key, field)
    local c = DB()
    local b = c and type(c.buffs) == "table" and c.buffs[key]
    if type(b) == "table" and b[field] ~= nil then return b[field] end
    local def = D.BY_KEY[key]
    if field == "threshold" then return def and def.threshold or 0 end
    if field == "targets" then return EMPTY end
    return BR.BUFF_DEFAULTS[field]
end
function BR.SetOpt(key, field, v)
    local c = DB()
    if not c then return end
    if type(c.buffs) ~= "table" then c.buffs = {} end
    if type(c.buffs[key]) ~= "table" then c.buffs[key] = {} end
    c.buffs[key][field] = v
end

-- the colour a key stands for (saved, else Readycheck's default)
function BR.Color(sec, key)
    local t = (sec == "icon") and BR.Icon() or BR.Tracker()
    local c = type(t.colors) == "table" and t.colors[key]
    if type(c) == "table" then return c end
    local d = BR.DEFAULTS[sec].colors[key]
    return d or C(1, 1, 1, 1)
end

-- ============================================================
-- READYCHECK (read only, defensively)
-- ============================================================
-- Readycheck's live settings for this character: its battleShoutReminder
-- and battleShoutPartyTracker tables, or nil.
function BR.ReadycheckTables()
    local RC = rawget(_G, "Readycheck")
    if type(RC) ~= "table" then return nil end
    local db = rawget(RC, "db")
    if type(db) ~= "table" then return nil end
    local a, b = db.battleShoutReminder, db.battleShoutPartyTracker
    return RC, (type(a) == "table") and a or nil, (type(b) == "table") and b or nil, db
end
-- is Readycheck's own Battle Shout reminder / party tracker on?
function BR.ReadycheckOn()
    local _, a, b = BR.ReadycheckTables()
    return (a and a.enabled == true) or false, (b and b.enabled == true) or false
end

-- ============================================================
-- WHO I AM, WHAT I KNOW
-- ============================================================
function BR.PlayerClass()
    local _, cls = UnitClass("player")
    return cls
end

-- does the player give this buff? Battle Shout keeps Readycheck's rule
-- (a warrior, or a class not known yet); the others want a rank known.
function BR.Gives(def)
    local cls = BR.PlayerClass()
    if def.port then return cls == nil or cls == def.class end
    if cls ~= def.class then return false end
    if def.item then return true end
    local known = IsPlayerSpell or IsSpellKnown
    if not known then return true end
    for _, id in ipairs(def.ids) do
        if known(id) then return true end
    end
    return false
end

-- the buffs this character gives, in order
function BR.MyBuffs()
    local out = {}
    for _, def in ipairs(D.BUFFS) do
        if BR.Gives(def) then out[#out + 1] = def end
    end
    return out
end

-- the reminder / the tracker for one buff on? nil saved = on for your
-- class (the buff's own default), Battle Shout off while Readycheck's is
local function SavedFlag(key, field)
    local c = DB()
    local b = c and type(c.buffs) == "table" and c.buffs[key]
    if type(b) == "table" then return b[field] end
    return nil
end
function BR.ReminderOn(key)
    local v = SavedFlag(key, "enabled")
    if v ~= nil then return v and true or false end
    local def = D.BY_KEY[key]
    if not def or not def.on then return false end
    if key == "battleshout" then
        local rcIcon = BR.ReadycheckOn()
        if rcIcon then return false end
    end
    return true
end
function BR.TrackerOn(key)
    local v = SavedFlag(key, "tracker")
    if v ~= nil then return v and true or false end
    local def = D.BY_KEY[key]
    if not def or not def.on then return false end
    if key == "battleshout" then
        local _, rcTracker = BR.ReadycheckOn()
        if rcTracker then return false end
    end
    return true
end

-- spell names: any rank's (they share one) and the group version's
local nameCache = {}
local function SpellName(id)
    if not (GetSpellInfo and id) then return nil end
    return GetSpellInfo(id)
end
BR.SpellName = SpellName
function BR.SingleName(def)
    return SpellName(def.ids[#def.ids]) or SpellName(def.ids[1]) or def.label
end
-- the group version, when a rank of it is known: name, rank index
function BR.GroupKnown(def)
    local g = def.group
    if not g then return nil end
    local known = IsPlayerSpell or IsSpellKnown
    local best
    for i, id in ipairs(g.ids) do
        if (not known) or known(id) then best = i end
    end
    if not best then return nil end
    return SpellName(g.ids[best]) or g.label, best
end
-- the reagent the best known group rank takes, and how many are in the bags
function BR.Reagent(def)
    local g = def.group
    if not (g and g.reagents) then return nil end
    local _, rank = BR.GroupKnown(def)
    local id = g.reagents[rank or #g.reagents] or g.reagents[#g.reagents]
    local n = (GetItemCount and GetItemCount(id)) or 0
    return id, n, D.REAGENTS[id] or ("Item " .. id)
end
-- a Soulstone in the bags: its item id, best first
function BR.ItemInBags(def)
    if not def.item then return nil end
    for i = #def.item, 1, -1 do
        local id = def.item[i]
        if GetItemCount and GetItemCount(id) > 0 then return id end
    end
    return nil
end
function BR.Icon_(def)
    local tex
    if GetSpellInfo then
        local _, _, t = GetSpellInfo(def.ids[#def.ids])
        tex = t
    end
    return tex or def.icon
end

-- every name the buff goes by on a unit
function BR.BuffNames(def)
    local set = nameCache[def.key]
    if set then return set end
    set = {}
    for _, id in ipairs(def.ids) do local n = SpellName(id) if n then set[n] = true end end
    if def.group then for _, id in ipairs(def.group.ids) do local n = SpellName(id) if n then set[n] = true end end end
    for _, n in ipairs(D.ENGLISH[def.key] or {}) do set[n] = true end
    nameCache[def.key] = set
    return set
end

-- ============================================================
-- VISIBILITY - Readycheck's "Show in" rule, for each frame
-- ============================================================
--   raids       inside a raid instance (the raid filter narrows it)
--   instances   inside a dungeon or a raid (the filter: raids only)
--   group       in any party or raid, anywhere
--   always      in a group, or inside a raid instance
--   everywhere  solo too
local function HasFilter(set)
    if type(set) ~= "table" then return false end
    for _, v in pairs(set) do if v then return true end end
    return false
end
function BR.InRaidInstance(filter)
    if not IsInInstance then return false end
    local inside, kind = IsInInstance()
    if not (inside and kind == "raid") then return false end
    if HasFilter(filter) then
        local name = GetInstanceInfo and GetInstanceInfo() or nil
        return (name and filter[name]) and true or false
    end
    return true
end
function BR.InDungeonOrRaid(filter)
    if not IsInInstance then return false end
    local inside, kind = IsInInstance()
    if not inside then return false end
    if kind == "party" then return true end
    if kind == "raid" then return BR.InRaidInstance(filter) end
    return false
end
function BR.ShowIn(sec)
    local mode = sec.visibilityMode or "raids"
    local inGroup = IsInGroup and IsInGroup() or false
    if mode == "raids" then return BR.InRaidInstance(sec.visibilityRaids) end
    if mode == "instances" then return BR.InDungeonOrRaid(sec.visibilityRaids) end
    if mode == "group" then return inGroup end
    if mode == "always" then return inGroup or BR.InRaidInstance(sec.visibilityRaids) end
    if mode == "everywhere" then return true end
    return false
end
-- the movers are up (Edit Mode / the page's "move" button): show the
-- frames with sample content so they can be placed
function BR.Placing(key)
    return ns.IsMoverShown and ns.IsMoverShown(key) or false
end

-- ============================================================
-- AURAS ON A UNIT
-- ============================================================
-- Battle Shout's attack power, as its tooltip words it (Readycheck's
-- parse). A fractional figure is tried first: "(%d+)" alone reads
-- "327.5" as 327.
local AP_PHRASES = { "melee attack power by ", "[Aa]ttack power increased by ", "[Aa]ttack power by " }
local function ParseAP(txt)
    for _, phrase in ipairs(AP_PHRASES) do
        local v = txt:match(phrase .. "(%d+%.%d+)") or txt:match(phrase .. "(%d+)")
        if v then return tonumber(v) end
    end
end
BR.ParseAP = ParseAP
-- value1 and the tooltip can disagree by the fraction (the 3-piece Wrath
-- bonus with 5/5 Improved Battle Shout is 327.5): within 1 the tooltip is
-- the same shout better rounded and wins.
local function ResolveShoutAP(value1, tipAP)
    local v = (value1 and value1 > 0) and value1 or nil
    local t = (tipAP and tipAP > 0) and tipAP or nil
    local ap = v or t or 0
    if v and t and math_abs(t - v) <= 1 then ap = t end
    return math_floor(ap + 0.5)
end
BR.ResolveShoutAP = ResolveShoutAP

local scanTip
local function ScanTip()
    if scanTip then return scanTip end
    scanTip = CreateFrame("GameTooltip", "ZacUIBuffRemScanTip", nil, "GameTooltipTemplate")
    if scanTip.SetOwner then scanTip:SetOwner(WorldFrame or UIParent, "ANCHOR_NONE") end
    return scanTip
end
local apTipCache = {}
local AP_CACHE_TTL = 5
local function APFromTooltip(unit, index, exp)
    local c = apTipCache[unit]
    if c then
        if exp and exp > 0 then
            if c.exp == exp then return c.ap end
        elseif (GetTime() - c.t) < AP_CACHE_TTL then
            return c.ap
        end
    end
    local tt = ScanTip()
    local ap = 0
    if tt.SetUnitBuff then
        if tt.SetOwner then tt:SetOwner(WorldFrame or UIParent, "ANCHOR_NONE") end
        if tt.ClearLines then tt:ClearLines() end
        tt:SetUnitBuff(unit, index)
        local n = tt:GetName()
        local lines = (tt.NumLines and tt:NumLines()) or 0
        for j = 2, lines do
            local line = _G[n .. "TextLeft" .. j]
            local txt = line and line.GetText and line:GetText()
            if txt then
                local v = ParseAP(txt)
                if v then ap = v break end
            end
        end
    end
    apTipCache[unit] = { ap = ap, exp = exp or 0, t = GetTime() }
    return ap
end
local apByName = {}
BR._apByName = apByName

-- One look at a unit answers for every buff this character gives: inside
-- a scan pass (BR.BeginPass / EndPass, round each frame's update) a unit's
-- buffs are read once and kept until the pass ends, so a priest's three
-- buffs and the reminder's and tracker's questions cost one UnitBuff loop
-- per unit, not one per buff. Outside a pass nothing is kept.
local pass = nil                -- { [unit] = { [key] = { has, rem, ap, exp } | false } }
function BR.BeginPass() pass = {} end
function BR.EndPass() pass = nil end
-- fn inside one pass (closed again even if fn fails)
function BR.InPass(fn)
    pass = {}
    local ok, r = pcall(fn)
    pass = nil
    if not ok then error(r, 0) end
    return r
end

local function Answer(unit, def, i, name, exp, value1)
    local remaining = 0
    if exp and exp > 0 then remaining = math_max(0, exp - GetTime()) end
    local ap = 0
    if def.port then
        -- resolved once per shout per player (by name: raid tokens move)
        local uName = UnitName(unit) or unit
        local c = apByName[uName]
        if c and c.exp == exp and c.v1 == value1 and c.ap then
            ap = c.ap
        else
            ap = ResolveShoutAP(value1, APFromTooltip(unit, i, exp))
            apByName[uName] = { exp = exp, v1 = value1, ap = ap }
        end
    elseif not (exp and exp > 0) then
        -- an aura with no end (Trueshot on the hunter's party)
        remaining = math.huge
    end
    return remaining, ap
end

-- has, seconds left, AP (Battle Shout only), expiration time
function BR.UnitBuffStatus(unit, def)
    if not UnitExists(unit) then return false, 0, 0, 0 end
    local fn = _G.UnitBuff
    if not fn then return false, 0, 0, 0 end
    if pass then
        local seen = pass[unit]
        if not seen then
            -- every buff of mine on this unit, in one loop
            seen = {}
            local defs = BR.MyBuffs()
            local hasThis = false
            for _, d in ipairs(defs) do if d == def then hasThis = true end end
            if not hasThis then defs = { def } end
            for i = 1, 40 do
                local name, _, _, _, _, exp, _, _, _, _, _, _, _, _, _, value1 = fn(unit, i)
                if not name then break end
                for _, d in ipairs(defs) do
                    if seen[d.key] == nil and BR.BuffNames(d)[name] then
                        local rem, ap = Answer(unit, d, i, name, exp, value1)
                        seen[d.key] = { rem, ap, exp or 0 }
                    end
                end
            end
            pass[unit] = seen
        end
        local r = seen[def.key]
        if r == nil and not BR.PassHas(seen, def) then
            -- a buff the loop did not look for (not one of mine)
            pass[unit] = nil
            local saved = pass
            pass = nil
            local a, b, c, d = BR.UnitBuffStatus(unit, def)
            pass = saved
            return a, b, c, d
        end
        if r then return true, r[1], r[2], r[3] end
        return false, 0, 0, 0
    end
    local names = BR.BuffNames(def)
    for i = 1, 40 do
        local name, _, _, _, _, exp, _, _, _, _, _, _, _, _, _, value1 = fn(unit, i)
        if not name then break end
        if names[name] then
            local rem, ap = Answer(unit, def, i, name, exp, value1)
            return true, rem, ap, (exp or 0)
        end
    end
    return false, 0, 0, 0
end
-- was this buff among those the pass's loop looked for?
function BR.PassHas(seen, def)
    for _, d in ipairs(BR.MyBuffs()) do if d == def then return true end end
    return false
end

local BLOODRAGE = { ["Bloodrage"] = true }
function BR.UnitHasBloodrage(unit)
    if not UnitExists(unit) then return false end
    local fn = _G.UnitBuff
    if not fn then return false end
    if GetSpellInfo then local n = GetSpellInfo(2687) if n then BLOODRAGE[n] = true end end
    for i = 1, 40 do
        local name = fn(unit, i)
        if not name then break end
        if BLOODRAGE[name] then return true end
    end
    return false
end

-- ============================================================
-- WHO A BUFF REACHES
-- ============================================================
BR.PARTY_UNITS = { "player", "party1", "party2", "party3", "party4" }

-- the raid's main tanks (the tank list for Thorns)
local function IsTank(unit)
    if GetPartyAssignment then
        local ok, mt = pcall(GetPartyAssignment, "MAINTANK", unit)
        if ok and mt then return true end
    end
    return false
end

local function Listed(def, unit)
    local name = UnitName(unit)
    if not name then return false end
    local list = BR.Opt(def.key, "targets")
    if type(list) == "table" then
        for _, n in ipairs(list) do if n == name then return true end end
    end
    if def.tanks and IsTank(unit) then return true end
    return false
end
BR.Listed = Listed

-- the units one buff can reach (out: reused array), for a scope:
--   "self"  the player only;  else the buff's reach
function BR.ReachUnits(def, scope, out)
    out = out or {}
    for i = #out, 1, -1 do out[i] = nil end
    if scope == "self" then out[1] = "player" return out end
    local inGroup = (IsInRaid and IsInRaid()) or (IsInGroup and IsInGroup())
    if def.reach == "party" then
        if inGroup then
            for _, u in ipairs(BR.PARTY_UNITS) do out[#out + 1] = u end
        else
            out[1] = "player"
        end
        return out
    end
    local list
    if ns.Roster and ns.Roster.Units then list = ns.Roster.Units() end
    if not list or #list == 0 then list = inGroup and BR.PARTY_UNITS or { "player" } end
    for _, u in ipairs(list) do
        if def.reach ~= "chosen" or Listed(def, u) then out[#out + 1] = u end
    end
    return out
end

-- the buff matters to this unit's class
function BR.Wants(def, unit)
    if not def.classes then return true end
    local _, cls = UnitClass(unit)
    return def.classes[cls] or false
end

-- the raid subgroup a unit is in (1 outside a raid)
function BR.Subgroup(unit)
    if not (IsInRaid and IsInRaid()) then return 1 end
    local i = unit and tonumber(unit:match("^raid(%d+)$"))
    if i and GetRaidRosterInfo then
        local _, _, sub = GetRaidRosterInfo(i)
        return tonumber(sub) or 1
    end
    if unit == "player" and UnitInRaid and GetRaidRosterInfo then
        local idx = UnitInRaid("player")
        if idx then
            local _, _, sub = GetRaidRosterInfo(idx + 1)
            return tonumber(sub) or 1
        end
    end
    return 1
end

-- in reach of a spell: 1 / 0 from the spell, else the group range check
function BR.InSpellRange(spell, unit)
    if unit == "player" then return true, true end
    if IsSpellInRange and spell then
        local r = IsSpellInRange(spell, unit)
        if r == 1 then return true, true end
        if r == 0 then return false, true end
    end
    if UnitInRange then
        local inR, checked = UnitInRange(unit)
        if checked then return inR and true or false, true end
    end
    return true, false
end

-- ============================================================
-- THE REMINDER'S SCAN (Readycheck's ScanBattleShoutStatus, for any buff)
-- ============================================================
-- missing, total, lowestRemaining, belowThreshold (0/1), lowestAP,
-- hasWeakShout, names, outOfRange
local WEAK_SHOUT_THRESHOLD = 290       -- below a max-rank, un-talented shout
local reachTmp = {}
function BR.ScanReminder(def)
    local ic = BR.Icon()
    local missing, total, outOfRange = 0, 0, 0
    local lowest, lowestAP, weak = 999999, 999999, false
    local threshold = BR.Opt(def.key, "threshold") or 0
    local wantNames, shorten = ic.showMissingNames, ic.shortenNames
    local doRange = BR.Opt(def.key, "rangeCheck")
    local missingNames, lowNames = {}, {}
    local selfOnly = BR.Opt(def.key, "scope") == "self"
    local single = BR.SingleName(def)
    local units = BR.ReachUnits(def, selfOnly and "self" or "group", reachTmp)
    for _, unit in ipairs(units) do
        if UnitExists(unit) and UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) and BR.Wants(def, unit) then
            total = total + 1
            local skip = false
            if doRange and unit ~= "player" then
                local inR, checked
                if def.port and UnitInRange then inR, checked = UnitInRange(unit)
                else inR, checked = BR.InSpellRange(single, unit) end
                if checked and not inR then
                    outOfRange = outOfRange + 1
                    if wantNames then
                        local n = UnitName(unit)
                        if shorten and n then n = string.sub(n, 1, 3) end
                        missingNames[#missingNames + 1] = "~" .. (n or "?")
                    end
                    skip = true
                end
            end
            if not skip then
                local has, rem, ap = BR.UnitBuffStatus(unit, def)
                if not has then
                    missing = missing + 1
                    if wantNames then
                        local n = UnitName(unit)
                        if shorten and n then n = string.sub(n, 1, 3) end
                        missingNames[#missingNames + 1] = n
                    end
                else
                    if rem < lowest then lowest = rem end
                    if def.port then
                        if ap > 0 and ap < lowestAP then lowestAP = ap end
                        if ap > 0 and ap < WEAK_SHOUT_THRESHOLD then weak = true end
                    end
                    if wantNames and threshold > 0 and rem <= threshold then
                        local n = UnitName(unit)
                        if shorten and n then n = string.sub(n, 1, 3) end
                        lowNames[#lowNames + 1] = n
                    end
                end
            end
        end
    end
    local below = 0
    if threshold > 0 and lowest <= threshold and lowest < 999999 then below = 1 end
    if lowestAP == 999999 then lowestAP = 0 end
    local all = {}
    for _, n in ipairs(missingNames) do all[#all + 1] = n end
    for _, n in ipairs(lowNames) do all[#all + 1] = n end
    return missing, total, lowest, below, lowestAP, weak, all, outOfRange
end

-- ============================================================
-- DRIVING IT
-- ============================================================
-- One dirty flag; BR.Kick() queues one re-check (0.3 s, a burst of
-- roster / zone news collapses into it; after a loading screen once more
-- a second later, as Readycheck does).
local listeners = {}
function BR.OnRefresh(key, fn) listeners[key] = fn end
BR.dirty = true
local queued, settle = false, false
local function RunAll()
    for _, fn in pairs(listeners) do
        local ok, err = pcall(fn)
        if not ok and ns.DebugPrint then pcall(ns.DebugPrint, "buff reminders: " .. tostring(err), "buffrem") end
    end
end
BR.RunAll = RunAll
function BR.Kick(settleToo)
    BR.dirty = true
    if settleToo then settle = true end
    if queued then return end
    queued = true
    C_Timer.After(0.3, function()
        queued = false
        RunAll()
        if settle then
            settle = false
            C_Timer.After(1.0, RunAll)
        end
    end)
end

-- a ticker, tracked by the profiler
function BR.NewTicker(name, interval, fn)
    local t = C_Timer.NewTicker(interval, fn)
    if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(t, name) end
    return t
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "UNIT_AURA", "SPELLS_CHANGED", "BAG_UPDATE" }) do
    pcall(ev.RegisterEvent, ev, e)
end
BR.combat = false
BR.regenHooks = {}
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "UNIT_AURA" then
        -- yours only (the reminder's "only me" and your own icon); the
        -- group is read by the tickers
        if arg1 == "player" then BR.dirty = true end
        return
    end
    if event == "BAG_UPDATE" then
        -- the reagent count is read by the tracker's scan
        BR.bagsDirty = true
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        -- (before the lockdown starts: the click layer can still be put away)
        BR.combat = true
        for _, fn in pairs(BR.regenHooks) do pcall(fn, true) end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        BR.combat = false
        for _, fn in pairs(BR.regenHooks) do pcall(fn, false) end
    end
    if event == "SPELLS_CHANGED" then
        for k in pairs(nameCache) do nameCache[k] = nil end
    end
    BR.Kick(event == "PLAYER_ENTERING_WORLD")
end)
if ns.Roster and ns.Roster.On then ns.Roster.On("buffRem", function() BR.Kick() end) end

-- the page's changes reach the live frames on the next frame
if ns.OnSettingsChanged and ns.Coalesce then
    local soon = ns.Coalesce(function()
        if BR.Restyle then BR.Restyle() end
        RunAll()
    end)
    ns.OnSettingsChanged(function()
        local P = ns.ConfigPreview
        local cur = P and P.Current and P.Current()
        if type(cur) == "string" and cur:find("^buffrem") then soon() end
    end)
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    C_Timer.After(1, function() BR.Kick(true) end)
end)
