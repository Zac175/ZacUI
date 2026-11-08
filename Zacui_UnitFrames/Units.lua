-- ============================================================================
-- ZacUF - Units.lua
-- Single secure unit frames: player, target, targettarget, pet.
-- Each frame listens ONLY to its own unit's events (RegisterUnitEvent), so it
-- does no work for unrelated units. Left-click targets; right-click opens the
-- unit menu. Frames can be dragged when unlocked (out of combat).
-- ============================================================================
local ADDON, ns = ...

-- Which "unit changed" events matter for each token
local CHANGE_EVENT = {
    target     = "PLAYER_TARGET_CHANGED",
    softtarget = "PLAYER_SOFT_ENEMY_CHANGED",
    focus      = "PLAYER_FOCUS_CHANGED",   -- TBC / Forever (Focus.lua; never spawned where there is none)
}

-- Case matters: LibGetFrame's patterns are case-sensitive ("Player", not
-- "player").
local WA_NAME_SUFFIX = {
    player = "Player", target = "Target", targettarget = "TargetTarget", pet = "Pet",
    softtarget = "SoftTarget", focus = "Focus", focustarget = "FocusTarget",
}

local function applyPosition(frame, cfg)
    frame:ClearAllPoints()
    frame:SetPoint(cfg.point or "CENTER", UIParent, cfg.point or "CENTER", cfg.x or 0, cfg.y or 0)
end

-- Mover overlay shown only while unlocked
local function ensureMover(frame, key)
    if frame.mover then return frame.mover end
    local host = frame.Overlay or frame  -- Overlay sits above the bars, so the tint+label show
    local m = host:CreateTexture(nil, "OVERLAY")
    m:SetAllPoints(frame)
    m:SetColorTexture(0.85, 0.65, 0.25, 0.15)
    frame.moverTex = m
    frame.mover = ns.UI:FS(host, 11)
    frame.mover:SetPoint("CENTER")
    frame.mover:SetText(key)
    frame.mover:SetTextColor(1, 0.82, 0)
    return frame.mover
end

local function setMoverState(frame, key, unlocked)
    ensureMover(frame, key)
    if InCombatLockdown() then return end -- visibility/UnitWatch changes only out of combat
    if frame.unit == "softenemy" then
        -- Mirrors the Target frame's rect exactly - there is nothing to
        -- move, so move mode hides it instead of stacking a second mover
        -- on top of the Target frame.
        UnregisterAttributeDriver(frame, "state-visibility")
        frame.moverTex:Hide(); frame.mover:Hide()
        if unlocked then
            frame:Hide()
        else
            local bc = ns.db.frames.target.borderColor
            frame:SetBackdropBorderColor(ns.UI:FrameBorderColor(frame, bc))
            RegisterAttributeDriver(frame, "state-visibility",
                "[@target,exists] hide; [@softenemy,exists] show; hide")
            ns.UpdateAll(frame)
        end
        return
    end
    if unlocked then
        UnregisterUnitWatch(frame)
        frame:Show()
        frame.moverTex:Show(); frame.mover:Show()
        frame:SetBackdropBorderColor(0.85, 0.65, 0.25, 1)
    else
        frame.moverTex:Hide(); frame.mover:Hide()
        local bc = ns.db.frames[key].borderColor
        frame:SetBackdropBorderColor(ns.UI:FrameBorderColor(frame, bc))
        if frame.unit ~= "player" then RegisterUnitWatch(frame) end
        if UnitExists(frame.unit) then frame:Show() end
        ns.UpdateAll(frame)
    end
end

-- One handler for every unit button (the boss and party-target buttons
-- of Extras.lua share it): each event to its painter.
local function OnUnitEvent(self, event, arg1, arg2)
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
    else -- PLAYER_ENTERING_WORLD / target change / UNIT_PET
        ns.UpdateAll(self)
    end
end
ns.UnitOnEvent = OnUnitEvent

