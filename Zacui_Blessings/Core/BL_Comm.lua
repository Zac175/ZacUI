-- BL_Comm - the paladin channel. Reads and writes the "PLPWR" addon
-- messages that PallyPower speaks, so ZacUI and PallyPower paladins in
-- one group share one set of assignments. Written from the message
-- shapes alone; the model it fills is ZacUI's own (BL.pallys).
-- Part of ZacUI; load order is set by the TOC.
--
-- THE MESSAGES (one line each, group channel unless whispered back):
--   REQ                         "tell me about yourselves"
--   PPLEADER <name>             I lead / assist the group
--   SELF <ranks>@<assign>       a paladin's blessing ranks + talents (6 x
--                               two hex digits, "nn" = unknown) and its
--                               nine class assignments (one digit each,
--                               "n" = none)
--   ASELF <ranks>@<aura>        the same for its 7 auras, and its aura
--   NASSIGN p c t b@p c t b...  per-player blessings (paladin, class slot,
--                               target name, blessing; 0 = cleared)
--   ASSIGN <name> <slot> <b>    one class assignment
--   PASSIGN <name>@<assign>     all nine at once
--   MASSIGN <name> <b>          every class the same blessing
--   AASSIGN <name> <aura>       an aura
--   CLEAR [SKIP]                leader wipes (SKIP: keep the auras)
--   FREEASSIGN YES|NO | SYMCOUNT n | COOLDOWNS:d:r:d:r
--                               may others set my blessings, my Symbols
--                               of Kings, my Lay on Hands / Divine
--                               Intervention cooldowns ("n" = unknown)
-- Someone may set another paladin's assignments only as the group's
-- leader or an assistant, or when that paladin allows it (free assign).

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local D = ns.BlessingsData
local BL = ns.Blessings
if not (D and BL) then return end

local Comm = {}
BL.Comm = Comm

local strfind, strsub, strsplit, format = string.find, string.sub, strsplit, string.format
local SendAddon = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage

local Short = ns.ShortName

-- ============================================================
-- SENDING - a small queue, so a burst (SELF, ASELF, NASSIGN...) never
-- trips the client's throttle; the same line twice in a row is sent once
-- ============================================================
local queue, lastSent = {}, nil
local pump

local Channel = ns.GroupChannel

