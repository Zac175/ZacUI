-- Chat_Panel - the chat's look and handling, past what Blz_Chat draws:
--   * the panel: a texture instead of the flat fill, the border's size
--     (none to 6 px) and colour from the accent or your class, a thin
--     inner line in a colour of its own                     (Chat > Look)
--   * the tabs: the name's colour on the tab you are on and on the others,
--     and the chip's padding around the name                 (Chat > Look)
--   * lock the chat's size: the resize grip refused     (Chat > Position)
--   * two buttons for the bar: chat settings (a cog) and the game's chat
--     menu (emotes, languages...)               (Chat > General, the bar)
-- All off by default; nothing saved = the chat exactly as before (the
-- panel flat with its 1 px edge, the tabs in the game's colours, the size
-- free, the bar as it was).
-- Part of ZacUI; load order is set by the TOC (after Blz_Chat).
--
-- HOW. Blz_Chat calls Chat.PanelExtra after it paints a panel and
-- Chat.ChipExtra before it paints a tab's chip - the real chat and the
-- Chat page's preview both - so this file only adds to what is drawn.
-- On the Classic look (the game's own edge art) the border and inner line
-- are the art's and are left alone; the texture still applies.
--
-- COST: nothing per frame; work only when a panel or tab is painted.

local ADDON_NAME, ns = ...

local Chat = ns.Chat
local GetColor = ns.GetColor
if not Chat then return end

local CP = {}
ns.ChatPanel = CP

local PANEL_ID, TABS_ID, LOCK_ID, BAR_ID = "chat_panel_look", "chat_tab_look", "chat_lock_size", "chat_bar_extras"
local PAD_X, PAD_Y = 7, 4   -- Blz_Chat's TAB_PAD_X / TAB_PAD_Y: the chip past its label
CP.PAD_X, CP.PAD_Y = PAD_X, PAD_Y
-- (the match pass: under the ZacUI look a chip with no padding picked is
-- the reference's tile - 12 either side of the name, 24 high - so the
-- sliders start from those)
local function DefPadX() return (Chat.Tiles and Chat.Tiles()) and Chat.REF.tabPadX or PAD_X end
local function DefPadY() return (Chat.Tiles and Chat.Tiles()) and Chat.REF.tabPadY or PAD_Y end
CP.DefPadX, CP.DefPadY = DefPadX, DefPadY

-- ============================================================
-- SETTINGS (ZacUIDB.chat; nothing saved = today)
--   panelTexture (bar texture name)   panelBorderSize (0-6; nil = 1)
--   panelBorderMode ("accent" | "class"; nil = the palette or the colour picked)
--   panelInner (bool)   panelInnerColor   tabNameColor / tabNameActive (colours)
--   tabPadX / tabPadY (px)   lockSize (bool)   items.zcog / items.zmenu (the bar)
-- ============================================================
local function DB() return Chat.DB() end
CP.DB = DB
local function Allowed(id) return not (ns.FeatureOn and not ns.FeatureOn(id)) end

-- ============================================================
-- THE PANEL
-- ============================================================
local function ModeColor(mode)
    if mode == "accent" then
        local c = GetColor("ui", "accent")
        return c.r, c.g, c.b, 1
    elseif mode == "class" then
        local class
        if UnitClass then class = select(2, UnitClass("player")) end
        if ns.ClassColor then
            local r, g, b = ns.ClassColor(class)
            return r, g, b, 1
        end
    end
    return nil
end
CP.ModeColor = ModeColor

local function Inner(bg)
    if bg._zcpInner then return bg._zcpInner end
    local t = {}
    for i = 1, 4 do
        local s = bg:CreateTexture(nil, "OVERLAY", nil, 6)
        s._zui_own = true
        s:SetTexture(ns.FLAT)
        s:Hide()
        t[i] = s
    end
    bg._zcpInner = t
    return t
end

function CP.PaintPanel(bg, d)
    if not bg then return end
    d = d or DB()
    local on = Allowed(PANEL_ID)
    -- the texture: the fill keeps its colour and opacity, only the art changes
    local fill = bg._zui_cbg
    local tex = on and d.panelTexture or nil
    if fill and fill.SetTexture then
        if type(tex) == "string" and tex ~= "" and ns.ResolveBarTexture then
            fill:SetTexture(ns.ResolveBarTexture(tex))
            bg._zcpTex = true
        elseif bg._zcpTex then
            bg._zcpTex = nil
            fill:SetTexture(ns.FLAT)
        end
    end
    local strips = bg._zui_borderTex
    if not strips or strips._zEdge then return end      -- the Classic edge: the art's own
    -- the border: size, then colour
    local size = on and tonumber(d.panelBorderSize) or nil
    if size ~= nil or bg._zcpSize then
        local n = math.max(0, math.min(6, size or 1))
        bg._zcpSize = (size ~= nil) or nil
        for i, t in ipairs(strips) do
            if n <= 0 then t:Hide() else
                t:Show()
                -- (physical pixels under ZacUI's look: HD polish)
                if not (ns.Pixel and ns.Pixel.SetEdgeSize(t, n)) then
                    if i <= 2 then t:SetHeight(n) else t:SetWidth(n) end
                end
            end
        end
    end
    local r, g, b, a = ModeColor(on and d.panelBorderMode or nil)
    if r and ns.TintBorder then ns.TintBorder(bg, r, g, b, a) end
    -- the inner line, one pixel inside the border
    local innerOn = on and d.panelInner == true
    if innerOn or bg._zcpInner then
        local t = Inner(bg)
        local off = math.max(0, math.min(6, size or 1))
        local ir, ig, ib, ia
        if type(d.panelInnerColor) == "table" and ns.ColorOf then ir, ig, ib, ia = ns.ColorOf(d.panelInnerColor)
        else local c = GetColor("ui", "accent") ir, ig, ib, ia = c.r, c.g, c.b, 0.45 end
        local pts = {
            { "TOPLEFT", off, -off, "TOPRIGHT", -off, -off, "h" },
            { "BOTTOMLEFT", off, off, "BOTTOMRIGHT", -off, off, "h" },
            { "TOPLEFT", off, -off, "BOTTOMLEFT", off, off, "w" },
            { "TOPRIGHT", -off, -off, "BOTTOMRIGHT", -off, off, "w" },
        }
        for i, s in ipairs(t) do
            if innerOn then
                local p = pts[i]
                s:ClearAllPoints()
                s:SetPoint(p[1], bg, p[1], p[2], p[3])
                s:SetPoint(p[4], bg, p[4], p[5], p[6])
                -- (one physical pixel under ZacUI's look: HD polish)
                if ns.Pixel then ns.Pixel.Edge(s, p[7] == "h" and "TOP" or "LEFT", bg)
                elseif p[7] == "h" then s:SetHeight(1) else s:SetWidth(1) end
                s:SetVertexColor(ir, ig, ib, ia or 1)
                s:Show()
            else
                s:Hide()
            end
        end
    end
    -- (the rail beside the panel: no edge where they meet - CP.RailSeam)
    if bg._zcpSeam and CP.RailSeam then CP.RailSeam() end
end
Chat.PanelExtra = CP.PaintPanel

-- ============================================================
-- THE TABS
-- ============================================================
function CP.TabsOn()
    if not Allowed(TABS_ID) then return false end
    local d = DB()
    return type(d.tabNameColor) == "table" or type(d.tabNameActive) == "table"
        or d.tabPadX ~= nil or d.tabPadY ~= nil
end

function CP.PaintChip(chip, selected, hover, news, d)
    if not chip then return end
    d = d or DB()
    local on = Allowed(TABS_ID)
    local text = chip.text
    -- the name's colour: the one picked for this state; else under the
    -- ZacUI look (the match pass) white, 65% on the tabs you are not on
    -- (a whisper window's tab keeps the game's whisper colour); else as
    -- the game left it
    if text and text.SetTextColor then
        local c = on and (selected and d.tabNameActive or d.tabNameColor) or nil
        local r, g, b, a
        if type(c) == "table" and ns.ColorOf then
            r, g, b, a = ns.ColorOf(c)
        elseif Chat.Match and Chat.Match() and not chip.isTemp and Chat.REF then
            local t = selected and Chat.REF.tabTextActive or Chat.REF.tabText
            r, g, b, a = t[1], t[2], t[3], t[4]
        end
        if r then
            if not chip._zcpStock and text.GetTextColor then chip._zcpStock = { text:GetTextColor() } end
            text:SetTextColor(r, g, b, a or 1)
        elseif chip._zcpStock then
            local s = chip._zcpStock
            text:SetTextColor(s[1], s[2], s[3], s[4] or 1)
            chip._zcpStock = nil
        end
    end
end
-- the chip's padding round the name, when one is picked here (nil, nil =
-- Blz_Chat's own placing: PlaceChip)
function CP.ChipPads(d)
    if not Allowed(TABS_ID) then return nil end
    d = d or DB()
    local px, py = tonumber(d.tabPadX), tonumber(d.tabPadY)
    if not (px or py) then return nil end
    if px then px = math.max(0, math.min(20, px)) end
    if py then py = math.max(0, math.min(12, py)) end
    return px, py
end
Chat.ChipPads = CP.ChipPads
Chat.ChipExtra = CP.PaintChip

-- ============================================================
-- LOCK THE SIZE
-- ============================================================
local held = setmetatable({}, { __mode = "k" })
local function GripOf(cf, name)
    return cf.resizeButton or (name and _G[name .. "ResizeButton"]) or nil
end
function CP.LockOn() return Allowed(LOCK_ID) and DB().lockSize == true end
function CP.ApplyLock()
    local on = CP.LockOn()
    for _, name in ipairs(CHAT_FRAMES or {}) do
        local cf = _G[name]
        local grip = cf and GripOf(cf, name)
        if grip then
            if on then
                if not held[grip] then
                    held[grip] = true
                    grip:EnableMouse(false)
                    grip:SetAlpha(0)
                end
            elseif held[grip] then
                held[grip] = nil
                grip:EnableMouse(true)
                grip:SetAlpha(1)
            end
        end
    end
end
CP.Held = function(grip) return held[grip] == true end

-- ============================================================
-- THE BAR'S TWO BUTTONS
-- ============================================================
local COG = "|TInterface\\Icons\\INV_Misc_Gear_01:14:14:0:0:64:64:5:59:5:59|t"
local MENU = "|TInterface\\ChatFrame\\UI-ChatIcon-Chat-Up:16:16|t"
CP.COG, CP.MENU = COG, MENU

local function Tip(self, title, line)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, self._zTipAnchor or "ANCHOR_TOP")
    GameTooltip:SetText(title, 1, 1, 1)
    if line then GameTooltip:AddLine(line, nil, nil, nil, true) end
    GameTooltip:Show()
end

-- the game's chat menu, where this client has one
function CP.HasMenu()
    return (type(ChatFrame_ToggleMenu) == "function" and _G.ChatMenu ~= nil)
        or (_G.ChatFrameMenuButton ~= nil and _G.ChatFrameMenuButton.Click ~= nil)
end
function CP.OpenMenu(owner)
    local menu = _G.ChatMenu
    if type(ChatFrame_ToggleMenu) == "function" and menu then
        pcall(ChatFrame_ToggleMenu)
        if owner and menu.IsShown and menu:IsShown() then
            menu:ClearAllPoints()
            menu:SetPoint("BOTTOMRIGHT", owner, "TOPRIGHT", 0, 4)
        end
        return true
    end
    local b = _G.ChatFrameMenuButton
    if b and b.Click then
        pcall(b.Click, b)
        return true
    end
    return false
end

CP.ITEMS = {
    { id = "zcog", label = "Chat settings button", sample = COG, keep = 40, every = 3600,
      text = function() return COG end,
      click = function() if ns.OpenConfig then ns.OpenConfig("chat") end end,
      tip = function(self) Tip(self, "Chat settings", "Opens ZacUI's Chat page.") end },
    { id = "zmenu", label = "Chat menu button", sample = MENU, keep = 41, every = 3600,
      text = function() return MENU end,
      click = function(self) CP.OpenMenu(self) end,
      tip = function(self) Tip(self, "Chat menu", "The game's chat menu: emotes, languages, voice.") end },
}
-- a button is on the bar only while it is switched on (d.items[id] ==
-- true), so with both off the bar is exactly what it was
function CP.Available(id)
    if not (Allowed(BAR_ID) and Chat.AddBarItem) then return false end
    return id ~= "zmenu" or CP.HasMenu()
end
function CP.ItemOn(id)
    local items = DB().items
    return CP.Available(id) and type(items) == "table" and items[id] == true
end
function CP.SetItem(id, on)
    if not CP.Available(id) then return false end
    local d = DB()
    if type(d.items) ~= "table" then d.items = {} end
    for _, it in ipairs(CP.ITEMS) do
        if it.id == id then
            if on then
                d.items[id] = true
                Chat.AddBarItem(it)
            else
                d.items[id] = nil
                if Chat.RemoveBarItem then Chat.RemoveBarItem(id) end
            end
        end
    end
    if Chat.Refresh then pcall(Chat.Refresh) end
    return true
end
local function AddItems()
    for _, it in ipairs(CP.ITEMS) do
        if CP.ItemOn(it.id) then Chat.AddBarItem(it) end
    end
end
-- (now, before the bar is first built, for the buttons already on)
if type(ZacUIDB) == "table" then AddItems() end

-- the rail's state, declared before the login hook below uses it (set
-- further down; 2026-11-08 fix: the hook read an undeclared global)
local rail
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    AddItems()
    if CP.LockOn() then CP.ApplyLock() end
    if type(FCF_OpenTemporaryWindow) == "function" then
        hooksecurefunc("FCF_OpenTemporaryWindow", function()
            if CP.LockOn() then C_Timer.After(0, CP.ApplyLock) end
        end)
    end
    -- the chat moved or resized (the game saves it then): the rail's side
    -- and how many icons fit are looked at again, a frame later
    -- (only where the rail can be: under a game look nothing is hooked)
    if type(FCF_SavePositionAndDimensions) == "function" and CP.RailAvailable() then
        hooksecurefunc("FCF_SavePositionAndDimensions", function()
            if rail.frame and rail.frame:IsShown() and not rail.queued then
                rail.queued = true
                C_Timer.After(0, function()
                    rail.queued = nil
                    pcall(CP.RailRefresh)
                end)
            end
        end)
    end
end)

