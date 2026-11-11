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
-- WoW Forever hides an enemy's auras in combat. On that client an aura
-- with hidden details answers false plus its table, and the row shows its
-- icon, stacks and timer straight from it (the game takes hidden values
-- as they are: ZacUI's display helpers, Core_Flavor); a read the game
-- refuses answers false alone and the walk goes past it. Every other
-- client reads exactly as before.
local hiddenClient = _G.ZACUI_MODERN and true or false
local function GetAura(unit, index, filter)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local a
        if hiddenClient then
            a = ns.ReadAura(unit, index, filter)
            if a == false then return false end
        else
            a = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
        end
        if not a then return end
        if ns.AuraHidden and ns.AuraHidden(a) then
            if hiddenClient then return false, a end
            return
        end
        -- (also: is it yours, its spell id, its dispel type - for the filter)
        local mine = a.isFromPlayerOrPlayerPet
        if mine == nil then mine = (a.sourceUnit == "player" or a.sourceUnit == "pet") end
        return a.icon, a.applications, a.duration, a.expirationTime, a.name, mine and true or false,
            a.spellId, a.dispelName
    elseif UnitAura then
        local name, icon, count, dispel, duration, expirationTime, caster, _, _, spellId =
            UnitAura(unit, index, filter)
        if not name then return end
        return icon, count, duration, expirationTime, name, (caster == "player" or caster == "pet"),
            spellId, dispel
    end
end

-- A debuff ZacUI's own debuff groups draw on this plate already (Faerie
-- Fire, the curses, Demoralizing Shout... in the row under the bar;
-- Sunder as the count at its end): this strip leaves it to them, so it
-- shows once, in the row with the others (2026-11-08, Zac: "why is there
-- a demo shout icon behind the noob stuff and not under the mob name
-- like ff and curse of reck").
local function OwnedByGroups(name)
    local D = NP.Debuffs
    return name ~= nil and D ~= nil and D.Shows ~= nil and D.Shows(name)
end

-- Debuffs this strip never shows (d.auras.hideNames: names with commas,
-- any case; nil or empty = none, as always). The set is rebuilt only when
-- the text changes. (WoW Forever: a debuff the game hides in combat has no
-- name to match and still shows.)
local hideSrc, hideSet
local function NeverShown(d, name)
    local src = d.auras.hideNames
    if not src or src == "" then return false end
    if src ~= hideSrc then
        hideSrc, hideSet = src, {}
        for n in tostring(src):gmatch("[^,\n]+") do
            n = n:gsub("^%s+", ""):gsub("%s+$", ""):lower()
            if n ~= "" then hideSet[n] = true end
        end
    end
    return name ~= nil and hideSet[name:lower()] or false
end

-- The HUD's BT/WW row (HUD > Hesitation) standing over this plate right
-- now, else nil. It stands over the name, where this strip goes: while
-- it is there the strip goes over the row instead, never behind it.
local function RowOver(f)
    local H = ns.Hesitation
    return H and H.RowOver and H.RowOver(f) or nil
end

-- the row came onto one plate and/or left another (HUD_Hesitation)
function NP.RowOverChanged(was, now)
    if was and was.auras then NP.LayoutAuras(was) end
    if now and now ~= was and now.auras then NP.LayoutAuras(now) end
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
    if NP.MatchOn and NP.MatchOn() then
        -- the match pass's square icons: ZacUI's crop (Core_Look)
        ns.Look.CropIcon(icon.tex)
    else
        icon.tex:SetTexCoord(0.1, 0.9, 0.28, 0.72) -- wide crop for short icons
    end
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
    -- (match pass: 2 px over a name above the bar, the reference's row)
    local row = RowOver(f)
    if row then
        NP.Place(f, holder, "auras", NP.SetDef(f, "auras", "BOTTOM", row, "TOP", 0, 2))
    elseif NP.MatchOn and NP.MatchOn() and f.name and not f._nameInside and not f.nameOnly then
        NP.Place(f, holder, "auras", NP.SetDef(f, "auras", "BOTTOM", f.name, "TOP", 0, 2))
    else
        NP.Place(f, holder, "auras", NP.SetDef(f, "auras", "BOTTOM", f, "TOP", 0, 14 + (f._iconOverhang or 0)))
    end
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

    -- (an icon row over the plate - Readycheck's - owns that space: NP_Health)
    if not d.auras.enabled or f._npIconRow then
        holder:Hide()
        return
    end

    -- (2026-11-10) THE FILTER (Core_AuraFilter, place "np_strip"): every
    -- debuff on the unit is read, the filter says which show and which
    -- are pinned, and the row is drawn from what is left, in its order.
    -- "Mine only", the icon limit and the never-show names this row had
    -- before are that filter's preset, limit and Never list now.
    local AF = ns.AuraFilter
    local list = f._afList
    if not list then list = {} f._afList = list end
    local pool = f._afPool
    if not pool then pool = {} f._afPool = pool end
    for i = #list, 1, -1 do list[i] = nil end
    local ctx = f._afCtx
    if not ctx then ctx = {} f._afCtx = ctx end
    ctx.inCombat = UnitAffectingCombat and UnitAffectingCombat("player") and true or false
    local cls = UnitClassification and UnitClassification(f.unit)
    ctx.boss = (cls == "worldboss" or cls == "elite" or cls == "rareelite") and true or false
    local index, used = 1, 0
    -- (only yours can show: ask the game for yours alone, as this row did)
    local mineQuery = (AF and AF.OnlyMine("np_strip")) or (not AF and d.auras.mineOnly)
    local query = mineQuery and "HARMFUL|PLAYER" or "HARMFUL"
    while index <= 40 do
        local icon, count, duration, expirationTime, aname, mine, spellId, dispel =
            GetAura(f.unit, index, query)
        if icon == nil then break end
        if mineQuery then mine = true end
        index = index + 1
        used = used + 1
        local a = pool[used]
        if not a then a = {} pool[used] = a end
        if icon == false then
            -- (WoW Forever: hidden details; `count` holds the aura's table)
            a.hidden, a.raw = true, count
            a.name, a.spellId, a.duration, a.expirationTime, a.count, a.dispel = nil, nil, nil, nil, nil, nil
            a.mine = mineQuery or (count and ns.AuraIsMine and ns.AuraIsMine(count)) or nil
            a.icon = nil
        else
            a.hidden, a.raw = nil, nil
            a.icon, a.count, a.duration, a.expirationTime = icon, count, duration, expirationTime
            a.name, a.mine, a.spellId, a.dispel = aname, mine and true or false, spellId, dispel
        end
        if (a.hidden and a.raw) or (not a.hidden and not OwnedByGroups(aname)) then
            local show, pinned = true, false
            if AF then show, pinned = AF.Pass("np_strip", a, ctx) end
            if show then
                a.pinned = pinned
                list[#list + 1] = a
            end
        end
    end
    if AF then AF.Arrange("np_strip", list)
    else for i = #list, (d.auras.max or 6) + 1, -1 do list[i] = nil end end

    local shown = 0
    for _, a in ipairs(list) do
        shown = shown + 1
        local btn = AcquireIcon(holder, shown)
        if a.hidden then
            local raw = a.raw
            pcall(btn.tex.SetTexture, btn.tex, raw.icon)
            if not ns.ShowAuraCount(btn.count, f.unit, raw) then btn.count:SetText("") end
            btn._cdStart, btn._cdDur = nil, nil
            if ns.ShowAuraTimer(btn.cd, f.unit, raw) then btn.cd:Show() else btn.cd:Hide() end
        else
            -- This runs per icon on every UNIT_AURA of the plate, which in a
            -- pull is many times a second. Size and font are set once, at birth
            -- and in LayoutAuras (any settings change re-lays out), not here.
            -- The swipe is only restarted when its timing actually changed;
            -- SetCooldown with the same pair would restart the animation.
            btn.tex:SetTexture(a.icon)
            btn.count:SetText(a.count and a.count > 1 and a.count or "")
            local duration, expirationTime = a.duration, a.expirationTime
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

-- ============================================================
-- THE FILTER'S PLACE
-- ============================================================
-- What this row had of its own before the filter (Mine only, Most icons,
-- the never-show names) becomes the filter's preset, limit and Never list
-- the first time it is read, so the row shows what it showed.
if ns.AuraFilter then
    ns.AuraFilter.Register("np_strip", {
        label = "Nameplates: simple debuff row", kind = "debuff", preset = "mine", max = 6,
        refresh = function() if NP.RefreshAll then NP.RefreshAll() elseif NP.Refresh then NP.Refresh() end end,
        migrate = function(c)
            local ok, d = pcall(DB)
            local a = ok and type(d) == "table" and d.auras
            if type(a) ~= "table" then return end
            c.preset = (a.mineOnly == false) and "all" or "mine"
            if tonumber(a.max) then c.adv.max = tonumber(a.max) end
            for n in tostring(a.hideNames or ""):gmatch("[^,\n]+") do
                n = n:gsub("^%s+", ""):gsub("%s+$", "")
                if n ~= "" then c.never[n:lower()] = n end
            end
        end,
    })
end
