-- NP_Debuffs - debuff icons, stack counts and timers on enemy plates:
-- Sunder/Expose count, Faerie Fire and curses, taunts, the Overpower
-- proc window, the Execute cue. Readycheck's "Nameplate Debuff Auras"
-- moved into ZacUI's own plates (Readycheck_Features/NameplateAuras.lua
-- was the original; this is the same engine on ZacUI's frames, with
-- Zac's settings as the defaults).
-- Part of ZacUI; load order is set by the TOC.
--
-- GROUPS. Each group is one spot on the plate, measured from the health
-- bar's CENTRE (attach "center"; "top"/"bottom" measure from the bar's
-- edge): mode "single" draws the first present member, "row" lays every
-- present member out from the offset in growDir. members are catalog
-- keys in order; memberOn[key] = false mutes one. showIcon / showCount
-- / showTimer, fontSize (count), timerSize, timerPos "beside"|"under",
-- timerGap.
--
-- PERF. UNIT_AURA only marks a plate dirty; one 0.2s ticker rescans at
-- most 12 dirty plates a tick and redraws a timer text once a second.
-- The elements are children of ZacUI's plate frame, so they fade and
-- scale with it and nothing is measured or counter-scaled. The Overpower
-- window is core's (ns.Overpower). Plates arrive through NP_Core's own
-- lifecycle.

local ADDON_NAME = ...
-- Zacui_Nameplates is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local NP = ns.Nameplates
if not NP then return end
local DBRoot = NP.DB
local SetNPFont = NP.SetNPFont

local floor, ceil, format = math.floor, math.ceil, string.format
local GetSpellInfo = GetSpellInfo
-- the classic multi-return when the client has it, else the same values
-- off C_UnitAuras (the HUD keeps the same fallback)
local UnitDebuff = UnitDebuff or function(unit, index)
    local a = C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex and C_UnitAuras.GetDebuffDataByIndex(unit, index)
    if a then return a.name, a.icon, a.applications, a.dispelName, a.duration, a.expirationTime end
end

local D = {}
NP.Debuffs = D

-- spellID is only a lookup seed: ResolveCatalog() turns it into the
-- localized spell NAME and matching happens on that exact name string,
-- so every rank and every caster of the same spell resolves to one key.
local CATALOG = {
    sunder          = { spellID = 7405,  stack = true },
    expose          = { spellID = 8647,  label = "E" },
    cor             = { spellID = 704 },
    faeriefire      = { spellID = 770 },
    faeriefireferal = { spellID = 16857 },
    demoshout       = { spellID = 1160 },
    demoroar        = { spellID = 99 },
    curseofweakness = { spellID = 702 },
    thunderclap     = { spellID = 6343 },
    thunderfury     = { spellID = 21992 },
    disarm          = { spellID = 676 },
    scorch          = { spellID = 22959, stack = true },
    curseofelements = { spellID = 1490 },
    curseofshadow   = { spellID = 17862 },
    judgelight      = { spellID = 20185 },
    judgewisdom     = { spellID = 20186 },
    huntersmark     = { spellID = 1130 },
    overpower       = { spellID = 7384, proc = true },  -- name only: IsUsableSpell
    -- taunt effects match by aura name, so every rank and every caster
    -- is covered - including the Razuvious understudy Taunt (29060)
    taunt            = { spellID = 355 },
    growl            = { spellID = 6795 },
    mockingblow      = { spellID = 694 },
    challengingshout = { spellID = 1161 },
    challengingroar  = { spellID = 5209 },
}
D.CATALOG = CATALOG

-- Zac's layout, as the defaults - "layout E" from the mock-ups
-- (2026-10-19): above the bar only the BT/WW/OP/EXE row (HUD >
-- Hesitation, its own fixed spot); the Sunder count big at the bar's
-- right end; everything ON the mob as one row of small icons hanging
-- under the bar from its left corner, timers inside; the raid packs'
-- icons the same size hanging from the right corner, growing left.
-- Overpower and Execute are not plate groups at all: HUD > Hesitation's
-- row shows them (Overpower through D.OverpowerProc below).
local function DefaultGroups()
    return {
        { id = "armor", name = "Sunder / Expose", mode = "single", attach = "right", timerPos = "beside",
          offsetX = 16, offsetY = 0, enabled = true, fontSize = 25, timerSize = 7, timerGap = 0,
          showIcon = false, showCount = true, showTimer = true,
          members = { "sunder", "expose", "scorch" }, memberOn = { scorch = false } },
        { id = "under", name = "Under the bar", mode = "row", attach = "bottomleft", timerPos = "beside",
          growDir = "right", offsetX = 0, offsetY = -2, enabled = true, fontSize = 14, timerSize = 8, timerGap = 0,
          showIcon = true, showCount = false, showTimer = true,
          members = { "faeriefire", "faeriefireferal", "cor", "curseofelements", "curseofshadow",
                      "taunt", "growl", "mockingblow", "challengingshout", "challengingroar",
                      "demoshout", "demoroar", "curseofweakness", "thunderclap", "thunderfury", "disarm",
                      "judgelight", "judgewisdom", "huntersmark" },
          memberOn = { curseofelements = false, curseofshadow = false,
                       demoshout = false, demoroar = false, curseofweakness = false, thunderclap = false,
                       thunderfury = false, disarm = false,
                       judgelight = false, judgewisdom = false, huntersmark = false } },
    }