local held = false      -- something was not sent inside an instance (Forever)
local function Pump()
    -- WoW Forever delivers no addon messages inside an instance: the queue
    -- goes, and once you are out everyone is asked and told again
    -- (Comm.Start's PLAYER_ENTERING_WORLD; Core_Flavor)
    if ns.AddonMessagesBlocked and ns.AddonMessagesBlocked() then
        wipe(queue)
        held = true
        if pump then pump:Cancel(); pump = nil end
        return
    end
    local item = table.remove(queue, 1)
    if not item then
        if pump then pump:Cancel(); pump = nil end
        return
    end
    local chan, target = item.chan, item.target
    if chan == nil then chan = Channel() end
    if chan then pcall(SendAddon, D.PREFIX, item.msg, chan, target) end
end

function Comm.Send(msg, whisperTo)
    if not BL.Running() then return end
    if not whisperTo and not Channel() then return end
    if not whisperTo then
        if msg == lastSent then return end
        lastSent = msg
    end
    queue[#queue + 1] = { msg = msg, chan = whisperTo and "WHISPER" or nil, target = whisperTo }
    if not pump then
        pump = C_Timer.NewTicker(0.15, Pump)
        if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(pump, "blessings.comm") end
    end
end

-- forget the de-dupe (a new group, a REQ: say it all again)
function Comm.Fresh() lastSent = nil end

-- ============================================================
-- WHAT I SAY ABOUT MYSELF
-- ============================================================
local function Hex(v) return format("%x", math.max(0, math.min(15, v or 0))) end

local function RanksString(list, n)
    local s = {}
    for i = 1, n do
        local r = list and list[i]
        s[#s + 1] = r and (Hex(r.rank) .. Hex(r.talent)) or "nn"
    end
    return table.concat(s)
end

local function AssignString(assign)
    local s = {}
    for i = 1, D.NUM_CLASSES do
        local b = assign and assign[i]
        s[#s + 1] = (b and b > 0) and tostring(b) or "n"
    end
    return table.concat(s)
end

-- everything about me; to one asker by whisper, else the group
function Comm.SendSelf(to)
    if BL.IsLeader(BL.me) then Comm.Send("PPLEADER " .. BL.me, to) end
    if not BL.isPaladin then return end
    local p = BL.Pally(BL.me)
    Comm.Send("SELF " .. RanksString(p.blessings, D.NUM_BLESSINGS) .. "@" .. AssignString(p.assign), to)
    Comm.Send("ASELF " .. RanksString(p.auras, D.NUM_AURAS) .. "@" .. tostring(p.aura or 0), to)
    local list = {}
    for slot, targets in pairs(p.normal) do
        for tname, b in pairs(targets) do
            list[#list + 1] = format("%s %d %s %d", BL.me, slot, tname, b)
        end
    end
    table.sort(list)
    for i = 1, #list, 5 do
        Comm.Send("NASSIGN " .. table.concat(list, "@", i, math.min(i + 4, #list)), to)
    end
    local cd = {}
    for i = 1, 2 do
        local c = p.cd and p.cd[i]
        if c and c.duration then
            local left = math.max(0, (c.start or 0) + c.duration - GetTime())
            cd[#cd + 1] = ":" .. math.floor(c.duration + 0.5) .. ":" .. math.floor(left + 0.5)
        else
            cd[#cd + 1] = ":n:n"
        end
    end
    Comm.Send(format("FREEASSIGN %s | SYMCOUNT %d | COOLDOWNS%s",
        BL.FreeAssign() and "YES" or "NO", p.symbols or 0, table.concat(cd)), to)
end

-- my changes to someone's assignments, as they happen
function Comm.SendAssign(name, slot, b) Comm.Send(format("ASSIGN %s %d %d", name, slot, b or 0)) end
function Comm.SendAllAssign(name) Comm.Send("PASSIGN " .. name .. "@" .. AssignString(BL.Pally(name).assign)) end
function Comm.SendMassAssign(name, b) Comm.Send(format("MASSIGN %s %d", name, b or 0)) end
function Comm.SendAura(name, a) Comm.Send(format("AASSIGN %s %d", name, a or 0)) end
function Comm.SendNormal(name, slot, tname, b)
    Comm.Send(format("NASSIGN %s %d %s %d", name, slot, tname, b or 0))
end
function Comm.SendClear(skipAuras) Comm.Send(skipAuras and "CLEAR SKIP" or "CLEAR") end
function Comm.Request() Comm.Fresh(); Comm.Send("REQ") end

-- ============================================================
-- WHAT OTHERS SAY
-- ============================================================
local function ParseRanks(s, n)
    local out = {}
    for i = 1, n do
        local r = strsub(s or "", (i - 1) * 2 + 1, (i - 1) * 2 + 1)
        local t = strsub(s or "", (i - 1) * 2 + 2, (i - 1) * 2 + 2)
        if r ~= "" and r ~= "n" then
            out[i] = { rank = tonumber(r, 16) or 0, talent = tonumber(t, 16) or 0 }
        end
    end
    return out
end

local function ParseAssign(s)
    local out = {}
    for i = 1, D.NUM_CLASSES do
        local c = strsub(s or "", i, i)
        local v = tonumber(c)
        out[i] = (v and v > 0 and v <= D.NUM_BLESSINGS) and v or 0
    end
    return out
end

-- may `sender` set `name`'s assignments?
local function MaySet(sender, name)
    if name == sender then return true end
    if BL.IsLeader(sender) then return true end
    -- a paladin who allows free assignment takes changes from anyone;
    -- for me that is my own setting
    if name == BL.me then return BL.FreeAssign() end
    local p = BL.pallys[name]
    return p ~= nil and p.freeassign == true
end

local function Parse(sender, msg)
    local changed = false

    -- PPLEADER: the roster already says who leads (raid rank); a claim
    -- alone never grants rights
    if msg:find("^PPLEADER ") then return end
    if sender == BL.me then return end

    if msg == "REQ" then
        -- answered to the asker only (in a battleground's instance group
        -- whispers do not cross, so there it is the group, as PallyPower does)
        if Channel() == "INSTANCE_CHAT" then Comm.Fresh() Comm.SendSelf() else Comm.SendSelf(sender) end
        return
    end

    local ranks, assign = msg:match("^SELF ([0-9a-fn]*)@([0-9n]*)")
    if ranks then
        local p = BL.Pally(sender)
        p.blessings = ParseRanks(ranks, D.NUM_BLESSINGS)
        p.assign = ParseAssign(assign)
        p.seen = GetTime()
        changed = true
    end

    local aranks, aura = msg:match("^ASELF ([0-9a-fn]*)@([0-9n]*)")
    if aranks then
        local p = BL.Pally(sender)
        p.auras = ParseRanks(aranks, D.NUM_AURAS)
        p.aura = tonumber(aura) or 0
        p.seen = GetTime()
        changed = true
    end

    local an, aslot, ab = msg:match("^ASSIGN (%S+) (%d+) (%d+)")
    if an then
        an = Short(an)
        aslot, ab = tonumber(aslot), tonumber(ab)
        if MaySet(sender, an) and aslot and aslot >= 1 and aslot <= D.NUM_CLASSES then
            BL.Pally(an).assign[aslot] = (ab and ab <= D.NUM_BLESSINGS) and ab or 0
            changed = true
        end
    end

    local pn, pas = msg:match("^PASSIGN (%S+)@([0-9n]*)")
    if pn then
        pn = Short(pn)
        if MaySet(sender, pn) then
            BL.Pally(pn).assign = ParseAssign(pas)
            changed = true
        end
    end

    local mn, mb = msg:match("^MASSIGN (%S+) (%d+)")
    if mn then
        mn = Short(mn)
        mb = tonumber(mb) or 0
        if MaySet(sender, mn) then
            local p = BL.Pally(mn)
            for i = 1, D.NUM_CLASSES do p.assign[i] = (mb <= D.NUM_BLESSINGS) and mb or 0 end
            changed = true
        end
    end

    if strsub(msg, 1, 8) == "NASSIGN " then
        for pname, slot, tname, b in string.gmatch(strsub(msg, 9), "([^@ ]+) (%d+) ([^@ ]+) (%d+)") do
            pname = Short(pname)
            slot, b = tonumber(slot), tonumber(b)
            if MaySet(sender, pname) and slot and slot >= 1 and slot <= D.NUM_CLASSES then
                local p = BL.Pally(pname)
                p.normal[slot] = p.normal[slot] or {}
                p.normal[slot][tname] = (b and b > 0 and b <= D.SACRIFICE) and b or nil
                changed = true
            end
        end
    end

    local aan, aaa = msg:match("^AASSIGN (%S+) (%d+)")
    if aan then
        aan = Short(aan)
        if MaySet(sender, aan) then
            local a = tonumber(aaa) or 0
            BL.Pally(aan).aura = (a <= D.NUM_AURAS) and a or 0
            changed = true
        end
    end

    if strsub(msg, 1, 5) == "CLEAR" then
        local skip = strfind(msg, "SKIP", 1, true) ~= nil
        if BL.IsLeader(sender) then
            BL.ClearAll(skip, true)
            changed = true
        elseif BL.FreeAssign() then
            BL.ClearAll(skip, "own")
            changed = true
        end
    end

    if strfind(msg, "FREEASSIGN", 1, true) then
        local p = BL.pallys[sender]
        if p then
            if strfind(msg, "FREEASSIGN YES", 1, true) then p.freeassign = true
            elseif strfind(msg, "FREEASSIGN NO", 1, true) then p.freeassign = false end
            local sym = msg:match("SYMCOUNT (%d+)")
            p.symbols = tonumber(sym) or 0
            local cdpart = msg:match("COOLDOWNS(:.*)$")
            if cdpart then
                local _, d1, r1, d2, r2 = strsplit(":", cdpart)
                p.cd = p.cd or {}
                for i, pair in ipairs({ { d1, r1 }, { d2, r2 } }) do
                    local dur, rem = tonumber(pair[1]), tonumber(pair[2])
                    if dur and rem then
                        p.cd[i] = { duration = dur, start = GetTime() - (dur - rem) }
                    end
                end
            end
            changed = true
        end
    end

    if changed then
        if BL.SaveMine then BL.SaveMine() end
        BL.Changed()
    end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, prefix, msg, dist, source)
    if event == "PLAYER_ENTERING_WORLD" then
        -- out of an instance after Forever held our messages: say it all again
        if held and not (ns.AddonMessagesBlocked and ns.AddonMessagesBlocked()) then
            held = false
            Comm.Request()
            Comm.SendSelf()
        end
        return
    end
    if prefix ~= D.PREFIX or type(msg) ~= "string" then return end
    if dist ~= "PARTY" and dist ~= "RAID" and dist ~= "WHISPER" and dist ~= "INSTANCE_CHAT" then return end
    local sender = Short(source)
    if not sender or sender == "" then return end
    Parse(sender, msg)
end)

function Comm.Start()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(D.PREFIX)
    end
    frame:RegisterEvent("CHAT_MSG_ADDON")
    -- (only where addon messages can be held: Forever, or its override)
    if (ns.ModernRules and ns.ModernRules()) or _G.ZACUI_MODERN then
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    end
end

function Comm.Stop()
    frame:UnregisterEvent("CHAT_MSG_ADDON")
    frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
    held = false
    wipe(queue)
    if pump then pump:Cancel(); pump = nil end
end