-- A unit with no change event of its own (target of target, focus
-- target): a light poll, only while the frame is shown. The full pass
-- (auras, name, indicators, castbar) when the unit behind the frame
-- changed and once a second besides; the other four polls are health
-- and power.
local function PollOnUpdate(self, e)
    self.elapsed = self.elapsed + e
    if self.elapsed >= 0.2 then
        self.elapsed = 0
        if self:IsShown() and self.unit and UnitExists(self.unit) then
            local guid = UnitGUID(self.unit)
            self._pollN = (self._pollN or 0) + 1
            if guid ~= self._pollGUID or self._pollN >= 5 then
                self._pollGUID, self._pollN = guid, 0
                ns.UpdateAll(self)
            else
                ns.UpdateHealth(self)
                ns.UpdatePower(self)
            end
        end
    end
end
ns.UnitPollOnUpdate = PollOnUpdate

function ns.SpawnUnit(key)
    if ns.frames[key] then return ns.frames[key] end
    -- "softtarget" is the frame key; the unit it watches is the client's
    -- soft enemy (Tab-style acquire target while nothing is hard-targeted).
    -- It BORROWS the Target frame's cfg wholesale, so it always looks
    -- identical to the target frame - same size, colors, elements, texts -
    -- and any Target restyle carries over automatically.
    local cfg  = (key == "softtarget") and ns.db.frames.target or ns.db.frames[key]
    local unit = (key == "softtarget") and "softenemy" or key
    -- Global names deliberately match LibGetFrame's generic oUF patterns
    -- (^oUF_.-Player$, ^oUF_.-Target$, ^oUF_.-TargetTarget$): that library is
    -- how WeakAuras' "Anchored To: Unit Frames" classifies layouts, and these
    -- names put the player / target / ToT singles into its ignore lists so
    -- they can never steal a group unit's anchor from the raid or party frame
    -- showing the same person. The old ZacUF_* names stay as global aliases
    -- for existing "Select Frame" anchors and macros.
    local f = CreateFrame("Button", "oUF_ZacUF" .. (WA_NAME_SUFFIX[key] or key), UIParent, "SecureUnitButtonTemplate,BackdropTemplate")
    _G["ZacUF_" .. key] = f
    f.unit = unit
    f.cfg = cfg
    f:SetSize(cfg.width, cfg.height)
    applyPosition(f, cfg)
    if key == "softtarget" and ns.frames.target then
        -- Pinned to the Target frame's exact rect: they can never both be
        -- visible, so the soft frame simply IS the target frame's slot.
        f:ClearAllPoints()
        f:SetAllPoints(ns.frames.target)
    end
    ns.UI:FrameBackdrop(f, cfg.bgColor, cfg.borderColor)
    f:SetClampedToScreen(true)

    -- Secure interaction
    f:SetAttribute("unit", unit)
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")
    f:RegisterForClicks("AnyUp")
    if key == "softtarget" then
        -- Clicking the soft-target frame HARD-TARGETS the soft enemy - a
        -- secure unit click, so it works even in combat. A unit menu makes
        -- no sense for a mob you haven't targeted: both buttons target.
        f:SetAttribute("*type2", "target")
        -- Visible only while soft-engaged WITHOUT a hard target. With a
        -- hard target the real target frame owns the screen (and softenemy
        -- collapses into it on this client anyway). A secure visibility
        -- driver keeps show/hide combat-legal.
        RegisterAttributeDriver(f, "state-visibility",
            "[@target,exists] hide; [@softenemy,exists] show; hide")
    elseif unit ~= "player" then
        RegisterUnitWatch(f)
    end

    -- Click-casting support: register this secure unit button so click-cast
    -- addons (Clique, mouseover heal addons) can apply their bindings to it.
    -- The table is watched by Clique; setting it = true registers the frame,
    -- and it works regardless of which addon loaded first.
    ClickCastFrames = ClickCastFrames or {}
    ClickCastFrames[f] = true

    -- Visuals
    ns.BuildElements(f)

    -- Per-unit element events (registered to match the per-frame toggles)
    ns.RegisterFrameEvents(f)
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    if CHANGE_EVENT[unit] then f:RegisterEvent(CHANGE_EVENT[unit]) end
    if unit == "pet" then f:RegisterEvent("UNIT_PET") end

    f:SetScript("OnEvent", OnUnitEvent)

    f:SetScript("OnShow", function(self) ns.UpdateAll(self) end)

    -- Mouseover tracking so the PvP text can show only while the cursor is over
    -- this frame. Hooked (not Set) so it never clobbers secure click handling.
    f:HookScript("OnEnter", function(self) self.hovered = true;  ns.UpdatePvP(self) end)
    f:HookScript("OnLeave", function(self) self.hovered = false; ns.UpdatePvP(self) end)

    -- targettarget (and focustarget) have no change event -> light poll
    -- only while visible. softtarget polls too: UNIT_* events aren't
    -- reliably routed to the "softenemy" token on this client, so the
    -- 0.2s tick keeps HP honest.
    if unit == "targettarget" or unit == "focustarget" or key == "softtarget" then
        f.elapsed = 0
        f:SetScript("OnUpdate", PollOnUpdate)
    end

    -- Drag to move (gated by lock + combat)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if key == "softtarget" then return end -- pinned to the Target frame
        if not ns.db.locked and not InCombatLockdown() then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        local nx, ny = cx - ux, cy - uy
        if ns.SnapValue then nx, ny = ns.SnapValue(nx), ns.SnapValue(ny) end
        cfg.point, cfg.x, cfg.y = "CENTER", nx, ny
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "CENTER", cfg.x, cfg.y)
        if ns.RefreshMoveDialog then ns.RefreshMoveDialog() end
    end)
    f:SetScript("OnMouseDown", function(self)
        if key == "softtarget" then return end
        if not ns.db.locked and ns.SelectMoveFrame then ns.SelectMoveFrame(key) end
    end)

    -- Restyle hook used by ns.ApplySettings()
    f.LeanRestyle = function(self)
        -- size + position are protected on a secure frame; only touch them out of
        -- combat (the cosmetic restyle below is always safe). Prevents
        -- ADDON_ACTION_BLOCKED if settings change mid-combat.
        if not InCombatLockdown() and key ~= "softtarget" then
            self:SetSize(cfg.width, cfg.height)
            applyPosition(self, cfg)
        end
        ns.UI:FrameBackdrop(self, cfg.bgColor, cfg.borderColor)
        ns.StyleElements(self)
        ns.RegisterFrameEvents(self)
        ns.UpdateAuras(self)   -- re-place buffs/debuffs live on anchor/offset edits
        ns.UpdateIndicators(self)  -- refresh status icons live on toggle/size edits
        -- StyleElements clears the incoming-heal chips, and every options control
        -- routes through ApplySettings -> here. Without a repaint, touching any
        -- setting would blank the chips on this frame until the next health tick.
        -- (The group path already gets this via ns.UpdateAll in Groups.lua.)
        ns.UpdateHealth(self)
        ns.CastbarPreview(self, not ns.db.locked)  -- show a sample castbar to position/size in move mode
        setMoverState(self, key, not ns.db.locked)
        local Zr = ns.ZUI or _G.ZacUI
        if Zr and Zr.Visibility then Zr.Visibility.Refresh(self) end
    end

    ns.frames[key] = f
    -- the frame's visibility rule (cfg.visibility, ZacUI's visibility shape):
    -- one evaluator, alpha only, composed with the offline dim (Elements.lua)
    local Zv = ns.ZUI or _G.ZacUI
    if key ~= "softtarget" and Zv and Zv.Visibility then
        Zv.Visibility.Register(f, function() return f.cfg and f.cfg.visibility end,
            { control = "gate", onChange = ns.VisibilityApply })
    end
    setMoverState(f, key, not ns.db.locked)
    if unit == "player" then f:Show() end
    ns.UpdateAll(f)
    return f
end
