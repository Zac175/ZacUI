-- ============================================================================
-- ZacUF - Groups.lua
-- Party and raid frames via Blizzard's SecureGroupHeaderTemplate.
--
-- The header owns unit assignment and show/hide (never touched in combat). For
-- each child it creates, a secure snippet sets size + click behavior, then
-- bridges to insecure Lua via CallMethod so we can build visuals exactly once.
-- Each child re-registers its OWN unit's events on reassignment, so a raid
-- frame only ever works for the one unit it currently shows.
--
-- A "mover" handle (shown in move mode) lets the whole header be dragged to a
-- new position even when the group is empty.
-- ============================================================================
local ADDON, ns = ...
-- ZacUI's shared services (roster), through the global: this part keeps
-- a private namespace
local Z = _G.ZacUI

-- (Re)bind a child's unit events for whatever unit it currently shows.
local function bindUnit(button)
    local unit = button:GetAttribute("unit")
    button.unit = unit
    if not unit then return end
    ns.RegisterFrameEvents(button)
    ns.UpdateAll(button)
end

-- Children eligible for range fading; populated once per child in styleChild,
-- consumed by the ticker at the bottom of this file.
local rangeButtons = {}
local function registerRangeButton(button)
    rangeButtons[#rangeButtons + 1] = button
end

-- Click wiring is the ONLY protected part of child styling (RegisterForClicks
-- on a protected frame is blocked in combat), so it lives apart from the rest
-- and gets deferred to PLAYER_REGEN_ENABLED when a child is built mid-fight
-- (someone joining the group in combat makes the secure header spawn a child
-- right then).
local function wireClicks(button)
    button:RegisterForClicks("AnyUp")
    -- Click-cast fallback: if Clique loaded *after* this header was created, the
    -- secure ref wasn't set when this child spawned, so the secure snippet in
    -- initialConfigFunction did nothing. Register insecurely here instead.
    -- Skipped when the secure path already handled it, to avoid double registration.
    if not button:GetParent().__cliqueSecure then
        ClickCastFrames = ClickCastFrames or {}
        ClickCastFrames[button] = true
    end
end

local pendingClicks = {}
local clickWaiter = CreateFrame("Frame")
clickWaiter:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    for button in next, pendingClicks do
        wireClicks(button)
    end
    wipe(pendingClicks)
end)

