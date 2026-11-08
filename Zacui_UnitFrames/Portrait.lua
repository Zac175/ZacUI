-- ============================================================================
-- Zacui_UnitFrames - Portrait.lua
-- A portrait on a unit frame: the unit's face as the game draws it (2D),
-- its class icon, or a small 3D model. OFF on every frame until it is
-- switched on (cfg.portrait.enabled, Config.lua), so a frame without one
-- is built, styled and laid out exactly as it always was - nothing here
-- runs for it beyond a nil check.
--
-- The portrait is a square beside the bars: the bars make room for it
-- inside the frame ("shrink"), or it sits beside the frame, which stays as
-- it is ("outside"), or it lies over the bar's end ("inside"). It wears the
-- frame's own border and background colours. The square is as tall as the
-- frame unless given a size of its own.
--
-- Wired in from the outside, on top of Elements.lua's constructors
-- (BuildElements / StyleElements / UpdateAll / ElementTarget): this file
-- loads after it and wraps those four, so Elements.lua itself is not
-- touched. The portrait's host frame is made the first time a frame turns
-- it on, so a frame that never does carries nothing extra.
--
-- Updates: the frame's own full refresh (UpdateAll: shown, target change,
-- unit reassigned) and the game's portrait events (UNIT_PORTRAIT_UPDATE,
-- PORTRAITS_UPDATED, UNIT_MODEL_CHANGED) and the roster notice, coalesced
-- into one pass a moment later - nothing per health tick. A 3D model is
-- only reloaded when the unit behind the frame changed (by GUID where the
-- game shows it; by the unit token and the events alone where it keeps it
-- hidden - WoW Forever in combat - so no hidden value is ever compared).
-- Only unit tokens reach the game: nothing is asked for a unit that does
-- not exist.
-- ============================================================================
local ADDON, ns = ...

local WHITE = "Interface\\Buttons\\WHITE8X8"
local CLASS_CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local FALLBACK_TCOORDS = {
    WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.5, 0, 0.25 }, ROGUE = { 0.5, 0.75, 0, 0.25 },
    DRUID = { 0.75, 1, 0, 0.25 }, HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.5, 0.25, 0.5 },
    PRIEST = { 0.5, 0.75, 0.25, 0.5 }, WARLOCK = { 0.75, 1, 0.25, 0.5 }, PALADIN = { 0, 0.25, 0.5, 0.75 },
    DEATHKNIGHT = { 0.25, 0.5, 0.5, 0.75 }, MONK = { 0.5, 0.75, 0.5, 0.75 }, DEMONHUNTER = { 0.75, 1, 0.5, 0.75 },
    EVOKER = { 0, 0.25, 0.75, 1 },
}
local NO_COLOR = { 0, 0, 0, 0 }
-- the square portrait's crop (ZacUI's look): the middle of the game's round
-- portrait art, past its dark rim (the rim sits in the outer ~13% of the
-- art; Blz_UnitFrames squares Blizzard's portraits the same 0.15 way)
local FACE_CROP = 0.15
-- the class icon's ring: this much of each cell's side off every edge
local CLASS_RING = 0.12
local lookArt   -- the game looks' portrait art (below StylePortrait's helpers)

-- a frame wearing a game look's kit (Kit.lua) always has its portrait: the
-- face in the art's ring, as the game's frames have it (the reference
-- forces it on the same way); the kit places and masks it
local KIT_PORTRAIT = { style = "2d", classIcon = false, side = "LEFT", layout = "inside",
    size = 0, gap = 0, border = false, background = false, zoom = 1 }

-- the frame's portrait settings, when it has any and they say on
local function Settings(frame)
    if frame and frame._zKitKind then return KIT_PORTRAIT end
    local cfg = frame and frame.cfg
    local pc = cfg and cfg.portrait
    if type(pc) ~= "table" or not (ns.PortraitOn and ns.PortraitOn(cfg)) then return nil end
    return pc
end
ns.PortraitSettings = Settings

-- a hidden value (WoW Forever) is never compared: nil stands for it
local function plain(v)
    if issecretvalue ~= nil and issecretvalue(v) then return nil end
    return v
