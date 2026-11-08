-- QoL_Quests - quest helpers for levelling: quests taken and handed in
-- for you, a sound when an objective or a whole quest is done, and the
-- progress said to your party. Every one off by default (Quality of life >
-- Quests).
-- Part of ZacUI; load order is set by the TOC.
--
-- TAKING AND HANDING IN. The quest pages the game opens are answered the
-- way your own click would: a quest offered is accepted; a hand-in that
-- asks for items goes on; the reward page is taken when there is no choice
-- to make (none, or one). It never decides a choice of rewards (the coin
-- from Win_QuestRewards shows the one that sells best), never hands in a
-- quest that wants your gold, and leaves a quest the game marks as too low
-- for you alone unless you say otherwise. On a quest giver's own page
-- (gossip or greeting) a finished quest is handed in first, then one on
-- offer is picked; one per page, as the next page comes up by itself.
-- Shift held stops it (or, if you prefer, only Shift held lets it run).
--
-- SOUNDS AND THE PARTY LINE come from your quest log, read a moment after
-- the game says the log changed (QUEST_LOG_UPDATE starts one short timer;
-- a burst of them is one read). An objective going from not done to done
-- plays one sound; a quest going to complete plays another. The first read
-- after login, and a quest just taken, only learn the log: nothing plays.
-- The party line goes to your party only (never a raid), out of combat
-- or in, and says "Quest: objective 8/8" or "Quest complete: name".
--
-- Classic Era, TBC and Forever read the log with the Classic calls; a
-- client without them (Retail) reads C_QuestLog. A hidden value (Forever)
-- is never compared or joined: that entry is skipped for the read.
--
-- COST: nothing registered while every switch is off. On: the quest
-- pages' events (when you talk to someone) and one log read per burst of
-- log changes, the log being at most 25 quests (Classic) long.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local Print = ns.Print
local QoL = ns.QoL
if not QoL then return end

local Q = {}
QoL.Quests = Q

local OWN_ID = "quest_helpers"
local READ_DELAY = 0.4          -- seconds after the last log change before it is read

local function Hidden(v) return ns.IsSecret and ns.IsSecret(v) or false end

-- ============================================================
-- SETTINGS (qol.quests; nothing saved = all off)
--   accept, turnIn, trivial (take grey quests too), shift ("skip" | "only"),
--   objSound, doneSound, announce, announceAll (every step, not only done),
--   sounds = { obj = spec, done = spec }
-- ============================================================
Q.SOUND_OBJ = { sound = "ui:Ting", channel = "Master", throttle = 0 }
Q.SOUND_DONE = { sound = "ui:Chime", channel = "Master", throttle = 0 }
Q.SHIFT_MODES = {
    { value = "skip", text = "Shift held stops it" },
    { value = "only", text = "Only while Shift is held" },
}

local function DB()
    local q = QoL.DB()
    if type(q.quests) ~= "table" then q.quests = {} end
    return q.quests
end
Q.DB = DB

local function Allowed()
    return not (ns.FeatureOn and not ns.FeatureOn(OWN_ID))
end
function Q.On(key) return Allowed() and DB()[key] == true end
function Q.AutoOn() return Q.On("accept") or Q.On("turnIn") end
function Q.LogOn() return Q.On("objSound") or Q.On("doneSound") or Q.On("announce") end
function Q.AnyOn() return Q.AutoOn() or Q.LogOn() end

-- whether Shift lets the automation through right now
function Q.ShiftAllows()
    local down = IsShiftKeyDown and IsShiftKeyDown() and true or false
    if DB().shift == "only" then return down end
    return not down
end