-- Build + wire a single child button (runs once, guarded). Everything here is
-- combat-safe - textures, fontstrings, scripts, event registration - EXCEPT
-- the click wiring, which defers itself when needed.
local function styleChild(button)
    if button.__leanInit then return end
    button.__leanInit = true
    button.isGroupUnit = true   -- ns.GetUnitFrame prefers group slots, like LibGetFrame

    ns.UI:FrameBackdrop(button, button.cfg.bgColor, button.cfg.borderColor)
    if InCombatLockdown() then
        pendingClicks[button] = true
        clickWaiter:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        wireClicks(button)
    end
    ns.BuildElements(button)
    registerRangeButton(button)

    button:SetScript("OnEvent", function(self, event, arg1, arg2)
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            ns.UpdateHealth(self)
        elseif event == "UNIT_HEAL_PREDICTION" then
            ns.UpdateHealPrediction(self)
        elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
            ns.UpdatePower(self)
        elseif event == "UNIT_NAME_UPDATE" then
            ns.UpdateName(self)
        elseif event == "UNIT_AURA" then
            ns.AuraDirty(self, arg2)     -- marks it; arg2 (the payload) lets a buff-only tick skip the walk
        elseif event == "UNIT_FLAGS" or event == "UNIT_FACTION"
            or event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED"
            or event == "PLAYER_FLAGS_CHANGED"
            or event == "INCOMING_RESURRECT_CHANGED" then
            ns.UpdateIndicators(self)
        elseif event == "RAID_TARGET_UPDATE" then
            ns.UpdateRaidMarker(self)
        elseif string.find(event, "SPELLCAST", 1, true) then
            ns.CastbarEvent(self, event, arg1, arg2)
        else
            ns.UpdateAll(self)
        end
    end)

    -- Secure template uses OnAttributeChanged internally, so HOOK to catch unit
    -- reassignment (never overwrite).
    button:HookScript("OnAttributeChanged", function(self, name)
        if name == "unit" then bindUnit(self) end
    end)
    button:HookScript("OnShow", function(self) ns.UpdateAll(self) end)
    button:HookScript("OnEnter", function(self) self.hovered = true;  ns.UpdatePvP(self) ns.GroupBorder(self) end)
    button:HookScript("OnLeave", function(self) self.hovered = false; ns.UpdatePvP(self) ns.GroupBorder(self) end)
    -- (match pass: the target's white border follows target changes)
    if ns.GroupBorderWatch then ns.GroupBorderWatch() end

    bindUnit(button)
end
-- (the tank frames' header styles its children the same way: Tanks.lua)
ns.StyleGroupChild = styleChild

-- The drag handle. Parented to UIParent (not the host) so it stays visible and
-- clickable when the group is empty and the host has zero-ish size. `host` is the
-- position-owning frame (the container); `spanW` widens the handle to sit over
-- the whole grouped block instead of a single column.
local function ensureMover(host, kind, cfg, spanW)
    if host.mover then return host.mover end
    local m = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    m:SetSize(math.max(spanW or cfg.width, 90), 22)
    m:SetPoint("BOTTOMLEFT", host, "TOPLEFT", 0, 2)
    m:SetFrameStrata("HIGH")
    m:SetMovable(true)
    m:SetClampedToScreen(true)   -- the handle (and thus the group's anchor) can never leave the screen
    ns.UI:Backdrop(m, ns.db.colors.background, { 0.85, 0.65, 0.25, 1 })
    m.label = ns.UI:FS(m, 11)
    m.label:SetPoint("CENTER")
    m.label:SetText((kind == "party") and "Party (drag)" or "Raid (drag)")
    m.label:SetTextColor(1, 0.82, 0)
    m:EnableMouse(true)
    m:RegisterForDrag("LeftButton")
    m:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then self:StartMoving() end
    end)
    m:SetScript("OnMouseDown", function(self)
        if ns.SelectMoveFrame then ns.SelectMoveFrame(kind) end
    end)
    m:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- The handle's BOTTOMLEFT sits at the container's TOPLEFT (+2). Derive the
        -- container's TOPLEFT in UIParent-TOPLEFT coordinates from the HANDLE (which
        -- always has a size), so this works even when the group is empty.
        local left, bottom = self:GetLeft(), self:GetBottom()
        if left and bottom then
            local x = left - UIParent:GetLeft()
            local y = (bottom - 2) - UIParent:GetTop()
            if ns.SnapValue then x, y = ns.SnapValue(x), ns.SnapValue(y) end
            cfg.point, cfg.x, cfg.y = "TOPLEFT", x, y
            if not InCombatLockdown() then
                host:ClearAllPoints()
                host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
            end
        end
        self:ClearAllPoints()
        self:SetPoint("BOTTOMLEFT", host, "TOPLEFT", 0, 2)
        if ns.UpdateMocks then ns.UpdateMocks() end
        if ns.RefreshMoveDialog then ns.RefreshMoveDialog() end
    end)
    m:Hide()
    host.mover = m
    return m
end

-- Secure visibility: which group types each header shows in. The roster
-- attributes alone don't hide a party header inside a raid (Blizzard falls
-- through to its showParty branch), so a visibility state driver gates it.
local function visibilityCond(kind, cfg)
    if kind == "raid" then
        return "[group:raid] show; hide"                       -- raid only
    elseif cfg.showInRaid then
        return "[group] show; hide"                            -- party AND raid
    else
        -- [group:party] is also true inside a raid (your subgroup counts as a
        -- party), so test raid first and hide explicitly. Otherwise both the
        -- party and raid headers show at once when in a raid.
        return "[group:raid] hide; [group:party] show; hide"  -- party only, never in a raid
    end
end

