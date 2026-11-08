-- ============================================================================
-- ZacUF - Mock.lua
-- Placeholder party/raid frames shown in move mode so the layout can be seen
-- and positioned without needing real group members. The raid mock always
-- previews the full 40-slot footprint (8 groups x 5, wrapped per groups-per-
-- row) and shows whenever you are not in an actual raid - solo or in a party.
--
-- These are plain (non-secure) frames styled exactly like the real ones, laid
-- out with the same grid math as the secure headers. Their container is
-- anchored to the real header, so dragging the header handle or changing the
-- X/Y coordinates moves the mock frames with it.
-- ============================================================================
local ADDON, ns = ...

local mocks = {} -- mocks[kind] = { container=, frames={}, shownCount= }

local PARTY_NAMES = { "You", "Partymate 1", "Partymate 2", "Partymate 3", "Partymate 4" }

local function buildMockFrame(parent, cfg)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f.cfg = cfg
    f:SetSize(cfg.width, cfg.height)
    ns.UI:FrameBackdrop(f, cfg.bgColor, cfg.borderColor)
    ns.BuildElements(f, true)   -- a preview: kept out of the live frame sets
    return f
end

local function fillMock(f, label, hp)
    if f.Health then
        f.Health:SetMinMaxValues(0, 1); f.Health:SetValue(hp)
        local hc = f.cfg
        if hc and not hc.healthClassColor and hc.healthColor then
            f.Health:SetStatusBarColor(hc.healthColor[1], hc.healthColor[2], hc.healthColor[3])
        else
            f.Health:SetStatusBarColor(0.35, 0.65, 0.35)  -- stand-in for class color (no real unit here)
        end
        if f.Health.text then f.Health.text:SetText(math.floor(hp * 100) .. "%") end
    end
    -- Incoming-heal preview: two sample chips (a direct heal and a dimmed HoT)
    -- so the move-mode preview shows what the real display looks like. Mocks have
    -- no unit, so ns.UpdateHealPrediction can't run here - this draws by hand
    -- through the same chip pool.
    if ns.MockHealChips then ns.MockHealChips(f, hp) end
    -- the portrait (when the group wears one): every placeholder shows you
    if ns.PaintPortrait and f.Portrait then
        ns.PaintPortrait(f, nil, { isPlayer = true, class = select(2, UnitClass("player")) })
    end
    if f.Power then
        f.Power:SetMinMaxValues(0, 1); f.Power:SetValue(0.6)
        f.Power:SetStatusBarColor(0.3, 0.4, 0.9)
    end
    if f.Name then
        f.Name:SetText(label)
        local nc = f.cfg
        if nc and not nc.nameClassColor and nc.nameColor then
            f.Name:SetTextColor(nc.nameColor[1], nc.nameColor[2], nc.nameColor[3])
        else
            f.Name:SetTextColor(0.9, 0.9, 0.9)
        end
    end
end

local function ensure(kind)
    local m = mocks[kind]
    if m then return m end
    if not ns.frames[kind] then return nil end
    local container = CreateFrame("Frame", nil, UIParent)
    container:SetSize(10, 10)
    container:SetFrameStrata("MEDIUM")
    mocks[kind] = { container = container, frames = {} }
    return mocks[kind]
end