end

-- ----------------------------------------------------------------------------
-- The host: a bordered square (the frame's colours) holding a texture for
-- the 2D face / class icon, and a model made only when 3D is picked.
-- ----------------------------------------------------------------------------
local function ensureHost(frame)
    local p = frame.Portrait
    if p then return p end
    p = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    -- above the bars (+1 / +2), under the text overlay (+5) and the castbar
    p:SetFrameLevel(frame:GetFrameLevel() + 3)
    p._zElement = "portrait"   -- the preview's "customize this element"
    local t = p:CreateTexture(nil, "ARTWORK")
    t:SetPoint("TOPLEFT", 1, -1)
    t:SetPoint("BOTTOMRIGHT", -1, 1)
    t:Hide()
    p.tex = t
    p:Hide()
    frame.Portrait = p
    if ns.PortraitEvents then ns.PortraitEvents() end
    return p
end

-- the 3D camera on the face; put back whenever the model (re)loads
local function frameModel(m)
    if m.SetCamDistanceScale then m:SetCamDistanceScale(1) end
    if m.SetPortraitZoom then m:SetPortraitZoom(m._zoom or 1) end
    if m.SetPosition then m:SetPosition(0, 0, 0) end
    if m.SetRotation then m:SetRotation(0) end
end

local function ensureModel(p)
    local m = p.model
    if m then return m end
    m = CreateFrame("PlayerModel", nil, p)
    m:SetPoint("TOPLEFT", 1, -1)
    m:SetPoint("BOTTOMRIGHT", -1, 1)
    m._zoom = 1
    -- WoW Forever loads the model after SetUnit returns and resets the
    -- camera when it lands (Win_Paperdoll found the head cut off): the
    -- framing goes back on once it is in. Classic sets the model up at
    -- once and never fires this, so it costs nothing there.
    if m.HasScript and m:HasScript("OnModelLoaded") then
        m:SetScript("OnModelLoaded", function(self) frameModel(self) end)
    end
    m:Hide()
    p.model = m
    return m
end

-- a frame with a portrait whose settings changed shape: forget what the
-- model shows so the next paint sets it again
local function forgetModel(p)
    p._munit, p._mguid = nil, nil
end

-- ----------------------------------------------------------------------------
-- Layout: where the square sits and what the bars do about it. Called after
-- Elements.lua's StyleElements has laid the frame out as it always did, so
-- with the portrait off there is nothing to undo but what this once moved.
-- ----------------------------------------------------------------------------
local function restoreBars(frame)
    local p = frame.Portrait
    if not (p and p._shrunk) then return end
    p._shrunk = nil
    -- Health and Power were re-placed by StyleElements already (it clears
    -- and sets their points every time); the Overlay is the one thing it
    -- never re-anchors
    frame.Overlay:SetAllPoints(frame)
end

-- the square's side for a frame cfg: its own size, else the frame's height
-- (inside the frame's 1px border for the two placements inside it)
function ns.PortraitSize(cfg)
    local pc = cfg and cfg.portrait
    local h = (cfg and cfg.height) or 30
    local size = pc and tonumber(pc.size) or 0
    if size <= 0 then
        size = (pc and pc.layout == "outside") and h or (h - 2)
    end
    return math.max(4, size)
end

-- ----------------------------------------------------------------------------
-- A game look's portrait art (2026-11-07, Zac: portraits on under the game's
-- looks, in each look's own art). Core_Look's look.portrait = { mask, ring,
-- ringScale, badge } wins; until a look carries one, the names below - read
-- in wow-ui-source (Blizzard_UnitFrame/Camelot/PlayerFrameTemplates.xml:11
-- for the Forever level circle, Mainline/PlayerFrame.xml:32 for the mask).
-- A name with no backslash is an atlas, used only when the client knows
-- it (C_Texture.GetAtlasInfo); else the round mask every client ships.
-- ----------------------------------------------------------------------------
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local LOOK_PORTRAIT = {
    classic  = { mask = ROUND_MASK },
    forever  = { mask = "UI-HUD-UnitFrame-Player-Portrait-Mask", badge = "UI-HUD-UnitFrame-SmallCircle" },
    blizzard = { mask = "UI-HUD-UnitFrame-Player-Portrait-Mask" },
}
local function isAtlas(name) return type(name) == "string" and not name:find("\\", 1, true) end
local function atlasInfo(name)
    local CT = _G.C_Texture
    if not (isAtlas(name) and CT and CT.GetAtlasInfo) then return nil end
    local ok, info = pcall(CT.GetAtlasInfo, name)
    return ok and type(info) == "table" and info or nil
end
-- the look's portrait spec, nil under ZacUI's own look
local function lookPortrait()
    local Z = _G.ZacUI
    local ok, look = pcall(function() return Z and Z.Look and Z.Look.For("unitframes") end)
    if not (ok and type(look) == "table") or look.id == "zacui" then return nil end
    return (type(look.portrait) == "table" and look.portrait) or LOOK_PORTRAIT[look.id] or { mask = ROUND_MASK }
end
-- dresses p in the look's art; false (and every piece hidden) under ZacUI's
lookArt = function(p, size, right)
    local spec = lookPortrait()
    if not spec then
        if p._lookMask and p.tex.RemoveMaskTexture then pcall(p.tex.RemoveMaskTexture, p.tex, p._lookMask) p._lookMasked = nil end
        if p._lookRing then p._lookRing:Hide() end
        if p._lookBadge then p._lookBadge:Hide() p._lookLevel:Hide() end
        p._badgeOn = nil
        return false
    end
    if p.CreateMaskTexture and p.tex.AddMaskTexture then
        if not p._lookMask then
            p._lookMask = p:CreateMaskTexture()
            p._lookMask:SetAllPoints(p.tex)
        end
        local m = p._lookMask
        if atlasInfo(spec.mask) then
            m:SetAtlas(spec.mask)
        else
            m:SetTexture(isAtlas(spec.mask) and ROUND_MASK or (spec.mask or ROUND_MASK),
                "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        end
        if not p._lookMasked then p.tex:AddMaskTexture(m) p._lookMasked = true end
    end
    if spec.ring then
        if not p._lookRing then p._lookRing = p:CreateTexture(nil, "OVERLAY") end
        local k = tonumber(spec.ringScale) or 1.3
        p._lookRing:ClearAllPoints()
        p._lookRing:SetPoint("CENTER", p, "CENTER", 0, 0)
        p._lookRing:SetSize(size * k, size * k)
        if atlasInfo(spec.ring) then p._lookRing:SetAtlas(spec.ring) else p._lookRing:SetTexture(spec.ring) end
        p._lookRing:Show()
    elseif p._lookRing then
        p._lookRing:Hide()
    end
    -- the level in a small circle on the portrait's lower outer corner
    local info = atlasInfo(spec.badge)
    if info then
        if not p._lookBadge then
            p._lookBadge = p:CreateTexture(nil, "OVERLAY", nil, 6)
            p._lookLevel = p:CreateFontString(nil, "OVERLAY")
            pcall(p._lookLevel.SetFontObject, p._lookLevel, "GameFontNormalSmall")
        end
        local b = p._lookBadge
        b:SetAtlas(spec.badge)
        local bs = math.max(10, math.floor(size * 0.36 + 0.5))
        local w, h = tonumber(info.width) or bs, tonumber(info.height) or bs
        local k = bs / math.max(1, h)
        b:SetSize(w * k, h * k)
        b:ClearAllPoints()
        b:SetPoint("CENTER", p, right and "BOTTOMRIGHT" or "BOTTOMLEFT", right and -bs * 0.35 or bs * 0.35, bs * 0.35)
        p._lookLevel:ClearAllPoints()
        p._lookLevel:SetPoint("CENTER", b, "CENTER", 0, 0)
        b:Show()
        p._lookLevel:Show()
        p._badgeOn = true
    else
        if p._lookBadge then p._lookBadge:Hide() p._lookLevel:Hide() end
        p._badgeOn = nil
    end
    return true
end

function ns.StylePortrait(frame)
    local cfg = frame.cfg or {}
    local pc = Settings(frame)
    if not pc then
        local p = frame.Portrait
        if p then
            p.on, p._styledOn = false, nil
            restoreBars(frame)
            p:Hide()
            if p.model then p.model:Hide() if p.model.ClearModel then p.model:ClearModel() end end
            forgetModel(p)
        end
        return
    end
    local p = ensureHost(frame)
    local wasOn = p._styledOn
    p.on, p._styledOn = true, true
    local size = ns.PortraitSize(cfg)
    local gap = math.max(0, tonumber(pc.gap) or 2)
    local right = (pc.side == "RIGHT")
    local layout = pc.layout or "shrink"
    if layout ~= "outside" and layout ~= "inside" then layout = "shrink" end
    -- a square too wide for the bars to make room for is held back
    if layout == "shrink" then
        local width = cfg.width or 100
        if size + gap > width - 24 then size = math.max(4, width - 24 - gap) end
    end
    p:SetSize(size, size)
    p:ClearAllPoints()
    if layout == "outside" then
        if right then p:SetPoint("LEFT", frame, "RIGHT", gap, 0)
        else p:SetPoint("RIGHT", frame, "LEFT", -gap, 0) end
    else
        if right then p:SetPoint("RIGHT", frame, "RIGHT", -1, 0)
        else p:SetPoint("LEFT", frame, "LEFT", 1, 0) end
    end
    -- the frame's own border and background, or neither; under one of the
    -- game's looks (Classic, WoW Forever, Blizzard style) that look's own
    -- portrait art instead (lookArt below) and no square box
    if lookArt(p, size, right) then
        ns.UI:Backdrop(p, NO_COLOR, NO_COLOR)
    else
        ns.UI:Backdrop(p, pc.background and cfg.bgColor or NO_COLOR, pc.border and cfg.borderColor or NO_COLOR)
    end

    -- the bars make room: the health bar, the power bar (unless its place
    -- was chosen by hand) and the text overlay all start past the square,
    -- so every text keeps its spot on the bars
    restoreBars(frame)
    if layout == "shrink" then
        local extra = size + gap
        local hb, pb, ov = frame.Health, frame.Power, frame.Overlay
        local custom = type(cfg.anchors) == "table" and cfg.anchors.power
        if right then
            hb:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1 - extra, -1)
            if pb and not custom then pb:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1 - extra, 1) end
            ov:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -extra, 0)
        else
            hb:SetPoint("TOPLEFT", frame, "TOPLEFT", 1 + extra, -1)
            if pb and not custom then pb:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1 + extra, 1) end
            ov:SetPoint("TOPLEFT", frame, "TOPLEFT", extra, 0)
        end
        -- the name's field was sized to the whole frame: as much narrower
        -- as the bars are now, never under the floor StyleElements keeps
        local nm = frame.Name
        if nm and not (cfg.name and ns.db.name.showStrip) then
            local floor = math.min((cfg.width or 100) - 8, 32)
            nm:SetWidth(math.max(floor, (nm:GetWidth() or 0) - extra))
        end
        p._shrunk = true
    end

    -- which kind draws
    local kind = (pc.style == "3d") and "3d" or "2d"
    if kind == "3d" then
        local m = ensureModel(p)
        m._zoom = tonumber(pc.zoom) or 1
        p.tex:Hide()
        m:Show()
        if p._mkind ~= "3d" then forgetModel(p) end
        p._mkind = "3d"
        frameModel(m)
    else
        if p.model then p.model:Hide() end
        p.tex:Show()
        p._mkind = "2d"
    end
    p:Show()
    -- a live frame shows its unit right away (a settings change does not
    -- come through UpdateAll on the single frames); samples are painted by
    -- their own code
    if frame.unit then ns.UpdatePortrait(frame, not wasOn) end