-- ----------------------------------------------------------------------------
-- One secure group header (a single subgroup in grouped mode, or the whole
-- roster in flat mode). Parented to the container so moving the container moves
-- every header with it.
-- ----------------------------------------------------------------------------
local function buildHeader(name, kind, cfg, container, groupFilter)
    local h = CreateFrame("Frame", name, container, "SecureGroupHeaderTemplate")
    h:SetClampedToScreen(true)

    -- Click-casting: register each child through Clique's own secure snippet via a
    -- frame ref to its header (global ClickCastHeader). Marks the header so we
    -- don't also register insecurely.
    if ClickCastHeader then
        SecureHandlerSetFrameRef(h, "clickcast_header", ClickCastHeader)
        h.__cliqueSecure = true
    end

    -- Insecure bridge the per-child secure snippet calls. `self` is THIS header,
    -- so per-group headers each build/style their own children.
    h.LeanStyleChild = function(self, childName)
        local child = _G[childName]
        if child then
            child.cfg = cfg
            styleChild(child)
        end
    end

    h:SetAttribute("template", "SecureUnitButtonTemplate,BackdropTemplate")
    h:SetAttribute("showSolo", false)
    h:SetAttribute("showPlayer", cfg.showPlayer and true or false)
    if kind == "party" then
        h:SetAttribute("showParty", true)
        h:SetAttribute("showRaid", false)
    else
        h:SetAttribute("showParty", false)
        h:SetAttribute("showRaid", true)
    end
    h:SetAttribute("groupFilter", groupFilter)

    -- Secure per-child snippet: size + clicks, then bridge to styling.
    h:SetAttribute("initialConfigFunction", ns.ChildConfigSnippet(cfg))

    return h
end

-- The per-child snippet, rebuilt whenever the size changes so children the
-- header makes later come out at the new size. Sizes keep two decimals:
-- a raid fitted to the chat window's width is rarely a whole number.
function ns.ChildConfigSnippet(cfg)
    return ([[
        self:SetWidth(%.2f)
        self:SetHeight(%.2f)
        self:SetAttribute("*type1", "target")
        self:SetAttribute("*type2", "togglemenu")
        self:GetParent():CallMethod("LeanStyleChild", self:GetName())

        local cc = self:GetParent():GetFrameRef("clickcast_header")
        if cc then
            cc:SetAttribute("clickcast_button", self)
            cc:RunAttribute("clickcast_register")
        end
    ]]):format(cfg.width, cfg.height)
end

-- Cheap, re-appliable layout attributes: row growth, sort, and (flat raid only)
-- the header's own column chunking. Structural attrs (template / filter / child
-- size) are set once in buildHeader. Safe out of combat; callers guard.
local function applyHeaderLayout(h, kind, cfg, grouped)
    local growUp = (cfg.growth == "UP")
    -- The GROUP header's child layout only understands TOP / BOTTOM / LEFT / RIGHT
    -- (getRelativePointAnchor); a corner like TOPLEFT collapses to CENTER and stairs
    -- the units diagonally. Each per-group header auto-sizes to one column and
    -- centers its frames on that width, so TOP/BOTTOM lands them in the right column.
    local point, xOff, yOff = growUp and "BOTTOM" or "TOP", 0, growUp and (cfg.spacing or 6) or -(cfg.spacing or 6)
    -- in ZacUI's raid chat the party sits in one row across the chat box
    -- (FitPartyToChat), not a column of bars the box's whole width
    if kind == "party" and ns.partyChatRow then
        point, xOff, yOff = "LEFT", ns.partyChatRow, 0
    end
    -- Switching between a column and a row: the header re-anchors each
    -- child to the one before it but never drops the anchor the old layout
    -- gave it, so a child hung BELOW its neighbour and now also BESIDE it
    -- stairs off diagonally (2026-10-23, the party in chat). Children
    -- lose their old anchors first; the header then sets the new ones.
    -- The point goes in first: every re-lay after it (one per attribute)
    -- then uses the new anchor, which a later re-lay replaces rather than
    -- adds to.
    if h:GetAttribute("point") ~= point or h:GetAttribute("xOffset") ~= xOff
       or h:GetAttribute("yOffset") ~= yOff then
        for _, child in ipairs({ h:GetChildren() }) do child:ClearAllPoints() end
        h:SetAttribute("point", point)
        h:SetAttribute("xOffset", xOff)
        h:SetAttribute("yOffset", yOff)
    end
    h:SetAttribute("sortMethod", (cfg.sortMethod == "Name") and "NAME" or "INDEX")
    h:SetAttribute("sortDir", (cfg.sortDir == "Descending") and "DESC" or "ASC")
    if (not grouped) and kind == "raid" then
        -- one header owns every group -> chunk by unit count into columns
        h:SetAttribute("unitsPerColumn", cfg.unitsPerColumn)
        h:SetAttribute("maxColumns", cfg.maxColumns)
        h:SetAttribute("columnSpacing", cfg.columnSpacing)
        h:SetAttribute("columnAnchorPoint", (cfg.columnGrowth == "LEFT") and "RIGHT" or "LEFT")
        h:SetAttribute("groupBy", nil)
        h:SetAttribute("groupingOrder", nil)
    end
