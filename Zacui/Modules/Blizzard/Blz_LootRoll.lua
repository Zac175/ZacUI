-- Blz_LootRoll - group loot roll bars and the Blizzard ready-check popup.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local AddPixelBorder = ns.AddPixelBorder
local AdoptQualityBorder = ns.AdoptQualityBorder
local ApplyMover = ns.ApplyMover
local Col = ns.Col
local Modules = ns.Modules
local SkinBackdrop = ns.SkinBackdrop
local SkinButton = ns.SkinButton
local SkinCloseButton = ns.SkinCloseButton
local StripFrameChrome = ns.StripFrameChrome
local StripTextures = ns.StripTextures
local TintBorder = ns.TintBorder
local TEX_NORM = ns.TEX_NORM
local ZUI = ns.ZUI

-- ============================================================
-- THE BAR: one constructor, one styler, one filler
-- ============================================================
-- The live bars and the settings page's preview strip are both built,
-- styled and filled here, so the sample on the page is exactly the bar
-- that pops up on a drop. Everything a bar shows is read from
-- ZacUIDB.lootRoll; nothing saved = the bars as they have always been
-- (180 x 16, 4 apart, the item name on the bar, no time left text).
local LR = {}
ns.LootRoll = LR

-- the numbers the bars always had
LR.D = { width = 180, height = 16, gap = 4 }
-- the time left, when it is switched on ("32s")
LR.TIME_DEFAULT = { time = "seconds" }
local EMPTY = {}
function LR.Cfg()
    local c = ZacUIDB and ZacUIDB.lootRoll
    return type(c) == "table" and c or EMPTY
end
local function V(cfg, k)
    local v = cfg[k]
    if v == nil then v = LR.D[k] end
    return v
end
LR.V = V

-- ElvUI's texcoord surgery on Blizzard's stock dice/coin/pass art:
-- crops the built-in ring so the glyph sits clean on a flat bar.
local ROLL_ART = {
    need  = { [[Interface\Buttons\UI-GroupLoot-Dice-Up]],
              0.05, 1.05, -0.05, 0.95 },
    greed = { [[Interface\Buttons\UI-GroupLoot-Coin-Up]],
              0.05, 1.05, -0.025, 0.85 },
    pass  = { [[Interface\Buttons\UI-GroupLoot-Pass-Up]],
              1.05, -0.1, 1.05, -0.1 },
}
local ROLL_ID = { need = 1, greed = 2, pass = 0 }
-- the texts a font can be picked for, and their fields on a bar
local TEXT_FIELD = { name = "name", time = "timeText", bind = "bind" }
local ROLL_TIP = { need = NEED, greed = GREED, pass = PASS }
LR.ROLL_ID = ROLL_ID

local function RollButton_OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.tiptext)
    local rolls = self.bar.rolls[self.rolltype]
    if rolls and #rolls > 0 then
        GameTooltip:AddLine(" ")
        for _, info in ipairs(rolls) do
            local cc = info[2] and RAID_CLASS_COLORS
                and RAID_CLASS_COLORS[info[2]]
            if cc then
                GameTooltip:AddLine(info[1], cc.r, cc.g, cc.b)
            else
                GameTooltip:AddLine(info[1], 1, 1, 1)
            end
        end
    end
    GameTooltip:Show()
end

