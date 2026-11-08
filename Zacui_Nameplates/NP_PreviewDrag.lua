-- NP_PreviewDrag - the nameplates' pieces for ZacUI's drag-to-customise
-- preview (UIF_PreviewDrag): on the first sample plate of the scene on
-- show, every text and part moves through its side's anchor spec
-- (d.enemy.anchors.<key> / d.friendly.anchors.<key>, what the Text and
-- Position tabs' X / Y write); the health bar, the cast bar, the cast
-- icon, the raid marker and the threat bar resize by their edges (the
-- Look tab's size sliders' keys). Enemy plates keep their in-combat size
-- equal to the resting one, as the Look tab's sliders do.
-- Part of ZacUI; load order is set by the TOC (after Config_PagesNameplates).

local ns = _G.ZacUI
if not ns then return end

local function NP() return ns.Nameplates end
local function Refresh() local N = NP() if N and N.RefreshAll then N.RefreshAll() end end

local function Pieces(canvas, P)
    local N = NP()
    if not (N and N.DB and N.ElementTarget and ns.CustomAccess) then return nil end
    local st = P and P.store
    local mode = (P.mode and st and st.sets and st.sets[P.mode]) and P.mode or "enemy"
    local set = st and st.sets and st.sets[mode]
    local f = set and set.plates and set.plates[1]
    if not (f and f:IsVisible()) then return nil end
    local d = N.DB()
    local side = f.isFriend and "friendly" or "enemy"
    local cfg = d[side]
    if type(cfg) ~= "table" then return nil end
    local combat = f.isFriend and f._pvCombat
    local list = {}

    local function Add(key, size)
        local r = N.ElementTarget(f, key)
        if not r then return end
        local get, set2 = ns.CustomAccess(cfg, "anchors", key, Refresh)
        list[#list + 1] = { key = key, pick = "np." .. key, label = (N.ANCHOR_LABELS and N.ANCHOR_LABELS[key]) or key,
            region = r, size = size,
            anchor = { get = get, set = set2, defaults = function() return N.AnchorDefaults(side, key) end } }
    end
    for _, k in ipairs(N.ANCHOR_TEXTS or {}) do Add(k) end
    for _, k in ipairs(N.ANCHOR_PARTS or {}) do
        local size
        if k == "castbar" then
            local lo = f.isFriend and 40 or 60
            size = { min = lo, max = 220, minH = 4, maxH = 32,
                get = function() return cfg.castWidth, cfg.castHeight end,
                set = function(w, h)
                    if w then cfg.castWidth = w end
                    if h then cfg.castHeight = h end
                    Refresh()
                end }
        elseif k == "castIcon" then
            size = { square = true, min = 6, max = 48,
                get = function() local v = tonumber(cfg.castIconSize) return v, v end,
                set = function(w) if w then cfg.castIconSize = w Refresh() end end,
                reset = function() cfg.castIconSize = nil Refresh() end }
        elseif k == "raidMarker" then
            -- 0 = automatic (a shade taller than the bar)
            size = { square = true, min = 1, max = 32,
                get = function() return cfg.markerSize, cfg.markerSize end,
                set = function(w) if w then cfg.markerSize = w Refresh() end end }
        elseif k == "threatBar" and type(d.threatBar) == "table" then
            local tbd = d.threatBar
            size = { min = 10, max = 220, minH = 1, maxH = 12,
                get = function() return tbd.width, tbd.height end,
                set = function(w, h)
                    if w then tbd.width = w end
                    if h then tbd.height = h end
                    Refresh()
                end }
        end
        Add(k, size)
    end

    -- the health bar: its edges set the plate's size
    if f.health then
        local wk, hk = combat and "combatWidth" or "width", combat and "combatHeight" or "height"
        list[#list + 1] = { key = "health", pick = "np.health", label = "Health bar", region = f.health, noMove = true,
            size = { min = 60, max = 220, minH = 4, maxH = 32,
                get = function() return cfg[wk], cfg[hk] end,
                set = function(w, h)
                    if w then cfg[wk] = w end
                    if h then cfg[hk] = h end
                    if side == "enemy" then cfg.combatWidth, cfg.combatHeight = cfg.width, cfg.height end
                    Refresh()
                end } }
    end
    return list, f
end

local PD = ns.PreviewDrag
if PD and PD.Register then PD.Register("nameplates.plates", { pieces = Pieces }) end
ns.NPDragPieces = Pieces
if PD and PD.Keywords then PD.Keywords("nameplates") end
