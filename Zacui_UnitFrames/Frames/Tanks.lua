-- ============================================================================
-- Zacui_UnitFrames - Tanks.lua
-- Tank frames: a second, small group of chosen raid members beside the raid
-- frames - the raid's main tanks (the game's raid roles: main tank, and main
-- assist if you want them; Retail's assigned tank role too), or a list of
-- names you keep. Same cells as the raid's (the frames' own elements, range
-- fade, click to target, click-casting), with settings of their own
-- (ns.db.frames.tanks), their own place - beside the raid block by default,
-- following it wherever it goes, or anywhere you drag them - Edit Mode, a
-- preview sample (the tanks next to a raid group) and a Test.
-- A secure group header does the picking (groupFilter by role, or its
-- nameList), so who shows is right in combat too; changing who is picked
-- waits for the fight to end. Off by default; nothing made while off.
-- Part of Zacui_UnitFrames; load order is set by the TOC (after Extras).
-- ============================================================================
local ADDON, ns = ...

local KEY = "tanks"
local SHOWN = 3        -- rows the holder (Edit Mode's box) and the stand-ins show
local testUntil        -- a Test's stand-ins are up (its token)

local function Cfg() return ns.db and ns.db.frames and ns.db.frames[KEY] end

-- the header's filter for who is picked
local function FilterOf(cfg)
    if cfg.who == "names" then
        local list = {}
        for n in tostring(cfg.names or ""):gmatch("[^,]+") do
            n = n:gsub("^%s+", ""):gsub("%s+$", "")
            if n ~= "" then list[#list + 1] = n end
        end
        return nil, table.concat(list, ",")
    end
    return cfg.assists and "MAINTANK,MAINASSIST,TANK" or "MAINTANK,TANK", nil
end

-- the raid block's right (or, growing up, its bottom-left) for the tanks
-- to sit beside: the raid's holder and the x past its last column
local function BesideRaid()
    local rc, rf = ns.db.raid, ns.frames.raid
    if not (rc and rc.enabled and rf and ns.GroupLayout) then return nil end
    local count, place = ns.GroupLayout("raid", rc, nil, true)
    local right = rc.width
    for i = 1, count do
        local x = place(i)
        if x + rc.width > right then right = x + rc.width end
    end
    return rf, right, (rc.growth == "UP") and "BOTTOMLEFT" or "TOPLEFT"
end

local function Place(c, cfg)
    if InCombatLockdown() then return end
    c:ClearAllPoints()
    local rf, right, pt = nil, nil, nil
    if cfg.follow ~= false then rf, right, pt = BesideRaid() end
    if rf then
        c:SetPoint(pt, rf, pt, right + (cfg.gap or 12), 0)
    else
        c:SetPoint(cfg.point or "CENTER", UIParent, cfg.point or "CENTER", cfg.x or 0, cfg.y or 0)
    end
end

local function Layout(c, cfg)
    if InCombatLockdown() then return end
    local sp = cfg.spacing or 3
    c:SetSize(cfg.width, SHOWN * cfg.height + (SHOWN - 1) * sp)
    local h = c.header
    local up = (cfg.growth == "UP")
    local point, yOff = up and "BOTTOM" or "TOP", up and sp or -sp
    if h:GetAttribute("point") ~= point or h:GetAttribute("yOffset") ~= yOff then
        for _, child in ipairs({ h:GetChildren() }) do child:ClearAllPoints() end
        h:SetAttribute("point", point)
        h:SetAttribute("xOffset", 0)
        h:SetAttribute("yOffset", yOff)
    end
    h:ClearAllPoints()
    h:SetPoint(up and "BOTTOMLEFT" or "TOPLEFT", c, up and "BOTTOMLEFT" or "TOPLEFT", 0, 0)
    local gf, names = FilterOf(cfg)
    if h:GetAttribute("groupFilter") ~= gf then h:SetAttribute("groupFilter", gf) end
    if h:GetAttribute("nameList") ~= names then h:SetAttribute("nameList", names) end
    -- children at the size (and the ones made later through the snippet)
    for _, child in ipairs({ h:GetChildren() }) do
        local w, ht = child:GetWidth(), child:GetHeight()
        if math.abs((w or 0) - cfg.width) > 0.01 or math.abs((ht or 0) - cfg.height) > 0.01 then
            child:SetSize(cfg.width, cfg.height)
        end
    end
    if c._sizeW ~= cfg.width or c._sizeH ~= cfg.height then
        c._sizeW, c._sizeH = cfg.width, cfg.height
        h:SetAttribute("initialConfigFunction", ns.ChildConfigSnippet(cfg))
    end
end

-- ----------------------------------------------------------------------------
-- The made-up tanks (preview, move mode, Test)
-- ----------------------------------------------------------------------------
local function TankPeople(P)
    local A = P.A
    return {
        P.person({ name = "Shieldy", class = "WARRIOR", isPlayer = true, friendly = true, pct = 0.64,
            role = "MAINTANK", marker = 8, buffs = {}, debuffs = { P.aura(A.swp) }, taunt = false,
            heals = { { amount = 900, previewClass = "PRIEST", previewSlot = 0, previewName = "Holyclone" } } }),
        P.person({ name = "Revenge", class = "WARRIOR", isPlayer = true, friendly = true, pct = 0.91,
            role = "MAINTANK", marker = 7, buffs = {}, debuffs = {} }),
        P.person({ name = "Barkskin", class = "DRUID", isPlayer = true, friendly = true, pct = 0.38,
            role = "MAINASSIST", marker = 6, buffs = {}, debuffs = {},
            heals = { { amount = 600, previewClass = "PALADIN", previewSlot = 0, previewName = "Lightbulb" } } }),
    }
end

local function StandInPlace(cfg)
    local sp = cfg.spacing or 3
    return function(i)
        if cfg.growth == "UP" then
            return 0, -(SHOWN - i) * (cfg.height + sp)
        end
        return 0, -(i - 1) * (cfg.height + sp)
    end
end

-- ----------------------------------------------------------------------------
-- The holder, its header and its handle
-- ----------------------------------------------------------------------------
local function EnsureHandle(c, cfg)
    if c.mover then return c.mover end
    local m = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    m:SetSize(math.max(cfg.width, 90), 22)
    m:SetPoint("BOTTOMLEFT", c, "TOPLEFT", 0, 2)
    m:SetFrameStrata("HIGH")
    m:SetMovable(true)
    m:SetClampedToScreen(true)
    ns.UI:Backdrop(m, ns.db.colors.background, { 0.85, 0.65, 0.25, 1 })
    m.label = ns.UI:FS(m, 11)
    m.label:SetPoint("CENTER")
    m.label:SetTextColor(1, 0.82, 0)
    m:EnableMouse(true)
    m:RegisterForDrag("LeftButton")
    m:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then self:StartMoving() end
    end)
    m:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- a drag puts the tanks where they are dropped (no longer beside
        -- the raid); the place is the holder's middle, as the page's X / Y
        local l, b = self:GetLeft(), self:GetBottom()
        if l and b and not InCombatLockdown() then
            local w, h = c:GetWidth() or cfg.width, c:GetHeight() or cfg.height
            local cx, cy = l + w / 2, (b - 2) - h / 2
            local ux, uy = UIParent:GetCenter()
            local nx, ny = cx - ux, cy - uy
            if ns.SnapValue then nx, ny = ns.SnapValue(nx), ns.SnapValue(ny) end
            cfg.follow = false
            cfg.point, cfg.x, cfg.y = "CENTER", nx, ny
            Place(c, cfg)
        end
        self:ClearAllPoints()
        self:SetPoint("BOTTOMLEFT", c, "TOPLEFT", 0, 2)
        if ns.RefreshOptions then ns.RefreshOptions() end
    end)
    m:Hide()
    c.mover = m
    return m