local function MakeRollButton(bar, kind)
    local art = ROLL_ART[kind]
    local b = CreateFrame("Button", nil, bar)
    b:SetSize(14, 14)
    b:SetNormalTexture(art[1])
    b:SetPushedTexture(art[1])
    b:SetDisabledTexture(art[1])
    b:SetHighlightTexture(art[1])
    for _, tex in ipairs({ b:GetNormalTexture(), b:GetPushedTexture(),
                           b:GetDisabledTexture(), b:GetHighlightTexture() }) do
        if tex then tex:SetTexCoord(art[2], art[3], art[4], art[5]) end
    end
    local dis = b:GetDisabledTexture()
    if dis then
        dis:SetDesaturated(true)
        dis:SetAlpha(0.25)
    end
    b:SetMotionScriptsWhileDisabled(true)
    b:SetHitRectInsets(2, 2, 2, 2)
    b.bar = bar
    b.rolltype = ROLL_ID[kind]
    b.tiptext = ROLL_TIP[kind]
    b:SetScript("OnEnter", RollButton_OnEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- live roll count, bottom-right of the glyph
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", 2, -2)
    return b
end

-- LR.NewBar(parent, name): the bar's anatomy - background, edge, timer
-- bar and spark, item icon with its stack count, pass / greed / need with
-- their counts, the bind tag, the item name and the time left. No events,
-- no rolling, no ticking: the live module adds those to its own bars.
function LR.NewBar(parent, name)
    local bar = CreateFrame("Frame", name, parent)
    bar:SetSize(LR.D.width, LR.D.height)
    bar:Hide()

    local w = Col("windowBg")
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(w.r, w.g, w.b, 0.92)
    AddPixelBorder(bar)

    -- timer fills the whole body, quality-tinted on show
    local status = CreateFrame("StatusBar", nil, bar)
    status:SetPoint("TOPLEFT", 1, -1)
    status:SetPoint("BOTTOMRIGHT", -1, 1)
    status:SetStatusBarTexture((ns.Media and ns.Media.BarPath(TEX_NORM)) or TEX_NORM)
    status:SetFrameLevel(bar:GetFrameLevel())
    status.bar = bar
    bar.status = status

    local spark = status:CreateTexture(nil, "ARTWORK", nil, 1)
    spark:SetWidth(2)
    spark:SetPoint("TOP")
    spark:SetPoint("BOTTOM")
    spark:SetPoint("RIGHT", status:GetStatusBarTexture())
    status.spark = spark

    -- item icon, flush against the bar's left edge
    local button = CreateFrame("Button", nil, bar)
    button:SetSize(LR.D.height, LR.D.height)
    local bbg = button:CreateTexture(nil, "BACKGROUND")
    bbg:SetAllPoints()
    bbg:SetColorTexture(w.r, w.g, w.b, 0.92)
    AddPixelBorder(button)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 1, -1)
    button.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.stack = button:CreateFontString(nil, "OVERLAY",
        "NumberFontNormalSmall")
    bar.button = button

    -- pass / greed / need packed on the right, ElvUI order
    bar.pass = MakeRollButton(bar, "pass")
    bar.greed = MakeRollButton(bar, "greed")
    bar.greed:SetPoint("RIGHT", bar.pass, "LEFT", -3, 0)
    bar.need = MakeRollButton(bar, "need")
    bar.need:SetPoint("RIGHT", bar.greed, "LEFT", -3, 0)

    -- BoP/BoE tag, the time left (when shown), the item name filling the rest
    bar.bind = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    -- (bar.time is the roll's own length: the text is timeText)
    bar.timeText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.timeText:Hide()
    bar.name = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bar.name:SetJustifyH("LEFT")
    bar.name:SetWordWrap(false)

    bar.rolls = {}
    -- what each text's own font is (a font picked then cleared goes back
    -- to exactly this)
    bar._zTpl = {}
    for k, f in pairs(TEXT_FIELD) do
        bar._zTpl[k] = { bar[f]:GetFont() }
    end
    -- the parts the anchors may hang off
    local parts = { bar = bar, icon = button, name = bar.name, time = bar.timeText, bind = bar.bind,
        buttons = bar.pass, need = bar.need }
    bar._zAnchorTo = function(key) return parts[key] end
    bar._zAD = {}
    return bar
end

-- what each piece hangs off with nothing saved: exactly the SetPoints the
-- bars always had (one table per piece per bar, reused)
local function Def(bar, key)
    local d = bar._zAD[key]
    if not d then d = {} bar._zAD[key] = d end
    return d
end

local FONT_SHADOW = { shadow = true }
local function Font(bar, key, spec, defaults)
    local fs = bar[TEXT_FIELD[key]]
    if type(spec) == "table" and next(spec) then
        local t = bar._zTpl[key]
        ns.ApplyFontSpec(fs, spec, { face = t[1], size = t[2] or 12, outline = (t[3] and t[3] ~= "") and t[3] or "none",
            shadow = defaults and defaults.shadow })
        fs._zLRCustom = true
    elseif fs._zLRCustom then
        local t = bar._zTpl[key]
        if t[1] then pcall(fs.SetFont, fs, t[1], t[2] or 12, t[3] or "") end
        fs._zLRCustom = nil
    end
