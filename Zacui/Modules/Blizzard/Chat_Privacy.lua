-- Chat_Privacy - the streaming privacy cover: one switch that masks what
-- guild, officer and whisper lines SAY in the chat windows ("[Guild]
-- Zaccw: ••••••"), so a stream never shows them, with a small "PRIVACY
-- ON" tag in the chat's tab area so it is never forgotten, a key binding
-- and /zui privacy. Off by default (Chat > General).
-- Part of ZacUI; load order is set by the TOC (after Blz_Chat).
--
-- WHAT IT TOUCHES. Only what the chat windows draw: a chat filter
-- (ChatFrame_AddMessageEventFilter) hands each of those lines back with
-- its text replaced, the sender and channel kept, so the line still
-- says who spoke and where. Nothing you type or send is ever changed -
-- the filter runs on messages coming IN to the display, never on the
-- edit box or SendChatMessage. The whisper button's glow and count and
-- the whisper sound keep working (they listen to the events, not the
-- text); the button's hover list and the raid strip's toasts show the
-- mask instead of the text while the cover is on (Blz_Chat asks
-- ns.ChatPrivacy.Mask). Chat history (Chat_History) brings no whispers
-- back and masks guild lines while it is on.
--
-- WoW FOREVER: the message text and sender can be hidden values in a
-- fight. The filter never reads them - it replaces the text outright and
-- passes everything else straight through - so nothing here does string
-- work on a chat argument.
--
-- COST: a filter call per guild / whisper line, nothing else.

local ADDON_NAME, ns = ...

local Chat = ns.Chat
local GetColor = ns.GetColor
local Print = ns.Print

local P = {}
ns.ChatPrivacy = P

local MASK = "\226\128\162\226\128\162\226\128\162\226\128\162\226\128\162\226\128\162"   -- six bullets
P.MASK = MASK
P.TAG_TEXT = "PRIVACY ON"
P.TAG_FONT_DEFAULTS = { size = 10, outline = "outline", shadow = false }

-- the lines the cover masks: others' words...
P.EVENTS = { "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER" }
-- ...and your own replies, which the chat shows too ("To Healbot: ...")
P.OWN_EVENTS = { "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER_INFORM" }
local OWN = {}
for _, e in ipairs(P.OWN_EVENTS) do OWN[e] = true end

-- ============================================================
-- SETTINGS (chat.privacy*; nothing saved = off, replies masked too, tag shown)
-- ============================================================
local function DB()
    if Chat and Chat.DB then return Chat.DB() end
    ZacUIDB.chat = ZacUIDB.chat or {}
    return ZacUIDB.chat
end
local function Allowed()
    return not (ns.FeatureOn and not ns.FeatureOn("chat_privacy"))
end
function P.On() return Allowed() and DB().privacy == true end
function P.Own() return DB().privacyOwn ~= false end
function P.TagShown() return DB().privacyTag ~= false end
function P.ClearOnStart() return DB().privacyClear == true end

-- the text a chat line carries while the cover is on (Blz_Chat's whisper
-- list and raid toasts ask this; never reads the text it is handed)
function P.Mask(text)
    if P.On() then return MASK end
    return text
end

-- ============================================================
-- THE FILTER
-- ============================================================
-- (self, event, msg, sender, ...) -> false, newMsg, sender, ... : the
-- game then draws the line with our text and everything else as it was.
-- Nothing returned = leave the line alone.
local function Filter(self, event, msg, ...)
    if not P.On() then return end
    if OWN[event] and not P.Own() then return end
    return false, MASK, ...
end
P.Filter = Filter

local filtersIn = false
local function InstallFilters()
    if filtersIn or type(ChatFrame_AddMessageEventFilter) ~= "function" then return end
    filtersIn = true
    for _, e in ipairs(P.EVENTS) do ChatFrame_AddMessageEventFilter(e, Filter) end
    for _, e in ipairs(P.OWN_EVENTS) do ChatFrame_AddMessageEventFilter(e, Filter) end
end

-- ============================================================
-- THE TAG in the chat's tab area
-- ============================================================
local tag
local function TagDefaultSpot(f)
    f:ClearAllPoints()
    local cf = DEFAULT_CHAT_FRAME
    local pad = Chat and Chat.Look and Chat.Look.PAD or 4
    if cf then
        f:SetPoint("BOTTOMRIGHT", cf, "TOPRIGHT", pad - 1, 2)
    else
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 420, 230)
    end
