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

-- TWO LOOKS (2026-11-20, Zac: "improve the loot frames that come up to
-- need/greed/pass just make them look better overall"). lootRoll.style:
--   nil / "compact"  the bars as they always were: 180 x 16, the timer
--                    filling the body, the name on it;
--   "card"           a taller card: 250 x 30, the item's name over its
--                    bind tag and the time left, a wash of the item's
--                    quality colour from the icon, the timer a thin strip
--                    along the foot, bigger roll buttons on plates, the
--                    card fading in and its icon popping.
-- A new install starts on the cards (Boot_Events writes the style once);
-- an existing one keeps its bars until Screen > Loot rolls > Look says
-- otherwise. Everything else on that page works on both: under a look,
-- "nothing saved" is that look's own numbers (LR.Defaults).
LR.STYLES = {
    { id = "compact", label = "Compact bars" },
    { id = "card",    label = "Cards" },
}
LR.CARD = { width = 250, height = 30, gap = 6, strip = 3 }
LR.CARD_ANIM = {
    show = { style = "fade", duration = 0.20, delay = 0, easing = "easeOutQuad" },
    icon = { style = "pop", duration = 0.30, delay = 0.03, easing = "easeOutBack" },
    hide = { style = "fade", duration = 0.15, delay = 0, easing = "easeOutQuad" },
}
-- (a bar's own: none, as always - what its pickers show until one is set)
local NO_ANIM = { style = "none", duration = 0.2, delay = 0, easing = "easeOutQuad" }
LR.BAR_ANIM = { show = NO_ANIM, icon = NO_ANIM, hide = NO_ANIM }
function LR.IsCard(cfg)
    cfg = cfg or LR.Cfg()
    return cfg.style == "card"
end
function LR.Defaults(cfg) return LR.IsCard(cfg) and LR.CARD or LR.D end
-- EVERY PART IS A SETTING (2026-11-20, Zac: "fully customizable"). A look
-- is only what its parts are with nothing saved; each can be set on
-- either look (Screen > Loot rolls > Look):
--   timer       "fill" the whole body / "strip" along the foot / "none"
--   strip       the strip's height
--   timerAlpha  how strong the timer's colour is
--   wash        the quality colour washing in from the icon, washAlpha
--   plates      a faint plate behind each roll button
--   buttonGap   between the roll buttons (buttonSize: nil = from the height)
--   edge        "quality" / "dim" (quality, quieter) / "plain" (ZacUI's
--               border) / "none"
--   bgAlpha     the ground
-- and, the same on both: spark (on), nameQuality (the name in its quality
-- colour, on).
LR.LOOKS = {
    compact = { timer = "fill", strip = 3, timerAlpha = 0.45, wash = false, washAlpha = 0.30, plates = false,
                buttonGap = 3, edge = "quality", bgAlpha = 0.92 },
    card    = { timer = "strip", strip = 3, timerAlpha = 0.95, wash = true, washAlpha = 0.30, plates = true,
                buttonGap = 6, edge = "dim", bgAlpha = 0.92 },
}
LR.TIMERS = { { value = "fill", text = "Fills the bar" }, { value = "strip", text = "A strip along the foot" },
              { value = "none", text = "Hidden" } }
LR.EDGES = { { value = "quality", text = "The item's quality colour" }, { value = "dim", text = "Quality colour, quieter" },
             { value = "plain", text = "ZacUI's border" }, { value = "none", text = "None" } }
function LR.LookDefaults(cfg) return LR.IsCard(cfg) and LR.LOOKS.card or LR.LOOKS.compact end
function LR.Part(cfg, key)
    cfg = cfg or LR.Cfg()
    local v = cfg[key]
    if v == nil then v = LR.LookDefaults(cfg)[key] end
    return v
end
-- the roll buttons' size: set, or from the bar's height (as always)
function LR.AutoButton(cfg)
    local H = cfg.height
    if H == nil then H = LR.Defaults(cfg).height end
    return LR.IsCard(cfg) and math.max(16, H - 10) or math.max(14, H - 4)
end
function LR.ButtonSize(cfg)
    cfg = cfg or LR.Cfg()
    return tonumber(cfg.buttonSize) or LR.AutoButton(cfg)
end
-- an animation: the one picked, else the look's own (a bar has none)
function LR.AnimOf(cfg, key)
    cfg = cfg or LR.Cfg()
    local a = cfg[key .. "Anim"]
    if type(a) == "table" then return a end
    return LR.IsCard(cfg) and LR.CARD_ANIM[key] or nil
end
-- the time left is written on a card unless switched off, on a bar only
-- when switched on (as always)
function LR.ShowsTime(cfg)
    cfg = cfg or LR.Cfg()
    if LR.IsCard(cfg) then return cfg.showTime ~= false end
    return cfg.showTime and true or false
end
local function V(cfg, k)
    local v = cfg[k]
    if v == nil then v = LR.Defaults(cfg)[k] end
    return v
end
LR.V = V
-- where each piece hangs with nothing saved, per look (what the page's
-- anchor pickers show as the default)
LR.ANCHORS = {
    compact = {
        name = { point = "LEFT", relPoint = "LEFT", x = 4, y = 0, label = "The bar" },
        time = { point = "RIGHT", relPoint = "LEFT", x = -4, y = 0, label = "The bind tag" },
        bind = { point = "RIGHT", relPoint = "LEFT", x = -4, y = 0, label = "The need button" },
        buttons = { point = "RIGHT", relPoint = "RIGHT", x = -3, y = 0, label = "The bar" },
        icon = { point = "RIGHT", relPoint = "LEFT", x = -2, y = 0, label = "The bar" },
        count = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = 2, y = -2, label = "Its roll button" },
        stack = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -1, y = 1, label = "The item icon" },
    },
    card = {
        -- (everything sits one up from the middle: the timer strip has the foot)
        name = { point = "LEFT", relPoint = "LEFT", x = 8, y = 7, label = "The card" },
        time = { point = "RIGHT", relPoint = "LEFT", x = -6, y = -5, label = "The need button" },
        bind = { point = "LEFT", relPoint = "LEFT", x = 8, y = -5, label = "The card" },
        buttons = { point = "RIGHT", relPoint = "RIGHT", x = -6, y = 1, label = "The card" },
        icon = { point = "RIGHT", relPoint = "LEFT", x = -3, y = 0, label = "The card" },
        count = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = 3, y = -3, label = "Its roll button" },
        stack = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -2, y = 2, label = "The item icon" },
    },
}
function LR.AnchorDefaults(cfg) return LR.IsCard(cfg) and LR.ANCHORS.card or LR.ANCHORS.compact end

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
-- THE ROLL BUTTONS' ART (2026-11-20, Zac: "should be 3d by default but
-- have the option to be 2d"). lootRoll.rollArt:
--   nil / "game"   the game's own dice, coin and pass art (3D), as always
--   "flat"         ZacUI's flat glyphs (Media\Icons\roll*64: a die, a
--                  coin, a struck ring), each in its own colour
--                  (lootRoll.flatColors.need / .greed / .pass)
LR.ARTS = { { value = "game", text = "The game's art (3D)" }, { value = "flat", text = "Flat (2D)" } }
local ICON_DIR = (ns.MEDIA or "Interface\\AddOns\\ZacUI\\Media\\") .. "Icons\\"
LR.FLAT_ART = { need = ICON_DIR .. "rollneed64", greed = ICON_DIR .. "rollgreed64", pass = ICON_DIR .. "rollpass64" }
LR.FLAT_COLORS = {
    need  = { r = 0.93, g = 0.88, b = 0.72 },
    greed = { r = 0.95, g = 0.79, b = 0.30 },
    pass  = { r = 0.88, g = 0.28, b = 0.23 },
}
LR.KINDS = { "need", "greed", "pass" }
function LR.IsFlat(cfg)
    cfg = cfg or LR.Cfg()
    return cfg.rollArt == "flat"
