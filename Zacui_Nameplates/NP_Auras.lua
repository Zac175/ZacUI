-- NP_Auras - debuff icons riding above the plate, with duration swipe
-- and stack count. Mine-only by default, like the Plater setup was.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME = ...
-- Zacui_Nameplates is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local AddPixelBorder = ns.AddPixelBorder
local NP = ns.Nameplates

local DB = NP.DB
local SetNPFont = NP.SetNPFont

-- ============================================================
-- AURA READ - two client generations of the same call
-- ============================================================
local function GetAura(unit, index, filter)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local a = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
        -- (WoW Forever hides an enemy's auras in combat: read as none)
        if not a or (ns.AuraHidden and ns.AuraHidden(a)) then return end
        return a.icon, a.applications, a.duration, a.expirationTime
    elseif UnitAura then
        local name, icon, count, _, duration, expirationTime =
            UnitAura(unit, index, filter)
        if not name then return end
        return icon, count, duration, expirationTime
    end
end

-- ============================================================
-- BUILD
-- ============================================================
function NP.BuildAuras(f)
    local holder = CreateFrame("Frame", nil, f)
    holder:SetPoint("BOTTOM", f, "TOP", 0, 16)
    holder:SetSize(10, 10)
    f.auras = holder
    holder.icons = {}
end

-- the icon's 1px edge in the plates' border colour
local function AddChrome(icon) if NP.BarChrome then NP.BarChrome(nil, icon) end end

local function AcquireIcon(holder, i)
    local icon = holder.icons[i]
    if icon then return icon end
    icon = CreateFrame("Frame", nil, holder)
    icon.tex = icon:CreateTexture(nil, "ARTWORK")
    icon.tex:SetPoint("TOPLEFT", 1, -1)
    icon.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    icon.tex:SetTexCoord(0.1, 0.9, 0.28, 0.72) -- wide crop for short icons
    AddPixelBorder(icon)

    icon.cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cd:SetAllPoints()
    icon.cd:SetReverse(true)
    if icon.cd.SetHideCountdownNumbers then
        icon.cd:SetHideCountdownNumbers(true)
    end
    if icon.cd.SetDrawEdge then icon.cd:SetDrawEdge(false) end

    -- count needs its own layer above the swipe
    local countHost = CreateFrame("Frame", nil, icon)
    countHost:SetAllPoints()
    countHost:SetFrameLevel(icon.cd:GetFrameLevel() + 1)
    icon.count = countHost:CreateFontString(nil, "OVERLAY")
    SetNPFont(icon.count, 8) -- font at birth; layout re-sizes
    -- its corner of the icon (d.auras.anchors.count on top of the old spot)
    local d = DB()
    local ca = d.auras.anchors
    ns.ApplyAnchor(icon.count, ca and ca.count, NP.AURA_COUNT_DEF)
    -- sized at birth too, so an icon born after the plate's layout pass
    -- is right without the update path having to size it every time
    icon:SetSize(d.auras.width, d.auras.height)
    local cf = d.auras.countFont
    NP.ApplyNPFont(icon.count, cf, tonumber(cf and cf.size) or 8)
    AddChrome(icon)

    holder.icons[i] = icon
    return icon
end

NP.AcquireAuraIcon = AcquireIcon      -- the preview plate borrows the icon maker

function NP.LayoutAuras(f)
    local d = DB()
    local holder = f.auras
    -- Rides the same shift as the name: the raid marker overflows above
    -- the bar, the name moved up to clear it, and the auras have to keep
    -- their spacing above the name rather than land on top of it.
    NP.Place(f, holder, "auras", NP.SetDef(f, "auras", "BOTTOM", f, "TOP", 0, 14 + (f._iconOverhang or 0)))
    holder:SetHeight(d.auras.height)
    local cf = d.auras.countFont
    local csz = tonumber(cf and cf.size) or 8
    local ca = d.auras.anchors
    for _, icon in ipairs(holder.icons) do
        icon:SetSize(d.auras.width, d.auras.height)
        NP.ApplyNPFont(icon.count, cf, csz)
        ns.ApplyAnchor(icon.count, ca and ca.count, NP.AURA_COUNT_DEF)
        AddChrome(icon)
    end
end

-- ============================================================
-- UPDATE
-- ============================================================
function NP.UpdateAuras(f)
    if not f.unit then return end
    local d = DB()
    local holder = f.auras

    if not d.auras.enabled then
        holder:Hide()
        return
    end

    local filter = d.auras.mineOnly and "HARMFUL|PLAYER" or "HARMFUL"
    local shown = 0
    local index = 1
    while shown < d.auras.max do
        local icon, count, duration, expirationTime =
            GetAura(f.unit, index, filter)
        if not icon then break end
        index = index + 1

        shown = shown + 1
        -- This runs per icon on every UNIT_AURA of the plate, which in a
        -- pull is many times a second. Size and font are set once, at birth
        -- and in LayoutAuras (any settings change re-lays out), not here.
        -- The swipe is only restarted when its timing actually changed;
        -- SetCooldown with the same pair would restart the animation.
        local btn = AcquireIcon(holder, shown)
        btn.tex:SetTexture(icon)
        btn.count:SetText(count and count > 1 and count or "")
        if duration and duration > 0 and expirationTime then
            local start = expirationTime - duration
            if btn._cdStart ~= start or btn._cdDur ~= duration then
                btn._cdStart, btn._cdDur = start, duration
                btn.cd:SetCooldown(start, duration)
            end
            btn.cd:Show()
        else
            btn._cdStart, btn._cdDur = nil, nil
            btn.cd:Hide()
        end
        btn:Show()
    end

    for i = shown + 1, #holder.icons do
        holder.icons[i]:Hide()
    end

    if shown == 0 then
        holder:Hide()
        return
    end

    holder:Show()
    NP.PlaceAuraRow(f, shown)
end

-- Where the row's first `shown` icons go - the live plate above and the
-- preview's sample both place them through here. Nothing saved: one row
-- left to right from the holder's bottom-left, as it always was. A saved
-- layout (d.auras.layout, ZacUI's layout shape) lays them out instead;
-- its gaps default to the row's own spacing, new lines go up.
local AURA_LAYOUT_DEF = { grow = "RIGHT", wrap = "UP", perLine = 0 }
NP.AURA_LAYOUT_DEF = AURA_LAYOUT_DEF
function NP.PlaceAuraRow(f, shown)
    local d = DB()
    local holder = f.auras
    local w, gap = d.auras.width, tonumber(d.auras.spacing) or 2
    local spec = d.auras.layout
    if type(spec) == "table" then
        AURA_LAYOUT_DEF.spacingX, AURA_LAYOUT_DEF.spacingY = gap, gap
        local lw, lh = ns.LayoutItems(holder.icons, shown, holder, spec, AURA_LAYOUT_DEF)
        holder:SetSize(math.max(1, lw), math.max(1, lh))
        return
    end
    -- centered row over the bar
    holder:SetWidth(shown * w + (shown - 1) * gap)
    for i = 1, shown do
        local btn = holder.icons[i]
        btn:ClearAllPoints()
        btn:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT",
            (i - 1) * (w + gap), 0)
    end
end
