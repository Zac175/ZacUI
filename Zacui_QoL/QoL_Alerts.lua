-- QoL_Alerts - short lines in the middle of the screen, and two small
-- conveniences that ride the same events:
--   Combat           "Entering combat" / "Leaving combat" (which ones, texts,
--                    colours or your class colour)
--   Group deaths     "<name> died" when someone in your party or raid dies
--                    (feigning hunters and you left out), with a sound
--   Instance reset   a line in party / raid chat when your reset worked
--   Screenshots      the game's "Screen captured" text hidden
-- Off by default, except hiding the screenshot text (on, as a fresh
-- install has it in other UI suites; harmless, one switch to bring it back).
-- Quality of life > Reminders.
-- Part of ZacUI; load order is set by the TOC.
--
-- THE LINES share one place on the screen (a mover: "Alerts", the middle
-- of the screen, a little above), stacked: combat on top, deaths under it.
-- A line fades in (0.15 s), holds (combat 1.2 s, a death 2.5 s) and fades
-- out (0.5 s); it never takes the mouse. Each line is as wide as its text,
-- so no text is ever cut. Text outlined, in the font picked here.
--
-- DEATHS are found the same way on every game: while you are in a group
-- and the switch is on, a light poll (0.35 s) asks each member whether
-- they are dead; a member going from alive to dead is announced once.
-- Era / TBC have a combat log that says it too, but WoW Forever does not,
-- and one path is easier to trust. A hidden name (Forever) is handed to
-- the line as it is (the game draws it), never joined to other text.
--
-- THE RESET LINE reads the game's own system line, matched with the game's
-- own words for it (INSTANCE_RESET_SUCCESS / _FAILED), so it reads right in
-- any language; in a party a "players still inside" answer still means the
-- reset went through (only a raid can fail one). A hidden line is skipped
-- before any string work.
--
-- COST: nothing registered while off. Combat: two events. Deaths: one
-- ticker while you are in a group (up to 40 members, 3 calls each).

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local GetColor = ns.GetColor
local QoL = ns.QoL
if not QoL then return end

local A = {}
QoL.Alerts = A

local OWN_ID = "qol_alerts"
local MOVER = "qolalerts"
local GAP = 4
local FADE_IN, FADE_OUT = 0.15, 0.5
local POLL = 0.35
A.HOLD = { combat = 1.2, death = 2.5, mana = 4 }
A.SIZE = { combat = 22, death = 34, mana = 22 }
A.ORDER = { "combat", "death", "mana" }     -- (mana: the ready-check line, QoL_Reminders)
A.FONT_DEFAULTS = { size = 22, outline = "outline", shadow = false }
A.SOUND_DEATH = { sound = "ui:Fail", channel = "Master", throttle = 1 }
A.SHOW_ON = {
    { value = "both", text = "Entering and leaving" },
    { value = "enter", text = "Entering only" },
    { value = "leave", text = "Leaving only" },
}
A.DEFAULT_TEXT = { enter = "Entering combat", leave = "Leaving combat" }

local function Hidden(v) return ns.IsSecret and ns.IsSecret(v) or false end

-- ============================================================
-- SETTINGS (qol.alerts; nothing saved = all off but the screenshot text)
-- ============================================================
local function DB()
    local q = QoL.DB()
    if type(q.alerts) ~= "table" then q.alerts = {} end
    return q.alerts
end
A.DB = DB
local function Allowed() return not (ns.FeatureOn and not ns.FeatureOn(OWN_ID)) end
function A.On(key)
    if not Allowed() then return false end
    if key == "noShot" then return DB().noShot ~= false end
    return DB()[key] == true
end
function A.ShowOn() return DB().combatShow or "both" end
function A.Text(which)
    local t = DB()[which .. "Text"]
    if type(t) == "string" and t ~= "" then return t end
    return A.DEFAULT_TEXT[which]
end
function A.Color(which)
    local d = DB()
    if d[which .. "Class"] and UnitClass then
        local _, file = UnitClass("player")
        local c = file and RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
        if c then return c.r, c.g, c.b end
    end
    local c = d[which .. "Color"]
    if type(c) == "table" and ns.ColorOf then return ns.ColorOf(c) end
    if which == "death" then
        local p = GetColor("text", "red")
        return p.r, p.g, p.b
    end
    return 1, 1, 1
