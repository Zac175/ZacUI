-- Core_VersionCheck - "a newer ZacUI is out". Every ZacUI client says
-- which version it runs to its guild and group over addon messages, and
-- the first time this one hears of a newer version it prints one line.
-- Part of ZacUI; load order is set by the TOC (after Core_Services, for
-- ns.GroupChannel, and Core_Flavor, for ns.AddonMessagesBlocked). ZacUI's
-- own code: nothing here reads or needs Readycheck.
--
--   ns.VersionCheck.Mine()           this client's version ("2.0.0"), or
--                                    nil when the TOC's is not a plain one
--   ns.VersionCheck.Newest()         version, who, channel: the highest
--                                    version heard this session (nil if none)
--   ns.VersionCheck.NoticeOn()       the General page's switch
--   ns.VersionCheck.SetNotice(on)
--   ns.VersionCheck.Compare(a, b)    -1 / 0 / 1, by number ("2.10" > "2.9")
--   ns.VersionCheck.Clean(v)         v when it is a version we believe, else nil
--   ns.VersionCommand()              /zacui version
--
-- THE TALK. One prefix, ZacUIVer, two short messages:
--   "Q:<version>"  hello: here is mine, and anyone newer please say so.
--                  Sent a little after login, and when you join a group.
--   "V:<version>"  the answer, only from a client NEWER than the asker,
--                  at most once a minute per channel, and not at all when
--                  someone else on that channel already said a version at
--                  least as new while ours waited its turn.
-- So a guild where everyone is up to date says one hello each at login
-- and nothing else.
--
-- WHAT WE BELIEVE. A version is digits and dots, two to four numbers,
-- the first no higher than 99, none longer than three digits. Anything
-- else (a joke, a typo, "999.0.0") is dropped before it is compared or
-- printed.
--
-- QUIET. Nothing is sent in combat: what would go out then waits for the
-- end of combat. A notice heard in combat is printed after it. Forever
-- delivers no addon messages inside an instance (Core_Flavor): what would
-- go out there waits until you are outside (the next loading screen).
--
-- THE SWITCH. ZacUIDB.versionCheck.notify (nil = on), account-wide and
-- outside every profile, like the voice. Off stops the line in chat; your
-- version is still shared, so guildmates on an older one still hear.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local GroupChannel = ns.GroupChannel
local Print = ns.Print
local ZUI = ns.ZUI

local type, tonumber, tostring, pairs = type, tonumber, tostring, pairs

local VC = {}
ns.VersionCheck = VC

local PREFIX       = "ZacUIVer"
local URL          = "curseforge.com/wow/addons/zacui"
local REPLY_GAP    = 60    -- seconds between two answers on one channel
local HELLO_GAP    = 60    -- seconds between two hellos on one channel
local LOGIN_DELAY  = 10    -- the hello after login waits for the guild roster
local MAX_MAJOR    = 99    -- "100.0.0" is somebody having fun
local MAX_SEEN     = 300   -- names remembered this session (a big guild)

-- ============================================================
-- VERSIONS
-- ============================================================
function VC.Clean(v)
    if type(v) ~= "string" then return nil end
    v = v:match("^%s*(.-)%s*$")
    if #v == 0 or #v > 15 then return nil end
    if not v:find("^%d+%.%d+[%.%d]*$") then return nil end
    local n = 0
    for part in v:gmatch("[^%.]+") do
        n = n + 1
        if n > 4 or #part > 3 then return nil end
        if n == 1 and tonumber(part) > MAX_MAJOR then return nil end
    end
    -- "2..0" and "2.0." have an empty part
    if v:find("%.%.") or v:find("%.$") then return nil end
    return v
end
local Clean = VC.Clean