end
function LR.FlatColor(cfg, kind)
    cfg = cfg or LR.Cfg()
    local c = type(cfg.flatColors) == "table" and cfg.flatColors[kind]
    if type(c) ~= "table" then c = LR.FLAT_COLORS[kind] end
    return c.r or 1, c.g or 1, c.b or 1
end
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
    if self._zPlate and self._zPlate:IsShown() then self._zPlate:SetColorTexture(1, 1, 1, 0.18) end
end
local function RollButton_OnLeave(self)
    GameTooltip:Hide()
    if self._zPlate then self._zPlate:SetColorTexture(1, 1, 1, 0.07) end
end

-- a roll button's art as set: the textures change only when the pick
-- does, the flat glyph's colour on every style pass (cheap)
local function PaintRollArt(b, cfg)
    local kind = b._zKind
    local flat = LR.IsFlat(cfg)
    local want = flat and "flat" or "game"
    if b._zArt ~= want then
        b._zArt = want
        local art = ROLL_ART[kind]
        local file = flat and LR.FLAT_ART[kind] or art[1]
        b:SetNormalTexture(file)
        b:SetPushedTexture(file)
        b:SetDisabledTexture(file)
        b:SetHighlightTexture(file)
        for _, tex in ipairs({ b:GetNormalTexture(), b:GetPushedTexture(),
                               b:GetDisabledTexture(), b:GetHighlightTexture() }) do
            if tex then
                if flat then tex:SetTexCoord(0, 1, 0, 1) else tex:SetTexCoord(art[2], art[3], art[4], art[5]) end
            end
        end
        local dis = b:GetDisabledTexture()
        if dis then
            dis:SetDesaturated(true)
            dis:SetAlpha(0.25)
        end
    end
    local r, g, bl = 1, 1, 1
    if flat then r, g, bl = LR.FlatColor(cfg, kind) end
    if b._zArtR ~= r or b._zArtG ~= g or b._zArtB ~= bl then
        b._zArtR, b._zArtG, b._zArtB = r, g, bl
        for _, tex in ipairs({ b:GetNormalTexture(), b:GetPushedTexture(),
                               b:GetDisabledTexture(), b:GetHighlightTexture() }) do
            if tex and tex.SetVertexColor then tex:SetVertexColor(r, g, bl) end
        end
    end
