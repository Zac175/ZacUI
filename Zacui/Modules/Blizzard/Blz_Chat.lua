-- Blz_Chat - chat frames, tabs, edit box and the chat menu buttons, and
-- the info bar that makes the docked chat a panel rather than a box.
-- Part of ZacUI; load order is set by the TOC.
--
-- THE PANEL. Each chat window sits on a dark panel. The docked chat (the
-- General tab and everything docked with it) also gets a BAR along the
-- bottom of that panel:
--
--   [S][G][W 2][P][R]  Latest            Bags 23 | Dur 98% | 412g | 60fps | 42ms
--    channel buttons    jump to newest    whatever the Chat page has ticked
--
-- and A STRIP ALONG THE TOP that the docked tabs sit on. The tab you are
-- on wears a raised chip with a gold line under it, and a tab with
-- something new pulses its line. By default the tabs and their strip are
-- HIDDEN UNTIL THE MOUSE IS OVER THE CHAT and fade in when it is; a tab
-- with something new shows regardless.
--
-- and THE EDIT BOX OPENS IN THAT BAR. Blizzard hangs the edit box under
-- the chat frame, where it sat half over the bottom of the panel; now the
-- bar is where you type, the buttons and numbers step aside while you do,
-- and nothing overlaps anything. Under the panel or above the tabs are
-- the other two choices on the Chat page.
--
-- NOTHING HERE LISTENS TO A BUSY EVENT. The bar reads its numbers on its
-- own clock (a quarter of a second for the two things that should feel
-- immediate, a second or slower for the rest) and only while it is on
-- screen; the only events are whispers arriving and leaving.
--
-- PRAT. Prat replaces the edit box with its own and re-asserts it, so
-- when Prat is loaded this file leaves every edit box alone. The bar is
-- ours either way.
--
-- TWO CHAT CODE BASES. Newer clients moved the ChatEdit_* globals onto
-- ChatFrameUtil and the edit box itself; every call into Blizzard's chat
-- goes through a small wrapper below that takes whichever exists.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local ClearButtonArt = ns.ClearButtonArt
local GetColor = ns.GetColor
local Hex = ns.Hex
local HideNamed = ns.HideNamed
local Modules = ns.Modules
local Print = ns.Print
local SkinAnyScrollBar = ns.SkinAnyScrollBar
local SkinArrowButton = ns.SkinArrowButton
local SkinBackdrop = ns.SkinBackdrop
local SkinEditBox = ns.SkinEditBox
local StripDeep = ns.StripDeep
local TintBorder = ns.TintBorder
local ZUI = ns.ZUI

local Chat = {}
local dock = {}        -- the bar's pieces, once built
local whispers = { unread = 0, log = {} }

local PAD    = 4       -- panel past the text: left, right and top
local TAB_PAD_X, TAB_PAD_Y = 7, 4   -- a tab's chip past its label
local FOOT   = 8       -- panel past the text at the bottom, with no bar
local GAP    = 6       -- bottom of the text to the top of the bar
local BAR_H  = 22
local EDIT_H = 24
local KEEP_WHISPERS = 5
local COPY_LINES = 500