end
local UNDER_ID = "under"       -- the group custom debuffs join
-- the two groups the row took over; a save still carrying them loses
-- them once (the Execute group's bosses-only choice goes with it)
local ROW_OWNED = { overpower = true, execute = true }

local function Cfg()
    local root = DBRoot()
    if type(root.debuffs) ~= "table" then root.debuffs = {} end
    local c = root.debuffs
    if c.enabled == nil then c.enabled = true end
    if type(c.groups) ~= "table" then c.groups = DefaultGroups() end
    if type(c.custom) ~= "table" then c.custom = {} end
    -- the raid mods' plate widgets (Disarm, Enrage, Whirlwind...) in one
    -- strip at one spot, measured like the groups from the bar's centre
    if c.packStrip == nil then c.packStrip = true end
    -- to the right of the BT/WW row (which sits centred at +48), level
    -- with it, clear of the +20 groups; the first default (-8, +20) sat
    -- on the Overpower and Execute icons and is moved once
    if c.packX == nil then c.packX = 0 end
    if c.packY == nil then c.packY = -3 end
    if c.packAt == nil then c.packAt = "after" end           -- "after" the debuff row | "bottomright" | "center"
    if c.packScale == nil then c.packScale = 0.55 end        -- the packs' art is ~30px; this makes it the strip's 16
    if not c._packSpotV2 then
        c._packSpotV2 = true
        if c.packX == -8 and c.packY == 20 then c.packX, c.packY = 40, 46 end
    end
    -- the first defaults measured everything from the bar's centre with
    -- Readycheck's 120-wide bar in mind; on ZacUI's wider plate the
    -- "edge" groups sat well inside it. Untouched groups move to the
    -- edge-relative spots once; a group Zac moved himself is left alone.
    if not c._edgeAnchorsV2 then
        c._edgeAnchorsV2 = true
        local OLD = { armor = { 102, 0, "right", 42 }, armorextra = { -59, 20, "left", 0 },
            taunts = { -106, 0, "left", -46 }, overpower = { 52, 20, "right", -8 }, execute = { 35, 20, "right", -25 } }
        for _, g in ipairs(c.groups) do
            local o = OLD[g.id]
            if o and (g.attach or "center") == "center" and g.offsetX == o[1] and g.offsetY == o[2] then
                g.attach, g.offsetX = o[3], o[4]
            end
        end
    end
    if not c._rowOwnsProcsV1 then
        c._rowOwnsProcsV1 = true
        for i = #c.groups, 1, -1 do
            local g = c.groups[i]
            if g and ROW_OWNED[g.id] then
                table.remove(c.groups, i)
            end
        end
    end
    -- layout E (2026-10-19): the groups and the pack strip start over
    -- from the new defaults once; custom debuffs rejoin the row, muted
    -- the strip follows the debuff row on the left now, so the right
    -- corner stays free for the mob's target name (Zac: "name still
    -- jumping down"); the old corner default moves once
    if not c._packAfterV1 then
        c._packAfterV1 = true
        if c.packAt == "bottomright" then c.packAt, c.packX, c.packY = "after", 2, 0 end
    end
    -- level with the threat strip (2 under the bar, as it is) rather than
    -- under it: an untouched -3 moves once
    if not c._rowLevelV1 then
        c._rowLevelV1 = true
        for _, g in ipairs(c.groups) do
            if g.id == "under" and g.offsetY == -3 then g.offsetY = -2 end
        end
    end
    if not c._layoutEV1 then
        c._layoutEV1 = true
        c.groups = DefaultGroups()
        c.packAt, c.packX, c.packY, c.packScale = "after", 2, 0, 0.55
        c._packAfterV1 = true
        for key in pairs(c.custom) do
            for _, g in ipairs(c.groups) do
                if g.id == UNDER_ID then
                    g.members[#g.members + 1] = key
                    g.memberOn = g.memberOn or {}
                    g.memberOn[key] = false
                end
            end
        end
    end
    return c
end
D.Cfg = Cfg
D.UNDER_ID = UNDER_ID

-- for the raid mods' anchoring (RM_Anchors): where their plate widgets
-- go, or nil to leave each pack's own offsets alone
function D.PackStrip()
    local c = Cfg()
    if not (c.enabled and c.packStrip) then return nil end
    return { x = c.packX, y = c.packY, at = c.packAt or "after", scale = c.packScale or 1 }
end

local function MemberEnabled(group, key)
    return group.memberOn == nil or group.memberOn[key] ~= false
end
D.MemberEnabled = MemberEnabled

local function GSize(group) return (group and group.fontSize) or 11 end
-- the timer defaults to 60% of the group font, floored at 7pt: below
-- that the outline eats the glyphs
local function TSize(group)
    return (group and group.timerSize) or math.max(7, floor(GSize(group) * 0.6))
end

local byName = {}
local function ResolveCatalog()
    local c = Cfg()
    for key, def in pairs(c.custom) do
        if type(def) == "table" and def.spellID then
            local e = CATALOG[key]
            if not e then e = {} CATALOG[key] = e end
            e.spellID = def.spellID
            e.stack = def.stack and true or nil
            e.custom = true
        end
    end
    wipe(byName)
    for key, entry in pairs(CATALOG) do
        local nm, _, icon = GetSpellInfo(entry.spellID)
        entry.name = nm or entry.name or key
        entry.icon = icon or entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
        byName[entry.name] = key
    end
end
D.ResolveCatalog = ResolveCatalog

-- ============================================================
-- COLOURS / TEXT
-- ============================================================
local function Col(cat, key, fr, fg, fb)
    local c = ns.GetColor and ns.GetColor(cat, key)
    if c then return c.r, c.g, c.b end
    return fr, fg, fb
end

-- 1 stack on the low colour, 5 (the Sunder / Scorch cap) on the high
local function StackColor(cnt)
    local lr, lg, lb = Col("text", "red", 1, 0.25, 0.25)
    local hr, hg, hb = Col("text", "green", 0.3, 1, 0.3)
    local t = (cnt - 1) / 4
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    return lr + (hr - lr) * t, lg + (hg - lg) * t, lb + (hb - lb) * t
end

local function FmtTime(rem)
    if rem >= 60 then return format("%dm", ceil(rem / 60)) end
    return format("%ds", ceil(rem))
end

-- The count and the timer each wear the group's font spec (countFont /
-- timerFont: face, outline, shadow - Nameplates > Text) at the group's
-- sizes; restyled only when the size, the spec or the plate font moved.
local function StyleElem(elem, group)
    local fSize, smallSize = GSize(group), TSize(group)
    local sz = fSize + 2
    elem.icon:SetSize(sz, sz)
    local face = NP.FontPath and NP.FontPath() or ""
    local cf, tf = group.countFont, group.timerFont
    if elem._mainSize ~= fSize or elem._mainSpec ~= cf or elem._mainFace ~= face then
        elem._mainSize, elem._mainSpec, elem._mainFace = fSize, cf, face
        if NP.ApplyNPFont then NP.ApplyNPFont(elem.main, cf, fSize) else SetNPFont(elem.main, fSize) end
    end
    if elem._subSize ~= smallSize or elem._subSpec ~= tf or elem._subFace ~= face then
        elem._subSize, elem._subSpec, elem._subFace = smallSize, tf, face
        if NP.ApplyNPFont then NP.ApplyNPFont(elem.sub, tf, smallSize) else SetNPFont(elem.sub, smallSize) end
    end
end

local function NewElem(parent)
    local e = {}
    e.iconBorder = parent:CreateTexture(nil, "OVERLAY")
    e.iconBorder:SetDrawLayer("OVERLAY", 0)
    e.iconBorder:SetColorTexture(0, 0, 0, 1)
    e.icon = parent:CreateTexture(nil, "OVERLAY")
    e.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    e.icon:SetDrawLayer("OVERLAY", 1)
    e.iconBorder:SetPoint("TOPLEFT", e.icon, "TOPLEFT", -1, 1)
    e.iconBorder:SetPoint("BOTTOMRIGHT", e.icon, "BOTTOMRIGHT", 1, -1)
    e.iconBorder:Hide()
    e.main = parent:CreateFontString(nil, "OVERLAY")
    e.main:SetDrawLayer("OVERLAY", 7)
    e.sub = parent:CreateFontString(nil, "OVERLAY")
    e.sub:SetDrawLayer("OVERLAY", 7)
    -- font at birth: a FontString with no font errors on its first SetText
    SetNPFont(e.main, 11)
    SetNPFont(e.sub, 7)
    e.main:Hide() e.sub:Hide() e.icon:Hide()
    return e
end

-- Where a group measures from. "left"/"right": the bar's own edge, so a
-- group pinned there stays on the edge whatever the bar's width (the
-- old centre offsets assumed one width and drifted inward on a wider
-- plate); "top"/"bottom": the bar's edge above/below; "center": the
-- bar's middle.
local function AnchorPoints(group)
    local a = group.attach or "center"
    if a == "top" then return "BOTTOM", "TOP" end
    if a == "bottom" then return "TOP", "BOTTOM" end
    if a == "left" then return "CENTER", "LEFT" end
    if a == "right" then return "CENTER", "RIGHT" end
    -- the corners: the element's matching corner on the bar's, so a row
    -- hanging from one starts flush with the bar's end
    if a == "bottomleft" then return "TOPLEFT", "BOTTOMLEFT" end
    if a == "bottomright" then return "TOPRIGHT", "BOTTOMRIGHT" end
    if a == "topleft" then return "BOTTOMLEFT", "TOPLEFT" end
    if a == "topright" then return "BOTTOMRIGHT", "TOPRIGHT" end
    return "CENTER", "CENTER"