end

-- LR.Style(bar, cfg): sizes, the bar texture, every piece's place and the
-- fonts. Cheap; call it on a change, never per frame.
function LR.Style(bar, cfg)
    cfg = cfg or LR.Cfg()
    local W, H = V(cfg, "width"), V(cfg, "height")
    local BTN = math.max(14, H - 4)
    local A = cfg.anchors or EMPTY
    bar:SetSize(W, H)
    bar.button:SetSize(H, H)
    for _, k in ipairs({ "pass", "greed", "need" }) do bar[k]:SetSize(BTN, BTN) end
    if cfg.texture then
        bar.status:SetStatusBarTexture(ns.ResolveBarTexture(cfg.texture))
        bar._zLRTex = true
    elseif bar._zLRTex then
        bar.status:SetStatusBarTexture((ns.Media and ns.Media.BarPath(TEX_NORM)) or TEX_NORM)
        bar._zLRTex = nil
    end
    local to = bar._zAnchorTo
    local d
    d = Def(bar, "icon")
    d.point, d.to, d.relPoint, d.x, d.y = "RIGHT", bar, "LEFT", -2, 0
    ns.ApplyAnchor(bar.button, A.icon, d, to)
    d = Def(bar, "buttons")
    d.point, d.to, d.relPoint, d.x, d.y = "RIGHT", bar, "RIGHT", -3, 0
    ns.ApplyAnchor(bar.pass, A.buttons, d, to)
    d = Def(bar, "bind")
    d.point, d.to, d.relPoint, d.x, d.y = "RIGHT", bar.need, "LEFT", -4, 0
    ns.ApplyAnchor(bar.bind, A.bind, d, to)
    d = Def(bar, "time")
    d.point, d.to, d.relPoint, d.x, d.y, d.justify = "RIGHT", bar.bind, "LEFT", -4, 0, "RIGHT"
    ns.ApplyAnchor(bar.timeText, A.time, d, to)
    bar.timeText:SetShown(cfg.showTime and true or false)
    d = Def(bar, "name")
    d.point, d.to, d.relPoint, d.x, d.y, d.justify = "LEFT", bar, "LEFT", 4, 0, "LEFT"
    d.point2, d.to2, d.relPoint2, d.x2, d.y2 = "RIGHT", cfg.showTime and bar.timeText or bar.bind, "LEFT", -2, 0
    local _, two = ns.ApplyAnchor(bar.name, A.name, d, to)
    if two == false then bar.name:SetWidth(math.max(40, W - 3 * BTN - 30)) end
    for _, k in ipairs({ "pass", "greed", "need" }) do
        local b = bar[k]
        d = Def(bar, "count" .. k)
        d.point, d.to, d.relPoint, d.x, d.y = "BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2
        ns.ApplyAnchor(b.count, A.count, d, to)
        b.count:SetShown(cfg.showCounts ~= false)
    end
    d = Def(bar, "stack")
    d.point, d.to, d.relPoint, d.x, d.y = "BOTTOMRIGHT", bar.button, "BOTTOMRIGHT", -1, 1
    ns.ApplyAnchor(bar.button.stack, A.stack, d, to)
    Font(bar, "name", cfg.nameFont, FONT_SHADOW)
    Font(bar, "time", cfg.timeFont, FONT_SHADOW)
    Font(bar, "bind", cfg.bindFont, FONT_SHADOW)
    if ns.TagElement then
        ns.TagElement(bar.name, "lootroll.name")
        ns.TagElement(bar.timeText, "lootroll.time")
        ns.TagElement(bar.bind, "lootroll.bind")
        ns.TagElement(bar.button, "lootroll.icon")
        ns.TagElement(bar.button.stack, "lootroll.stack")
        for _, k in ipairs({ "pass", "greed", "need" }) do
            ns.TagElement(bar[k], "lootroll.buttons")
            ns.TagElement(bar[k].count, "lootroll.count")
        end
    end
end

local BIND_TAG = {
    [1] = { "BoP", 1, 0.3, 0.1 },
    [2] = { "BoE", 0.3, 1, 0.3 },
    [3] = { "BoU", 0.3, 1, 0.3 },
}
LR.BIND_TAG = BIND_TAG

