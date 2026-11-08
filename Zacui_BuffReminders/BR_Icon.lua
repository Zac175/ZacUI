-- BR_Icon - the reminder: an icon per buff, warning when you (or the
-- people it reaches) are missing it or it is about to run out.
-- Part of ZacUI; load order is set by the TOC.
--
-- The icon is Readycheck's Battle Shout icon, ported: the same parts
-- (background, 1 px border, the art and a grey copy for "missing", the
-- count in the middle, the missing names beside it), the same texts and
-- the same rules for when it shows, what it says and when it sounds.
-- Every buff the class gives gets one; they sit in a row on one holder
-- (the mover, CENTER 200, 0 like Readycheck's icon), so a warrior's one
-- Battle Shout icon is exactly where Readycheck's always was.
--
-- The drawing is split from the deciding, for the settings preview:
-- Icon.New builds one (no position, mouse, events or name), Icon.Style
-- dresses it from the settings, Icon.Fill paints one state on it. The live
-- icons and the preview's samples go through all three.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local BR = ns.BuffRem
if not BR then return end
local D = BR.Data

local Icon = {}
BR.IconUI = Icon

local FLAT = ns.FLAT or "Interface\\Buttons\\WHITE8X8"
local math_floor = math.floor

-- ============================================================
-- WHERE THE TEXTS AND PARTS SIT (ZacUI's anchor shape; icon.anchors.<key>)
-- ============================================================
-- Each element's built-in placement is exactly the SetPoint Readycheck's
-- icon always had: nothing saved = the same spot.
Icon.COUNT_DEF = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0, justify = "CENTER" }
Icon.ICON_DEF = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 0, y = 0,
    point2 = "BOTTOMRIGHT", relPoint2 = "BOTTOMRIGHT", x2 = 0, y2 = 0 }
local function SetDef(t, p, to, rp, x, y, j)
    t.point, t.to, t.relPoint, t.x, t.y, t.justify = p, to, rp, x, y, j
    return t
end
-- the names: beside / above / below the icon by the gap
function Icon.NamesDef(t, frame, ic)
    local pos = ic.namesPosition or "right"
    local gap = tonumber(ic.namesOffset) or 5
    if pos == "left" then return SetDef(t, "RIGHT", frame, "LEFT", -gap, 0, "RIGHT") end
    if pos == "above" then return SetDef(t, "BOTTOM", frame, "TOP", 0, gap, "CENTER") end
    if pos == "below" then return SetDef(t, "TOP", frame, "BOTTOM", 0, -gap, "CENTER") end
    return SetDef(t, "LEFT", frame, "RIGHT", gap, 0, "LEFT")
end
local pageDef = {}
function Icon.AnchorDefaults(key)
    if key == "count" then return Icon.COUNT_DEF end
    if key == "icon" then return Icon.ICON_DEF end
    if key == "names" then return Icon.NamesDef(pageDef, nil, BR.Icon()) end
end
Icon.TARGETS = {
    { value = "frame", text = "The icon frame" }, { value = "icon", text = "Icon art" },
    { value = "count", text = "Count text" }, { value = "names", text = "Missing names" },
}
local function SpecOf(ic, key)
    local a = ic and ic.anchors
    return type(a) == "table" and a[key] or nil
end
Icon.SpecOf = SpecOf

-- ============================================================
-- THE MATCH PASS (2026-11-07, zui_tests/MATCH_BARS_1107.md; ZacUI look
-- only): the reference UI's reminder icons - full opacity, the icon in
-- full colour while it warns (the icon showing IS the warning; the ring
-- keeps its warning colour), every text a crisp outline with no shadow,
-- the buff's short name 12 px under the icon, 14 px between icons. The
-- settings are saved as they are read, so a value still at the shipped
-- number (opacity 0.7, the shadowed fonts) draws these; anything set by
-- hand is the player's; the other looks draw what they drew.
-- ============================================================
local function HDOn()
    local L = ns.Look
    return (L and L.Is and L.Is("buffrem", "zacui")) and true or false
