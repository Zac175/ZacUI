-- ============================================================================
-- ZacUF - MoveDialog.lua
-- A focused frame-placement tool: pick a frame, drag it (or type an exact X / Y /
-- Width / Height, plus Spacing / Col gap for groups), nudge by 1px, and snap to a
-- grid. Everything else - element positions, on/off toggles, colours, group
-- layout - lives in the main options window; the "All settings" button opens it.
--
-- X/Y read the frame's actual on-screen position, so the boxes track live while
-- you drag. Single-frame size/position is fully live; group position + spacing
-- are live out of combat; group Width/Height apply on /reload (the move-mode mock
-- frames preview them at once).
-- ============================================================================
local ADDON, ns = ...

local dlg, sel = nil, "player"
local rows = {}
local onSelect -- forward declaration

local KEYS   = { "player", "target", "targettarget", "pet", "party", "raid" }
local LABELS = {
    player = "Player", target = "Target", targettarget = "Target of Target",
    pet = "Pet", party = "Party", raid = "Raid",
}

-- ---- grid + snapping ------------------------------------------------------
local grid
local GRID = 20      -- cell size in pixels
local snapOn = true  -- snap dragged frames to the grid (keeps things symmetrical)

function ns.SnapValue(v)
    if not snapOn then return v end
    return math.floor(v / GRID + 0.5) * GRID
end

local function buildGrid()
    grid = CreateFrame("Frame", "ZacUFGrid", UIParent)
    grid:SetAllPoints(UIParent)
    grid:SetFrameStrata("BACKGROUND")
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local function line(horiz, pos)
        local t = grid:CreateTexture(nil, "BACKGROUND")
        t:SetColorTexture(1, 1, 1, 0.05)
        if horiz then t:SetSize(w, 1); t:SetPoint("TOP", grid, "TOP", 0, -pos)
        else t:SetSize(1, h); t:SetPoint("LEFT", grid, "LEFT", pos, 0) end
    end
    local x = 0; while x <= w do line(false, x); x = x + GRID end
    local y = 0; while y <= h do line(true, y);  y = y + GRID end
    -- emphasized center lines for left/right + top/bottom symmetry
    local cv = grid:CreateTexture(nil, "ARTWORK"); cv:SetColorTexture(0.85, 0.65, 0.25, 0.5); cv:SetSize(1, h); cv:SetPoint("CENTER")
    local ch = grid:CreateTexture(nil, "ARTWORK"); ch:SetColorTexture(0.85, 0.65, 0.25, 0.5); ch:SetSize(w, 1); ch:SetPoint("CENTER")
    grid:Hide()
end

function ns.ShowGrid()
    if not snapOn then return end
    if not grid then buildGrid() end
    grid:Show()
end
function ns.HideGrid() if grid then grid:Hide() end end

local function getCfg(key) return ns.db.frames[key] or ns.db[key] end
local function isHeader(key) return key == "party" or key == "raid" end

-- actual CENTER-relative position of a single frame (so boxes track during drag)
local function liveXY(key)
    local cfg = getCfg(key)
    local f = ns.frames[key]
    if f and not isHeader(key) and f.GetCenter then
        local cx, cy = f:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if cx and ux then
            return math.floor(cx - ux + 0.5), math.floor(cy - uy + 0.5)
        end
    end
    return cfg.x, cfg.y
end

-- ---- live appliers --------------------------------------------------------
local function setPos(key, axis, v)
    local cfg = getCfg(key)
    cfg[axis] = v
    local f = ns.frames[key]
    if f and not InCombatLockdown() then
        f:ClearAllPoints()
        f:SetPoint(cfg.point or "CENTER", UIParent, cfg.point or "CENTER", cfg.x, cfg.y)
        if f.mover then
            f.mover:ClearAllPoints()
            f.mover:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 2)
        end
    end
    if ns.UpdateMocks then ns.UpdateMocks() end
end

local function setSize(key, dim, v)
    local cfg = getCfg(key)
    cfg[dim] = v
    local f = ns.frames[key]
    if f and not isHeader(key) and not InCombatLockdown() then
        f:SetSize(cfg.width, cfg.height)
        ns.StyleElements(f)
        ns.UpdateAll(f)
    end
    if ns.UpdateMocks then ns.UpdateMocks() end
end

local function setSpacing(key, which, v)
    local cfg = getCfg(key)
    cfg[which] = v
    -- frames[key] is the insecure container that wraps the secure header(s); its
    -- LeanRestyle re-applies row/column spacing to the real header(s) and re-grids
    -- them (out of combat). Applies live for both flat and per-group raid layouts.
    local h = ns.frames[key]
    if h and h.LeanRestyle and not InCombatLockdown() then
        h:LeanRestyle()
    end
    if ns.UpdateMocks then ns.UpdateMocks() end
end

local function refreshRows()
    for _, r in ipairs(rows) do if r.Refresh then r:Refresh() end end
end