end

-- ============================================================
-- THE LINES
-- ============================================================
local anchor
local lines = {}

local function Anchor()
    if anchor then return anchor end
    anchor = CreateFrame("Frame", "ZacUIAlerts", UIParent)
    anchor:SetSize(A.SIZE.combat * 7, A.SIZE.combat + 14)
    anchor:SetFrameStrata("HIGH")
    anchor:EnableMouse(false)
    anchor:ClearAllPoints()
    anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 169)
    if ns.ApplyMover then ns.ApplyMover(MOVER) end
    return anchor
end
A.Frame = function() return anchor end

local function Layout()
    if not anchor then return end
    local off = 0
    for _, id in ipairs(A.ORDER) do
        local line = lines[id]
        if line and line:IsShown() then
            line:ClearAllPoints()
            line:SetPoint("TOP", anchor, "TOP", 0, -off)
            off = off + line:GetHeight() + GAP
        end
    end
end

local function Style(line)
    local size = A.SIZE[line.id]
    local spec = DB().font
    if ns.ApplyFontSpec then
        -- the picked face and outline; each line keeps its own size, scaled by the picked one
        local s = { }
        if type(spec) == "table" then for k, v in pairs(spec) do s[k] = v end end
        local base = tonumber(s.size) or A.FONT_DEFAULTS.size
        s.size = math.floor(size * base / A.FONT_DEFAULTS.size + 0.5)
        ns.ApplyFontSpec(line.text, s, A.FONT_DEFAULTS)
    elseif ns.HouseFont then
        ns.HouseFont(line.text, size, "OUTLINE")
    else
        line.text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "OUTLINE")
    end
end

local function OnUpdate(self, elapsed)
    self.t = self.t + elapsed
    local t, hold = self.t, self.hold
    local a
    if t < FADE_IN then a = t / FADE_IN
    elseif t < FADE_IN + hold then a = 1
    elseif t < FADE_IN + hold + FADE_OUT then a = 1 - (t - FADE_IN - hold) / FADE_OUT
    else
        self:Hide()
        return
    end
    self:SetAlpha(a)
end

local function Line(id)
    if lines[id] then return lines[id] end
    local f = CreateFrame("Frame", nil, Anchor())
    f.id = id
    f:SetFrameStrata("HIGH")
    f:EnableMouse(false)
    f:Hide()
    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER")
    f.text = fs
    f.t, f.hold = 0, A.HOLD[id]
    f:SetScript("OnUpdate", OnUpdate)
    f:SetScript("OnShow", Layout)
    f:SetScript("OnHide", Layout)
    lines[id] = f
    return f
end
A.Line = function(id) return lines[id] end

-- show `text` (plain) or `fmt` with one value (which may be hidden) on a line
function A.Show(id, r, g, b, text, fmt, value)
    local f = Line(id)
    Style(f)
    if fmt then f.text:SetFormattedText(fmt, value) else f.text:SetText(text) end
    f.text:SetTextColor(r or 1, g or 1, b or 1)
    -- as wide as its text: nothing cut (a hidden name measures as the game draws it)
    local size = A.SIZE[id]
    local w = f.text.GetStringWidth and f.text:GetStringWidth() or 0
    if Hidden(w) or type(w) ~= "number" then w = size * 7 end
    f:SetSize(math.max(size * 7, w + 20), size + 14)
    f.t = 0
    f:SetAlpha(0)
    f:Show()
    Layout()
    return f
end

-- ============================================================
-- COMBAT
-- ============================================================
function A.Combat(which, test)
    if not test and not A.On("combat") then return end
    local show = A.ShowOn()
    if not test and show ~= "both" and show ~= which then return end
    local r, g, b = A.Color(which)
    return A.Show("combat", r, g, b, A.Text(which))
end

-- ============================================================
-- GROUP DEATHS
-- ============================================================
local dead = {}       -- [unit token] = true while dead
local ticker

