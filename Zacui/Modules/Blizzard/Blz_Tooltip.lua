-- Blz_Tooltip - every tooltip in the game, plus the tooltip anchor mover.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local AddPixelBorder = ns.AddPixelBorder
local Col = ns.Col
local Modules = ns.Modules
local Print = ns.Print
local SkinBackdrop = ns.SkinBackdrop
local SkinCloseButton = ns.SkinCloseButton
local TEX_NORM = ns.TEX_NORM
local ZUI = ns.ZUI

-- TOOLTIP LOOK (2026-10-27, Zac: "my zui tooltips are boring and they
-- overlap my damage meters by default"): ZacUIDB.tooltip -
--   cursor      default-anchored tooltips ride beside the cursor instead
--               of Blizzard's corner (a saved /zacui movetip spot still
--               wins over the corner when this is off)
--   unitBorder  a unit tooltip's border takes the unit's class or
--               reaction colour
--   healthText  "4.6k / 4.6k  100%" on the health bar, which grows a bit
-- and the look on Screen > Tooltips (every default is what this file drew
-- before those settings existed; a colour or font left unset is "as
-- before"):
--   scale, cursorX/Y, barHeight (0 = 11 px with numbers, 6 without),
--   barTexture, bgColor, borderColor, barColor, healthColor, headerFont,
--   bodyFont, healthFont, showTarget, spellId, showAnim
local TIP_DEFAULTS = {
    cursor = false, unitBorder = true, healthText = true,
    scale = 1, cursorX = 18, cursorY = 12, barHeight = 0,
    showTarget = true, spellId = true,
}
local function TipCfg()
    local t = ZacUIDB.tooltip
    if type(t) ~= "table" then t = {} ZacUIDB.tooltip = t end
    for k, v in pairs(TIP_DEFAULTS) do
        if t[k] == nil then t[k] = v end
    end
    return t
end
ns.TipCfg = TipCfg
local function ShortNum(n)
    n = tonumber(n) or 0
    if n >= 1e6 then return string.format("%.1fm", n / 1e6)
    elseif n >= 1e4 then return string.format("%.0fk", n / 1e3)
    elseif n >= 1e3 then return string.format("%.1fk", n / 1e3)
    else return tostring(math.floor(n + 0.5)) end
end

local function HexRGB(r, g, b)
    return string.format("|cff%02x%02x%02x",
        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5))
end

local function Empty(spec) return type(spec) ~= "table" or next(spec) == nil end

-- ============================================================
-- THE LOOK - shared by the real tooltips and the Tooltips page's sample
-- ============================================================
local TipLook = {}