end
local function IsCorner(group)
    local a = group.attach
    return a == "bottomleft" or a == "bottomright" or a == "topleft" or a == "topright"
end
local function HangsUnder(group)
    local a = group.attach
    return a == "bottom" or a == "bottomleft" or a == "bottomright"
end

-- the raid-pack strip on this plate, when it has something in it
local function PackUp(f)
    local ps = f._zuiPackStrip
    if ps and ps:IsShown() and (ps._zuiN or 0) > 0 and (Cfg().packAt or "after") ~= "center" then return ps end
end

-- How tall the icon line under THIS plate is right now (below
-- NP.UnderDrop): the tallest under-bar group with something showing,
-- or the raid-pack strip with something in it, in the plate's units;
-- 0 when nothing is up. The crosshair keeps its line clear of it.
function D.UnderReach(f)
    if not f then return 0 end
    local reach = 0
    if f.dbGroups then
        for _, g in ipairs(Cfg().groups) do
            if g.enabled and HangsUnder(g) then
                local e = f.dbGroups[g.id]
                if e and (e.shownN or 0) > 0 then
                    local h = ((g.fontSize or 11) + 2) + math.abs(g.offsetY or 0)
                    if h > reach then reach = h end
                end
            end
        end
    end
    local ps = PackUp(f)
    if ps then
        local h = (ps:GetHeight() or 0) * (ps:GetScale() or 1) + math.abs(Cfg().packY or 0) + 3
        if h > reach then reach = h end
    end
    return reach
