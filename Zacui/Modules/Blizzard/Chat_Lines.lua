-- Chat_Lines - what each chat line says, three ways (Chat > Text):
--   * short channel names: "[Party]" -> "[P]", "[Raid Leader]" -> "[RL]",
--     "[Guild]" -> "[G]", "[2. Trade - City]" -> "[2]" (or "[T]", or
--     "[2.T]"); every abbreviation editable;
--   * time stamps: the game's own time stamp setting picked here (its
--     formats), and "stamp every line" for the lines the game never
--     stamps (addon messages and the like), in a colour if you like;
--   * class-coloured names: names of people in your group or raid typed
--     INSIDE a message take their class colour (the sender's name is
--     already coloured by the game).
-- All off by default; nothing saved = the chat exactly as before.
-- Part of ZacUI; load order is set by the TOC (after Chat_Links).
--
-- WHERE THE WORDS COME FROM. The channel names are read from the game's
-- own line formats (CHAT_PARTY_GET, CHAT_RAID_LEADER_GET...), so they
-- match in the client's language; numbered channels are matched on the
-- channel link itself.
--
-- HOW A LINE IS CHANGED.
--   Names in a message: a chat filter (ChatFrame_AddMessageEventFilter)
--   on the player chat events, the message handed back with the names
--   coloured; links, colours and icons inside it are left alone. Works on
--   every game.
--   Channel names and stamping every line: the finished line is rewritten
--   on its way into each chat window (the window's AddMessage, wrapped).
--   That is Classic Era and TBC only: on WoW Forever and Retail the chat's
--   drawing is secure code (wrapping it would break the game's whisper
--   reply in a fight), so those two stay the game's there. The time stamp
--   format picker is the game's own setting and works everywhere.
--   The combat log window is never wrapped; nor is anything while Prat
--   (which does its own) is loaded.
--
-- SECRET-SAFE: a message or line the game hides from addons (Forever, in
-- a fight) is passed through whole, never read.
--
-- COST: a filter call per player chat line while names are on; one pass
-- over a line's channel tag per chat line while the rewrite is on.

local ADDON_NAME, ns = ...

local Chat = ns.Chat
local GetColor = ns.GetColor

local CLn = {}
ns.ChatLines = CLn

local SHORT_ID, STAMP_ID, NAMES_ID = "chat_short_names", "chat_stamps", "chat_name_colors"

local function Modern()
    if ns.ModernClient then return ns.ModernClient() and true or false end
    return _G.ZACUI_MODERN and true or false
end
local function Secret(v) return ns.IsSecret and ns.IsSecret(v) or false end
local function EachPlain(text, fn)
    if ns.ChatText and ns.ChatText.EachPlain then return ns.ChatText.EachPlain(text, fn) end
    return fn(text)
end

-- ============================================================
-- SETTINGS (ZacUIDB.chat; nothing saved = off)
--   shortNames (bool)   shortWorld ("number" default / "letters" / "both" / "keep")
--   shortAbbrev { [TYPE] = "P" }   stampAll (bool)   stampColor (colour)
--   nameColors (bool)
-- ============================================================
local function DB()
    if Chat and Chat.DB then return Chat.DB() end
    ZacUIDB.chat = ZacUIDB.chat or {}
    return ZacUIDB.chat
end
CLn.DB = DB
local function Allowed(id) return not (ns.FeatureOn and not ns.FeatureOn(id)) end
-- the line rewrite exists on this client
function CLn.CanRewrite() return not Modern() end
function CLn.ShortOn() return Allowed(SHORT_ID) and CLn.CanRewrite() and DB().shortNames == true end
function CLn.StampAllOn() return Allowed(STAMP_ID) and CLn.CanRewrite() and DB().stampAll == true end
function CLn.NamesOn() return Allowed(NAMES_ID) and DB().nameColors == true end
function CLn.World()
    local w = DB().shortWorld
    if w == "letters" or w == "both" or w == "keep" then return w end
    return "number"
end

-- ============================================================
-- SHORT CHANNEL NAMES
-- ============================================================
CLn.TYPES = {
    { key = "PARTY", short = "P", label = "Party" },
    { key = "PARTY_LEADER", short = "PL", label = "Party leader" },
    { key = "RAID", short = "R", label = "Raid" },
    { key = "RAID_LEADER", short = "RL", label = "Raid leader" },
    { key = "RAID_WARNING", short = "RW", label = "Raid warning" },
    { key = "GUILD", short = "G", label = "Guild" },
    { key = "OFFICER", short = "O", label = "Officer" },
    { key = "INSTANCE_CHAT", short = "I", label = "Instance" },
    { key = "INSTANCE_CHAT_LEADER", short = "IL", label = "Instance leader" },
}
local BY_KEY = {}
for _, t in ipairs(CLn.TYPES) do BY_KEY[t.key] = t end

function CLn.Abbrev(key)
    local a = DB().shortAbbrev
    local v = type(a) == "table" and a[key]
    if type(v) == "string" and v ~= "" then return v end
    local t = BY_KEY[key]
    return t and t.short or key
end

-- the game's own words for each tag ("Party", "Raid Leader"...), read
-- from its line formats; English when the client has none
local ENGLISH = { PARTY = "Party", PARTY_LEADER = "Party Leader", RAID = "Raid", RAID_LEADER = "Raid Leader",
    RAID_WARNING = "Raid Warning", GUILD = "Guild", OFFICER = "Officer", INSTANCE_CHAT = "Instance",
    INSTANCE_CHAT_LEADER = "Instance Leader" }
local labels      -- [label text] = key
local function Labels()
    if labels then return labels end
    labels = {}
    for _, t in ipairs(CLn.TYPES) do
        local fmt = _G["CHAT_" .. t.key .. "_GET"]
        local word = type(fmt) == "string" and fmt:match("%[(.-)%]") or nil
        if not word or word == "" or word:find("%%") then word = ENGLISH[t.key] end
        if not labels[word] then labels[word] = t.key end
    end
    return labels
end
CLn.Labels = Labels
function CLn.ResetLabels() labels = nil end

local function Escape(s) return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end

-- a world channel's letters: "Trade - City" -> "T", "LocalDefense" ->
-- "LD", "LookingForGroup" -> "LFG"; one that would read as a group tag
-- ("General" -> "G", the guild's) takes two letters ("Ge")
function CLn.Letters(name)
    local base = name:match("^(.-)%s+%-%s+") or name
    base = base:gsub("^%s+", ""):gsub("%s+$", "")
    local caps = base:gsub("[^%u]", "")
    if caps == "" then
        caps = base:match("^[%z\1-\127\194-\244][\128-\191]*") or base:sub(1, 1)
        caps = caps:upper()
    end
    if #caps == 1 then
        for _, t in ipairs(CLn.TYPES) do
            if CLn.Abbrev(t.key) == caps then
                local two = base:match("^[%a][%a]")
                if two then caps = two:sub(1, 1):upper() .. two:sub(2, 2):lower() end
                break
            end
        end
    end
    return caps
end

-- "2. Trade - City" (the number and the name), or nil
local function WorldParts(label)
    local num, name = label:match("^(%d+)%.%s*(.*)$")
    return num, name
end
function CLn.WorldTag(label)
    local num, name = WorldParts(label)
    if not num then return nil end
    local mode = CLn.World()
    if mode == "keep" then return nil end
    if mode == "number" then return num end
    local letters = (name and name ~= "") and CLn.Letters(name) or num
    if mode == "letters" then return letters end
    return num .. "." .. letters
end

-- every channel tag in a finished line, shortened
function CLn.Shorten(text)
    if type(text) ~= "string" or Secret(text) then return text end
    if not text:find("[", 1, true) then return text end
    local map = Labels()
    local out = text:gsub("(|Hchannel:([^|]*)|h)%[(.-)%](|h)", function(open, target, label, close)
        local key = map[label]
        if key then return open .. "[" .. CLn.Abbrev(key) .. "]" .. close end
        local tag = CLn.WorldTag(label)
        if tag then return open .. "[" .. tag .. "]" .. close end
        return nil
    end)
    -- tags the game writes without a channel link ("[Raid Warning] Name: "),
    -- only at the front of the line (after a time stamp)
    for label, key in pairs(map) do
        local fmt = _G["CHAT_" .. key .. "_GET"]
        if type(fmt) ~= "string" or not fmt:find("|Hchannel", 1, true) then
            local pat = "^([%d:%s%.APMapm]*)%[" .. Escape(label) .. "%]"
            local hit
            out, hit = out:gsub(pat, function(pre) return pre .. "[" .. CLn.Abbrev(key) .. "]" end, 1)
            if hit > 0 then break end
        end
    end
    return out
end

-- ============================================================
-- TIME STAMPS
-- ============================================================
-- the formats the game's own setting takes (the values it stores)
CLn.STAMPS = {
    { value = "none", text = "No time stamps" },
    { value = "%I:%M ", text = "03:27" },
    { value = "%I:%M:%S ", text = "03:27:32" },
    { value = "%I:%M %p ", text = "03:27 PM" },
    { value = "%I:%M:%S %p ", text = "03:27:32 PM" },
    { value = "%H:%M ", text = "15:27" },
    { value = "%H:%M:%S ", text = "15:27:32" },
}
local function ReadStamp()
    local f = (C_CVar and C_CVar.GetCVar) or _G.GetCVar
    if not f then return nil end
    local ok, v = pcall(f, "showTimestamps")
    if ok and type(v) == "string" then return v end
    return nil
end
-- the format in use now, or nil for none
function CLn.StampFormat()
    local v
    if not Modern() and type(_G.CHAT_TIMESTAMP_FORMAT) == "string" then v = _G.CHAT_TIMESTAMP_FORMAT
    else v = ReadStamp() end
    if type(v) ~= "string" or v == "" or v == "none" then return nil end
    return v
end
-- the game's own setting, as stored ("none" when off or unknown)
function CLn.GameStamp()
    local v = ReadStamp()
    if type(v) ~= "string" or v == "" then return "none" end
    return v
end
function CLn.SetGameStamp(v)
    if type(v) ~= "string" or v == "" then return false end
    local done
    if ns.CVar and ns.CVar.Set then
        done = ns.CVar.Set("showTimestamps", v, "chat")
    else
        local f = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
        done = f and pcall(f, "showTimestamps", v) or false
    end
    -- Classic reads the format from this global (its own options page
    -- writes it the same way); the modern client's is left to the game
    if not Modern() then _G.CHAT_TIMESTAMP_FORMAT = (v ~= "none") and v or nil end
    return done and true or false
end

local function Stamp(fmt, when)
    when = when or (time and time()) or 0
    if type(BetterDate) == "function" then
        local ok, s = pcall(BetterDate, fmt, when)
        if ok and type(s) == "string" then return s end
    end
    if type(date) == "function" then
        local ok, s = pcall(date, fmt, when)
        if ok and type(s) == "string" then return s end
    end
    return nil
end
CLn.Stamp = Stamp

function CLn.StampColor()
    local c = DB().stampColor
    if type(c) == "table" and ns.ColorOf then
        local r, g, b = ns.ColorOf(c)
        return r, g, b
    end
    return nil
end
local function Hex(r, g, b)
    return string.format("%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local HISTORY_MARK = "|cff010203|r"
-- a finished line: the stamp put in front when it has none (and
-- coloured, when a colour is set - the game's own stamps too)
function CLn.StampLine(text)
    if type(text) ~= "string" or Secret(text) then return text end
    local fmt = CLn.StampFormat()
    if not fmt then return text end
    local mark = ns.ChatHistory and ns.ChatHistory.MARK or HISTORY_MARK
    if text:sub(1, #mark) == mark then return text end   -- a restored line keeps its own time
    local s = Stamp(fmt)
    if not s or s == "" then return text end
    local r, g, b
    if CLn.StampAllOn() then r, g, b = CLn.StampColor() end
    local lead = text:match("^|c%x%x%x%x%x%x%x%x") or ""
    local rest = text:sub(#lead + 1)
    if rest:sub(1, #s) == s then
        -- the game stamped it already: only the colour
        if r and lead == "" then return "|cff" .. Hex(r, g, b) .. s .. "|r" .. rest:sub(#s + 1) end
        return text
    end
    if r then s = "|cff" .. Hex(r, g, b) .. s .. "|r" end
    return s .. text
end

-- ============================================================
-- THE LINE REWRITE (Classic Era / TBC): each window's AddMessage, wrapped
-- ============================================================
local orig = setmetatable({}, { __mode = "k" })
local function Rewrite(text)
    if CLn.ShortOn() then text = CLn.Shorten(text) end
    if CLn.StampAllOn() then text = CLn.StampLine(text) end
    return text
end
CLn.Rewrite = Rewrite

local function Wrapped(self, text, ...)
    local o = orig[self]
    if type(text) == "string" and not Secret(text) and (CLn.ShortOn() or CLn.StampAllOn()) then
        local ok, out = pcall(Rewrite, text)
        if ok and type(out) == "string" then text = out end
    end
    if o then return o(self, text, ...) end
end

local function WrapFrame(cf)
    if not cf or orig[cf] or type(cf.AddMessage) ~= "function" then return end
    if _G.COMBATLOG ~= nil and cf == _G.COMBATLOG then return end
    orig[cf] = cf.AddMessage
    cf.AddMessage = Wrapped
end
CLn.Wrapped = function(cf) return orig[cf] ~= nil end

local tempHooked = false
local function WrapAll()
    if Modern() or _G.Prat ~= nil then return end
    for _, name in ipairs(CHAT_FRAMES or {}) do WrapFrame(_G[name]) end
    if not tempHooked and type(FCF_OpenTemporaryWindow) == "function" then
        tempHooked = true
        hooksecurefunc("FCF_OpenTemporaryWindow", function()
            if CLn.ShortOn() or CLn.StampAllOn() then C_Timer.After(0, WrapAll) end
        end)
    end
end

-- ============================================================
-- CLASS-COLOURED NAMES IN A MESSAGE
-- ============================================================
local roster, rosterDirty = {}, true
local function Rebuild()
    rosterDirty = false
    wipe(roster)
    local function Add(unit)
        if not (UnitExists and UnitExists(unit)) then return end
        local name = UnitName(unit)
        if type(name) ~= "string" or Secret(name) or name == "" then return end
        local _, class = UnitClass(unit)
        if type(class) ~= "string" or Secret(class) then return end
        roster[name:lower()] = class
    end
    Add("player")
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do Add("raid" .. i) end
    elseif IsInGroup and IsInGroup() then
        for i = 1, 4 do Add("party" .. i) end
    end
end
CLn.Roster = function() if rosterDirty then Rebuild() end return roster end
function CLn.RosterDirty() rosterDirty = true end

local function ColourWord(w)
    local class = roster[w:lower()]
    if not class then return nil end
    local r, g, b = 0.6, 0.6, 0.6
    if ns.ClassColor then r, g, b = ns.ClassColor(class) end
    return "|cff" .. Hex(r, g, b) .. w .. "|r"
end
function CLn.ColourNames(text)
    if type(text) ~= "string" or Secret(text) then return nil end
    if rosterDirty then Rebuild() end
    if next(roster) == nil then return nil end
    local out = EachPlain(text, function(s)
        return (s:gsub("[%a\128-\255][%a\128-\255]+", function(w) return ColourWord(w) end))
    end)
    if out == text then return nil end
    return out
end

CLn.EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_CHANNEL", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
}
local function NameFilter(self, event, msg, ...)
    if not CLn.NamesOn() then return end
    if type(msg) ~= "string" or Secret(msg) then return end
    local out = CLn.ColourNames(msg)
    if out then return false, out, ... end
end
CLn.NameFilter = NameFilter

local filtersIn = false
local rosterEv
local function Apply()
    if CLn.ShortOn() or CLn.StampAllOn() then WrapAll() end
    if CLn.NamesOn() then
        if not filtersIn and type(ChatFrame_AddMessageEventFilter) == "function" then
            filtersIn = true
            for _, e in ipairs(CLn.EVENTS) do ChatFrame_AddMessageEventFilter(e, NameFilter) end
        end
        if not rosterEv then
            rosterEv = CreateFrame("Frame")
            rosterEv:SetScript("OnEvent", function() rosterDirty = true end)
        end
        rosterEv:RegisterEvent("GROUP_ROSTER_UPDATE")
        rosterEv:RegisterEvent("PLAYER_ENTERING_WORLD")
        rosterDirty = true
    elseif rosterEv then
        rosterEv:UnregisterAllEvents()
    end
end
CLn.Apply = Apply

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    Apply()
end)

-- ============================================================
-- THE PREVIEW: a sample line as the chat would show it now
-- ============================================================
-- (the Chat page's preview strip and the cards below; the samples are
-- written the way the game writes them, "[Guild] [Zaccw]: ...", so the
-- tag is matched on its words)
function CLn.Preview(text)
    if type(text) ~= "string" then return text end
    local out = text
    if CLn.ShortOn() then
        local map = Labels()
        out = out:gsub("^%[(.-)%]", function(label)
            local key = map[label]
            if key then return "[" .. CLn.Abbrev(key) .. "]" end
            local tag = CLn.WorldTag(label)
            if tag then return "[" .. tag .. "]" end
            return nil
        end, 1)
    end
    if CLn.NamesOn() then
        -- the sample names, coloured as group members would be
        local SAMPLE = { zaccw = "WARRIOR", thallen = "PRIEST", mograine = "PALADIN", ashbringer = "WARRIOR" }
        local head, body = out:match("^(.-%]:%s)(.*)$")
        if head then
            out = head .. EachPlain(body, function(s)
                return (s:gsub("%a%a+", function(w)
                    local c = SAMPLE[w:lower()]
                    if not c then return nil end
                    local r, g, b = 0.6, 0.6, 0.6
                    if ns.ClassColor then r, g, b = ns.ClassColor(c) end
                    return "|cff" .. Hex(r, g, b) .. w .. "|r"
                end))
            end)
        end
    end
    -- the game stamps what people say whenever its setting is on
    if CLn.StampFormat() then out = CLn.StampLine(out) end
    return out
end
function CLn.PreviewOn() return CLn.ShortOn() or CLn.NamesOn() or CLn.StampFormat() ~= nil end

-- ============================================================
-- THE CHAT PAGE: cards on Text
-- ============================================================
local function AddTab(page, tab, label, build)
    if ns.AddPageTab then return ns.AddPageTab(page, tab, label, build) end
    ns.PageTabs = ns.PageTabs or {}
    local list = ns.PageTabs[page] or {}
    ns.PageTabs[page] = list
    list[#list + 1] = { tab = tab, label = label, build = build }
end

local function SampleRow(L, UI, lines)
    local w = math.max(160, ((UI.CardInnerWidth and UI.CardInnerWidth(L)) or 400) - 40)
    local host = UI.Holder(L.current)
    host.fs = {}
    for i = 1, #lines do
        local fs = UI.Font(host, UI.F.SMALL, { width = w, justify = "LEFT" })
        if i == 1 then fs:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        else fs:SetPoint("TOPLEFT", host.fs[i - 1], "BOTTOMLEFT", 0, -3) end
        host.fs[i] = fs
    end
    -- each line as tall as it wraps to; true when the height changed
    function host.Refresh()
        local h = 0
        for i, l in ipairs(lines) do
            local fs = host.fs[i]
            fs:SetText(CLn.Preview(l[1]))
            fs:SetTextColor(l[2], l[3], l[4], 1)
            local lh = math.max(12, math.ceil(fs:GetStringHeight() or 12))
            fs:SetHeight(lh)
            h = h + lh + (i > 1 and 3 or 0)
        end
        h = h + 2
        local was = host:GetHeight()
        host:SetSize(w, h)
        return math.abs((was or 0) - h) > 0.5
    end
    host.Refresh()
    return host
end
local SAMPLES = {
    { "[Guild] [Zaccw]: pulling in 10", 0.25, 1, 0.25 },
    { "[Raid Leader] [Thallen]: Mograine left", 1, 0.28, 0.04 },
    { "[2. Trade - City] [Healbot]: LF heals", 1, 0.75, 0.75 },
}

AddTab("chat", "text", "Text", function(L)
    local short, stamps, names = Allowed(SHORT_ID), Allowed(STAMP_ID), Allowed(NAMES_ID)
    if not (short or stamps or names) then return end
    local UI = ns.UI
    local Kit = ns.CorePageKit
    local d = DB()
    local sample
    local function Changed()
        Apply()
        -- a sample line that now wraps differently: the page is laid out again
        if sample and sample.Refresh() and ns.RefreshConfig then ns.RefreshConfig() end
        if ns.SettingsChanged then ns.SettingsChanged("chat.lines") end
    end

    L:Card("What each line says")
    sample = SampleRow(L, UI, SAMPLES)
    L:Add(sample, 6)

    if short then
        local can = CLn.CanRewrite()
        local on = UI.Checkbox(L.current, "Short channel names", CLn.ShortOn(), function(v)
            d.shortNames = v and true or nil
            Changed()
            if ns.RefreshConfig then ns.RefreshConfig() end
        end, { tooltip = "\"[Party]\" reads \"[P]\", \"[Raid Leader]\" \"[RL]\", \"[Guild]\" \"[G]\", and world "
            .. "channels as their number (or letters). Every abbreviation is yours to change below." })
        L:Row(on, 17)
        if not can then
            UI.SetEnabled(on, false, UI.WHY_FLAVOR)
            L:Desc("Not on this game: its chat is drawn by secure code ZacUI does not rewrite.")
        else
            local kids = {}
            local WORLD = { { value = "number", text = "Their number: [2]" }, { value = "letters", text = "Letters: [T]" },
                { value = "both", text = "Both: [2.T]" }, { value = "keep", text = "As the game writes them" } }
            kids[#kids + 1] = UI.Field(L.current, "World channels", function(h)
                return UI.Dropdown(h, { width = 220, items = function() return WORLD end,
                    selectedValue = function() return CLn.World() end,
                    selected = function()
                        for _, it in ipairs(WORLD) do if it.value == CLn.World() then return it.text end end
                        return WORLD[1].text
                    end,
                    onSelect = function(v) d.shortWorld = (v ~= "number") and v or nil Changed() end })
            end, { width = 220 })
            for _, t in ipairs(CLn.TYPES) do
                kids[#kids + 1] = UI.Field(L.current, t.label, function(h)
                    return UI.EditBox(h, { width = 80, text = CLn.Abbrev(t.key),
                        onChange = function(text)
                            text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
                            if type(d.shortAbbrev) ~= "table" then d.shortAbbrev = {} end
                            d.shortAbbrev[t.key] = (text ~= "" and text ~= t.short) and text or nil
                            if next(d.shortAbbrev) == nil then d.shortAbbrev = nil end
                            Changed()
                        end })
                end, { width = 120 })
            end
            L:Dependent(kids, CLn.ShortOn(), 3, nil, "Short channel names")
        end
    end

    if names then
        local nc = UI.Checkbox(L.current, "Colour group members' names in messages", CLn.NamesOn(), function(v)
            d.nameColors = v and true or nil
            Changed()
        end, { tooltip = "A name of someone in your party or raid typed inside a message takes their class "
            .. "colour (\"heal Thallen\"). The sender's own name is the game's, coloured as it already is." })
        L:Row(nc, 17)
    end
    L:EndCard()

    if stamps then
        L:Card("Time stamps")
        local function TextOf(v)
            for _, it in ipairs(CLn.STAMPS) do if it.value == v then return it.text end end
            return v
        end
        local fmt = UI.Field(L.current, "The game's time stamps", function(h)
            return UI.Dropdown(h, { width = 220, items = function() return CLn.STAMPS end,
                selectedValue = function() return CLn.GameStamp() end,
                selected = function() return TextOf(CLn.GameStamp()) end,
                onSelect = function(v) CLn.SetGameStamp(v) Changed() end })
        end, { width = 220 })
        L:Add(fmt, 6)
        L:Desc("The game's own setting (also under Interface > Social), written here. New lines show it."
            .. (Modern() and " On this game it may take a /reload to show." or ""))
        if CLn.CanRewrite() then
            local all = UI.Checkbox(L.current, "Stamp every line", CLn.StampAllOn(), function(v)
                d.stampAll = v and true or nil
                Changed()
                if ns.RefreshConfig then ns.RefreshConfig() end
            end, { tooltip = "The game stamps what people say but not every line - addon messages and some "
                .. "notices come without one. With this on, every line gets the stamp, in the format above." })
            L:Row(all, 17)
            local kids = {}
            kids[#kids + 1] = UI.ColorPicker(L.current, { label = "Stamp colour",
                get = function()
                    local r, g, b = CLn.StampColor()
                    if r then return r, g, b, 1 end
                    local p = GetColor("text", "gray") return p.r, p.g, p.b, 1
                end,
                set = function(r, g, b) d.stampColor = { r = r, g = g, b = b, a = 1 } Changed() end,
                default = function() local p = GetColor("text", "gray") return p.r, p.g, p.b, 1 end,
                reset = function() d.stampColor = nil Changed() end })
            L:Dependent(kids, CLn.StampAllOn(), 1, nil, "Stamp every line")
            L:Desc("Blank colour = the line's own. The colour is for every stamp while this is on.")
        else
            L:Desc("Stamping every line is not on this game: its chat is drawn by secure code ZacUI does not rewrite.")
        end
        L:EndCard()
    end
end)

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("chat", "short channel names abbreviate abbreviation party raid guild officer trade general "
        .. "timestamp timestamps time stamp clock class colour color names")
end