function VC.Compare(a, b)
    local pa, pb = {}, {}
    for d in tostring(a or ""):gmatch("%d+") do pa[#pa + 1] = tonumber(d) end
    for d in tostring(b or ""):gmatch("%d+") do pb[#pb + 1] = tonumber(d) end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end
local Compare = VC.Compare

-- The TOC's ## Version (what the CurseForge release says), else the one
-- written in Core_Boot. A packager placeholder reads as no version: we
-- then neither send nor compare.
local function ReadMine()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local v
    if get then
        local ok, r = pcall(get, ADDON_NAME, "Version")
        if ok then v = r end
    end
    return Clean(v) or Clean(ZUI and ZUI.VERSION)
end
local mine = ReadMine()
function VC.Mine() return mine end

-- ============================================================
-- THE SWITCH
-- ============================================================
function VC.NoticeOn()
    local d = type(ZacUIDB) == "table" and ZacUIDB.versionCheck
    return not (type(d) == "table" and d.notify == false)
end

function VC.SetNotice(on)
    if type(ZacUIDB) ~= "table" then return end
    if on then
        -- back to the default: nothing left saved
        if type(ZacUIDB.versionCheck) == "table" then
            ZacUIDB.versionCheck.notify = nil
            if next(ZacUIDB.versionCheck) == nil then ZacUIDB.versionCheck = nil end
        end
    else
        if type(ZacUIDB.versionCheck) ~= "table" then ZacUIDB.versionCheck = {} end
        ZacUIDB.versionCheck.notify = false
    end
end

-- ============================================================
-- WHAT WE HEARD
-- ============================================================
local seen, seenCount = {}, 0                -- name -> version
local newest, newestWho, newestChan          -- the highest heard
local noticed = false                        -- the line went out this session
local noticeWaiting = false                  -- heard in combat, printed after

local CHANNEL_WORDS = { GUILD = "guild", RAID = "raid", PARTY = "party", INSTANCE_CHAT = "instance group" }

function VC.Newest() return newest, newestWho, newestChan end
function VC.SeenCount() return seenCount end

local events  -- the event frame (below)

local function InCombat() return InCombatLockdown and InCombatLockdown() and true or false end

local function NoticeLine(v)
    return "A newer ZacUI (" .. v .. ") is out. Update it with the CurseForge app or from " .. URL .. "."
end
VC.NoticeLine = NoticeLine

local function TryNotice()
    if noticed or not newest or not mine then return end
    if Compare(newest, mine) <= 0 then return end
    if not VC.NoticeOn() then return end
    if InCombat() then
        noticeWaiting = true
        if events then events:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return
    end
    noticed, noticeWaiting = true, false
    Print(NoticeLine(newest))
end
VC.TryNotice = TryNotice

local function Heard(who, v, chan)
    -- (past MAX_SEEN names the version still counts, the name is not kept)
    if who and (seen[who] ~= nil or seenCount < MAX_SEEN) then
        if seen[who] == nil then seenCount = seenCount + 1 end
        seen[who] = v
    end
    if not newest or Compare(v, newest) > 0 then
        newest, newestWho, newestChan = v, who, chan
    end
    TryNotice()
end

-- ============================================================
-- SENDING
-- ============================================================
local lastSent = { Q = {}, V = {} }      -- kind -> channel -> GetTime()
local held = {}                          -- channel -> "Q" | "V", waiting
local holding = false
local replyWait = {}                     -- channel -> "waiting" | "covered"

local function Blocked()
    return ns.AddonMessagesBlocked and ns.AddonMessagesBlocked() or false
end

-- still a channel we can talk on (a group can be left while a message waits)
local function ChannelLive(chan)
    if chan == "GUILD" then return IsInGuild and IsInGuild() and true or false end
    if not (IsInGroup and IsInRaid and GroupChannel) then return false end
    return GroupChannel() == chan
end

local function Hold(chan, kind)
    -- a hello also asks newer clients to answer, so it covers an answer
    if held[chan] ~= "Q" then held[chan] = kind end
    holding = true
    if events and InCombat() then events:RegisterEvent("PLAYER_REGEN_ENABLED") end
end

local function Send(chan, kind)
    if not mine or not chan then return false end
    local send = C_ChatInfo and C_ChatInfo.SendAddonMessage
    if not send then return false end
    if Blocked() or InCombat() then
        Hold(chan, kind)
        return false
    end
    local now = GetTime()
    local gap = kind == "Q" and HELLO_GAP or REPLY_GAP
    local last = lastSent[kind][chan]
    if last and now - last < gap then return false end
    if not ChannelLive(chan) then return false end
    lastSent[kind][chan] = now
    pcall(send, PREFIX, kind .. ":" .. mine, chan)
    return true
end
VC.Send = Send

-- what waited (combat, or an instance on Forever) goes out once we can
local function Release()
    if not holding or Blocked() then return end
    if InCombat() then
        -- (out of an instance straight into a fight: after it, then)
        if events then events:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return
    end
    holding = false
    local list = held
    held = {}
    for chan, kind in pairs(list) do Send(chan, kind) end
end
VC.Release = Release

-- the hello: the guild, and the group when there is one
local function Hello()
    if IsInGuild and IsInGuild() then Send("GUILD", "Q") end
    local g = IsInGroup and IsInRaid and GroupChannel and GroupChannel()
    if g then Send(g, "Q") end
end
VC.Hello = Hello

-- an answer, a moment later (a raid full of newer clients does not all
-- answer on the same frame; the first one heard covers the rest)
local function Answer(chan)
    if replyWait[chan] then return end
    local last = lastSent.V[chan]
    if last and GetTime() - last < REPLY_GAP then return end
    replyWait[chan] = "waiting"
    C_Timer.After(1 + math.random() * 3, function()
        local st = replyWait[chan]
        replyWait[chan] = nil
        if st == "covered" then return end
        Send(chan, "V")
    end)
end

-- ============================================================
-- HEARING
-- ============================================================
local OK_DIST = { GUILD = true, RAID = true, PARTY = true, INSTANCE_CHAT = true }

local function Me(name)
    local me = UnitName and UnitName("player")
    return me and name == me
end

function VC.OnMessage(msg, dist, sender)
    if type(msg) ~= "string" or not OK_DIST[dist] then return end
    local kind, v = msg:match("^([QV]):(.+)$")
    v = Clean(v)
    if not v then return end
    local who = ns.ShortName and ns.ShortName(sender) or sender
    if Me(who) then return end
    Heard(who, v, dist)
    if not mine then return end
    local cmp = Compare(v, mine)
    -- someone on this channel already said a version at least as new
    -- as ours: our waiting answer adds nothing
    if cmp >= 0 and replyWait[dist] then replyWait[dist] = "covered" end
    -- an older client said hello: tell it
    if kind == "Q" and cmp < 0 then Answer(dist) end
end

-- ============================================================
-- EVENTS
-- ============================================================
local loggedIn = false
local groupChan          -- the group channel last said hello on
local groupCheck = false

local function CheckGroup()
    groupCheck = false
    local g = IsInGroup and IsInRaid and GroupChannel and GroupChannel()
    if g and g ~= groupChan then Send(g, "Q") end
    groupChan = g
end

events = CreateFrame("Frame")
VC.frame = events
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(self, event, a1, a2, a3, a4)
    if event == "CHAT_MSG_ADDON" then
        if a1 ~= PREFIX then return end
        VC.OnMessage(a2, a3, a4)
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- comes in bursts: one look, a few seconds after the first
        if not loggedIn or groupCheck then return end
        groupCheck = true
        C_Timer.After(3 + math.random() * 2, CheckGroup)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- every loading screen: out of an instance on Forever, what
        -- waited goes out
        Release()
        if not loggedIn then
            loggedIn = true
            -- the parts against the core, once (a popup in the login queue)
            pcall(VC.CheckParts)
            C_Timer.After(LOGIN_DELAY + math.random() * 5, function()
                groupChan = IsInGroup and IsInRaid and GroupChannel and GroupChannel() or nil
                Hello()
            end)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        Release()
        if noticeWaiting then TryNotice() end
    end
end)

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
end

-- ============================================================
-- THE PARTS AGAINST THE CORE (finish pass)
-- ============================================================
-- Every Zacui_* addon in the AddOns folder should carry the core's
-- version: a part left behind by an update errors in ways that look like
-- ZacUI bugs. At login each one's TOC version is compared with ours; a
-- mismatch is one popup naming the stale parts, in its turn in the login
-- popup queue (Core_Popups, after the others), once a session. A part
-- without a plain version (a development copy) is not judged.
--   ns.VersionCheck.StaleParts()  { { addon, version }, ... } (sorted)
--   ns.VersionCheck.CheckParts()  the popup when any are stale; true when it was asked for
local function AddonNames()
    local out = {}
    local num = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
    local info = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    if not (num and info) then return out end
    local ok, n = pcall(num)
    if not ok or type(n) ~= "number" then return out end
    for i = 1, n do
        local okI, name = pcall(info, i)
        if okI and type(name) == "string" and name:find("^Zacui_") then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

function VC.StaleParts()
    local out = {}
    if not mine then return out end
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if not get then return out end
    for _, name in ipairs(AddonNames()) do
        local ok, v = pcall(get, name, "Version")
        v = ok and Clean(v) or nil
        if v and Compare(v, mine) ~= 0 then out[#out + 1] = { addon = name, version = v } end
    end
    return out
end

local partsAsked = false
function VC.CheckParts()
    if partsAsked then return false end
    local stale = VC.StaleParts()
    if #stale == 0 then return false end
    partsAsked = true
    local list = {}
    for _, p in ipairs(stale) do list[#list + 1] = p.addon:gsub("^Zacui_", "") .. " " .. p.version end
    local function Show()
        local UI = ns.UI
        if not (UI and UI.Confirm) then
            Print("These ZacUI parts are not version " .. mine .. ": " .. table.concat(list, ", ")
                .. ". Update every ZacUI folder together.")
            return nil
        end
        return UI.Confirm({
            title = "ZacUI parts out of date",
            text = "These ZacUI parts are not the same version as ZacUI (" .. mine .. "):\n"
                .. table.concat(list, ", ") .. "\n"
                .. "Update every ZacUI folder together (the CurseForge app does). Until then they can show "
                .. "errors that are not real bugs.",
            acceptText = "Okay", noCancel = true,
        })
    end
    if ns.Popups then ns.Popups.Want("parts", Show, { delay = 2 }) else Show() end
    return true
end

-- ============================================================
-- /zacui version
-- ============================================================
function ns.VersionCommand()
    Print("This is ZacUI " .. (mine or "(no version - a development copy)") .. ".")
    if not newest then
        Print("No other ZacUI heard yet this session (your guild and group are asked a few seconds after login).")
    elseif not mine or Compare(newest, mine) > 0 then
        Print("Newest seen: " .. newest .. ", from " .. tostring(newestWho or "?")
            .. " (" .. (CHANNEL_WORDS[newestChan] or "group") .. "). Update it with the CurseForge app or from "
            .. URL .. ".")
    else
        Print("You are up to date. Newest heard: " .. newest .. ", from " .. tostring(newestWho or "?")
            .. " (" .. (CHANNEL_WORDS[newestChan] or "group") .. "); "
            .. seenCount .. (seenCount == 1 and " player" or " players") .. " compared.")
    end
    if not VC.NoticeOn() then
        Print("The newer-version notice is off (General > Overview > Updates).")
    end
    if holding then
        Print("Your version waits to be shared until you leave the instance (Forever) or combat ends.")
    end
end
