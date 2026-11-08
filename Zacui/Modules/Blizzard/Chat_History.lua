-- Chat_History - the chat comes back after a /reload. The last N lines
-- of every chat window are written down when you log out or reload and
-- put back when you log in, dimmed (or stamped with the time they were
-- saved) so they read as old. Off by default (Chat > General).
-- Part of ZacUI; load order is set by the TOC (after Blz_Chat).
--
-- WHAT IS KEPT. Each window's last N messages (chat.historyLines, 100),
-- with the colour each was drawn in, so a guild line comes back green
-- and a say line white. The combat log window is never kept. A message
-- the game hides from addons (WoW Forever, in a fight) is skipped. The
-- lines go in ZacUICharDB.chatHistory (this character's bookkeeping,
-- outside every profile) and are read once, at the first login screen
-- after the save.
--
-- RESTORED LINES ARE NEVER SAVED AGAIN: each one is marked with an empty
-- colour span at its start (invisible), and the save skips marked lines,
-- so a second /reload does not dim them twice or stamp them twice.
--
-- THE PRIVACY COVER (Chat_Privacy): while it is on, whispers are not put
-- back at all, and guild and officer lines come back masked, the way the
-- cover shows them live.
--
-- COST: nothing between logins. One pass over the windows at logout, one
-- at the first PLAYER_ENTERING_WORLD.

local ADDON_NAME, ns = ...

local Chat = ns.Chat
local GetColor = ns.GetColor
local Hex = ns.Hex
local Print = ns.Print

local H = {}
ns.ChatHistory = H

local MARK = "|cff010203|r"          -- an empty coloured span: draws nothing
local MASK = "\226\128\162\226\128\162\226\128\162\226\128\162\226\128\162\226\128\162"   -- six bullets
local DEFAULT_LINES = 100
local DEFAULT_DIM = 60              -- percent of the colour the line had
local MIN_LINES, MAX_LINES = 20, 300

H.MARK, H.MASK = MARK, MASK
H.LOOKS = {
    { value = "dim", text = "Dimmed" },
    { value = "stamp", text = "With the time they were saved" },
    { value = "plain", text = "As they were" },
}

-- ============================================================
-- SETTINGS (chat.history*, nothing saved = off, 100 lines, dimmed to 60%)
-- ============================================================
local function DB()
    if Chat and Chat.DB then return Chat.DB() end
    ZacUIDB.chat = ZacUIDB.chat or {}
    return ZacUIDB.chat
end
function H.On() return DB().history == true end
function H.Lines()
    local n = tonumber(DB().historyLines) or DEFAULT_LINES
    return math.max(MIN_LINES, math.min(MAX_LINES, math.floor(n)))
end
function H.Look()
    local l = DB().historyLook
    if l == "stamp" or l == "plain" then return l end
    return "dim"
end
function H.Dim()
    local v = tonumber(DB().historyDim) or DEFAULT_DIM
    return math.max(30, math.min(100, v)) / 100
end
H.DEFAULT_LINES, H.DEFAULT_DIM = DEFAULT_LINES, DEFAULT_DIM

-- ============================================================
-- WHICH LINES ARE WHOSE (the privacy cover needs to know)
-- ============================================================
-- The game's own prefixes, turned into patterns: "%s whispers: " ->
-- "^.- whispers: ". Built once, from whatever globals this client has.
local function Pattern(g)
    if type(g) ~= "string" or g == "" then return nil end
    local p = g:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    p = p:gsub("%%%%s", ".-"):gsub("%%%%d", "%%d+")
    return "^" .. p