-- ---- widgets --------------------------------------------------------------
local function field(parent, x, y, label, getf, setf, boxW)
    local l = ns.UI:FS(parent, 11)
    l:SetPoint("TOPLEFT", x, y)
    l:SetText(label)
    local eb = ns.UI:EditBox(parent, boxW or 58, getf, setf)
    eb:SetPoint("TOPLEFT", x + 50, y + 4)
    eb.fieldLabel = l
    rows[#rows + 1] = eb
    return eb
end

local function header(parent, x, y, txt)
    local h = ns.UI:FS(parent, 11)
    h:SetPoint("TOPLEFT", x, y)
    h:SetText(txt)
    h:SetTextColor(0.85, 0.65, 0.25)
    return h
end

local function nudge(dx, dy)
    local x, y = liveXY(sel)
    setPos(sel, "x", x + dx)
    setPos(sel, "y", y + dy)
    refreshRows()
end

local function resetFrame()
    local d = ns.defaults.frames[sel] or ns.defaults[sel]
    if d then
        local cfg = getCfg(sel)
        cfg.x, cfg.y, cfg.width, cfg.height = d.x, d.y, d.width, d.height
        if d.spacing then cfg.spacing = d.spacing end
        if d.columnSpacing then cfg.columnSpacing = d.columnSpacing end
        cfg.nameAnchor, cfg.nameX, cfg.nameY = d.nameAnchor, d.nameX, d.nameY
        cfg.hpAnchor, cfg.hpX, cfg.hpY = d.hpAnchor, d.hpX, d.hpY
        cfg.debuffAnchor, cfg.debuffX, cfg.debuffY = d.debuffAnchor, d.debuffX, d.debuffY
        cfg.buffAnchor, cfg.buffX, cfg.buffY = d.buffAnchor, d.buffX, d.buffY
        for _, k in ipairs({ "combat", "leader", "role", "raid", "pvp" }) do
            cfg[k .. "Anchor"], cfg[k .. "X"], cfg[k .. "Y"] = d[k .. "Anchor"], d[k .. "X"], d[k .. "Y"]
        end
        cfg.cbAnchor, cfg.cbX, cfg.cbY = d.cbAnchor, d.cbX, d.cbY
        cfg.cbWidth, cfg.cbHeight = d.cbWidth, d.cbHeight
    end
    ns.ApplySettings()
    onSelect()
end

local ARROW_ROT = { up = 0, down = math.pi, left = math.pi / 2, right = -math.pi / 2 }
local function arrowBtn(parent, dir, onClick)
    local b = ns.UI:Button(parent, "", 26, 22, onClick)
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetSize(12, 12)
    t:SetPoint("CENTER")
    t:SetTexture("Interface\\AddOns\\Zacui_UnitFrames\\Media\\arrowUp")
    t:SetRotation(ARROW_ROT[dir] or 0)
    t:SetVertexColor(1, 0.82, 0)
    b.arrow = t
    return b
end

-- One click per step on the raid groups-per-row wrap (4 = groups 1-4 across
-- the top, 5-8 below). Applies live via the shared setter (combat-deferred),
-- and the 40-slot mock preview re-grids with it.
local function stepGroups(d)
    local v = math.max(1, math.min(8, (ns.db.raid.maxColumns or 8) + d))
    if v ~= ns.db.raid.maxColumns then
        ns.SetRaidGroupsPerRow(v)
    end
    if dlg and dlg.grpVal then dlg.grpVal:SetText(ns.db.raid.maxColumns) end
end

-- ---- build ----------------------------------------------------------------
local function build()
    dlg = ns.UI:Window("ZacUFMove", "Unit frame positions", 300, 374)
    local c = dlg.content

    local sl = ns.UI:FS(c, 11); sl:SetPoint("TOPLEFT", 6, -8); sl:SetText("Frame")
    local names = {}
    for _, k in ipairs(KEYS) do names[#names + 1] = LABELS[k] end
    dlg.dd = ns.UI:Dropdown(c, 224, names, LABELS[sel], function(chosen)
        for _, k in ipairs(KEYS) do if LABELS[k] == chosen then sel = k break end end
        onSelect()
    end)
    dlg.dd:SetPoint("TOPLEFT", 50, -4)

    header(c, 6, -42, "Position & size")
    field(c, 14, -62, "X", function() local x = liveXY(sel); return x end, function(v) setPos(sel, "x", v) end)
    field(c, 150, -62, "Y", function() local _, y = liveXY(sel); return y end, function(v) setPos(sel, "y", v) end)
    field(c, 14, -88, "W", function() return getCfg(sel).width end, function(v) setSize(sel, "width", v) end)
    field(c, 150, -88, "H", function() return getCfg(sel).height end, function(v) setSize(sel, "height", v) end)
    dlg.spRow  = field(c, 14, -114, "Space", function() return getCfg(sel).spacing or 0 end, function(v) setSpacing(sel, "spacing", v) end)
    dlg.colRow = field(c, 150, -114, "Col", function() return getCfg(sel).columnSpacing or 0 end, function(v) setSpacing(sel, "columnSpacing", v) end)

    -- Raid only: groups-per-row stepper (the wrap from the /zuf groups command)
    dlg.grpLabel = ns.UI:FS(c, 11)
    dlg.grpLabel:SetPoint("TOPLEFT", 14, -142)
    dlg.grpLabel:SetText("Groups / row")
    dlg.grpLess = arrowBtn(c, "left", function() stepGroups(-1) end)
    dlg.grpLess:SetPoint("TOPLEFT", 96, -138)
    dlg.grpVal = ns.UI:FS(c, 12)
    dlg.grpVal:SetPoint("TOPLEFT", 130, -142)
    dlg.grpVal:SetTextColor(1, 0.82, 0)
    dlg.grpMore = arrowBtn(c, "right", function() stepGroups(1) end)
    dlg.grpMore:SetPoint("TOPLEFT", 148, -138)

    header(c, 6, -176, "Nudge 1px")
    local up    = arrowBtn(c, "up",    function() nudge(0, 1) end);  up:SetPoint("TOPLEFT", 44, -194)
    local left  = arrowBtn(c, "left",  function() nudge(-1, 0) end); left:SetPoint("TOPLEFT", 14, -218)
    local right = arrowBtn(c, "right", function() nudge(1, 0) end);  right:SetPoint("TOPLEFT", 74, -218)
    local down  = arrowBtn(c, "down",  function() nudge(0, -1) end); down:SetPoint("TOPLEFT", 44, -242)

    dlg.snapChk = ns.UI:Checkbox(c, "Snap to grid", snapOn, function(v)
        snapOn = v
        if v then ns.ShowGrid() else ns.HideGrid() end
    end)
    dlg.snapChk:SetPoint("TOPLEFT", 132, -194)
    local rstb = ns.UI:Button(c, "Reset frame", 132, 22, resetFrame)
    rstb:SetPoint("TOPLEFT", 132, -220)
    local allb = ns.UI:Button(c, "All settings", 132, 22, function() if ns.ToggleConfig then ns.ToggleConfig() end end)
    allb:SetPoint("TOPLEFT", 132, -246)

    dlg.note = ns.UI:FS(c, 10)
    dlg.note:SetPoint("BOTTOMLEFT", 6, 8); dlg.note:SetWidth(268); dlg.note:SetJustifyH("LEFT")
    dlg.note:SetTextColor(0.6, 0.6, 0.6)

    -- live-refresh non-focused boxes so dragging updates the coords on screen
    dlg:SetScript("OnUpdate", function(self, e)
        self._t = (self._t or 0) + e
        if self._t < 0.1 then return end
        self._t = 0
        for _, r in ipairs(rows) do
            if r.Refresh and not r:HasFocus() then r:Refresh() end
        end
    end)
end

onSelect = function()
    refreshRows()
    local hdr = isHeader(sel)
    local raid = (sel == "raid")
    dlg.spRow:SetShown(hdr);   dlg.spRow.fieldLabel:SetShown(hdr)
    dlg.colRow:SetShown(raid); dlg.colRow.fieldLabel:SetShown(raid)
    dlg.grpLabel:SetShown(raid)
    dlg.grpLess:SetShown(raid)
    dlg.grpMore:SetShown(raid)
    dlg.grpVal:SetShown(raid)
    if raid then dlg.grpVal:SetText(ns.db.raid.maxColumns or 8) end
    dlg.note:SetText(hdr
        and "Drag the handle or type coords - position, spacing and groups/row are live (out of combat). Group W/H, sort, toggles, colours and element positions live in All settings."
        or "Drag the frame or type coords - applies live. Toggles, colours and element positions live in All settings.")
end

function ns.ShowMoveDialog()
    if not dlg then build() end
    onSelect()
    dlg:Show()
    ns.ShowGrid()
end

function ns.HideMoveDialog()
    if dlg then dlg:Hide() end
    ns.HideGrid()
end

function ns.ToggleMoveDialog()
    if dlg and dlg:IsShown() then ns.HideMoveDialog() else ns.ShowMoveDialog() end
end

function ns.RefreshMoveDialog() if dlg and dlg:IsShown() then onSelect() end end

-- Click a frame (or group handle) in move mode to select it in the dialog
function ns.SelectMoveFrame(key)
    -- hosted by ZacUI's Edit Mode the dialog stays out of the way until a
    -- frame is clicked; ZacUI's grid is up already, so ours is not shown
    if ns._zuiEdit and not (dlg and dlg:IsShown()) then
        if not dlg then build() end
        dlg:Show()
    end
    if not dlg or not dlg:IsShown() then return end
    if not getCfg(key) then return end
    sel = key
    if dlg.dd then dlg.dd:SetValue(LABELS[key]) end
    onSelect()
end