end

-- ----------------------------------------------------------------------------
-- Spawn a party or raid group. In grouped raid mode each subgroup gets its OWN
-- secure header so every group owns a column even when partially filled - a
-- single header chunks by unit count, packing e.g. a 1-man group 1 and a 3-man
-- group 2 into the same column. Party (and raid with grouping off) use one
-- header. Either way an insecure container owns the position + drag handle, so
-- the mover / mock / restyle code is identical for both layouts.
-- ----------------------------------------------------------------------------
function ns.SpawnHeader(kind)
    if ns.frames[kind] then return ns.frames[kind] end
    local cfg = ns.db[kind]
    local grouped = (kind == "raid") and cfg.groupBy and true or false

    local container = CreateFrame("Frame", "ZacUF_" .. kind .. "Header", UIParent)
    container:SetMovable(true)
    container:SetSize(cfg.width, cfg.height)
    container:ClearAllPoints()
    container:SetPoint(cfg.point or "TOPLEFT", UIParent, cfg.point or "TOPLEFT", cfg.x or 0, cfg.y or 0)
    container.grouped = grouped
    container.headers = {}

    -- Lay each subgroup header into a grid: one column per group, wrapping to a
    -- new block-row every `maxColumns` groups (Max columns = 4 -> groups 1-4 across
    -- the top, 5-8 below). Flat / party just pins the single header at the corner.
    local function positionHeaders()
        local colSpacing = cfg.columnSpacing or 0
        local dir    = (cfg.columnGrowth == "LEFT") and -1 or 1
        local growUp = (cfg.growth == "UP")
        local anchor = growUp and "BOTTOMLEFT" or "TOPLEFT"
        if grouped then
            local cols   = math.max(1, math.min(8, cfg.maxColumns or 8))
            -- Block-row height = one full 5-man column (5 units, 4 gaps) plus a
            -- columnSpacing gap, so the vertical gap between wrapped rows matches
            -- the horizontal gap between group columns.
            -- (Classic WoW UI, Kit.lua's raid kit: each group's column
            -- starts under its gold "Group N" title - titleH of room, 0
            -- under every other look, so nothing else moves a pixel)
            local Kit = ns.Kit
            local titleH = (kind == "raid" and Kit and Kit.RaidTitleH and Kit.RaidTitleH(cfg, grouped)) or 0
            local blockH = 5 * cfg.height + 4 * (cfg.spacing or 0) + colSpacing + titleH
            local spots = titleH > 0 and {} or nil
            for gi = 0, 7 do
                local h = container.headers[gi + 1]
                if h then
                    local col = gi % cols
                    local row = math.floor(gi / cols)
                    local x = dir * col * (cfg.width + colSpacing)
                    local y = growUp and (row * blockH) or -(row * blockH)
                    h:ClearAllPoints()
                    h:SetPoint(anchor, container, anchor, x, y - titleH)
                    if spots then spots[gi + 1] = { x, y } end
                end
            end
            if kind == "raid" and Kit and Kit.RaidTitles then Kit.RaidTitles(container, cfg, spots) end
        else
            local h = container.headers[1]
            if h then
                h:ClearAllPoints()
                h:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            end
        end
    end

    -- Build the header(s). Header names feed the auto-generated child names
    -- (oUF_ZacUFRaidG2UnitButton3, ...), which match LibGetFrame's generic
    -- ^oUF_.-Raid / ^oUF_.-Party priority patterns - that is what makes
    -- WeakAuras' unit-frame anchoring pick these children deterministically
    -- instead of falling through to its unordered last-resort pick.
    local nameBase = "oUF_ZacUF" .. ((kind == "party") and "Party" or "Raid")
    if grouped then
        for g = 1, 8 do
            local h = buildHeader(nameBase .. "G" .. g, kind, cfg, container, tostring(g))
            applyHeaderLayout(h, kind, cfg, true)
            container.headers[g] = h
        end
    else
        local h = buildHeader(nameBase .. "Main", kind, cfg, container, "1,2,3,4,5,6,7,8")
        applyHeaderLayout(h, kind, cfg, false)
        container.headers[1] = h
    end

    positionHeaders()

    -- Pre-instantiate every child a header can ever need NOW, at spawn, out of
    -- combat: with a negative startingIndex the secure header's own math
    -- (numDisplayed = unitCount - (startingIndex - 1)) builds its full child
    -- complement even on an empty roster. A player joining mid-combat then
    -- reuses an existing, fully styled child instead of running
    -- initialConfigFunction + styling in combat - which trips
    -- ADDON_ACTION_BLOCKED on RegisterForClicks. Headers must be visible for
    -- their update to run, so this happens before the visibility driver takes
    -- over.
    local prebuild = grouped and 4 or ((kind == "party") and 4 or 39)
    for _, h in ipairs(container.headers) do
        h:Show()
        h:SetAttribute("startingIndex", -prebuild)
        h:SetAttribute("startingIndex", 1)
        RegisterStateDriver(h, "visibility", visibilityCond(kind, cfg))
    end

    -- Handle spans the whole grouped block so it's easy to grab.
    local spanW
    if grouped then
        local cols = math.max(1, math.min(8, cfg.maxColumns or 8))
        spanW = cols * cfg.width + (cols - 1) * (cfg.columnSpacing or 0)
    end
    ensureMover(container, kind, cfg, spanW)

    -- Live restyle: re-apply media/colors to every child, re-apply the cheap
    -- layout attrs (sort + row/column spacing) and re-grid the headers, and
    -- show/hide the mover. Header COUNT (toggling group-by), child size, and
    -- showPlayer are structural and take effect on /reload.
    -- Child size, live (out of combat): resize every child, re-arm the
    -- snippet for children made later, and nudge each header to re-lay.
    container.ApplySize = function(self)
        if InCombatLockdown() then return false end
        for _, h in ipairs(self.headers) do
            local changed = false
            for _, child in ipairs({ h:GetChildren() }) do
                local w, ht = child:GetWidth(), child:GetHeight()
                if math.abs((w or 0) - cfg.width) > 0.01 or math.abs((ht or 0) - cfg.height) > 0.01 then
                    child:SetSize(cfg.width, cfg.height)
                    changed = true
                end
            end
            if changed or self._sizeW ~= cfg.width or self._sizeH ~= cfg.height then
                h:SetAttribute("initialConfigFunction", ns.ChildConfigSnippet(cfg))
                h:SetAttribute("point", h:GetAttribute("point"))
            end
        end
        self._sizeW, self._sizeH = cfg.width, cfg.height
        if self.mover then
            local span = cfg.width
            if grouped then
                local cols = math.max(1, math.min(8, cfg.maxColumns or 8))
                span = cols * cfg.width + (cols - 1) * (cfg.columnSpacing or 0)
            end
            self.mover:SetWidth(math.max(span, 90))
        end
        return true
    end
    container._sizeW, container._sizeH = cfg.width, cfg.height

    container.LeanRestyle = function(self)
        if not InCombatLockdown() then self:ApplySize() end
        for _, h in ipairs(self.headers) do
            if not InCombatLockdown() then
                applyHeaderLayout(h, kind, cfg, grouped)
                RegisterStateDriver(h, "visibility", visibilityCond(kind, cfg))
            end
            for _, child in ipairs({ h:GetChildren() }) do
                if child.__leanInit then
                    child.__rangeFaded = nil   -- re-applied at the next range check (its opacity may have changed)
                    ns.UI:FrameBackdrop(child, child.cfg.bgColor, child.cfg.borderColor)
                    ns.StyleElements(child)
                    ns.RegisterFrameEvents(child)
                    ns.UpdateAll(child)
                    ns.CastbarPreview(child, not ns.db.locked)  -- sample castbar in move mode
                end
            end
        end
        if not InCombatLockdown() then positionHeaders() end   -- live column/row spacing + growth
        if self.mover then
            self.mover:SetShown(not ns.db.locked)
        end
    end

    ns.frames[kind] = container
    if not ns.db.locked then container.mover:Show() end
    return container