-- The dark panel behind one tooltip (Blizzard's NineSlice faded out).
function TipLook.Skin(tt)
    if not tt or tt._zui_bg then return tt and tt._zui_bg end
    if type(tt.NineSlice) == "table" and tt.NineSlice.SetAlpha then tt.NineSlice:SetAlpha(0) end
    local bg = CreateFrame("Frame", nil, tt, "BackdropTemplate")
    bg:SetAllPoints()
    bg:SetFrameLevel(math.max(0, tt:GetFrameLevel() - 1))
    SkinBackdrop(bg, "windowBg", 0.95)
    tt._zui_bg = bg
    -- a palette change repaints this; the tooltip's own settings win
    bg._zPaint = function() TipLook.Paint(tt) end
    return bg
end

-- Background, border (unless a unit's colour is on it) and scale.
function TipLook.Paint(tt, cfg)
    local bg = tt and tt._zui_bg
    if not bg then return end
    cfg = cfg or TipCfg()
    if type(cfg.bgColor) == "table" and bg._zui_cbg then
        bg._zui_cbg:SetVertexColor(ns.ColorOf(cfg.bgColor))
    else
        SkinBackdrop(bg, "windowBg", 0.95)
    end
    if not tt._zui_tinted and ns.TintBorder then
        if type(cfg.borderColor) == "table" then
            ns.TintBorder(bg, ns.ColorOf(cfg.borderColor))
        else
            ns.TintBorder(bg)
        end
    end
    local s = tonumber(cfg.scale) or 1
    if tt.SetScale and (s ~= 1 or tt._zScaled) then
        tt._zScaled = s ~= 1 or nil
        tt:SetScale(s)
    end
end

-- The border when a tooltip is about a unit: its class or reaction
-- colour, or back to the setting / palette.
function TipLook.TintUnit(tt, r, g, b)
    local bg = tt and tt._zui_bg
    if not (bg and ns.TintBorder) then return end
    if r then
        ns.TintBorder(bg, r, g, b, 1)
        tt._zui_tinted = true
    else
        tt._zui_tinted = nil
        TipLook.Paint(tt)
    end
end

function TipLook.BarHeight(cfg)
    cfg = cfg or TipCfg()
    local h = tonumber(cfg.barHeight) or 0
    if h > 0 then return h end
    return cfg.healthText and 11 or 6
end

local function HealthFontDefaults()
    local f = ZacUIDB and ZacUIDB.font
    return { size = 9 + ((f and f.delta) or 0), outline = "outline", shadow = false }
end
TipLook.HealthFontDefaults = HealthFontDefaults

-- The health bar: texture, height, the numbers' font and colour. The
-- real bar is GameTooltipStatusBar; the sample is a bar of its own.
function TipLook.StyleBar(bar, cfg)
    if not bar then return end
    cfg = cfg or TipCfg()
    if cfg.barTexture then
        bar:SetStatusBarTexture(ns.ResolveBarTexture(cfg.barTexture))
    else
        bar:SetStatusBarTexture((ns.Media and ns.Media.BarPath(TEX_NORM)) or TEX_NORM)
    end
    bar:SetHeight(TipLook.BarHeight(cfg))
    if not bar._zui_text then
        bar._zui_text = bar:CreateFontString(nil, "OVERLAY")
        bar._zui_text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    end
    local fs = bar._zui_text
    -- its spot: the bar's middle, or the saved one (cfg.anchors.health,
    -- ZacUI's anchor shape: any point of the bar or of the tooltip)
    local a = type(cfg.anchors) == "table" and cfg.anchors.health or nil
    if a or fs._zMoved then
        local d = fs._zDef or {}
        fs._zDef = d
        d.point, d.relPoint, d.x, d.y, d.to = "CENTER", "CENTER", 0, 0, bar
        if not fs._zTo then
            fs._zTo = function(k) if k == "bar" then return bar elseif k == "tooltip" then return bar:GetParent() end end
        end
        ns.ApplyAnchor(fs, a, d, fs._zTo)
        fs._zMoved = a ~= nil or nil
    end
    if Empty(cfg.healthFont) then
        if ns.HouseFont then ns.HouseFont(fs, 9, "OUTLINE", STANDARD_TEXT_FONT)
        else fs:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE") end
    elseif ns.ApplyFontSpec then
        ns.ApplyFontSpec(fs, cfg.healthFont, HealthFontDefaults())
    end
    local r, g, b
    if type(cfg.healthColor) == "table" then
        r, g, b = ns.ColorOf(cfg.healthColor)
    else
        local t = Col("text")
        r, g, b = t.r, t.g, t.b
    end
    fs:SetTextColor(r, g, b)
end

-- The bar's colour: the unit's, unless a fixed one is set.
function TipLook.BarColor(r, g, b, cfg)
    cfg = cfg or TipCfg()
    if type(cfg.barColor) == "table" then return ns.ColorOf(cfg.barColor) end
    return r, g, b
end

-- the health numbers' format shape (what nothing saved reads as)
TipLook.HP_DEFAULT = { template = "[cur] / [max]  [pct]%", decimals = 0 }
TipLook.HP_SMALL = { template = "[pct]%" }
TipLook.HP_KINDS = { cur = "number", max = "number", deficit = "number", pct = "percent" }
TipLook.HP_TOKENS = { { token = "cur", label = "Current" }, { token = "max", label = "Most" },
    { token = "deficit", label = "Missing" }, { token = "pct", label = "Percent" } }
TipLook.fmtValues = {}

-- The numbers on the bar ("" when they are off).
function TipLook.HealthText(cur, maxv, cfg)
    cfg = cfg or TipCfg()
    if not cfg.healthText then return "" end
    cur, maxv = tonumber(cur) or 0, tonumber(maxv) or 0
    if maxv <= 0 then return "" end
    local fmt = type(cfg.formats) == "table" and cfg.formats.health or nil
    if fmt and ns.FormatText then
        -- a saved format (cfg.formats.health): the line through ZacUI's
        -- formatter; its defaults read as the line always did
        local v = TipLook.fmtValues
        v.cur, v.max, v.deficit, v.pct = cur, maxv, maxv - cur, cur / maxv * 100
        return ns.FormatText(fmt, maxv <= 100 and TipLook.HP_SMALL or TipLook.HP_DEFAULT, v, TipLook.HP_KINDS)
    end
    local pct = math.floor(cur / maxv * 100 + 0.5)
    if maxv <= 100 then return pct .. "%" end
    return ShortNum(cur) .. " / " .. ShortNum(maxv) .. "  " .. pct .. "%"
end

-- Tooltip text: Blizzard's three tooltip font objects, set from the
-- page's specs. An unset spec leaves the object alone (or puts back what
-- it had before ZacUI touched it).
local FONT_OBJECTS = {
    { obj = "GameTooltipHeaderText", key = "headerFont" },
    { obj = "GameTooltipText",       key = "bodyFont" },
    { obj = "GameTooltipTextSmall",  key = "bodyFont", smaller = 2 },
}
local fontStock = {}
function TipLook.StockFont(objName)
    local s = fontStock[objName]
    if s then return s[1], s[2], s[3] end
    local o = _G[objName]
    if o and o.GetFont then return o:GetFont() end
end
function TipLook.ApplyFonts(cfg)
    cfg = cfg or TipCfg()
    local restored = false
    for _, f in ipairs(FONT_OBJECTS) do
        local o = _G[f.obj]
        if o and o.GetFont and ns.ApplyFontSpec then
            local spec = cfg[f.key]
            if Empty(spec) then
                local s = fontStock[f.obj]
                if s then
                    fontStock[f.obj] = nil
                    pcall(o.SetFont, o, s[1], s[2], s[3])
                    if o.SetShadowOffset then o:SetShadowOffset(s[4] or 0, s[5] or 0) end
                    restored = true
                end
            else
                if not fontStock[f.obj] then
                    local p, sz, fl = o:GetFont()
                    local sx, sy = 0, 0
                    if o.GetShadowOffset then sx, sy = o:GetShadowOffset() end
                    fontStock[f.obj] = { p, sz, fl, sx, sy }
                end
                local s = fontStock[f.obj]
                local use = spec
                if f.smaller and spec.size then
                    use = {}
                    for k, v in pairs(spec) do use[k] = v end
                    use.size = math.max(6, spec.size - f.smaller)
                end
                ns.ApplyFontSpec(o, use, { face = s[1], size = s[2] or 12,
                    outline = (s[3] and s[3] ~= "") and s[3] or "none",
                    shadow = (s[4] or 0) ~= 0 or (s[5] or 0) ~= 0,
                    shadowX = s[4], shadowY = s[5] })
            end
        end
    end
    -- the global font (Appearance > Fonts) back over anything put back
    if restored and ns.ApplyFonts then pcall(ns.ApplyFonts) end
end

-- What one sample tooltip says, in the colours the decorator uses.
function TipLook.UnitColor(kind)
    if kind == "enemy" then
        local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[2]
        if c then return c.r, c.g, c.b end
        return 1, 0.1, 0.1
    end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS.WARRIOR
    if c then return c.r, c.g, c.b end
    return 0.78, 0.61, 0.43
end
function TipLook.SampleLines(tt, kind, cfg)
    cfg = cfg or TipCfg()
    if not tt.AddLine then return end
    local t, a = Col("text"), Col("accent")
    if kind == "item" then
        tt:AddLine("Sulfuras, Hand of Ragnaros", 1, 0.5, 0)
        tt:AddLine("Binds when picked up", 1, 1, 1)
        tt:AddDoubleLine("Two-Hand", "Mace", 1, 1, 1, 1, 1, 1)
        tt:AddDoubleLine("223 - 372 Damage", "Speed 3.70", 1, 1, 1, 1, 1, 1)
        tt:AddLine("+12 Stamina", 1, 1, 1)
        if cfg.spellId then
            tt:AddDoubleLine("Spell ID", "21162", a.r, a.g, a.b, t.r, t.g, t.b)
        end
        return
    end
    local r, g, b = TipLook.UnitColor(kind)
    if kind == "enemy" then
        tt:AddLine("Ragnaros", r, g, b)
        tt:AddLine("|cffff3333Level ??|r Elemental (Boss)", t.r, t.g, t.b)
        if cfg.showTarget then
            tt:AddLine("Target: |cffff3333<< YOU >>|r", t.r, t.g, t.b)
        end
        return
    end
    tt:AddLine("Zaccw |cff999999<AFK>|r", r, g, b)
    tt:AddLine("<Petri Out>", a.r, a.g, a.b)
    tt:AddLine("|cffffff00Level 60|r Human " .. HexRGB(r, g, b) .. "Warrior|r", t.r, t.g, t.b)
    if cfg.showTarget then
        tt:AddLine("Target: |cffff3333Ragnaros|r", t.r, t.g, t.b)
    end
end

ns.TipLook = TipLook

Modules.tooltip = function()
    -- Explicit appends (hole-in-ipairs law): WorldMapTooltip is gone on
    -- 11509 and the shopping tooltips vary by build - a nil mid-literal
    -- would silently skip every tooltip after the hole.
    local tips = {}
    local function AddTip(t) if t then tips[#tips + 1] = t end end
    AddTip(GameTooltip)
    AddTip(ItemRefTooltip)
    AddTip(ShoppingTooltip1)
    AddTip(ShoppingTooltip2)
    AddTip(ItemRefShoppingTooltip1)
    AddTip(ItemRefShoppingTooltip2)
    AddTip(WorldMapTooltip)
    for _, tt in ipairs(tips) do
        if tt and not ZUI.skinned[tt] then
            ZUI.skinned[tt] = true
            TipLook.Skin(tt)
            TipLook.Paint(tt)
            tt:HookScript("OnShow", function(self)
                if self._zui_bg then self._zui_bg:Show() end
            end)
        end
    end
    local itemRefClose = ItemRefCloseButton or (ItemRefTooltip and ItemRefTooltip.CloseButton)
    if itemRefClose then SkinCloseButton(itemRefClose) end
    if GameTooltipStatusBar then
        -- texture, height and the numbers' font (TipLook.StyleBar)
        TipLook.StyleBar(GameTooltipStatusBar)
        if ns.Media then ns.Media.TrackBar(GameTooltipStatusBar) end
    end
    TipLook.ApplyFonts()

    -- EVERY CHANGE ON THE TOOLTIPS PAGE APPLIES AT ONCE: repaint the
    -- tooltips, restyle the bar, set the fonts (once per frame at most).
    -- Also after the Fonts page or a bar-texture change, which would
    -- otherwise put the global font / texture back over a chosen one.
    local function ApplyLook()
        local cfg = TipCfg()
        for _, tt in ipairs(tips) do TipLook.Paint(tt, cfg) end
        if GameTooltipStatusBar then
            local bar = GameTooltipStatusBar
            TipLook.StyleBar(bar, cfg)
            local c = bar._zui_col
            if c then bar:SetStatusBarColor(TipLook.BarColor(c[1], c[2], c[3], cfg)) end
        end
        TipLook.ApplyFonts(cfg)
    end
    TipLook.ApplyAll = ApplyLook
    if ns.OnSettingsChanged and ns.Coalesce and not ZUI._tipLookListen then
        ZUI._tipLookListen = true
        ns.OnSettingsChanged(ns.Coalesce(ApplyLook))
    end

    -- APPEARING: the tooltip's show animation (none unless one is picked
    -- on the Tooltips page). GameTooltip only - the item comparison and
    -- link tooltips hang off it or stay put.
    if GameTooltip and GameTooltip.HookScript and ns.Motion then
        GameTooltip:HookScript("OnShow", function(self)
            local spec = TipCfg().showAnim
            if type(spec) == "table" and spec.style and spec.style ~= "none" then
                ns.Motion.Play(self, spec, "in")
            end
        end)
    end

    -- UNIT INFO DECORATOR - TipTac-lite, house-clean. Runs after
    -- Blizzard fills a unit tooltip; recolors/reformats lines Blizzard
    -- already wrote and adds ONE line (the unit's target). Name takes
    -- class color (players) or reaction color (NPCs) with grey
    -- <AFK>/<DND>/<Dead> tags; guild goes accent in brackets; the level
    -- line gets a difficulty-colored level and class-colored class; the
    -- health bar wears the media texture in the unit's color and HOLDS
    -- it against Blizzard's green-red gradient writes. Dual-generation
    -- install: TooltipDataProcessor when the client has it, classic
    -- OnTooltipSetUnit HookScript otherwise. Everything guarded.
    local function UnitColor(unit)
        if UnitIsPlayer and UnitIsPlayer(unit) and UnitClass then
            -- direct call: "UnitClass and UnitClass(u)" would truncate
            -- the multiple returns and lose the class token
            local _, classToken = UnitClass(unit)
            local c = classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
            if c then return c.r, c.g, c.b end
        elseif UnitReaction then
            local re = UnitReaction(unit, "player")
            local c = re and FACTION_BAR_COLORS and FACTION_BAR_COLORS[re]
            if c then return c.r, c.g, c.b end
        end
        local t = Col("text")
        return t.r, t.g, t.b
    end
    -- QUIET IN FIGHTS AND RAIDS (2026-10-22, Zac: "tooltips should be
    -- disabled in a raid/combat its annoying to have it always there").
    -- Unit tooltips - a player or mob under the mouse, a unit frame - do
    -- not show in combat, nor anywhere inside a raid instance; hold Shift
    -- while you point to see one anyway. Item, spell, bag and button
    -- tooltips are untouched. Both on unless switched off on the main page.
    local function TipQuiet()
        local d = ZacUIDB.tooltipHide
        if type(d) ~= "table" then d = { combat = true, raid = true } ZacUIDB.tooltipHide = d end
        if IsShiftKeyDown() then return false end
        if d.combat and (InCombatLockdown() or UnitAffectingCombat("player")) then return true end
        if d.raid and ns.InRaidInstance() then return true end
        return false
    end
    local function Decorate(tt)
        if tt ~= GameTooltip then return end
        -- a tooltip about to be hidden (QuietUnit, below) is not dressed
        if TipQuiet() then return end
        local _, unit = tt.GetUnit and tt:GetUnit()
        if not unit and UnitExists and UnitExists("mouseover") then
            unit = "mouseover"
        end
        if not (unit and UnitExists and UnitExists(unit)) then return end

        local l1 = _G.GameTooltipTextLeft1
        if l1 then
            local r, g, b = UnitColor(unit)
            l1:SetTextColor(r, g, b)
            local tag
            if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then tag = "Dead"
            elseif UnitIsAFK and UnitIsAFK(unit) then tag = "AFK"
            elseif UnitIsDND and UnitIsDND(unit) then tag = "DND" end
            if tag then
                local txt = l1:GetText()
                if txt and not txt:find("<" .. tag .. ">", 1, true) then
                    l1:SetText(txt .. " |cff999999<" .. tag .. ">|r")
                end
            end
        end

        if UnitIsPlayer and UnitIsPlayer(unit) and GetGuildInfo then
            local guild = GetGuildInfo(unit)
            local l2 = _G.GameTooltipTextLeft2
            local t2 = l2 and l2.GetText and l2:GetText()
            if guild and t2 and t2:find(guild, 1, true) then
                local a = Col("accent")
                l2:SetText("<" .. guild .. ">")
                l2:SetTextColor(a.r, a.g, a.b)
            end
        end

        local lvl = UnitLevel and UnitLevel(unit)
        if lvl and tt.NumLines and LEVEL then
            for i = 2, tt:NumLines() do
                local line = _G["GameTooltipTextLeft" .. i]
                local txt = line and line.GetText and line:GetText()
                if txt and txt:sub(1, #LEVEL) == LEVEL then
                    local diff = GetQuestDifficultyColor
                        and GetQuestDifficultyColor(lvl > 0 and lvl or 63)
                    local dh = diff and HexRGB(diff.r, diff.g, diff.b) or "|cffffffff"
                    local lvlText = lvl > 0 and tostring(lvl) or "??"
                    local rest = txt:sub(#LEVEL + 1):match("^%s*%S*%s*(.*)$") or ""
                    if UnitIsPlayer(unit) and UnitClass then
                        local className, classToken = UnitClass(unit)
                        local cc = classToken and RAID_CLASS_COLORS
                            and RAID_CLASS_COLORS[classToken]
                        if className and cc then
                            local pos = rest:find(className, 1, true)
                            if pos then
                                rest = rest:sub(1, pos - 1)
                                    .. HexRGB(cc.r, cc.g, cc.b) .. className .. "|r"
                                    .. rest:sub(pos + #className)
                            end
                        end
                    end
                    line:SetText(dh .. LEVEL .. " " .. lvlText .. "|r " .. rest)
                    break
                end
            end
        end

        local tu = unit .. "target"
        if TipCfg().showTarget and UnitExists and UnitExists(tu) and UnitName then
            local t = Col("text")
            if UnitIsUnit and UnitIsUnit(tu, "player") then
                tt:AddLine("Target: |cffff3333<< YOU >>|r", t.r, t.g, t.b)
            else
                local tn = UnitName(tu)
                if tn then
                    tt:AddLine("Target: " .. HexRGB(UnitColor(tu)) .. tn .. "|r",
                        t.r, t.g, t.b)
                end
            end
        end

        local bar = GameTooltipStatusBar
        if bar and bar.SetStatusBarColor then
            local r, g, b = UnitColor(unit)
            bar._zui_col = { r, g, b }
            bar:SetStatusBarColor(TipLook.BarColor(r, g, b))
            bar._zui_unit = unit
        end
        -- the border in the unit's colour, back to the setting on hide
        if TipCfg().unitBorder and tt._zui_bg then
            TipLook.TintUnit(tt, UnitColor(unit))
        end
    end
    if GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnHide", function(self)
            if self._zui_tinted then TipLook.TintUnit(self) end
            self._zui_cursor = nil
            if GameTooltipStatusBar then GameTooltipStatusBar._zui_unit = nil end
        end)
    end
    if GameTooltipStatusBar then
        AddPixelBorder(GameTooltipStatusBar)
        if GameTooltipStatusBar.HookScript then
            GameTooltipStatusBar:HookScript("OnValueChanged", function(self, value)
                local cfg = TipCfg()
                local c = self._zui_col
                if c then self:SetStatusBarColor(TipLook.BarColor(c[1], c[2], c[3], cfg)) end
                local fs = self._zui_text
                if fs then
                    local u0 = self._zui_unit
                    local hidden = ns.IsSecret and (ns.IsSecret(value)
                        or (u0 and UnitHealthMax and ns.IsSecret(UnitHealthMax(u0))))
                    if hidden then
                        -- WoW Forever hides health in combat: no numbers then
                        fs:SetText("")
                    elseif cfg.healthText then
                        local _, maxv = self:GetMinMaxValues()
                        local cur = tonumber(value) or self:GetValue() or 0
                        maxv = tonumber(maxv) or 0
                        -- the bar runs 0-100 for a unit whose real health
                        -- the client keeps from us; then the percent alone
                        local u = self._zui_unit
                        if u and UnitHealthMax and UnitHealthMax(u) and UnitHealthMax(u) > 100 then
                            cur, maxv = UnitHealth(u), UnitHealthMax(u)
                        end
                        fs:SetText(TipLook.HealthText(cur, maxv, cfg))
                        fs:Show()
                    else
                        fs:SetText("")
                    end
                    -- Blizzard sizes the bar itself on some paths
                    local want = TipLook.BarHeight(cfg)
                    if math.abs((self:GetHeight() or 0) - want) > 0.5 then self:SetHeight(want) end
                end
            end)
        end
    end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, Decorate)
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetUnit", Decorate)
    end

    local function QuietUnit(tt)
        if tt == GameTooltip and TipQuiet() then tt:Hide() end
    end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, QuietUnit)
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetUnit", QuietUnit)
    end

    -- SPELL ID LINE. Every aura and spell tooltip ends with the spell's
    -- id: the buff bar, target / party / unit-frame auras, the aura
    -- engine's icons, action buttons, the spellbook, spell links. Two
    -- hook families because aura tooltips are filled by
    -- SetUnitAura/Buff/Debuff and never fire OnTooltipSetSpell.
    -- Blizzard's buff buttons re-set their tooltip every frame while
    -- hovered and each set clears the lines, so the id is put back each
    -- time; the last-line check is what stops a tooltip reached by both
    -- families from getting it twice.
    local SPELL_ID_LABEL = "Spell ID"
    local function AddSpellID(tt, id)
        if type(id) ~= "number" or id <= 0 then return end
        if not TipCfg().spellId then return end
        local name, n = tt.GetName and tt:GetName(), tt.NumLines and tt:NumLines() or 0
        if not name or n == 0 then return end
        -- runs every frame while a buff is hovered: the line font strings
        -- are looked up once per tooltip and line number
        local lefts = tt._zLeft
        if not lefts then lefts = {} tt._zLeft = lefts end
        local last = lefts[n]
        if not last then
            last = _G[name .. "TextLeft" .. n]
            lefts[n] = last
        end
        if last and last.GetText and last:GetText() == SPELL_ID_LABEL then return end
        local a, t = Col("accent"), Col("text")
        tt:AddDoubleLine(SPELL_ID_LABEL, tostring(id), a.r, a.g, a.b, t.r, t.g, t.b)
        tt:Show()       -- re-fits the tooltip to the extra line
    end
    local function AuraHook(read)
        return function(tt, unit, index, filter)
            -- spellId is the 10th return; no aura = no returns = no line
            AddSpellID(tt, (select(10, read(unit, index, filter))))
        end
    end
    local function SpellHook(tt)
        if not tt.GetSpell then return end
        -- (name, id) here; older builds put a rank string in between
        local _, a, b = tt:GetSpell()
        AddSpellID(tt, type(b) == "number" and b or a)
    end
    -- the buff and debuff bar on 1.15.9 fills its tooltips by aura
    -- instance id, not by index (2026-10-27, Zac: "on my buffs and
    -- debuffs bar can we get the ability/spell id") - the same line, read
    -- from the aura data
    local function InstanceHook(tt, unit, auraInstanceID)
        local get = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
        local data = get and unit and auraInstanceID and get(unit, auraInstanceID)
        -- (WoW Forever may hide the aura's id in combat: no line then)
        if data and ns.IsSecret and ns.IsSecret(data.spellId) then return end
        AddSpellID(tt, data and data.spellId)
    end
    if GameTooltip and hooksecurefunc then
        for _, m in ipairs({ "SetUnitBuffByAuraInstanceID", "SetUnitDebuffByAuraInstanceID", "SetUnitAuraByAuraInstanceID" }) do
            if GameTooltip[m] then hooksecurefunc(GameTooltip, m, InstanceHook) end
        end
        if GameTooltip.SetUnitAura and UnitAura then
            hooksecurefunc(GameTooltip, "SetUnitAura", AuraHook(UnitAura))
        end
        if GameTooltip.SetUnitBuff and UnitBuff then
            hooksecurefunc(GameTooltip, "SetUnitBuff", AuraHook(UnitBuff))
        end
        if GameTooltip.SetUnitDebuff and UnitDebuff then
            hooksecurefunc(GameTooltip, "SetUnitDebuff", AuraHook(UnitDebuff))
        end
    end
    local spellTips = {}
    if GameTooltip then spellTips[#spellTips + 1] = GameTooltip end
    if ItemRefTooltip then spellTips[#spellTips + 1] = ItemRefTooltip end
    for _, tt in ipairs(spellTips) do
        if tt.HasScript and tt:HasScript("OnTooltipSetSpell") then
            tt:HookScript("OnTooltipSetSpell", SpellHook)
        end
    end

    -- MOVABLE default anchor: when a position is saved, default-anchored
    -- tooltips (mouseover units, world objects, UI hover) appear there
    -- instead of Blizzard's corner. Unset = Blizzard default. Position is
    -- set with the drag anchor from /zacui movetip.
    if type(GameTooltip_SetDefaultAnchor) == "function" then
        local function PlaceAtCursor(tt)
            local x, y = GetCursorPosition()
            local s = UIParent:GetEffectiveScale()
            local cfg = TipCfg()
            -- the tooltip's own scale divides the offset it is placed at
            local ts = (tt.GetScale and tt:GetScale()) or 1
            if ts <= 0 then ts = 1 end
            tt:ClearAllPoints()
            tt:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT",
                (x / s + (tonumber(cfg.cursorX) or 18)) / ts, (y / s + (tonumber(cfg.cursorY) or 12)) / ts)
        end
        -- while a cursor-anchored tooltip is up it follows the cursor;
        -- one frame handle for every GameTooltip refresh (no per-frame
        -- work when nothing is anchored this way)
        GameTooltip:HookScript("OnUpdate", function(self)
            if self._zui_cursor then PlaceAtCursor(self) end
        end)
        hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tt, parent)
            if TipCfg().cursor then
                tt._zui_cursor = true
                PlaceAtCursor(tt)
                return
            end
            tt._zui_cursor = nil
            local pos = ZacUIDB.tooltipPos
            if pos and pos.point then
                -- NO SetOwner HERE. SetOwner CLEARS EVERY LINE, and this
                -- is an anchor hook - it runs on paths that have already
                -- written their content, and on refreshes of a tooltip
                -- that is currently up. The result is a tooltip that is
                -- shown, owned, still sized to its old contents, and
                -- completely empty; with the 0.95 windowBg this file
                -- paints behind it, that reads as a solid black
                -- rectangle following the cursor rather than as the
                -- near-invisible sliver an empty tooltip is on
                -- Blizzard's own art.
                --
                -- Nothing is lost by dropping it: GameTooltip_SetDefaultAnchor
                -- has already assigned the owner before this hook runs,
                -- so only the PLACEMENT needs overriding.
                local ts = (tt.GetScale and tt:GetScale()) or 1
                if ts <= 0 then ts = 1 end
                tt:ClearAllPoints()
                tt:SetPoint(pos.point, UIParent, pos.point, (pos.x or 0) / ts, (pos.y or 0) / ts)
            end
        end)
    end
end

-- Drag anchor for the tooltip position (toggled by /zacui movetip).
local tipMover
-- shown = true builds (once) and shows the anchor, false hides it.
-- `silent` skips the chat hint - Edit Mode shows every anchor at once
-- and one line per anchor would be noise.
local function SetTipMover(shown, silent)
    if not shown then
        if tipMover then tipMover:Hide() end
        return
    end
    if not tipMover then
        tipMover = CreateFrame("Frame", "ZacUITooltipMover", UIParent)
        tipMover:SetSize(160, 42)
        local function PlaceBox()
            local pos = ZacUIDB.tooltipPos
            tipMover:ClearAllPoints()
            if pos and pos.point then
                tipMover:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, pos.y or 0)
            else
                tipMover:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -120, 120)
            end
        end
        PlaceBox()
        -- the box's corner (the saved one, else bottom right) from the
        -- same corner of the screen: the numbers tooltipPos keeps
        local function Spot()
            local pos = ZacUIDB.tooltipPos
            local point = (pos and pos.point) or "BOTTOMRIGHT"
            local P = ns.MoverKit.POINTS[point] or ns.MoverKit.POINTS.CENTER
            local l, b, w, h = tipMover:GetRect()
            if not l then return point, pos and pos.x or -120, pos and pos.y or 120 end
            return point, l + w * P[1] - (UIParent:GetWidth() or 0) * P[1],
                b + h * P[2] - (UIParent:GetHeight() or 0) * P[2]
        end
        -- ZacUI's handle kit, like every other box you drag
        ns.MoverKit.Dress(tipMover, {
            label = "Tooltip anchor",
            coords = function(self)
                local pos = ZacUIDB.tooltipPos
                if pos and pos.point and not rawget(self, "_zDragging") then
                    return ns.MoverKit.Format(pos.point, pos.x, pos.y)
                end
                return ns.MoverKit.Format(Spot())
            end,
            dragStop = function()
                local point, x, y = Spot()
                ZacUIDB.tooltipPos = { point = point, x = ns.MoverKit.Round(x), y = ns.MoverKit.Round(y) }
                PlaceBox()
            end,
            nudge = function(dx, dy)
                local point, x, y = Spot()
                local pos = ZacUIDB.tooltipPos
                if pos and pos.point then point, x, y = pos.point, pos.x or 0, pos.y or 0 end
                ZacUIDB.tooltipPos = { point = point, x = ns.MoverKit.Round(x) + dx, y = ns.MoverKit.Round(y) + dy }
                PlaceBox()
            end,
            reset = function()
                ZacUIDB.tooltipPos = nil
                PlaceBox()
            end,
            hint = "Where tooltips without a home of their own appear.",
        })
        tipMover._zPlace = PlaceBox
    end
    tipMover._zPlace()
    tipMover:Show()
    if not silent then
        Print("Drag the anchor; /zacui movetip again to lock. /zacui resettip restores default.")
    end
end
local function ToggleTipMover()
    if tipMover and tipMover:IsShown() then
        tipMover:Hide()
        return
    end
    SetTipMover(true)
end

-- One popup skin, shared by the dialogs module and the classifier - so
-- popups created LATER (logout, summon, StaticPopup5+ on busy screens)
-- get the identical treatment the moment the watcher sees them.
-- Kill every texture on the popup and its NON-BUTTON children that ZacUI
-- did not create (ownership tags). Four rounds of backdrop/child fixes
-- failed because the popup's own texture REGIONS were never swept - this
-- covers that layer and survives Blizzard repainting them on show.
local function KillPopupChrome(f, depth)
    if not f or (depth or 0) > 2 then return end
    if f.GetRegions then
        for _, region in ipairs({ f:GetRegions() }) do
            if region.IsObjectType and region:IsObjectType("Texture")
                and not region._zui_own then
                region:SetTexture(nil)
                region:SetAlpha(0)
            end
        end
    end
    if f.GetChildren then
        for _, child in ipairs({ f:GetChildren() }) do
            if not (child.IsObjectType and child:IsObjectType("Button")) then
                KillPopupChrome(child, (depth or 0) + 1)
            end
        end
    end
end


-- shared with later ZacUI files
ns.SetTipMover = SetTipMover
-- back to Blizzard's spot, and the box with it when it is up
ns.ResetTipPos = function()
    ZacUIDB.tooltipPos = nil
    if tipMover and tipMover._zPlace then tipMover._zPlace() end
end
ns.ToggleTipMover = ToggleTipMover
ns.KillPopupChrome = KillPopupChrome
