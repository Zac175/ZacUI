-- PreviewDrag - the unit frames' pieces for ZacUI's drag-to-customise
-- preview (UIF_PreviewDrag): every text and part of the sample frame can
-- be dragged (its anchor spec, cfg.anchors.<element>, the same one the
-- Text and Position tabs' X / Y write), the status icons, the castbar and
-- the frame itself resized by their edges (the Size / Width / Height
-- sliders' keys), the buff and debuff blocks moved as a whole (their
-- X / Y offsets). A party or raid preview hands over its first member:
-- every member shares the group's settings.
-- Part of Zacui_UnitFrames; load order is set by the TOC (after Options,
-- whose page wraps its frames preview through ns.UFDragAttach).

local _, ns = ...

local function Z() return ns.ZUI or _G.ZacUI end
local function Apply() if ns.ApplySettings then ns.ApplySettings() end end

-- what a game look's frame kit (Kit.lua: Classic WoW UI, Blizzard style,
-- WoW Forever) places itself, whatever the settings say: the frame's box
-- (the art's size), the name (where the art has its name), the power bar
-- (in the art's track) and the name strip (hidden). Offered for dragging
-- there, they would write a setting and not move - so they are not.
local KIT_OWNS = { name = true, power = true, nameStrip = true }

-- the parts with a size of their own (the status icons) and its range
local ICON_SIZE = { combat = "combatSize", leader = "leaderSize", role = "roleSize", raid = "raidSize", rez = "rezSize" }

local function IsGroup(mode) return mode == "party" or mode == "raid" end
local function CfgOf(mode)
    if not ns.db then return nil end
    if IsGroup(mode) then return ns.db[mode] end
    return ns.db.frames and (ns.db.frames[mode] or ns.db.frames.player)
end
local function DefOf(mode)
    local d = ns.defaults
    if not d then return nil end
    if IsGroup(mode) then return d[mode] end
    return d.frames and (d.frames[mode] or d.frames.player)
end

-- the Look tab's ranges for the frame's own size
local function FrameRange(mode)
    if mode == "raid" then return 50, 200, 20, 80 end
    if mode == "party" then return 80, 320, 20, 80 end
    return 60, 320, 16, 80
end

local function Pieces(canvas, P)
    local zc = Z()
    if not (zc and zc.CustomAccess and ns.ElementTarget) then return nil end
    local st = P and P.store
    if not st then return nil end
    local mode = P.mode or "player"
    local f
    if IsGroup(mode) then f = st[mode] and st[mode][1]
    elseif ns.ExtraFrame and ns.ExtraFrame(mode) and ns.ExtraFrame(mode).layout then
        f = st.extra and st.extra[1]   -- a set of an extra file (the boss frames): its first, as a group's
    else f = st.single end
    if not (f and f:IsShown()) then return nil end
    local cfg, def = CfgOf(mode), DefOf(mode)
    if not cfg then return nil end
    local list = {}
    local kit = rawget(f, "_zKitOn") and true or false

    -- the frame: its edges set its width and height
    local wLo, wHi, hLo, hHi = FrameRange(mode)
    if not kit then list[#list + 1] = { key = "frame", label = "The frame", region = f, noMove = true,
        -- its size is on the Look tab ("Size of this frame")
        open = function()
            local st = zc.ConfigState and zc.ConfigState()
            if not st then return end
            st.tabs = st.tabs or {}
            st.tabs.unitframes = "look"
            if zc.RefreshConfig then zc.RefreshConfig() end
        end,
        size = { min = wLo, max = wHi, minH = hLo, maxH = hHi,
            get = function() return cfg.width, cfg.height end,
            set = function(w, h)
                if w then cfg.width = w end
                if h then cfg.height = h end
                Apply()
            end,
            reset = def and function()
                cfg.width, cfg.height = def.width, def.height
                Apply()
            end or nil } } end

    local function Add(key)
        if kit and KIT_OWNS[key] then return end
        local r = ns.ElementTarget(f, key)
        if not r then return end
        local get, set = zc.CustomAccess(cfg, "anchors", key, Apply)
        local piece = { key = key, label = (ns.ANCHOR_LABELS and ns.ANCHOR_LABELS[key]) or key, region = r,
            anchor = { get = get, set = set, defaults = function() return ns.AnchorDefaults(cfg, key) end } }
        local sk = ICON_SIZE[key]
        if sk then
            piece.size = { square = true, min = 6, max = 40,
                get = function() return cfg[sk], cfg[sk] end,
                set = function(w) if w then cfg[sk] = w Apply() end end,
                reset = def and def[sk] and function() cfg[sk] = def[sk] Apply() end or nil }
        elseif key == "castbar" then
            -- 0 = automatic (the frame's width, the castbar height)
            piece.size = { min = 20, max = 400, minH = 4, maxH = 60,
                get = function() return cfg.cbWidth, cfg.cbHeight end,
                set = function(w, h)
                    if w then cfg.cbWidth = w end
                    if h then cfg.cbHeight = h end
                    Apply()
                end,
                reset = function() cfg.cbWidth, cfg.cbHeight = 0, 0 Apply() end }
        end
        list[#list + 1] = piece
    end
    for _, k in ipairs(ns.ANCHOR_TEXTS or {}) do Add(k) end
    for _, k in ipairs(ns.ANCHOR_PARTS or {}) do Add(k) end

    -- the buff and debuff blocks: their icons move together, writing the
    -- blocks' offsets (buffX / buffY, debuffX / debuffY - the Position
    -- tab's sliders; the anchor presets stay)
    for _, blk in ipairs({ { "buffs", "buffX", "buffY", "Buffs" }, { "debuffs", "debuffX", "debuffY", "Debuffs" } }) do
        local icons = {}
        for _, b in ipairs(f.auraIcons or {}) do
            if b._zBlock == blk[1] and b:IsShown() then icons[#icons + 1] = b end
        end
        if #icons > 0 then
            local kx, ky = blk[2], blk[3]
            list[#list + 1] = { key = blk[1], label = blk[4], region = icons,
                -- (their X / Y are on the Position tab, "Place and size an element")
                open = function()
                    local st = zc.ConfigState and zc.ConfigState()
                    if not st then return end
                    st.tabs = st.tabs or {}
                    st.tabs.unitframes = "pos"
                    if zc.RefreshConfig then zc.RefreshConfig() end
                end,
                move = {
                    get = function() return cfg[kx] or 0, cfg[ky] or 0 end,
                    set = function(x, y) cfg[kx], cfg[ky] = x, y Apply() end,
                    reset = def and function() cfg[kx], cfg[ky] = def[kx] or 0, def[ky] or 0 Apply() end or nil,
                    -- (the block's offsets are the frame's units)
                    eff = function() return f:GetEffectiveScale() end } }
        end
    end
    return list, f
end

-- the frames preview spec, made draggable (or as it was, without ZacUI's helper)
function ns.UFDragAttach(spec)
    local zc = Z()
    if not (zc and zc.PreviewDrag and zc.PreviewDrag.Attach) then return spec end
    return zc.PreviewDrag.Attach(spec, { pieces = Pieces })
end
ns.UFDragPieces = Pieces
do
    local zc = Z()
    if zc and zc.PreviewDrag and zc.PreviewDrag.Keywords then zc.PreviewDrag.Keywords("unitframes") end
end