-- ============================================================
-- THE ICON RAIL (2026-11-08, Zac: "some extra buttons that i would like
-- added")
-- ============================================================
-- A column of icons beside the chat panel, the reference chat's sidebar
-- with its numbers: 40 wide, the panel's height, the panel's colour and
-- 6% edge; icons 22 (friends 26, its online count under the glyph at 9)
-- 10 apart from the top, white at 40% and 90% under the mouse; scroll to
-- the newest line pinned 10 off the bottom. Our own glyphs (Media/Icons,
-- zui_tests/icons/make_icons.py), our own code.
--   friends     the online count (WoW + Battle.net); opens the friends list
--   guild       guild members online; opens the guild list       (off)
--   durability  your most worn piece; opens the character window (off)
--   copy        the copy-chat window for the tab you are on
--   channels    the game's chat channels window, where it has one (off)
--   menu        the game's chat menu (emotes, languages), where it has one (off)
--   swap        the chat box: the raid / party frames or the chat (only while
--               the box holds the frames); its glyph shows which is up
--   msgs        the raid messages over the frames on / off (same; off)
--   raidbox     raid frames in the chat box on / off; waits out a fight (off)
--   settings    ZacUI's Chat page
--   scroll      to the newest line - only while you are scrolled up
-- Each its own switch (chat.railItems[id] = false / true; nothing saved =
-- the default above), the whole rail one (chat.rail = false), its side
-- (chat.railSide "left" / "right"; nothing saved = LEFT, or right when
-- the chat sits too close to the screen's left edge for it). It hangs
-- outside the panel: the chat box never changes size or place for it. A right-click
-- on the rail lists the icons to switch.
-- ONLY UNDER THE ZACUI LOOK: under a game look (Classic, WoW Forever,
-- Blizzard style) the chat's skin stands down and the game's own chat
-- buttons are back (its button column, chat menu, social button), so a
-- second column of the same buttons is not made; nothing of the rail
-- exists there.
-- TAINT: the rail is ZacUI's own frame (a UIParent child, hung from our
-- panel); it hooks nothing of the chat's. The social, guild, character
-- and channel windows are opened only out of combat (Blizzard's panels);
-- copy, settings, scroll and the chat menu work any time.
-- COST: one quarter-second check while the rail is on screen (scrolled up?
-- the counts every few seconds); nothing when it is not.
local RAIL_ID = "chat_rail"
local ICONS = (ns.MEDIA or "Interface\\AddOns\\ZacUI\\Media\\") .. "Icons\\"
local RAIL = { W = 40, MIN_W = 28, INSET = 38, ICON = 22, FRIEND = 26, SPACE = 10, COUNT = 9, GLYPH = 18, FGLYPH = 17,
    ALPHA = 0.4, HOVER = 0.9, DIM = 0.2, COUNT_A = 0.5, COUNT_HOVER = 0.9, HOVER_FILL = 0.08 }
CP.RAIL = RAIL
rail = {}                  -- the frame and its buttons, once built
CP.Rail = rail

local function InCombat() return InCombatLockdown and InCombatLockdown() end
local function NotInCombat()
    if not InCombat() then return true end
    if UIErrorsFrame then
        UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT or "You can't do that while in combat.", 1, 0.1, 0.1)
    end
    return false
end
local function OnlineFriends()
    local n = 0
    if C_FriendList and C_FriendList.GetNumOnlineFriends then
        local ok, v = pcall(C_FriendList.GetNumOnlineFriends)
        if ok and type(v) == "number" then n = v end
    end
    if BNGetNumFriends then
        local ok, _, online = pcall(BNGetNumFriends)
        if ok and type(online) == "number" then n = n + online end
    end
    return n
end
local function GuildOnline()
    if not (IsInGuild and IsInGuild()) or not GetNumGuildMembers then return nil end
    local ok, _, online = pcall(GetNumGuildMembers)
    return (ok and type(online) == "number") and online or 0
end
local function WornPct()
    if not GetInventoryItemDurability then return nil end
    local low
    for slot = 1, 18 do
        local cur, max = GetInventoryItemDurability(slot)
        if type(cur) == "number" and type(max) == "number" and max > 0 then
            local p = cur / max
            if not low or p < low then low = p end
        end
    end
    return low and math.floor(low * 100) or nil
end
local function TipTitle(owner, title, line)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, owner._zTipAnchor or "ANCHOR_RIGHT")
    local t = GetColor("tooltip", "title")
    GameTooltip:SetText(title, t.r, t.g, t.b)
    if line then
        local b = GetColor("tooltip", "body")
        GameTooltip:AddLine(line, b.r, b.g, b.b, true)
    end