end

-- the tag's look (the live one and the Chat page's sample)
function P.StyleTag(f)
    local d = DB()
    local fs = f._zText
    if ns.ApplyFontSpec then
        ns.ApplyFontSpec(fs, d.privacyTagFont, P.TAG_FONT_DEFAULTS)
    elseif ns.HouseFont then
        ns.HouseFont(fs, 10, "OUTLINE")
    end
    fs:SetText(P.TAG_TEXT)
    local r, g, b, a
    if type(d.privacyTagColor) == "table" and ns.ColorOf then
        r, g, b, a = ns.ColorOf(d.privacyTagColor)
    else
        local c = GetColor("text", "orange")
        r, g, b, a = c.r, c.g, c.b, 1
    end
    fs:SetTextColor(r, g, b, a or 1)
    if f._zPaint then f:_zPaint() end
    local w = fs:GetStringWidth() or 60
    f:SetSize(math.max(40, math.ceil(w) + 12), math.max(14, math.ceil(fs:GetStringHeight() or 10) + 6))
end

function P.BuildTag(parent, sample)
    local UI = ns.UI
    local f = CreateFrame("Button", (not sample) and "ZacUIPrivacyTag" or nil, parent or UIParent)
    f:SetSize(80, 16)
    if UI then
        UI.Fill(f, "ui", "windowBg", 0.85)
        UI.Border(f, "ui", "border")
        f._zPaint = function(self) UI.PaintBox(self) end
    end
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER", 0, 0)
    f._zText = fs
    if not sample then
        f:SetFrameStrata("MEDIUM")
        f:SetFrameLevel(8)
        f:SetScript("OnClick", function() P.Toggle() end)
        if UI and UI.Tooltip then
            UI.Tooltip(f, "Privacy cover on",
                "Guild, officer and whisper text is masked in the chat windows. What you send is untouched. "
                .. "Click to turn it off (also /zui privacy, or the key binding).")
        end
    else
        f:EnableMouse(false)
    end
    P.StyleTag(f)
    return f
end

-- the mover row exists from login (the Movers page lists it); the tag
-- itself is made the first time the cover goes on
local function RegisterTagMover()
    if not ns.RegisterMover then return end
    ns.RegisterMover("privacytag", "Privacy cover tag", function() return tag end, "BOTTOMLEFT", 420, 230, nil, {
        reset = function() if tag then TagDefaultSpot(tag) end end,
        own = true,
    })
end
local function Tag()
    if tag then return tag end
    tag = P.BuildTag(UIParent, false)
    TagDefaultSpot(tag)
    if ns.ApplyMover then ns.ApplyMover("privacytag") end
    return tag
end
P.TagFrame = function() return tag end

local function PaintTag()
    if P.On() and P.TagShown() then
        local t = Tag()
        P.StyleTag(t)
        t:Show()
    elseif tag then
        tag:Hide()
    end
end

-- ============================================================
-- ON / OFF
-- ============================================================
function P.Set(on, quiet)
    if not Allowed() then
        if not quiet then Print(ns.FeatureOffNote and ns.FeatureOffNote("chat_privacy") or "The privacy cover does not run here.") end
        return false
    end
    on = on and true or false
    local was = P.On()
    DB().privacy = on or nil
    if on and not was and P.ClearOnStart() then
        for i = 1, (NUM_CHAT_WINDOWS or 10) do
            local cf = _G["ChatFrame" .. i]
            if cf and cf.Clear and not (_G.COMBATLOG ~= nil and cf == _G.COMBATLOG) then pcall(cf.Clear, cf) end
        end
    end
    PaintTag()
    if not quiet and on ~= was then
        if on then
            Print("privacy cover ON - guild, officer and whisper text shows as " .. MASK
                .. " in the chat. What you send is untouched. /zui privacy turns it off.")
        else
            Print("privacy cover off - the chat shows everything again (lines already masked stay masked).")
        end
    end
    if ns.RefreshConfig then pcall(ns.RefreshConfig) end
    return on
