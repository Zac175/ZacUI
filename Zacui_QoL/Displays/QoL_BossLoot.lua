-- QoL_BossLoot - a small card that lists what a boss dropped as it becomes
-- known, and who got each item. Off by default (Quality of life > Boss
-- loot); a mover ("Boss loot") puts it anywhere; a Test button plays a
-- sample kill. (2026-11-20, Zac: "something that will show ... what
-- dropped from a boss on my screen with a nice animation and stuff but not
-- be too intrusive or big off by default this should be zui".)
-- Part of ZacUI; load order is set by the TOC.
--
-- WHEN A CARD STARTS. A boss dies: ENCOUNTER_END with a kill (ns.Encounter),
-- in a raid or in a dungeon (a switch each). Where the game sends no
-- encounter (a world boss), looting the dead boss you have targeted starts
-- one. The next pull puts the card away.
--
-- WHAT IT KNOWS, for the "keep listening" time after the kill (five
-- minutes as shipped):
--   1. YOUR OWN LOOT WINDOW (LOOT_OPENED): every item on the corpse or in
--      the chest, at once.
--   2. GROUP LOOT ROLLS (START_LOOT_ROLL): each item being rolled for.
--   3. LOOT LINES (CHAT_MSG_LOOT, matched against the client's own
--      LOOT_ITEM formats so a localised client reads its own words):
--      "<name> receives loot: <item>" - the item if it is new, and who
--      got it.
--   4. LINKS IN GROUP CHAT from the master looter, the raid leader or an
--      assistant (a switch): under master loot only the looter sees the
--      corpse, and what they link is what dropped.
--   5. ENCOUNTER_LOOT_RECEIVED, on a client that sends it.
-- Items under the picked quality are left out (blue and up as shipped).
-- NOTHING IS LISTED TWICE: a roll or a loot line fills the entry the loot
-- window already made for that item; a chat link only adds an item not
-- yet listed.
--
-- SECRET-SAFE. On WoW Forever a chat line can be a hidden value in a
-- fight; one is skipped before any string work.
--
-- COST. Off, this file makes no frame and hears nothing. On, it hears
-- ns.Encounter and LOOT_OPENED; the chat and roll events are registered
-- only while a kill is being listened to. Every event only queues; the
-- queue drains on the next frame. No ticker, no OnUpdate: the animations
-- are ns.Motion's and stop by themselves.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local GetColor = ns.GetColor
local QoL = ns.QoL
if not (QoL and QoL.DB) then return end

local BL = {}
QoL.BossLoot = BL

local OWN_ID = "boss_loot"
local MOVER = "bossloot"
-- what ships (each a setting; nothing saved = these)
BL.DEFAULTS = { width = 230, iconSize = 22, maxRows = 8, quality = 3, hold = 15, collect = 300, bgAlpha = 0.6,
                pad = 6, rowGap = 4, stagger = 0.07 }
BL.LIMITS = { width = { 160, 400 }, iconSize = { 14, 40 }, maxRows = { 2, 16 }, quality = { 0, 5 },
              hold = { 4, 120 }, collect = { 30, 900 }, bgAlpha = { 0, 1 },
              pad = { 0, 16 }, rowGap = { 0, 12 }, stagger = { 0, 0.5 } }
-- EVERY PART IS A SETTING (2026-11-20, Zac: "fully customizable"); with
-- nothing saved each is what ships:
--   head (the boss's name, on), rule (the line under it, on), headAlign
--   ("LEFT"), headColor (ZacUI's accent); bgColor (the window ground),
--   border (on), borderColor (ZacUI's border); icons (on), iconEdge (the
--   icon's edge in the quality colour, on), counts (stack counts, on),
--   nameQuality (names in their quality colour, on); whoClass (winners in
--   their class colour, on), whoColor, whoFont (the item text's); glow
--   (an epic arrives with a glow, on), flash (a won row flashes, on);
--   more (the "+2 more" line, on); grow ("down", or "up": the card
--   builds upward from its spot).
BL.ALIGNS = { { value = "LEFT", text = "Left" }, { value = "CENTER", text = "Centre" }, { value = "RIGHT", text = "Right" } }
BL.GROWS = { { value = "down", text = "Down from its spot" }, { value = "up", text = "Up from its spot" } }
BL.FONT_DEFAULTS = { size = 12, outline = "outline", shadow = false }
BL.HEAD_FONT_DEFAULTS = { size = 12, outline = "outline", shadow = false }
-- the three animations (Appearance > Motion's switch and speed apply)
BL.ANIM = {
    show = { style = "slide", duration = 0.30, delay = 0, easing = "easeOutCubic", dir = "up", distance = 10 },
    hide = { style = "fade", duration = 0.50, delay = 0, easing = "easeOutQuad" },
    row  = { style = "slide", duration = 0.28, delay = 0, easing = "easeOutCubic", dir = "left", distance = 14 },
}
local ICON_UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"
local GLOW_TEX = "Interface\\Buttons\\UI-ActionButton-Border"

-- ============================================================
-- SETTINGS (qol.bossLoot; nothing saved = off). Reading writes nothing.
-- ============================================================
local EMPTY = {}
local function Cfg()
    local q = QoL.DB()
    return type(q.bossLoot) == "table" and q.bossLoot or EMPTY
end
local function Writable()
    local q = QoL.DB()
    if type(q.bossLoot) ~= "table" then q.bossLoot = {} end
    return q.bossLoot
end
BL.Cfg, BL.Writable = Cfg, Writable
local view = setmetatable({}, {
    __index = function(_, k) return Cfg()[k] end,
    __newindex = function(_, k, v) Writable()[k] = v end,
})
local function Allowed() return not (ns.FeatureOn and not ns.FeatureOn(OWN_ID)) end
function BL.On() return Allowed() and Cfg().enabled == true end
local function Num(key)
    local lim = BL.LIMITS[key]
    local v = tonumber(Cfg()[key]) or BL.DEFAULTS[key]
    if v ~= v then v = BL.DEFAULTS[key] end
    return math.max(lim[1], math.min(lim[2], v))
end
function BL.Width() return math.floor(Num("width") + 0.5) end
function BL.IconSize() return math.floor(Num("iconSize") + 0.5) end
function BL.MaxRows() return math.floor(Num("maxRows") + 0.5) end
function BL.MinQuality() return math.floor(Num("quality") + 0.5) end
function BL.Hold() return Num("hold") end
function BL.Collect() return Num("collect") end
function BL.BgAlpha() return Num("bgAlpha") end
local function Pad() return math.floor(Num("pad") + 0.5) end
local function RowGap() return math.floor(Num("rowGap") + 0.5) end
function BL.Stagger() return Num("stagger") end
BL.Pad, BL.RowGap = Pad, RowGap
-- a part: there unless switched off
local function Part(key) return Cfg()[key] ~= false end
BL.Part = Part
function BL.GrowsUp() return Cfg().grow == "up" end
function BL.HeadAlign()
    local a = Cfg().headAlign
    return (a == "CENTER" or a == "RIGHT") and a or "LEFT"
end
-- a colour that may be unset: the palette's until one is picked
local function ColorOr(key, cat, name)
    local c = Cfg()[key]
    if type(c) == "table" then return c.r or 1, c.g or 1, c.b or 1 end
    local p = GetColor(cat, name)
    return p.r, p.g, p.b
end
BL.ColorOr = ColorOr
-- a winner's colour: their class's, or the one picked (a quiet grey)
local function WhoColor(class)
    if Part("whoClass") and class and ns.ClassColor then return ns.ClassColor(class) end
    local c = Cfg().whoColor
    if type(c) == "table" then return c.r or 1, c.g or 1, c.b or 1 end
    return 0.85, 0.85, 0.85
end
BL.WhoColor = WhoColor
-- switches: on unless switched off / off unless switched on
function BL.InRaids() return Cfg().raids ~= false end
function BL.InDungeons() return Cfg().dungeons ~= false end
function BL.Winners() return Cfg().winners ~= false end
function BL.Links() return Cfg().links ~= false end
function BL.Tooltips() return Cfg().tooltips == true end
local function Anim(key)
    local s = Cfg()[key .. "Anim"]
    return type(s) == "table" and s or BL.ANIM[key]
end
BL.AnimOf = Anim

-- ============================================================
-- ITEMS
-- ============================================================
local function Secret(v) return ns.IsSecret and ns.IsSecret(v) or false end

-- an item link's quality: the game's answer, else the link's own colour
local function Quality(link)
    if GetItemInfo then
        local ok, _, _, q = pcall(GetItemInfo, link)
        if ok and type(q) == "number" then return q end
    end
    -- (the newer link form names it: |cnIQ4:)
    local iq = link:match("|cnIQ(%d):")
    if iq then return tonumber(iq) end
    local hex = link:match("|c(%x%x%x%x%x%x%x%x)")
    local Q = _G.ITEM_QUALITY_COLORS
    if hex and Q then
        hex = hex:lower()
        for q = 0, 7 do
            local c = Q[q]
            local h = c and c.hex and c.hex:lower():match("|c(%x%x%x%x%x%x%x%x)")
            if h == hex then return q end
        end
    end
    return 1
end
local function ItemIcon(link)
    if GetItemInfoInstant then
        local ok, _, _, _, _, icon = pcall(GetItemInfoInstant, link)
        if ok and icon then return icon end
    end
    if GetItemIcon then
        local ok, icon = pcall(GetItemIcon, link)
        if ok and icon then return icon end
    end
    return ICON_UNKNOWN
end
local function ItemID(link) return tonumber(link:match("|Hitem:(%d+)")) end
local function ItemName(link) return link:match("|h%[(.-)%]|h") or link:match("%[(.-)%]") or "?" end
BL.Quality, BL.ItemID = Quality, ItemID

-- every item link in a line of text
local function EachLink(text, fn)
    for link in text:gmatch("(|c[^|]*|Hitem:.-|h%[.-%]|h|r)") do fn(link) end
end

-- ============================================================
-- THE KILL BEING LISTENED TO
-- ============================================================
-- kill = { name, at, items = { entry ... }, test }
-- entry = { id, link, name, icon, quality, count, winner, class, rollID,
--           fromWindow, shown }
local kill, last
local closeTimer
local Render, StopListening   -- (forward)

-- An item heard of. how: "window" (your loot window: every slot is its own
-- item), "roll", "line" (a loot line, with who), "link" (group chat),
-- "got" (the client's own encounter loot).
-- -> the entry, and true when something changed
function BL.Note(how, link, count, who, class, rollID)
    if not kill or type(link) ~= "string" or Secret(link) then return nil, false end
    local id = ItemID(link)
    if not id then return nil, false end
    local q = Quality(link)
    if q < BL.MinQuality() then return nil, false end
    count = tonumber(count) or 1
    local items = kill.items
    local entry
    if how == "window" then
        -- (one entry per slot: two of a token are two rows)
    elseif how == "roll" then
        for _, e in ipairs(items) do
            if e.id == id and e.rollID == rollID then return e, false end       -- (heard twice)
        end
        for _, e in ipairs(items) do
            if e.id == id and not e.rollID and not e.winner then entry = e break end
        end
        if entry then entry.rollID = rollID return entry, false end
    elseif how == "line" or how == "got" then
        if who and BL.Winners() then
            -- (the same award heard twice - a loot line and the client's own event)
            for _, e in ipairs(items) do
                if e.id == id and e.winner == who then return e, false end
            end
        end
        for _, e in ipairs(items) do
            if e.id == id and not e.winner then entry = e break end
        end
        if entry then
            if who and BL.Winners() then
                entry.winner, entry.class = who, class
                return entry, true
            end
            return entry, false
        end
    else -- "link"
        for _, e in ipairs(items) do
            if e.id == id then return e, false end
        end
    end
    entry = { id = id, link = link, name = ItemName(link), icon = ItemIcon(link), quality = q, count = count,
              rollID = rollID, fromWindow = (how == "window") or nil }
    if who and BL.Winners() and (how == "line" or how == "got") then entry.winner, entry.class = who, class end
    items[#items + 1] = entry
    return entry, true
end

local function CloseWindow()
    if closeTimer then closeTimer:Cancel() closeTimer = nil end
    if kill then last = kill end
    kill = nil
    if StopListening then StopListening() end
end
BL.CloseWindow = CloseWindow

-- a new kill to listen to (the one before it is over)
function BL.Begin(name, test)
    CloseWindow()
    kill = { name = (type(name) == "string" and name ~= "") and name or "Boss", at = GetTime(), items = {}, test = test or nil }
    last = kill
    BL.ClearCard()
    if not test then
        BL.Listen()
        closeTimer = C_Timer.NewTimer(BL.Collect(), function()
            closeTimer = nil
            CloseWindow()
        end)
    end
    return kill
end
function BL.Kill() return kill end
function BL.Last() return last end

-- ============================================================
-- THE CARD
-- ============================================================
local holder, card
local rows = {}
local holdTimer

local function Font(fs, spec, defaults)
    if ns.ApplyFontSpec then ns.ApplyFontSpec(fs, spec, defaults)
    elseif ns.HouseFont then ns.HouseFont(fs, defaults.size, "OUTLINE") end
end
local function HeadHeight()
    if not Part("head") then return 0 end
    local f = Cfg().headFont
    local size = (type(f) == "table" and tonumber(f.size)) or BL.HEAD_FONT_DEFAULTS.size
    return math.floor(size + 8.5)
end
local function RowHeight() return BL.IconSize() + RowGap() end
function BL.HolderSize()
    return BL.Width(), Pad() * 2 + HeadHeight() + BL.MaxRows() * RowHeight() + 14
end

local function Row_OnEnter(self)
    if not (self._zLink and GameTooltip) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, self._zLink)
    if ok then GameTooltip:Show() else GameTooltip:Hide() end
end
local function Row_OnLeave() if GameTooltip then GameTooltip:Hide() end end
local function Row_OnClick(self)
    if self._zLink and HandleModifiedItemClick then HandleModifiedItemClick(self._zLink) end
end

-- BL.StyleRow(row): the sizes and fonts as set now. Cheap; on a change,
-- never per frame.
function BL.StyleRow(row)
    local size = BL.IconSize()
    local icons = Part("icons")
    row:SetHeight(size)
    row._zBox:SetSize(size, size)
    row._zBox:SetShown(icons)
    row._zGlow:SetSize(size * 1.75, size * 1.75)
    if row._zIconsOn ~= icons then
        -- (without icons the name starts at the row's own edge)
        row._zIconsOn = icons
        row._zText:ClearAllPoints()
        if icons then row._zText:SetPoint("LEFT", row._zBox, "RIGHT", 6, 0)
        else row._zText:SetPoint("LEFT", row, "LEFT", 0, 0) end
        row._zText:SetPoint("RIGHT", row._zWho, "LEFT", -6, 0)
    end
    Font(row._zText, Cfg().font, BL.FONT_DEFAULTS)
    Font(row._zWho, Cfg().whoFont or Cfg().font, BL.FONT_DEFAULTS)
    row._zCount:SetShown(Part("counts"))
    if ns.HouseFont then ns.HouseFont(row._zCount, math.max(8, math.floor(size * 0.45)), "OUTLINE") end
    row:EnableMouse(BL.Tooltips() and not row._zSample)
end

-- one row: the icon in a quality edge with its glow, the stack count, the
-- item's name, and who got it at the right
function BL.MakeRow(parent)
    local row = CreateFrame("Button", nil, parent)
    local w = ns.Col and ns.Col("windowBg") or { r = 0, g = 0, b = 0 }
    local box = CreateFrame("Frame", nil, row)
    box:SetPoint("LEFT", row, "LEFT", 0, 0)
    local bbg = box:CreateTexture(nil, "BACKGROUND")
    bbg:SetAllPoints()
    bbg:SetColorTexture(w.r, w.g, w.b, 0.9)
    if ns.AddPixelBorder then ns.AddPixelBorder(box) end
    local icon = box:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    if ZacUI and ZacUI.Look and ZacUI.Look.CropIcon then ZacUI.Look.CropIcon(icon) else icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
    row._zBox, row._zIcon = box, icon
    -- the glow an epic arrives with (and a row flashes with when it is won)
    local glow = CreateFrame("Frame", nil, row)
    glow:SetPoint("CENTER", box, "CENTER", 0, 0)
    glow:SetFrameLevel(box:GetFrameLevel() + 2)
    local gt = glow:CreateTexture(nil, "OVERLAY")
    gt:SetAllPoints()
    gt:SetTexture(GLOW_TEX)
    gt:SetBlendMode("ADD")
    glow._zTex = gt
    glow:SetAlpha(0)
    row._zGlow = glow
    local count = box:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -1, 1)
    row._zCount = count
    local who = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    who:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    who:SetJustifyH("RIGHT")
    who:SetWordWrap(false)
    row._zWho = who
    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", box, "RIGHT", 6, 0)
    fs:SetPoint("RIGHT", who, "LEFT", -6, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    row._zText = fs
    row._zIconsOn = true
    row:SetScript("OnEnter", Row_OnEnter)
    row:SetScript("OnLeave", Row_OnLeave)
    row:SetScript("OnClick", Row_OnClick)
    BL.StyleRow(row)
    return row
end

function BL.Fill(row, e)
    row._zLink = e.link
    row._zIcon:SetTexture(e.icon or ICON_UNKNOWN)
    local r, g, b = ns.QualityRGB(e.quality)
    row._zText:SetText(e.name or "?")
    if Part("nameQuality") then
        row._zText:SetTextColor(r, g, b, 1)
    else
        local t = ns.Col("text")
        row._zText:SetTextColor(t.r, t.g, t.b, 1)
    end
    if ns.TintBorder then
        if Part("iconEdge") then
            ns.TintBorder(row._zBox, r, g, b, 1)
        else
            local br, bgc, bb = ColorOr("borderColor", "ui", "border")
            ns.TintBorder(row._zBox, br, bgc, bb, 1)
        end
    end
    row._zGlow._zTex:SetVertexColor(r, g, b, 1)
    local n = tonumber(e.count) or 1
    row._zCount:SetText(n > 1 and tostring(n) or "")
    if e.winner and BL.Winners() then
        local cr, cg, cb = WhoColor(e.class)
        row._zWho:SetText(e.winner)
        row._zWho:SetTextColor(cr, cg, cb, 1)
    else
        row._zWho:SetText("")
    end
end

-- the glow: up at once, then gone (nothing of it once it has faded)
local function Glow(row, r, g, b)
    local glow = row._zGlow
    if r then glow._zTex:SetVertexColor(r, g, b, 1) end
    local M = ns.Motion
    if not (M and M.FadeTo and (not M.Enabled or M.Enabled())) then glow:SetAlpha(0) return end
    glow:SetAlpha(0.9)
    M.FadeTo(glow, 0, { style = "fade", duration = 0.9, easing = "easeOutQuad" })
end

-- the colours and fonts of a card (the live one, or the page's sample)
local function PaintCard(c)
    c = c or card
    if not c then return end
    local wr, wg, wb = ColorOr("bgColor", "ui", "windowBg")
    local a = BL.BgAlpha()
    c._zBg:SetColorTexture(wr, wg, wb, a)
    if ns.TintBorder then
        local br, bgc, bb = ColorOr("borderColor", "ui", "border")
        ns.TintBorder(c, br, bgc, bb, (Part("border") and a > 0) and math.min(1, a + 0.3) or 0)
    end
    local hr, hg, hb = ColorOr("headColor", "ui", "accent")
    c._zHead:SetTextColor(hr, hg, hb, 1)
    c._zHead:SetJustifyH(BL.HeadAlign())
    c._zHead:SetShown(Part("head"))
    c._zRule:SetColorTexture(hr, hg, hb, 0.45)
    c._zRule:SetShown(Part("head") and Part("rule"))
    local gray = GetColor("text", "gray")
    c._zMore:SetTextColor(gray.r, gray.g, gray.b, 1)
    Font(c._zHead, Cfg().headFont, BL.HEAD_FONT_DEFAULTS)
    Font(c._zMore, Cfg().font, BL.FONT_DEFAULTS)
end
BL.PaintCard = PaintCard

-- BL.MakeCard(parent): the card's own parts - ground, edge, the boss's
-- name over a thin rule, the "+2 more" line. The live card and the
-- settings page's sample are both made here.
function BL.MakeCard(parent)
    local c = CreateFrame("Frame", nil, parent)
    local bg = c:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    c._zBg = bg
    if ns.AddPixelBorder then ns.AddPixelBorder(c) end
    local PAD = Pad()
    local head = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    head:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -PAD)
    head:SetPoint("TOPRIGHT", c, "TOPRIGHT", -PAD, -PAD)
    head:SetJustifyH("LEFT")
    head:SetWordWrap(false)
    c._zHead = head
    local rule = c:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, 0)
    rule:SetPoint("TOPRIGHT", c, "TOPRIGHT", -PAD, 0)
    rule:SetHeight(1)
    if ns.Pixel and ns.Pixel.Edge then ns.Pixel.Edge(rule, "TOP", c) end
    c._zRule = rule
    local more = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    more:SetJustifyH("LEFT")
    more:Hide()
    c._zMore = more
    return c
end

-- the card hangs from its spot's top, or stands on its foot ("up")
local function PlaceCard()
    if not (holder and card) then return end
    local up = BL.GrowsUp()
    if card._zUp == up then return end
    card._zUp = up
    -- (only ever placed at rest)
    if ns.Motion and ns.Motion.Stop then ns.Motion.Stop(card) end
    card:ClearAllPoints()
    if up then
        card:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
        card:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
    else
        card:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
        card:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
    end
end

local function Holder()
    if holder then return holder end
    holder = CreateFrame("Frame", "ZacUIBossLoot", UIParent)
    holder:SetSize(BL.HolderSize())
    holder:SetFrameStrata("MEDIUM")
    holder:EnableMouse(false)
    holder:ClearAllPoints()
    holder:SetPoint("CENTER", UIParent, "CENTER", 520, 150)
    card = BL.MakeCard(holder)
    PlaceCard()
    card:SetHeight(Pad() * 2 + HeadHeight())
    card:Hide()
    PaintCard()
    if ns.ApplyMover then ns.ApplyMover(MOVER) end
    return holder
end
BL.Frame = function() return holder end
BL.Card = function() return card end
BL.Rows = function() return rows end

-- BL.Lay(c, list, entries, limit): the rows of a card placed and filled
-- (no animation); -> how many are drawn, the card's height
function BL.Lay(c, list, entries, limit)
    local headH, rowH = HeadHeight(), RowHeight()
    local PAD, ROW_GAP = Pad(), RowGap()
    c._zHead:ClearAllPoints()
    c._zHead:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -PAD)
    c._zHead:SetPoint("TOPRIGHT", c, "TOPRIGHT", -PAD, -PAD)
    c._zRule:ClearAllPoints()
    c._zRule:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -(PAD + headH - 4))
    c._zRule:SetPoint("TOPRIGHT", c, "TOPRIGHT", -PAD, -(PAD + headH - 4))
    local n = math.min(#entries, limit)
    for i = 1, n do
        local row = list[i]
        if not row then
            row = BL.MakeRow(c)
            list[i] = row
        end
        BL.StyleRow(row)
        if row._zAt ~= i or row._zRowH ~= rowH or row._zHeadH ~= headH or row._zPad ~= PAD then
            -- (a row is only ever placed while it is at rest)
            if ns.Motion and ns.Motion.Stop then ns.Motion.Stop(row) end
            row._zAt, row._zRowH, row._zHeadH, row._zPad = i, rowH, headH, PAD
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -(PAD + headH + (i - 1) * rowH))
            row:SetPoint("TOPRIGHT", c, "TOPRIGHT", -PAD, -(PAD + headH + (i - 1) * rowH))
        end
        BL.Fill(row, entries[i])
    end
    for i = n + 1, #list do list[i]:Hide() end
    local h = PAD * 2 + headH + n * rowH - (n > 0 and ROW_GAP or 0)
    local extra = #entries - n
    if extra > 0 and Part("more") then
        c._zMore:ClearAllPoints()
        c._zMore:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -(PAD + headH + n * rowH))
        c._zMore:SetText(string.format("+%d more", extra))
        c._zMore:Show()
        h = h + ROW_GAP + 12
    else
        c._zMore:Hide()
    end
    return n, h
end

local function HoldAgain()
    if holdTimer then holdTimer:Cancel() end
    holdTimer = C_Timer.NewTimer(BL.Hold(), function()
        holdTimer = nil
        if card and card:IsShown() then
            local M = ns.Motion
            if M and M.Hide then
                card._zLeaving = true
                M.Hide(card, Anim("hide"), function() card._zLeaving = nil end)
            else
                card:Hide()
            end
        end
    end)
end

-- the kill's items onto the card; new ones arrive one after another
function Render(k, replay)
    k = k or kill or last
    if not (k and #k.items > 0) then return end
    Holder()
    local M = ns.Motion
    card._zHead:SetText(k.name or "")
    local n, h = BL.Lay(card, rows, k.items, BL.MaxRows())
    card:SetHeight(h)
    local fresh = 0
    for i = 1, n do
        local e, row = k.items[i], rows[i]
        if replay or not e.shown then
            e.shown = true
            local spec = {}
            for key, v in pairs(Anim("row")) do spec[key] = v end
            spec.delay = (tonumber(spec.delay) or 0) + fresh * BL.Stagger()
            fresh = fresh + 1
            if M and M.Show then M.Show(row, spec) else row:Show() end
            if (e.quality or 0) >= 4 and Part("glow") then
                local r, g, b = ns.QualityRGB(e.quality)
                C_Timer.After(spec.delay, function() if row:IsShown() and row._zLink == e.link then Glow(row, r, g, b) end end)
            end
        else
            if not row:IsShown() then row:Show() end
        end
    end
    -- (past the limit: counted, never drawn, so nothing waits to animate)
    for i = n + 1, #k.items do k.items[i].shown = true end
    if not card:IsShown() then
        if M and M.Show then M.Show(card, Anim("show")) else card:Show() end
    elseif card._zLeaving and M and M.Show then
        -- (it was on its way out: back in, from where it is)
        M.Show(card, Anim("show"))
    end
    card._zLeaving = nil
    HoldAgain()
end
BL.Render = function(k, replay) return Render(k, replay) end

-- someone got an entry: its row says so, with a flash in their colour
local function Won(entry)
    local k = kill or last
    if not k then return end
    Render(k)
    for i, e in ipairs(k.items) do
        if e == entry and rows[i] and rows[i]:IsShown() then
            if Part("flash") then Glow(rows[i], WhoColor(e.class)) end
            break
        end
    end
end

-- nothing on the card (a new kill, the part switched off)
function BL.ClearCard()
    if holdTimer then holdTimer:Cancel() holdTimer = nil end
    local M = ns.Motion
    for _, row in ipairs(rows) do
        if M and M.Stop then M.Stop(row) end
        row:Hide()
        row._zLink = nil
    end
    if card then
        if M and M.Stop then M.Stop(card) end
        card._zLeaving = nil
        card:Hide()
    end
end
-- the last boss's items once more (the page's button)
function BL.ShowAgain()
    local k = kill or last
    if not (k and #k.items > 0) then return false end
    for _, e in ipairs(k.items) do e.shown = nil end
    BL.ClearCard()
    Render(k, true)
    return true
end

-- ============================================================
-- READING THE GAME
-- ============================================================
-- "<name> receives loot: <item>." in the client's own words
local linePats
local function BuildPatterns()
    linePats = {}
    local Pat = QoL.LootFeed and QoL.LootFeed.Pat
    if not Pat then return end
    -- the "multiple" forms first: "x3" would otherwise end up in the name
    for _, g in ipairs({ { "LOOT_ITEM_MULTIPLE" }, { "LOOT_ITEM" },
                         { "LOOT_ITEM_SELF_MULTIPLE", true }, { "LOOT_ITEM_SELF", true } }) do
        local p = Pat(_G[g[1]])
        if p then linePats[#linePats + 1] = { p, g[2] } end
    end
end
-- a loot line -> link, count, who (short name), or nil
function BL.ParseLine(msg)
    if type(msg) ~= "string" or Secret(msg) then return nil end
    if not linePats then BuildPatterns() end
    for _, lp in ipairs(linePats) do
        local a, b, c = msg:match(lp[1])
        if a then
            if lp[2] then
                -- yours: item, count
                if a:find("|Hitem:", 1, true) then return a, tonumber(b) or 1, UnitName("player") end
            else
                -- (a localised line may name the item first)
                local who, link, count = a, b, c
                if type(a) == "string" and a:find("|Hitem:", 1, true) then who, link = b, a end
                if type(link) == "string" and link:find("|Hitem:", 1, true) and type(who) == "string" then
                    return link, tonumber(count) or 1, (ns.ShortName and ns.ShortName(who)) or who
                end
            end
        end
    end
    return nil
end

local function MasterLooterUnit()
    local ok, method, partyMaster, raidMaster
    if C_PartyInfo and C_PartyInfo.GetLootMethod then
        ok, method, partyMaster, raidMaster = pcall(C_PartyInfo.GetLootMethod)
    elseif GetLootMethod then
        ok, method, partyMaster, raidMaster = pcall(GetLootMethod)
    end
    if not ok then return nil end
    local master = method == "master"
        or (type(Enum) == "table" and Enum.LootMethod and method ~= nil and method == Enum.LootMethod.Masterlooter)
    if not master then return nil end
    if IsInRaid and IsInRaid() and type(raidMaster) == "number" and raidMaster > 0 then return "raid" .. raidMaster end
    if partyMaster == 0 then return "player" end
    if type(partyMaster) == "number" and partyMaster > 0 then return "party" .. partyMaster end
    return nil
end
-- may this sender's links be taken as "what dropped"?
function BL.MayAnnounce(sender)
    if type(sender) ~= "string" or Secret(sender) then return false end
    local short = (ns.ShortName and ns.ShortName(sender)) or sender
    local R = ns.Roster
    local unit = R and (R.UnitByName(short) or R.UnitByName(sender)) or nil
    if not unit then return false end
    if UnitIsGroupLeader and UnitIsGroupLeader(unit) then return true end
    if UnitIsGroupAssistant and UnitIsGroupAssistant(unit) then return true end
    local ml = MasterLooterUnit()
    return ml ~= nil and UnitIsUnit and UnitIsUnit(ml, unit) and true or false
end

-- the dead boss you have targeted, where the game sends no encounter
local function TargetBoss()
    if not (UnitExists and UnitExists("target") and UnitIsDead and UnitIsDead("target")) then return nil end
    local c = UnitClassification and UnitClassification("target")
    local lvl = UnitLevel and UnitLevel("target")
    if c == "worldboss" or lvl == -1 then
        local name = UnitName("target")
        if type(name) == "string" and not Secret(name) then return name, UnitGUID("target") end
    end
    return nil
end

-- your loot window, read while it is open: { { link, count } ... } and
-- whether one slot comes off the targeted boss
local function ReadLootWindow()
    local list, offTarget = {}, false
    local n = GetNumLootItems and GetNumLootItems() or 0
    local _, bossGUID = TargetBoss()
    for slot = 1, n do
        local link = GetLootSlotLink and GetLootSlotLink(slot)
        if type(link) == "string" and not Secret(link) and link:find("|Hitem:", 1, true) then
            local _, _, quantity = GetLootSlotInfo(slot)
            list[#list + 1] = { link, tonumber(quantity) or 1 }
        end
        if bossGUID and GetLootSourceInfo then
            local ok, guid = pcall(GetLootSourceInfo, slot)
            if ok and guid == bossGUID then offTarget = true end
        end
    end
    return list, offTarget
end

local queue, draining = {}, false
local function Drain()
    draining = false
    local list = queue
    queue = {}
    local changed, won = false, nil
    for _, q in ipairs(list) do
        local what = q[1]
        if what == "window" then
            -- no kill being listened to: a world boss looted starts one
            if not kill and q[3] and BL.On() then BL.Begin(q[3]) end
            if kill then
                -- a slot is a new item only past the ones already listed
                -- with that id: the same corpse looked at twice, or an
                -- item the looter linked first, lists nothing twice (two
                -- of a token in one window are still two)
                local have, seen = {}, {}
                for _, e in ipairs(kill.items) do have[e.id] = (have[e.id] or 0) + 1 end
                for _, it in ipairs(q[2]) do
                    local id = ItemID(it[1])
                    if id then
                        seen[id] = (seen[id] or 0) + 1
                        if seen[id] > (have[id] or 0) then
                            local _, ch = BL.Note("window", it[1], it[2])
                            changed = changed or ch
                        end
                    end
                end
            end
        elseif what == "roll" then
            local _, ch = BL.Note("roll", q[2], q[3], nil, nil, q[4])
            changed = changed or ch
        elseif what == "line" then
            local link, count, who = BL.ParseLine(q[2])
            if link then
                local class = who and ns.Roster and ns.Roster.Class(who) or nil
                local e, ch = BL.Note("line", link, count, who, class)
                if ch then
                    changed = true
                    if e and e.winner then won = e end
                end
            end
        elseif what == "got" then
            local who = q[4]
            if type(who) == "string" and not Secret(who) then who = (ns.ShortName and ns.ShortName(who)) or who else who = nil end
            local e, ch = BL.Note("got", q[2], q[3], who, q[5])
            if ch then
                changed = true
                if e and e.winner then won = e end
            end
        elseif what == "chat" then
            if BL.Links() and type(q[2]) == "string" and not Secret(q[2]) and BL.MayAnnounce(q[3]) then
                EachLink(q[2], function(link)
                    local _, ch = BL.Note("link", link, 1)
                    changed = changed or ch
                end)
            end
        end
    end
    if changed and kill then
        if won then Won(won) else Render(kill) end
    end
end
BL.Drain = Drain

local function Queue(...)
    queue[#queue + 1] = { ... }
    if #queue > 60 then table.remove(queue, 1) end
    if not draining then
        draining = true
        C_Timer.After(0, Drain)
    end
end

-- ============================================================
-- EVENTS
-- ============================================================
local ev
local WINDOW_EVENTS = { "CHAT_MSG_LOOT", "START_LOOT_ROLL", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
                        "CHAT_MSG_RAID_WARNING", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "ENCOUNTER_LOOT_RECEIVED" }
local listening = false

local function OnEvent(_, event, a, b, c, d, e, f)
    if event == "LOOT_OPENED" then
        -- (the slots are gone when the window closes: read now, drawn next frame)
        local ok, list, offTarget = pcall(ReadLootWindow)
        if not ok then return end
        local bossName
        if not kill and offTarget then bossName = TargetBoss() end
        -- a kill's own window is taken once; a second corpse within the
        -- time is taken too (a boss with two bodies, a chest)
        if kill or bossName then Queue("window", list, bossName) end
    elseif event == "START_LOOT_ROLL" then
        local rollID = a
        local link = GetLootRollItemLink and GetLootRollItemLink(rollID)
        if type(link) == "string" and not Secret(link) then
            local count = 1
            if GetLootRollItemInfo then
                local ok, _, _, n = pcall(GetLootRollItemInfo, rollID)
                if ok and tonumber(n) then count = tonumber(n) end
            end
            Queue("roll", link, count, rollID)
        end
    elseif event == "CHAT_MSG_LOOT" then
        Queue("line", a)
    elseif event == "ENCOUNTER_LOOT_RECEIVED" then
        -- encounterID, itemID, itemLink, quantity, playerName, className
        if type(c) == "string" and not Secret(c) then Queue("got", c, d, e, f) end
    else
        -- group chat: text, sender
        Queue("chat", a, b)
    end
end

function BL.Listen()
    if listening or not ev then return end
    for _, e in ipairs(WINDOW_EVENTS) do pcall(ev.RegisterEvent, ev, e) end
    listening = true
end
function StopListening()
    if not (listening and ev) then return end
    for _, e in ipairs(WINDOW_EVENTS) do pcall(ev.UnregisterEvent, ev, e) end
    listening = false
end
BL.Listening = function() return listening end

local function OnEncounter(event, id, name, difficulty, size, success)
    if event == "start" then
        -- a new pull: the last boss's card goes, nothing is listened to
        CloseWindow()
        BL.ClearCard()
    elseif event == "end" and success == 1 then
        if not BL.On() then return end
        local inInstance, kind = false, nil
        if IsInInstance then inInstance, kind = IsInInstance() end
        if kind == "party" and not BL.InDungeons() then return end
        if kind ~= "party" and not BL.InRaids() then return end
        if type(name) ~= "string" or Secret(name) then name = nil end
        BL.Begin(name)
    end
end
BL.OnEncounter = OnEncounter

local registered = false
function BL.Apply()
    local on = BL.On()
    if on and not registered then
        if not ev then
            ev = CreateFrame("Frame")
            ev:SetScript("OnEvent", OnEvent)
        end
        pcall(ev.RegisterEvent, ev, "LOOT_OPENED")
        if ns.Encounter and ns.Encounter.On then ns.Encounter.On("bossloot", OnEncounter) end
        registered = true
    elseif not on and registered then
        CloseWindow()
        ev:UnregisterAllEvents()
        listening = false
        if ns.Encounter and ns.Encounter.On then ns.Encounter.On("bossloot", nil) end
        registered = false
        BL.ClearCard()
    end
    -- (switched on = there is a frame, even while nothing calls for it:
    -- Edit Mode places what exists and reads a missing frame as "off")
    if on then Holder() end
    if holder then
        holder:SetSize(BL.HolderSize())
        PlaceCard()
        PaintCard()
        local k = kill or last
        if card:IsShown() and k then
            local _, h = BL.Lay(card, rows, k.items, BL.MaxRows())
            card:SetHeight(h)
        else
            for _, row in ipairs(rows) do BL.StyleRow(row) end
        end
    end
end
BL.Registered = function() return registered end

-- ============================================================
-- THE TEST BUTTON: a sample kill, its items one after another, then who
-- got them
-- ============================================================
BL.SAMPLE_BOSS = "Ragnaros"
BL.SAMPLES = {
    { link = "|cffff8000|Hitem:17204::::::::60:::::::|h[Eye of Sulfuras]|h|r", q = 5 },
    { link = "|cffa335ee|Hitem:17076::::::::60:::::::|h[Bonereaver's Edge]|h|r", q = 4, who = "Aldric", class = "WARRIOR" },
    { link = "|cffa335ee|Hitem:16922::::::::60:::::::|h[Leggings of Transcendence]|h|r", q = 4, who = "Mirelle", class = "PRIEST" },
    { link = "|cffa335ee|Hitem:17063::::::::60:::::::|h[Band of Accuria]|h|r", q = 4, who = "Tobin", class = "ROGUE" },
    { link = "|cffa335ee|Hitem:18814::::::::60:::::::|h[Choker of the Fire Lord]|h|r", q = 4 },
}
-- a sample as an entry (no game calls beyond the icon: Test works anywhere)
function BL.SampleEntry(s, withWinner)
    return { id = ItemID(s.link), link = s.link, name = ItemName(s.link), icon = ItemIcon(s.link), quality = s.q, count = 1,
             winner = withWinner and s.who or nil, class = withWinner and s.class or nil }
end
local testToken = 0
function BL.Test()
    testToken = testToken + 1
    local token = testToken
    local k = BL.Begin(BL.SAMPLE_BOSS, true)
    for i, s in ipairs(BL.SAMPLES) do
        C_Timer.After((i - 1) * 0.35, function()
            if token ~= testToken or kill ~= k then return end
            k.items[#k.items + 1] = BL.SampleEntry(s)
            Render(k)
        end)
    end
    local n = 0
    for i, s in ipairs(BL.SAMPLES) do
        if s.who then
            n = n + 1
            C_Timer.After(#BL.SAMPLES * 0.35 + 1.2 + n * 0.9, function()
                if token ~= testToken or kill ~= k then return end
                local e = k.items[i]
                if e and BL.Winners() then
                    e.winner, e.class = s.who, s.class
                    Won(e)
                end
            end)
        end
    end
    -- (a test listens to nothing and ends by itself)
    C_Timer.After(#BL.SAMPLES * 0.35 + 6, function()
        if token == testToken and kill == k then last = k kill = nil end
    end)
end

-- ============================================================
-- THE MOVER, THE SETTINGS HOOK, THE START
-- ============================================================
if Allowed() then
    if ns.RegisterMover then
        ns.RegisterMover(MOVER, "Boss loot", function() return holder end, "CENTER", 520, 150, nil, { own = true,
            -- (it follows the pieces' one scale, and has the registry's own size)
            screen = true, page = "qol", tab = "bossloot",
            -- its sizes in Edit Mode: the page's own
            sizes = function()
                local function Row(label, key, step)
                    local lim, def = BL.LIMITS[key], BL.DEFAULTS[key]
                    return { label = label, unit = "px", min = lim[1], max = lim[2], step = step, fine = 1, def = def,
                        get = function() return math.floor(Num(key) + 0.5) end,
                        set = function(v)
                            Writable()[key] = (v ~= def) and v or nil
                            BL.Apply()
                        end }
                end
                return { Row("Width", "width", 10), Row("Icon size", "iconSize", 2),
                    { label = "Text size", unit = "px", min = 8, max = 24, step = 1, fine = 1, def = BL.FONT_DEFAULTS.size,
                      get = function()
                          local f = Cfg().font
                          return (type(f) == "table" and tonumber(f.size)) or BL.FONT_DEFAULTS.size
                      end,
                      set = function(v)
                          local d = Writable()
                          local spec = {}
                          for k, val in pairs(type(d.font) == "table" and d.font or EMPTY) do spec[k] = val end
                          spec.size = v
                          d.font = spec
                          BL.Apply()
                      end } }
            end })
    end
    if ns.OnSettingsChanged then ns.OnSettingsChanged(function() if QoL.enabled then BL.Apply() end end) end
    local base = QoL.EnableAutomation
    function QoL.EnableAutomation(...)
        if base then base(...) end
        BL.Apply()
    end
end

-- ============================================================
-- THE PAGE: Quality of life > Boss loot
-- ============================================================
local function AddTab(page, tab, label, build)
    if ns.AddPageTab then return ns.AddPageTab(page, tab, label, build) end
    ns.PageTabs = ns.PageTabs or {}
    local list = ns.PageTabs[page] or {}
    ns.PageTabs[page] = list
    list[#list + 1] = { tab = tab, label = label, build = build }
end

BL.QUALITIES = {
    { value = 2, text = "Green and up" },
    { value = 3, text = "Blue and up" },
    { value = 4, text = "Purple and up" },
    { value = 5, text = "Orange only" },
}

-- THE PREVIEW STRIP: the card itself (BL.MakeCard / BL.Lay, the same
-- code as the live one) at its real size, restyled on every change.
-- Modes: with the winners named, or as it looks while the loot is still
-- on the corpse. Replay plays the arrival the way a kill does.
local function PreviewEntries(mode)
    local won = (mode ~= "drop")
    local out = {}
    for i, sm in ipairs(BL.SAMPLES) do out[i] = BL.SampleEntry(sm, won) end
    return out
end
local function PreviewSpec()
    return {
        key = "qol.bossloot", title = "Boss loot",
        width = BL.Width() + 16, height = 170,
        modes = { { id = "won", label = "With winners" }, { id = "drop", label = "Just dropped" } },
        build = function(canvas, P)
            local st = P.store
            st.card = BL.MakeCard(canvas)
            st.rows = {}
        end,
        update = function(canvas, P)
            local st = P.store
            local M = ns.Motion
            if M and M.Stop then
                M.Stop(st.card)
                for _, row in ipairs(st.rows) do M.Stop(row) end
            end
            local entries = PreviewEntries(P.mode)
            st.entries = entries
            st.card:ClearAllPoints()
            st.card:SetPoint("TOP", canvas, "TOP", 0, -8)
            st.card:SetWidth(BL.Width())
            PaintCard(st.card)
            st.card._zHead:SetText(BL.SAMPLE_BOSS)
            local n, h = BL.Lay(st.card, st.rows, entries, math.min(#entries, BL.MaxRows()))
            for i = 1, n do
                local row = st.rows[i]
                row._zSample = true
                row:EnableMouse(false)
                row:SetAlpha(1)
                row:Show()
            end
            st.card:SetHeight(h)
            st.card:SetAlpha(1)
            st.card:Show()
            if P.Resize then P.Resize(BL.Width() + 16, h + 16) end
        end,
        replay = function(canvas, P)
            local st = P.store
            local M = ns.Motion
            if not (M and M.Show and st.card and st.entries) then return end
            M.Stop(st.card)
            st.card:Hide()
            M.Show(st.card, Anim("show"))
            local shown = math.min(#st.entries, BL.MaxRows())
            for i = 1, shown do
                local row, e = st.rows[i], st.entries[i]
                if row then
                    M.Stop(row)
                    row:Hide()
                    local spec = {}
                    for k, v in pairs(Anim("row")) do spec[k] = v end
                    spec.delay = (tonumber(spec.delay) or 0) + (i - 1) * BL.Stagger()
                    M.Show(row, spec)
                    if (e.quality or 0) >= 4 and Part("glow") then
                        local r, g, b = ns.QualityRGB(e.quality)
                        C_Timer.After(spec.delay, function() if row:IsShown() then Glow(row, r, g, b) end end)
                    end
                    if e.winner and Part("flash") and BL.Winners() then
                        C_Timer.After(spec.delay + 1.2, function()
                            if row:IsShown() then Glow(row, WhoColor(e.class)) end
                        end)
                    end
                end
            end
        end,
    }
end
BL.PreviewSpec = PreviewSpec

AddTab("qol", "bossloot", "Boss loot", function(L)
    if not Allowed() then return end
    local UI = ns.UI
    local Kit = ns.CorePageKit
    local function Live() if QoL.enabled then BL.Apply() end end
    local function View() return view end
    if L.Preview then L:Preview(PreviewSpec()) end

    -- rows that save only what differs from what ships
    local function Px(v) return v .. " px" end
    local function Secs(v) return v .. " s" end
    local function SliderOf(label, key, step, fmt, tip)
        local lim, def = BL.LIMITS[key], BL.DEFAULTS[key]
        return UI.Slider(L.current, { width = 220, min = lim[1], max = lim[2], step = step, label = label,
            value = Num(key), format = fmt, tooltip = tip,
            onChange = function(v)
                Writable()[key] = (v ~= def) and v or nil
                Live()
            end })
    end
    local function SliderRow(label, key, step, fmt, tip) L:Row(SliderOf(label, key, step, fmt, tip), 40) end
    local function SwitchOf(label, key, shippedOn, tip, rebuild)
        local now = Cfg()[key]
        if shippedOn then now = now ~= false else now = now == true end
        return UI.Checkbox(L.current, label, now, function(v)
            if shippedOn then Writable()[key] = (not v) and false or nil
            else Writable()[key] = v and true or nil end
            Live()
            if rebuild and ns.RefreshConfig then ns.RefreshConfig() end
        end, tip and { tooltip = tip } or nil)
    end
    local function SwitchRow(label, key, shippedOn, tip, rebuild) L:Row(SwitchOf(label, key, shippedOn, tip, rebuild), 17) end
    local function ChoiceRow(label, key, items, def)
        local function Now() local v = Cfg()[key] if v == nil then v = def end return v end
        local f = UI.Field(L.current, label, function(h)
            return UI.Dropdown(h, { width = 200,
                items = function() return items end,
                selectedValue = Now,
                selected = function()
                    for _, it in ipairs(items) do if it.value == Now() then return it.text end end
                    return items[1].text
                end,
                onSelect = function(v)
                    Writable()[key] = (v ~= def) and v or nil
                    Live()
                end })
        end, { width = 200 })
        L:Row(f, 30)
    end
    local function ColorRow(label, key, cat, name)
        if not (Kit and Kit.Color) then return end
        Kit.Color(L, label, View, key, function() return BL.ColorOr(key, cat, name) end, { after = Live })
    end

    -- ---------------- what it does ----------------
    L:Card("Boss loot")
    local on = UI.Checkbox(L.current, "Show what a boss dropped on a small card", Cfg().enabled == true, function(v)
        Writable().enabled = v or nil
        Live()
        if ns.RefreshConfig then ns.RefreshConfig() end
    end, { tooltip = "After a boss dies: the items it dropped, as they become known - from your own loot window, "
        .. "loot rolls, the loot lines in chat, and what the master looter links - and who got each one. "
        .. "The card fades away by itself and the next pull puts it away." })
    L:Row(on, 17)
    local kids = {}
    kids[#kids + 1] = SliderOf("The card stays", "hold", 1, Secs, "How long the card stays after the last thing it learned.")
    kids[#kids + 1] = SliderOf("Keep listening after the kill", "collect", 30,
        function(v) return string.format("%d min %02d s", math.floor(v / 60), v % 60) end,
        "How long after the kill loot lines, rolls and links still count as that boss's loot.")
    kids[#kids + 1] = SliderOf("Items at most", "maxRows", 1, nil, "More than this are counted on one line under the list.")
    kids[#kids + 1] = UI.Field(L.current, "Items shown", function(h)
        return UI.Dropdown(h, { width = 200,
            items = function() return BL.QUALITIES end,
            selectedValue = function() return BL.MinQuality() end,
            selected = function()
                for _, it in ipairs(BL.QUALITIES) do if it.value == BL.MinQuality() then return it.text end end
                return BL.QUALITIES[2].text
            end,
            onSelect = function(v) Writable().quality = (v ~= BL.DEFAULTS.quality) and v or nil end })
    end, { width = 200 })
    kids[#kids + 1] = SwitchOf("In raids", "raids", true)
    kids[#kids + 1] = SwitchOf("In dungeons", "dungeons", true)
    kids[#kids + 1] = SwitchOf("Show who got each item", "winners", true,
        "The winner's name beside the item once the game says who received it.")
    kids[#kids + 1] = SwitchOf("Count items the master looter links", "links", true,
        "Under master loot only the looter sees the corpse. Item links the master looter, the raid leader or an "
        .. "assistant puts in raid or party chat after the kill are listed as drops.")
    kids[#kids + 1] = SwitchOf("Item tooltips under the mouse", "tooltips", false,
        "On: a row shows its item's tooltip under the mouse and Shift-click links it. Off, the card never takes a click.")
    kids[#kids + 1] = SwitchOf("A \"+2 more\" line when there are too many", "more", true)
    kids[#kids + 1] = UI.Button(L.current, "Test", { width = 80,
        tooltip = "Plays a sample kill on screen: five items arrive, then three of them are won.",
        onClick = function() BL.Test() end })
    kids[#kids + 1] = UI.Button(L.current, "Last boss again", { width = 130,
        tooltip = "Shows the last boss's items once more.",
        onClick = function() BL.ShowAgain() end })
    L:Dependent(kids, Cfg().enabled == true, 1, nil, "Show what a boss dropped on a small card")
    L:EndCard()

    -- ---------------- the card ----------------
    L:Card("The card")
    SliderRow("Width", "width", 5, Px)
    SliderRow("Space inside its edge", "pad", 1, Px)
    L:Row(UI.Slider(L.current, { width = 220, min = 0, max = 100, step = 5, label = "Background",
        value = math.floor(BL.BgAlpha() * 100 + 0.5), format = function(v) return v .. "%" end,
        tooltip = "How solid the card's ground is. 0% is the items alone.",
        onChange = function(v)
            Writable().bgAlpha = (v ~= 60) and (v / 100) or nil
            Live()
        end }), 40)
    ColorRow("Background colour", "bgColor", "ui", "windowBg")
    SwitchRow("A border", "border", true, nil, true)
    if Part("border") then ColorRow("Border colour", "borderColor", "ui", "border") end
    ChoiceRow("With more items the card grows", "grow", BL.GROWS, "down")
    L:EndCard()

    -- ---------------- the boss's name ----------------
    L:Card("Boss name")
    SwitchRow("Show the boss's name", "head", true, nil, true)
    if Part("head") then
        ChoiceRow("It sits", "headAlign", BL.ALIGNS, "LEFT")
        ColorRow("Colour", "headColor", "ui", "accent")
        SwitchRow("A thin line under it", "rule", true)
        if Kit and Kit.Font then
            Kit.Font(L, "Font", View, "headFont", BL.HEAD_FONT_DEFAULTS, { sample = BL.SAMPLE_BOSS, after = Live })
        end
    end
    L:EndCard()

    -- ---------------- the items ----------------
    L:Card("Items")
    SwitchRow("Item icons", "icons", true, nil, true)
    SliderRow("Icon size", "iconSize", 1, Px, "Also how tall a row is.")
    SliderRow("Space between rows", "rowGap", 1, Px)
    if Part("icons") then
        SwitchRow("Icon edge in the item's quality colour", "iconEdge", true)
        SwitchRow("Stack counts on the icons", "counts", true)
    end
    SwitchRow("Item names in their quality colour", "nameQuality", true)
    SwitchRow("An epic arrives with a glow", "glow", true)
    if Kit and Kit.Font then
        Kit.Font(L, "Font", View, "font", BL.FONT_DEFAULTS, { sample = "Bonereaver's Edge", after = Live })
    end
    L:EndCard()

    -- ---------------- who got it ----------------
    L:Card("Winners")
    SwitchRow("Names in their class colour", "whoClass", true, nil, true)
    if not Part("whoClass") and Kit and Kit.Color then
        Kit.Color(L, "Colour", View, "whoColor", function() return 0.85, 0.85, 0.85, 1 end, { after = Live })
    end
    SwitchRow("The row flashes when someone wins it", "flash", true)
    if Kit and Kit.Font then
        Kit.Font(L, "Font", View, "whoFont", BL.FONT_DEFAULTS,
            { sample = "Aldric", after = Live, defaultLabel = "The item font" })
    end
    L:EndCard()

    -- ---------------- motion and place ----------------
    L:Card("Motion")
    if Kit and Kit.Anim then
        Kit.Anim(L, "When the card appears", View, "showAnim", { "none", "fade", "slide", "pop" }, nil,
            { default = BL.ANIM.show })
        Kit.Anim(L, "When each item arrives", View, "rowAnim", { "none", "fade", "slide", "pop" }, nil,
            { default = BL.ANIM.row })
        Kit.Anim(L, "When the card leaves", View, "hideAnim", { "none", "fade", "slide", "pop" }, nil,
            { default = BL.ANIM.hide })
    end
    L:Row(UI.Slider(L.current, { width = 220, min = 0, max = 500, step = 10, label = "Time between items",
        value = math.floor(BL.Stagger() * 1000 + 0.5), format = function(v) return v .. " ms" end,
        tooltip = "When several items become known at once, each arrives this long after the one before.",
        onChange = function(v)
            Writable().stagger = (v ~= 70) and (v / 1000) or nil
            Live()
        end }), 40)
    L:Desc("Replay on the preview plays them. Appearance > Motion's switch and speed apply.")
    L:EndCard()

    L:Card("Position")
    if Kit and Kit.Mover and ns.MOVERS and ns.MOVERS[MOVER] then Kit.Mover(L, MOVER, "the card") end
    L:Desc("Its place and scale are set in Edit Mode; its box there also has the width, icon and text sizes.")
    L:EndCard()
end)

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("qol", "boss loot drops dropped items who got won winner master looter roll card")
end