-- THE MATCH PASS (2026-11-08, Zac: "his chat has some styling that i
-- like"): under the ZacUI look the chat wears the reference chat's
-- numbers (zui_tests/MATCH_CHAT_1108.md lists each with its source). The
-- panel a dark blue-black at 65%, every edge and divider one physical
-- pixel of white at 6%; the tab strip the panel carried on behind the
-- tabs, each tab a 44% (selected 65%) tile of the panel colour with its
-- name at 11 in white (65% unselected), the selected one underlined one
-- pixel in the accent, a 6% hairline between tabs; the bar under the
-- text the panel itself with the 6% divider over it; the edit box 23
-- high; wrapped lines indented; the resize grip ZacUI's own glyph at 40%.
-- A colour or font picked on the Chat page still wins over every one.
-- Sizes and spots of the chat itself are never moved.
local REF = {
    bg = { 0.03, 0.045, 0.05 }, bgA = 0.65,
    edge = { 1, 1, 1, 0.06 },
    tabIdleA = 0.44, tabActiveA = 0.65, tabHoverA = 0.55,
    tabText = { 1, 1, 1, 0.65 }, tabTextActive = { 1, 1, 1, 1 },
    tabSize = 11, tabH = 24, tabPadX = 12, tabPadY = 6,
    editH = 23,
    gripSize = 18, gripX = 4, gripY = -3, gripA = 0.4, gripHoverA = 0.9,
}
-- Zac (2026-11-08): "i still like how its layed out mostly" - so the pass
-- moves nothing: no size, spot or saved value changes; the polish is one
-- switch (chat.refStyle = false turns it all off) and the reference's tab
-- tiles (which change the strip's height) are a second, off by default
-- (chat.tabTiles).
-- the chat's part wears ZacUI's own look (the only one the skin runs under;
-- the Chat page's preview can draw another look through Look.With)
local function ZacLook()
    local L = ns.Look
    if not (L and L.For) then return true end
    local l = L.For("chat")
    return l == nil or l.id == "zacui"
end
-- ...and the polish is on
local function Match()
    if not ZacLook() then return false end
    local c = type(ZacUIDB) == "table" and ZacUIDB.chat
    return not (type(c) == "table" and c.refStyle == false)
end
-- the reference's tab tiles (strip height from the name, tiles the tab's
-- width): opt-in, they change the strip's height
local function Tiles()
    local c = type(ZacUIDB) == "table" and ZacUIDB.chat
    return Match() and type(c) == "table" and c.tabTiles == true
end

-- ============================================================
-- SMALL THINGS
-- ============================================================
local function Dim(s) return "|cff" .. Hex(GetColor("text", "gray")) .. s .. "|r" end
local function Tone(key, s) return "|cff" .. Hex(GetColor("text", key)) .. s .. "|r" end

-- A readout's number in its colour: green when it is fine, then yellow,
-- orange, red. `limits` are the three edges, best first; `high` says
-- whether a bigger number is the better one (fps, free bags) or not (ms).
local function Rate(v, limits, high)
    local a, b, c = limits[1], limits[2], limits[3]
    local key
    if high then
        key = (v >= a and "green") or (v >= b and "yellow") or (v >= c and "orange") or "red"
    else
        key = (v <= a and "green") or (v <= b and "yellow") or (v <= c and "orange") or "red"
    end
    return Tone(key, tostring(v))
end
local BAGS_AT = { 11, 4, 1 }       -- free slots
local DUR_AT  = { 80, 51, 21 }     -- percent, the most worn piece
local FPS_AT  = { 60, 40, 20 }
local MS_AT   = { 100, 150, 300 }
local function Dur(pct) return Tone(((pct >= DUR_AT[1] and "green") or (pct >= DUR_AT[2] and "yellow")
    or (pct >= DUR_AT[3] and "orange") or "red"), pct .. "%") end

-- 12g 34s 56c, as text (a bar that changes width by a coin icon twitches)
local function Money(copper)
    copper = math.floor(math.abs(copper or 0))
    local g = math.floor(copper / 10000)
    local s = math.floor(copper / 100) % 100
    local c = copper % 100
    local out = {}
    if g > 0 then
        out[#out + 1] = Tone("coin", ((BreakUpLargeNumbers and BreakUpLargeNumbers(g)) or g) .. "g")
    end
    if s > 0 or g > 0 then out[#out + 1] = Tone("silver", s .. "s") end
    out[#out + 1] = Tone("copper", c .. "c")
    return table.concat(out, " ")
end

local function PratOwns() return _G.Prat ~= nil end

local function EachChatFrame(fn)
    for _, name in ipairs(CHAT_FRAMES or {}) do
        local cf = _G[name]
        if cf then fn(cf, name) end
    end
end

local function EditBoxOf(cf)
    if not cf then return nil end
    return cf.editBox or (cf.GetName and cf:GetName() and _G[cf:GetName() .. "EditBox"])
end

-- the docked chat: the General window and everything docked with it,
-- which Blizzard keeps at exactly the General window's position and size
local function InDock(cf)
    return cf ~= nil and (cf == DEFAULT_CHAT_FRAME or cf.isDocked == true or cf.isDocked == 1)
end

-- the docked window you are looking at
local function SelectedFrame()
    local f = SELECTED_DOCK_FRAME
    if not f and FCFDock_GetSelectedWindow and GENERAL_CHAT_DOCK then
        local ok, sel = pcall(FCFDock_GetSelectedWindow, GENERAL_CHAT_DOCK)
        if ok then f = sel end
    end
    if f and f.IsShown and f:IsShown() then return f end
    return DEFAULT_CHAT_FRAME
end

-- ---- Blizzard's chat, old names or new ----
local function OpenChat(text, cf)
    local fn = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
    if fn then return fn(text, cf or SelectedFrame()) end
end

local function ReplyTell(cf)
    local fn = (ChatFrameUtil and ChatFrameUtil.ReplyTell) or ChatFrame_ReplyTell
    if fn then fn(cf or SelectedFrame()) end
end

local function LastTell()
    local fn = (ChatFrameUtil and ChatFrameUtil.GetLastTellTarget) or ChatEdit_GetLastTellTarget
    if not fn then return nil end
    local ok, name = pcall(fn)
    if ok and name and name ~= "" then return name end
    return nil
end

local function ChatTypeOf(eb)
    if eb.GetChatType then return eb:GetChatType() end
    return eb.GetAttribute and eb:GetAttribute("chatType")
end

local function ChannelOf(eb)
    if eb.GetChannelTarget then return eb:GetChannelTarget() end
    return eb.GetAttribute and eb:GetAttribute("channelTarget")
end

local function Tip(owner, title)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    local t = GetColor("tooltip", "title")
    GameTooltip:SetText(title, t.r, t.g, t.b)
end

local function TipLine(left, right)
    local b = GetColor("tooltip", "body")
    if right then
        GameTooltip:AddDoubleLine(left, right, b.r, b.g, b.b, b.r, b.g, b.b)
    else
        GameTooltip:AddLine(left, b.r, b.g, b.b, true)
    end
end

local function TipHint(text)
    local g = GetColor("text", "gray")
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(text, g.r, g.g, g.b, true)
end

-- ============================================================
-- WHAT THE BAR CAN SHOW
-- ============================================================
-- One entry per number. `text` returns what to print ("" hides the item
-- for now - no group, no guild, an instance with no coordinates); `every`
-- is how many seconds between reads; `keep` is the order they are kept in
-- when the chat is too narrow for all of them (1 survives longest);
-- `sample` is the widest text it is expected to show, which is the room
-- it is given on the bar from the start (see SetItemText).
-- They sit on the bar in the order of this list, left to right.
local function BagSlots()
    local free, total = 0, 0
    local Free = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
    local Size = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    if not (Free and Size) then return 0, 0 end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local f, family = Free(bag)
        -- quivers, soul bags and profession bags hold one kind of thing;
        -- room in them is not room for loot
        if not family or family == 0 then
            free = free + (f or 0)
            total = total + (Size(bag) or 0)
        end
    end
    return free, total
end

local WEAR_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }
local function Wear()
    local low
    for _, slot in ipairs(WEAR_SLOTS) do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            local pct = cur / max
            if not low or pct < low then low = pct end
        end
    end
    return low
end

local function OnlineFriends()
    local n = 0
    if C_FriendList and C_FriendList.GetNumOnlineFriends then
        n = C_FriendList.GetNumOnlineFriends() or 0
    end
    if BNGetNumFriends then
        local ok, _, online = pcall(BNGetNumFriends)
        if ok and online then n = n + online end
    end
    return n
end

local function RealmClock()
    local h, m
    if GetCVarBool and GetCVarBool("timeMgrUseLocalTime") then
        h, m = tonumber(date("%H")), tonumber(date("%M"))
    else
        h, m = GetGameTime()
    end
    return h, m
end

local function ClockText(h, m)
    if not h then return "" end
    if GetCVarBool and GetCVarBool("timeMgrUseMilitaryTime") then
        return string.format("%02d:%02d", h, m)
    end
    local suffix = (h >= 12) and "pm" or "am"
    h = h % 12
    if h == 0 then h = 12 end
    return string.format("%d:%02d", h, m) .. Dim(suffix)
end

local LOOT_NAMES = {
    freeforall = "LOOT_FREE_FOR_ALL", roundrobin = "LOOT_ROUND_ROBIN", master = "LOOT_MASTER_LOOTER",
    group = "LOOT_GROUP_LOOT", needbeforegreed = "LOOT_NEED_BEFORE_GREED",
}

local ITEMS = {
    { id = "group", sample = "Raid 40", label = "Group size", default = true, keep = 6, every = 2,
      text = function()
          if IsInRaid and IsInRaid() then
              return Dim((RAID or "Raid") .. " ") .. (GetNumGroupMembers() or 0)
          elseif IsInGroup and IsInGroup() then
              return Dim((PARTY or "Party") .. " ") .. (GetNumGroupMembers() or 0)
          end
          return ""
      end,
      tip = function(self)
          local raid = IsInRaid and IsInRaid()
          Tip(self, raid and (RAID or "Raid") or (PARTY or "Party"))
          local n = GetNumGroupMembers() or 0
          TipLine("Members", tostring(n))
          if raid and GetRaidRosterInfo then
              local offline, dead = 0, 0
              for i = 1, n do
                  local name, _, _, _, _, _, _, online, isDead = GetRaidRosterInfo(i)
                  if name then
                      if not online then offline = offline + 1 elseif isDead then dead = dead + 1 end
                  end
              end
              TipLine("Offline", offline > 0 and Tone("red", tostring(offline)) or "0")
              TipLine("Dead", dead > 0 and Tone("orange", tostring(dead)) or "0")
          end
          if GetLootMethod then
              local method = GetLootMethod()
              if type(method) == "string" then
                  TipLine("Loot", _G[LOOT_NAMES[method] or ""] or method)
              end
          end
          if GetLootThreshold then
              local q = GetLootThreshold()
              local name = q and _G["ITEM_QUALITY" .. q .. "_DESC"]
              local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
              if name and c then
                  TipLine("Threshold", string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name))
              end
          end
      end },

    { id = "guild", sample = "Guild 999", label = "Guild members online", default = false, keep = 9, every = 5,
      text = function()
          if not (IsInGuild and IsInGuild()) then return "" end
          local _, online = GetNumGuildMembers()
          return Dim((GUILD or "Guild") .. " ") .. (online or 0)
      end,
      tip = function(self)
          local T = ns.MinimapTips
          if T and T.Guild then T.Guild(self) else Tip(self, GUILD or "Guild") end
      end,
      click = function()
          local T = ns.MinimapTips
          if T and T.OpenSocial then T.OpenSocial() end
      end },

    { id = "friends", sample = "Friends 99", label = "Friends online", default = false, keep = 8, every = 5,
      text = function() return Dim((FRIENDS or "Friends") .. " ") .. OnlineFriends() end,
      tip = function(self)
          local T = ns.MinimapTips
          if T and T.Friends then T.Friends(self) else Tip(self, FRIENDS or "Friends") end
      end,
      click = function()
          local T = ns.MinimapTips
          if T and T.OpenSocial then T.OpenSocial() end
      end },

    { id = "coords", sample = "100.0, 100.0", label = "Coordinates", default = false, keep = 10, every = 0.5,
      text = function()
          local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
          local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
          if not pos then return "" end
          local x, y = pos:GetXY()
          if not (x and y) or (x == 0 and y == 0) then return "" end
          return string.format("%.1f, %.1f", x * 100, y * 100)
      end,
      tip = function(self)
          Tip(self, "Coordinates")
          TipLine((GetZoneText and GetZoneText()) or "")
          local sub = GetSubZoneText and GetSubZoneText()
          if sub and sub ~= "" then TipLine(sub) end
      end },

    { id = "bags", sample = "Bags 88", label = "Free bag slots", default = true, keep = 2, every = 2,
      text = function()
          local free, total = BagSlots()
          if total == 0 then return "" end
          return Dim("Bags ") .. Rate(free, BAGS_AT, true)
      end,
      tip = function(self)
          Tip(self, "Bag space")
          local Free = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
          local Size = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
          local Name = (C_Container and C_Container.GetBagName) or GetBagName
          for bag = 0, (NUM_BAG_SLOTS or 4) do
              local size = Size and Size(bag) or 0
              if size > 0 then
                  local name = (bag == 0 and (BACKPACK_TOOLTIP or "Backpack")) or (Name and Name(bag)) or ("Bag " .. bag)
                  TipLine(name, (Free(bag) or 0) .. " / " .. size)
              end
          end
          TipHint("Click to open your bags")
      end,
      click = function() if ToggleAllBags then ToggleAllBags() end end },

    { id = "dur", sample = "Dur 100%", label = "Durability", default = true, keep = 1, every = 3,
      text = function()
          local low = Wear()
          if not low then return "" end
          local pct = math.floor(low * 100 + 0.5)
          return Dim("Dur ") .. Dur(pct)
      end,
      tip = function(self)
          Tip(self, DURABILITY or "Durability")
          for _, slot in ipairs(WEAR_SLOTS) do
              local cur, max = GetInventoryItemDurability(slot)
              if cur and max and max > 0 then
                  local pct = math.floor(cur / max * 100 + 0.5)
                  TipLine(GetInventoryItemLink("player", slot) or ("Slot " .. slot), Dur(pct))
              end
          end
          TipHint("The bar shows your most worn piece")
      end },

    { id = "gold", sample = "99g 99s", label = "Gold", default = true, keep = 3, every = 2,
      text = function()
          local copper = GetMoney and GetMoney() or 0
          local g = math.floor(copper / 10000)
          if g >= 100 then
              return Tone("coin", ((BreakUpLargeNumbers and BreakUpLargeNumbers(g)) or g) .. "g")
          elseif g >= 1 then
              return Tone("coin", g .. "g") .. " " .. Tone("silver", (math.floor(copper / 100) % 100) .. "s")
          end
          return Tone("silver", (math.floor(copper / 100) % 100) .. "s") .. " " .. Tone("copper", (copper % 100) .. "c")
      end,
      tip = function(self)
          Tip(self, "Gold")
          local copper = GetMoney and GetMoney() or 0
          TipLine("This character", Money(copper))
          local diff = copper - (dock.money0 or copper)
          if diff > 0 then
              TipLine("Since you logged in", Tone("green", "+ ") .. Money(diff))
          elseif diff < 0 then
              TipLine("Since you logged in", Tone("red", "- ") .. Money(diff))
          else
              TipLine("Since you logged in", Dim("no change"))
          end
      end },

    { id = "fps", sample = "999fps", label = "Frames per second", default = true, keep = 5, every = 1,
      text = function()
          local fps = math.floor((GetFramerate and GetFramerate() or 0) + 0.5)
          return Rate(fps, FPS_AT, true) .. Dim("fps")
      end,
      tip = function(self)
          Tip(self, "Frames per second")
          TipLine("How smoothly the game is drawing right now.")
      end },

    { id = "ms", sample = "999ms", label = "Latency", default = true, keep = 4, every = 2,
      text = function()
          local _, _, home, world = GetNetStats()
          local ms = math.max(home or 0, world or 0)
          return Rate(ms, MS_AT, false) .. Dim("ms")
      end,
      tip = function(self)
          Tip(self, "Latency")
          local _, _, home, world = GetNetStats()
          TipLine("Home (chat, auction house)", (home or 0) .. " ms")
          TipLine("World (combat, movement)", (world or 0) .. " ms")
          TipHint("The bar shows the worse of the two")
      end },

    { id = "clock", sample = "12:00pm", label = "Clock", default = false, keep = 7, every = 5,
      text = function() return ClockText(RealmClock()) end,
      tip = function(self)
          Tip(self, "Time")
          local h, m = GetGameTime()
          TipLine("Realm", ClockText(h, m))
          TipLine("Yours", ClockText(tonumber(date("%H")), tonumber(date("%M"))))
          TipLine(date("%A %d %B"))
          TipHint("Click for the alarm and stopwatch")
      end,
      click = function()
          if TimeManager_LoadUI then pcall(TimeManager_LoadUI) end
          if TimeManager_Toggle then TimeManager_Toggle() end
      end },
}

-- Numbers for the look (the rest of it - colours, fonts, animations -
-- is unset until chosen):
--   barHeight      the bar under the chat
--   editHeight     the edit box (where it is not filling the bar)
--   tabLine        the line under the tab you are on
--   tabFadeIn / tabFadeOut / tabLinger   the tabs on mouseover
--   timeVisible / fadeDuration           old messages fading (0 = Blizzard's)
local LOOK = {
    barHeight = BAR_H, editHeight = EDIT_H, tabLine = 2,
    tabFadeIn = 0.12, tabFadeOut = 0.30, tabLinger = 0.6,
    timeVisible = 0, fadeDuration = 0,
}

local BY_KEEP = {}
for i, it in ipairs(ITEMS) do BY_KEEP[i] = it end
table.sort(BY_KEEP, function(a, b) return a.keep < b.keep end)

-- ============================================================
-- SETTINGS
-- ============================================================
-- The docked edit box and the bar are what was asked for, so they are on
-- from the first load. Everything else starts where the addon already
-- was: 75% panel, no fading.
local function DB()
    ZacUIDB.chat = ZacUIDB.chat or {}
    local d = ZacUIDB.chat
    if d.bar == nil then d.bar = true end
    if d.editBox ~= "bar" and d.editBox ~= "below" and d.editBox ~= "above" then d.editBox = "bar" end
    -- (the reference's 65% and 1 px line are NOT defaults: Zac keeps his
    -- chat as it is; both are one slider away on the Chat page)
    if type(d.opacity) ~= "number" then d.opacity = 0.75 end
    if d.fade == nil then d.fade = false end
    if d.arrows == nil then d.arrows = true end
    if d.tint == nil then d.tint = true end
    if d.channels == nil then d.channels = true end
    if d.whispers == nil then d.whispers = true end
    if d.latest == nil then d.latest = true end
    if d.tabs == nil then d.tabs = true end
    if d.tabStrip == nil then d.tabStrip = true end
    -- when the tabs show: "hover" (mouse over the chat), "always", or
    -- "blizzard" (the game's own dimming, left alone)
    -- raid mode (RAID MODE below): off until switched on
    if d.raidMode == nil then d.raidMode = false end
    -- ...and in a 5-man party too while it is on (the party frames)
    if d.raidModeParty == nil then d.raidModeParty = true end
    if d.tabsVisible ~= "hover" and d.tabsVisible ~= "always" and d.tabsVisible ~= "blizzard" then
        d.tabsVisible = "hover"
    end
    d.tabsShow = nil    -- retired: replaced by tabsVisible
    if type(d.items) ~= "table" then d.items = {} end
    for _, it in ipairs(ITEMS) do
        if d.items[it.id] == nil then d.items[it.id] = it.default end
    end
    -- THE LOOK (Screen > Chat): every default is what this file drew
    -- before the setting existed. Colours and fonts left unset are "as
    -- before" (the palette, ZacUI's font for the bar, Blizzard's own
    -- fonts for tabs, edit box and messages), so they have no default.
    for k, v in pairs(LOOK) do
        if d[k] == nil then d[k] = v end
    end
    return d
end

-- ============================================================
-- THE LOOK - shared by the real chat and the Chat page's preview
-- ============================================================
local function Empty(spec) return type(spec) ~= "table" or next(spec) == nil end
local function HouseOutline()
    local f = ZacUIDB and ZacUIDB.font
    return (f and f.outline == "NONE") and "none" or "outline"
end
local function Delta()
    local f = ZacUIDB and ZacUIDB.font
    return (f and f.delta) or 0
end
-- a colour setting, or the palette's
local function ColorOr(c, cat, key, alpha)
    if type(c) == "table" then return ns.ColorOf(c) end
    local p = GetColor(cat, key)
    return p.r, p.g, p.b, alpha or p.a or 1
end

-- The bar's height and the hover fade's timings, read once per Refresh
-- into dock (they are used ten times a second while the mouse fades).
local function BarH() return dock.barH or BAR_H end
local function EditH()
    return math.max(16, math.min(40, tonumber(DB().editHeight) or EDIT_H))
end

-- The bar's text: ZacUI's font at the house small size, or the chosen
-- font (whose size is absolute).
local function StyleBarText(fs, d)
    if not fs then return end
    d = d or DB()
    if Empty(d.barFont) then
        if fs._zCustom then
            fs._zCustom = nil
            if ns.HouseFont then ns.HouseFont(fs, ns.UI.F.SMALL) end
            if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
        end
    elseif ns.ApplyFontSpec then
        fs._zCustom = true
        ns.ApplyFontSpec(fs, d.barFont, { size = ns.UI.F.SMALL + Delta(), outline = HouseOutline(), shadow = true })
    end
end

-- A Blizzard string (tab label, edit box, a chat window's messages) in
-- the chosen font, or back to what it had. `keepSize` leaves the size to
-- Blizzard unless the spec names one (each chat window has its own).
local function StyleBlizzText(fs, spec, keepSize)
    if not (fs and fs.GetFont and fs.SetFont) then return end
    if Empty(spec) then
        local s = fs._zStockFont
        if s then
            fs._zStockFont = nil
            local _, size = fs:GetFont()
            pcall(fs.SetFont, fs, s[1], keepSize and (size or s[2]) or s[2], s[3])
            if fs.SetShadowOffset then fs:SetShadowOffset(s[4] or 0, s[5] or 0) end
        end
        return
    end
    if not ns.ApplyFontSpec then return end
    if not fs._zStockFont then
        local p, size, flags = fs:GetFont()
        local sx, sy = 0, 0
        if fs.GetShadowOffset then sx, sy = fs:GetShadowOffset() end
        fs._zStockFont = { p, size, flags, sx, sy }
    end
    local s = fs._zStockFont
    local _, curSize = fs:GetFont()
    ns.ApplyFontSpec(fs, spec, { fallbackFace = s[1],
        size = (keepSize and curSize) or s[2] or 12,
        outline = (s[3] and s[3] ~= "") and s[3] or "none",
        shadow = (s[4] or 0) ~= 0 or (s[5] or 0) ~= 0, shadowX = s[4], shadowY = s[5] })
end

-- WHICH FONT A BLIZZARD STRING WEARS: the one picked on the Chat page, or
-- under the ZacUI look (the match pass) ZacUI's face, outlined as the
-- house outline says - the tab names at the reference's 11, messages at
-- each window's own size, the edit box at its own. Outside the ZacUI look
-- with nothing picked: nil, the game's own font as before.
local MATCH_SPEC = {}
function Chat.FontSpec(which, d)
    d = d or DB()
    local key = (which == "tab" and "tabFont") or (which == "edit" and "editFont") or "messageFont"
    local own = d[key]
    if not Empty(own) then return own end
    if not Match() then return nil end
    local s = MATCH_SPEC[which]
    if not s then
        s = {}
        MATCH_SPEC[which] = s
    end
    s.outline = HouseOutline()
    s.size = (which == "tab") and REF.tabSize or nil
    return s
end

-- Wrapped lines start under the first line's words, not at the edge
-- (the reference's indented wrap) - under the ZacUI look unless switched
-- off (chat.indent = false); what the window had is put back otherwise.
function Chat.ApplyIndent(cf, d)
    if not (cf and cf.SetIndentedWordWrap) then return end
    d = d or DB()
    local want = Match() and d.indent ~= false
    if cf._zStockIndent == nil and cf.GetIndentedWordWrap then
        local ok, v = pcall(cf.GetIndentedWordWrap, cf)
        cf._zStockIndent = (ok and v) and true or false
    end
    local now = want and true or (cf._zStockIndent or false)
    if cf._zIndent ~= now then
        cf._zIndent = now
        pcall(cf.SetIndentedWordWrap, cf, now)
    end
end

-- THE RESIZE GRIP: the window's own resize button (the game's, so sizing
-- and its saving stay the game's) wearing ZacUI's corner glyph, white at
-- 40%, 90% under the mouse, 18 across (the reference's). Only its art and
-- size change; where the game puts it and when it shows stay the game's.
-- Lock size (Chat_Panel) hides the button itself, so the two never meet.
local GRIP_ART = (ns.MEDIA or "Interface\\AddOns\\ZacUI\\Media\\") .. "Icons\\resize"
function Chat.StyleGrip(cf)
    if not cf or not Match() then return end
    local name = cf.GetName and cf:GetName()
    local grip = cf.resizeButton or (name and _G[name .. "ResizeButton"])
    if not grip or grip._zGrip or not grip.SetNormalTexture then return end
    grip._zGrip = true
    local function Art(setter, getter, a)
        if not grip[setter] then return end
        pcall(grip[setter], grip, GRIP_ART)
        local t = grip[getter] and grip[getter](grip)
        if t then
            t._zui_own = true
            if t.SetTexCoord then t:SetTexCoord(0, 1, 0, 1) end
            if t.SetVertexColor then t:SetVertexColor(1, 1, 1, a) end
            if t.SetBlendMode then t:SetBlendMode("BLEND") end
        end
    end
    Art("SetNormalTexture", "GetNormalTexture", REF.gripA)
    Art("SetPushedTexture", "GetPushedTexture", REF.gripHoverA)
    Art("SetHighlightTexture", "GetHighlightTexture", REF.gripHoverA - REF.gripA)
    -- the size on the clients where the game leaves the button to the
    -- addon side (Era / TBC); the modern clients keep their own
    local modern = ns.ModernClient and ns.ModernClient()
    if not modern and grip.SetSize and not InCombatLockdown() then
        pcall(grip.SetSize, grip, REF.gripSize, REF.gripSize)
    end
end

-- The dark panel behind a chat window: the palette window colour at the
-- opacity setting, or the chosen colour; its edge the palette's or chosen.
-- (the match pass: nothing picked = the reference's dark blue-black and a
-- white 6% hairline, under the ZacUI look)
local function PanelRGB(d)
    if type(d.panelColor) == "table" then
        local r, g, b = ns.ColorOf(d.panelColor)
        return r, g, b
    end
    if Match() then return REF.bg[1], REF.bg[2], REF.bg[3] end
    return nil
end
local function EdgeRGBA(d)
    if type(d.panelBorderColor) == "table" then return ns.ColorOf(d.panelBorderColor) end
    if Match() then return REF.edge[1], REF.edge[2], REF.edge[3], REF.edge[4] end
    return nil
end
local function PaintPanel(bg, d)
    d = d or DB()
    -- (the chat part's look: Core_Look, part "chat")
    SkinBackdrop(bg, "windowBg", d.opacity, "chat")
    local r, g, b = PanelRGB(d)
    if r and bg._zui_cbg then
        bg._zui_cbg:SetVertexColor(r, g, b, d.opacity)
    end
    local er, eg, eb, ea = EdgeRGBA(d)
    if er and not (bg._zui_borderTex and bg._zui_borderTex._zEdge) then
        TintBorder(bg, er, eg, eb, ea)
    else
        TintBorder(bg)
    end
    -- texture, border size / colour mode, inner line (Chat_Panel)
    if Chat.PanelExtra then Chat.PanelExtra(bg, d) end
end

-- The bar's own look (fill and top line), on the real bar or a sample.
local function MakeBarLook(bar)
    ns.UI.Fill(bar, "ui", "headerBg")
    local top = bar:CreateTexture(nil, "ARTWORK", nil, 5)
    top._zui_own = true
    top:SetTexture(ns.FLAT)
    -- (one physical pixel under ZacUI's look: Core_Pixel, HD polish)
    if ns.Pixel then ns.Pixel.Edge(top, "TOP", bar) else top:SetHeight(1) end
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    bar._zTop = top
    bar._zPaint = function(self)
        local d = DB()
        local match = Match()
        -- (the match pass: the bar is the panel itself - no fill of its own -
        -- under the reference's 6% divider)
        if match and type(d.barColor) ~= "table" then
            self._zFill:SetVertexColor(0, 0, 0, 0)
        else
            local r, g, b, a = ColorOr(d.barColor, "ui", "headerBg")
            self._zFill:SetVertexColor(r, g, b, a)
        end
        if match and type(d.barLineColor) ~= "table" then
            self._zTop:SetVertexColor(REF.edge[1], REF.edge[2], REF.edge[3], REF.edge[4])
        else
            self._zTop:SetVertexColor(ColorOr(d.barLineColor, "ui", "border"))
        end
    end
    bar:_zPaint()
end

-- The tab strip's look (fill, edge, accent rule).
local function MakeHeadLook(head)
    ns.UI.Fill(head, "ui", "headerBg")
    ns.UI.Border(head, "ui", "border")
    -- the house hairline under a header: accent, at 60%
    local rule = head:CreateTexture(nil, "ARTWORK", nil, 5)
    rule._zui_own = true
    rule:SetTexture(ns.FLAT)
    if ns.Pixel then ns.Pixel.Edge(rule, "BOTTOM", head) else rule:SetHeight(1) end
    rule:SetPoint("BOTTOMLEFT", 1, 1)
    rule:SetPoint("BOTTOMRIGHT", -1, 1)
    head._zRule = rule
    head._zPaint = function(self)
        ns.UI.PaintBox(self)
        local d = DB()
        local match = Match()
        if type(d.stripColor) == "table" then
            self._zFill:SetVertexColor(ns.ColorOf(d.stripColor))
        elseif match then
            -- (the match pass: the panel carried on behind the tabs)
            local r, g, b = PanelRGB(d)
            self._zFill:SetVertexColor(r, g, b, tonumber(d.opacity) or REF.bgA)
        end
        if match and self._zBorder then
            local er, eg, eb, ea = EdgeRGBA(d)
            for _, t in ipairs(self._zBorder) do t:SetVertexColor(er, eg, eb, ea) end
        end
        if type(d.stripLineColor) == "table" then
            self._zRule:SetVertexColor(ns.ColorOf(d.stripLineColor))
        elseif match then
            self._zRule:SetVertexColor(REF.edge[1], REF.edge[2], REF.edge[3], REF.edge[4])
        else
            local a = GetColor("ui", "accent")
            self._zRule:SetVertexColor(a.r, a.g, a.b, 0.6)
        end
    end
    head:_zPaint()
end

-- A tab's chip, anchored to its label: a fill, a line along the bottom,
-- the line's pulse (Blizzard's look) and a host for a chosen "something
-- new" animation.
local function MakeChip(tab, text)
    local fill = tab:CreateTexture(nil, "BACKGROUND")
    fill._zui_own = true
    fill:SetTexture(ns.FLAT)
    fill:SetPoint("TOPLEFT", text, "TOPLEFT", -TAB_PAD_X, TAB_PAD_Y)
    fill:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", TAB_PAD_X, -TAB_PAD_Y)
    fill:Hide()

    local line = tab:CreateTexture(nil, "ARTWORK")
    line._zui_own = true
    line:SetTexture(ns.FLAT)
    -- (whole physical pixels under the ZacUI look; PaintChipState sizes it)
    if ns.Pixel then ns.Pixel.Edge(line, "BOTTOM", tab, 1) else line:SetHeight(1) end
    line:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
    line:Hide()

    local pulse = line:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local a = pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.2)
    a:SetDuration(0.6)
    a:SetSmoothing("IN_OUT")

    local host = CreateFrame("Frame", nil, tab)
    host:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT", 0, 0)
    host:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
    host:SetHeight(2)
    local news = host:CreateTexture(nil, "ARTWORK")
    news._zui_own = true
    news:SetTexture(ns.FLAT)
    news:SetAllPoints()
    host:Hide()

    -- the hairline between two tabs on the strip (the match pass)
    local sep = tab:CreateTexture(nil, "ARTWORK")
    sep._zui_own = true
    sep:SetTexture(ns.FLAT)
    sep:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
    sep:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
    if ns.Pixel then ns.Pixel.Edge(sep, "LEFT", tab) else sep:SetWidth(1) end
    sep:Hide()

    return { fill = fill, line = line, pulse = pulse, host = host, news = news, text = text, tab = tab, sep = sep }
end

-- WHERE A CHIP SITS. Padding picked on the Chat page (Chat_Panel's
-- ChipPads): round the label by that much, as before. Otherwise, under the
-- ZacUI look (the match pass), a docked tab on the strip is a tile the
-- strip's height (chip.band, measured with the strip) and its tab's width,
-- as the reference's tabs are; anywhere else (a window on its own, the
-- Chat page's sample) the reference's 12 either side of the name and 24
-- high round its middle. Outside the ZacUI look: the old 7 / 4 round the
-- name. Placed again only when the answer changes.
local function PlaceChip(chip, d)
    local fill, text = chip.fill, chip.text
    if not (fill and text) then return end
    local px, py
    if Chat.ChipPads then px, py = Chat.ChipPads(d) end
    local band = chip.band
    local key, mode
    if px or py then
        px, py = px or (Tiles() and REF.tabPadX or TAB_PAD_X), py or (Tiles() and REF.tabPadY or TAB_PAD_Y)
        mode = "pad"
    elseif Tiles() and band and chip.tab then
        mode = "band"
    elseif Tiles() then
        mode = "ref"
    else
        mode = "old"
    end
    if mode == "band" then
        key = "band" .. band.up .. ":" .. band.down
    else
        key = mode .. tostring(px) .. ":" .. tostring(py)
    end
    if chip._zPlaced == key then return end
    chip._zPlaced = key
    fill:ClearAllPoints()
    if mode == "pad" then
        fill:SetPoint("TOPLEFT", text, "TOPLEFT", -px, py)
        fill:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", px, -py)
    elseif mode == "band" then
        fill:SetPoint("TOP", text, "TOP", 0, band.up)
        fill:SetPoint("BOTTOM", text, "BOTTOM", 0, -band.down)
        fill:SetPoint("LEFT", chip.tab, "LEFT", 0, 0)
        fill:SetPoint("RIGHT", chip.tab, "RIGHT", 0, 0)
    elseif mode == "ref" then
        fill:SetPoint("LEFT", text, "LEFT", -REF.tabPadX, 0)
        fill:SetPoint("RIGHT", text, "RIGHT", REF.tabPadX, 0)
        fill:SetHeight(REF.tabH)
    else
        fill:SetPoint("TOPLEFT", text, "TOPLEFT", -TAB_PAD_X, TAB_PAD_Y)
        fill:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", TAB_PAD_X, -TAB_PAD_Y)
    end
end

-- One chip in one state: selected (raised fill, line), hover (faint
-- fill), news (line, pulsing - or the chosen animation).
local function PaintChipState(chip, selected, hover, news, d)
    d = d or DB()
    -- the label's colours (Chat_Panel), then where the chip sits
    if Chat.ChipExtra then Chat.ChipExtra(chip, selected, hover, news, d) end
    PlaceChip(chip, d)
    if Match() and type(d.tabFillColor) ~= "table" then
        -- (the match pass: every tab a tile of the panel's colour, 44%,
        -- the one under the mouse 55%, the one you are on 65%)
        local r, g, b = PanelRGB(d)
        chip.fill:SetVertexColor(r, g, b, selected and REF.tabActiveA or hover and REF.tabHoverA or REF.tabIdleA)
        chip.fill:Show()
    elseif selected or hover then
        local r, g, b = ColorOr(d.tabFillColor, "button", "hover")
        chip.fill:SetVertexColor(r, g, b, selected and 1 or 0.55)
        chip.fill:Show()
    else
        chip.fill:Hide()
    end
    if chip.sep then
        if chip.band and Tiles() and chip._zPlaced and chip._zPlaced:sub(1, 4) == "band" then
            local er, eg, eb, ea = EdgeRGBA(d)
            chip.sep:SetVertexColor(er, eg, eb, ea)
            chip.sep:Show()
        else
            chip.sep:Hide()
        end
    end
    local lh = math.max(1, math.min(6, tonumber(d.tabLine) or 2))
    -- (whole physical pixels under the ZacUI look: Core_Pixel)
    if not (ns.Pixel and ns.Pixel.SetEdgeSize(chip.line, lh)) then chip.line:SetHeight(lh) end
    chip.host:SetHeight(lh)
    local spec = d.newsAnim
    local custom = type(spec) == "table" and spec.style and spec.style ~= "none" and ns.Motion
    if selected or news then
        local r, g, b = ColorOr(d.tabLineColor, "ui", "accent")
        -- (a vertex colour's alpha IS the texture's alpha, hence the 1)
        chip.line:SetVertexColor(r, g, b, 1)
        chip.news:SetVertexColor(r, g, b, 1)
        if news and custom then
            chip.pulse:Stop()
            chip.line:Hide()
            chip.host:Show()
            if not ns.Motion.IsPlaying(chip.host) then
                local s = ns.CopySetting and ns.CopySetting(spec) or spec
                if ns.Motion.LOOPS and ns.Motion.LOOPS[s.style] and s.loop == nil then s.loop = true end
                ns.Motion.Play(chip.host, s, "update")
            end
            return
        end
        chip.line:Show()
        if news then
            if not chip.pulse:IsPlaying() then chip.pulse:Play() end
        else
            chip.pulse:Stop()
            chip.line:SetAlpha(1)
        end
    else
        chip.pulse:Stop()
        chip.line:Hide()
    end
    if chip.host:IsShown() then
        if ns.Motion then ns.Motion.Stop(chip.host) end
        chip.host:Hide()
    end
end

-- ============================================================
-- PANEL AND EDIT BOX PLACEMENT
-- ============================================================
local function BarFor(cf)
    return dock.bar ~= nil and DB().bar and InDock(cf)
end

-- WHERE THE TAB LABELS AND THE EDIT BOX SIT (ZacUI's anchor shape, chat.
-- anchors.<tabText|editBox>). A tab label's default is wherever the game
-- put it (read once, the first time a spec moves it, and put back exactly
-- when the spec goes); the edit box's is its "Where you type" spot, the
-- spec on top of it. Nothing saved = never touched.
local function ChatAnchor(d, key)
    local a = d and d.anchors
    return type(a) == "table" and a[key] or nil
end
local function PlaceTabText(text, tab, d)
    if not text then return end
    local spec = ChatAnchor(d, "tabText")
    if not spec then
        local o = text._zOrigPts
        if o and text._zMoved then
            text:ClearAllPoints()
            for _, p in ipairs(o) do text:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
            if o.justify then text:SetJustifyH(o.justify) end
            text._zMoved = nil
        end
        return
    end
    if not text._zOrigPts then
        local o = {}
        for i = 1, (text.GetNumPoints and text:GetNumPoints() or 0) do
            local p, rel, rp, x, y = text:GetPoint(i)
            if p then o[#o + 1] = { p, rel or tab, rp or p, x or 0, y or 0 } end
        end
        if #o == 0 then o[1] = { "CENTER", tab, "CENTER", 0, 0 } end
        o.justify = text.GetJustifyH and text:GetJustifyH() or nil
        text._zOrigPts = o
    end
    local o = text._zOrigPts
    local D = text._zTabDef or {}
    text._zTabDef = D
    D.point, D.to, D.relPoint, D.x, D.y = o[1][1], o[1][2], o[1][3], o[1][4], o[1][5]
    D.justify = o.justify
    if o[2] then D.point2, D.to2, D.relPoint2, D.x2, D.y2 = o[2][1], o[2][2], o[2][3], o[2][4], o[2][5]
    else D.point2, D.to2, D.relPoint2, D.x2, D.y2 = nil, nil, nil, nil, nil end
    if not tab._zAnchorTo then tab._zAnchorTo = function(k) if k == "tab" then return tab end end end
    ns.ApplyAnchor(text, spec, D, tab._zAnchorTo)
    text._zMoved = true
end

-- the edit box at its "Where you type" spot, or the saved anchor on top
local function PlaceEditBoxAt(eb, where, bar, over, bg, d)
    local spec = ChatAnchor(d, "editBox")
    eb:ClearAllPoints()
    if not spec then
        if where == "bar" then
            eb:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            eb:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
        elseif where == "above" then
            eb:SetPoint("BOTTOMLEFT", over, "TOPLEFT", 0, 2)
            eb:SetPoint("BOTTOMRIGHT", over, "TOPRIGHT", 0, 2)
            eb:SetHeight(EditH())
        else
            -- clear of the panel, where it used to sit six pixels into it
            eb:SetPoint("TOPLEFT", bg, "BOTTOMLEFT", 0, -2)
            eb:SetPoint("TOPRIGHT", bg, "BOTTOMRIGHT", 0, -2)
            eb:SetHeight(EditH())
        end
        return
    end
    local D = eb._zEbDef or {}
    eb._zEbDef = D
    if where == "bar" then
        D.point, D.to, D.relPoint, D.x, D.y = "TOPLEFT", bar, "TOPLEFT", 0, 0
        D.point2, D.relPoint2, D.x2, D.y2 = "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0
    elseif where == "above" then
        D.point, D.to, D.relPoint, D.x, D.y = "BOTTOMLEFT", over, "TOPLEFT", 0, 2
        D.point2, D.relPoint2, D.x2, D.y2 = "BOTTOMRIGHT", "TOPRIGHT", 0, 2
    else
        D.point, D.to, D.relPoint, D.x, D.y = "TOPLEFT", bg, "BOTTOMLEFT", 0, -2
        D.point2, D.relPoint2, D.x2, D.y2 = "TOPRIGHT", "BOTTOMRIGHT", 0, -2
    end
    eb._zEbTargets = eb._zEbTargets or {}
    local T = eb._zEbTargets
    T.panel, T.bar, T.tabs = bg, bar, over ~= bg and over or nil
    if not eb._zEbResolve then eb._zEbResolve = function(k) return eb._zEbTargets[k] end end
    local _, two = ns.ApplyAnchor(eb, spec, D, eb._zEbResolve)
    if not two then
        -- one point once moved: as wide as the panel
        eb:SetWidth(math.max(80, (bg.GetWidth and bg:GetWidth() or 300)))
    end
    if not two or where ~= "bar" then eb:SetHeight(EditH()) end
end

local function TabOf(cf)
    return cf and cf.GetName and cf:GetName() and _G[cf:GetName() .. "Tab"]
end

local function TabText(tab)
    if not tab then return nil end
    return tab.Text or (tab.GetFontString and tab:GetFontString())
        or (tab.GetName and tab:GetName() and _G[tab:GetName() .. "Text"])
end

-- HOW TALL THE STRIP BEHIND THE DOCKED TABS HAS TO BE, measured from where
-- the General tab's label actually is rather than from a number: the tab
-- row's height and offset differ between client builds, and a strip
-- drawn from the wrong guess sits beside the tabs instead of under them.
-- Anything implausible measures as 0 - no strip is better than a stray one.
local function MeasureHead()
    local d = DB()
    if not (dock.head and d.tabs and d.tabStrip) then return 0 end
    local cf = DEFAULT_CHAT_FRAME
    local tab = TabOf(cf)
    local text = TabText(tab)
    if not (cf and tab and text and text.GetTop and cf.GetTop) then return 0 end
    local top, base = text:GetTop(), cf:GetTop()
    -- not laid out yet: keep whatever was measured last
    if not (top and base) then return dock.headH or 0 end
    local bottom = text.GetBottom and text:GetBottom() or nil
    local ts = (tab.GetEffectiveScale and tab:GetEffectiveScale()) or 1
    local cs = (cf.GetEffectiveScale and cf:GetEffectiveScale()) or 1
    if cs and cs > 0 and ts then
        top = top * ts / cs
        if bottom then bottom = bottom * ts / cs end
    end
    local floor = base + PAD - 1
    -- THE MATCH PASS: a strip the label sits in the middle of (the
    -- reference's tabs centre their names), its tabs tiles the strip's
    -- height; chip.band says how far the tiles reach past the label
    if Tiles() and bottom and bottom < top and not (Chat.ChipPads and Chat.ChipPads(d)) then
        local mid = (top + bottom) / 2
        local h = math.floor(2 * (mid - floor) + 0.5)
        local up = math.floor((floor + h - top) * 100 + 0.5) / 100
        local down = math.floor((bottom - floor) * 100 + 0.5) / 100
        -- (an odd client layout - the name too low or too high for a
        -- centred strip - keeps the old strip below)
        if h >= 16 and h <= 48 and up >= 0 and down >= 0 then
            local b = dock.band
            if not b or b.up ~= up or b.down ~= down then dock.band = { up = up, down = down } end
            return h
        end
    end
    dock.band = nil
    -- from the strip's bottom edge (PAD - 1 above the text area) to two
    -- pixels over the top of a chip
    local h = math.floor(top + TAB_PAD_Y + 2 - floor + 0.5)
    if h < 8 or h > 48 then return 0 end
    return h
end

local function PlacePanel(cf)
    local bg = cf._zui_chatbg
    if not bg then return end
    local docked = InDock(cf)
    -- Docked windows share the General window's top edge. The combat
    -- log's own frame starts lower, under its row of filter buttons, and
    -- its panel should still reach the tabs.
    local topRef = (docked and DEFAULT_CHAT_FRAME) or cf
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", topRef, "TOPLEFT", -PAD, PAD)
    -- with the bar, the panel reaches down around it (and its 1px edge)
    bg:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", PAD, BarFor(cf) and -(GAP + BarH() + 1) or -FOOT)
    PaintPanel(bg)
end

-- Is an edit box that lives in the bar being typed in?
local function Typing()
    local typing = false
    EachChatFrame(function(cf)
        local eb = EditBoxOf(cf)
        if eb and eb._zWhere == "bar" and eb:IsShown() and eb:HasFocus() then typing = true end
    end)
    return typing
end

-- "IM style" chat leaves the edit box on screen, dimmed, when you are not
-- typing. In the bar that would be a grey box over the numbers for ever,
-- so there it rests invisible and lets the mouse through (a click on the
-- bar opens it), and comes back the moment it has the cursor.
local function SyncEditBox(eb)
    if not eb then return end
    if eb._zWhere == "bar" then
        if eb:IsShown() and not eb:HasFocus() then
            eb._zRest = true
            eb:SetAlpha(0)
            eb:EnableMouse(false)
        elseif eb._zRest then
            eb._zRest = nil
            eb:EnableMouse(true)
            eb:SetAlpha(1)
        end
    elseif eb._zRest then
        eb._zRest = nil
        eb:EnableMouse(true)
        eb:SetAlpha(eb:HasFocus() and 1 or 0.35)
    end
    if dock.content then dock.content:SetShown(not Typing()) end
end

-- The box's edge takes the colour of the channel you are about to talk
-- in - the same colour its "Party:" label already has - so a mistell is
-- visible before you press Enter.
local function TintEditBox(eb)
    if not eb or not eb._zui_borderTex or PratOwns() then return end
    if not DB().tint then TintBorder(eb) return end
    local kind = ChatTypeOf(eb)
    local info
    if kind == "CHANNEL" then
        local target = ChannelOf(eb)
        local id = target and GetChannelName and GetChannelName(target)
        info = id and ChatTypeInfo and ChatTypeInfo["CHANNEL" .. id]
    end
    info = info or (kind and ChatTypeInfo and ChatTypeInfo[kind])
    if info and info.r then
        TintBorder(eb, info.r, info.g, info.b, 1)
    else
        TintBorder(eb)
    end
end

local PlaceEditBox   -- forward: a box found somewhere else is put back

local function HookEditBox(eb)
    if eb._zChatHooked then return end
    eb._zChatHooked = true
    -- If anything has re-anchored the box since it was placed, put it
    -- back as it opens rather than let it open over the panel again.
    eb:HookScript("OnShow", function(self)
        if not self._zAnchor or not self._zChat or not self.GetPoint then return end
        local _, rel = self:GetPoint(1)
        if rel ~= self._zAnchor then PlaceEditBox(self._zChat) end
    end)
    -- Now, and once more next frame: Blizzard sets the box's alpha and
    -- focus in whichever order suits it, and the second look settles it.
    local function Sync(self)
        SyncEditBox(self)
        if not self._zSyncQueued then
            self._zSyncQueued = true
            C_Timer.After(0, function()
                self._zSyncQueued = nil
                SyncEditBox(self)
            end)
        end
    end
    eb:HookScript("OnShow", Sync)
    eb:HookScript("OnHide", Sync)
    eb:HookScript("OnEditFocusGained", Sync)
    eb:HookScript("OnEditFocusLost", Sync)
    if type(eb.UpdateHeader) == "function" then
        pcall(hooksecurefunc, eb, "UpdateHeader", TintEditBox)
    end
end

PlaceEditBox = function(cf)
    local eb = EditBoxOf(cf)
    local bg = cf._zui_chatbg
    if not eb or not bg or PratOwns() then return end
    HookEditBox(eb)
    local d = DB()
    local where = d.editBox
    if where == "bar" and not BarFor(cf) then where = "below" end
    eb._zWhere, eb._zChat = where, cf
    -- "above" clears the tab strip when the strip is always up; when the
    -- tabs only show on mouseover it sits on the panel, over where they are
    local over = bg
    if where == "above" and InDock(cf) and dock.head and (dock.headH or 0) > 0
        and d.tabs and d.tabsVisible == "always" then
        over = dock.head
    end
    eb._zAnchor = (where == "bar") and dock.bar or (where == "above") and over or bg
    PlaceEditBoxAt(eb, where, dock.bar, over, bg, d)
    if ChatAnchor(d, "editBox") then
        -- what it hangs off now (the OnShow check above compares with it)
        local _, rel = eb:GetPoint(1)
        eb._zAnchor = rel or eb._zAnchor
    end
    -- the edit box's font (and its "Say:" header's), Blizzard's until chosen
    -- (ZacUI's face, outlined, under the ZacUI look: the match pass)
    local espec = Chat.FontSpec("edit", d)
    StyleBlizzText(eb, espec)
    local header = eb.header or (eb.GetName and eb:GetName() and _G[eb:GetName() .. "Header"])
    if header then StyleBlizzText(header, espec) end
    -- up and down recall what you typed without holding Alt
    if eb.SetAltArrowKeyMode then eb:SetAltArrowKeyMode(not d.arrows) end
    SyncEditBox(eb)
    TintEditBox(eb)
end

-- The bar and the tab strip belong to the dock: up while any docked
-- window is.
local function DockUp()
    local up = false
    EachChatFrame(function(cf)
        if InDock(cf) and cf:IsShown() then up = true end
    end)
    return up
end
local function SyncBar()
    -- (the icon rail, Chat_Panel, rides with the dock too)
    if Chat.RailSync then pcall(Chat.RailSync) end
    if not (dock.bar or dock.head) then return end
    local up = DockUp()
    if dock.bar then dock.bar:SetShown(up and DB().bar and true or false) end
    if dock.head then dock.head:SetShown(up and (dock.headH or 0) > 0) end
end

-- ============================================================
-- TABS
-- ============================================================
-- Blizzard's tab art is stripped (SkinChatFrame), which left bare words
-- floating over the chat. Each tab gets a CHIP anchored to its LABEL, not
-- to the tab's own rectangle - the hit area is much taller than the text
-- and docking moves and resizes it at will - made of a fill and a 2px
-- line along the bottom:
--   the tab you are on    raised fill, gold line
--   a tab with news       gold line, pulsing
--   under the mouse       a faint fill
--   the rest              nothing: just the word
local function IsSelectedTab(cf)
    if not InDock(cf) then return true end      -- a window on its own is always "on"
    return SelectedFrame() == cf
end

-- Hands a tab's alpha back to Blizzard. It is left at full rather than
-- at whatever the mouseover fade last wrote - which may be zero, and the
-- game only rewrites a tab's alpha when the mouse next crosses the chat.
local function ReleaseTab(tab)
    if tab._zWantAlpha == nil then return end
    tab._zWantAlpha = nil
    if tab.SetAlpha then tab:SetAlpha(1) end
end

local function PaintTab(cf)
    local tab = cf and cf._zTab
    local chip = tab and tab._zChip
    if not chip then return end
    local d = DB()
    if not d.tabs then
        chip.pulse:Stop()
        chip.fill:Hide()
        chip.line:Hide()
        if chip.host:IsShown() then
            if ns.Motion then ns.Motion.Stop(chip.host) end
            chip.host:Hide()
        end
        ReleaseTab(tab)
        return
    end

    local selected = IsSelectedTab(cf)
    local news = (tab.alerting and not selected) and true or false
    -- on the strip (the match pass): a docked tab while the strip is up
    chip.band = (InDock(cf) and (dock.headH or 0) > 0) and dock.band or nil
    -- a whisper window's tab keeps the game's whisper colour on its name
    chip.isTemp = cf.isTemporary and true or nil
    PaintChipState(chip, selected, tab._zHover, news, d)

    -- how visible it is: held at full, left to Blizzard, or - the
    -- default - driven by the mouse (TABS ON MOUSEOVER, below)
    if d.tabsVisible == "always" then
        -- (scaled by the whole chat's idle fade / visibility rule: Chat_Fade)
        local full = Chat.fadeScale or 1
        tab._zWantAlpha = full
        if tab.GetAlpha and tab:GetAlpha() ~= full then tab:SetAlpha(full) end
    elseif d.tabsVisible == "blizzard" then
        ReleaseTab(tab)
    end
end

local function PaintTabs() EachChatFrame(PaintTab) end

local tabsQueued
local function PaintTabsSoon()
    if tabsQueued then return end
    tabsQueued = true
    C_Timer.After(0, function()
        tabsQueued = nil
        PaintTabs()
    end)
end

local function SkinTab(cf)
    local tab = TabOf(cf)
    if not tab then return end
    cf._zTab = tab
    if not tab._zChip then
        local text = TabText(tab)
        if not text then return end
        tab._zChip = MakeChip(tab, text)

        tab:HookScript("OnEnter", function(self) self._zHover = true; PaintTab(cf) end)
        tab:HookScript("OnLeave", function(self) self._zHover = nil; PaintTab(cf) end)
        -- a click is how the selection changes; Blizzard's handler runs
        -- first, so look once it has
        tab:HookScript("OnClick", PaintTabsSoon)
        -- held at full alpha while the option asks for it, however often
        -- Blizzard's fade writes to it
        pcall(hooksecurefunc, tab, "SetAlpha", function(self, alpha)
            if self._zAlphaBusy then return end
            local want = self._zWantAlpha
            if want and alpha ~= want then
                self._zAlphaBusy = true
                self:SetAlpha(want)
                self._zAlphaBusy = nil
            end
        end)
    end
    -- the label's font, Blizzard's until one is chosen (ZacUI's at 11
    -- under the ZacUI look: the match pass)
    StyleBlizzText(TabText(tab), Chat.FontSpec("tab", DB()))
    PlaceTabText(TabText(tab), tab, DB())
    PaintTab(cf)
end

-- The strip the docked tabs sit on: the bar's twin at the other end of
-- the panel. Hung from the General window; sized by MeasureHead.
local function BuildHead()
    if dock.head or not DEFAULT_CHAT_FRAME then return end
    local UI = ns.UI
    local head = CreateFrame("Frame", "ZacUIChatHead", UIParent)
    ZUI.skinned[head] = true
    dock.head = head
    -- with the panels and just above them, as low as it can sit: the
    -- tabs have to draw over it (/zui chatinfo prints their strata)
    head:SetFrameStrata("BACKGROUND")
    head:SetFrameLevel(2)
    head:Hide()
    -- A box of its own, standing on the panel's top edge rather than
    -- built into the panel: it comes and goes with the mouse, and the
    -- panel should not change height when it does.
    MakeHeadLook(head)
end

local function PlaceHead()
    local head = dock.head
    local cf = DEFAULT_CHAT_FRAME
    if not head or not cf then return end
    local h = dock.headH or 0
    if h <= 0 then return end
    head:ClearAllPoints()
    -- as wide as the panel, its bottom edge on the panel's top edge
    head:SetPoint("BOTTOMLEFT", cf, "TOPLEFT", -PAD, PAD - 1)
    head:SetPoint("BOTTOMRIGHT", cf, "TOPRIGHT", PAD, PAD - 1)
    head:SetHeight(h + 1)
end

-- ============================================================
-- TABS ON MOUSEOVER
-- ============================================================
-- In "hover" mode the tabs and the strip are invisible until the mouse is
-- over the chat - the text, the tab row above it or the bar below - then
-- fade in, and fade out a moment after it leaves. An invisible tab still
-- takes the mouse, so reaching for where a tab is brings them up.
--
-- The docked tabs and the strip move together; a window dragged out of
-- the dock answers to the mouse over itself. A tab with something new is
-- shown whatever the mouse is doing: a whisper in another tab should not
-- depend on where the cursor happens to be.
--
-- Driven by one small frame's OnUpdate: ten looks a second at rest, every
-- frame only while something is fading.
local hover = { dock = { alpha = 0, away = 99 }, own = {} }
-- defaults; Refresh copies the settings (tabFadeIn / Out / Linger) here
local FADE_IN, FADE_OUT, LINGER = 0.12, 0.30, 0.6

local function SetTabAlpha(tab, alpha)
    alpha = alpha * (Chat.fadeScale or 1)
    tab._zWantAlpha = alpha
    if tab.GetAlpha and tab:GetAlpha() ~= alpha then tab:SetAlpha(alpha) end
end

-- Is the mouse over this chat window, its tab row or (docked) the bar?
local function MouseOverChat(cf, docked)
    if not (cf and cf.IsMouseOver and cf:IsVisible()) then return false end
    -- generous upwards: the tab row, and the combat log's frame starts a
    -- row of buttons lower than the tabs it belongs under
    local up = PAD + math.max(dock.headH or 0, 28) + 30
    local down = (docked and BarFor(cf)) and (GAP + BarH() + 2) or (FOOT + 2)
    return cf:IsMouseOver(up, -down, -PAD, PAD) and true or false
end

-- Moves one group's alpha towards shown or hidden. True while it is
-- still moving, or waiting out its linger.
local function HoverStep(g, hot, dt)
    local before = g.alpha
    -- Appearance > Motion: off makes the fades instant, speed scales them
    local m = ns.Motion
    local on = not m or m.Enabled()
    local sp = (m and m.Speed()) or 1
    local fin, fout = on and FADE_IN / sp or 0, on and FADE_OUT / sp or 0
    if hot then
        g.away = 0
        g.alpha = (fin <= 0) and 1 or math.min(1, g.alpha + dt / fin)
    else
        g.away = g.away + dt
        if g.away >= LINGER then
            g.alpha = (fout <= 0) and 0 or math.max(0, g.alpha - dt / fout)
        end
    end
    return g.alpha ~= before or (not hot and g.alpha > 0)
end

local function HoverApply()
    local shared = hover.dock.alpha
    -- raid mode: the raid frames have the chat box, tabs and all
    if Chat.raidHidden then shared = 0 end
    if dock.head then dock.head:SetAlpha(shared * (Chat.fadeScale or 1)) end
    for _, name in ipairs(CHAT_FRAMES or {}) do
        local cf = _G[name]
        local tab = cf and cf._zTab
        if tab and tab._zChip then
            local a
            if InDock(cf) then
                a = shared
            else
                local g = hover.own[cf]
                a = g and g.alpha or 0
            end
            SetTabAlpha(tab, (tab.alerting and not (Chat.raidHidden and InDock(cf))) and 1 or a)
        end
    end
end

local function HoverUpdate(dt)
    local busy = HoverStep(hover.dock, MouseOverChat(SelectedFrame(), true), dt)
    for _, name in ipairs(CHAT_FRAMES or {}) do
        local cf = _G[name]
        if cf and cf._zTab and not InDock(cf) and cf:IsShown() then
            local g = hover.own[cf]
            if not g then
                g = { alpha = 0, away = 99 }
                hover.own[cf] = g
            end
            if HoverStep(g, MouseOverChat(cf, false), dt) then busy = true end
        end
    end
    HoverApply()
    return busy
end

local function BuildHoverDriver()
    if dock.hoverDriver then return end
    local driver = CreateFrame("Frame", nil, UIParent)
    driver:Hide()
    driver:SetScript("OnShow", function(self) self.t, self.busy = 0, true end)
    driver:SetScript("OnUpdate", function(self, dt)
        self.t = (self.t or 0) + dt
        if not self.busy and self.t < 0.1 then return end
        local step = math.min(self.t, 0.1)
        self.t = 0
        self.busy = HoverUpdate(step)
    end)
    dock.hoverDriver = driver
end

-- Puts the chosen visibility into effect (Chat.Refresh, after the tabs
-- are skinned).
local function ApplyTabVisibility()
    local d = DB()
    local mode = d.tabs and d.tabsVisible or "blizzard"
    if dock.hoverDriver then dock.hoverDriver:SetShown(mode == "hover") end
    if mode == "hover" then
        HoverApply()
    elseif dock.head then
        dock.head:SetAlpha(Chat.fadeScale or 1)
    end
end
-- the tabs and their strip again, after Chat.fadeScale changed (Chat_Fade)
function Chat.RepaintTabs()
    if not dock.built then return end
    PaintTabs()
    ApplyTabVisibility()
end

-- ============================================================
-- THE BAR
-- ============================================================
local function PaintPlate(b, hover)
    local c = GetColor("button", hover and "hover" or "bg")
    b._fill:SetVertexColor(c.r, c.g, c.b, hover and 1 or (b._restAlpha or 0))
end

-- A flat button on the bar: no fill until the mouse is on it.
local function Plate(parent)
    local UI = ns.UI
    local b = CreateFrame("Button", nil, parent)
    ZUI.skinned[b] = true
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local fill = b:CreateTexture(nil, "BACKGROUND")
    fill._zui_own = true
    fill:SetAllPoints()
    fill:SetTexture(ns.FLAT)
    b._fill = fill
    b._label = UI.Font(b, UI.F.SMALL, { cat = "text", key = "normal" })
    b._label:SetPoint("CENTER", 0, 0)
    b._label:SetWordWrap(false)
    StyleBarText(b._label)
    b:SetScript("OnEnter", function(self)
        PaintPlate(self, true)
        if self._tip then
            local ok = pcall(self._tip, self)
            if ok then GameTooltip:Show() else GameTooltip:Hide() end
        end
    end)
    b:SetScript("OnLeave", function(self)
        PaintPlate(self, false)
        GameTooltip:Hide()
    end)
    PaintPlate(b, false)
    return b
end

local BarMenu   -- forward: plates open it on a right-click

-- The bar's numbers in the saved order (d.barOrder: item ids; nil = the
-- list as it is, not copied). `list` is ITEMS or the Chat page's samples
-- (each with ._it, its item); keyed by id.
local function ItemKey(it) return it.id or (it._it and it._it.id) end
function Chat.OrderedItems(list)
    local order = DB().barOrder
    if type(order) ~= "table" or not ns.OrderedList then return list end
    return ns.OrderedList(list, order, ItemKey)
end

local function LayoutBar()
    local bar, content = dock.bar, dock.content
    if not bar then return end
    local w = bar:GetWidth() or 0
    if w <= 0 then return end

    -- channel buttons from the left (and never past the right edge)
    local x = 3
    for _, chip in ipairs(dock.chips) do
        if chip._on and x + chip:GetWidth() <= w - 3 then
            chip:ClearAllPoints()
            chip:SetPoint("LEFT", content, "LEFT", x, 0)
            chip:Show()
            x = x + chip:GetWidth() + 2
        else
            chip:Hide()
        end
    end

    -- which numbers there is room for, the ones that matter most first
    local room = w - x - 10
    local used = 0
    for _, it in ipairs(BY_KEEP) do
        local b = dock.items[it.id]
        b._fits = false
        if b._now ~= "" and used + b._wide <= room then
            b._fits = true
            used = used + b._wide
        end
    end
    -- then set them down from the right, in list order (the saved order,
    -- d.barOrder - item ids, dragged in the Chat preview; nil = ITEMS)
    local rx = -2
    local leftmost
    local list = Chat.OrderedItems(ITEMS)
    for i = #list, 1, -1 do
        local b = dock.items[list[i].id]
        if b._fits then
            b:ClearAllPoints()
            b:SetPoint("RIGHT", content, "RIGHT", rx, 0)
            b:SetWidth(b._wide)
            b._rule:Show()
            b:Show()
            rx = rx - b._wide
            leftmost = b
        else
            b:Hide()
        end
    end
    -- no divider to the left of the first one
    if leftmost then leftmost._rule:Hide() end
end

-- The width a label would be with this text in it.
local function WidthOf(label, text)
    local was = label:GetText()
    label:SetText(text)
    local w = label:GetStringWidth() or 0
    label:SetText(was or "")
    return w
end

-- EVERY NUMBER HAS A FIXED SLOT. Its width comes from the item's sample
-- (the widest text it should ever show) and only grows. The slots used
-- to be exactly as wide as their text, so frame rate going from 59 to
-- 144 moved everything to its left, and near the edge of what fits an
-- item would drop off the bar and come back a second later.
--
-- Returns true only when the bar has to be laid out again: the item
-- appeared, disappeared, or outgrew its slot.
local function SetItemText(b, text)
    text = text or ""
    if text == b._now then return false end
    local was = b._now
    b._now = text
    b._label:SetText(text)
    local relayout = (was == "") ~= (text == "")
    if text ~= "" then
        local w = math.ceil((b._label:GetStringWidth() or 0) + 12)
        if w > b._wide then
            b._wide = w
            relayout = true
        end
    end
    return relayout
end

local function WhisperColor()
    local info = ChatTypeInfo and ChatTypeInfo.WHISPER
    if info and info.r then return info.r, info.g, info.b end
    return 1, 0.5, 1
end

local function PaintChip(chip)
    local spec = chip.spec
    local r, g, b
    if spec.accent then
        local a = GetColor("ui", "accent")
        r, g, b = a.r, a.g, a.b
    else
        local info = ChatTypeInfo and ChatTypeInfo[spec.id]
        if info and info.r then
            r, g, b = info.r, info.g, info.b
        else
            local c = GetColor("text", "normal")
            r, g, b = c.r, c.g, c.b
        end
    end
    chip._label:SetTextColor(r, g, b, 1)
    if chip._glow then
        -- SetVertexColor's alpha IS the texture's alpha, so the glow's
        -- rest state has to be put back after every repaint
        chip._glow:SetVertexColor(r, g, b, 1)
        chip._glow:SetAlpha((chip._lit and not chip._customLit) and 1 or 0)
    end
    if chip._alertGlow then chip._alertGlow:SetVertexColor(r, g, b, 0.3) end
end

-- `sample`: size it for this text rather than what it shows now (the
-- whisper button keeps room for its count, so the count arriving does not
-- push the buttons after it along). It only ever grows.
local function SizeChip(chip, sample)
    local text = (chip._label:GetStringWidth() or 0)
    if sample then text = math.max(text, WidthOf(chip._label, sample)) end
    local w = math.max(18, math.ceil(text + 10 + (chip._lead or 0)))
    if w > (chip._sized or 0) then
        chip._sized = w
        chip:SetWidth(w)
    end
end

-- The channel buttons. `show` says whether you can talk there right now.
-- IN ORDER OF HOW LONG THEY STAY. Say and Guild are there all session,
-- the whisper button from the first whisper on, and the group ones come
-- and go - so those are last, where arriving moves nothing else.
local CHIPS = {
    { id = "SAY", text = "S", slash = "SLASH_SAY1", fallback = "/s",
      show = function() return true end },
    { id = "GUILD", text = "G", slash = "SLASH_GUILD1", fallback = "/g",
      show = function() return IsInGuild and IsInGuild() end },
    { id = "WHISPER", whisper = true },
    { id = "PARTY", text = "P", slash = "SLASH_PARTY1", fallback = "/p",
      show = function() return IsInGroup and IsInGroup() end },
    { id = "RAID", text = "R", slash = "SLASH_RAID1", fallback = "/raid",
      show = function() return IsInRaid and IsInRaid() end },
    { id = "RAID_WARNING", text = "RW", slash = "SLASH_RAID_WARNING1", fallback = "/rw",
      show = function()
          return IsInRaid and IsInRaid() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))
      end },
}

local function ChipName(spec)
    return _G["CHAT_MSG_" .. spec.id] or spec.id
end

-- WHISPERS. A reply button that counts: every whisper since you last
-- answered one, with the last few on its tooltip.
-- The whisper button's glow: a texture with Blizzard-style pulse (the
-- default) and a frame of its own for a chosen animation. On the real
-- button and the Chat page's sample.
local function AddWhisperGlow(w)
    local glow = w:CreateTexture(nil, "BORDER")
    glow._zui_own = true
    glow:SetAllPoints()
    glow:SetTexture(ns.FLAT)
    -- lit only while its animation runs; at rest it is alpha 0, because
    -- an alpha animation that stops hands back the texture's own alpha
    glow:SetAlpha(0)
    w._glow = glow
    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local a = pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(0.10)
    a:SetToAlpha(0.38)
    a:SetDuration(0.9)
    a:SetSmoothing("IN_OUT")
    w._pulse = pulse
    -- a chosen "unread whisper" animation plays on a frame of its own
    -- carrying a copy of the glow (the glow's own pulse is Blizzard-style
    -- and stays the default)
    local host = CreateFrame("Frame", nil, w)
    host:SetAllPoints()
    -- under the button, so the wash never covers the label
    host:SetFrameLevel(math.max(0, (w:GetFrameLevel() or 1) - 1))
    local hostGlow = host:CreateTexture(nil, "BORDER")
    hostGlow._zui_own = true
    hostGlow:SetAllPoints()
    hostGlow:SetTexture(ns.FLAT)
    host:Hide()
    w._alertHost, w._alertGlow = host, hostGlow
end

local function BuildWhisperChip(spec)
    local w = Plate(dock.content)
    w.spec = spec
    w:SetHeight(BarH() - 6)
    w._label:SetText("W")
    AddWhisperGlow(w)
    w._tip = function(self)
        Tip(self, "Whispers")
        if #whispers.log == 0 then
            TipLine("Nobody has whispered you this session.")
        else
            local r, g, b = WhisperColor()
            for _, m in ipairs(whispers.log) do
                local ago = math.max(0, time() - m.at)
                local when = (ago < 60) and "just now"
                    or (ago < 3600) and (math.floor(ago / 60) .. " min ago")
                    or (math.floor(ago / 3600) .. " h ago")
                GameTooltip:AddDoubleLine(m.name, when, r, g, b, 0.6, 0.6, 0.6)
                GameTooltip:AddLine(m.text, 0.9, 0.9, 0.9, true)
            end
        end
        local last = LastTell()
        if last then
            TipHint("Click to reply to " .. last .. (whispers.unread > 0 and ". Right-click to clear the count." or "."))
        end
    end
    w:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if whispers.unread > 0 then
                whispers.unread = 0
                dock.slow = 99
            else
                BarMenu()
            end
            return
        end
        whispers.unread = 0
        dock.slow = 99
        ReplyTell()
    end)
    PaintChip(w)
    -- room for a count from the start
    SizeChip(w, "W 9")
    dock.whisper = w
    return w
end

local function BuildChips()
    dock.chips = {}

    for _, spec in ipairs(CHIPS) do
        if spec.whisper then
            dock.chips[#dock.chips + 1] = BuildWhisperChip(spec)
        else
            local chip = Plate(dock.content)
            chip.spec = spec
            chip:SetHeight(BarH() - 6)
            chip._label:SetText(spec.text)
            chip._tip = function(self)
                Tip(self, ChipName(spec))
                TipHint("Click to talk here")
            end
            chip:SetScript("OnClick", function(_, button)
                if button == "RightButton" then BarMenu() return end
                OpenChat((_G[spec.slash] or spec.fallback) .. " ")
            end)
            PaintChip(chip)
            SizeChip(chip)
            dock.chips[#dock.chips + 1] = chip
        end
    end

    -- JUMP TO LATEST. The scroll buttons are gone with the rest of the
    -- side column, so being scrolled up needs saying somewhere.
    local l = Plate(dock.content)
    l.spec = { id = "LATEST", accent = true }
    l:SetHeight(BarH() - 6)
    local arrow = l:CreateTexture(nil, "ARTWORK")
    arrow._zui_own = true
    arrow:SetSize(8, 8)
    arrow:SetPoint("LEFT", 5, 0)
    arrow:SetTexture(ns.TEX_ARROW)
    local ac = GetColor("ui", "accent")
    arrow:SetVertexColor(ac.r, ac.g, ac.b, 1)
    l._label:ClearAllPoints()
    l._label:SetPoint("LEFT", arrow, "RIGHT", 4, 0)
    l._label:SetText("Latest")
    l._lead = 12
    l._tip = function(self)
        Tip(self, "You are scrolled up")
        TipLine("New messages are arriving below what you can see.")
        TipHint("Click to jump to the latest")
    end
    l:SetScript("OnClick", function(_, button)
        if button == "RightButton" then BarMenu() return end
        local cf = SelectedFrame()
        if cf and cf.ScrollToBottom then cf:ScrollToBottom() end
        dock.fast = 99
    end)
    PaintChip(l)
    SizeChip(l)
    dock.latest = l
    dock.chips[#dock.chips + 1] = l
end

-- one number's plate (the items at load, and a block another file docks
-- later: Chat.AddBarItem)
local function BuildItem(it)
    local b = Plate(dock.content)
    b:SetHeight(BarH() - 2)
    b._now = ""
    -- the text hangs from the right of its slot, so the unit stays
    -- put and only the digits to its left change
    b._label:ClearAllPoints()
    b._label:SetPoint("RIGHT", b, "RIGHT", -6, 0)
    b._wide = math.ceil(WidthOf(b._label, it.sample or "") + 12)
    b._tip = it.tip
    -- the friends and guild tooltips are the minimap's, which open
    -- downwards unless told otherwise; down here that is off screen
    b._zTipAnchor = "ANCHOR_TOP"
    local rule = b:CreateTexture(nil, "ARTWORK")
    rule._zui_own = true
    rule:SetTexture(ns.FLAT)
    if ns.Pixel then ns.Pixel.Edge(rule, "LEFT", b) else rule:SetWidth(1) end
    rule:SetPoint("TOPLEFT", 0, -5)
    rule:SetPoint("BOTTOMLEFT", 0, 5)
    local c = GetColor("text", "gray")
    rule:SetVertexColor(c.r, c.g, c.b, 0.35)
    b._rule = rule
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then BarMenu() return end
        if it.click then pcall(it.click, self, button) end
    end)
    b:Hide()
    dock.items[it.id] = b
    return b
end

local function BuildItems()
    dock.items = {}
    for _, it in ipairs(ITEMS) do BuildItem(it) end
end

-- ANOTHER FILE'S BLOCK ON THE BAR (feature cluster 3: Chat_LDB docks
-- LibDataBroker objects). The same shape as the items above ({ id,
-- label, sample, keep, every, text, tip, click }); `front` puts it at the
-- left of the numbers, else at the right. Off until its switch in
-- d.items[id] is ticked, like every item. Returns the spec and its plate
-- (the plate once the bar is built).
local function RebuildKeep()
    wipe(BY_KEEP)
    for i, it in ipairs(ITEMS) do BY_KEEP[i] = it end
    table.sort(BY_KEEP, function(a, b) return (a.keep or 99) < (b.keep or 99) end)
end
function Chat.AddBarItem(spec, front)
    if type(spec) ~= "table" or not spec.id then return nil end
    for _, it in ipairs(ITEMS) do
        if it.id == spec.id then return it, dock.items and dock.items[it.id] end
    end
    if front then table.insert(ITEMS, 1, spec) else ITEMS[#ITEMS + 1] = spec end
    RebuildKeep()
    local b
    if dock.content and dock.items then
        b = BuildItem(spec)
        StyleBarText(b._label, DB())
        b._wide = math.ceil(WidthOf(b._label, spec.sample or "") + 12)
        dock.dirty = true
    end
    return spec, b
end

function Chat.RemoveBarItem(id)
    for i, it in ipairs(ITEMS) do
        if it.id == id then
            table.remove(ITEMS, i)
            RebuildKeep()
            local b = dock.items and dock.items[id]
            if b then
                b:Hide()
                dock.items[id] = nil
            end
            dock.dirty = true
            return true
        end
    end
    return false
end

function Chat.BarItem(id)
    return dock.items and dock.items[id]
end

-- The bar's clock. `step` is the time since it last ran.
local function Tick(step)
    if not dock.content:IsShown() then return end
    local d = DB()
    local dirty = dock.dirty
    dock.dirty = nil

    -- scrolled up? asked every time: it should appear as you scroll
    local cf = SelectedFrame()
    local up = (d.latest and cf ~= nil and cf.AtBottom ~= nil and not cf:AtBottom()) and true or false
    if up ~= dock.latest._on then
        dock.latest._on = up
        dirty = true
    end

    dock.slow = (dock.slow or 99) + step
    if dock.slow >= 1 then
        dock.slow = 0
        for _, chip in ipairs(dock.chips) do
            local spec = chip.spec
            if spec.show then
                local ok, can = pcall(spec.show)
                local on = d.channels and ok and can and true or false
                if on ~= chip._on then
                    chip._on = on
                    dirty = true
                end
                if on then PaintChip(chip) end
            end
        end
        local w = dock.whisper
        local on = d.whispers and (whispers.unread > 0 or LastTell() ~= nil) or false
        local label = (whispers.unread > 0) and ("W " .. whispers.unread) or "W"
        if on ~= w._on or label ~= w._caption then
            w._on, w._caption = on, label
            w._label:SetText(label)
            PaintChip(w)
            SizeChip(w, "W 9")
            dirty = true
        end
        -- the tabs' state, and where they are: both can change without any
        -- event this file hears (a font change moves the labels)
        PaintTabs()
        if MeasureHead() ~= (dock.headH or 0) then dock.refresh = true end

        local lit = on and whispers.unread > 0
        if lit ~= w._lit then
            w._lit = lit
            Chat.LightWhisper(w, lit, d)
        end
    end

    for _, it in ipairs(ITEMS) do
        local b = dock.items[it.id]
        if d.items[it.id] and not b._dead then
            b._t = (b._t or 99) + step
            if b._t >= (it.every or 1) then
                b._t = 0
                local ok, text = pcall(it.text)
                if not ok then
                    -- one bad read retires the item rather than erroring
                    -- every second; /zui chatinfo says which and why
                    b._dead = tostring(text)
                    text = ""
                end
                if SetItemText(b, text) then dirty = true end
            end
        elseif b._now ~= "" then
            SetItemText(b, "")
            b._t = 99
            dirty = true
        end
    end

    if dirty then LayoutBar() end
    if dock.refresh then
        dock.refresh = nil
        Chat.Refresh()
    end
end

local function BuildBar()
    if dock.bar or not DEFAULT_CHAT_FRAME then return end
    local UI = ns.UI
    local cf = DEFAULT_CHAT_FRAME

    -- A UIParent child like the panels (see SkinChatFrame), hung from the
    -- General window: every docked window sits exactly where that one is.
    local bar = CreateFrame("Button", "ZacUIChatBar", UIParent)
    ZUI.skinned[bar] = true
    -- known from its first line, so a build that fails part way can be
    -- cleaned up rather than leaving an empty button under the chat
    dock.bar = bar
    -- above the chat frames, whose hit area reaches past their text, and
    -- below the edit box
    bar:SetFrameStrata("MEDIUM")
    bar:SetFrameLevel(1)
    bar:SetHeight(BarH())
    bar:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", -(PAD - 1), -GAP)
    bar:SetPoint("TOPRIGHT", cf, "BOTTOMRIGHT", PAD - 1, -GAP)
    MakeBarLook(bar)

    bar:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    bar:SetScript("OnClick", function(_, button)
        if button == "RightButton" then BarMenu() else OpenChat("") end
    end)

    -- everything that steps aside while you type
    local content = CreateFrame("Frame", nil, bar)
    content:SetAllPoints()
    dock.content = content

    BuildChips()
    BuildItems()

    bar:SetScript("OnSizeChanged", function() dock.dirty = true; LayoutBar() end)
    bar:SetScript("OnShow", function() dock.fast, dock.slow = 99, 99 end)
    bar:SetScript("OnUpdate", function(_, dt)
        dock.fast = (dock.fast or 99) + dt
        if dock.fast < 0.25 then return end
        local step = math.min(dock.fast, 5)
        dock.fast = 0
        Tick(step)
    end)

    dock.money0 = GetMoney and GetMoney() or nil

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("CHAT_MSG_WHISPER")
    ev:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
    pcall(ev.RegisterEvent, ev, "CHAT_MSG_BN_WHISPER")
    pcall(ev.RegisterEvent, ev, "CHAT_MSG_BN_WHISPER_INFORM")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function(_, event, text, sender)
        if event == "PLAYER_ENTERING_WORLD" then
            -- money is not known until the world is
            if not dock.money0 or dock.money0 == 0 then dock.money0 = GetMoney and GetMoney() or nil end
        elseif event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER" then
            local name = sender or "?"
            if event == "CHAT_MSG_WHISPER" then name = ns.ShortName(name) end
            -- (the privacy cover, Chat_Privacy: the hover list shows the
            -- mask instead of the words while it is on)
            if ns.ChatPrivacy and ns.ChatPrivacy.Mask then text = ns.ChatPrivacy.Mask(text) end
            table.insert(whispers.log, 1, { name = name, text = text or "", at = time() })
            for i = #whispers.log, KEEP_WHISPERS + 1, -1 do whispers.log[i] = nil end
            whispers.unread = whispers.unread + 1
        else
            -- you answered somebody: nothing is waiting any more
            whispers.unread = 0
        end
        dock.slow = 99
    end)
    dock.events = ev
end

-- ============================================================
-- COPY CHAT
-- ============================================================
-- The game has no clipboard, so copying chat means putting it in a box
-- you can select from. Colour codes and icons come out; links become
-- their [name].
local function PlainLine(text)
    text = tostring(text or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    text = text:gsub("|n", "\n")
    return text
end

function Chat.CopyChat(cf)
    cf = cf or SelectedFrame()
    local UI = ns.UI
    if not (cf and cf.GetNumMessages and cf.GetMessageInfo and UI) then
        Print("copy chat: this chat window cannot be read.")
        return
    end

    local win = dock.copy
    if not win then
        -- (2026-11-08) the popup shell (UIF_Dialogs UI.Popup)
        win = (UI.Popup or UI.Window)("ZacUIChatCopy", 620, 400, "Copy chat")
        local pad = win.pad or 12
        local box = UI.TextBox(win, { width = 620 - 2 * pad, height = 330 })
        if UI.PopupField then UI.PopupField(box) end
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", win, "TOPLEFT", pad, -(win.headerHeight or 30))
        box:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -pad, pad + 16)
        -- the text wraps to the box, at whatever size the window is
        box:SetScript("OnSizeChanged", function(self, width)
            if width and width > 40 then self.editBox:SetWidth(width - 14) end
        end)
        local hint = UI.PopupText and UI.PopupText(win, "hint",
            { text = "Click in the text, Ctrl+A to select it all, Ctrl+C to copy." })
            or UI.Font(win, UI.F.SMALL, { cat = "text", key = "gray",
            text = "Click in the text, Ctrl+A to select it all, Ctrl+C to copy." })
        hint:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", pad, pad - 4)
        UI.AttachResizeGrip(win, { minW = 360, minH = 220, maxW = 1400, maxH = 1000 })
        win.box = box
        dock.copy = win
    end

    local n = cf:GetNumMessages() or 0
    local lines = {}
    for i = math.max(1, n - COPY_LINES + 1), n do
        local ok, text = pcall(cf.GetMessageInfo, cf, i)
        if ok and text then lines[#lines + 1] = PlainLine(text) end
    end
    win.box:SetText(table.concat(lines, "\n"))
    local tab = cf.GetName and cf:GetName() and _G[cf:GetName() .. "Tab"]
    local tabName = tab and tab.GetText and tab:GetText()
    local copyTitle = "Copy chat" .. ((tabName and tabName ~= "") and (" - " .. tabName) or "")
    if win.SetTitle then win:SetTitle(copyTitle) elseif win.titleText then win.titleText:SetText(copyTitle) end
    UI.OpenWindow(win)
    -- newest at the bottom, so open there
    C_Timer.After(0.05, function()
        local eb = win.box.editBox
        local scroll = eb and eb:GetParent()
        if scroll and scroll.SetVerticalScroll then
            scroll:SetVerticalScroll(math.max(0, (eb:GetHeight() or 0) - (scroll:GetHeight() or 0)))
        end
    end)
end

-- ============================================================
-- RIGHT-CLICK MENU
-- ============================================================
BarMenu = function()
    local UI = ns.UI
    if not (UI and UI.ContextMenu) then return end
    local function Toggle(label, get, set)
        return { text = label, keepOpen = true, checked = get,
                 func = function() set(not get()); Chat.Refresh() end }
    end
    local items = { { text = "Show on the chat bar", isTitle = true } }
    for _, it in ipairs(ITEMS) do
        items[#items + 1] = Toggle(it.label,
            function() return DB().items[it.id] and true or false end,
            function(v) DB().items[it.id] = v end)
    end
    items[#items + 1] = { separator = true }
    items[#items + 1] = Toggle("Channel buttons",
        function() return DB().channels end, function(v) DB().channels = v end)
    items[#items + 1] = Toggle("Whisper counter",
        function() return DB().whispers end, function(v) DB().whispers = v end)
    items[#items + 1] = Toggle("Jump to latest",
        function() return DB().latest end, function(v) DB().latest = v end)
    items[#items + 1] = { separator = true }
    items[#items + 1] = { text = "Copy chat...", func = function() Chat.CopyChat() end }
    items[#items + 1] = { text = "Chat settings...",
        func = function() if ns.OpenConfig then ns.OpenConfig("chat") end end }
    UI.ContextMenu(items)
end

-- ============================================================
-- APPLY
-- ============================================================
-- Called by the Chat page after any change and by the module on load.
-- The bar's look after a settings change: height, colours, the text's
-- font (which resizes every button and number slot to fit it).
local function StyleBar(d)
    local bar = dock.bar
    if not bar then return end
    bar:SetHeight(BarH())
    bar:_zPaint()
    for _, chip in ipairs(dock.chips or {}) do
        chip:SetHeight(BarH() - 6)
        StyleBarText(chip._label, d)
        chip._sized = nil
        SizeChip(chip, chip == dock.whisper and "W 9" or nil)
    end
    for _, it in ipairs(ITEMS) do
        local b = dock.items and dock.items[it.id]
        if b then
            b:SetHeight(BarH() - 2)
            StyleBarText(b._label, d)
            b._wide = math.ceil(WidthOf(b._label, it.sample or "") + 12)
            if b._now ~= "" then
                b._wide = math.max(b._wide, math.ceil((b._label:GetStringWidth() or 0) + 12))
            end
        end
    end
    dock.dirty = true
    if dock.whisper and dock.whisper._lit then Chat.LightWhisper(dock.whisper, true, d) end
end

-- The unread-whisper glow: Blizzard-style pulse by default, the chosen
-- animation on its own frame when one is picked.
function Chat.LightWhisper(w, lit, d)
    d = d or DB()
    local spec = d.whisperAnim
    local custom = type(spec) == "table" and spec.style and spec.style ~= "none" and ns.Motion
    w._pulse:Stop()
    w._glow:SetAlpha(0)
    if w._alertHost then
        if ns.Motion then ns.Motion.Stop(w._alertHost) end
        w._alertHost:Hide()
    end
    w._customLit = nil
    if not lit then return end
    if custom and w._alertHost then
        w._customLit = true
        local s = ns.CopySetting and ns.CopySetting(spec) or spec
        if ns.Motion.LOOPS and ns.Motion.LOOPS[s.style] and s.loop == nil then s.loop = true end
        w._alertHost:Show()
        ns.Motion.Play(w._alertHost, s, "update")
    else
        w._glow:SetAlpha(1)
        w._pulse:Play()
    end
end

-- Old messages: Blizzard's own timings unless set (0 = Blizzard's).
local function ApplyFadeTimes(cf, d)
    if not cf.SetTimeVisible then return end
    if not cf._zStockFade and cf.GetTimeVisible then
        cf._zStockFade = { cf:GetTimeVisible(), cf.GetFadeDuration and cf:GetFadeDuration() or nil }
    end
    local stock = cf._zStockFade or {}
    local tv = tonumber(d.timeVisible) or 0
    if tv > 0 then cf:SetTimeVisible(tv) elseif stock[1] then cf:SetTimeVisible(stock[1]) end
    local fd = tonumber(d.fadeDuration) or 0
    if cf.SetFadeDuration then
        if fd > 0 then cf:SetFadeDuration(fd) elseif stock[2] then cf:SetFadeDuration(stock[2]) end
    end
end

function Chat.Refresh()
    if not dock.built then return end
    local d = DB()
    dock.barH = math.max(14, math.min(40, tonumber(d.barHeight) or BAR_H))
    FADE_IN = math.max(0, tonumber(d.tabFadeIn) or 0.12)
    FADE_OUT = math.max(0, tonumber(d.tabFadeOut) or 0.30)
    LINGER = math.max(0, tonumber(d.tabLinger) or 0.6)
    StyleBar(d)
    if dock.head then dock.head:_zPaint() end
    -- the strip first: the docked panels are placed around it
    dock.headH = MeasureHead()
    PlaceHead()
    SyncBar()
    EachChatFrame(function(cf)
        if cf.SetFading then cf:SetFading(d.fade and true or false) end
        ApplyFadeTimes(cf, d)
        StyleBlizzText(cf, Chat.FontSpec("messages", d), true)
        Chat.ApplyIndent(cf, d)
        Chat.StyleGrip(cf)
        SkinTab(cf)
        PlacePanel(cf)
        PlaceEditBox(cf)
    end)
    ApplyTabVisibility()
    if Chat.RaidMode and Chat.RaidMode.strip then Chat.RaidMode.Apply() end
    if dock.bar and dock.items then
        -- read every number again now rather than on its own clock
        for _, b in pairs(dock.items) do b._t = 99 end
        dock.fast, dock.slow, dock.dirty = 99, 99, true
        if dock.content then dock.content:SetShown(not Typing()) end
    end
    if Chat.ApplyWidth then Chat.ApplyWidth() end
    -- the icon rail beside the panel (Chat_Panel)
    if Chat.RailRefresh then pcall(Chat.RailRefresh, d) end
end

local refreshQueued
local function RefreshSoon()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = nil
        Chat.Refresh()
    end)
end

function Chat.Built() return dock.built == true end

-- ============================================================
-- SAME WIDTH ON EVERY CHARACTER
-- ============================================================
-- Blizzard keeps the chat window's size per character. With sameWidth on,
-- every character on the account opens with the main window at
-- ZacUIDB.chat.width, saved back through Blizzard's own call so the game
-- remembers it too (and ZacUF's raid fit follows). Chat frames are not
-- protected, so this is fine at any time.
-- SAME SIZE AND SPOT ON EVERY CHARACTER: with sameSpot on, the main
-- window's rect (BOTTOMLEFT offsets + size, in its own units) lives in
-- ZacUIDB.chat.spot. The first character to load with it on records its
-- window; every character after that opens there. Moving or resizing the
-- window (Blizzard saves it then) records the new rect for everyone. The
-- spot is applied once per session, so a drag in progress is never
-- pulled back.
local spotApplied = false
local spotReady = false     -- set 1s after login, once Blizzard has placed it

local function ReadSpot(cf)
    local l, b = cf:GetLeft(), cf:GetBottom()
    if not l then return nil end
    return { x = math.floor(l * 100 + 0.5) / 100, y = math.floor(b * 100 + 0.5) / 100,
             w = math.floor(cf:GetWidth() * 100 + 0.5) / 100,
             h = math.floor(cf:GetHeight() * 100 + 0.5) / 100 }
end

local function ApplySpot(d, cf)
    local sp = type(d.spot) == "table" and d.spot or nil
    if not (sp and tonumber(sp.x) and tonumber(sp.y) and tonumber(sp.w) and tonumber(sp.h)) then
        d.spot = ReadSpot(cf)
        spotApplied = d.spot ~= nil
        return
    end
    spotApplied = true
    local w = (d.sameWidth and tonumber(d.width)) or sp.w
    local cur = ReadSpot(cf)
    if cur and math.abs(cur.x - sp.x) < 0.5 and math.abs(cur.y - sp.y) < 0.5
        and math.abs(cur.w - w) < 0.5 and math.abs(cur.h - sp.h) < 0.5 then return end
    cf:ClearAllPoints()
    cf:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", sp.x, sp.y)
    cf:SetSize(w, sp.h)
    if FCF_SavePositionAndDimensions then FCF_SavePositionAndDimensions(cf) end
    RefreshSoon()
end

if FCF_SavePositionAndDimensions then
    hooksecurefunc("FCF_SavePositionAndDimensions", function(cf)
        if cf ~= _G.ChatFrame1 or not spotApplied then return end
        local d = DB()
        if not d.sameSpot then return end
        local sp = ReadSpot(cf)
        if not sp then return end
        d.spot = sp
        if d.sameWidth then d.width = math.floor(sp.w + 0.5) end
    end)
end

function Chat.ApplyWidth()
    local d = DB()
    local cf = _G.ChatFrame1
    if not cf then return end
    if d.sameSpot then
        if not spotReady then return end
        if not spotApplied then ApplySpot(d, cf) end
        -- the width slider still works with the spot on
        local w = d.sameWidth and tonumber(d.width)
        if w and w >= 100 and math.abs((cf:GetWidth() or 0) - w) >= 0.5 then
            cf:SetWidth(w)
            if FCF_SavePositionAndDimensions then FCF_SavePositionAndDimensions(cf) end
            RefreshSoon()
        end
        return
    end
    spotApplied = false
    if not d.sameWidth then return end
    -- switched on with no width yet: this window's width becomes the one
    if not tonumber(d.width) then d.width = math.floor((cf:GetWidth() or 400) + 0.5) end
    local w = tonumber(d.width)
    if w < 100 then return end
    if math.abs((cf:GetWidth() or 0) - w) < 0.5 then return end
    cf:SetWidth(w)
    if FCF_SavePositionAndDimensions then FCF_SavePositionAndDimensions(cf) end
    RefreshSoon()
end

do
    local wev = CreateFrame("Frame")
    wev:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- after Blizzard has put the window back where this character had it
    wev:SetScript("OnEvent", function()
        C_Timer.After(1, function()
            spotReady = true
            Chat.ApplyWidth()
        end)
    end)
end

function Chat.Diagnose()
    Print("--- chat ---")
    if not dock.built then
        Print("the chat module has not run (is it off on the Modules page?)")
        return
    end
    local d = DB()
    Print("Prat loaded: " .. tostring(PratOwns())
        .. "   chat style: " .. tostring(GetCVar and GetCVar("chatStyle"))
        .. "   edit box: " .. tostring(d.editBox)
        .. "   new chat code: " .. tostring(ChatFrameUtil ~= nil))
    local bar = dock.bar
    if bar then
        Print(string.format("bar: want=%s shown=%s width=%d typing=%s", tostring(d.bar),
            tostring(bar:IsShown()), math.floor((bar:GetWidth() or 0) + 0.5), tostring(Typing())))
    else
        Print("bar: |cffff9900not built|r")
    end
    EachChatFrame(function(cf, name)
        if cf:IsShown() or InDock(cf) then
            local eb = EditBoxOf(cf)
            Print(string.format("%-12s docked=%-5s shown=%-5s panel=%-5s box=%s%s", name,
                tostring(InDock(cf)), tostring(cf:IsShown()), tostring(cf._zui_chatbg ~= nil),
                eb and tostring(eb._zWhere) or "|cffff9900none|r",
                eb and ("  shown=" .. tostring(eb:IsShown()) .. " alpha=" .. string.format("%.2f", eb:GetAlpha() or 0)) or ""))
        end
    end)
    do
        -- where the General tab's label really is, which is what the
        -- strip is sized from
        local cf = DEFAULT_CHAT_FRAME
        local tab = TabOf(cf)
        local text = TabText(tab)
        local top, bottom, base = text and text.GetTop and text:GetTop(), text and text.GetBottom and text:GetBottom(), cf and cf.GetTop and cf:GetTop()
        Print(string.format("tabs: styled=%s strip=%s visible=%s (mouse over chat: %s)  strip height=%d (%s)  label top %s / bottom %s above the text area  tab alpha %s",
            tostring(d.tabs), tostring(d.tabStrip), tostring(d.tabsVisible),
            tostring(MouseOverChat(SelectedFrame(), true)), dock.headH or 0,
            dock.head and (dock.head:IsShown() and "showing" or "hidden") or "|cffff9900not built|r",
            (top and base) and string.format("%.1f", top - base) or "?",
            (bottom and base) and string.format("%.1f", bottom - base) or "?",
            (tab and tab.GetAlpha) and string.format("%.2f", tab:GetAlpha() or 0) or "?"))
        if tab and tab.GetFrameStrata then
            Print("General tab: strata " .. tostring(tab:GetFrameStrata()) .. " level " .. tostring(tab:GetFrameLevel())
                .. "   strip: strata BACKGROUND level 2   chip: " .. tostring(tab._zChip ~= nil))
        end
    end
    if bar and dock.items then
        for _, it in ipairs(ITEMS) do
            local b = dock.items[it.id]
            Print(string.format("%-8s on=%-5s %s", it.id, tostring(d.items[it.id]),
                b._dead and ("|cffff9900failed:|r " .. b._dead)
                or (b._now ~= "" and (b:IsShown() and "showing" or "no room") or "nothing to show")))
        end
    end
    Print("whispers waiting: " .. whispers.unread)
end

-- ============================================================
-- RAID MODE
-- ============================================================
-- In a raid the docked chat box holds the RAID FRAMES (ZacUF fits them to
-- the message area through ZacUIRaidChat.Area) and the chat text goes
-- out of sight; nothing is lost - every line still lands in the window.
-- A strip where the tabs sit carries:
--   [Raid] [Chat 3]                                  [Hide msgs]
-- Raid warnings, whispers and raid / raid-leader lines pop over the top of
-- the frames for a few seconds: X on one dismisses it, a right-click
-- clears them all, a whisper left-clicked opens the reply. "Hide msgs"
-- (or the key bound to it, or /zui msgs) silences them; the Chat count
-- keeps going. Chat - or Enter, or a reply - brings the whole chat back
-- over the frames; Raid (or finishing what you were typing) puts it away.
-- Room at the top of the box can be kept clear (SetReserveTop) for a
-- docked route tracker, which ZacLayout puts there.
--
-- Combat-safe by construction: chat frames, tabs and the frames' alpha
-- are not protected; ZacUF places the secure raid frames itself and waits
-- for the fight to end. The message events are only listened to in a raid.
-- PARTY (2026-10-22, Zac: "can party frames also go inside chat as
-- well"): in a party (not a raid) the same goes for the PARTY frames,
-- with party / party-leader lines popping instead of the raid ones
-- (chat.raidModeParty, on with the mode; RM.kind says which).
local RM = { active = false, peek = false, temp = false, unread = 0, reserve = 0,
             live = {}, rows = {}, STRIP_H = 18, TTL = 8, FADE = 0.6, MAX = 3 }
Chat.RaidMode = RM
RM.EVENTS = { CHAT_MSG_RAID_WARNING = "RAID_WARNING", CHAT_MSG_WHISPER = "WHISPER",
              CHAT_MSG_BN_WHISPER = "BN_WHISPER", CHAT_MSG_RAID_LEADER = "RAID_LEADER",
              CHAT_MSG_RAID = "RAID" }
RM.TAGS = { RAID_WARNING = "RW", WHISPER = "W", BN_WHISPER = "W", RAID_LEADER = "RL", RAID = "R",
            PARTY = "P", PARTY_LEADER = "PL" }
-- in a party: the whispers, plus party and party-leader lines
RM.PARTY_EVENTS = { CHAT_MSG_WHISPER = "WHISPER", CHAT_MSG_BN_WHISPER = "BN_WHISPER",
                    CHAT_MSG_PARTY = "PARTY", CHAT_MSG_PARTY_LEADER = "PARTY_LEADER" }

-- the account's switch, or this character's own when one is set
function RM.Enabled()
    local own = ZacUICharDB and ZacUICharDB.chatRaidMode
    if own ~= nil then return own == true end
    return DB().raidMode == true
end

-- the party frames in the box too, in a party
function RM.PartyEnabled()
    return RM.Enabled() and DB().raidModeParty ~= false
end

-- "raid", "party" or nil: what the box holds right now
function RM.Kind() return RM.active and RM.kind or nil end

function RM.ToUI(f, v) return v * f:GetEffectiveScale() / UIParent:GetEffectiveScale() end

-- The raid frames' room: the docked panel's message area (UIParent units,
-- from its bottom-left), less the reserved top when withReserve.
function RM.Area(withReserve)
    local cf = DEFAULT_CHAT_FRAME
    local bg = cf and cf._zui_chatbg
    if not (bg and bg:GetLeft() and cf:GetBottom()) then return nil end
    local l = RM.ToUI(bg, bg:GetLeft()) + 3
    local r = RM.ToUI(bg, bg:GetRight()) - 3
    local t = RM.ToUI(bg, bg:GetTop()) - 3
    local b
    if BarFor(cf) and dock.bar:GetTop() then b = RM.ToUI(dock.bar, dock.bar:GetTop()) + 2
    else b = RM.ToUI(bg, bg:GetBottom()) + 3 end
    if withReserve and RM.kind ~= "party" and RM.RouteUp() then t = t - (RM.reserve or 0) end
    return l, r, t, b
end

function RM.IsActive() return RM.active end

-- Is Readycheck tracking a route here? The room at the top is only kept
-- while it is: no route on, or none set up for this raid's config, and
-- the raid frames have the whole box.
function RM.RouteUp()
    local RC = _G.Readycheck
    local RR = RC and RC.RaidRoute
    local st = RR and RR.GetSettings and RR:GetSettings()
    if not (st and st.enabled and st.trackerEnabled ~= false and RR.raidName) then return false end
    -- a finished route's bar folds away (Readycheck, bar style): the raid
    -- frames take the whole box again once it has (2026-10-28, Zac:
    -- "when routes is done raid uf should take back up the entire chat box")
    if RR.finished and not (RR.trackerFrame and RR.trackerFrame:IsShown()) then return false end
    local ok, steps = pcall(RR.GetSteps, RR)
    return ok and type(steps) == "table" and #steps > 0 or false
end

-- re-fit when that changes (a route switched on or off, a raid entered)
function RM.CheckRoute()
    local up = RM.RouteUp()
    if up == RM.routeUp then return end
    RM.routeUp = up
    RM.PlaceToasts()
    if RM.active and (RM.reserve or 0) > 0 then RM.Refit() end
end

function RM.Refit()
    local Z = _G.ZacUF
    if Z and Z.FitRaidToChat then C_Timer.After(0, function() Z.FitRaidToChat() end) end
end

function RM.SetReserveTop(h)
    h = math.max(0, tonumber(h) or 0)
    if math.abs(h - (RM.reserve or 0)) < 0.5 then return end
    RM.reserve = h
    RM.PlaceToasts()
    if RM.active then RM.Refit() end
end

-- ---- the toasts ----
function RM.ClearToasts()
    wipe(RM.live)
    RM.LayoutToasts()
end

function RM.PlaceToasts()
    local h = RM.holder
    if not h then return end
    local l, r, t = RM.Area(true)
    if not l then return end
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l + 3, t - 3)
    h:SetWidth(math.max(60, r - l - 6))
end

function RM.Row(i)
    local row = RM.rows[i]
    if row then return row end
    local UI = ns.UI
    row = UI.Box(RM.holder, "ui", "windowBg", { alpha = 0.9 })
    row:SetHeight(18)
    row:EnableMouse(true)
    row.chip = UI.Box(row, "ui", "accent", { border = false })
    row.chip:SetSize(18, 11)
    row.chip:SetPoint("LEFT", row, "LEFT", 5, 0)
    row.tag = UI.Font(row.chip, 9, { outline = "" })
    row.tag:SetPoint("CENTER", row.chip, "CENTER", 0, 0)
    row.tag:SetTextColor(0.08, 0.06, 0.03, 1)
    row.text = UI.Font(row, 11)
    row.text:SetPoint("LEFT", row.chip, "RIGHT", 6, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -22, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.x = UI.CloseX(row, 12, function()
        for k, rec in ipairs(RM.live) do
            if rec == row.rec then table.remove(RM.live, k) break end
        end
        RM.LayoutToasts()
    end)
    row.x:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then RM.ClearToasts() return end
        local rec = self.rec
        if rec and (rec.kind == "WHISPER" or rec.kind == "BN_WHISPER") then
            ReplyTell(DEFAULT_CHAT_FRAME)
        else
            RM.SetPeek(true, false)
        end
    end)
    UI.Tooltip(row, "Raid message", "Left-click: open the chat (a whisper: reply).\nRight-click: clear them all.\nX: dismiss this one.")
    RM.rows[i] = row
    return row
end

function RM.LayoutToasts()
    local h = RM.holder
    if not h then return end
    local n = 0
    for i, rec in ipairs(RM.live) do
        if i > RM.MAX then break end
        n = i
        local row = RM.Row(i)
        row.rec = rec
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", h, "TOPLEFT", 0, -(i - 1) * 20)
        row:SetPoint("TOPRIGHT", h, "TOPRIGHT", 0, -(i - 1) * 20)
        row.tag:SetText(RM.TAGS[rec.kind] or "")
        row.chip:SetWidth(math.max(14, (row.tag:GetStringWidth() or 8) + 6))
        if row.chip._zFill then row.chip._zFill:SetVertexColor(rec.r, rec.g, rec.b, 1) end
        row.text:SetText(rec.text)
        row.text:SetTextColor(rec.r, rec.g, rec.b, 1)
        row:SetAlpha(1)
        row:Show()
    end
    for i = n + 1, #RM.rows do RM.rows[i]:Hide() end
    h:SetHeight(math.max(1, n * 20))
    h:SetShown(n > 0 and RM.hidden == true and not DB().raidMsgsHidden)
end

function RM.AddToast(kind, text)
    local info = ChatTypeInfo and ChatTypeInfo[kind]
    local rec = { kind = kind, text = text, born = GetTime(),
                  r = info and info.r or 1, g = info and info.g or 0.8, b = info and info.b or 0.4 }
    table.insert(RM.live, 1, rec)
    while #RM.live > RM.MAX do table.remove(RM.live) end
    RM.LayoutToasts()
end

-- ten looks a second, and only while a toast is up
function RM.ToastTick(self, dt)
    self.t = (self.t or 0) + dt
    if self.t < 0.1 then return end
    self.t = 0
    local now, changed = GetTime(), false
    for i = #RM.live, 1, -1 do
        local rec = RM.live[i]
        local age = now - rec.born
        if age >= RM.TTL then
            table.remove(RM.live, i)
            changed = true
        else
            local row = RM.rows[i]
            if row and row.rec == rec then
                row:SetAlpha((age > RM.TTL - RM.FADE) and math.max(0, (RM.TTL - age) / RM.FADE) or 1)
            end
        end
    end
    if changed then RM.LayoutToasts() end
end

-- ---- the strip ----
-- Room at the end of the chat's own tab row for the one way back while
-- the chat is up (2026-10-23, Zac: "overlap in the header where it says
-- log general other and then the raid frames button"): the game's tab
-- dock is narrowed by px, and given its width back after.
local function DockInset(px)
    local dm = _G.GeneralDockManager
    if not (dm and dm.GetNumPoints and dm.ClearAllPoints) then return end
    if px > 0 then
        if dm._zRMInset == px then return end
        if not dm._zRMPts then
            local pts = {}
            for i = 1, dm:GetNumPoints() do pts[i] = { dm:GetPoint(i) } end
            dm._zRMPts, dm._zRMW = pts, dm:GetWidth()
        end
        local right = false
        dm:ClearAllPoints()
        for _, p in ipairs(dm._zRMPts) do
            local x = p[4] or 0
            if type(p[1]) == "string" and p[1]:find("RIGHT") then x = x - px; right = true end
            dm:SetPoint(p[1], p[2], p[3], x, p[5] or 0)
        end
        if not right and (dm._zRMW or 0) > px then dm:SetWidth(dm._zRMW - px) end
        dm._zRMInset = px
    elseif dm._zRMPts then
        dm:ClearAllPoints()
        for _, p in ipairs(dm._zRMPts) do dm:SetPoint(p[1], p[2], p[3], p[4] or 0, p[5] or 0) end
        if dm._zRMW and dm._zRMW > 0 then dm:SetWidth(dm._zRMW) end
        dm._zRMPts, dm._zRMW, dm._zRMInset = nil, nil, nil
    else
        return
    end
    if FCFDock_UpdateTabs and GENERAL_CHAT_DOCK then pcall(FCFDock_UpdateTabs, GENERAL_CHAT_DOCK, true) end
end
RM.DockInset = DockInset

-- the Chat button's count (all a new raid line changes on the strip)
local function PaintUnread()
    local s = RM.strip
    if not s then return end
    local n = RM.unread or 0
    s.chatBtn:SetLabel(n > 0 and ("Chat |cff" .. Hex(GetColor("text", "yellow")) .. n .. "|r") or "Chat")
end
-- raid chat comes in bursts: one repaint of the count per burst
RM.PaintUnreadSoon = ns.Coalescer(PaintUnread, 0.2)

function RM.PaintStrip()
    local s = RM.strip
    if not s then return end
    s.raidBtn:SetActive(not RM.peek)
    s.chatBtn:SetActive(RM.peek)
    -- with the chat up its own tabs are back where the strip is: the
    -- strip lets the mouse through and keeps one way back, at the far end
    s:EnableMouse(not RM.peek)
    s.raidBtn:ClearAllPoints()
    local party = RM.kind == "party"
    if RM.peek then
        s.raidBtn:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 0, 0)
        s.raidBtn:SetWidth(party and 84 or 76)
        s.raidBtn:SetLabel(party and "Party frames" or "Raid frames")
        DockInset((party and 84 or 76) + 6)
    else
        DockInset(0)
        s.raidBtn:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 0, 0)
        s.raidBtn:SetWidth(party and 50 or 44)
        s.raidBtn:SetLabel(party and "Party" or "Raid")
    end
    s.chatBtn:SetShown(not RM.peek)
    s.msgBtn:SetShown(not RM.peek)
    PaintUnread()
    s.msgBtn:SetLabel(DB().raidMsgsHidden and "Show msgs" or "Hide msgs")
    -- (2026-11-08, Zac: the Party / Chat / Show msgs / Hide msgs buttons
    -- go - the chat rail's raid-frames, chat and messages icons do the
    -- same jobs). The strip stays as the frames' holder, but draws nothing
    -- and takes no clicks, and the chat's tabs keep their width.
    if RM.RailHasSwap == nil or RM.RailHasSwap() then
        s.raidBtn:Hide()
        s.chatBtn:Hide()
        s.msgBtn:Hide()
        s:EnableMouse(false)
        DockInset(0)
    end
end
-- the rail is up with its swap icons (Chat_Panel): then the strip's own
-- buttons are not needed
function RM.RailHasSwap()
    local CP = Chat.Panel or ns.ChatPanel
    if CP and CP.RailOn then return CP.RailOn() and true or false end
    return true
end

function RM.Build()
    if RM.strip or not DEFAULT_CHAT_FRAME then return end
    local bg = DEFAULT_CHAT_FRAME._zui_chatbg
    if not bg then return end
    local UI = ns.UI
    local s = CreateFrame("Frame", "ZacUIRaidChatStrip", UIParent)
    ZUI.skinned[s] = true
    s:SetFrameStrata("MEDIUM")
    s:SetFrameLevel(30)
    s:EnableMouse(true)
    s:SetPoint("BOTTOMLEFT", bg, "TOPLEFT", 0, 1)
    s:SetPoint("BOTTOMRIGHT", bg, "TOPRIGHT", 0, 1)
    s:SetHeight(RM.STRIP_H)
    s:Hide()
    local function Btn(text, w, tip, onClick)
        local b = UI.Button(s, text, { width = w, height = RM.STRIP_H, size = 10, onClick = onClick,
                                       tooltip = tip })
        return b
    end
    s.raidBtn = Btn("Raid", 44, "The raid frames (the chat stays out of sight).", function() RM.SetPeek(false) end)
    s.raidBtn:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 0, 0)   -- PaintStrip moves it while the chat is up
    s.chatBtn = Btn("Chat", 56, "The whole chat, over the raid frames. Enter does the same while you type.",
        function() RM.SetPeek(not RM.peek or RM.temp, false) end)
    s.chatBtn:SetPoint("LEFT", s.raidBtn, "RIGHT", 2, 0)
    s.msgBtn = Btn("Hide msgs", 72, "Stop or start the raid messages popping over the frames (/zui msgs, or a key: ZacUI chat in Key Bindings).",
        function() RM.ToggleMsgs() end)
    s.msgBtn:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 0, 0)
    RM.strip = s

    local h = CreateFrame("Frame", "ZacUIRaidChatToasts", UIParent)
    ZUI.skinned[h] = true
    h:SetFrameStrata("HIGH")
    h:SetSize(200, 1)
    h:Hide()
    h:SetScript("OnUpdate", RM.ToastTick)
    RM.holder = h

    RM.ev = CreateFrame("Frame")
    RM.ev:SetScript("OnEvent", RM.OnMessage)

    -- Enter opens the chat for as long as you type
    EachChatFrame(function(cf)
        local eb = EditBoxOf(cf)
        if eb and not eb._zRMHooked then
            eb._zRMHooked = true
            eb:HookScript("OnEditFocusGained", function()
                if RM.active and not RM.peek then RM.SetPeek(true, true) end
            end)
            local function Done()
                if not (RM.peek and RM.temp) then return end
                C_Timer.After(0.1, function()
                    if not (RM.peek and RM.temp) then return end
                    local typing = false
                    EachChatFrame(function(c)
                        local e = EditBoxOf(c)
                        if e and e:HasFocus() then typing = true end
                    end)
                    if not typing then RM.SetPeek(false) end
                end)
            end
            eb:HookScript("OnEditFocusLost", Done)
            eb:HookScript("OnHide", Done)
        end
    end)
    -- a new whisper window is skinned with its alpha put back; hide again
    if type(FCF_OpenTemporaryWindow) == "function" then
        hooksecurefunc("FCF_OpenTemporaryWindow", function() C_Timer.After(0, RM.Apply) end)
    end
    -- the route's state comes from Readycheck's tracker refresh
    local RR = _G.Readycheck and _G.Readycheck.RaidRoute
    if RR and type(RR.RefreshTracker) == "function" then
        hooksecurefunc(RR, "RefreshTracker", RM.CheckRoute)
    end
end

function RM.OnMessage(_, event, msg, sender)
    local kind = (RM.kind == "party" and RM.PARTY_EVENTS or RM.EVENTS)[event]
    if not kind or type(msg) ~= "string" then return end
    local who = sender or "?"
    if kind ~= "BN_WHISPER" then
        who = ns.ShortName(who)
        if (kind == "RAID" or kind == "RAID_LEADER" or kind == "RAID_WARNING"
            or kind == "PARTY" or kind == "PARTY_LEADER") and who == UnitName("player") then return end
    end
    RM.unread = (RM.unread or 0) + 1
    RM.PaintUnreadSoon()
    if RM.hidden and not DB().raidMsgsHidden then
        -- (a whisper's words under the privacy cover: the mask, Chat_Privacy)
        if (kind == "WHISPER" or kind == "BN_WHISPER") and ns.ChatPrivacy and ns.ChatPrivacy.Mask then
            msg = ns.ChatPrivacy.Mask(msg)
        end
        RM.AddToast(kind, who .. ": " .. msg)
    end
end

function RM.ToggleMsgs()
    local d = DB()
    d.raidMsgsHidden = not d.raidMsgsHidden
    if d.raidMsgsHidden then RM.ClearToasts() end
    RM.PaintStrip()
    RM.LayoutToasts()
    return d.raidMsgsHidden
end

-- ---- applying it ----
local function RMChatShown(on, peek)
    EachChatFrame(function(cf)
        if InDock(cf) then
            if on then
                if cf._zRMHid then
                    cf._zRMHid = nil
                    cf:SetAlpha(1)
                    cf:EnableMouse(true)
                    if cf.EnableMouseWheel then cf:EnableMouseWheel(true) end
                end
            else
                cf._zRMHid = true
                cf:SetAlpha(0)
                cf:EnableMouse(false)
                if cf.EnableMouseWheel then cf:EnableMouseWheel(false) end
            end
            -- over the raid frames while it is brought back in a raid
            if peek then
                if not cf._zRMStrata then cf._zRMStrata = cf:GetFrameStrata() end
                cf:SetFrameStrata("HIGH")
            elseif cf._zRMStrata then
                cf:SetFrameStrata(cf._zRMStrata)
                cf._zRMStrata = nil
            end
        end
    end)
end

function RM.Apply()
    if not RM.strip then return end
    local hidden = RM.active and not RM.peek
    RM.hidden = hidden
    Chat.raidHidden = hidden
    RMChatShown(not hidden, RM.active and RM.peek)
    local s = RM.strip
    s:SetHeight(((dock.headH or 0) >= 12) and dock.headH or RM.STRIP_H)
    s:SetShown(RM.active)
    -- the docked tabs and their strip stay out of the way under ours
    if hidden then
        if dock.head then dock.head:SetAlpha(0) end
        EachChatFrame(function(cf)
            if InDock(cf) and cf._zTab then SetTabAlpha(cf._zTab, 0) end
        end)
    elseif RM.wasHidden then
        ApplyTabVisibility()
        local d = DB()
        if not (d.tabs and d.tabsVisible == "hover") then
            EachChatFrame(function(cf)
                if InDock(cf) and cf._zTab then SetTabAlpha(cf._zTab, 1) end
            end)
        end
    end
    RM.wasHidden = hidden
    -- the frames and a docked tracker step aside while the chat is up
    local fade = RM.active and RM.peek
    if fade or RM.faded then
        local a = fade and 0 or 1
        local raid, tr = _G.ZacUF_raidHeader, _G.ReadycheckRouteTracker
        if raid then raid:SetAlpha(a) end
        local party = _G.ZacUF_partyHeader
        if party then party:SetAlpha(a) end
        if tr then tr:SetAlpha(a) end
        RM.faded = fade or nil
    end
    RM.PlaceToasts()
    RM.LayoutToasts()
    RM.PaintStrip()
end

function RM.SetPeek(on, temp)
    on = on and RM.active or false
    RM.peek = on
    RM.temp = on and temp and true or false
    if on then
        RM.unread = 0
        wipe(RM.live)
    end
    RM.Apply()
end

function RM.Update()
    if not dock.built then return end
    RM.Build()
    if not RM.strip then return end
    local kind
    if RM.Enabled() then
        if IsInRaid and IsInRaid() then kind = "raid"
        elseif RM.PartyEnabled() and IsInGroup and IsInGroup() then kind = "party" end
    end
    local want = kind ~= nil
    -- roster news that changes nothing here (most of it) does nothing to
    -- the box; while it holds the frames they are fitted again (one timer,
    -- the roster notice is already one per burst), so a fit that ran
    -- before the chat had settled is put right by the next roster change
    -- (2026-10-26: raid frames left at the top of the screen after a reload)
    if want == RM.active and (not want or kind == RM.kind) then
        if want then RM.Refit() end
        return
    end
    RM.active = want
    RM.kind = kind
    RM.peek, RM.temp, RM.unread = false, false, 0
    wipe(RM.live)
    for ev in pairs(RM.EVENTS) do pcall(RM.ev.UnregisterEvent, RM.ev, ev) end
    for ev in pairs(RM.PARTY_EVENTS) do pcall(RM.ev.UnregisterEvent, RM.ev, ev) end
    if want then
        for ev in pairs(kind == "party" and RM.PARTY_EVENTS or RM.EVENTS) do
            pcall(RM.ev.RegisterEvent, RM.ev, ev)
        end
    end
    RM.Apply()
    RM.Refit()
end

do
    -- One pending refresh at a time, whatever brought it on: roster news
    -- (the shared roster, already gathered into one notice per burst) and
    -- zoning a fifth of a second later, a load once the world has
    -- settled. Nothing of this runs while the chat module is off.
    local settleUntil, waiting = 0, false
    local function Refresh()
        if not dock.built then return end
        local wait = settleUntil - GetTime()
        if wait > 0 then
            -- a second loading screen moved the settle point on: come back
            -- once it passes instead of dropping this refresh
            if not waiting then
                waiting = true
                C_Timer.After(wait + 0.05, function() waiting = false; Refresh() end)
            end
            return
        end
        RM.Update()
        RM.CheckRoute()
    end
    local soon = ns.Coalescer(Refresh, 0.2)
    local late = ns.Coalescer(Refresh, 1.5)
    ns.Roster.On("Chat.raidMode", soon)
    local rev = CreateFrame("Frame")
    rev:RegisterEvent("PLAYER_ENTERING_WORLD")
    rev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    rev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            -- the roster's own load-time notice waits for this one
            settleUntil = GetTime() + 1.4
            late()
        else
            soon()
        end
    end)
end

-- the key binding (Bindings.xml) and other addons
BINDING_HEADER_ZACUICHAT = "ZacUI chat"
BINDING_NAME_ZACUI_RAIDMSGS = "Raid chat: hide / show the messages"
function ZacUI_ToggleRaidMsgs() RM.ToggleMsgs() end
_G.ZacUIRaidChat = {
    Enabled = RM.Enabled, IsActive = RM.IsActive, Area = RM.Area,
    PartyEnabled = RM.PartyEnabled, Kind = RM.Kind,
    SetReserveTop = RM.SetReserveTop, Update = function() RM.Update() end,
}

Chat.DB = DB
Chat.ITEMS = ITEMS
-- the match pass's numbers and test, and what the icon rail (Chat_Panel)
-- reads of the dock: the docked window in view, the panel it stands
-- beside, the strip's state, whether the mouse is over the chat
Chat.REF = REF
Chat.Match = Match
Chat.ZacLook = ZacLook
Chat.Tiles = Tiles
Chat.PanelRGB = PanelRGB
Chat.EdgeRGBA = EdgeRGBA
Chat.SelectedFrame = SelectedFrame
Chat.Dock = function() return dock end
Chat.DockUp = DockUp
Chat.MouseOverChat = function() return MouseOverChat(SelectedFrame(), true) end
-- The pieces the Chat page's preview is built from: the same panel, bar,
-- strip, tab chip, button and text functions the real chat uses.
Chat.Look = {
    LOOK = LOOK,
    BarH = function() return math.max(14, math.min(40, tonumber(DB().barHeight) or BAR_H)) end,
    EditH = EditH,
    PaintPanel = PaintPanel,
    MakeBarLook = MakeBarLook,
    MakeHeadLook = MakeHeadLook,
    MakeChip = MakeChip,
    PaintChipState = PaintChipState,
    Plate = function(parent) return Plate(parent) end,
    StyleBarText = StyleBarText,
    StyleBlizzText = StyleBlizzText,
    SizeChip = SizeChip,
    WidthOf = WidthOf,
    AddWhisperGlow = AddWhisperGlow,
    PaintChannel = PaintChip,
    LightWhisper = function(w, lit, d) Chat.LightWhisper(w, lit, d) end,
    Tone = Tone, Dim = Dim,
    PlaceTabText = PlaceTabText, PlaceEditBoxAt = PlaceEditBoxAt,
    TAB_TARGETS = { { value = "tab", text = "The tab" } },
    EDIT_TARGETS = { { value = "panel", text = "The chat panel" }, { value = "bar", text = "The bar" },
        { value = "tabs", text = "The tab strip" }, { value = "screen", text = "The screen" } },
    PAD = PAD, GAP = GAP, TAB_PAD_X = TAB_PAD_X, TAB_PAD_Y = TAB_PAD_Y,
}

Modules.chat = function()
    -- FULL chat treatment (per verdict: "do the entire chat if you're
    -- going to do that"): dark panel behind each window, side button
    -- column and utility buttons GONE (their functions live in the tab
    -- right-click menu), styled edit box and text-only tabs on top.
    local function HideForever(f)
        if not f or f._zui_hidden then return end
        f._zui_hidden = true
        ZUI.skinned[f] = true
        f:Hide()
        f:HookScript("OnShow", function(fh) fh:Hide() end)
        if f.UnregisterAllEvents then f:UnregisterAllEvents() end
    end

    -- One body for every chat window, so the pop-out whisper windows
    -- (ChatFrame11+, built later by FCF_OpenTemporaryWindow) get it too.
    -- Every step is fenced, so re-running on a recycled window is free.
    local function SkinChatFrame(name)
        local cf = _G[name]
        if cf then
            cf:SetAlpha(1)
            HideNamed(name, {
                "Background", "TopTexture", "BottomTexture", "LeftTexture", "RightTexture",
                "TopLeftTexture", "TopRightTexture", "BottomLeftTexture", "BottomRightTexture",
                "ButtonFrameBackground", "ButtonFrameTopTexture", "ButtonFrameBottomTexture",
                "ButtonFrameLeftTexture", "ButtonFrameRightTexture",
                "ButtonFrameTopLeftTexture", "ButtonFrameTopRightTexture",
                "ButtonFrameBottomLeftTexture", "ButtonFrameBottomRightTexture",
            })
            if cf.buttonFrame then HideForever(cf.buttonFrame) end

            -- Dark panel behind the window - a UIParent SIBLING, not a
            -- child: children share the parent's render/alpha chain, and
            -- the in-game observation was that the panel's alpha bled
            -- into the message text. A sibling anchored to the chat frame
            -- cannot interact with text alpha at all.
            if not cf._zui_chatbg then
                local bg = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
                bg:SetFrameStrata("BACKGROUND")
                cf._zui_chatbg = bg
                -- Sibling panels escape the parent's ALPHA chain (the
                -- point) but also its VISIBILITY chain (the black boxes:
                -- Blizzard pre-creates hidden ChatFrames and their
                -- always-shown sibling panels floated over nothing).
                -- Visibility syncs explicitly.
                bg:SetShown(cf:IsShown())
                cf:HookScript("OnShow", function(f)
                    if f._zui_chatbg then f._zui_chatbg:Show() end
                    SyncBar()
                end)
                cf:HookScript("OnHide", function(f)
                    if f._zui_chatbg then f._zui_chatbg:Hide() end
                    SyncBar()
                end)
            end
            -- where the panel ends depends on whether this window has the
            -- bar under it (PlacePanel), and so does the edit box
            PlacePanel(cf)

            local eb = _G[name .. "EditBox"]
            if eb then SkinEditBox(eb, EditH()) end
            PlaceEditBox(cf)

            local tab = _G[name .. "Tab"]
            if tab then
                -- Compact CHIP tabs: textured, but sized to the LABEL,
                -- not to Blizzard's huge hit-rect - the fill and border
                -- anchor to the tab's text with small padding, so no
                -- geometry fight with FCF docking ever occurs. Fenced
                -- from the classifier (skinned mark) as doctrine.
                ZUI.skinned[tab] = true
                ClearButtonArt(tab)
                local tn = tab:GetName()
                if tn then
                    HideNamed(tn, { "SelectedLeft", "SelectedMiddle", "SelectedRight",
                                    "HighlightLeft", "HighlightMiddle", "HighlightRight",
                                    "ActiveLeft", "ActiveMiddle", "ActiveRight" })
                end
                -- the chip (see TABS above); fenced, so a re-run only repaints
                pcall(SkinTab, cf)
            end

            if cf.SetFading then cf:SetFading(DB().fade and true or false) end
            if cf.ScrollBar then SkinAnyScrollBar(cf.ScrollBar) end
            if cf.ScrollToBottomButton then
                SkinArrowButton(cf.ScrollToBottomButton, "down")
            end
        end
    end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        SkinChatFrame("ChatFrame" .. i)
    end
    if type(FCF_OpenTemporaryWindow) == "function" then
        hooksecurefunc("FCF_OpenTemporaryWindow", function()
            for _, n in ipairs(CHAT_FRAMES or {}) do SkinChatFrame(n) end
        end)
    end
    -- Explicit appends (hole-in-ipairs law): QuickJoinToastButton is a
    -- retail-lineage global that may not exist on this build, and a nil
    -- mid-literal truncates the loop.
    local extras = {}
    local function AddExtra(b) if b then extras[#extras + 1] = b end end
    AddExtra(ChatFrameMenuButton)
    AddExtra(ChatFrameChannelButton)
    AddExtra(QuickJoinToastButton)
    for _, extra in ipairs(extras) do
        HideForever(extra)
    end

    -- THE BAR, then everything placed again now that it exists. Fenced in
    -- a pcall so a client that is missing a piece of it still gets the
    -- panels, the tabs and the edit box above.
    if not dock.built then
        local ok, err = pcall(BuildBar)
        if not ok then
            -- do not leave half a bar on screen
            if dock.bar then dock.bar:SetScript("OnUpdate", nil); dock.bar:Hide() end
            dock.bar, dock.content, dock.items, dock.chips = nil, nil, nil, nil
            Print("|cffff9900chat bar:|r could not be built (" .. tostring(err) .. "). The rest of the chat skin is unaffected.")
        end
        -- the frame that fades the tabs in under the mouse
        pcall(BuildHoverDriver)
        -- THE TAB STRIP, fenced the same way.
        local okHead, errHead = pcall(BuildHead)
        if not okHead then
            if dock.head then dock.head:Hide() end
            dock.head = nil
            Print("|cffff9900chat tab strip:|r could not be built (" .. tostring(errHead) .. "). The tabs themselves are unaffected.")
        end
        dock.built = true
        -- other addons' LibDataBroker blocks the player ticked (Chat_LDB)
        if ns.ChatLDB and ns.ChatLDB.Apply then pcall(ns.ChatLDB.Apply) end
        -- a window dragged out of, or into, the dock gains or loses the bar
        for _, fn in ipairs({ "FCF_DockFrame", "FCF_UnDockFrame" }) do
            if type(_G[fn]) == "function" then hooksecurefunc(fn, RefreshSoon) end
        end
        -- which tab is selected, and which has something new
        for _, fn in ipairs({ "FCF_StartAlertFlash", "FCF_StopAlertFlash", "FCFDock_SelectWindow", "FCF_SelectDockFrame" }) do
            if type(_G[fn]) == "function" then hooksecurefunc(fn, PaintTabsSoon) end
        end
        -- the older chat code announces a change of channel through a
        -- global; the newer one through the edit box (see HookEditBox)
        if type(ChatEdit_UpdateHeader) == "function" then
            hooksecurefunc("ChatEdit_UpdateHeader", function(eb) TintEditBox(eb) end)
        end
    end
    Chat.Refresh()
    -- once more when the world has settled: docking is restored from the
    -- saved layout after this module has already run
    C_Timer.After(2, Chat.Refresh)

    -- CHAT BUBBLES: in-world say/yell bubbles get the dark treatment.
    if C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles then
        local function SkinBubbles()
            for _, bubble in ipairs(C_ChatBubbles.GetAllChatBubbles()) do
                if not ZUI.skinned[bubble] then
                    ZUI.skinned[bubble] = true
                    local inner = select(1, bubble:GetChildren()) or bubble
                    StripDeep(inner, 0)
                    SkinBackdrop(inner, "windowBg", 0.92)
                end
            end
        end
        local bev = CreateFrame("Frame")
        local BUBBLE_EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL",
                                "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL",
                                "CHAT_MSG_PARTY", "CHAT_MSG_RAID" }
        -- Inside an instance the bubbles belong to the game alone (addons
        -- cannot touch them), so the chat events are only listened to
        -- outside one; zoning decides.
        local function Listen()
            local inside = IsInInstance()
            for _, e in ipairs(BUBBLE_EVENTS) do
                if inside then bev:UnregisterEvent(e) else pcall(bev.RegisterEvent, bev, e) end
            end
        end
        bev:RegisterEvent("PLAYER_ENTERING_WORLD")
        Listen()
        -- boss-mod raid spam is bursts of lines; one skin pass per burst
        local SkinSoon = ns.Coalescer(SkinBubbles, 0.05)
        bev:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_ENTERING_WORLD" then Listen() return end
            SkinSoon()
        end)
    end
end

-- shared with later ZacUI files
ns.Chat = Chat

-- TOOLTIPS