end

-- ----------------------------------------------------------------------------
-- Range fading: dim group children whose unit is out of (roughly) heal range.
-- UnitInRange is the ~40yd group-member check; classic makes it fuzzy at the
-- margins, but it's the honest signal available. When it can't judge (the
-- player's own frame, or a unit on another map) UnitIsVisible breaks the tie,
-- and offline units read as unreachable. Alpha only - SetAlpha is not
-- protected, so this is combat-safe on secure children.
-- ----------------------------------------------------------------------------
local RANGE_ALPHA    = 0.40   -- the default; each group's own is cfg.rangeAlpha
local RANGE_INTERVAL = 0.30

-- the opacity of an out-of-range member for a group's settings (the
-- settings preview fades its samples with this too)
function ns.RangeAlpha(cfg)
    local a = cfg and tonumber(cfg.rangeAlpha)
    if not a then return RANGE_ALPHA end
    return math.max(0, math.min(1, a))
end

local function applyRangeAlpha(button, faded)
    if button.__rangeFaded ~= faded then
        button.__rangeFaded = faded
        button:SetAlpha(faded and ns.RangeAlpha(button.cfg) or 1)
    end
end

local rangeElapsed = 0
local ranger = CreateFrame("Frame")
ranger:SetScript("OnUpdate", function(_, e)
    rangeElapsed = rangeElapsed + e
    if rangeElapsed < RANGE_INTERVAL then return end
    rangeElapsed = 0
    for i = 1, #rangeButtons do
        local b = rangeButtons[i]
        local unit = b.unit
        if not b.cfg.rangeFade or not unit or not b:IsVisible() then
            applyRangeAlpha(b, false)
        elseif not UnitIsConnected(unit) then
            applyRangeAlpha(b, true)
        else
            local inRange, checked = UnitInRange(unit)
            -- (WoW Forever hands the range back hidden: no fading on it)
            if issecretvalue ~= nil and (issecretvalue(inRange) or issecretvalue(checked)) then
                inRange, checked = true, true
            end
            if checked then
                applyRangeAlpha(b, not inRange)
            else
                applyRangeAlpha(b, not UnitIsVisible(unit))
            end
        end
    end
end)