-- Where each placeholder of a group goes: returns count and place(idx) ->
-- x, y, label (offsets from the block's top-left). Move mode's mocks and the
-- settings preview both lay out through this. chatRow: the party sits in a
-- row across the chat box (move mode passes ns.partyChatRow); honourPlayer:
-- leave "You" out of a party when Show player is off (the preview does; the
-- move-mode column always shows five).
function ns.GroupLayout(kind, cfg, chatRow, honourPlayer)
    local grouped    = (kind == "raid") and cfg.groupBy and true or false
    local growUp     = (cfg.growth == "UP")
    local dir        = (cfg.columnGrowth == "LEFT") and -1 or 1
    local colSpacing = cfg.columnSpacing or 0
    local spacing    = cfg.spacing or 0

    -- place(idx) -> x, y, label. Grouped raid mirrors Groups.lua's
    -- positionHeaders(): one column per group, wrapping to a new block-row
    -- every maxColumns groups, always previewing the full 8 groups x 5 so the
    -- real footprint is visible. Flat raid mirrors the single header's
    -- unitsPerColumn chunking. Party is one column of five.
    local count, place
    if grouped then
        local cols   = math.max(1, math.min(8, cfg.maxColumns or 8))
        local blockH = 5 * cfg.height + 4 * spacing + colSpacing
        count = 40
        place = function(idx)
            local gi  = math.floor((idx - 1) / 5)   -- group 0..7
            local r   = (idx - 1) % 5               -- slot in group 0..4
            local col = gi % cols
            local row = math.floor(gi / cols)
            local x   = dir * col * (cfg.width + colSpacing)
            local y   = row * blockH + r * (cfg.height + spacing)
            return x, growUp and y or -y, ("G%d"):format(gi + 1)
        end
    elseif kind == "party" and chatRow then
        -- in the chat box: one row across it, as the real frames sit there
        local gap = chatRow
        local skip = cfg.showPlayer and 0 or 1
        count = cfg.showPlayer and 5 or 4
        place = function(idx)
            return (idx - 1) * (cfg.width + gap), 0, PARTY_NAMES[idx + skip] or ("Party " .. idx)
        end
    elseif kind == "party" then
        local skip = (honourPlayer and not cfg.showPlayer) and 1 or 0
        count = 5 - skip
        place = function(idx)
            local y = (idx - 1) * (cfg.height + spacing)
            return 0, growUp and y or -y, PARTY_NAMES[idx + skip] or ("Party " .. idx)
        end
    else
        local perCol = cfg.unitsPerColumn or 5
        local cols   = cfg.maxColumns or 8
        count = math.min(perCol * cols, 40)
        place = function(idx)
            local c = math.floor((idx - 1) / perCol)
            local r = (idx - 1) % perCol
            local x = dir * c * (cfg.width + colSpacing)
            local y = r * (cfg.height + spacing)
            return x, growUp and y or -y, ("Raid " .. idx)
        end
    end
    return count, place
end

local function layout(kind)
    local m = ensure(kind); if not m then return end
    local cfg = ns.db[kind]
    local header = ns.frames[kind]

    m.container:ClearAllPoints()
    if header.mover then
        -- anchor to the drag handle so mocks track the handle live while dragging
        m.container:SetPoint("TOPLEFT", header.mover, "BOTTOMLEFT", 0, -2)
    else
        m.container:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
    end

    local count, place = ns.GroupLayout(kind, cfg, ns.partyChatRow)

    for idx = 1, count do
        local f = m.frames[idx]
        if not f then
            f = buildMockFrame(m.container, cfg)
            m.frames[idx] = f
        end
        f.cfg = cfg
        f:SetSize(cfg.width, cfg.height)
        ns.StyleElements(f)

        local x, y, label = place(idx)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", m.container, "TOPLEFT", x, y)

        fillMock(f, label, 0.5 + (idx % 5) * 0.08)
        if ns.CastbarPreview then ns.CastbarPreview(f, true) end  -- mocks only render in move mode
        f:Show()
        -- the second placeholder carries a Magic debuff you could remove,
        -- so the dispel glow's look (Look tab) can be seen in place
        if ns.DispelGlowSet then ns.DispelGlowSet(f, (idx == 2) and "Magic" or nil, true) end
    end
    for i = count + 1, #m.frames do m.frames[i]:Hide() end
    m.shownCount = count
end

local function setShown(kind, show)
    local m = mocks[kind]
    if not show then
        if m then for _, f in ipairs(m.frames) do f:Hide() end end
        return
    end
    layout(kind)
    m = mocks[kind]
    if m then for i = 1, (m.shownCount or 0) do m.frames[i]:Show() end end
end

-- Party mock only while completely solo (in a party the real frames are up).
-- Raid mock whenever NOT in an actual raid - solo OR in a 5-man - since the
-- real raid frames are hidden in both cases; previews the full 40-slot
-- footprint of the current layout.
-- The preview frames of one group kind ("party" / "raid") and how many
-- there are - for ZacUI's Edit Mode, which draws one outline round the
-- whole block. Hidden ones are in the list too; the caller skips those.
function ns.MockFrames(kind)
    local m = mocks[kind]
    if not m then return nil, 0 end
    return m.frames, #m.frames
end

function ns.UpdateMocks()
    local moving = not ns.db.locked
    setShown("party", moving and not IsInGroup() and ns.db.party.enabled and ns.frames.party ~= nil)
    setShown("raid",  moving and not IsInRaid()  and ns.db.raid.enabled  and ns.frames.raid  ~= nil)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function()
    if ns.UpdateMocks then ns.UpdateMocks() end
end)