-- ============================================================
-- THE QUEST PAGES
-- ============================================================
local function Call(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok = pcall(fn, ...)
    return ok
end

-- a quest the game marks as too low for you (grey)
local function TrivialDetail()
    local id = GetQuestID and GetQuestID()
    if not id or Hidden(id) then return false end
    local CQ = _G.C_QuestLog
    if CQ and type(CQ.IsQuestTrivial) == "function" then
        local ok, v = pcall(CQ.IsQuestTrivial, id)
        if ok and v == true then return true end
    end
    return false
end

function Q.OnDetail()
    if not Q.On("accept") or not Q.ShiftAllows() then return false end
    -- a quest the game has already taken (Retail's auto-accept) needs nothing
    if QuestGetAutoAccept and QuestGetAutoAccept() then return false end
    if not DB().trivial and TrivialDetail() then return false end
    return Call(AcceptQuest)
end

function Q.OnAcceptConfirm()
    -- a quest a party member started (an escort): the same switch takes it
    if not Q.On("accept") or not Q.ShiftAllows() then return false end
    return Call(ConfirmAcceptQuest)
end

function Q.OnProgress()
    if not Q.On("turnIn") or not Q.ShiftAllows() then return false end
    if not (IsQuestCompletable and IsQuestCompletable()) then return false end
    local money = GetQuestMoneyToGet and GetQuestMoneyToGet() or 0
    if Hidden(money) or (tonumber(money) or 0) > 0 then return false end
    return Call(CompleteQuest)
end

function Q.OnComplete()
    if not Q.On("turnIn") or not Q.ShiftAllows() then return false end
    local n = GetNumQuestChoices and GetNumQuestChoices() or 0
    if Hidden(n) then return false end
    n = tonumber(n) or 0
    if n > 1 then return false end      -- a choice: yours to make
    return Call(GetQuestReward, n)
end

-- The gossip page: C_GossipInfo where the client has it, the old calls else.
-- Each list as { complete = bool, trivial = bool, pick = function }.
local function GossipLists()
    local active, avail = {}, {}
    local G = _G.C_GossipInfo
    if G and type(G.GetActiveQuests) == "function" then
        local ok, list = pcall(G.GetActiveQuests)
        for _, e in ipairs(ok and type(list) == "table" and list or {}) do
            local id = e.questID
            active[#active + 1] = { complete = e.isComplete == true, pick = function()
                if id and G.SelectActiveQuest then G.SelectActiveQuest(id) end end }
        end
        ok, list = pcall(G.GetAvailableQuests)
        for _, e in ipairs(ok and type(list) == "table" and list or {}) do
            local id = e.questID
            avail[#avail + 1] = { trivial = e.isTrivial == true, pick = function()
                if id and G.SelectAvailableQuest then G.SelectAvailableQuest(id) end end }
        end
        return active, avail
    end
    -- the old calls: name, level, isTrivial, isComplete, ... per quest (6 values)
    if type(GetGossipActiveQuests) == "function" then
        local t = { GetGossipActiveQuests() }
        local per = 6
        for i = 1, math.floor(#t / per) do
            local idx = i
            active[#active + 1] = { complete = t[(i - 1) * per + 4] and true or false,
                pick = function() if SelectGossipActiveQuest then SelectGossipActiveQuest(idx) end end }
        end
    end
    if type(GetGossipAvailableQuests) == "function" then
        local t = { GetGossipAvailableQuests() }
        local per = 7
        for i = 1, math.floor(#t / per) do
            local idx = i
            avail[#avail + 1] = { trivial = t[(i - 1) * per + 3] and true or false,
                pick = function() if SelectGossipAvailableQuest then SelectGossipAvailableQuest(idx) end end }
        end
    end
    return active, avail
end

-- The greeting page (a quest giver with several quests and no gossip).
local function GreetingLists()
    local active, avail = {}, {}
    local na = GetNumActiveQuests and GetNumActiveQuests() or 0
    for i = 1, (tonumber(na) or 0) do
        local _, done = nil, false
        if GetActiveTitle then _, done = GetActiveTitle(i) end
        local idx = i
        active[#active + 1] = { complete = done and true or false,
            pick = function() if SelectActiveQuest then SelectActiveQuest(idx) end end }
    end
    local nv = GetNumAvailableQuests and GetNumAvailableQuests() or 0
    for i = 1, (tonumber(nv) or 0) do
        local trivial = false
        if GetAvailableQuestInfo then trivial = GetAvailableQuestInfo(i) and true or false end
        local idx = i
        avail[#avail + 1] = { trivial = trivial,
            pick = function() if SelectAvailableQuest then SelectAvailableQuest(idx) end end }
    end
    return active, avail
end

-- one pick per page: a finished quest handed in first, then one on offer
local function PickFrom(active, avail)
    if not Q.ShiftAllows() then return nil end
    if Q.On("turnIn") then
        for _, e in ipairs(active) do
            if e.complete then pcall(e.pick) return "turnin" end
        end
    end
    if Q.On("accept") then
        local trivialOK = DB().trivial == true
        for _, e in ipairs(avail) do
            if trivialOK or not e.trivial then pcall(e.pick) return "accept" end
        end
    end
    return nil
end
function Q.OnGossip() return PickFrom(GossipLists()) end
function Q.OnGreeting() return PickFrom(GreetingLists()) end

-- ============================================================
-- THE LOG: sounds and the party line
-- ============================================================
-- one entry per quest: { title, done = bool, objs = { {text, finished}, ... } }
-- or nil when this client has no quest log calls
local function ReadClassic()
    if type(GetNumQuestLogEntries) ~= "function" or type(GetQuestLogTitle) ~= "function" then return nil end
    local out = {}
    local n = GetNumQuestLogEntries()
    if Hidden(n) then return nil end
    for i = 1, (tonumber(n) or 0) do
        local title, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
        if not isHeader and questID and not Hidden(questID) and type(title) == "string" and not Hidden(title) then
            local e = { title = title, done = (isComplete == 1 or isComplete == true), objs = {} }
            local nb = GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i) or 0
            for j = 1, (tonumber(nb) or 0) do
                local text, _, finished = GetQuestLogLeaderBoard(j, i)
                if type(text) == "string" and not Hidden(text) then
                    e.objs[#e.objs + 1] = { text = text, finished = finished and true or false }
                end
            end
            out[questID] = e
        end
    end
    return out
end

local function ReadModern()
    local CQ = _G.C_QuestLog
    if not (CQ and type(CQ.GetNumQuestLogEntries) == "function" and type(CQ.GetInfo) == "function") then return nil end
    local out = {}
    local n = CQ.GetNumQuestLogEntries()
    if Hidden(n) then return nil end
    for i = 1, (tonumber(n) or 0) do
        local info = CQ.GetInfo(i)
        local id = type(info) == "table" and info.questID or nil
        if id and not info.isHeader and not Hidden(id) and type(info.title) == "string" and not Hidden(info.title) then
            local done = CQ.IsComplete and CQ.IsComplete(id) or false
            local e = { title = info.title, done = done == true, objs = {} }
            local objs = CQ.GetQuestObjectives and CQ.GetQuestObjectives(id) or nil
            for _, o in ipairs(type(objs) == "table" and objs or {}) do
                if type(o.text) == "string" and not Hidden(o.text) then
                    e.objs[#e.objs + 1] = { text = o.text, finished = o.finished == true }
                end
            end
            out[id] = e
        end
    end
    return out
end

function Q.ReadLog() return ReadClassic() or ReadModern() end

local known          -- the last read, nil until the first
local said = {}      -- the party lines sent this read (no line twice)

local function Say(text)
    if not Q.On("announce") then return end
    if said[text] then return end
    said[text] = true
    if not (IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid()) then return end
    if SendChatMessage then pcall(SendChatMessage, text, "PARTY") end
end
Q.Say = Say

local function Sound(which)
    local d = DB()
    local key = which == "done" and "doneSound" or "objSound"
    if not Q.On(key) or not ns.PlaySoundSpec then return end
    local spec = type(d.sounds) == "table" and d.sounds[which] or nil
    ns.PlaySoundSpec(spec, which == "done" and Q.SOUND_DONE or Q.SOUND_OBJ, "qol.quests." .. which)
end
Q.Sound = Sound

-- what changed between two reads: plays and says it, returns the counts
function Q.Compare(old, new)
    local objDone, questDone, steps = 0, 0, 0
    for id, e in pairs(new) do
        local was = old[id]
        if was then
            if e.done and not was.done then
                questDone = questDone + 1
                Sound("done")
                Say("Quest complete: " .. e.title)
            else
                for j, o in ipairs(e.objs) do
                    local p = was.objs[j]
                    if p and o.text ~= p.text then
                        if o.finished and not p.finished then
                            objDone = objDone + 1
                            Sound("obj")
                            Say(e.title .. ": " .. o.text)
                        elseif DB().announceAll then
                            steps = steps + 1
                            Say(e.title .. ": " .. o.text)
                        end
                    end
                end
            end
        end
    end
    return objDone, questDone, steps
end

function Q.Read()
    if not Q.LogOn() then known = nil return end
    local now = Q.ReadLog()
    if not now then return end
    wipe(said)
    if known then Q.Compare(known, now) end
    known = now
end
function Q.Known() return known end
function Q.Forget() known = nil end

local pending = false
local function Schedule()
    if pending then return end
    pending = true
    C_Timer.After(READ_DELAY, function()
        pending = false
        pcall(Q.Read)
    end)
end

-- ============================================================
-- EVENTS: armed only while a switch is on
-- ============================================================
local ev
local PAGE_EVENTS = { "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_ACCEPT_CONFIRM",
    "GOSSIP_SHOW", "QUEST_GREETING" }

local function OnEvent(_, event)
    if event == "QUEST_LOG_UPDATE" then return Schedule() end
    if event == "QUEST_DETAIL" then Q.OnDetail()
    elseif event == "QUEST_PROGRESS" then Q.OnProgress()
    elseif event == "QUEST_COMPLETE" then Q.OnComplete()
    elseif event == "QUEST_ACCEPT_CONFIRM" then Q.OnAcceptConfirm()
    elseif event == "GOSSIP_SHOW" then Q.OnGossip()
    elseif event == "QUEST_GREETING" then Q.OnGreeting()
    end
end

function Q.Apply()
    local auto, log = Q.AutoOn(), Q.LogOn()
    if not (auto or log) then
        if ev then ev:UnregisterAllEvents() end
        known = nil
        return
    end
    if not ev then
        ev = CreateFrame("Frame")
        ev:SetScript("OnEvent", OnEvent)
    end
    for _, e in ipairs(PAGE_EVENTS) do
        if auto then pcall(ev.RegisterEvent, ev, e) else pcall(ev.UnregisterEvent, ev, e) end
    end
    if log then
        ev:RegisterEvent("QUEST_LOG_UPDATE")
        if not known then Schedule() end
    else
        ev:UnregisterEvent("QUEST_LOG_UPDATE")
        known = nil
    end
end
function Q.Armed() return ev ~= nil and ev:IsEventRegistered("QUEST_LOG_UPDATE") or false end
function Q.PagesArmed() return ev ~= nil and ev:IsEventRegistered("QUEST_DETAIL") or false end

-- armed when the module starts (QoL_Core calls QoL.EnableAutomation at
-- login), so the helpers stand down with the rest of the module behind
-- Leatrix Plus; no frame is made until a switch is on
local function Live() if QoL.enabled then Q.Apply() end end
Q.Live = Live
if Allowed() then
    local base = QoL.EnableAutomation
    function QoL.EnableAutomation(...)
        if base then base(...) end
        pcall(Q.Apply)
    end
end

-- ============================================================
-- THE PAGE: Quality of life > Quests
-- ============================================================
local function AddTab(page, tab, label, build)
    if ns.AddPageTab then return ns.AddPageTab(page, tab, label, build) end
    ns.PageTabs = ns.PageTabs or {}
    local list = ns.PageTabs[page] or {}
    ns.PageTabs[page] = list
    list[#list + 1] = { tab = tab, label = label, build = build }
end

AddTab("qol", "quests", "Quests", function(L)
    if not Allowed() then return end
    local UI = ns.UI
    local d = DB()
    local function Check(key, label, tip)
        local w = UI.Checkbox(L.current, label, d[key] == true, function(v)
            d[key] = v and true or nil
            Live()
            if ns.RefreshConfig then ns.RefreshConfig() end
        end, tip and { tooltip = tip } or nil)
        L:Row(w, 17)
        return w
    end

    L:Card("Taking and handing in")
    Check("accept", "Take quests for me",
        "A quest a quest giver offers is accepted as soon as its page opens, and on a quest giver's list the "
        .. "first one on offer is picked. Quests the game shows grey (too low for you) are left alone unless you tick below.")
    Check("turnIn", "Hand in finished quests for me",
        "A finished quest is handed in when you talk to its quest giver. The reward is taken only when there is "
        .. "no choice to make; a choice of rewards, or a quest that wants your gold, is left to you.")
    local kids = {}
    kids[#kids + 1] = UI.Checkbox(L.current, "Grey quests too", d.trivial == true, function(v)
        d.trivial = v and true or nil
    end, { tooltip = "Also take the quests the game marks as too low for your level." })
    kids[#kids + 1] = UI.Field(L.current, "Shift key", function(h)
        return UI.Dropdown(h, { width = 190,
            items = function() return Q.SHIFT_MODES end,
            selectedValue = function() return d.shift or "skip" end,
            selected = function()
                for _, m in ipairs(Q.SHIFT_MODES) do if m.value == (d.shift or "skip") then return m.text end end
                return Q.SHIFT_MODES[1].text
            end,
            onSelect = function(v) d.shift = (v ~= "skip") and v or nil end })
    end, { width = 190 })
    L:Dependent(kids, Q.AutoOn(), 1, nil, "Take quests for me")
    L:EndCard()

    L:Card("Sounds and your party")
    local soundRows = {}
    local function SoundRow(key, label, which, def, tip)
        Check(key, label, tip)
        if UI.SoundSpecPicker and ns.CustomAccess then
            local get, set = ns.CustomAccess(DB, "sounds", which)
            local p = UI.SoundSpecPicker(L.current, { get = get, set = set, defaults = def,
                width = UI.CardInnerWidth and UI.CardInnerWidth(L) or nil })
            L:Dependent({ p }, d[key] == true, 1, nil, label)
            soundRows[#soundRows + 1] = p
        end
    end
    SoundRow("objSound", "A sound when an objective is done", "obj", Q.SOUND_OBJ,
        "Plays when one of a quest's objectives is finished (the last kill or item of it).")
    SoundRow("doneSound", "A sound when a quest is complete", "done", Q.SOUND_DONE,
        "Plays when every objective of a quest is finished and it is ready to hand in.")
    Check("announce", "Tell my party",
        "In a party (never a raid) a line in party chat when an objective or a quest is done: "
        .. "\"Kobold Camp Cleanup: Kobold Vermin slain: 10/10\".")
    local all = UI.Checkbox(L.current, "Every step, not only when one is done", d.announceAll == true, function(v)
        d.announceAll = v and true or nil
    end, { tooltip = "Also a line for each kill or item on the way (3/10, 4/10...)." })
    L:Dependent({ all }, d.announce == true, 1, nil, "Tell my party")
    local test = UI.Button(L.current, "Test the sounds", { width = 120,
        tooltip = "Plays the objective sound, then the quest sound.",
        onClick = function()
            if not ns.PlaySoundSpec then return end
            ns.PlaySoundSpec(type(d.sounds) == "table" and d.sounds.obj or nil, Q.SOUND_OBJ)
            C_Timer.After(0.8, function()
                ns.PlaySoundSpec(type(d.sounds) == "table" and d.sounds.done or nil, Q.SOUND_DONE)
            end)
        end })
    L:Row(test, 26)
    L:EndCard()
end)

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("qol", "quest quests accept turn in hand in auto accept auto turn in objective complete sound party announce progress levelling leveling")
end