end
local function TipHint(text)
    local g = GetColor("text", "gray")
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(text, g.r, g.g, g.b, true)
end

-- id, the glyph, the tooltip's title, default, whether this client has it
CP.RAIL_ITEMS = {
    { id = "friends", keep = 3, glyph = "friends", label = "Friends", default = true, count = true, big = true,
      count_fn = function() return tostring(OnlineFriends()) end,
      tip = function(self)
          local T = ns.MinimapTips
          if T and T.Friends then T.Friends(self) else TipTitle(self, FRIENDS or "Friends") end
          TipHint("Click to open your friends list")
      end,
      click = function()
          if not NotInCombat() then return end
          local T = ns.MinimapTips
          if T and T.OpenSocial then T.OpenSocial() elseif ToggleFriendsFrame then ToggleFriendsFrame() end
      end },
    { id = "guild", keep = 6, glyph = "guild", label = "Guild", default = false, count = true, big = true,
      count_fn = function() local n = GuildOnline() return n and tostring(n) or "" end,
      tip = function(self)
          local T = ns.MinimapTips
          if T and T.Guild then T.Guild(self) else TipTitle(self, GUILD or "Guild") end
          TipHint("Click to open your guild")
      end,
      click = function()
          if not NotInCombat() then return end
          if type(ToggleGuildFrame) == "function" then pcall(ToggleGuildFrame)
          else
              local T = ns.MinimapTips
              if T and T.OpenSocial then T.OpenSocial() end
          end
      end },
    { id = "durability", keep = 7, glyph = "durability", label = "Durability", default = false, count = true, big = true,
      count_fn = function() local p = WornPct() return p and (p .. "%") or "" end,
      tip = function(self)
          TipTitle(self, DURABILITY or "Durability", "Your most worn piece of gear.")
          for slot = 1, 18 do
              local cur, max = GetInventoryItemDurability(slot)
              if type(cur) == "number" and type(max) == "number" and max > 0 then
                  local b = GetColor("tooltip", "body")
                  GameTooltip:AddDoubleLine(GetInventoryItemLink and GetInventoryItemLink("player", slot) or ("Slot " .. slot),
                      math.floor(cur / max * 100 + 0.5) .. "%", b.r, b.g, b.b, b.r, b.g, b.b)
              end
          end
          TipHint("Click to open your character")
      end,
      click = function()
          if not NotInCombat() then return end
          if ToggleCharacter then pcall(ToggleCharacter, "PaperDollFrame") end
      end },
    { id = "copy", keep = 4, glyph = "copy", label = "Copy chat", default = true,
      tip = function(self) TipTitle(self, "Copy chat", "The tab you are on, in a box you can select and copy from.") end,
      click = function() if Chat.CopyChat then Chat.CopyChat() end end },
    { id = "channels", keep = 8, glyph = "channels", label = "Chat channels", default = false,
      has = function() return type(ToggleChannelFrame) == "function" end,
      tip = function(self) TipTitle(self, CHANNELS or "Chat channels", "The game's channels window: join, leave, voice.") end,
      click = function() if NotInCombat() then pcall(ToggleChannelFrame) end end },
    { id = "menu", keep = 9, glyph = "report", label = "Chat menu", default = false,
      has = function() return CP.HasMenu() end,
      tip = function(self) TipTitle(self, "Chat menu", "The game's chat menu: emotes, languages, channels.") end,
      click = function(self) CP.OpenMenu(self) end },
    -- THE RAID BOX (2026-11-08, Zac: "add buttons there to swap between raid
    -- frames and chat"): Blz_Chat's raid mode puts the raid (and, with that
    -- switch, party) frames in the chat box. The swap button shows which
    -- view is up - the frames' glyph or the chat's - and flips it; it and
    -- the messages button are only there while the box holds the frames.
    -- The swap is the box's own strip buttons' action (opacity only), so it
    -- works in a fight; switching the mode itself moves the secure frames
    -- and waits for the fight to end.
    { id = "swap", keep = 1, glyph = "raidframes", label = "Swap chat and raid frames", default = true,
      live = function() local RM = Chat.RaidMode return RM and RM.active and true or false end,
      art = function()
          local RM = Chat.RaidMode
          return (RM and RM.peek) and "chatview" or "raidframes"
      end,
      tip = function(self)
          local RM = Chat.RaidMode
          local what = (RM and RM.kind == "party") and "party" or "raid"
          if RM and RM.peek then
              TipTitle(self, "Showing: the chat", "The " .. what .. " frames are in the chat box, behind the chat.")
              TipHint("Click to show the " .. what .. " frames")
          else
              TipTitle(self, "Showing: the " .. what .. " frames", "The chat is behind them; nothing is lost.")
              if RM and (RM.unread or 0) > 0 then GameTooltip:AddLine(RM.unread .. " new in the chat", 1, 0.82, 0) end
              TipHint("Click to show the chat")
          end
      end,
      click = function()
          local RM = Chat.RaidMode
          if RM and RM.active and RM.SetPeek then RM.SetPeek(not RM.peek or RM.temp, false) end
          rail.t = 99
      end },
    { id = "msgs", keep = 5, glyph = "eye", label = "Raid messages on / off", default = false,
      live = function() local RM = Chat.RaidMode return RM and RM.active and true or false end,
      dim = function() return DB().raidMsgsHidden == true end,
      tip = function(self)
          local off = DB().raidMsgsHidden == true
          TipTitle(self, off and "Raid messages: hidden" or "Raid messages: showing",
              "Raid warnings, whispers and raid lines popping over the frames for a few seconds.")
          TipHint(off and "Click to show them again" or "Click to stop them (the chat still counts them)")
      end,
      click = function()
          local RM = Chat.RaidMode
          if RM and RM.ToggleMsgs then RM.ToggleMsgs() end
          rail.t = 99
      end },
    { id = "raidbox", keep = 10, glyph = "raidbox", label = "Raid frames in the chat box (on / off)", default = false,
      dim = function() local RM = Chat.RaidMode return not (RM and RM.Enabled and RM.Enabled()) end,
      tip = function(self)
          local RM = Chat.RaidMode
          local on = RM and RM.Enabled and RM.Enabled()
          TipTitle(self, on and "Raid frames in the chat box: on" or "Raid frames in the chat box: off",
              "In a raid (and a party, if set on the Chat page) the chat box holds the frames. Same as /zacui raidchat.")
          if rail.raidQueued ~= nil then
              GameTooltip:AddLine("Switching " .. (rail.raidQueued and "on" or "off") .. " when this fight ends.", 1, 0.82, 0, true)
          elseif InCombat() then
              TipHint("In a fight: a click waits for the fight to end")
          else
              TipHint("Click to switch it " .. (on and "off" or "on"))
          end
      end,
      click = function() CP.ToggleRaidBox() end },
    { id = "settings", keep = 2, glyph = "settings", label = "Chat settings", default = true,
      tip = function(self) TipTitle(self, "Chat settings", "Opens ZacUI's Chat page.") end,
      click = function() if ns.OpenConfig then ns.OpenConfig("chat") end end },
    { id = "scroll", glyph = "bottom", label = "Scroll to the newest line", default = true, bottom = true,
      tip = function(self)
          TipTitle(self, "You are scrolled up", "New lines are arriving below what you can see.")
          TipHint("Click to jump to the newest line")
      end,
      click = function()
          local cf = Chat.SelectedFrame and Chat.SelectedFrame()
          if cf and cf.ScrollToBottom then cf:ScrollToBottom() end
          rail.t = 99
      end },
}
local RAIL_BY = {}
for _, it in ipairs(CP.RAIL_ITEMS) do RAIL_BY[it.id] = it end