end
Icon.HDOn = HDOn
Icon.HD_LAYOUT_DEF = { grow = "RIGHT", spacingX = 14, spacingY = 14 }
Icon.SHORT = { battleshout = "Shout", trueshot = "Trueshot", intellect = "Intellect", fortitude = "Fortitude",
    spirit = "Spirit", shadowprot = "Shadow", motw = "Wild", thorns = "Thorns", soulstone = "Soulstone" }
-- what an icon setting draws at
function Icon.Opacity(ic)
    local o = tonumber(ic and ic.opacity) or 0.7
    if o == 0.7 and HDOn() then return 1 end
    return o
end
local function ShippedFont(spec, size)
    return type(spec) == "table" and spec.face == nil and spec.size == size
        and (spec.outline == "OUTLINE" or spec.outline == "outline") and spec.shadow == true
end
local HD_COUNT = { size = 16, outline = "OUTLINE", shadow = false }
local HD_NAMES = { size = 12, outline = "OUTLINE", shadow = false }
function Icon.FontSpec(ic, key)
    local spec = ic and ic[key]
    if HDOn() then
        if key == "countFont" and (spec == nil or ShippedFont(spec, 16)) then return HD_COUNT end
        if key == "namesFont" and (spec == nil or ShippedFont(spec, 12)) then return HD_NAMES end
    end
    return spec
end
function Icon.LayoutDefaults()
    return HDOn() and Icon.HD_LAYOUT_DEF or Icon.LAYOUT_DEF
end

-- ============================================================
-- BUILD / STYLE / FILL
-- ============================================================
function Icon.New(parent, def, preview)
    local f = CreateFrame("Frame", nil, parent)
    f.def = def
    f.preview = preview
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    -- the 1 px border, one strip a side (coloured per state by Fill)
    f.border = {}
    -- HD polish (2026-11-07, ZacUI's look): the ring OVER the icon (on the
    -- BORDER layer the icon, drawn over the whole rect, hid it and its
    -- state colour) and one physical pixel per unit of thickness
    local hd = ns.Pixel and ns.Pixel.On()
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
        local t = f:CreateTexture(nil, hd and "OVERLAY" or "BORDER", nil, hd and 6 or nil)
        t:SetTexture(FLAT)
        if side == "top" then t:SetPoint("TOPLEFT") t:SetPoint("TOPRIGHT") t:SetHeight(1)
        elseif side == "bottom" then t:SetPoint("BOTTOMLEFT") t:SetPoint("BOTTOMRIGHT") t:SetHeight(1)
        elseif side == "left" then t:SetPoint("TOPLEFT") t:SetPoint("BOTTOMLEFT") t:SetWidth(1)
        else t:SetPoint("TOPRIGHT") t:SetPoint("BOTTOMRIGHT") t:SetWidth(1) end
        if hd then ns.Pixel.Edge(t, side:upper(), f) end
        f.border[side] = t
    end
    local tex = BR.Icon_(def)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexture(tex)
    ZacUI.Look.CropIcon(f.icon)
    f.desaturate = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.desaturate:SetAllPoints()
    f.desaturate:SetTexture(tex)
    ZacUI.Look.CropIcon(f.desaturate)
    f.desaturate:SetDesaturated(true)
    f.desaturate:Hide()
    f.countText = f:CreateFontString(nil, "OVERLAY")
    ns.ApplyFontSpec(f.countText, nil, BR.DEFAULTS.icon.countFont)
    f.countText:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.countText:SetJustifyH("CENTER")
    f.namesText = f:CreateFontString(nil, "OVERLAY")
    ns.ApplyFontSpec(f.namesText, nil, BR.DEFAULTS.icon.namesFont)
    f.namesText:Hide()
    f._to = function(k)
        if k == "frame" then return f elseif k == "icon" then return f.icon
        elseif k == "count" then return f.countText elseif k == "names" then return f.namesText end
    end
    f._namesDef = {}
    if preview and ns.TagElement then
        ns.TagElement(f.icon, "buffrem.icon") ns.TagElement(f.desaturate, "buffrem.icon")
        ns.TagElement(f.countText, "buffrem.count") ns.TagElement(f.namesText, "buffrem.names")
    end
    Icon.Style(f, BR.Icon())
    return f