-- Solo there is nothing to fade: the ticker only runs while in a group,
-- and leaving one puts every frame back to full alpha once.
local function rangeGate()
    if IsInGroup() then
        ranger:Show()
    elseif ranger:IsShown() then
        ranger:Hide()
        for i = 1, #rangeButtons do applyRangeAlpha(rangeButtons[i], false) end
    end
end
Z.Roster.On("ZacUF.rangeFade", rangeGate)
rangeGate()

-- ----------------------------------------------------------------------------
-- Fit the raid to the chat window (raid.fitChat): the grouped block's left
-- edge on the chat panel's left edge, its right edge on the right, frames
-- widened to fill (height untouched), and the bottom row raid.fitGap above
-- the panel. Measured live, so each character lines up with its own chat;
-- re-run on login, on UI scale or resolution changes and when the chat is
-- moved or resized. The panel is ZacUI's chat backdrop when it is skinned,
-- else ChatFrame1 itself. Out of combat only (secure children).
-- ----------------------------------------------------------------------------
local fitPending = false

local function ToUIParent(frame, v)
    return v * frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

local function Round2(v) return math.floor(v * 100 + 0.5) / 100 end

-- ZacUI's raid chat in a PARTY (2026-10-22, Zac: "can party frames also
-- go inside chat as well"): the party frames sit in the chat box's message
-- area in ONE ROW across it, side by side, as tall as a raid row would be
-- (2026-10-22, Zac: "the bars are super long" - they were one full-width
-- bar each). Their own place and size are kept in party.preChat and come
-- back once the box gives them up.
local PARTY_ROW_GAP, PARTY_ROW_MAX_H = 4, 46
local PARTY_GEO = { "point", "x", "y", "width", "height" }