end
local function Patterns(names)
    local out = {}
    for _, n in ipairs(names) do
        local p = Pattern(_G[n])
        if p then out[#out + 1] = p end
    end
    return out
end
local WHISPER_PATTERNS, GUILD_PATTERNS
local function EnsurePatterns()
    if WHISPER_PATTERNS then return end
    WHISPER_PATTERNS = Patterns({ "CHAT_WHISPER_GET", "CHAT_WHISPER_INFORM_GET", "CHAT_BN_WHISPER_GET",
        "CHAT_BN_WHISPER_INFORM_GET" })
    GUILD_PATTERNS = Patterns({ "CHAT_GUILD_GET", "CHAT_OFFICER_GET" })
    -- English, when a client has none of the globals
    if #WHISPER_PATTERNS == 0 then WHISPER_PATTERNS = { "^.- whispers: ", "^To .-: " } end
    if #GUILD_PATTERNS == 0 then GUILD_PATTERNS = { "^%[Guild%] .-: ", "^%[Officer%] .-: " } end
end
local function PrefixEnd(text, pats)
    for _, p in ipairs(pats) do
        local _, e = text:find(p)
        if e then return e end
    end
    return nil
end
function H.IsWhisper(text)
    EnsurePatterns()
    return PrefixEnd(text, WHISPER_PATTERNS) ~= nil
end
-- "[Guild] Name: what they said" -> "[Guild] Name: ••••••", or nil when
-- the line is not a guild or officer line
function H.MaskGuild(text)
    EnsurePatterns()
    local e = PrefixEnd(text, GUILD_PATTERNS)
    if not e then return nil end
    return text:sub(1, e) .. MASK
end

local function PrivacyOn()
    local P = ns.ChatPrivacy
    return P and P.On and P.On() or false
end

-- ============================================================
-- THE WINDOWS
-- ============================================================
local function IsCombatLog(cf)
    return _G.COMBATLOG ~= nil and cf == _G.COMBATLOG
end

-- every ordinary chat window by name (the pop-out whisper windows are
-- temporary and not kept)
local function EachWindow(fn)
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local name = "ChatFrame" .. i
        local cf = _G[name]
        if cf and not IsCombatLog(cf) and cf.GetNumMessages and cf.GetMessageInfo then fn(cf, name) end
    end
end

-- the last N lines of one window, oldest first: { text, r, g, b }
function H.Collect(cf, n)
    local out = {}
    local total = cf:GetNumMessages() or 0
    if type(total) ~= "number" or total <= 0 then return out end
    local first = math.max(1, total - n + 1)
    for i = first, total do
        local ok, text, r, g, b = pcall(cf.GetMessageInfo, cf, i)
        if ok and type(text) == "string" and not (ns.IsSecret and (ns.IsSecret(text) or ns.IsSecret(r)))
            and text:sub(1, #MARK) ~= MARK and text ~= "" then
            out[#out + 1] = { text,
                type(r) == "number" and r or nil, type(g) == "number" and g or nil, type(b) == "number" and b or nil }
        end
    end
    return out
end

-- written at logout / reload
function H.Save()
    if type(ZacUICharDB) ~= "table" then return false end
    if not H.On() then
        ZacUICharDB.chatHistory = nil
        return false
    end
    local n = H.Lines()
    local frames, any = {}, false
    EachWindow(function(cf, name)
        local lines = H.Collect(cf, n)
        if #lines > 0 then frames[name] = lines any = true end
    end)
    ZacUICharDB.chatHistory = any and { at = time(), frames = frames } or nil
    return any
end

-- one saved line the way it comes back: text and colour
function H.Dress(line, look, dim, stamp, privacy)
    local text, r, g, b = line[1], line[2] or 1, line[3] or 1, line[4] or 1
    if privacy then
        if H.IsWhisper(text) then return nil end
        local masked = H.MaskGuild(text)
        if masked then text = masked end
    end
    if look == "dim" then
        r, g, b = r * dim, g * dim, b * dim
    elseif look == "stamp" and stamp then
        text = "|cff" .. Hex(GetColor("text", "gray")) .. stamp .. "|r " .. text
    end
    return MARK .. text, r, g, b
end

-- put a window's saved lines back (the lines as H.Collect made them)
function H.Restore(cf, lines, at)
    local look, dim = H.Look(), H.Dim()
    local stamp = at and date and date("%H:%M", at) or nil
    local privacy = PrivacyOn()
    local n = 0
    for _, line in ipairs(lines) do
        local text, r, g, b = H.Dress(line, look, dim, stamp, privacy)
        if text then
            cf:AddMessage(text, r, g, b)
            n = n + 1
        end
    end
    return n
end

local restored = false
function H.RestoreAll()
    if restored then return 0 end
    restored = true
    local h = type(ZacUICharDB) == "table" and ZacUICharDB.chatHistory
    if type(h) ~= "table" or type(h.frames) ~= "table" then return 0 end
    -- read once: a reload with the feature now off throws the old lines away
    ZacUICharDB.chatHistory = nil
    if not H.On() then return 0 end
    local n = 0
    EachWindow(function(cf, name)
        local lines = h.frames[name]
        if type(lines) == "table" and #lines > 0 then n = n + H.Restore(cf, lines, h.at) end
    end)
    return n
end

-- the Chat page's Preview button: three made-up lines, dressed the way
-- the saved ones come back, into the window you are looking at
H.SAMPLE = {
    { "|Hchannel:GUILD|h[Guild]|h |Hplayer:Zaccw|h[Zaccw]|h: pulling in 10", 0.25, 1, 0.25 },
    { "|Hplayer:Healbot|h[Healbot]|h whispers: innervate is yours", 1, 0.5, 1 },
    { "|Hplayer:Zaccw|h[Zaccw]|h: ok", 1, 1, 1 },
}
function H.Preview(cf)
    cf = cf or (SELECTED_DOCK_FRAME and SELECTED_DOCK_FRAME.AddMessage and SELECTED_DOCK_FRAME) or DEFAULT_CHAT_FRAME
    if not (cf and cf.AddMessage) then return 0 end
    return H.Restore(cf, H.SAMPLE, time())
end

-- ============================================================
-- EVENTS: the save at logout, the restore at the first world
-- ============================================================
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGOUT" then
        pcall(H.Save)
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        -- a beat after the world, so the login lines land first and the
        -- windows are the ones the saved layout restored
        C_Timer.After(0.5, function() pcall(H.RestoreAll) end)
    end
end)

-- ============================================================
-- THE CHAT PAGE: a card on General
-- ============================================================
local function AddTab(page, tab, label, build)
    if ns.AddPageTab then return ns.AddPageTab(page, tab, label, build) end
    ns.PageTabs = ns.PageTabs or {}
    local list = ns.PageTabs[page] or {}
    ns.PageTabs[page] = list
    list[#list + 1] = { tab = tab, label = label, build = build }
end

AddTab("chat", "general", "General", function(L)
    if ns.FeatureOn and not ns.FeatureOn("chat_history") then return end
    local UI = ns.UI
    local d = DB()
    L:Card("Chat history")
    local on = UI.Checkbox(L.current, "Keep the chat across /reload", H.On(), function(v)
        d.history = v and true or nil
        if ns.RefreshConfig then ns.RefreshConfig() end
    end, { tooltip = "The last lines of every chat window are saved when you log out or reload and come back "
        .. "when you log in, so a /reload mid-raid does not wipe what was said. The combat log is never kept. "
        .. "While the privacy cover is on, whispers are not brought back and guild lines come back masked." })
    L:Row(on, 17)
    local lines = UI.Slider(L.current, { width = 220, min = MIN_LINES, max = MAX_LINES, step = 10,
        value = H.Lines(), label = "Lines per window",
        format = function(v) return v .. " lines" end,
        onChange = function(v) d.historyLines = (v ~= DEFAULT_LINES) and v or nil end })
    local function LookText(v)
        for _, it in ipairs(H.LOOKS) do if it.value == v then return it.text end end
        return H.LOOKS[1].text
    end
    local look = UI.Field(L.current, "Restored lines look", function(h)
        return UI.Dropdown(h, { width = 240,
            items = function() return H.LOOKS end,
            selectedValue = function() return H.Look() end,
            selected = function() return LookText(H.Look()) end,
            onSelect = function(v)
                d.historyLook = (v ~= "dim") and v or nil
                if ns.RefreshConfig then ns.RefreshConfig() end
            end })
    end, { width = 240 })
    local dim = UI.Slider(L.current, { width = 220, min = 30, max = 100, step = 5,
        value = math.floor(H.Dim() * 100 + 0.5), label = "Dimmed to",
        format = function(v) return v .. "%" end,
        onChange = function(v) d.historyDim = (v ~= DEFAULT_DIM) and v or nil end })
    local test = UI.Button(L.current, "Preview", { width = 90,
        tooltip = "Puts three made-up lines into the chat window you are looking at, dressed the way "
            .. "saved lines come back.",
        onClick = function() H.Preview() end })
    L:Dependent({ lines, look, dim, test }, H.On(), 1, nil, "Keep the chat across /reload")
    if H.Look() ~= "dim" then UI.SetEnabled(dim, false, H.On() and "Only used when saved lines come back dimmed." or 'Needs "Keep the chat across /reload" turned on.') end
    L:Desc("Dimmed lines keep their channel colour, darker. The time stamp is the time of the reload "
        .. "or logout they were saved at.")
    L:EndCard()
end)

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("chat", "history reload restore keep lines saved old messages persist")
end