end

local function Spawn()
    local cfg = Cfg()
    if not (cfg and cfg.enabled) or ns.frames[KEY] or InCombatLockdown() then return ns.frames[KEY] end
    if not (ns.StyleGroupChild and ns.ChildConfigSnippet) then return nil end
    local c = CreateFrame("Frame", "ZacUF_tanksHeader", UIParent)
    c.cfg = cfg
    c:SetMovable(true)
    local h = CreateFrame("Frame", "ZacUF_TanksGroup", c, "SecureGroupHeaderTemplate")
    c.header = h
    c.headers = { h }
    if ClickCastHeader then
        SecureHandlerSetFrameRef(h, "clickcast_header", ClickCastHeader)
        h.__cliqueSecure = true
    end
    h.LeanStyleChild = function(_, childName)
        local child = _G[childName]
        if child then
            child.cfg = cfg
            ns.StyleGroupChild(child)
            -- a tank's raid cell stays the one WeakAuras and the frame
            -- lookup find for them (this is the second showing)
            child.isGroupUnit = false
        end
    end
    h:SetAttribute("template", "SecureUnitButtonTemplate,BackdropTemplate")
    h:SetAttribute("showSolo", false)
    h:SetAttribute("showParty", false)
    h:SetAttribute("showRaid", true)
    h:SetAttribute("showPlayer", true)
    h:SetAttribute("sortMethod", "INDEX")
    h:SetAttribute("initialConfigFunction", ns.ChildConfigSnippet(cfg))
    c._sizeW, c._sizeH = cfg.width, cfg.height
    Layout(c, cfg)
    Place(c, cfg)
    -- every child it can need made now, out of combat (Groups.lua's way)
    h:Show()
    h:SetAttribute("startingIndex", -4)
    h:SetAttribute("startingIndex", 1)
    RegisterStateDriver(h, "visibility", "[group:raid] show; hide")
    EnsureHandle(c, cfg)

    c.LeanRestyle = function(self)
        local unlocked = not ns.db.locked
        Layout(self, cfg)
        Place(self, cfg)
        for _, child in ipairs({ h:GetChildren() }) do
            if child.__leanInit then
                child.__rangeFaded = nil
                ns.UI:FrameBackdrop(child, cfg.bgColor, cfg.borderColor)
                ns.StyleElements(child)
                ns.RegisterFrameEvents(child)
                ns.UpdateAll(child)
            end
        end
        if self.mover then
            self.mover:SetWidth(math.max(cfg.width, 90))
            self.mover.label:SetText(cfg.follow ~= false and "Tanks (beside the raid)" or "Tanks (drag)")
            self.mover:SetShown(unlocked and cfg.enabled and true or false)
        end
        -- move mode out of a raid: three made-up tanks where they will sit
        if unlocked and cfg.enabled and not IsInRaid() then
            local PV = ns.UFPreview
            if PV and PV.Kit then ns.ShowStandIns(self, TankPeople(PV.Kit()), StandInPlace(cfg), cfg) end
        elseif not testUntil then
            ns.HideStandIns(self)
        end
        local Zr = ns.ZUI or _G.ZacUI
        if Zr and Zr.Visibility then Zr.Visibility.Refresh(self) end
    end

    ns.frames[KEY] = c
    local Zv = ns.ZUI or _G.ZacUI
    if Zv and Zv.Visibility then
        Zv.Visibility.Register(c, function() return cfg.visibility end,
            { control = "gate", onChange = ns.VisibilityApply })
    end
    -- the raid block moved (dragged, lined up with chat): the tanks follow it
    -- by their anchor alone; a resize of its cells moves its right edge
    local rf = ns.frames.raid
    if rf and rf.LeanRestyle then hooksecurefunc(rf, "LeanRestyle", function() Place(c, cfg) end) end
    c:LeanRestyle()
    return c
end

-- live: on = made now (out of combat); off = the header's driver hides it
local function Apply()
    local cfg, c = Cfg(), ns.frames[KEY]
    if not cfg then return end
    if cfg.enabled and not c then Spawn() return end
    if c and not InCombatLockdown() then
        RegisterStateDriver(c.header, "visibility", cfg.enabled and "[group:raid] show; hide" or "hide")
        if not cfg.enabled then
            ns.HideStandIns(c)
            if c.mover then c.mover:Hide() end
        end
    end
end

-- the Test: the three made-up tanks on screen for a few seconds
local function Test()
    local c, cfg, PV = ns.frames[KEY], Cfg(), ns.UFPreview
    if not (c and cfg and cfg.enabled and PV and PV.Kit) then
        if ns.Print then ns.Print("switch the tank frames on first (Show this frame, above).") end
        return
    end
    if InCombatLockdown() then
        if ns.Print then ns.Print("the test waits until combat ends.") end
        return
    end
    ns.ShowStandIns(c, TankPeople(PV.Kit()), StandInPlace(cfg), cfg)
    local token = {}
    testUntil = token
    C_Timer.After(8, function()
        if testUntil ~= token then return end
        testUntil = nil
        if ns.db.locked ~= false or IsInRaid() then ns.HideStandIns(c) end
    end)
end
ns.TestTanks = Test

-- ----------------------------------------------------------------------------
-- The preview: the tanks beside one raid group, as they sit in game
-- ----------------------------------------------------------------------------
local function PreviewLayout(cfg, P)
    local people = TankPeople(P)
    local rc = ns.db.raid
    local raidCol = {}
    local names = { "Zaccw", "Holyclone", "Stabbz", "Frostie", "Dotsy" }
    local classes = { "WARRIOR", "PRIEST", "ROGUE", "MAGE", "WARLOCK" }
    for i = 1, 5 do
        local d = P.person({ name = names[i], class = classes[i], isPlayer = true, friendly = true,
            pct = 0.55 + i * 0.08, buffs = {}, debuffs = {} })
        d._cfg = rc
        d.cast = nil
        raidCol[i] = d
        people[#people + 1] = d
    end
    local gap = cfg.gap or 12
    local sp, rsp = cfg.spacing or 3, rc.spacing or 3
    local raidH = 5 * rc.height + 4 * rsp
    local total = rc.width + gap + cfg.width
    local x0, y0 = -total / 2, raidH / 2
    return people, function(i)
        if i <= SHOWN then
            -- (growing up, the first sits at the bottom of the three)
            local row = (cfg.growth == "UP") and (SHOWN - i) or (i - 1)
            return x0 + rc.width + gap, y0 - row * (cfg.height + sp)
        end
        local r = i - SHOWN
        return x0, y0 - (r - 1) * (rc.height + rsp)
    end
end

if ns.RegisterExtraFrame and ns.defaults and ns.defaults.raid then
    local def = ns.CopyDefaults(ns.defaults.raid, {
        enabled = false, width = 96, height = 30, spacing = 3, growth = "DOWN",
        who = "role", assists = false, names = "", follow = true, gap = 12,
        point = "CENTER", x = -320, y = 120,
        healthText = "percent", nameAnchor = "LEFT", hpAnchor = "RIGHT",
        -- white names (a class-coloured name on a class-coloured bar reads
        -- poorly at this size), the marker on the top edge as on the party
        nameClassColor = false,
        leaderIcon = false, roleIcon = false, raidIcon = true, raidAnchor = "TOP", raidX = 0, raidY = 0, raidSize = 16,
    })
    for _, k in ipairs({ "showPlayer", "sortMethod", "sortDir", "unitsPerColumn", "maxColumns", "columnSpacing",
        "columnGrowth", "groupBy", "fitChat", "fitGap" }) do def[k] = nil end
    ns.RegisterExtraFrame({ key = KEY, label = "Tank frames", short = "Tanks", after = "raid",
        available = function() return ns.UFFeatureOn("uf_tanks") end, defaults = def,
        spawn = Spawn, apply = Apply, layout = PreviewLayout })
end

-- ----------------------------------------------------------------------------
-- The page
-- ----------------------------------------------------------------------------
local WHO = { { text = "The raid's main tanks", value = "role" }, { text = "A list of names", value = "names" } }

ns.UFPageCards[#ns.UFPageCards + 1] = function(L, tab, key, cfg, H)
    if key ~= KEY or not ns.ExtraFrame(KEY) then return end
    local Z = ns.ZUI or _G.ZacUI
    local UI = Z and Z.UI
    if tab == "general" then
        L:Card("Who the tank frames show")
        H.Drops(L, { label = "Show", items = WHO, get = function() return cfg.who or "role" end,
            set = function(v) cfg.who = v H.Refresh() end })
        if (cfg.who or "role") == "role" then
            H.Checks(L, { { "Main assists too", function() return cfg.assists end, function(v) cfg.assists = v end,
                "The raid's main assists as well as its main tanks (the leader sets both in the raid window)." } }, 1)
            L:Desc("The raid leader marks the main tanks in the raid window (or with /maintank). "
                .. "On a game with assigned roles, players in the tank role show too.")
        else
            if UI and UI.EditBox then
                local box = UI.EditBox(L.current, { width = math.min(320, H.InnerWidth(L)), text = cfg.names or "",
                    onEnter = function(t) cfg.names = t or "" H.Apply() end })
                L:Row(box, (UI.M and UI.M.EDIT_H or 20) + 6)
            end
            H.Buttons(L, { { "Add my target", 120, function()
                local n = UnitExists("target") and UnitIsPlayer("target") and UnitName("target")
                if type(n) ~= "string" or (ns.ZUI and ns.ZUI.IsSecret and ns.ZUI.IsSecret(n)) then return end
                local cur = cfg.names or ""
                for m in cur:gmatch("[^,]+") do if m:gsub("^%s+", ""):gsub("%s+$", "") == n then return end end
                cfg.names = (cur ~= "" and (cur .. ", ") or "") .. n
                H.Apply()
                H.Refresh()
            end, "Adds the player you have targeted to the list." } })
            L:Desc("Names separated by commas, in the order they show. Enter saves the list.")
        end
        H.Checks(L, { { "Fade out of range", function() return cfg.rangeFade end, function(v) cfg.rangeFade = v end,
            "A tank out of your reach dims, as on the raid frames." } }, 1)
        L:Desc("Who is picked changes when the fight ends; health, casts and the rest update in combat as everywhere.")
        H.Button(L, "Test on screen", 130, Test, "Three made-up tanks where yours will show, for a few seconds.")
        L:EndCard()
    elseif tab == "pos" then
        L:Card("Tank frames layout")
        H.Checks(L, { { "Beside the raid frames", function() return cfg.follow ~= false end,
            function(v) cfg.follow = v and true or false end,
            "They sit just right of the raid block and follow it when it moves. Off: they stay at the X / Y above." } }, 1)
        H.Sliders(L,
            { label = "Gap from the raid", min = 0, max = 60, format = H.PX, get = function() return cfg.gap or 12 end,
              set = function(v) cfg.gap = v end },
            { label = "Gap between them", min = 0, max = 24, format = H.PX, get = function() return cfg.spacing or 3 end,
              set = function(v) cfg.spacing = v end })
        H.Drops(L, { label = "Grow", items = { { text = "Down", value = "DOWN" }, { text = "Up", value = "UP" } },
            get = function() return cfg.growth or "DOWN" end, set = function(v) cfg.growth = v end })
        L:Desc("Dragging their handle in move mode puts them where you drop them (Beside the raid frames goes off).")
        L:EndCard()
    end
end