-- the raid box on / off (the Chat page's switch: the account's, a
-- character's own override cleared); in a fight it waits for the end
local function SetRaidBox(on)
    local RM = Chat.RaidMode
    local d = DB()
    d.raidMode = on and true or false
    if ZacUICharDB then ZacUICharDB.chatRaidMode = nil end
    if RM and RM.Update then pcall(RM.Update) end
    rail.t = 99
end
function CP.ToggleRaidBox()
    local RM = Chat.RaidMode
    local on = RM and RM.Enabled and RM.Enabled()
    if InCombat() then
        -- a second click in the same fight takes the wish back
        if rail.raidQueued ~= nil then rail.raidQueued = nil return end
        rail.raidQueued = not on
        if not rail.regen then
            rail.regen = CreateFrame("Frame")
            rail.regen:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                local want = rail.raidQueued
                rail.raidQueued = nil
                if want ~= nil then SetRaidBox(want) end
            end)
        end
        rail.regen:RegisterEvent("PLAYER_REGEN_ENABLED")
        if UIErrorsFrame then UIErrorsFrame:AddMessage("Raid frames in the chat box: switching when this fight ends.", 1, 0.82, 0) end
        return
    end
    SetRaidBox(not on)
end

-- whether the rail can exist here: the feature, and the ZacUI look
function CP.RailAvailable()
    if not Allowed(RAIL_ID) then return false end
    return not (Chat.ZacLook and not Chat.ZacLook())
end
function CP.RailOn() return CP.RailAvailable() and DB().rail ~= false end
-- mouseover only (the default) or always up
function CP.RailHover() return DB().railHover ~= false end
function CP.RailFade(f, dt)
    local want = 1
    if CP.RailHover() then
        local cf = DEFAULT_CHAT_FRAME
        local bg = cf and cf._zui_chatbg
        local over = (f.IsMouseOver and f:IsMouseOver())
            or (bg and bg.IsMouseOver and bg:IsMouseOver())
            or (cf and cf.IsMouseOver and cf:IsMouseOver())
        if over then
            rail.away = 0
        else
            rail.away = (rail.away or 0) + (dt or 0)
            -- a short grace, so crossing the gap from chat to rail never blinks
            if rail.away > 0.4 then want = 0 end
        end
    end
    local a = f:GetAlpha() or 1
    if math.abs(a - want) < 0.02 then
        if a ~= want then f:SetAlpha(want) end
        return
    end
    f:SetAlpha(a + (want - a) * math.min(1, (dt or 0.016) * 8))
end
function CP.RailItemHere(id)
    local it = RAIL_BY[id]
    if not it then return false end
    if it.has then
        local ok, v = pcall(it.has)
        return ok and v and true or false
    end
    return true
end
function CP.RailItemOn(id)
    local it = RAIL_BY[id]
    if not (it and CP.RailItemHere(id)) then return false end
    local items = DB().railItems
    local v
    if type(items) == "table" then v = items[id] end
    if v == nil then return it.default end
    return v and true or false