-- MOVE MODE IN THE CHAT BOX (2026-10-24, Zac: "even if not in a raid or
-- party the mock frames to show moving should be moved to chat no?"):
-- with raid chat on, the move-mode preview shows the frames where they
-- will really be - the party row along the top of the chat box and the
-- raid grid filling the rest of it - instead of at their own spots.
-- Locking the frames again puts everything back.
local function ChatPreview()
    if not (ns.db and not ns.db.locked) then return false end
    local RCh = _G.ZacUIRaidChat
    if not (RCh and RCh.Enabled and RCh.Enabled() and RCh.Area) then return false end
    if RCh.IsActive and RCh.IsActive() then return false end
    return true
end
ns.ChatPreview = ChatPreview

function ns.FitPartyToChat()
    local cfg = ns.db and ns.db.party
    if not cfg then return false end
    if InCombatLockdown() then fitPending = true; return false end
    local c = ns.frames and ns.frames.party
    local RCh = _G.ZacUIRaidChat
    local kind = RCh and RCh.Kind and RCh.Kind()
    -- the preview: solo, move mode, the party in the box too
    local preview = ChatPreview() and not IsInGroup()
        and RCh.PartyEnabled and RCh.PartyEnabled() and true or false
    if (kind == "party" or preview) and cfg.growth ~= "UP" then
        local l, r, t, b = RCh.Area(true)
        local n = cfg.showPlayer and 5 or 4
        if l and r - l > 40 and t - b > 20 then
            local w = (r - l - (n - 1) * PARTY_ROW_GAP) / n
            local h = math.min(PARTY_ROW_MAX_H, t - b)
            if w >= 20 and h >= 8 then
                ns.partyChatRow = PARTY_ROW_GAP
                if type(cfg.preChat) ~= "table" or cfg.preChat.width == nil then
                    cfg.preChat = {}
                    for _, k in ipairs(PARTY_GEO) do cfg.preChat[k] = cfg[k] end
                end
                cfg.point = "TOPLEFT"
                cfg.x = Round2(l - (UIParent:GetLeft() or 0))
                cfg.y = Round2(t - UIParent:GetHeight())
                cfg.width, cfg.height = Round2(w), Round2(h)
                if c then
                    c:ClearAllPoints()
                    c:SetPoint("TOPLEFT", UIParent, "TOPLEFT", cfg.x, cfg.y)
                    if c.LeanRestyle then c:LeanRestyle() end
                end
                return true
            end
        end
        return false
    end
    ns.partyChatRow = nil
    if type(cfg.preChat) == "table" then
        local p = cfg.preChat
        for _, k in ipairs(PARTY_GEO) do if p[k] ~= nil then cfg[k] = p[k] end end
        cfg.preChat = nil
        if c then
            c:ClearAllPoints()
            c:SetPoint(cfg.point or "TOPLEFT", UIParent, cfg.point or "TOPLEFT", cfg.x or 0, cfg.y or 0)
            if c.LeanRestyle then c:LeanRestyle() end
        end
    end
    return false
end

function ns.FitRaidToChat()
    pcall(ns.FitPartyToChat)
    local cfg = ns.db and ns.db.raid
    if not (cfg and cfg.fitChat) then return false end
    if InCombatLockdown() then fitPending = true; return false end
    if cfg.growth == "UP" or cfg.columnGrowth == "LEFT" then return false end
    -- ZacUI's raid chat: in a raid the chat box itself holds the raid
    -- frames, so they fill its message area (under whatever it keeps
    -- clear at the top) - the unit height is fitted to it, and the
    -- height from before comes back when the mode is off.
    local RCh = _G.ZacUIRaidChat
    local preview = ChatPreview() and not IsInRaid()
    if RCh and ((RCh.IsActive and RCh.IsActive()) or preview) then
        local l, r, t, b = RCh.Area(true)
        -- the preview shows the party row along the top as well: the raid
        -- grid goes under it
        if preview and ns.partyChatRow and l and ns.db.party then
            t = t - (ns.db.party.height or 0) - 6
        end
        if l and r - l > 40 and t - b > 40 then
            local cols = math.max(1, math.min(8, cfg.maxColumns or 8))
            local cs = cfg.columnSpacing or 0
            local sp = cfg.spacing or 0
            local w = (r - l - (cols - 1) * cs) / cols
            local rows = math.ceil(8 / cols)
            local h = ((t - b + cs) / rows - cs - 4 * sp) / 5
            if w >= 20 and h >= 8 then
                if not cfg.preChatHeight then cfg.preChatHeight = cfg.height end
                cfg.height = Round2(h)
                cfg.width = Round2(w)
                cfg.point = "TOPLEFT"
                cfg.x = Round2(l - (UIParent:GetLeft() or 0))
                cfg.y = Round2(t - UIParent:GetHeight())
                local c = ns.frames and ns.frames.raid
                if c then
                    c:ClearAllPoints()
                    c:SetPoint("TOPLEFT", UIParent, "TOPLEFT", cfg.x, cfg.y)
                    if c.LeanRestyle then c:LeanRestyle() end
                end
                if ns.UpdateMocks then ns.UpdateMocks() end
                return true
            end
        end
    elseif cfg.preChatHeight then
        cfg.height = cfg.preChatHeight
        cfg.preChatHeight = nil
    end
    local cf = _G.ChatFrame1
    local panel = cf and (cf._zui_chatbg or cf)
    if not (panel and panel:GetLeft() and panel:GetRight() and panel:GetTop()) then return false end
    local left  = ToUIParent(panel, panel:GetLeft())
    local right = ToUIParent(panel, panel:GetRight())
    local top   = ToUIParent(panel, panel:GetTop())
    -- the chat's tab row stands on the panel's top edge (ZacUI's strip
    -- behind the tabs, Blizzard's own tabs): the raid sits above it, or
    -- its bottom row covers the tabs. The strip is hidden until the mouse
    -- is over the chat, so it counts from its height, not its rect.
    local head = _G.ZacUIChatHead
    if head and head.GetNumPoints and head:GetNumPoints() > 0 and (head:GetHeight() or 0) > 0 then
        local t = top - ToUIParent(head, 1) + ToUIParent(head, head:GetHeight())
        if t > top then top = t end
    end
    local tab = _G.ChatFrame1Tab
    if tab and tab:IsShown() and tab:GetTop() then
        local t = ToUIParent(tab, tab:GetTop())
        if t > top and t - top < 60 then top = t end
    end
    local cols = math.max(1, math.min(8, cfg.maxColumns or 8))
    local cs = cfg.columnSpacing or 0
    local w = (right - left - (cols - 1) * cs) / cols
    if w < 20 then return false end
    local rows = math.ceil(8 / cols)
    local blockH = 5 * cfg.height + 4 * (cfg.spacing or 0) + cs
    local totalH = rows * blockH - cs
    local gap = cfg.fitGap or 4
    local uiTop = UIParent:GetHeight()
    cfg.point = "TOPLEFT"
    cfg.x = Round2(left - (UIParent:GetLeft() or 0))
    cfg.y = Round2(top + gap + totalH - uiTop)
    cfg.width = Round2(w)
    local c = ns.frames and ns.frames.raid
    if c then
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", UIParent, "TOPLEFT", cfg.x, cfg.y)
        if c.LeanRestyle then c:LeanRestyle() end
    end
    if ns.UpdateMocks then ns.UpdateMocks() end
    return true
end

-- move mode on or off: re-fit when the preview comes or goes
do
    local lastPreview
    local hk = CreateFrame("Frame")
    hk:RegisterEvent("PLAYER_LOGIN")
    hk:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        if type(ns.UpdateMocks) ~= "function" then return end
        hooksecurefunc(ns, "UpdateMocks", function()
            local p = ChatPreview()
            if p ~= lastPreview then
                lastPreview = p
                C_Timer.After(0, function() pcall(ns.FitRaidToChat) end)
            end
        end)
    end)
end

local fitter = CreateFrame("Frame")
fitter:RegisterEvent("PLAYER_ENTERING_WORLD")
fitter:RegisterEvent("PLAYER_REGEN_ENABLED")
fitter:RegisterEvent("UI_SCALE_CHANGED")
fitter:RegisterEvent("DISPLAY_SIZE_CHANGED")
fitter:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if not fitPending then return end
        fitPending = false
    end
    -- the chat window and ZacUI's panel settle a beat after login; a fit
    -- that found no room yet (the box not measured, raid chat not up) is
    -- tried twice more, so a slow load does not leave the frames at
    -- their raw spot (2026-10-26)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(2, function()
            if ns.FitRaidToChat() then return end
            C_Timer.After(2, function()
                if ns.FitRaidToChat() then return end
                C_Timer.After(3, ns.FitRaidToChat)
            end)
        end)
    else
        C_Timer.After(0.2, ns.FitRaidToChat)
    end
end)
-- Blizzard saves the chat window's place whenever it is moved or resized.
if FCF_SavePositionAndDimensions then
    hooksecurefunc("FCF_SavePositionAndDimensions", function(chatFrame)
        if chatFrame == _G.ChatFrame1 then C_Timer.After(0.1, ns.FitRaidToChat) end
    end)
end