end

-- How far what sits BESIDE this plate's bar reaches past its left and
-- right edges, at the height of the bar's middle - the Sunder count on
-- the right edge, and any single group pinned left / right / centre - in
-- the bar's units; 0, 0 when nothing is there. The crosshair stops its
-- side lines short of it (Zac: "my crosshair line goes over my sunder
-- number").
-- WORKED OUT, NOT MEASURED: a nameplate's regions are restricted, and
-- GetLeft/GetRight on them throws ("Can't measure restricted regions").
-- So the reach comes from the group's own layout - where it is pinned,
-- its offsets and font size - and the width of the text it shows
-- (GetStringWidth measures the string, not the region, and is allowed).
function D.SideReach(f)
    if not (f and f.dbGroups) then return 0, 0 end
    local barW, barH = f._layW or 0, f._layH or 0
    local l, r = 0, 0
    for _, g in ipairs(Cfg().groups) do
        local a = g.attach or "center"
        if g.enabled and (g.mode or "single") ~= "row" and (a == "right" or a == "left" or a == "center") then
            local e = f.dbGroups[g.id]
            local fSize = GSize(g)
            -- only what crosses the middle of the bar, where the side lines run
            if e and (e.shownN or 0) > 0 and math.abs(g.offsetY or 0) <= (fSize + 2) / 2 + barH / 2 then
                local iconHalf = e.icon:IsShown() and (fSize + 2) / 2 or 0
                local mainW = e.main:IsShown() and (e.main:GetStringWidth() or 0) or 0
                local subW = e.sub:IsShown() and (e.sub:GetStringWidth() or 0) or 0
                local right, left
                if mainW > 0 then
                    right = mainW / 2
                    if subW > 0 and g.timerPos ~= "under" then right = right + (g.timerGap or 0) + subW end
                    left = mainW / 2
                else
                    right, left = subW / 2, subW / 2
                end
                right, left = math.max(right, iconHalf), math.max(left, iconHalf)
                -- the element's centre, from the bar's right edge (right),
                -- left edge (left) or middle (centre)
                local x = g.offsetX or 0
                local fromR, fromL
                if a == "right" then
                    fromR, fromL = x, barW + x
                elseif a == "left" then
                    fromR, fromL = x - barW, x
                else
                    fromR, fromL = x - barW / 2, barW / 2 + x
                end
                if fromR + right > r then r = fromR + right end
                if left - fromL > l then l = left - fromL end
            end
        end
    end
    return ceil(l), ceil(r)
end

-- Does the icon line under this plate reach the mob's target name
-- (right-aligned under the bar's right corner, nameW wide)? The debuff
-- row grows right from the left corner and the pack strip follows it;
-- a strip pinned to the right corner always does.
function D.UnderHitsName(f, nameW)
    if not (f and f.health) or (nameW or 0) <= 0 then return false end
    local used = f.dbUnderW or 0
    local ps = PackUp(f)
    if ps then
        if (Cfg().packAt or "after") == "bottomright" then return true end
        used = used + (Cfg().packX or 0) + (ps:GetWidth() or 0) * (ps:GetScale() or 1)
    end
    if used <= 0 then return false end
    local bw = f.health:GetWidth() or 0
    if bw <= 0 and NP.Dims then
        local d = NP.DB()
        bw = NP.Dims(f.isFriend and d.friendly or d.enemy) or 0
    end
    return used > bw - nameW - 4
end


-- ============================================================
-- PER-PLATE STATE
-- ============================================================
-- active[unit] = f (ZacUI's plate frame); per plate: f.dbAura (key ->
-- state), f.dbGroups (id -> element with slots)
local active, friendly, dirty = {}, {}, {}
local hasDirty = false
local running = false          -- between D.Start and D.Stop

-- what a group measures from: always the health bar's own edges and
-- corners - a group hanging under the plate drops further by whatever
-- is in the way right now (cast bar, threat strip and its text)
local function BarOf(f) return f.health or f end
-- A group hanging under the plate clears a cast bar, and sits level
-- with the threat strip on the other side. Only a row from the left
-- corner long enough to run into the strip (width = what it needs)
-- drops below the strip and its text instead.
local function UnderPad(f, group, width)
    if not HangsUnder(group) then return 0 end
    local cast = NP.CastDrop and NP.CastDrop(f) or 0
    local tw = NP.ThreatWidth and NP.ThreatWidth(f) or 0
    if tw > 0 then
        local bw = (f.health and f.health:GetWidth()) or 0
        if bw <= 0 and NP.Dims then
            local d = NP.DB()
            bw = NP.Dims(f.isFriend and d.friendly or d.enemy) or 0
        end
        local a = group.attach
        local need = (a == "bottomleft") and (width or 0) or bw
        if need > bw - tw then return (NP.UnderDrop and NP.UnderDrop(f)) or cast end
    end
    return cast
end

local function PositionGroup(f, group)
    local g = f.dbGroups[group.id]
    StyleElem(g, group)
    local ep, rp = AnchorPoints(group)
    g.icon:ClearAllPoints()
    g.icon:SetPoint(ep, BarOf(f, group), rp, group.offsetX or 0, (group.offsetY or 0) - UnderPad(f, group))
end

local function EnsurePlate(f)
    if not f.dbAura then f.dbAura = {} end
    if not f.dbGroups then f.dbGroups = {} end
    for _, group in ipairs(Cfg().groups) do
        local g = f.dbGroups[group.id]
        if not g then
            g = NewElem(f)
            g.slots = {}
            f.dbGroups[group.id] = g
        end
        PositionGroup(f, group)
        for _, s in ipairs(g.slots) do StyleElem(s, group) end
    end
end

local function EnsureSlot(f, group, i)
    local g = f.dbGroups[group.id]
    if not g.slots[i] then g.slots[i] = NewElem(f) end
    StyleElem(g.slots[i], group)
end

local _ak, _as = {}, {}
local function CollectActive(f, group)
    local n = 0
    local aura = f.dbAura
    for _, key in ipairs(group.members) do
        if MemberEnabled(group, key) then
            local st = aura[key]
            if st and st.present then
                n = n + 1
                _ak[n] = key
                _as[n] = st
            end
        end
    end
    return n
end

local function SetFS(fs, str)
    if str ~= fs.lastText then fs:SetText(str) fs.lastText = str end
    fs:Show()
end
local function HideFS(fs)
    if fs.lastText ~= "" then fs:SetText("") fs.lastText = "" end
    fs:Hide()
end
local function HideElem(e)
    if not e then return end
    e.icon:Hide() HideFS(e.main) HideFS(e.sub)
    e.iconBorder:Hide()
end

local function RenderInto(elem, key, st, group, now)
    local entry = CATALOG[key]
    local countStr
    if entry.stack and group.showCount then countStr = tostring(st.count or 1) end
    local timerStr
    if group.showTimer and st.expiration and st.expiration > 0 then
        local rem = st.expiration - now
        if rem < 0 then rem = 0 end
        timerStr = FmtTime(rem)
    end
    local cr, cg, cb = StackColor(st.count or 1)
    local tr, tg, tb = Col("text", "normal", 0.85, 0.85, 0.85)
    local beside = (group.timerPos ~= "under")
    local fSize, smallSize = GSize(group), TSize(group)
    local compact = fSize + 2
    local baseDrop = floor((fSize - smallSize) * 0.2 + 0.5)

    elem.icon:SetTexture(entry.icon)
    elem.icon:Show()
    elem.iconBorder:Show()
    elem.main:ClearAllPoints() elem.sub:ClearAllPoints()
    elem.icon:SetSize(compact, compact)
    if countStr and timerStr then
        elem.main:SetTextColor(cr, cg, cb) SetFS(elem.main, countStr)
        elem.sub:SetTextColor(tr, tg, tb) SetFS(elem.sub, timerStr)
        elem.main:SetPoint("CENTER", elem.icon, "CENTER", 0, 0)
        if beside then
            elem.sub:SetPoint("BOTTOMLEFT", elem.main, "BOTTOMRIGHT", (group.timerGap or 0), baseDrop)
        else
            elem.sub:SetPoint("TOP", elem.main, "BOTTOM", 0, -1)
        end
    elseif countStr then
        elem.main:SetPoint("CENTER", elem.icon, "CENTER", 0, 0)
        elem.main:SetTextColor(cr, cg, cb) SetFS(elem.main, countStr)
        HideFS(elem.sub)
    elseif timerStr then
        HideFS(elem.main)
        elem.sub:SetPoint("CENTER", elem.icon, "CENTER", 0, 0)
        elem.sub:SetTextColor(tr, tg, tb) SetFS(elem.sub, timerStr)
    else
        HideFS(elem.main) HideFS(elem.sub)
    end
end

local ROW_MAX = 10

-- The once-a-second pass over a row that is up: only the time left on
-- each icon moves (where the timer sits and what else shows only change
-- with the auras, which redraw the row in full).
local function RowTimers(g, group, now)
    if not group.showTimer then return end
    local n = g.shownN or 0
    if n > ROW_MAX then n = ROW_MAX end
    for i = 1, n do
        local s = g.slots[i]
        local st = s and s._st
        if st and st.present and st.expiration and st.expiration > 0 then
            local rem = st.expiration - now
            if rem < 0 then rem = 0 end
            SetFS(s.sub, FmtTime(rem))
        end
    end
end

local function RenderGroup(f, group, now)
    local g = f.dbGroups and f.dbGroups[group.id]
    if not g then return end
    if not group.enabled then
        HideElem(g)
        for _, s in ipairs(g.slots) do HideElem(s) end
        g.activeKey, g.expiration = nil, 0
        g.shownN = 0
        return
    end
    local n = CollectActive(f, group)
    g.shownN = n
    local anchorTo = BarOf(f)

    if (group.mode or "single") == "row" then
        HideElem(g)
        g.activeKey, g.expiration = nil, 0
        -- oldest applied first; icons hold their slot as neighbours expire
        for i = 2, n do
            local ak, as = _ak[i], _as[i]
            local fa = as.firstSeen or 0
            local j = i - 1
            while j >= 1 and (_as[j].firstSeen or 0) > fa do
                _ak[j + 1] = _ak[j] _as[j + 1] = _as[j]
                j = j - 1
            end
            _ak[j + 1] = ak _as[j + 1] = as
        end
        if n > ROW_MAX then n = ROW_MAX end
        local sz = GSize(group) + 2
        local step = sz + 2
        local ep, rp = AnchorPoints(group)
        local dir = group.growDir or "right"
        local horiz = (dir == "left" or dir == "right")
        local sign = (dir == "left" or dir == "down") and -1 or 1
        -- half an icon of lead-in so the offset lands on the row's leading
        -- edge - none from a corner, which already is the leading edge
        local lead = IsCorner(group) and 0 or sz / 2
        local baseX = (group.offsetX or 0) + (horiz and (sign * lead) or 0)
        -- the room this row takes (and the raid-pack strip after it)
        local need = (group.offsetX or 0) + n * step
        local ps = f._zuiPackStrip
        if ps and ps:IsShown() and (ps._zuiN or 0) > 0 and (Cfg().packAt or "after") == "after" then
            need = need + (Cfg().packX or 0) + (ps:GetWidth() or 0) * (ps:GetScale() or 1)
        end
        local pad = UnderPad(f, group, need)
        f.dbUnderPad = pad
        local baseY = (group.offsetY or 0) + (horiz and 0 or (sign * lead)) - pad
        for i = 1, n do
            if not g.slots[i] then EnsureSlot(f, group, i) end
            local s = g.slots[i]
            local off = sign * (i - 1) * step
            s.icon:ClearAllPoints()
            s.icon:SetPoint(ep, anchorTo, rp, baseX + (horiz and off or 0), baseY + (horiz and 0 or off))
            RenderInto(s, _ak[i], _as[i], group, now)
            s._st = _as[i]
        end
        for i = n + 1, #g.slots do HideElem(g.slots[i]) g.slots[i]._st = nil end
        -- the row under the bar from its left corner: where it ends, for
        -- the raid-pack strip to follow on and the target name to check
        if group.attach == "bottomleft" and dir == "right" then
            local x = (group.offsetX or 0) + n * step
            f.dbUnderW = n > 0 and (x - 2) or 0
            local m = f.dbUnderEnd
            if not m then
                m = CreateFrame("Frame", nil, f)
                m:SetSize(1, 1)
                f.dbUnderEnd = m
            end
            local y = (group.offsetY or 0) - pad
            if m._x ~= x or m._y ~= y then
                m._x, m._y = x, y
                m:ClearAllPoints()
                m:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", n > 0 and (x - 2) or 0, y)
            end
        end
        return
    end

    for _, s in ipairs(g.slots) do HideElem(s) end
    if n == 0 then
        HideElem(g)
        g.activeKey, g.expiration = nil, 0
        return
    end
    local key, st = _ak[1], _as[1]
    g.activeKey = key
    g.expiration = st.expiration or 0
    local ep, rp = AnchorPoints(group)
    if group.showIcon then
        g.icon:ClearAllPoints()
        g.icon:SetPoint(ep, anchorTo, rp, group.offsetX or 0, (group.offsetY or 0) - UnderPad(f, group))
        RenderInto(g, key, st, group, now)
    else
        -- text only (Zac's sunder count): the number sits on the offset
        g.icon:Hide() g.iconBorder:Hide()
        local entry = CATALOG[key]
        local countStr
        if entry.stack and group.showCount then countStr = tostring(st.count or 1)
        elseif entry.label and group.showCount then countStr = entry.label end
        local timerStr
        if group.showTimer and st.expiration and st.expiration > 0 then
            local rem = st.expiration - now
            if rem < 0 then rem = 0 end
            timerStr = FmtTime(rem)
        end
        local cr, cg, cb = StackColor(st.count or 1)
        local tr, tg, tb = Col("text", "normal", 0.85, 0.85, 0.85)
        if countStr then
            g.main:ClearAllPoints()
            g.main:SetPoint(ep, anchorTo, rp, group.offsetX or 0, group.offsetY or 0)
            g.main:SetTextColor(cr, cg, cb)
            SetFS(g.main, countStr)
            if timerStr then
                local baseDrop = floor((GSize(group) - TSize(group)) * 0.2 + 0.5)
                g.sub:ClearAllPoints()
                g.sub:SetPoint("BOTTOMLEFT", g.main, "BOTTOMRIGHT", (group.timerGap or 0), baseDrop)
                g.sub:SetTextColor(tr, tg, tb)
                SetFS(g.sub, timerStr)
            else
                HideFS(g.sub)
            end
        elseif timerStr then
            g.main:ClearAllPoints()
            g.main:SetPoint(ep, anchorTo, rp, group.offsetX or 0, group.offsetY or 0)
            g.main:SetTextColor(tr, tg, tb)
            SetFS(g.main, timerStr)
            HideFS(g.sub)
        else
            HideFS(g.main) HideFS(g.sub)
        end
    end
end

-- ============================================================
-- THE OVERPOWER WINDOW now lives in core (ns.Overpower): one window per
-- mob that dodged you, read by both the HUD's buff bar and the plate
-- row, so the two can never show different timers. Kept for anything
-- that still asks this module.
-- ============================================================
local ev = CreateFrame("Frame")
function D.OverpowerProc()
    return ns.Overpower.Left() > 0
end

-- ============================================================
-- SCAN / RENDER
-- ============================================================
local function ScanPlate(unit)
    local f = active[unit]
    if not f then return false end
    local aura = f.dbAura
    for _, st in pairs(aura) do
        st._wp, st._wc, st._we = st.present, st.count, st.expiration
        st.present = false
    end
    local now = GetTime()
    for i = 1, 40 do
        local nm, _, count, _, duration, expiration = UnitDebuff(unit, i)
        if not nm then break end
        local key = byName[nm]
        if key then
            local st = aura[key]
            if not st then st = {} aura[key] = st end
            if not st.firstSeen then
                if duration and duration > 0 and expiration and expiration > 0 then
                    st.firstSeen = expiration - duration
                else
                    st.firstSeen = now
                end
            end
            st.present = true
            st.count = count or 1
            st.expiration = expiration or 0
        end
    end
    for _, st in pairs(aura) do if not st.present then st.firstSeen = nil end end

    local changed = false
    for _, st in pairs(aura) do
        if st.present ~= st._wp or (st.present and (st.count ~= st._wc or st.expiration ~= st._we)) then
            changed = true
        end
        st._wp, st._wc, st._we = nil, nil, nil
    end
    return changed
end

local function RescanAndRender(unit, now)
    local f = active[unit]
    if not f then return end
    if ScanPlate(unit) or f.dbForce then
        f.dbForce = nil
        for _, group in ipairs(Cfg().groups) do
            local g = f.dbGroups[group.id]
            if g then g.lastSec = nil g.rowSec = nil end
            RenderGroup(f, group, now)
        end
        -- the under-bar icons came or went: the name and (on my target)
        -- the crosshair's bottom line move to clear them, or close up
        local reach, w = D.UnderReach(f), f.dbUnderW or 0
        local moved = false
        if reach ~= f.dbUnderReach or w ~= f.dbUnderWas then
            f.dbUnderReach, f.dbUnderWas = reach, w
            moved = true
        end
        -- beside the bar (the Sunder count): only my target's plate has
        -- a crosshair to move, so only it is measured
        if f.unit and UnitIsUnit(f.unit, "target") then
            local sl, sr = D.SideReach(f)
            if sl ~= f.dbSideL or sr ~= f.dbSideR then
                f.dbSideL, f.dbSideR = sl, sr
                moved = true
            end
        end
        if moved and NP.UnderContentChanged then NP.UnderContentChanged(f) end
    end
end

local function Tick()
    local now = GetTime()
    local secNow = floor(now)
    if hasDirty then
        hasDirty = false
        local budget = 12
        for unit in pairs(dirty) do
            dirty[unit] = nil
            RescanAndRender(unit, now)
            budget = budget - 1
            if budget <= 0 then
                if next(dirty) then hasDirty = true end
                break
            end
        end
    end
    local groups = Cfg().groups
    for _, f in pairs(active) do
        local pg = f.dbGroups
        if pg then
            for _, group in ipairs(groups) do
                if group.enabled and group.showTimer then
                    local g = pg[group.id]
                    if g then
                        if (group.mode or "single") == "row" then
                            -- an empty row has no timers; a full one only
                            -- has its timer texts to move on the second
                            if g.rowSec ~= secNow and (g.shownN or 0) > 0 then
                                g.rowSec = secNow
                                RowTimers(g, group, now)
                            end
                        elseif g.activeKey and g.expiration > 0 then
                            local sec = ceil(g.expiration - now)
                            if sec ~= g.lastSec then g.lastSec = sec RenderGroup(f, group, now) end
                        end
                    end
                end
            end
        end
    end
end

-- ============================================================
-- PLATES COMING AND GOING
-- ============================================================
local function TracksUnit(unit)
    return (UnitCanAttack("player", unit) or not UnitIsFriend("player", unit)) and true or false
end

local function HideAll(f)
    if f.dbGroups then
        for _, g in pairs(f.dbGroups) do
            HideElem(g)
            for _, s in ipairs(g.slots) do HideElem(s) end
            g.activeKey, g.expiration = nil, 0
        end
    end
end

-- NP_Core calls these from its own plate lifecycle (the plate is dressed
-- by then); they do nothing while the module is off
function D.OnAdded(unit)
    if not running then return end
    local f = NP.activePlates and NP.activePlates[unit]
    if not f then return end
    if not TracksUnit(unit) then
        if active[unit] then D.OnRemoved(unit) end
        friendly[unit] = true
        return
    end
    friendly[unit] = nil
    active[unit] = f
    f.dbForce = true
    EnsurePlate(f)
    dirty[unit] = true
    hasDirty = true
end

function D.OnRemoved(unit)
    local f = active[unit]
    if f then
        HideAll(f)
        if f.dbAura then wipe(f.dbAura) end
    end
    active[unit] = nil
    friendly[unit] = nil
    dirty[unit] = nil
end

function D.MarkDirty(unit)
    if active[unit] then dirty[unit] = true hasDirty = true end
end

-- a cast bar coming or going under the plate: the groups hanging under
-- it re-anchor to the new lowest thing and redraw
if NP.OnUnderBarChange then
    NP.OnUnderBarChange(function(f)
        local unit = f.unit
        if not (unit and active[unit] == f and f.dbGroups) then return end
        for _, group in ipairs(Cfg().groups) do
            if HangsUnder(group) and f.dbGroups[group.id] then PositionGroup(f, group) end
        end
        f.dbForce = true
        dirty[unit] = true hasDirty = true
    end)
end

function D.RefreshAll()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    for unit in pairs(active) do D.OnRemoved(unit) end
    for _, p in ipairs(C_NamePlate.GetNamePlates()) do
        local unit = p.namePlateUnitToken
        if unit then D.OnAdded(unit) end
    end
end

-- every setting change: catalog, positions, sizes, then a full redraw
function D.Apply()
    ResolveCatalog()
    for unit, f in pairs(active) do
        EnsurePlate(f)
        f.dbForce = true
        dirty[unit] = true
    end
    hasDirty = true
    if NP.Preview and NP.Preview.Refresh then NP.Preview.Refresh() end
end

-- The preview plate (NP_Preview): every group drawn once with a sample
-- state - a 5-stack Sunder with 25s left, Faerie Fire, a Taunt, the
-- Overpower window, Disarm, and the Execute cue - laid out from the
-- live settings. Not in `active`, so the tick never touches it.
-- a sample plate that shows no debuffs (a friendly one in the preview)
function D.ClearPreview(f)
    if f.dbGroups then HideAll(f) end
    f.dbUnderW = 0
end

function D.PreviewPlate(f)
    if not Cfg().enabled then
        if f.dbGroups then HideAll(f) end
        return
    end
    if not next(byName) then ResolveCatalog() end
    EnsurePlate(f)
    local now = GetTime()
    local aura = f.dbAura
    wipe(aura)
    local function Put(key, count, left)
        aura[key] = { present = true, count = count or 1, expiration = left and (now + left) or 0, firstSeen = now }
    end
    Put("sunder", 5, 25)
    Put("faeriefire", 1, 32)
    Put("cor", 1, 90)
    Put("taunt", 1, 3)
    Put("disarm", 1, 8)
    for _, group in ipairs(Cfg().groups) do RenderGroup(f, group, now) end
end

-- ============================================================
-- START / STOP
-- ============================================================
local ticker
ev:SetScript("OnEvent", function(_, event, a1)
    if event == "UNIT_AURA" then
        D.MarkDirty(a1)
    elseif event == "UNIT_FACTION" then
        if friendly[a1] or active[a1] then D.OnAdded(a1) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        D.RefreshAll()
    end
end)

function D.Start()
    if not Cfg().enabled then D.Stop() return end
    running = true
    ResolveCatalog()
    -- plates come and go through NP_Core (D.OnAdded / D.OnRemoved)
    for _, e in ipairs({ "UNIT_AURA", "UNIT_FACTION", "PLAYER_ENTERING_WORLD" }) do
        ev:RegisterEvent(e)
    end
    if not ticker then
        ticker = C_Timer.NewTicker(0.2, Tick)
        if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(ticker, "np.debuffs") end
    end
    D.RefreshAll()
end

function D.Stop()
    running = false
    ev:UnregisterAllEvents()
    if ticker then ticker:Cancel() ticker = nil end
    for unit in pairs(active) do D.OnRemoved(unit) end
    wipe(dirty) hasDirty = false
end

function D.SetEnabled(on)
    Cfg().enabled = on and true or false
    if on then D.Start() else D.Stop() end
end

function D.ResetGroups()
    Cfg().groups = DefaultGroups()
    D.Apply()
end

function D.AddCustom(spellID, stack)
    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 then return nil, "invalid" end
    local name = GetSpellInfo(spellID)
    if not name then return nil, "unknown" end
    local key = "cd" .. spellID
    local c = Cfg()
    c.custom[key] = { spellID = spellID, stack = stack and true or false }
    D.Apply()
    return key, name
end

function D.RemoveCustom(key)
    local c = Cfg()
    c.custom[key] = nil
    for _, g in ipairs(c.groups) do
        for i = #g.members, 1, -1 do if g.members[i] == key then table.remove(g.members, i) end end
        if g.memberOn then g.memberOn[key] = nil end
    end
    CATALOG[key] = nil
    D.Apply()
end

-- Readycheck's own copy of this must not draw the same icons twice:
-- while this module is on, Readycheck's nameplate auras are switched
-- off (its setting is left as it was when this is off again).
local function QuietReadycheck()
    local RC = _G.Readycheck
    local NA = RC and RC.nameplateAuras
    if not (NA and NA.cfg) then return end
    local c = NA.cfg()
    if Cfg().enabled and c.enabled then
        c.enabled = false
        if NA.Stop then NA:Stop() end
        if RC.SaveConfigurationToProfile then RC:SaveConfigurationToProfile() end
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    local d = DBRoot()
    if d and d.enabled ~= false then D.Start() end
    C_Timer.After(2, QuietReadycheck)
end)