end
-- set one icon; the default stores nothing (and an empty list goes)
function CP.SetRailItem(id, on)
    local it = RAIL_BY[id]
    if not it then return false end
    local d = DB()
    if type(d.railItems) ~= "table" then d.railItems = {} end
    if (on and true or false) == it.default then d.railItems[id] = nil else d.railItems[id] = on and true or false end
    if next(d.railItems) == nil then d.railItems = nil end
    if CP.RailRefresh then CP.RailRefresh() end
    return true
end
function CP.SetRail(on)
    if on then DB().rail = nil else DB().rail = false end
    if CP.RailRefresh then CP.RailRefresh() end
end

-- the side: as saved, else RIGHT of the chat (Zac, 2026-11-08: "on the
-- other side of the chat"), or left when the chat is too near the screen's
-- right edge for the rail to fit there. Either way it hangs OUTSIDE the
-- panel: the chat itself never changes size or place.
local function Num(v) return type(v) == "number" and not (ns.IsSecret and ns.IsSecret(v)) end
function CP.RailSide(bg)
    local s = DB().railSide
    if s == "left" or s == "right" then return s end
    if s == "inside" then return "inside" end
    -- (2026-11-08, Zac: "i wanted the stuff on the other side" - the
    -- right-hand rail sat on his weapon bar) LEFT of the chat, unless the
    -- chat is too near the screen's left edge for it to fit there
    local l = bg and bg.GetLeft and bg:GetLeft()
    if Num(l) then
        local k = 1
        if bg.GetEffectiveScale and UIParent and UIParent.GetEffectiveScale then
            local ok, a = pcall(bg.GetEffectiveScale, bg)
            local ok2, u = pcall(UIParent.GetEffectiveScale, UIParent)
            if ok and ok2 and Num(a) and Num(u) and u > 0 then k = a / u end
        end
        -- (2026-11-08, Zac: "house them outside the chat but to the left";
        -- inside, the chat window took the clicks) a chat close to the
        -- screen's edge gets a narrower column, down to RAIL.MIN_W; flush
        -- against the panel, so all of that room is the column's
        if l * k >= RAIL.MIN_W then return "left", l * k end
    end
    local r = bg and bg.GetRight and bg:GetRight()
    local sw = UIParent and UIParent.GetRight and UIParent:GetRight()
    if not Num(sw) and UIParent and UIParent.GetWidth then sw = UIParent:GetWidth() end
    if Num(r) and Num(sw) then
        local k = 1
        if bg.GetEffectiveScale and UIParent and UIParent.GetEffectiveScale then
            local ok, a = pcall(bg.GetEffectiveScale, bg)
            local ok2, u = pcall(UIParent.GetEffectiveScale, UIParent)
            if ok and ok2 and Num(a) and Num(u) and u > 0 then k = a / u end
        end
        if r * k + RAIL.W > sw then return "left" end
    end
    return "right"
end

local function Snap(v, f) return (ns.Pixel and ns.Pixel.Snap) and ns.Pixel.Snap(v, f) or v end

local function PaintButton(b, hot)
    local a = hot and RAIL.HOVER or RAIL.ALPHA
    -- a switch that is off: dimmer still at rest
    if b._dim and not hot then a = RAIL.DIM end
    b._glyph:SetVertexColor(1, 1, 1, a)
    b._hover:SetShown(hot and true or false)
    if b._count then b._count:SetTextColor(1, 1, 1, hot and RAIL.COUNT_HOVER or RAIL.COUNT_A) end
end

local RailMenu   -- forward: a right-click on the rail

local function MakeButton(parent, it)
    local b = CreateFrame("Button", nil, parent)
    if ns.ZUI and ns.ZUI.skinned then ns.ZUI.skinned[b] = true end
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local size = it.big and RAIL.FRIEND or RAIL.ICON
    b._size = size
    -- the hover box: the button's own rect, so it sits exactly on it
    local hov = b:CreateTexture(nil, "BACKGROUND")
    hov._zui_own = true
    hov:SetTexture(ns.FLAT)
    hov:SetAllPoints(b)
    hov:SetVertexColor(1, 1, 1, RAIL.HOVER_FILL)
    hov:Hide()
    b._hover = hov
    local g = b:CreateTexture(nil, "ARTWORK")
    g._zui_own = true
    g:SetTexture(ICONS .. it.glyph)
    if it.count then
        -- the glyph at the top, its number under it inside the button
        g:SetSize(RAIL.FGLYPH, RAIL.FGLYPH)
        g:SetPoint("TOP", b, "TOP", 0, -1)
        local fs = b:CreateFontString(nil, "OVERLAY")
        if ns.HouseFont then ns.HouseFont(fs, RAIL.COUNT) else fs:SetFont(STANDARD_TEXT_FONT, RAIL.COUNT, "OUTLINE") end
        fs:SetPoint("BOTTOM", b, "BOTTOM", 0, 0)
        fs:SetJustifyH("CENTER")
        fs:SetWordWrap(false)
        b._count = fs
    else
        g:SetSize(RAIL.GLYPH, RAIL.GLYPH)
        g:SetPoint("CENTER", b, "CENTER", 0, 0)
    end
    b._glyph = g
    b._it = it
    b:SetScript("OnEnter", function(self)
        PaintButton(self, true)
        if it.tip then
            local ok = pcall(it.tip, self)
            if ok and GameTooltip then GameTooltip:Show() elseif GameTooltip then GameTooltip:Hide() end
        end
    end)
    b:SetScript("OnLeave", function(self)
        PaintButton(self, false)
        if GameTooltip then GameTooltip:Hide() end
    end)
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then RailMenu(self) return end
        if it.click then pcall(it.click, self) end
    end)
    PaintButton(b, false)
    b:Hide()
    return b
end