end
LR.PaintRollArt = PaintRollArt

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
    b._zKind, b._zArt, b._zArtR, b._zArtG, b._zArtB = kind, "game", 1, 1, 1
    b:SetMotionScriptsWhileDisabled(true)
    b:SetHitRectInsets(2, 2, 2, 2)
    b.bar = bar
    b.rolltype = ROLL_ID[kind]
    b.tiptext = ROLL_TIP[kind]
    b:SetScript("OnEnter", RollButton_OnEnter)
    b:SetScript("OnLeave", RollButton_OnLeave)
    -- (the cards' look: a faint plate behind the glyph, brighter under the mouse)
    local plate = b:CreateTexture(nil, "BACKGROUND")
    plate:SetPoint("TOPLEFT", -2, 2)
    plate:SetPoint("BOTTOMRIGHT", 2, -2)
    plate:SetColorTexture(1, 1, 1, 0.07)
    plate:Hide()
    b._zPlate = plate
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
    bar._zBg = bg
    AddPixelBorder(bar)
    -- (the cards' look: the item's quality colour washing in from the icon)
    local wash = bar:CreateTexture(nil, "BACKGROUND", nil, 1)
    wash:SetPoint("TOPLEFT", 1, -1)
    wash:SetPoint("BOTTOMRIGHT", -1, 1)
    wash:SetTexture([[Interface\Buttons\WHITE8X8]])
    wash:Hide()
    bar._zWash = wash

    -- timer fills the whole body, quality-tinted on show
    local status = CreateFrame("StatusBar", nil, bar)
    status:SetPoint("TOPLEFT", 1, -1)
    status:SetPoint("BOTTOMRIGHT", -1, 1)
    status:SetStatusBarTexture((ns.Media and ns.Media.BarPath(ns.Media.HouseBar())) or TEX_NORM)
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
    ns.Look.CropIcon(button.icon)
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
        ns.ApplyFontSpec(fs, spec, { fallbackFace = t[1], size = t[2] or 12, outline = (t[3] and t[3] ~= "") and t[3] or "none",
            shadow = defaults and defaults.shadow })
        fs._zLRCustom = true
    elseif fs._zLRCustom then
        local t = bar._zTpl[key]
        -- (back in ZacUI's font, which its template wore)
        if t[1] then
            if ns.FollowFont then ns.FollowFont(fs, t[2] or 12, t[3] or "")
            else pcall(fs.SetFont, fs, t[1], t[2] or 12, t[3] or "") end
        end
        fs._zLRCustom = nil
    end
end

-- LR.Style(bar, cfg): sizes, the bar texture, every piece's place and the
-- fonts. Cheap; call it on a change, never per frame.
function LR.Style(bar, cfg)
    cfg = cfg or LR.Cfg()
    local card = LR.IsCard(cfg)
    local AD = LR.AnchorDefaults(cfg)
    local W, H = V(cfg, "width"), V(cfg, "height")
    local BTN = LR.ButtonSize(cfg)
    local A = cfg.anchors or EMPTY
    local plates = LR.Part(cfg, "plates") and true or false
    bar:SetSize(W, H)
    bar.button:SetSize(H, H)
    for _, k in ipairs({ "pass", "greed", "need" }) do
        bar[k]:SetSize(BTN, BTN)
        bar[k]._zPlate:SetShown(plates)
        PaintRollArt(bar[k], cfg)
    end
    -- the roll buttons' own spacing (3 apart on a bar, as always)
    local between = tonumber(LR.Part(cfg, "buttonGap")) or 3
    do
        local w = Col("windowBg")
        bar._zBg:SetColorTexture(w.r, w.g, w.b, tonumber(LR.Part(cfg, "bgAlpha")) or 0.92)
    end
    bar.greed:ClearAllPoints()
    bar.greed:SetPoint("RIGHT", bar.pass, "LEFT", -between, 0)
    bar.need:ClearAllPoints()
    bar.need:SetPoint("RIGHT", bar.greed, "LEFT", -between, 0)
    -- the timer: the whole body of a bar, a strip along a card's foot
    local timer = LR.Part(cfg, "timer")
    bar.status:ClearAllPoints()
    if timer == "strip" then
        bar.status:SetPoint("BOTTOMLEFT", 1, 1)
        bar.status:SetPoint("BOTTOMRIGHT", -1, 1)
        bar.status:SetHeight(math.max(1, math.min(H - 2, tonumber(LR.Part(cfg, "strip")) or 3)))
    else
        bar.status:SetPoint("TOPLEFT", 1, -1)
        bar.status:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    -- (a hidden timer still counts: only its paint goes)
    bar.status:SetAlpha(timer == "none" and 0 or 1)
    bar.status.spark:SetShown(cfg.spark ~= false)
    bar._zWash:SetShown(LR.Part(cfg, "wash") and true or false)
    bar._zLRCard = card
    if cfg.texture then
        bar.status:SetStatusBarTexture(ns.ResolveBarTexture(cfg.texture))
        bar._zLRTex = true
    elseif bar._zLRTex then
        bar.status:SetStatusBarTexture((ns.Media and ns.Media.BarPath(ns.Media.HouseBar())) or TEX_NORM)
        bar._zLRTex = nil
    end
    local to = bar._zAnchorTo
    local d
    local showTime = LR.ShowsTime(cfg)
    d = Def(bar, "icon")
    d.point, d.to, d.relPoint, d.x, d.y = "RIGHT", bar, "LEFT", AD.icon.x, 0
    ns.ApplyAnchor(bar.button, A.icon, d, to)
    d = Def(bar, "buttons")
    d.point, d.to, d.relPoint, d.x, d.y = "RIGHT", bar, "RIGHT", AD.buttons.x, AD.buttons.y
    ns.ApplyAnchor(bar.pass, A.buttons, d, to)
    if card then
        -- two lines: the name over the bind tag (left) and the time left (right)
        d = Def(bar, "bind")
        d.point, d.to, d.relPoint, d.x, d.y, d.justify = "LEFT", bar, "LEFT", AD.bind.x, AD.bind.y, "LEFT"
        ns.ApplyAnchor(bar.bind, A.bind, d, to)
        d = Def(bar, "time")
        d.point, d.to, d.relPoint, d.x, d.y, d.justify = "RIGHT", bar.need, "LEFT", AD.time.x, AD.time.y, "RIGHT"
        ns.ApplyAnchor(bar.timeText, A.time, d, to)
        bar.timeText:SetShown(showTime)
        d = Def(bar, "name")
        d.point, d.to, d.relPoint, d.x, d.y, d.justify = "LEFT", bar, "LEFT", AD.name.x, AD.name.y, "LEFT"
        d.point2, d.to2, d.relPoint2, d.x2, d.y2 = "RIGHT", bar.need, "LEFT", -6, AD.name.y
        local _, two = ns.ApplyAnchor(bar.name, A.name, d, to)
        if two == false then bar.name:SetWidth(math.max(40, W - 3 * BTN - 2 * between - 26)) end
    else
        d = Def(bar, "bind")
        d.point, d.to, d.relPoint, d.x, d.y, d.justify = "RIGHT", bar.need, "LEFT", -4, 0, nil
        ns.ApplyAnchor(bar.bind, A.bind, d, to)
        d = Def(bar, "time")
        d.point, d.to, d.relPoint, d.x, d.y, d.justify = "RIGHT", bar.bind, "LEFT", -4, 0, "RIGHT"
        ns.ApplyAnchor(bar.timeText, A.time, d, to)
        bar.timeText:SetShown(showTime)
        d = Def(bar, "name")
        d.point, d.to, d.relPoint, d.x, d.y, d.justify = "LEFT", bar, "LEFT", 4, 0, "LEFT"
        d.point2, d.to2, d.relPoint2, d.x2, d.y2 = "RIGHT", showTime and bar.timeText or bar.bind, "LEFT", -2, 0
        local _, two = ns.ApplyAnchor(bar.name, A.name, d, to)
        if two == false then bar.name:SetWidth(math.max(40, W - 3 * BTN - 30)) end
    end
    for _, k in ipairs({ "pass", "greed", "need" }) do
        local b = bar[k]
        d = Def(bar, "count" .. k)
        d.point, d.to, d.relPoint, d.x, d.y = "BOTTOMRIGHT", b, "BOTTOMRIGHT", AD.count.x, AD.count.y
        ns.ApplyAnchor(b.count, A.count, d, to)
        b.count:SetShown(cfg.showCounts ~= false)
    end
    d = Def(bar, "stack")
    d.point, d.to, d.relPoint, d.x, d.y = "BOTTOMRIGHT", bar.button, "BOTTOMRIGHT", AD.stack.x, AD.stack.y
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
    if cfg.nameQuality == false then
        local t = Col("text")
        bar.name:SetTextColor(t.r, t.g, t.b)
    else
        bar.name:SetTextColor(r, g, b)
    end
    TintBorder(bar.button, r, g, b, 1)
    -- the edge: the quality colour (a bar), quieter (a card), ZacUI's, none
    local edge = LR.Part(cfg, "edge")
    if edge == "dim" then
        TintBorder(bar, r * 0.55, g * 0.55, b * 0.55, 1)
    elseif edge == "plain" then
        local bd = Col("border")
        TintBorder(bar, bd.r, bd.g, bd.b, 1)
    elseif edge == "none" then
        TintBorder(bar, r, g, b, 0)
    else
        TintBorder(bar, r, g, b, 1)
    end
    bar.status:SetStatusBarColor(r, g, b, tonumber(LR.Part(cfg, "timerAlpha")) or 0.45)
    if LR.Part(cfg, "wash") then
        -- the quality colour washing in from the icon
        local wash = bar._zWash
        local wa = tonumber(LR.Part(cfg, "washAlpha")) or 0.30
        local okG = CreateColor and wash.SetGradient
            and pcall(wash.SetGradient, wash, "HORIZONTAL", CreateColor(r, g, b, wa), CreateColor(r, g, b, 0))
        if not okG and wash.SetGradientAlpha then
            okG = pcall(wash.SetGradientAlpha, wash, "HORIZONTAL", r, g, b, wa, r, g, b, 0)
        end
        if not okG then wash:SetVertexColor(r, g, b, wa / 3) end
    end
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
    if not LR.ShowsTime(cfg) then return end
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
    local GAP = tonumber(lay.spacingY) or LR.Defaults(cfg).gap
    local up = lay.grow == "UP"
    holder:SetSize(W + H + 2, H)
    local M = ns.Motion
    for i, bar in ipairs(bars) do
        -- (a bar is only ever placed at rest)
        if M and M.IsPlaying and M.Stop and M.IsPlaying(bar) then M.Stop(bar) end
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
        -- (a card fades out; a bar goes at once, as always)
        local M = ns.Motion
        local out = LR.AnimOf(nil, "hide")
        if out and out.style ~= "none" and M and M.Hide and bar:IsShown() then
            bar._zLeaving = true
            M.Hide(bar, out, function() bar._zLeaving = nil end)
        else
            if M and M.Stop then M.Stop(bar) end
            bar._zLeaving = nil
            bar:Hide()
        end
    end
    -- a roll (or a test) onto a bar: shown at once, or a card's entrance
    local function ShowBar(bar)
        local M = ns.Motion
        bar._zLeaving = nil
        local show, icon = LR.AnimOf(nil, "show"), LR.AnimOf(nil, "icon")
        if M and M.Stop then M.Stop(bar) M.Stop(bar.button) end
        if show and show.style ~= "none" and M and M.Show then M.Show(bar, show) else bar:Show() end
        if icon and icon.style ~= "none" and M and M.Show then M.Show(bar.button, icon) else bar.button:Show() end
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
            -- (a card on its way out is left to finish its fade)
            if not bar._zLeaving then bar:Hide() end
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
        ShowBar(bar)

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
                ShowBar(bar)
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
                ns.Look.CropIcon(item.Icon)
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