-- LR.Fill(bar, item, cfg): the item on the bar. item = { icon, name,
-- count, quality, bind (1 BoP / 2 BoE / 3 BoU), canNeed, canGreed, time,
-- left, ms (time / left in milliseconds), need / greed / pass (roll
-- counts as text) }.
function LR.Fill(bar, item, cfg)
    cfg = cfg or LR.Cfg()
    bar.button.icon:SetTexture(item.icon)
    local count = item.count
    bar.button.stack:SetShown(count and count > 1)
    bar.button.stack:SetText(count or "")
    bar.need.count:SetText(item.need or "")
    bar.greed.count:SetText(item.greed or "")
    bar.pass.count:SetText(item.pass or "")
    bar.need:SetEnabled(item.canNeed and true or false)
    bar.greed:SetEnabled(item.canGreed and true or false)

    local qc = item.quality and ITEM_QUALITY_COLORS
        and ITEM_QUALITY_COLORS[item.quality]
    local r, g, b = 0.8, 0.8, 0.8
    if qc then r, g, b = qc.r, qc.g, qc.b end
    bar.name:SetText(item.name)
    bar.name:SetTextColor(r, g, b)
    TintBorder(bar, r, g, b, 1)
    TintBorder(bar.button, r, g, b, 1)
    bar.status:SetStatusBarColor(r, g, b, 0.45)
    bar.status.spark:SetColorTexture(r, g, b, 0.9)

    local tag = item.bind and BIND_TAG[item.bind]
    if tag and cfg.showBind ~= false then
        bar.bind:SetText(tag[1])
        bar.bind:SetTextColor(tag[2], tag[3], tag[4])
    else
        bar.bind:SetText("")
    end
    -- (a real roll's clock is in milliseconds, a made-up one in seconds)
    local total = item.time or 0
    bar.status:SetMinMaxValues(0, total)
    bar.status:SetValue(item.left or total)
    LR.PaintTime(bar, (item.left or total) / (item.ms and 1000 or 1), cfg)
end

local TIME_VALUES, TIME_KINDS = {}, { time = "time" }
-- the time left text (only while it is switched on: nothing is formatted
-- for a text nobody sees)
function LR.PaintTime(bar, left, cfg)
    cfg = cfg or LR.Cfg()
    if not cfg.showTime then return end
    local f = cfg.formats and cfg.formats.time
    local ms = math.floor((left or 0) * 1000)
    if bar._zLRTimeMs == ms and bar._zLRTimeF == f then return end
    bar._zLRTimeMs, bar._zLRTimeF = ms, f
    if f then
        -- a saved format: before / after it, letters, a template
        TIME_VALUES.time = left or 0
        bar.timeText:SetText(ns.FormatText(f, LR.TIME_DEFAULT, TIME_VALUES, TIME_KINDS, "time"))
    else
        bar.timeText:SetText(ns.FormatTime(left or 0, nil, LR.TIME_DEFAULT))
    end
end

-- LR.Place(bars, holder, cfg): the column of bars under (or over) the
-- mover's holder, as many as given.
-- (cfg.layout: grow DOWN / UP and spacingY, the gap - the standard's
-- layout shape; nothing saved = down, 4 apart)
function LR.Place(bars, holder, cfg)
    cfg = cfg or LR.Cfg()
    local lay = type(cfg.layout) == "table" and cfg.layout or EMPTY
    local W, H = V(cfg, "width"), V(cfg, "height")
    local GAP = tonumber(lay.spacingY) or LR.D.gap
    local up = lay.grow == "UP"
    holder:SetSize(W + H + 2, H)
    for i, bar in ipairs(bars) do
        bar:ClearAllPoints()
        if i == 1 then
            bar:SetPoint("TOP", holder, "TOP", (H + 2) / 2, 0)
        elseif up then
            bar:SetPoint("BOTTOM", bars[i - 1], "TOP", 0, GAP)
        else
            bar:SetPoint("TOP", bars[i - 1], "BOTTOM", 0, -GAP)
        end
    end
end

-- the made-up drops /zui testroll and the settings page show
LR.SAMPLES = {
    { name = "High Councillor's Boots", quality = 3, count = 1,
      icon = [[Interface\Icons\INV_Boots_07]], bind = 1, time = 32, need = "2", canNeed = true },
    { name = "Pristine Black Diamond", quality = 3, count = 1,
      icon = [[Interface\Icons\INV_Misc_Gem_Diamond_01]], bind = nil, time = 24, canNeed = true, canGreed = true },
    { name = "Major Healing Potion", quality = 1, count = 5,
      icon = [[Interface\Icons\INV_Potion_54]], bind = nil, time = 16, greed = "4", canNeed = true, canGreed = true },
}

-- GROUP LOOT ROLLS - the full ElvUI rebuild. Blizzard's GroupLootFrames
-- are retired outright (UIParent stops listening for START_LOOT_ROLL)
-- and replaced with our own bars: item icon flush left, a quality-
-- colored timer bar filling the body, need/greed/pass on the right with
-- live roll counts, item name riding the bar. Rolling itself is still
-- one Blizzard call (RollOnLoot), so a styling bug can cost pixels but
-- never a roll.
Modules.lootroll = function()
    if ZUI._lootRollBars then
        ApplyMover("lootroll")
        return
    end

    -- Sized WAY down from ElvUI's stock 328x28 by request - same
    -- anatomy, compact bar (LR.D; Screen > Loot rolls changes it).
    local NUM_BARS = NUM_GROUP_LOOT_FRAMES or 4

    local GetItemInfoFn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local histGetItem = C_LootHistory and C_LootHistory.GetItem
    local histGetPlayer = C_LootHistory and C_LootHistory.GetPlayerInfo

    local bars = {}
    ZUI._lootRollBars = bars
    local cachedRolls = {}
    -- rollIDs already answered by ANYONE - our buttons, an auto-pass aura,
    -- another addon. See the RollOnLoot hook below.
    local rolled = {}
    local rollTypes = { [1] = "need", [2] = "greed", [0] = "pass" }
    local ClearBar -- forward: the roll buttons close over it in test mode

    -- The mover drags this; every bar hangs off it.
    local holder = CreateFrame("Frame", "ZacUI_LootRollHolder", UIParent)
    holder:SetSize(LR.D.width + LR.D.height + 2, LR.D.height)
    holder:SetPoint("TOP", UIParent, "TOP", 0, -220)
    ZUI._lootRollHolder = holder

    local function RollClick(self)
        if self.bar.rollID then
            RollOnLoot(self.bar.rollID, self.rolltype)
        elseif self.bar.testMode then
            -- test bars: any roll button just dismisses the bar
            ClearBar(self.bar)
        end
    end

    function ClearBar(bar)
        bar.rollID = nil
        bar.time = nil
        bar.testMode = nil
        bar.testEnds = nil
        bar.button.rollID = nil
        bar.button.link = nil
        bar._zItem = nil
        bar:Hide()
    end

    local function StatusUpdate(status, elapsed)
        local bar = status.bar
        -- test bars drain a fake clock; real bars ask the server's
        if bar.testMode then
            local left = (bar.testEnds or 0) - GetTime()
            if left <= 0 then ClearBar(bar) else status:SetValue(left) LR.PaintTime(bar, left) end
            return
        end
        if not bar.rollID then
            bar:Hide()
            return
        end
        status.elapsed = (status.elapsed or 0) + elapsed
        if status.elapsed > 0.1 then
            status.elapsed = 0
            local left = GetLootRollTimeLeft(bar.rollID)
            if left <= 0 then -- other addons may auto-pass the roll away
                ClearBar(bar)
            else
                status:SetValue(left)
                -- (the server counts in milliseconds)
                LR.PaintTime(bar, left / 1000)
            end
        end
    end

    local function ItemButton_OnEnter(self)
        if not self.rollID then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetLootRollItem(self.rollID)
        if IsShiftKeyDown() and GameTooltip_ShowCompareItem then
            GameTooltip_ShowCompareItem()
        end
    end

    -- the bar from LR.NewBar, plus what only a live bar does: tick, roll,
    -- show the item's tooltip
    local function MakeBar(i)
        local bar = LR.NewBar(UIParent, "ZacUI_LootRollBar" .. i)
        local status = bar.status
        if ns.Media then ns.Media.TrackBar(status) end
        status:SetScript("OnUpdate", StatusUpdate)

        local button = bar.button
        button:SetScript("OnEnter", ItemButton_OnEnter)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        button:SetScript("OnClick", function(self)
            if self.link and IsModifiedClick() then
                HandleModifiedItemClick(self.link)
            end
        end)
        -- Shift / Ctrl re-read the tooltip (compare, dress up); heard only
        -- while the roll is on screen, not on every modifier press all
        -- fight from a pooled bar nobody can see
        button:SetScript("OnShow", function(self) self:RegisterEvent("MODIFIER_STATE_CHANGED") end)
        button:SetScript("OnHide", function(self) self:UnregisterEvent("MODIFIER_STATE_CHANGED") end)
        button:SetScript("OnEvent", function(self)
            if self:IsMouseOver() then ItemButton_OnEnter(self) end
        end)
        for _, k in ipairs({ "pass", "greed", "need" }) do bar[k]:SetScript("OnClick", RollClick) end

        LR.Style(bar)
        bars[i] = bar
        return bar
    end

    for i = 1, NUM_BARS do MakeBar(i) end
    LR.Place(bars, holder)
    ApplyMover("lootroll")

    -- a change on Screen > Loot rolls, on the bars at once (coalesced)
    LR.ApplyLive = function()
        local cfg = LR.Cfg()
        for _, bar in ipairs(bars) do
            LR.Style(bar, cfg)
            if bar._zItem and bar:IsShown() then
                local left = bar.status:GetValue()
                bar._zItem.left = left
                LR.Fill(bar, bar._zItem, cfg)
            end
        end
        LR.Place(bars, holder, cfg)
    end

    local function GetFreeBar()
        for _, bar in ipairs(bars) do
            if not bar.rollID then return bar end
        end
    end

    local function StartRoll(rollID, rollTime)
        -- Answered before this handler ran: an auto-pass aura listening to
        -- the same START_LOOT_ROLL got there first. A bar now would sit on
        -- screen for the full roll timer offering a choice already made.
        if rolled[rollID] then return end
        local texture, name, count, quality, _, canNeed, canGreed =
            GetLootRollItemInfo(rollID)
        if not name then return end
        local bar = GetFreeBar()
        if not bar then return end

        local link = GetLootRollItemLink(rollID)
        local bindType
        if link then
            local _, _, _, _, _, _, _, _, _, _, _, _, _, bt =
                GetItemInfoFn(link)
            bindType = bt
        end

        wipe(bar.rolls)
        bar.rollID = rollID
        bar.time = rollTime
        -- (a test bar taken by a real roll is a real bar now: it runs on
        -- the server's clock, not the test's)
        bar.testMode, bar.testEnds = nil, nil

        bar.button.link = link
        bar.button.rollID = rollID
        local item = { icon = texture, name = name, count = count, quality = quality,
            bind = bindType, canNeed = canNeed, canGreed = canGreed, time = rollTime, ms = true }
        bar._zItem = item
        LR.Fill(bar, item)

        bar.status.elapsed = 1
        bar:Show()

        -- roll info that arrived before the bar existed
        local cached = cachedRolls[rollID]
        if cached then
            for rollType, rollers in pairs(cached) do
                bar.rolls[rollType] = bar.rolls[rollType] or {}
                for _, info in ipairs(rollers) do
                    bar.rolls[rollType][#bar.rolls[rollType] + 1] = info
                end
                local btn = bar[rollTypes[rollType]]
                if btn then btn.count:SetText(#bar.rolls[rollType]) end
            end
        end
    end

    local function HistoryChanged(itemIdx, playerIdx)
        if not (histGetItem and histGetPlayer) then return end
        local pname, playerClass, rollType = histGetPlayer(itemIdx, playerIdx)
        local rollID = histGetItem(itemIdx)
        if not (pname and rollType) then return end
        local info = { pname, playerClass }
        for _, bar in ipairs(bars) do
            if bar.rollID == rollID then
                bar.rolls[rollType] = bar.rolls[rollType] or {}
                bar.rolls[rollType][#bar.rolls[rollType] + 1] = info
                local btn = bar[rollTypes[rollType]]
                if btn then btn.count:SetText(#bar.rolls[rollType]) end
                return
            end
        end
        -- roll not shown yet; cache for START_LOOT_ROLL
        cachedRolls[rollID] = cachedRolls[rollID] or {}
        cachedRolls[rollID][rollType] = cachedRolls[rollID][rollType] or {}
        local c = cachedRolls[rollID][rollType]
        c[#c + 1] = info
    end

    local driver = CreateFrame("Frame")
    driver:RegisterEvent("START_LOOT_ROLL")
    driver:RegisterEvent("CANCEL_LOOT_ROLL")
    if histGetPlayer then
        driver:RegisterEvent("LOOT_HISTORY_ROLL_CHANGED")
        driver:RegisterEvent("LOOT_HISTORY_ROLL_COMPLETE")
    end
    driver:RegisterEvent("LOOT_ROLLS_COMPLETE")
    driver:SetScript("OnEvent", function(_, event, a, b)
        if event == "START_LOOT_ROLL" then
            StartRoll(a, b)
        elseif event == "CANCEL_LOOT_ROLL" then
            rolled[a] = nil
            for _, bar in ipairs(bars) do
                if bar.rollID == a then ClearBar(bar) end
            end
        elseif event == "LOOT_HISTORY_ROLL_CHANGED" then
            HistoryChanged(a, b)
        else -- LOOT_HISTORY_ROLL_COMPLETE / LOOT_ROLLS_COMPLETE
            wipe(cachedRolls)
            wipe(rolled)
        end
    end)

    -- ============================================================
    -- A ROLL MADE ANYWHERE CLOSES THE BAR
    -- ============================================================
    -- Rolling your own choice does not end the roll - it runs on for
    -- everyone else, CANCEL_LOOT_ROLL never fires for you, and
    -- GetLootRollTimeLeft keeps counting. So a pass made by an auto-roll
    -- aura left this bar up for the whole timer, still offering
    -- need/greed/pass on an item already passed, which is exactly how an
    -- auto-pass that WORKED looked like one that did not.
    --
    -- Every roll, from any caller, goes through RollOnLoot, so that is
    -- where to listen. A pass is final the moment it is sent. Need or
    -- greed on a bind-on-pickup item is not - the client asks to confirm
    -- first - so for those the bar is left until the answer is in rather
    -- than taking away the only way back if the popup is cancelled.
    hooksecurefunc("RollOnLoot", function(rollID, rollType)
        if not rollID then return end
        local final = (rollType == 0)
        if not final then
            local _, _, _, _, bop = GetLootRollItemInfo(rollID)
            final = not bop
        end
        if not final then return end
        rolled[rollID] = true
        for _, bar in ipairs(bars) do
            if bar.rollID == rollID then ClearBar(bar) end
        end
    end)
    -- the bind-on-pickup confirmation, once accepted, is the final answer
    if ConfirmLootRoll then
        hooksecurefunc("ConfirmLootRoll", function(rollID)
            if not rollID then return end
            rolled[rollID] = true
            for _, bar in ipairs(bars) do
                if bar.rollID == rollID then ClearBar(bar) end
            end
        end)
    end

    -- Retire Blizzard's popups: UIParent stops spawning GroupLootFrames.
    -- Turning the module off restores them on the next reload, because
    -- this function simply never runs.
    UIParent:UnregisterEvent("START_LOOT_ROLL")
    UIParent:UnregisterEvent("CANCEL_LOOT_ROLL")

    -- ============================================================
    -- /zui testroll - fake bars so the layout can be seen (and the
    -- mover placed) without waiting for a group drop. Buttons dismiss
    -- their bar instead of rolling; everything fades out on its own.
    -- ============================================================
    ns.LootRollTest = function()
        for i, fake in ipairs(LR.SAMPLES) do
            local bar = bars[i]
            if bar then
                wipe(bar.rolls)
                bar.rollID = nil
                bar.testMode = true
                bar.testEnds = GetTime() + fake.time

                bar.button.link = nil
                bar.button.rollID = nil
                local item = {}
                for k, v in pairs(fake) do item[k] = v end
                bar._zItem = item
                LR.Fill(bar, item)
                bar:Show()
            end
        end
    end
end

-- a change on the page reaches the live bars once, next frame
if ns.OnSettingsChanged and ns.Coalesce then
    local soon = ns.Coalesce(function() if LR.ApplyLive then LR.ApplyLive() end end)
    ns.OnSettingsChanged(function() if LR.ApplyLive then soon() end end)
end

-- READY CHECK + MASTER LOOT + ROLE POLL - the raid utility popups.
-- Strip + dark panel + our buttons only: no geometry changes, and
-- everything existence-guarded (these frames vary across shared-code
-- builds and some may not exist at all on a given client).
Modules.readycheck = function()
    if ReadyCheckFrame and not ZUI.skinned[ReadyCheckFrame] then
        ZUI.skinned[ReadyCheckFrame] = true
        StripTextures(ReadyCheckFrame)
        StripFrameChrome(ReadyCheckFrame)
        SkinBackdrop(ReadyCheckFrame, "windowBg", 0.97)
        if ReadyCheckListenerFrame then StripTextures(ReadyCheckListenerFrame) end
        if ReadyCheckFrameYesButton then SkinButton(ReadyCheckFrameYesButton) end
        if ReadyCheckFrameNoButton then SkinButton(ReadyCheckFrameNoButton) end
        if ReadyCheckFrameText then
            local tc = Col("text")
            ReadyCheckFrameText:SetTextColor(tc.r, tc.g, tc.b, 1)
        end
    end
    if MasterLooterFrame and not ZUI.skinned[MasterLooterFrame] then
        ZUI.skinned[MasterLooterFrame] = true
        StripTextures(MasterLooterFrame)
        StripFrameChrome(MasterLooterFrame)
        SkinBackdrop(MasterLooterFrame, "windowBg", 0.97)
        -- The item strip is a CHILD frame the strip above never reached:
        -- loot-toast name plate off, icon cropped, quality ring moved onto
        -- a pixel border around the icon.
        local item = MasterLooterFrame.Item
        if item then
            for _, k in ipairs({ "NameBorderLeft", "NameBorderRight", "NameBorderMid" }) do
                local t = item[k]
                if t and t.SetTexture then
                    t:SetTexture(nil)
                    t:SetAlpha(0)
                end
            end
            if item.Icon and item.Icon.SetTexCoord then
                item.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                local holder = CreateFrame("Frame", nil, item)
                holder:SetAllPoints(item.Icon)
                AddPixelBorder(holder)
                if item.IconBorder and AdoptQualityBorder then
                    AdoptQualityBorder(holder, item.IconBorder)
                end
            end
        end
        -- Player rows are pooled and created on demand per loot: restyle
        -- whatever exists after each rebuild (one flag per row).
        local function SkinRows()
            for i = 1, 40 do
                local row = MasterLooterFrame["player" .. i]
                if not row then break end
                if not row._zui_row then
                    row._zui_row = true
                    if row.Highlight then row.Highlight:SetColorTexture(1, 1, 1, 0.08) end
                end
            end
        end
        SkinRows()
        if type(MasterLooterFrame_UpdatePlayers) == "function" then
            hooksecurefunc("MasterLooterFrame_UpdatePlayers", SkinRows)
        end
    end
    if RolePollPopup and not ZUI.skinned[RolePollPopup] then
        ZUI.skinned[RolePollPopup] = true
        StripTextures(RolePollPopup)
        SkinBackdrop(RolePollPopup, "windowBg", 0.97)
        local close = RolePollPopup.CloseButton or RolePollPopupCloseButton
        if close then SkinCloseButton(close) end
    end
end

-- BUFFS / DEBUFFS (restored by request): cropped icons, 1px borders;
-- debuff borders take the dispel-type color Blizzard computes (its chunky
-- Border art hidden, live vertex color copied onto our pixel border).
-- Dual-path: classic AuraButton_Update hook, plus the modern pooled
-- BuffFrame sweep driven by a coalesced UNIT_AURA (never inline work on
-- a burst event).
-- BUFFS / DEBUFFS - ADDITIVE-ONLY, the raid-safety rebuild. Two timing
-- fixes failed to stop buffs rendering invisible at login, so timing is
-- no longer the defense: this module performs ZERO subtractive
-- operations. No SetTexCoord (cropping masked pooled textures was the
-- prime blanking suspect), no SetAlpha on Blizzard art, no hides. It may
-- ADD a 1px border and READ the dispel color to tint it - nothing else.
-- A module that only adds textures cannot make a buff or debuff
-- invisible, on any build, in any timing window. If you can't see an
-- aura with this module on, ZacUI is not the cause - by construction.
