-- Chat_Links - two things for the links in the chat:
--   * web addresses in what people say ("https://...", "www....") become a
--     clickable link in a colour of their own; a click opens a small box
--     with the address selected, ready for Ctrl+C;
--   * hovering an item, spell, quest, talent, achievement or enchant link
--     in a chat window shows its tooltip at the cursor (the game only does
--     it on a click).
-- Both off by default (Chat > General), each with a Test.
-- Part of ZacUI; load order is set by the TOC (after Blz_Chat).
--
-- HOW THE ADDRESSES ARE FOUND. A chat filter (the game's own
-- ChatFrame_AddMessageEventFilter, the way every chat addon changes what a
-- line says) hands back the message with each address wrapped in a link of
-- ZacUI's own ("addon:ZacUI:url:<address>", a local-only link: nothing
-- typed or sent ever carries it). Parts of the message that are already
-- links, colours or icons are left alone. A message the game hides from
-- addons (WoW Forever, in a fight) is passed through untouched - no string
-- work on it at all.
--
-- THE CLICK. A post-hook on SetItemRef (secure: the game's own click runs
-- first, untouched) opens the box. On Classic Era and TBC the item tooltip
-- is also told to skip ZacUI's link (an older client would try to read it
-- as an item), installed only once the feature has been switched on.
--
-- THE HOVER. OnHyperlinkEnter / OnHyperlinkLeave hooked on each chat
-- window (HookScript, after the game's own), once per window, the first
-- time the feature is on; while it is off the hooks do nothing. A hidden
-- link is never read.
--
-- ns.ChatText.EachPlain(text, fn) is shared with Chat_Lines: fn runs on
-- every stretch of a message that is not a link, colour, texture or
-- Battle.net name, and the stretches are stitched back in order.
--
-- COST: a filter call per player chat line (one plain find when there is
-- no "://" or "www."), two script calls per link hovered.

local ADDON_NAME, ns = ...

local Chat = ns.Chat
local GetColor = ns.GetColor
local Print = ns.Print

local CL = {}
ns.ChatLinks = CL

local URL_ID, TIP_ID = "chat_urls", "chat_link_tips"
local PREFIX = "addon:ZacUI:url:"
CL.PREFIX = PREFIX

local function Modern()
    if ns.ModernClient then return ns.ModernClient() and true or false end
    return _G.ZACUI_MODERN and true or false
end
local function Secret(v) return ns.IsSecret and ns.IsSecret(v) or false end

-- ============================================================
-- SETTINGS (chat.urls, chat.urlColor, chat.linkTips; nothing saved = off)
-- ============================================================
local function DB()
    if Chat and Chat.DB then return Chat.DB() end
    ZacUIDB.chat = ZacUIDB.chat or {}
    return ZacUIDB.chat
end
CL.DB = DB
local function Allowed(id) return not (ns.FeatureOn and not ns.FeatureOn(id)) end
function CL.UrlsOn() return Allowed(URL_ID) and DB().urls == true end
function CL.TipsOn() return Allowed(TIP_ID) and DB().linkTips == true end

function CL.UrlColor()
    local c = DB().urlColor
    if type(c) == "table" and ns.ColorOf then
        local r, g, b = ns.ColorOf(c)
        return r, g, b
    end
    local p = GetColor("ui", "accent")
    return p.r, p.g, p.b
end
local function HexOf(r, g, b)
    return string.format("%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- ============================================================
-- THE PLAIN STRETCHES OF A MESSAGE (shared with Chat_Lines)
-- ============================================================
-- |c...|r colour spans (item links sit inside one), |H...|h...|h links,
-- |T...|t textures, |A...|a atlases, |K...|k Battle.net names: kept as
-- they are. fn(plain) -> the stretch's new text.
local ENDS = { H = "|h.-|h", T = "|t", A = "|a", K = "|k", c = "|r" }
local function EachPlain(text, fn)
    if type(text) ~= "string" then return text end
    local out, pos, n = {}, 1, #text
    while pos <= n do
        local s, _, kind = text:find("|([HTAKc])", pos)
        if not s then
            out[#out + 1] = fn(text:sub(pos))
            break
        end
        if s > pos then out[#out + 1] = fn(text:sub(pos, s - 1)) end
        local _, e = text:find(ENDS[kind], s + 2)
        if not e then
            -- an unclosed escape: the rest stays as it is
            out[#out + 1] = text:sub(s)
            break
        end
        out[#out + 1] = text:sub(s, e)
        pos = e + 1
    end
    return table.concat(out)
end
ns.ChatText = ns.ChatText or {}
ns.ChatText.EachPlain = EachPlain

-- ============================================================
-- WEB ADDRESSES
-- ============================================================
local PATTERNS = {
    "%f[%w]%a[%w%+%.%-]*://[^%s|]+",
    "%f[%w]www%.[%w%-]+%.[^%s|]+",
}
local TRAIL = "[%.,;:!%?%)%]%}'\"]+$"

local function LinkFor(url, hex)
    return "|cff" .. hex .. "|H" .. PREFIX .. url .. "|h[" .. url .. "]|h|r"
end

-- one plain stretch: every address in it wrapped (an address found by the
-- first pattern is not looked at again by the second)
local function WrapPlain(s, hex)
    if not (s:find("://", 1, true) or s:find("www.", 1, true)) then return s end
    local spans = {}
    for _, p in ipairs(PATTERNS) do
        local init = 1
        while true do
            local a, b = s:find(p, init)
            if not a then break end
            local inside = false
            for _, sp in ipairs(spans) do if a <= sp[2] and b >= sp[1] then inside = true end end
            if not inside then
                local url = s:sub(a, b)
                local trail = url:match(TRAIL)
                if trail then b = b - #trail end
                if b > a then spans[#spans + 1] = { a, b } end
            end
            init = b + 1
        end
    end
    if #spans == 0 then return s end
    table.sort(spans, function(x, y) return x[1] < y[1] end)
    local out, pos = {}, 1
    for _, sp in ipairs(spans) do
        out[#out + 1] = s:sub(pos, sp[1] - 1)
        out[#out + 1] = LinkFor(s:sub(sp[1], sp[2]), hex)
        pos = sp[2] + 1
    end
    out[#out + 1] = s:sub(pos)
    return table.concat(out)
end

-- a whole message: nil when there is nothing to change (or it is hidden)
function CL.WrapURLs(text)
    if type(text) ~= "string" or Secret(text) then return nil end
    if not (text:find("://", 1, true) or text:find("www.", 1, true)) then return nil end
    local hex = HexOf(CL.UrlColor())
    local out = EachPlain(text, function(s) return WrapPlain(s, hex) end)
    if out == text then return nil end
    return out
end

-- the address a link of ours carries, or nil
function CL.URLOf(link)
    if type(link) ~= "string" or Secret(link) then return nil end
    if link:sub(1, #PREFIX) ~= PREFIX then return nil end
    local url = link:sub(#PREFIX + 1)
    if url == "" then return nil end
    return url
end

-- ============================================================
-- THE BOX
-- ============================================================
local box
function CL.ShowURL(url)
    local UI = ns.UI
    if not UI then return end
    if not box then
        box = UI.Window("ZacUIChatURL", 460, 104, "Copy link")
        local eb = UI.EditBox(box, { width = 436 })
        eb:ClearAllPoints()
        eb:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -((box.headerHeight or 30) + 10))
        local inner = eb.editBox
        if inner then
            inner:SetScript("OnEscapePressed", function(self) self:ClearFocus() box:Hide() end)
            -- the address cannot be typed over: any edit puts it back
            inner:SetScript("OnTextChanged", function(self, user)
                if user and box._url and self:GetText() ~= box._url then
                    self:SetText(box._url)
                    self:HighlightText()
                end
            end)
        end
        local hint = UI.Font(box, UI.F.SMALL, { cat = "text", key = "gray",
            text = "Ctrl+C to copy, Esc to close." })
        hint:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 12, 10)
        box.eb = eb
        box:SetFrameStrata("DIALOG")
    end
    box._url = url
    local inner = box.eb.editBox
    if inner then
        inner:SetText(url)
        if inner.SetCursorPosition then inner:SetCursorPosition(0) end
    end
    UI.OpenWindow(box)
    if inner then
        inner:SetFocus()
        inner:HighlightText()
    end
    return box
end
CL.Box = function() return box end

-- one click, however many of the hooks below see it
local lastLink, lastAt
local function OnLinkClicked(link)
    local url = CL.URLOf(link)
    if not url then return false end
    local now = GetTime and GetTime() or 0
    if link == lastLink and now == lastAt then return true end
    lastLink, lastAt = link, now
    CL.ShowURL(url)
    return true
end
CL.OnLinkClicked = OnLinkClicked

local clickHooked, refHooked = false, false
local function HookClicks()
    if not clickHooked and type(SetItemRef) == "function" then
        clickHooked = true
        hooksecurefunc("SetItemRef", function(link)
            if OnLinkClicked(link) then
                local t = ItemRefTooltip
                if t and t.IsShown and t:IsShown() and t.NumLines and (t:NumLines() or 0) == 0 then t:Hide() end
            end
        end)
    end
    -- Classic Era / TBC: the item tooltip skips our link instead of trying
    -- to read it (never on the modern client, whose chat is secure code)
    if not refHooked and not Modern() and ItemRefTooltip and ItemRefTooltip.SetHyperlink then
        refHooked = true
        local orig = ItemRefTooltip.SetHyperlink
        ItemRefTooltip.SetHyperlink = function(self, link, ...)
            if type(link) == "string" and not Secret(link) and link:sub(1, #PREFIX) == PREFIX then
                OnLinkClicked(link)
                if self.Hide then self:Hide() end
                return
            end
            return orig(self, link, ...)
        end
    end
end

-- ============================================================
-- THE FILTER
-- ============================================================
CL.EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_CHANNEL", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_EMOTE",
}
local function Filter(self, event, msg, ...)
    if not CL.UrlsOn() then return end
    if type(msg) ~= "string" or Secret(msg) then return end
    local out = CL.WrapURLs(msg)
    if out then return false, out, ... end
end
CL.Filter = Filter

local filtersIn = false
local function InstallFilters()
    if filtersIn or type(ChatFrame_AddMessageEventFilter) ~= "function" then return end
    filtersIn = true
    for _, e in ipairs(CL.EVENTS) do ChatFrame_AddMessageEventFilter(e, Filter) end
end

-- ============================================================
-- HOVER TOOLTIPS
-- ============================================================
CL.TIP_TYPES = { item = true, spell = true, enchant = true, quest = true, talent = true,
    achievement = true, currency = true, instancelock = true, glyph = true }
local hooked = setmetatable({}, { __mode = "k" })
local shownBy

local function OnEnter(self, link)
    if not CL.TipsOn() then return end
    if type(link) ~= "string" or Secret(link) then return end
    local kind = link:match("^([^:]+)")
    if not (kind and CL.TIP_TYPES[kind]) then return end
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
    if ok then
        GameTooltip:Show()
        shownBy = self
    else
        GameTooltip:Hide()
    end
end
local function OnLeave(self)
    if shownBy then
        shownBy = nil
        if GameTooltip then GameTooltip:Hide() end
    end
end
CL.OnEnter, CL.OnLeave = OnEnter, OnLeave

local function HookFrame(cf)
    if not cf or hooked[cf] or not cf.HookScript then return end
    if _G.COMBATLOG ~= nil and cf == _G.COMBATLOG then return end
    hooked[cf] = true
    cf:HookScript("OnHyperlinkEnter", OnEnter)
    cf:HookScript("OnHyperlinkLeave", OnLeave)
end
local function HookAll()
    for _, name in ipairs(CHAT_FRAMES or {}) do HookFrame(_G[name]) end
end
CL.Hooked = function(cf) return hooked[cf] == true end

local tempHooked = false
local function Apply()
    if CL.UrlsOn() then
        InstallFilters()
        HookClicks()
    end
    if CL.TipsOn() then
        HookAll()
        if not tempHooked and type(FCF_OpenTemporaryWindow) == "function" then
            tempHooked = true
            hooksecurefunc("FCF_OpenTemporaryWindow", function()
                if CL.TipsOn() then C_Timer.After(0, HookAll) end
            end)
        end
    end
end
CL.Apply = Apply

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    Apply()
end)

-- a line in the chat with a sample address in it, through the same filter
function CL.Test()
    local cf = (SELECTED_DOCK_FRAME and SELECTED_DOCK_FRAME.AddMessage and SELECTED_DOCK_FRAME) or DEFAULT_CHAT_FRAME
    if not cf then return nil end
    local line = CL.WrapURLs("Links look like this: https://www.curseforge.com/wow/addons - click one to copy it.")
        or "Links look like this: https://www.curseforge.com/wow/addons"
    cf:AddMessage("|cff" .. HexOf(GetColor("text", "gray").r, GetColor("text", "gray").g, GetColor("text", "gray").b)
        .. "ZacUI:|r " .. line)
    return line
end

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
    local urls, tips = Allowed(URL_ID), Allowed(TIP_ID)
    if not (urls or tips) then return end
    local UI = ns.UI
    local Kit = ns.CorePageKit
    local d = DB()
    L:Card("Links in the chat")
    if urls then
        local on = UI.Checkbox(L.current, "Make web addresses clickable", CL.UrlsOn(), function(v)
            d.urls = v and true or nil
            Apply()
            if ns.RefreshConfig then ns.RefreshConfig() end
        end, { tooltip = "\"https://...\" and \"www....\" in what people say become a link in the colour below. "
            .. "Click one and a box opens with the address selected: Ctrl+C copies it. Lines already in the chat "
            .. "stay as they were." })
        L:Row(on, 17)
        local kids = {}
        if Kit then
            local w = math.max(160, ((UI.CardInnerWidth and UI.CardInnerWidth(L)) or 400) - 40)
            local sample = UI.Holder(L.current)
            local fs = UI.Font(sample, UI.F.SMALL, { width = w, justify = "LEFT" })
            fs:SetPoint("TOPLEFT", sample, "TOPLEFT", 0, 0)
            sample.text = fs
            -- (drawn as the chat draws the link - its colour and brackets -
            -- without the link itself, which is only clickable in the chat)
            local function Paint()
                fs:SetText("Sample: see |cff" .. HexOf(CL.UrlColor()) .. "[https://wow.gg]|r")
                sample:SetSize(w, math.max(14, math.ceil(fs:GetStringHeight() or 12) + 2))
            end
            Paint()
            local pick = UI.ColorPicker(L.current, { label = "Link colour",
                get = function() local r, g, b = CL.UrlColor() return r, g, b, 1 end,
                set = function(r, g, b) d.urlColor = { r = r, g = g, b = b, a = 1 } Paint() end,
                default = function() local p = GetColor("ui", "accent") return p.r, p.g, p.b, 1 end,
                reset = function() d.urlColor = nil Paint() end })
            kids[#kids + 1] = pick
            kids[#kids + 1] = sample
        end
        kids[#kids + 1] = UI.Button(L.current, "Test", { width = 80,
            tooltip = "Puts a line with an address in it into the chat window you are looking at; click the "
                .. "address to see the box.",
            onClick = function() Apply() CL.Test() end })
        L:Dependent(kids, CL.UrlsOn(), 1, nil, "Make web addresses clickable")
    end
    if tips then
        local tip = UI.Checkbox(L.current, "Show a link's tooltip on hover", CL.TipsOn(), function(v)
            d.linkTips = v and true or nil
            Apply()
        end, { tooltip = "Item, spell, quest, talent, achievement and enchant links in the chat show their "
            .. "tooltip at the cursor while the mouse is over them. A click still opens them as before." })
        L:Row(tip, 17)
    end
    L:Desc("What you type and send is never changed; only what the chat shows.")
    L:EndCard()
end)

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("chat", "url urls link links web address website http https www copy clickable hover tooltip item")
end