local function BuildRail()
    if rail.frame then return rail.frame end
    local f = CreateFrame("Frame", "ZacUIChatRail", UIParent)
    if ns.ZUI and ns.ZUI.skinned then ns.ZUI.skinned[f] = true end
    -- with the bar: over the panels, under the edit box
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(1)
    f:SetWidth(RAIL.W)
    f:EnableMouse(true)
    f:Hide()
    local fill = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    fill._zui_own = true
    fill:SetTexture(ns.FLAT)
    fill:SetAllPoints()
    rail.fill = fill
    if ns.Pixel and ns.Pixel.Border then
        rail.edges = ns.Pixel.Border(f, 1, 1, 1, 0.06)
    else
        rail.edges = {}
        for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local t = f:CreateTexture(nil, "OVERLAY", nil, 7)
            t:SetTexture(ns.FLAT)
            if side == "TOP" or side == "BOTTOM" then
                t:SetPoint(side .. "LEFT") t:SetPoint(side .. "RIGHT") t:SetHeight(1)
            else
                t:SetPoint("TOP" .. side) t:SetPoint("BOTTOM" .. side) t:SetWidth(1)
            end
            rail.edges[#rail.edges + 1] = t
        end
    end
    f:SetScript("OnMouseUp", function(self, button) if button == "RightButton" then RailMenu(self) end end)
    rail.buttons = {}
    for _, it in ipairs(CP.RAIL_ITEMS) do rail.buttons[it.id] = MakeButton(f, it) end
    -- the clock: scrolled up? (a quarter second), the counts (every 5 s)
    f:SetScript("OnShow", function() rail.t, rail.slow = 99, 99 end)
    f:SetScript("OnUpdate", function(self, dt)
        -- (2026-11-08, Zac: "make this area next to the chat mouse over by
        -- default but have the ability in the ui to make it not hover")
        -- the icons fade in while the mouse is over the chat or the rail,
        -- and out a moment after it leaves; chat.railHover = false keeps
        -- them up
        CP.RailFade(self, dt)
        rail.t = (rail.t or 99) + dt
        if rail.t < 0.25 then return end
        rail.slow = (rail.slow or 99) + rail.t
        rail.t = 0
        CP.RailTick()
    end)
    rail.frame = f
    return f
end

-- the colours: the panel's own (its colour at its opacity, its edge)
local function PaintRail(d)
    local f = rail.frame
    if not f then return end
    local r, g, b = 0.03, 0.045, 0.05
    if Chat.PanelRGB then
        local pr, pg, pb = Chat.PanelRGB(d)
        if pr then r, g, b = pr, pg, pb end
    end
    -- (2026-11-08, Zac: "add a background to these buttons") the column
    -- has the chat's own panel colour behind it - the panel's fill exactly
    -- as painted, so chat and rail read as one box
    local a = tonumber(d.opacity) or 0.65
    local cf = DEFAULT_CHAT_FRAME
    local pfill = cf and cf._zui_chatbg and cf._zui_chatbg._zui_cbg
    if pfill and pfill.GetVertexColor then
        local pr, pg, pb, pa = pfill:GetVertexColor()
        if Num(pr) and Num(pg) and Num(pb) then r, g, b = pr, pg, pb end
        if Num(pa) then a = pa end
    end
    rail.fill:SetVertexColor(r, g, b, a)
    local er, eg, eb, ea = 1, 1, 1, 0.06
    if Chat.EdgeRGBA then
        local a1, a2, a3, a4 = Chat.EdgeRGBA(d)
        if a1 then er, eg, eb, ea = a1, a2, a3, a4 end
    end
    for _, t in ipairs(rail.edges) do
        if t.SetColorTexture then t:SetColorTexture(er, eg, eb, ea or 1) else t:SetVertexColor(er, eg, eb, ea or 1) end
    end
end

-- where everything sits: the rail beside the panel, the icons down it
-- The chat windows' text, inset from the left by `px` (0 = as Blizzard
-- lays it): the message lines live in the frame's FontStringContainer, so
-- moving that moves the text and nothing else - the window keeps its saved
-- size and place.
function CP.InsetText(px)
    px = px or 0
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        local c = cf and rawget(cf, "FontStringContainer")
        if c and c.ClearAllPoints and rawget(cf, "_zRailInset") ~= px then
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", cf, "TOPLEFT", px, 0)
            c:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 0, 0)
            rawset(cf, "_zRailInset", px)
        end
    end
end

-- The panel's own edge where the rail meets it: hidden while the rail is
-- up beside the panel (left: its LEFT edge, right: its RIGHT), back when
-- the rail goes or moves inside - on every docked window's panel (they
-- share the spot; the rail stays while another docked tab is up). A
-- border set to 0 on the Chat page stays hidden either way. Called after
-- every rail change and every panel paint.
local function SeamOne(bg, want)
    local strips = bg and bg._zui_borderTex
    if not strips or strips._zEdge then return end      -- the Classic edge: the art's own
    local was = bg._zcpSeam
    if was and was ~= want and strips[was] then
        local d = DB()
        local size = Allowed(PANEL_ID) and tonumber(d.panelBorderSize) or nil
        if size == nil or size > 0 then strips[was]:Show() end
    end
    if want and strips[want] then strips[want]:Hide() end
    bg._zcpSeam = want
end
function CP.RailSeam()
    local f = rail.frame
    local want
    if f and f:IsShown() and CP.RailOn() then
        if rail.side == "left" then want = 3 elseif rail.side == "right" then want = 4 end
    end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        local bg = cf and rawget(cf, "_zui_chatbg")
        if bg then
            local docked = cf == DEFAULT_CHAT_FRAME or cf.isDocked == true or cf.isDocked == 1
            SeamOne(bg, docked and want or nil)
        end
    end
end

