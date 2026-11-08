-- Config_PreviewDrag - ZacUI's own pages' pieces for the drag-to-customise
-- preview (UIF_PreviewDrag), each registered by its preview key so the
-- pages themselves are untouched:
--   screen.tooltips  the health numbers (cfg.anchors.health) and the health
--                    bar's height (barHeight; 0 = automatic)
--   screen.buffs     the time left and the stack number on the icons
--                    (auraStyle.anchors.timer / .count)
--   screen.minimap   the map-only look's pills (anchors.<zone|clock|coords|
--                    friends|guild>), the panel look's texts
--                    (anchors.<panelZone|...>) and the corner icons
--                    (anchors.<mail|tracking|battlefield|lfg>)
-- Every write goes through the same ns.CustomAccess pair and refresh the
-- page's own picker uses.
-- Part of ZacUI; load order is set by the TOC (after the pages).

local ADDON_NAME, ns = ...

local PD = ns.PreviewDrag
if not (PD and PD.Register) then return end

local function Visible(r) return r and r.IsVisible and r:IsVisible() and r or nil end

-- ============================================================
-- TOOLTIP
-- ============================================================
local HP_DEF = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }
local function TipCfg() return ns.TipCfg and ns.TipCfg() or {} end
PD.Register("screen.tooltips", { pieces = function(canvas, P)
    local st = P and P.store
    local tt, bar = st and st.tt, st and st.bar
    if not (Visible(tt) and Visible(bar)) then return nil end
    local list = {}
    if bar._zui_text then
        local get, set = ns.CustomAccess(TipCfg, "anchors", "health")
        list[#list + 1] = { key = "health", pick = "tooltip.health", label = "Health numbers", region = bar._zui_text,
            anchor = { get = get, set = set, defaults = HP_DEF } }
    end
    list[#list + 1] = { key = "bar", pick = "tooltip.look", label = "Health bar", region = bar, noMove = true,
        size = { axis = "y", min = 1, max = 24,
            get = function() local v = TipCfg().barHeight return v, v end,
            set = function(_, h) if h then TipCfg().barHeight = h end end,
            reset = function() TipCfg().barHeight = nil end } }
    return list, tt
end })

-- ============================================================
-- PLAYER BUFFS AND DEBUFFS
-- ============================================================
local function BuffCfg() return ns.BuffLook and ns.BuffLook.Cfg() or {} end
local function Restyle() if ns.ApplyAuraStride then ns.ApplyAuraStride() end end
local AURA_LABEL = { timer = "Time left", count = "Stack number" }
PD.Register("screen.buffs", { pieces = function(canvas, P)
    local st = P and P.store
    if not (st and st.all) then return nil end
    local list, container = {}, nil
    for _, key in ipairs({ "timer", "count" }) do
        for _, b in ipairs(st.all) do
            local r = (key == "timer") and b._zTimer or b.Count
            if Visible(r) and r.GetText and (r:GetText() or "") ~= "" then
                local get, set = ns.CustomAccess(BuffCfg, "anchors", key, Restyle)
                list[#list + 1] = { key = key, pick = "buffs." .. key, label = AURA_LABEL[key], region = r,
                    anchor = { get = get, set = set,
                        defaults = function() return ns.AuraTextDefaults and ns.AuraTextDefaults(BuffCfg(), key) end } }
                container = container or b
                break
            end
        end
    end
    return list, container
end })

-- ============================================================
-- MINIMAP
-- ============================================================
local PANEL_FIELD = { panelZone = "zone", panelClock = "clock", panelFriends = "friends",
    panelGuild = "guild", panelCoords = "coords" }
PD.Register("screen.minimap", { pieces = function(canvas, P)
    local ML, MM = ns.MinimapLook, ns.MinimapOptions
    local st = P and P.store
    if not (ML and MM and MM.DB and st and st.parts) then return nil end
    local function Refresh() if MM.Refresh then MM.Refresh() end end
    local owner = function() return MM.DB() end
    local list = {}
    local function Add(key, region, label, defaults)
        if not Visible(region) then return end
        local get, set = ns.CustomAccess(owner, "anchors", key, Refresh)
        list[#list + 1] = { key = key, pick = "minimap." .. key, label = label or key, region = region,
            anchor = { get = get, set = set, defaults = defaults } }
    end
    if ML.Overlay and ML.Overlay() then
        -- the map-only look: its pills
        for _, k in ipairs(ML.PIECES or {}) do
            Add(k, st[k], ML.PIECE_LABELS and ML.PIECE_LABELS[k],
                function() return ML.PillDefault(ML.PIECE_KEYS[k]) end)
        end
    else
        -- the panel look: its texts
        for _, k in ipairs(ML.PANEL_TEXTS or {}) do
            Add(k, st.parts[PANEL_FIELD[k]], ML.PANEL_LABELS and ML.PANEL_LABELS[k],
                function() return ML.PanelDefault(k) end)
        end
    end
    for _, k in ipairs(ML.ICONS or {}) do
        Add(k, st.icons and st.icons[k], ML.ICON_LABELS and ML.ICON_LABELS[k],
            function() return ML.IconDefault(k) end)
    end
    return list, st.map
end })

-- ============================================================
-- CHAT: the info bar's numbers reorder along the bar
-- (ZacUIDB.chat.barOrder: item ids; nil = the bar's own order)
-- ============================================================
PD.Register("screen.chat", { pieces = function(canvas, P)
    local C = ns.Chat
    local st = P and P.store
    if not (C and C.ITEMS and C.OrderedItems and st and st.items and PD.OrderPieces) then return nil end
    local items = {}
    for _, b in ipairs(C.OrderedItems(st.items)) do
        if Visible(b) and b._it then items[#items + 1] = { key = b._it.id, label = b._it.label or b._it.id, region = b } end
    end
    if #items < 2 then return nil end
    local function DB() return ZacUIDB.chat end
    local group = { key = "barOrder", items = items, axis = "x", pick = "chat.bar",
        defaults = function()
            local out = {}
            for _, it in ipairs(C.ITEMS) do out[#out + 1] = it.id end
            return out
        end,
        get = function() local d = DB() return d and d.barOrder end,
        set = function(list)
            local d = DB()
            if not d then return end
            d.barOrder = list
            if C.Refresh then C.Refresh() end
        end }
    return PD.OrderPieces(group), st.content
end })

-- the search finds them by the words for dragging
if PD.Keywords then PD.Keywords("tooltips", "buffs", "minimap", "chat") end