local function Units()
    local out = {}
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    if Hidden(n) then return out end
    n = tonumber(n) or 0
    if IsInRaid and IsInRaid() then
        for i = 1, n do out[#out + 1] = "raid" .. i end
    else
        for i = 1, math.max(0, n - 1) do out[#out + 1] = "party" .. i end
    end
    return out
end

function A.DeathText() return DB().deathText or "%s died" end

function A.Announce(unit, test)
    local name = test and "Zacw" or (UnitName and UnitName(unit))
    if name == nil then return end
    local r, g, b = A.Color("death")
    local fmt = A.DeathText()
    if not fmt:find("%%s") then fmt = "%s " .. fmt end
    local ok = pcall(A.Show, "death", r, g, b, nil, fmt, name)
    if not ok then return end
    if ns.PlaySoundSpec then
        local s = type(DB().sounds) == "table" and DB().sounds.death or nil
        ns.PlaySoundSpec(s, A.SOUND_DEATH, (not test) and "qol.alerts.death" or nil)
    end
    return true
end

function A.Poll()
    if not A.On("deaths") then return 0 end
    local said = 0
    local seen = {}
    for _, u in ipairs(Units()) do
        seen[u] = true
        if UnitExists and UnitExists(u) and not (UnitIsUnit and UnitIsUnit(u, "player")) then
            local isDead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(u)
            local feign = UnitIsFeignDeath and UnitIsFeignDeath(u)
            if not Hidden(isDead) and not Hidden(feign) then
                isDead = isDead and not feign and true or false
                if isDead and dead[u] == false then
                    if A.Announce(u) then said = said + 1 end
                end
                dead[u] = isDead
            end
        else
            dead[u] = nil
        end
    end
    for u in pairs(dead) do if not seen[u] then dead[u] = nil end end
    return said
end

local function StopPoll()
    if ticker then ticker:Cancel() ticker = nil end
    wipe(dead)
end
function A.PollRunning() return ticker ~= nil end

local function GroupChanged()
    if A.On("deaths") and IsInGroup and IsInGroup() then
        if not ticker then
            -- the roster now, learned quietly: someone already dead is not news
            wipe(dead)
            ticker = C_Timer.NewTicker(POLL, function() pcall(A.Poll) end)
            if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(ticker, "qol.alerts.deaths") end
            for _, u in ipairs(Units()) do
                local d = UnitIsDeadOrGhost and UnitIsDeadOrGhost(u)
                if not Hidden(d) then dead[u] = d and true or false end
            end
        end
    else
        StopPoll()
    end
end
A.GroupChanged = GroupChanged

-- ============================================================
-- INSTANCE RESET
-- ============================================================
-- the game's own words, "%s has been reset." -> a pattern
local function Pattern(gs)
    if type(gs) ~= "string" or gs == "" then return nil end
    -- the format's own %s / %d put aside, every magic character escaped,
    -- then the two put back as captures
    local p = gs:gsub("%%s", "\1"):gsub("%%d", "\2")
    p = p:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("\1", "(.+)"):gsub("\2", "%%d+")
    return "^" .. p
end
function A.ResetKind(msg)
    if type(msg) ~= "string" or Hidden(msg) then return nil end
    local ok = Pattern(_G.INSTANCE_RESET_SUCCESS)
    if ok and msg:find(ok) then return "ok" end
    local fail = Pattern(_G.INSTANCE_RESET_FAILED)
    if fail and msg:find(fail) then return "inside" end
    return nil
end
A.DEFAULT_RESET = "The instance has been reset - you can go back in."
local pendingReset = false
function A.OnSystem(msg)
    if not A.On("reset") then return false end
    local kind = A.ResetKind(msg)
    if not kind then return false end
    if not (IsInGroup and IsInGroup()) then return false end
    local raid = IsInRaid and IsInRaid()
    if kind == "inside" and raid then return false end
    if pendingReset then return false end      -- several dungeons reset at once: one line
    pendingReset = true
    C_Timer.After(0.3, function()
        pendingReset = false
        local text = DB().resetText
        if type(text) ~= "string" or text == "" then text = A.DEFAULT_RESET end
        if SendChatMessage then pcall(SendChatMessage, text, (IsInRaid and IsInRaid()) and "RAID" or "PARTY") end
    end)
    return true
end

-- ============================================================
-- SCREENSHOTS
-- ============================================================
function A.HideShot()
    if not A.On("noShot") then return end
    C_Timer.After(0, function()
        local f = _G.ActionStatus
        if f and f.Hide then f:Hide() end
    end)
end

-- ============================================================
-- EVENTS: armed per switch
-- ============================================================
local ev
local function OnEvent(_, event, ...)
    if event == "PLAYER_REGEN_DISABLED" then A.Combat("enter")
    elseif event == "PLAYER_REGEN_ENABLED" then A.Combat("leave")
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then GroupChanged()
    elseif event == "CHAT_MSG_SYSTEM" then A.OnSystem(...)
    elseif event == "SCREENSHOT_SUCCEEDED" or event == "SCREENSHOT_FAILED" then A.HideShot()
    end
end

local function Want(e, on)
    if on then pcall(ev.RegisterEvent, ev, e) else pcall(ev.UnregisterEvent, ev, e) end
end

function A.Apply()
    local combat, deaths, reset, shot = A.On("combat"), A.On("deaths"), A.On("reset"), A.On("noShot")
    if not (combat or deaths or reset or shot) then
        if ev then ev:UnregisterAllEvents() end
        StopPoll()
        return
    end
    if not ev then
        ev = CreateFrame("Frame")
        ev:SetScript("OnEvent", OnEvent)
    end
    Want("PLAYER_REGEN_DISABLED", combat)
    Want("PLAYER_REGEN_ENABLED", combat)
    Want("GROUP_ROSTER_UPDATE", deaths)
    Want("PLAYER_ENTERING_WORLD", deaths)
    Want("CHAT_MSG_SYSTEM", reset)
    Want("SCREENSHOT_SUCCEEDED", shot)
    Want("SCREENSHOT_FAILED", shot)
    GroupChanged()
    if anchor then for _, f in pairs(lines) do if f:IsShown() then Style(f) end end end
end
function A.Registered(e) return ev ~= nil and ev:IsEventRegistered(e) or false end

local function Live() if QoL.enabled then A.Apply() end end
A.Live = Live
if Allowed() then
    if ns.RegisterMover then
        ns.RegisterMover(MOVER, "Alerts", function() return anchor end, "CENTER", 0, 169, nil, { own = true })
    end
    local base = QoL.EnableAutomation
    function QoL.EnableAutomation(...)
        if base then base(...) end
        pcall(A.Apply)
    end
end

-- ============================================================
-- THE PAGE: Quality of life > Reminders
-- ============================================================
local function AddTab(page, tab, label, build)
    if ns.AddPageTab then return ns.AddPageTab(page, tab, label, build) end
    ns.PageTabs = ns.PageTabs or {}
    local list = ns.PageTabs[page] or {}
    ns.PageTabs[page] = list
    list[#list + 1] = { tab = tab, label = label, build = build }
end

local view = setmetatable({}, {
    __index = function(_, k) return DB()[k] end,
    __newindex = function(_, k, v) DB()[k] = v end,
})

local function ColorPick(L, label, which)
    local UI = ns.UI
    return UI.ColorPicker(L.current, { label = label,
        get = function() local r, g, b = A.Color(which) return r, g, b, 1 end,
        set = function(r, g, b) DB()[which .. "Color"] = { r = r, g = g, b = b, a = 1 } end })
end

AddTab("qol", "reminders", "Reminders", function(L)
    if not Allowed() then return end
    local UI = ns.UI
    local Kit = ns.CorePageKit
    local d = DB()
    local function Check(key, label, tip, onValue)
        local w = UI.Checkbox(L.current, label, A.On(key), function(v)
            if onValue then onValue(v) else d[key] = v and true or nil end
            Live()
            if ns.RefreshConfig then ns.RefreshConfig() end
        end, tip and { tooltip = tip } or nil)
        L:Row(w, 17)
        return w
    end

    L:Card("Combat")
    Check("combat", "Say when I enter and leave combat",
        "A short line in the middle of the screen as a fight starts and as it ends.")
    local kids = {}
    kids[#kids + 1] = UI.Field(L.current, "Show", function(h)
        return UI.Dropdown(h, { width = 180,
            items = function() return A.SHOW_ON end,
            selectedValue = function() return A.ShowOn() end,
            selected = function()
                for _, m in ipairs(A.SHOW_ON) do if m.value == A.ShowOn() then return m.text end end
                return A.SHOW_ON[1].text
            end,
            onSelect = function(v) d.combatShow = (v ~= "both") and v or nil end })
    end, { width = 180 })
    for _, which in ipairs({ "enter", "leave" }) do
        local lab = which == "enter" and "Entering" or "Leaving"
        kids[#kids + 1] = UI.Field(L.current, lab .. " text", function(h)
            return UI.EditBox(h, { width = 200, text = d[which .. "Text"] or "", hint = A.DEFAULT_TEXT[which],
                onChange = function(v) d[which .. "Text"] = (v and v ~= "") and v or nil end })
        end, { width = 200 })
        kids[#kids + 1] = ColorPick(L, lab .. " colour", which)
        kids[#kids + 1] = UI.Checkbox(L.current, lab .. ": my class colour", d[which .. "Class"] == true, function(v)
            d[which .. "Class"] = v and true or nil
        end)
    end
    kids[#kids + 1] = UI.Button(L.current, "Test", { width = 80,
        tooltip = "Shows the entering line, then the leaving line.",
        onClick = function()
            A.Combat("enter", true)
            C_Timer.After(1.9, function() A.Combat("leave", true) end)
        end })
    L:Dependent(kids, A.On("combat"), 1, nil, "Say when I enter and leave combat")
    L:EndCard()

    L:Card("Group deaths")
    Check("deaths", "Say when someone in my group dies",
        "\"Name died\" in the middle of the screen, with a sound, when a party or raid member dies. "
        .. "A hunter's Feign Death is not a death; your own is left out.")
    local dk = {}
    dk[#dk + 1] = ColorPick(L, "Colour", "death")
    if UI.SoundSpecPicker and ns.CustomAccess then
        local get, set = ns.CustomAccess(DB, "sounds", "death")
        dk[#dk + 1] = UI.SoundSpecPicker(L.current, { get = get, set = set, defaults = A.SOUND_DEATH,
            width = UI.CardInnerWidth and UI.CardInnerWidth(L) or nil })
    end
    dk[#dk + 1] = UI.Button(L.current, "Test", { width = 80,
        tooltip = "Shows the line with a sample name.",
        onClick = function() A.Announce(nil, true) end })
    L:Dependent(dk, A.On("deaths"), 1, nil, "Say when someone in my group dies")
    L:EndCard()

    L:Card("Where they show")
    if Kit then
        Kit.Font(L, "Font", function() return view end, "font", A.FONT_DEFAULTS,
            { sample = "Entering combat", after = function() Live() end,
              desc = "The combat line uses this size; a death line is half as big again." })
        if Kit.Mover and ns.MOVERS and ns.MOVERS[MOVER] then Kit.Mover(L, MOVER, "the alerts") end
    end
    L:EndCard()

    L:Card("Instance reset and screenshots")
    Check("reset", "Tell my group when I reset an instance",
        "After a reset that worked, one line in party or raid chat so everyone knows they can go back in.")
    local rt = UI.Field(L.current, "The line", function(h)
        return UI.EditBox(h, { width = 300, text = d.resetText or "", hint = A.DEFAULT_RESET,
            onChange = function(v) d.resetText = (v and v ~= "") and v or nil end })
    end, { width = 300 })
    L:Dependent({ rt }, A.On("reset"), 1, nil, "Tell my group when I reset an instance")
    Check("noShot", "Hide the \"Screen captured\" text",
        "The game's line in the middle of the screen after a screenshot. On unless you untick it.",
        function(v) if v then d.noShot = nil else d.noShot = false end end)
    L:EndCard()
end)

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("qol", "alert alerts combat entering leaving death died dead group party raid announce instance reset screenshot screen captured")
end