end
function P.Toggle() return P.Set(not P.On()) end
function P.Apply() PaintTag() end

-- the key binding (Bindings.xml) and the slash command
BINDING_NAME_ZACUI_PRIVACY = "Chat: privacy cover on / off"
function ZacUI_TogglePrivacy() P.Toggle() end
ns.SlashCommands = ns.SlashCommands or {}
ns.SlashCommands.privacy = function(rest)
    rest = (rest or ""):lower()
    if rest == "on" then P.Set(true)
    elseif rest == "off" then P.Set(false)
    elseif rest == "" or rest == "toggle" then P.Toggle()
    else Print("/zui privacy [on|off] - mask guild, officer and whisper text in the chat while you stream.") end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    InstallFilters()
    RegisterTagMover()
    PaintTag()
    if ns.OnSettingsChanged then
        local soon = ns.Coalesce and ns.Coalesce(PaintTag) or PaintTag
        ns.OnSettingsChanged(function() soon() end)
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
    if not Allowed() then return end
    local UI = ns.UI
    local Kit = ns.CorePageKit
    local d = DB()
    L:Card("Streaming privacy cover")
    local on = UI.Checkbox(L.current, "Mask guild, officer and whisper text", P.On(), function(v)
        P.Set(v, true)
    end, { tooltip = "Those lines show as \"[Guild] Name: " .. MASK .. "\" in every chat window, so a stream never "
        .. "shows them. Only what the chat draws changes: what you type and send is never touched. "
        .. "Also /zui privacy and a key binding (Key Bindings > ZacUI chat)." })
    L:Row(on, 17)
    local own = UI.Checkbox(L.current, "Your own replies too", P.Own(), function(v)
        if v then d.privacyOwn = nil else d.privacyOwn = false end
    end, { tooltip = "\"To Healbot: ...\" lines - what you whispered back - are masked as well." })
    local tagCb = UI.Checkbox(L.current, "Show the PRIVACY ON tag", P.TagShown(), function(v)
        if v then d.privacyTag = nil else d.privacyTag = false end
        PaintTag()
    end, { tooltip = "A small tag at the right end of the chat's tab strip while the cover is on. Movable (Movers)." })
    local clear = UI.Checkbox(L.current, "Clear the chat windows when it goes on", P.ClearOnStart(), function(v)
        d.privacyClear = v or nil
    end, { tooltip = "Lines already on screen are not masked after the fact; this wipes them instead." })
    L:Dependent({ own, tagCb, clear }, true, 1)
    -- the tag's look, with a sample of it
    local sampleRow = UI.Holder(L.current)
    sampleRow:SetSize(200, 22)
    local sample = P.BuildTag(sampleRow, true)
    sample:SetPoint("LEFT", sampleRow, "LEFT", 0, 0)
    local hint = UI.Font(sampleRow, UI.F.SMALL, { cat = "text", key = "gray", text = "the tag, as it looks" })
    hint:SetPoint("LEFT", sample, "RIGHT", 8, 0)
    L:Row(sampleRow, 26)
    if Kit then
        Kit.Font(L, "Tag font", DB, "privacyTagFont", P.TAG_FONT_DEFAULTS,
            { sample = P.TAG_TEXT, after = function() P.StyleTag(sample) PaintTag() end })
        Kit.Color(L, "Tag colour", DB, "privacyTagColor", Kit.Palette("text", "orange"),
            { after = function() P.StyleTag(sample) PaintTag() end })
    end
    if Kit and Kit.Mover and ns.MOVERS and ns.MOVERS.privacytag then Kit.Mover(L, "privacytag", "the tag") end
    L:Desc("The whisper button, its glow and the whisper sound keep working; only the words are hidden.")
    L:EndCard()
end)

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("chat", "privacy stream streaming mask hide guild officer whisper text cover dots")
end