end

-- size, opacity, background, border thickness, fonts, the parts' spots
function Icon.Style(f, ic)
    ic = ic or BR.Icon()
    local size = tonumber(ic.iconSize) or 40
    local opacity = Icon.Opacity(ic)
    f:SetSize(size, size)
    local bgC = BR.Color("icon", "background")
    f.bg:SetColorTexture(bgC.r, bgC.g, bgC.b, opacity * 0.7)
    f.icon:SetAlpha(opacity)
    f.desaturate:SetVertexColor(0.4, 0.4, 0.4, opacity)
    local bs = tonumber(ic.borderSize) or 1
    for side, t in pairs(f.border) do
        if bs <= 0 then t:Hide() else
            t:Show()
            if not (ns.Pixel and ns.Pixel.SetEdgeSize(t, bs)) then
                if side == "top" or side == "bottom" then t:SetHeight(bs) else t:SetWidth(bs) end
            end
        end
    end
    local hd = HDOn()
    local cspec = Icon.FontSpec(ic, "countFont")
    ns.ApplyFontSpec(f.countText, cspec, BR.DEFAULTS.icon.countFont)
    -- the count has always worn a heavier 2 px shadow (not the ZacUI look's)
    local cs = type(cspec) == "table" and cspec.shadow
    if cs == nil or cs then f.countText:SetShadowOffset(2, -2) end
    ns.ApplyFontSpec(f.namesText, Icon.FontSpec(ic, "namesFont"), BR.DEFAULTS.icon.namesFont)
    if hd then
        -- the short name under the icon (made only under the ZacUI look)
        if not f.label then
            f.label = f:CreateFontString(nil, "OVERLAY")
            f.label:SetPoint("TOP", f, "BOTTOM", 0, -5)
            f.label:SetJustifyH("CENTER")
        end
        ns.ApplyFontSpec(f.label, nil, HD_NAMES)
        local def = f.def
        f.label:SetText((def and (Icon.SHORT[def.key] or (def.label and def.label:match("(%S+)$")))) or "")
        f.label:SetTextColor(1, 1, 1, 1)
        f.label:Show()
    elseif f.label then
        f.label:Hide()
    end
    ns.ApplyAnchor(f.countText, SpecOf(ic, "count"), Icon.COUNT_DEF, f._to)
    local iconSpec = SpecOf(ic, "icon")
    local _, two = ns.ApplyAnchor(f.icon, iconSpec, Icon.ICON_DEF, f._to)
    ns.ApplyAnchor(f.desaturate, iconSpec, Icon.ICON_DEF, f._to)
    if not two then
        f.icon:SetSize(size, size)
        f.desaturate:SetSize(size, size)
    end
    ns.ApplyAnchor(f.namesText, SpecOf(ic, "names"), Icon.NamesDef(f._namesDef, f, ic), f._to)
    -- shadow and glow round it (icon.chrome); nothing saved = nothing made
    if ns.ApplyChrome and (ic.chrome or f._zcShadow or f._zcGlow) then ns.ApplyChrome(f, ic.chrome) end
end

-- one state: warn (bool), the count text, the names (or nil)
function Icon.Fill(f, warn, text, names)
    local tc = BR.Color("icon", warn and "missingText" or "allBuffedText")
    -- (the ZacUI look: in colour while it warns - match pass)
    local grey = warn and not HDOn()
    f._zWarn = warn and true or false
    f.icon:SetShown(not grey)
    f.desaturate:SetShown(grey and true or false)
    f.countText:SetText(text or "")
    f.countText:SetTextColor(tc.r, tc.g, tc.b, tc.a or 1)
    local bc = BR.Color("icon", warn and "missingBorder" or "normalBorder")
    for _, t in pairs(f.border) do t:SetColorTexture(bc.r, bc.g, bc.b, bc.a or 1) end
    if names and names ~= "" then
        f.namesText:SetText(names)
        f.namesText:SetTextColor(tc.r, tc.g, tc.b, tc.a or 1)
        f.namesText:Show()
    else
        f.namesText:Hide()
    end
end

-- ============================================================
-- APPEAR / GO (showAnim, alertAnim, hideAnim; nil = none, as ever)
-- ============================================================
local NONE = { style = "none" }
function Icon.Appear(f, warn)
    local ic = BR.Icon()
    local M = ns.Motion
    local entering = (not f:IsShown()) or f._leaving
    local function Alert()
        if warn and f:IsShown() and not f._leaving and ic.alertAnim then
            f._alert = true
            M.Play(f, ic.alertAnim, "update")
        end
    end
    if entering then
        f._leaving, f._alert = nil, nil
        if not M.Show(f, ic.showAnim or NONE, Alert) then f:Show() end
    elseif warn and not f._alert then
        Alert()
    elseif not warn and f._alert then
        f._alert = nil
        M.Stop(f)
    end
end
function Icon.Go(f)
    if not f or not f:IsShown() or f._leaving then return end
    local ic = BR.Icon()
    f._alert = nil
    f._leaving = true
    ns.Motion.Hide(f, ic.hideAnim or NONE, function() f._leaving = nil end)
    if not f:IsShown() then f._leaving = nil end
end
function Icon.StopNow(f)
    if not f then return end
    if ns.Motion then ns.Motion.Stop(f) end
    f._alert, f._leaving = nil, nil
    f:Hide()
end

-- ============================================================
-- WHAT ONE ICON SAYS (Readycheck's UpdateBattleShoutReminder)
-- ============================================================
-- -> show (bool), warn, text, names, startedWarning
local GREED_SHOUT_THRESHOLD = 180
function Icon.Decide(def)
    local ic = BR.Icon()
    local key = def.key
    if def.port and BR.Opt(key, "greedMode") then
        -- the long (15-min) shout still well up on you: stay quiet
        local has, rem = BR.UnitBuffStatus("player", def)
        if has and rem > GREED_SHOUT_THRESHOLD then return false end
        if BR.Opt(key, "greedSkipIfImpCleave") and Icon.HasTalent and Icon.HasTalent("Improved Cleave") then
            return false
        end
    end
    local missing, total, lowest, below, lowestAP, weak, names = BR.ScanReminder(def)
    if total == 0 then return false end
    local needsWarning = missing > 0 or below > 0 or weak
    if ic.hideWhenAllBuffed and not needsWarning then return false, needsWarning end
    local selfOnly = BR.Opt(key, "scope") == "self"
    local showAP = def.port and BR.Opt(key, "showAPValue")
    local text, namesText = "", nil
    if needsWarning then
        if selfOnly then
            -- with only yourself tracked "1 missing" is the icon itself
            if weak and showAP then text = lowestAP .. " AP"
            elseif below > 0 and missing == 0 then text = tostring(math_floor(lowest)) end
        elseif weak and showAP then
            text = lowestAP .. " AP"
        elseif missing > 0 and below > 0 then
            text = missing .. "/" .. math_floor(lowest)
        elseif missing > 0 then
            text = tostring(missing)
        elseif below > 0 then
            text = tostring(math_floor(lowest))
        end
        if ic.showMissingNames and not selfOnly and #names > 0 then namesText = table.concat(names, "\n") end
    elseif showAP and lowestAP > 0 then
        text = lowestAP .. " AP"
    end
    return true, needsWarning, text, namesText, missing, below, lowest
end

-- a talent by name (Improved Cleave), on any client
function Icon.HasTalent(name)
    if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo) then return false end
    for tab = 1, GetNumTalentTabs() do
        for i = 1, GetNumTalents(tab) do
            local n, _, _, _, rank = GetTalentInfo(tab, i)
            if n == name then return (rank or 0) > 0 end
        end
    end
    return false
end

-- ============================================================
-- THE LIVE ICONS
-- ============================================================
local holder
local icons = {}        -- [key] = frame
local lastWarn = {}     -- [key] = warning at the last look
BR.liveIcons = icons
local MOVER = "buffRemIcon"
Icon.MOVER = MOVER

local function Holder()
    if holder then return holder end
    holder = CreateFrame("Frame", "ZacUIBuffRemIcons", UIParent)
    holder:SetSize(40, 40)
    holder:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    holder:SetClampedToScreen(true)
    holder:SetFrameStrata("MEDIUM")
    holder:SetFrameLevel(50)
    if ns.RegisterMover then
        ns.RegisterMover(MOVER, "Buff reminder", function() return holder end, "CENTER", 200, 0)
        if ns.ApplyMover then ns.ApplyMover(MOVER) end
    end
    -- when it shows (icon.visibility, ZacUI's shape: fade rules on top of
    -- "Show in"); nothing saved = never touched
    if ns.Visibility and ns.Visibility.Register then
        ns.Visibility.Register(holder, function() return BR.Icon().visibility end, { control = "alpha" })
    end
    Icon.ApplyLayer()
    return holder
end
Icon.Holder = Holder

-- layer and scale (icon.framePos: strata, level offset, scale, clamp)
function Icon.ApplyLayer()
    if not holder then return end
    local fp = BR.Icon().framePos
    if fp or holder._zcLayered then
        holder._zcLayered = true
        ns.ApplyFramePosition(holder, fp, { strata = "MEDIUM", level = 50, scale = 1, clamp = true })
    end
end

local function LiveIcon(def)
    local f = icons[def.key]
    if f then return f end
    f = Icon.New(Holder(), def, false)
    f:Hide()
    icons[def.key] = f
    return f
end

-- the shown icons in a row on the holder (icon.layout; nothing saved =
-- one icon on the holder's spot, the next ones to its right, 4 apart)
Icon.LAYOUT_DEF = { grow = "RIGHT", spacingX = 4, spacingY = 4 }
local order = {}
function Icon.Arrange(host, list)
    local ic = BR.Icon()
    local w, h = ns.LayoutItems(list, #list, host, ic.layout, Icon.LayoutDefaults())
    local size = tonumber(ic.iconSize) or 40
    host:SetSize(math.max(size, w or size), math.max(size, h or size))
end

local function ShowFrames()
    if not BR.On() then return false end
    if BR.Placing(MOVER) then return true end
    return BR.ShowIn(BR.Icon())
end

local warnStarted = {}
local function Sound(def)
    local ic = BR.Icon()
    if ic.playSound then
        local dflt = { sound = ic.soundKey or "WR: Warning", channel = "Master" }
        local snd = type(ic.sounds) == "table" and ic.sounds.warn or nil
        local name = (type(snd) == "table" and snd.sound) or dflt.sound
        if name ~= "none" and not (ns.PlaySoundSpec and ns.PlaySoundSpec(snd, dflt, "buffrem.warn")) then
            -- a name no sound library knows: Readycheck's own warning file
            local throttled = type(snd) == "table" and tonumber(snd.throttle) and tonumber(snd.throttle) > 0
            if not throttled then
                pcall(PlaySoundFile, "Interface\\AddOns\\Readycheck\\Media\\Sounds\\announce.ogg",
                    (type(snd) == "table" and snd.channel) or "Master")
            end
        end
    end
    if ic.speak and C_VoiceChat and C_VoiceChat.SpeakText and ns.VoiceId then
        pcall(C_VoiceChat.SpeakText, ns.VoiceId(), def.label, 0, 100, 1)
    end
end

-- the layout helper shows what it places; the icons appear through their
-- own animation instead, so it places stand-ins that pass the anchors on
local Proxy = {}
Proxy.__index = Proxy
function Proxy:GetWidth() return self.f:GetWidth() end
function Proxy:GetHeight() return self.f:GetHeight() end
function Proxy:SetSize(w, h) self.f:SetSize(w, h) end
function Proxy:SetHeight(h) self.f:SetHeight(h) end
function Proxy:ClearAllPoints() self.f:ClearAllPoints() end
function Proxy:SetPoint(...) self.f:SetPoint(...) end
local proxies = setmetatable({}, { __mode = "k" })
-- the shown icons in the order dragged in the preview (icon.order: buff
-- keys; nil = the list as it is, not copied)
local function FrameKey(f) return f and f.def and f.def.key end
function Icon.Ordered(frames)
    local o = BR.Icon().order
    if type(o) ~= "table" or not ns.OrderedList then return frames end
    return ns.OrderedList(frames, o, FrameKey)
end

function Icon.Place(host, frames)
    frames = Icon.Ordered(frames)
    local list = {}
    for i, f in ipairs(frames) do
        local p = proxies[f]
        if not p then p = setmetatable({ f = f }, Proxy) proxies[f] = p end
        list[i] = p
    end
    Icon.Arrange(host, list)
end

local decided = {}
local UpdateInner
-- IN THE WARRIOR HUD'S BUFF ROW (Zac 2026-11-03: "put the battleshout
-- reminder in my buff bar part of the hud ... out of the center of my
-- screen but still be visible enough"). With buffs.battleshout.hudDock on
-- and the warrior HUD's buff row showing, the reminder's own icon stays
-- away and the row shows its "bsRem" slot instead: the same decision (and
-- the same sound / voice), its count under it, glowing while it warns.
-- The HUD reads the last decision (BR.HudState); nothing is scanned twice.
local hudState = {}
local function HudRowOn()
    local WH = ns.WarriorHUD
    if not (WH and WH.IsActive and WH:IsActive() and WH.Store) then return false end
    local cfg = WH.Store()
    local row = cfg and cfg.auraRow
    if not row or row.enabled == false then return false end
    if type(row.hidden) == "table" and row.hidden.bsRem then return false end
    return true
end
function Icon.Docked(def)
    return def and def.key == "battleshout" and BR.Opt("battleshout", "hudDock") == true and HudRowOn() or false
end
function BR.HudState(key)
    return hudState[key]
end

function Icon.Update() return BR.InPass(UpdateInner) end
UpdateInner = function()
    local mine = BR.MyBuffs()
    local show = ShowFrames()
    local placing = BR.Placing(MOVER)
    for i = #order, 1, -1 do order[i] = nil end
    for i = #decided, 1, -1 do decided[i] = nil end
    for _, def in ipairs(mine) do
        if show and BR.ReminderOn(def.key) then
            local f = LiveIcon(def)
            local on, warn, text, names, nMissing, nBelow, lowest
            if placing then
                on, warn, text, names = true, true, def.reach == "party" and "3" or "5", nil
            else
                on, warn, text, names, nMissing, nBelow, lowest = Icon.Decide(def)
            end
            -- the warning just started: sound and voice, once
            if warn and not lastWarn[def.key] and not placing then Sound(def) end
            if warn ~= nil then lastWarn[def.key] = warn and true or false end
            if Icon.Docked(def) and not placing then
                -- missing: the icon greyed (and how many, in a group);
                -- under the warn threshold: in colour, the time left in red
                local hs = hudState[def.key] or {}
                hs.warn, hs.text, hs.tex = warn and true or false, text, BR.Icon_(def)
                hs.missing = (nMissing or 0) > 0
                hs.low = (nBelow or 0) > 0
                hs.lowest = lowest
                hs.lowAt = (lowest and lowest < 999999) and (GetTime() + lowest) or nil
                hs.count = nMissing or 0
                hs.selfOnly = BR.Opt(def.key, "scope") == "self"
                hs.names = names
                hudState[def.key] = on and hs or nil
                on = false
            else
                hudState[def.key] = nil
            end
            if on then
                Icon.Fill(f, warn, text, names)
                order[#order + 1] = f
            end
            decided[#decided + 1] = { f = f, on = on, warn = warn }
        else
            lastWarn[def.key] = nil
            hudState[def.key] = nil
            if icons[def.key] then decided[#decided + 1] = { f = icons[def.key], on = false } end
        end
    end
    -- in the saved order (icon.order) before "most shown" keeps the first
    local ord = Icon.Ordered(order)
    if ord ~= order then for i = 1, #ord do order[i] = ord[i] end end
    -- "most shown" (icon.layout.max): the ones past it go
    local mx = type(BR.Icon().layout) == "table" and tonumber(BR.Icon().layout.max)
    if mx and mx >= 1 and #order > mx then
        for i = #order, mx + 1, -1 do
            local f = order[i]
            order[i] = nil
            for _, d in ipairs(decided) do if d.f == f then d.on = false end end
        end
    end
    -- icons of buffs this character does not give
    for key, f in pairs(icons) do
        local def = D.BY_KEY[key]
        if not (def and BR.Gives(def)) and f:IsShown() then Icon.StopNow(f) end
    end
    if #order > 0 then
        -- re-placed only when the row changes (a move mid-animation would
        -- fight the animation's rest): which icons, their size, the layout
        local ic = BR.Icon()
        local parts = { tostring(ic.iconSize or 40) }
        for _, f in ipairs(order) do parts[#parts + 1] = f.def.key end
        local lay = ic.layout
        if type(lay) == "table" then
            for _, k in ipairs({ "grow", "wrap", "perLine", "spacingX", "spacingY", "padding", "max", "reverse" }) do
                parts[#parts + 1] = tostring(lay[k])
            end
        end
        local sig = table.concat(parts, ":")
        if sig ~= Icon._sig then
            Icon._sig = sig
            for _, f in ipairs(order) do ns.Motion.Stop(f) end
            Icon.Place(Holder(), order)
        end
    end
    -- then each one appears or goes (its animations from its spot)
    for _, d in ipairs(decided) do
        if d.on then Icon.Appear(d.f, d.warn) else Icon.Go(d.f) end
    end
    return #order
end

function Icon.Restyle()
    local ic = BR.Icon()
    Icon._sig = nil
    for _, f in pairs(icons) do Icon.Style(f, ic) end
    Icon.ApplyLayer()
    if holder and ns.Visibility and ns.Visibility.Refresh then ns.Visibility.Refresh(holder) end
end

-- the 1.5 s ticker while the reminder may show (Readycheck's pace)
local ticker
local function Wanted()
    if not ShowFrames() then return false end
    for _, def in ipairs(BR.MyBuffs()) do
        if BR.ReminderOn(def.key) then return true end
    end
    return false
end
local function Tick()
    if not Wanted() then
        if ticker then ticker:Cancel() ticker = nil end
        Icon.Update()
        return
    end
    Icon.Update()
end
function Icon.Refresh()
    if Wanted() then
        if not ticker then ticker = BR.NewTicker("buffRem.reminder", 1.5, Tick) end
        Icon.Update()
    else
        if ticker then ticker:Cancel() ticker = nil end
        for _, f in pairs(icons) do Icon.Go(f) end
    end
end
Icon.Running = function() return ticker ~= nil end
BR.OnRefresh("icon", Icon.Refresh)

-- your own aura changed: a quicker look (one queued, 0.3 s)
local quick = false
local auraWatch = CreateFrame("Frame")
pcall(auraWatch.RegisterEvent, auraWatch, "UNIT_AURA")
auraWatch:SetScript("OnEvent", function(_, _, unit)
    if unit ~= "player" or not ticker or quick then return end
    quick = true
    C_Timer.After(0.3, function() quick = false if ticker then Icon.Update() end end)
end)