local function PlaceRail(d)
    local f = rail.frame
    local cf = DEFAULT_CHAT_FRAME
    local bg = cf and cf._zui_chatbg
    if not (f and bg) then return false end
    local side, room = CP.RailSide(bg)
    rail.side = side
    f:ClearAllPoints()
    CP.InsetText(side == "inside" and RAIL.INSET or 0)
    -- the column's width: 40, or what room the screen's edge leaves
    local w = RAIL.W
    if side == "left" and type(room) == "number" and room < RAIL.W then
        w = math.max(RAIL.MIN_W, math.floor(room))
    end
    f:SetWidth(w)
    if side == "inside" then
        f:SetPoint("TOPLEFT", bg, "TOPLEFT", 0, 0)
        f:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 0, 0)
    elseif side == "right" then
        f:SetPoint("TOPLEFT", bg, "TOPRIGHT", 0, 0)
        f:SetPoint("BOTTOMLEFT", bg, "BOTTOMRIGHT", 0, 0)
    else
        f:SetPoint("TOPRIGHT", bg, "TOPLEFT", 0, 0)
        f:SetPoint("BOTTOMRIGHT", bg, "BOTTOMLEFT", 0, 0)
    end
    -- (2026-11-08, Zac: "the chat settings cog and that bar not attached
    -- to the chat, looks weird with a gap") FLUSH against the panel, its
    -- top and bottom (the bar the panel reaches down around included):
    -- one box with the chat. No line where they meet - neither the
    -- rail's edge nor the panel's (CP.RailSeam) - only the outer edges.
    -- (edges: TOP, BOTTOM, LEFT, RIGHT)
    if rail.edges[3] then rail.edges[3]:SetShown(side ~= "right") end
    if rail.edges[4] then rail.edges[4]:SetShown(side ~= "left") end
    local anchor = (side == "right") and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
    -- the icons from the top, 10 apart; the scroll button 10 off the bottom
    local h = f.GetHeight and f:GetHeight() or nil
    if type(h) ~= "number" or h <= 0 or (ns.IsSecret and ns.IsSecret(h)) then h = nil end
    local bottomRoom = RAIL.SPACE + RAIL.ICON + RAIL.SPACE
    -- what is up, and what fits: when the chat is too short for all of them
    -- the least needed step off first (RAIL_KEEP), the rest keep their order
    local want, total = {}, RAIL.SPACE
    for _, it in ipairs(CP.RAIL_ITEMS) do
        if not it.bottom and CP.RailItemOn(it.id) and (not it.live or it.live()) then
            want[it.id] = true
            total = total + rail.buttons[it.id]._size + RAIL.SPACE
        end
    end
    if h then
        local order = {}
        for id in pairs(want) do order[#order + 1] = id end
        table.sort(order, function(x, y) return (RAIL_BY[x].keep or 50) > (RAIL_BY[y].keep or 50) end)
        local i = 1
        while total - RAIL.SPACE > h - bottomRoom and order[i] do
            want[order[i]] = nil
            total = total - rail.buttons[order[i]]._size - RAIL.SPACE
            i = i + 1
        end
    end
    local y = RAIL.SPACE
    local shown = {}
    for _, it in ipairs(CP.RAIL_ITEMS) do
        local b = rail.buttons[it.id]
        b._zTipAnchor = anchor
        local s = b._size
        b:SetSize(Snap(s, b), Snap(s, b))
        if it.bottom then
            b:ClearAllPoints()
            b:SetPoint("BOTTOM", f, "BOTTOM", 0, Snap(RAIL.SPACE, f))
        else
            local fits = want[it.id] and true or false
            if fits then
                b:ClearAllPoints()
                b:SetPoint("TOP", f, "TOP", 0, -Snap(y, f))
                y = y + s + RAIL.SPACE
                shown[it.id] = true
            end
            b._fits = fits
            if not fits then b:Hide() end
        end
    end
    rail.shown = shown
    rail.liveKey = CP.RailLiveKey()
    return true
end

-- which conditional icons are up (the raid box's): a change lays the rail out again
function CP.RailLiveKey()
    local k = ""
    for _, it in ipairs(CP.RAIL_ITEMS) do
        if it.live then
            local ok, v = pcall(it.live)
            k = k .. ((ok and v) and "1" or "0")
        end
    end
    return k
end

-- the quarter-second look: scrolled up? the numbers
function CP.RailTick()
    local f = rail.frame
    if not (f and f:IsShown()) then return end
    if CP.RailLiveKey() ~= rail.liveKey then PlaceRail(DB()) end
    -- the glyph that says what the box shows, and switches that are off dimmed
    for id in pairs(rail.shown or {}) do
        local b = rail.buttons[id]
        local it = b._it
        if it.art then
            local ok, name = pcall(it.art)
            if ok and name and name ~= b._art then
                b._art = name
                b._glyph:SetTexture(ICONS .. name)
            end
        end
        if it.dim then
            local ok, v = pcall(it.dim)
            local dim = ok and v and true or false
            if dim ~= b._dim then
                b._dim = dim
                PaintButton(b, false)
            end
        end
    end
    local sb = rail.buttons.scroll
    local cf = Chat.SelectedFrame and Chat.SelectedFrame()
    local up = false
    if CP.RailItemOn("scroll") and not Chat.raidHidden and cf and cf.AtBottom then
        local ok, at = pcall(cf.AtBottom, cf)
        up = ok and at == false
    end
    if sb:IsShown() ~= up then
        sb:SetShown(up)
        if not up then PaintButton(sb, false) end
    end
    for id in pairs(rail.shown or {}) do
        local b = rail.buttons[id]
        if not b:IsShown() then b:Show() end
    end
    if (rail.slow or 99) >= 5 then
        rail.slow = 0
        for _, it in ipairs(CP.RAIL_ITEMS) do
            local b = rail.buttons[it.id]
            if it.count_fn and b._count and b:IsShown() then
                local ok, txt = pcall(it.count_fn)
                txt = ok and txt or ""
                if txt ~= b._countText then
                    b._countText = txt
                    b._count:SetText(txt)
                end
            end
        end
    end
end

-- after every chat refresh (Blz_Chat calls it) and every switch here
function CP.RailRefresh(d)
    d = d or DB()
    local want = CP.RailOn() and Chat.Built and Chat.Built()
    if not want then
        if rail.frame then rail.frame:Hide() end
        CP.InsetText(0)
        CP.RailSeam()
        return
    end
    local cf = DEFAULT_CHAT_FRAME
    local bg = cf and cf._zui_chatbg
    if not bg then return end
    BuildRail()
    PaintRail(d)
    PlaceRail(d)
    -- up while the dock is (any docked window shown: General is hidden
    -- while another docked tab is selected, and the rail stays)
    rail.frame:SetShown((Chat.DockUp and Chat.DockUp() or bg:IsShown()) and true or false)
    CP.RailSeam()
    rail.t, rail.slow = 99, 99
    CP.RailTick()
end
Chat.RailRefresh = CP.RailRefresh
-- a chat window shown or hidden (Blz_Chat's SyncBar): the rail with the dock
function CP.RailSync()
    local f = rail.frame
    if not f then return end
    local up = CP.RailOn() and Chat.DockUp and Chat.DockUp() and true or false
    if f:IsShown() ~= up then f:SetShown(up) CP.RailSeam() end
end
Chat.RailSync = CP.RailSync

RailMenu = function(owner)
    local UI = ns.UI
    if not (UI and UI.ContextMenu) then return end
    local items = { { text = "On the icon rail", isTitle = true } }
    for _, it in ipairs(CP.RAIL_ITEMS) do
        if CP.RailItemHere(it.id) then
            items[#items + 1] = { text = it.label, keepOpen = true,
                checked = function() return CP.RailItemOn(it.id) end,
                func = function() CP.SetRailItem(it.id, not CP.RailItemOn(it.id)) end }
        end
    end
    items[#items + 1] = { separator = true }
    items[#items + 1] = { text = "Chat settings...", func = function() if ns.OpenConfig then ns.OpenConfig("chat") end end }
    UI.ContextMenu(items)
end

-- ============================================================
-- THE CHAT PAGE: Look and Position
-- ============================================================
local function AddTab(page, tab, label, build)
    if ns.AddPageTab then return ns.AddPageTab(page, tab, label, build) end
    ns.PageTabs = ns.PageTabs or {}
    local list = ns.PageTabs[page] or {}
    ns.PageTabs[page] = list
    list[#list + 1] = { tab = tab, label = label, build = build }
end

local function Changed()
    if Chat.Refresh then pcall(Chat.Refresh) end
    if ns.SettingsChanged then ns.SettingsChanged("chat.panel") end
end

local function ColorRow(L, UI, label, key, fallback, alpha)
    local d = DB()
    return UI.ColorPicker(L.current, { label = label, alpha = alpha,
        get = function()
            local c = d[key]
            if type(c) == "table" then return ns.ColorOf(c) end
            return fallback()
        end,
        set = function(r, g, b, a) d[key] = { r = r, g = g, b = b, a = a or 1 } Changed() end,
        default = fallback,
        reset = function() d[key] = nil Changed() end })
end

AddTab("chat", "look", "Look", function(L)
    local UI = ns.UI
    local d = DB()
    if Allowed(PANEL_ID) then
        L:Card("Panel texture and border")
        if UI.TexturePicker then
            local tp = UI.TexturePicker(L.current, { label = "Panel texture", defaultLabel = "Flat (as before)",
                get = function() return d.panelTexture end,
                set = function(v) d.panelTexture = v Changed() end,
                defaultPath = function() return ns.FLAT end,
                width = 260 })
            L:Add(tp, 8)
        end
        L:Row(UI.Slider(L.current, { width = 220, min = 0, max = 6, step = 1,
            value = tonumber(d.panelBorderSize) or 1, label = "Border size",
            format = function(v) return v == 0 and "none" or (v .. " px") end,
            onChange = function(v) d.panelBorderSize = (v ~= 1) and v or nil Changed() end }), 40)
        local MODES = { { value = "own", text = "The palette / the colour picked" },
            { value = "accent", text = "The accent colour" }, { value = "class", text = "Your class colour" } }
        local function ModeText()
            local m = d.panelBorderMode or "own"
            for _, it in ipairs(MODES) do if it.value == m then return it.text end end
            return MODES[1].text
        end
        L:Add(UI.Field(L.current, "Border colour", function(h)
            return UI.Dropdown(h, { width = 240, items = function() return MODES end,
                selectedValue = function() return d.panelBorderMode or "own" end,
                selected = ModeText,
                onSelect = function(v) d.panelBorderMode = (v ~= "own") and v or nil Changed() end })
        end, { width = 240 }), 6)
        local inner = UI.Checkbox(L.current, "A thin line inside the border", d.panelInner == true, function(v)
            d.panelInner = v and true or nil
            Changed()
            if ns.RefreshConfig then ns.RefreshConfig() end
        end)
        L:Row(inner, 17)
        L:Dependent({ ColorRow(L, UI, "Inner line colour", "panelInnerColor", function()
            local c = GetColor("ui", "accent") return c.r, c.g, c.b, 0.45 end, true) }, d.panelInner == true, 1, nil, "A thin line inside the border")
        L:Desc("Shown on the preview above. On the Classic look the edge is the game's art and keeps its own size.")
        L:EndCard()
    end
    if Allowed(TABS_ID) then
        L:Card("Tab names")
        local function Stock() local c = GetColor("text", "normal") return c.r, c.g, c.b, 1 end
        L:Grid({
            ColorRow(L, UI, "The tab you are on", "tabNameActive", Stock),
            ColorRow(L, UI, "The other tabs", "tabNameColor", Stock),
        }, 2)
        L:Row(UI.Slider(L.current, { width = 220, min = 0, max = 20, step = 1, value = tonumber(d.tabPadX) or DefPadX(),
            label = "Chip padding across", format = function(v) return v .. " px" end,
            onChange = function(v) d.tabPadX = (v ~= DefPadX()) and v or nil Changed() end }), 40)
        L:Row(UI.Slider(L.current, { width = 220, min = 0, max = 12, step = 1, value = tonumber(d.tabPadY) or DefPadY(),
            label = "Chip padding up and down", format = function(v) return v .. " px" end,
            onChange = function(v) d.tabPadY = (v ~= DefPadY()) and v or nil Changed() end }), 40)
        L:Desc("Blank colours: white (65% on the other tabs) under ZacUI's look, the game's own under the others. "
            .. "Where the tabs sit along the strip stays the game's.")
        L:EndCard()
    end
    -- the match pass's switches (Blz_Chat; ZacUI's look only)
    if Chat.ZacLook and Chat.ZacLook() then
        L:Card("Polish")
        local function Re() Changed() if ns.RefreshConfig then ns.RefreshConfig() end end
        L:Row(UI.Checkbox(L.current, "Polished chat styling", d.refStyle ~= false, function(v)
            if v then d.refStyle = nil else d.refStyle = false end
            Re()
        end, { tooltip = "A deep blue-black panel with faint 1 px edges, the strip behind the tabs in the panel's colour, "
            .. "tab names in ZacUI's font in white, a 1 px underline, ZacUI's font outlined on messages and the edit box, "
            .. "and ZacUI's resize grip. Colours and fonts you pick still win. Nothing moves." }), 17)
        L:Dependent({
            UI.Checkbox(L.current, "Tabs as tiles", d.tabTiles == true, function(v)
                d.tabTiles = v and true or nil
                Re()
            end, { tooltip = "Each tab a tile as wide as the tab, the strip as tall as it takes to centre the names. "
                .. "The strip's height changes; off keeps today's layout." }),
            UI.Checkbox(L.current, "Indent wrapped lines", d.indent ~= false, function(v)
                if v then d.indent = nil else d.indent = false end
                Changed()
            end, { tooltip = "A message too long for one line carries on under its first words rather than at the "
                .. "chat's edge, so where each message starts is easy to see." }),
        }, d.refStyle ~= false, 1, nil, "Polished chat styling")
        L:EndCard()
    end
end)

AddTab("chat", "general", "General", function(L)
    CP.RailCard(L)
    if not (CP.Available("zcog") or CP.Available("zmenu")) then return end
    local UI = ns.UI
    L:Card("Bar buttons")
    local cog = UI.Checkbox(L.current, "A chat settings button (a cog)", CP.ItemOn("zcog"), function(v)
        CP.SetItem("zcog", v)
    end, { tooltip = "A cog at the right end of the bar that opens this page." })
    L:Row(cog, 17)
    if CP.Available("zmenu") then
        local menu = UI.Checkbox(L.current, "The game's chat menu button", CP.ItemOn("zmenu"), function(v)
            CP.SetItem("zmenu", v)
        end, { tooltip = "The game's own chat menu - emotes, languages, voice - which ZacUI's chat otherwise "
            .. "tucks away with the button column." })
        L:Row(menu, 17)
    end
    L:Desc("Once on, they are in \"What the bar shows\" with the rest and step off first when the bar is narrow.")
    L:EndCard()
end)

-- THE ICON RAIL's card (General)
function CP.RailCard(L)
    if not Allowed(RAIL_ID) then return end
    local UI = ns.UI
    local d = DB()
    L:Card("Icon rail")
    if not CP.RailAvailable() then
        L:Desc("The icon rail is part of ZacUI's chat look. Under a game look the chat is the game's own, "
            .. "with the game's own chat buttons.")
        L:EndCard()
        return
    end
    local function Refresh() if ns.RefreshConfig then ns.RefreshConfig() end end
    local master = UI.Checkbox(L.current, "Show the icon rail", CP.RailOn(), function(v)
        CP.SetRail(v)
        Refresh()
    end, { tooltip = "A column of icons beside the chat panel: friends online, copy chat, these settings, and a "
        .. "button back to the newest line while you are scrolled up. Right-click the rail to switch icons." })
    L:Row(master, 17)
    local boxes = {}
    for _, it in ipairs(CP.RAIL_ITEMS) do
        if CP.RailItemHere(it.id) then
            boxes[#boxes + 1] = UI.Checkbox(L.current, it.label, CP.RailItemOn(it.id), function(v)
                CP.SetRailItem(it.id, v)
            end)
        end
    end
    local hover = UI.Checkbox(L.current, "Only while the mouse is over the chat", CP.RailHover(), function(v)
        if v then DB().railHover = nil else DB().railHover = false end
        if rail.frame then rail.frame:SetAlpha(1) end
    end, { tooltip = "On: the icons fade in when you mouse over the chat or the icons, and fade out after. "
        .. "Off: they always show." })
    table.insert(boxes, 1, hover)
    L:Dependent(boxes, CP.RailOn(), 2, nil, "Show the icon rail")
    local SIDES = { { value = "auto", text = "Left (right when there is no room)" },
        { value = "left", text = "Outside, left of the chat" }, { value = "right", text = "Outside, right of the chat" } }
    local function SideText()
        local v = d.railSide or "auto"
        for _, it in ipairs(SIDES) do if it.value == v then return it.text end end
        return SIDES[1].text
    end
    L:Add(UI.Field(L.current, "Side", function(h)
        return UI.Dropdown(h, { width = 240, items = function() return SIDES end,
            selectedValue = function() return d.railSide or "auto" end,
            selected = SideText,
            onSelect = function(v) d.railSide = (v ~= "auto") and v or nil CP.RailRefresh() end })
    end, { width = 240 }), 6)
    L:Desc("Icons that do not fit the chat's height are left off from the bottom of the list. "
        .. "Friends, guild, character and channels open out of combat only (they are the game's own windows).")
    L:EndCard()
end

AddTab("chat", "pos", "Position", function(L)
    if not Allowed(LOCK_ID) then return end
    local UI = ns.UI
    local d = DB()
    L:Card("Size")
    local cb = UI.Checkbox(L.current, "Lock the chat's size", CP.LockOn(), function(v)
        d.lockSize = v and true or nil
        CP.ApplyLock()
    end, { tooltip = "The resize grip in the chat's corner stops working (and is not drawn), so the chat cannot be "
        .. "resized by a stray drag. Moving it is the game's own Lock Window, on the tab's right-click menu." })
    L:Row(cb, 17)
    L:EndCard()
end)

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("chat", "texture border thickness inner line class accent tab name colour color padding "
        .. "lock size resize grip cog settings button chat menu emote language icon rail sidebar friends online "
        .. "copy chat scroll bottom newest guild durability channels")
end