end

-- ----------------------------------------------------------------------------
-- Painting. unit: a live unit token (the real frames); d: a made-up person
-- (the settings preview, the move-mode placeholders) with isPlayer / class
-- and maybe a `portrait` icon. force: set the 3D model again even for the
-- same unit (the portrait events).
-- ----------------------------------------------------------------------------
local function tcoords(class)
    local t = (CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]) or FALLBACK_TCOORDS[class]
    return t
end

local function clear(p)
    p.tex:SetTexture(nil)
    if p.model then
        if p.model.ClearModel then p.model:ClearModel() end
        forgetModel(p)
    end
end

function ns.PaintPortrait(frame, unit, d, force)
    local p = frame.Portrait
    if not (p and p.on) then return end
    local pc = Settings(frame)
    if not pc then return end
    if unit and not UnitExists(unit) then clear(p) return end
    local isPlayer, class
    if unit then
        isPlayer = UnitIsPlayer(unit)
        if isPlayer and pc.classIcon then
            local _, c = UnitClass(unit)
            class = plain(c)
        end
    elseif d then
        isPlayer, class = d.isPlayer, pc.classIcon and d.class or nil
    end

    if p._mkind == "3d" and p.model then
        local m = p.model
        if unit then
            local guid = plain(UnitGUID(unit))
            local same
            if guid ~= nil then same = (guid == p._mguid) and (unit == p._munit)
            else same = (unit == p._munit) end
            if force or not same then
                m:SetUnit(unit)
                p._munit, p._mguid = unit, guid
                frameModel(m)
            end
        else
            -- a sample: your own character stands in for every player, a
            -- creature of the preview's choosing for the rest
            local want = (d and d.isPlayer) and "player" or (d and d.creature) or "player"
            if force or p._munit ~= want then
                if want == "player" then
                    if UnitExists("player") then m:SetUnit("player") end
                elseif m.SetCreature then
                    m:SetCreature(want)
                else
                    m:SetUnit("player")
                end
                p._munit, p._mguid = want, nil
                frameModel(m)
            end
        end
        return
    end

    -- 2D: the class icon, the game's portrait, or a sample's own picture.
    -- Under ZacUI's own look the square box holds it: the game's round
    -- portrait art is cropped to its middle (FACE_CROP), so its dark rim and
    -- its transparent corners go and the face meets the box's one edge
    -- (2026-11-08, Zac: "a black circle around my characters head then a
    -- lighter grey border"); the class icon's ring goes the same way. The
    -- game looks keep the round art in their round mask.
    local t = p.tex
    local square = not lookPortrait()
    local tc = class and tcoords(class)
    -- (the icon zoom's re-crop lets go of it: each branch sets its own
    -- coords; the icon ones below hand it back to the helper)
    if ZacUI.Look and ZacUI.Look.ForgetIcon then ZacUI.Look.ForgetIcon(t) end
    if tc then
        t:SetTexture(CLASS_CIRCLES)
        if square then
            local iw, ih = (tc[2] - tc[1]) * CLASS_RING, (tc[4] - tc[3]) * CLASS_RING
            t:SetTexCoord(tc[1] + iw, tc[2] - iw, tc[3] + ih, tc[4] - ih)
        else
            t:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
        end
    elseif unit then
        -- (the crop after the art: the client's portrait call may set coords)
        if SetPortraitTexture then
            SetPortraitTexture(t, unit)
            if square then t:SetTexCoord(FACE_CROP, 1 - FACE_CROP, FACE_CROP, 1 - FACE_CROP)
            else t:SetTexCoord(0, 1, 0, 1) end
        else t:SetTexture(QUESTION) ZacUI.Look.CropIcon(t) end
    elseif d and d.portrait then
        t:SetTexture(d.portrait)
        -- (a sample's portrait is an icon: cropped as every icon is)
        ZacUI.Look.CropIcon(t)
    elseif d and d.isPlayer and SetPortraitTexture and UnitExists("player") then
        SetPortraitTexture(t, "player")
        if square then t:SetTexCoord(FACE_CROP, 1 - FACE_CROP, FACE_CROP, 1 - FACE_CROP)
        else t:SetTexCoord(0, 1, 0, 1) end
    else
        t:SetTexture(QUESTION)
        ZacUI.Look.CropIcon(t)
    end
end

-- a live frame: its unit, as it stands
function ns.UpdatePortrait(frame, force)
    local p = frame.Portrait
    if not (p and p.on) then return end
    local unit = frame.unit
    if not unit or not UnitExists(unit) then clear(p) return end
    ns.PaintPortrait(frame, unit, nil, force)
    -- the look's level circle (lookArt): the level, "??" for a skull
    if p._badgeOn and p._lookLevel then
        local lv = UnitLevel and UnitLevel(unit)
        if issecretvalue ~= nil and issecretvalue(lv) then
            p._lookLevel:SetText("")
        else
            p._lookLevel:SetText((type(lv) == "number" and lv > 0) and tostring(lv) or "??")
        end
    end
end

-- ----------------------------------------------------------------------------
-- The game's portrait events, and the roster: one pass over the frames that
-- wear a portrait, a moment after the burst.
-- ----------------------------------------------------------------------------
local armed = false
local function flush()
    armed = false
    for f in pairs(ns.unitButtons or {}) do
        local p = f.Portrait
        if p and p.on and f.unit and f:IsVisible() then ns.UpdatePortrait(f, true) end
    end
end
local function refreshAll()
    if armed then return end
    armed = true
    C_Timer.After(0.1, flush)
end
ns.RefreshPortraits = refreshAll

-- listened for from the first portrait on (ensureHost): a UI without one
-- has no frame and no listener of the portraits' at all
local ev
local function ensureEvents()
    if ev then return end
    ev = CreateFrame("Frame")
    for _, e in ipairs({ "UNIT_PORTRAIT_UPDATE", "PORTRAITS_UPDATED", "UNIT_MODEL_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP" }) do
        pcall(ev.RegisterEvent, ev, e)   -- a client without one of these keeps the rest
    end
    ev:SetScript("OnEvent", refreshAll)
    local Z = _G.ZacUI
    if Z and Z.Roster and Z.Roster.On then
        Z.Roster.On("ZacUF.portraits", refreshAll)
    else
        pcall(ev.RegisterEvent, ev, "GROUP_ROSTER_UPDATE")
    end
end
ns.PortraitEvents = ensureEvents

-- ----------------------------------------------------------------------------
-- On top of Elements.lua: the frame's constructors call these by name, so
-- wrapping them here reaches every frame (live, placeholder and sample).
-- ----------------------------------------------------------------------------
do
    local style, update, target = ns.StyleElements, ns.UpdateAll, ns.ElementTarget
    -- (BuildElements styles through ns.StyleElements, so a new frame gets
    -- its portrait laid out by this same wrapper; nothing to build apart)
    -- before the frame is laid out, the portrait is known to be on or off
    -- (its host made on the first time), so a text hung off it finds it in
    -- the same pass that switches it on
    local function prepare(frame)
        local pc = Settings(frame)
        if pc then ensureHost(frame).on = true
        elseif frame.Portrait then frame.Portrait.on = false end
    end
    if style then
        ns.StyleElements = function(frame, ...)
            prepare(frame)
            style(frame, ...)
            ns.StylePortrait(frame)
        end
    end
    if update then
        ns.UpdateAll = function(frame, ...)
            update(frame, ...)
            if frame.Portrait and frame.Portrait.on and frame.unit then ns.UpdatePortrait(frame) end
        end
    end
    if target then
        ns.ElementTarget = function(frame, key, ...)
            if key == "portrait" then
                -- only while it is on: a text hung off a portrait that is
                -- off falls back to its usual spot
                local p = frame and frame.Portrait
                return (p and p.on) and p or nil
            end
            return target(frame, key, ...)
        end
    end
    -- texts and parts can hang off the portrait (the anchor pickers' list)
    if ns.ANCHOR_TARGETS then
        local have = false
        for _, k in ipairs(ns.ANCHOR_TARGETS) do if k == "portrait" then have = true end end
        if not have then ns.ANCHOR_TARGETS[#ns.ANCHOR_TARGETS + 1] = "portrait" end
    end
    if ns.ANCHOR_LABELS then ns.ANCHOR_LABELS.portrait = "Portrait" end
end
