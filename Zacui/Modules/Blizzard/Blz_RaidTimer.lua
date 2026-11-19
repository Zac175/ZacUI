-- Blz_RaidTimer - a raid clear timer on the raid chat strip, with splits
-- compared to your best clear. Part of ZacUI; load order is set by the
-- TOC (after Blz_Chat, whose raid strip it sits on).
--
-- 2026-10-28, Zac: "in the chat somewhere can we somehow fit a raid timer
-- that compares splits to previous raids while the same raid config is
-- active". Picked: compare to the BEST run, on the tab strip's right side.
--
--   * A run starts at the first fight inside a raid instance and runs on
--     through reloads and relogs (time(), kept per character). It is over
--     at the raid's last boss, or after four hours without a kill.
--     "The first fight" is whichever of these comes first (2026-11-18,
--     Zac: "it needs to start on first combat or boss pull without a
--     logout at the start of the raid"):
--       - this character enters combat in the raid (PLAYER_REGEN_DISABLED)
--       - a boss is pulled (ENCOUNTER_START), whether or not this
--         character is in the fight - dead, or still running in
--       - this character arrives already fighting: logged in, reloaded or
--         zoned in while in combat, when the game sends no "entered
--         combat" of its own
--     and the clock is on the strip from that moment: while a run is
--     going in this raid the strip is asked every second, so a start the
--     strip could not show (not built yet, the chat peeked at) appears by
--     itself, with no reload or relog.
--   * A FIGHT WITH NO KILL IS NOT THE START (2026-11-18 23:25, Zac: "our
--     raid today was 39:34 and the timer said like 44 mins ... it counted
--     us being in combat before we actually started the raid we do a trash
--     skip to get to a certain position"). A run begun by entering combat
--     is PENDING: its clock shows, dimmed, and it becomes the run when an
--     enemy dies or a boss is pulled in that fight (the start stays the
--     moment the fight began). A fight that ends - for the whole raid, not
--     only for this character - with nothing killed takes its run away
--     again, and the next fight starts from 0:00. The combat log is only
--     listened to while a run is pending (through ns.CLEU, the one
--     combat log reader). chat.raidTimerStart = "combat" is the old rule:
--     the first time this character enters combat. A game version that
--     gives addons no combat log (WoW Forever) cannot see a kill, so it
--     keeps the old rule.
--   * Each boss kill (ENCOUNTER_END, success) is a split.
--   * Runs are compared within one RAID CONFIG: the instance plus the
--     Readycheck raid config active for it ("Naxxramas | Speed"). A
--     different config is a different race.
--   * Best = the fastest FULL clear (last boss killed) for that config.
--     Until there is one, the timer just counts.
--   * The strip shows "Faerlina -0:31  23:45" (last split's delta to the
--     best's same split, then the clock); hover lists every split; a
--     finished run shows its total. Shift-right-click forgets the best.
--   * Costs nothing outside a raid: a 1s ticker only while the strip is
--     up and a run is going.

local ADDON_NAME, ns = ...
local Chat = ns.Chat
local RM = Chat and Chat.RaidMode
if not RM then return end
local GetColor, Hex, Print = ns.GetColor, ns.Hex, ns.Print

local T = {}
RM.Timer = T

-- the raids' last bosses: their kill ends the run (Classic Era's; another
-- game version's are asked of Core_FlavorRaids, and a game whose raids are
-- not listed ends a run once the lockout says every boss is down)
local FINAL = {
    ["Ragnaros"] = true, ["Nefarian"] = true, ["Hakkar"] = true, ["C'Thun"] = true,
    ["Kel'Thuzad"] = true, ["Onyxia"] = true, ["Ossirian the Unscarred"] = true,
}
local STALE = 4 * 3600

local function Enabled()
    local c = ZacUIDB and ZacUIDB.chat
    return not (c and c.raidTimer == false)
end
local function Store()
    ZacUIDB.raidTimer = ZacUIDB.raidTimer or {}
    local s = ZacUIDB.raidTimer
    s.best = s.best or {}
    return s
end
local function Run()
    return type(ZacUICharDB) == "table" and ZacUICharDB.raidRun or nil
end

local function InstanceName()
    local inInst, kind = IsInInstance()
    if not (inInst and kind == "raid") then return nil end
    return (GetInstanceInfo())
end
-- the raid config Readycheck has active for this raid (its own raid name
-- when it is tracking one, else the instance's)
local function ConfigName(inst)
    local RC = _G.Readycheck
    local RR = RC and RC.RaidRoute
    local raid = (RR and RR.raidName) or inst
    if RC and RC.GetActiveRaidProfile and raid then
        local ok, _, name = pcall(RC.GetActiveRaidProfile, RC, raid)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return "Default"
end

-- the clock: "23:45" / "1:02:03" - or the chat's saved raid clock format
-- (chat.formats.raidClock, ZacUI's text format shape)
T.CLOCK_DEFAULTS = { time = "mmss" }
local function Clock(sec)
    local c = ZacUIDB and ZacUIDB.chat
    local spec = c and type(c.formats) == "table" and c.formats.raidClock
    if spec and ns.FormatTime then return ns.FormatTime(math.max(0, sec or 0), spec, T.CLOCK_DEFAULTS) end
    sec = math.max(0, math.floor((sec or 0) + 0.5))
    local h, m, s = math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end
T.Clock = Clock
local function Delta(d)
    if not d then return "" end
    local sign = d < 0 and "-" or "+"
    local c = GetColor("text", d < 0 and "green" or (d > 0 and "red" or "gray"))
    return "|cff" .. Hex(c) .. sign .. Clock(math.abs(d)) .. "|r"
end
local function Copy(t)
    local o = {}
    for k, v in pairs(t or {}) do o[k] = v end
    return o
end

-- when a run starts: "kill" (the first fight in which something dies, or
-- a boss pull) or "combat" (the first time this character enters combat)
-- (whether this game version lets an addon see a kill at all)
local function SeesKills()
    if _G.ZACUI_MODERN or (ns.NoCombatLog and ns.NoCombatLog()) then return false end
    return ns.CLEU ~= nil and type(ns.CLEU.On) == "function"
end
T.SeesKills = SeesKills
local function StartRule()
    local c = ZacUIDB and ZacUIDB.chat
    if c and c.raidTimerStart == "combat" then return "combat" end
    return SeesKills() and "kill" or "combat"
end
T.StartRule = StartRule

-- ---- the run
local function Start(inst)
    ZacUICharDB = ZacUICharDB or {}
    ZacUICharDB.raidRun = { inst = inst, key = inst .. " | " .. ConfigName(inst),
        start = time(), touched = time(), splits = {}, order = {} }
end
local function Finish(r)
    r.done = true
    r.total = r.splits[r.order[#r.order]] or (time() - r.start)
    local s = Store()
    local best = s.best[r.key]
    if not best or r.total < (best.total or math.huge) then
        r.wasBest = best and best.total or nil
        s.best[r.key] = { total = r.total, splits = Copy(r.splits), order = Copy(r.order), at = time() }
        r.newBest = true
        Print(string.format("raid timer: %s cleared in %s - a new best%s.", r.inst, Clock(r.total),
            r.wasBest and (" (" .. Delta(r.total - r.wasBest) .. ")") or ""))
    else
        Print(string.format("raid timer: %s cleared in %s (%s against your best).", r.inst, Clock(r.total),
            Delta(r.total - best.total)))
    end
end

-- ---- a pending run (see the head of this file)
local HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x00000040
local NPC = COMBATLOG_OBJECT_TYPE_NPC or 0x00000800
local band = bit and bit.band
local Watch
-- the fight had a kill, or a boss in it: the pending run is the run
local function Confirm(r)
    if not (r and r.pending) then return end
    r.pending = nil
    Watch(false)
    T.Paint()
end
T.Confirm = function() Confirm(Run()) end
-- one death out of the combat log (ns.CLEU hands over the event's values)
local function OnDeath(_, _, _, _, _, _, _, _, _, destFlags)
    local r = Run()
    if not (r and r.pending) then Watch(false) return end
    -- an enemy of the raid's, not a pet, a totem or a critter
    if type(destFlags) == "number" and band and band(destFlags, HOSTILE) ~= 0 and band(destFlags, NPC) ~= 0 then
        Confirm(r)
    end
end
Watch = function(on)
    if not SeesKills() then
        T.watching = false
        return
    end
    if on then ns.CLEU.On("RaidTimer.pending", "UNIT_DIED", OnDeath)
    else ns.CLEU.Off("RaidTimer.pending") end
    T.watching = on and true or false
end
-- anyone of the raid still fighting (asked when this character's own
-- combat ends, and every two seconds after that while the answer is yes)
local function GroupFighting()
    if UnitAffectingCombat("player") then return true end
    if not (IsInRaid and IsInRaid()) then return false end
    for i = 1, (GetNumGroupMembers and GetNumGroupMembers()) or 0 do
        if UnitAffectingCombat("raid" .. i) then return true end
    end
    return false
end
local checking = false
local function Settle()
    checking = false
    local r = Run()
    if not (r and r.pending) then return end
    if GroupFighting() then
        -- (this character is out of it - dead, or clear of the pack - and
        -- the fight goes on: it may still have its kill)
        if not UnitAffectingCombat("player") then
            checking = true
            C_Timer.After(2, Settle)
        end
        return
    end
    -- the fight is over and nothing died: that was not the start
    ZacUICharDB.raidRun = nil
    Watch(false)
    T.Paint()
end
T.Settle = Settle

-- A fight began: this character entered combat (sure = nil), or a boss was
-- pulled (sure = true).
function T.OnCombat(sure)
    if not Enabled() then return end
    local inst = InstanceName()
    if not inst then return end
    local r = Run()
    if r and r.pending then
        if r.inst == inst and T.watching then
            -- the pending fight goes on; a boss pulled in it settles it
            if sure then Confirm(r) end
            return
        end
        -- (a pending run nothing is listening for - left over from another
        -- raid or a session that ended mid-fight - was never the start)
        ZacUICharDB.raidRun = nil
        r = nil
    end
    -- a run in this raid (going, or cleared this session) holds
    if r and r.inst == inst and time() - (r.touched or r.start or 0) < STALE then return end
    Start(inst)
    if not sure and StartRule() == "kill" then
        Run().pending = true
        Watch(true)
    end
    T.Paint()
end
-- This character's own combat ended.
function T.OnCombatEnd()
    local r = Run()
    if r and r.pending and not checking then Settle() end
end

function T.OnKill(name, id)
    local r = Run()
    if not (r and not r.done and name) then return end
    if InstanceName() ~= r.inst or r.splits[name] then return end
    Confirm(r)        -- (a boss died in it: no fight is more certainly the raid's)
    r.splits[name] = time() - r.start
    r.order[#r.order + 1] = name
    r.touched = time()
    if FINAL[name] or (ns.RaidLastBoss and ns.RaidLastBoss(id, name)) then
        Finish(r)
    elseif ns.RaidEndsByLockout and ns.RaidEndsByLockout() then
        ns.WhenRaidCleared("RaidTimer", function()
            if Run() == r and not r.done then
                Finish(r)
                T.Paint()
            end
        end)
    end
    T.Paint()
end

-- ---- on the strip
local function Widget()
    local s = RM.strip
    if not s then return nil end
    if s.timer then return s.timer end
    local w = CreateFrame("Frame", nil, s)
    w:SetSize(220, RM.STRIP_H or 18)
    w:SetPoint("RIGHT", s.msgBtn, "LEFT", -8, 0)
    w:EnableMouse(true)
    w.text = w:CreateFontString(nil, "OVERLAY")
    if ns.HouseFont then ns.HouseFont(w.text, 10, nil, STANDARD_TEXT_FONT)
    else w.text:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE") end
    w.text:SetPoint("RIGHT", w, "RIGHT", 0, 0)
    w.text:SetJustifyH("RIGHT")
    w:SetScript("OnEnter", T.Tooltip)
    w:SetScript("OnLeave", function() GameTooltip:Hide() end)
    w:SetScript("OnMouseUp", function(_, button)
        local r = Run()
        if button == "RightButton" and IsShiftKeyDown() and r then
            Store().best[r.key] = nil
            Print("raid timer: best clear forgotten for " .. r.key .. ".")
            T.Paint()
        end
    end)
    w:Hide()
    s.timer = w
    return w
end

-- A run that is going, in the raid the player is standing in.
-- (only where this character uses the raid chat: there is no strip to wait
-- for otherwise)
local function GoingHere()
    local r = Run()
    return Enabled() and RM.Enabled() and r and not r.done and r.inst == InstanceName() or false
end
T.GoingHere = GoingHere

local ticker
local function Tick(on)
    if on and not ticker then
        ticker = C_Timer.NewTicker(1, function() T.Paint() end)
    elseif not on and ticker then
        ticker:Cancel()
        ticker = nil
    end
    T.ticking = ticker ~= nil
end

function T.Paint()
    local w = Widget()
    if not w then
        -- (no strip yet: a run that is going keeps asking for it)
        Tick(GoingHere())
        return
    end
    local r = Run()
    local show = Enabled() and RM.active and RM.kind ~= "party" and not RM.peek
        and r and r.inst == InstanceName()
    if not show then
        w:Hide()
        -- (hidden for now - the chat peeked at, the raid chat not up yet:
        -- a run that is going comes back by itself)
        Tick(GoingHere())
        return
    end
    local best = Store().best[r.key]
    local txt
    local normal = GetColor("text", "normal")
    if r.done then
        local gold = GetColor("text", "gold")
        txt = "|cff" .. Hex(gold) .. "Clear " .. Clock(r.total) .. "|r"
        if r.newBest and r.wasBest then txt = txt .. "  " .. Delta(r.total - r.wasBest)
        elseif not r.newBest and best then txt = txt .. "  " .. Delta(r.total - best.total) end
        Tick(false)
    else
        -- (a pending run's clock is dimmed: it may yet turn out not to be the start)
        local clock = "|cff" .. Hex(r.pending and GetColor("text", "gray") or normal) .. Clock(time() - r.start) .. "|r"
        local last = r.order[#r.order]
        if last then
            local gray = GetColor("text", "gray")
            local b = best and best.splits and best.splits[last]
            txt = "|cff" .. Hex(gray) .. last .. "|r " .. (b and Delta(r.splits[last] - b) or "") .. "   " .. clock
        else
            txt = clock
        end
        Tick(true)
    end
    w.text:SetText(txt)
    w:Show()
end

function T.Tooltip(w)
    local r = Run()
    if not r then return end
    local best = Store().best[r.key]
    GameTooltip:SetOwner(w, "ANCHOR_TOP")
    GameTooltip:AddLine("Raid timer", 1, 0.82, 0)
    GameTooltip:AddLine(r.key, 0.6, 0.6, 0.6)
    if r.pending then
        GameTooltip:AddLine("Counting from this fight's start. It becomes the run at the first kill or boss pull; "
            .. "a fight that ends with nothing killed does not start it.", 0.9, 0.9, 0.9, true)
    end
    if #r.order == 0 then
        GameTooltip:AddLine("No kills yet.", 0.9, 0.9, 0.9)
    end
    for _, name in ipairs(r.order) do
        local t = r.splits[name]
        local b = best and best.splits and best.splits[name]
        local right = Clock(t) .. (b and ("  " .. Delta(t - b)) or "")
        GameTooltip:AddDoubleLine(name, right, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9)
    end
    GameTooltip:AddLine(" ")
    if best then
        GameTooltip:AddDoubleLine("Best clear", Clock(best.total) .. "  (" .. date("%b %d", best.at or time()) .. ")",
            0.6, 0.6, 0.6, 1, 0.82, 0)
        -- the bosses the best run killed that this one has not yet
        local next
        for _, name in ipairs(best.order or {}) do
            if not r.splits[name] then next = name break end
        end
        if next and not r.done then
            GameTooltip:AddDoubleLine("Next on the best run", next .. " at " .. Clock(best.splits[next]),
                0.6, 0.6, 0.6, 0.9, 0.9, 0.9)
        end
    else
        GameTooltip:AddLine("No full clear with this raid config yet - the first one becomes the best.", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:AddLine("Shift-right-click: forget this config's best.", 0.45, 0.45, 0.45)
    GameTooltip:Show()
end

-- the strip is drawn again whenever the raid chat changes
if hooksecurefunc and type(RM.PaintStrip) == "function" then
    hooksecurefunc(RM, "PaintStrip", function() T.Paint() end)
end

-- Arrived (a login, a reload, a zone line): painted once the world has
-- settled; and a character that arrives already fighting starts the run,
-- since the game sends no "entered combat" for a fight that was going.
function T.OnArrive()
    local fighting = (UnitAffectingCombat and UnitAffectingCombat("player")) or (InCombatLockdown and InCombatLockdown())
    -- a pending run kept through a reload or a relog: its fight is still
    -- going (listen again), or it ended meanwhile (settle it)
    local r = Run()
    if r and r.pending then
        if fighting and r.inst == InstanceName() then Watch(true) else Settle() end
    end
    if InstanceName() and fighting then T.OnCombat() end
    T.Paint()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("ENCOUNTER_START")
ev:RegisterEvent("ENCOUNTER_END")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, event, id, name, _, _, success)
    if event == "PLAYER_REGEN_DISABLED" then T.OnCombat()
    elseif event == "ENCOUNTER_START" then T.OnCombat(true)
    elseif event == "PLAYER_REGEN_ENABLED" then T.OnCombatEnd()
    elseif event == "ENCOUNTER_END" then
        if success == 1 then T.OnKill(name, id) end
    else
        C_Timer.After(2, T.OnArrive)
    end
end)
