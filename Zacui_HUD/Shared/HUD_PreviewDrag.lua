-- HUD_PreviewDrag - the HUDs' pieces for ZacUI's drag-to-customise preview
-- (UIF_PreviewDrag), on every HUD page: the class HUDs (Class HUD v2), the
-- Warrior HUD, the Priest HUD and the Paladin HUD.
--   MOVE: every piece of a HUD sample stands where the HUD sits on screen,
--   so a drag writes its mover's position of record (ZacUIDB.movers[key] -
--   what Edit Mode and the Movers page write - in UIParent units) and the
--   live holder follows through the mover registry. A piece never dragged
--   starts from its store's default; undo leaves no mover behind.
--   REORDER: the icons of a row reorder by dragging them along it.
--     class HUDs   cfg.v2.order.<main|utility|buffs|debuffs|reminders>
--                  (HUD_V2_Rows lays the row out in it), and the tracked
--                  buff bars' stack cfg.v2.buffBars.order
--     Warrior HUD  <warrior store>.order.<main|buffs>
--     Priest HUD   <priest store>.order.<main|debuffs|reminders>
--   (all nil = today's order; for the Warrior and Priest HUDs the rows'
--   shared layouts are wrapped here and order only a registered row with
--   a saved order - anything else goes through untouched, not copied).
--   Alt-drag on an icon moves its whole row.
-- Part of ZacUI; load order is set by the TOC (after every HUD file).

local ns = _G.ZacUI
if not ns then return end
local PD = ns.PreviewDrag
local HUD = ns.HUD
if not (PD and PD.RegisterMatch and PD.OrderPieces and HUD) then return end

local function IconKey(icon) return icon and icon.def and icon.def.key end
local function Keys(list)
    local out = {}
    for _, e in ipairs(list or {}) do if e.key ~= nil then out[#out + 1] = e.key end end
    return out
end
local function KeysOfIcons(list)
    local out = {}
    for _, icon in ipairs(list or {}) do local k = IconKey(icon) if k ~= nil then out[#out + 1] = k end end
    return out
end

-- ============================================================
-- A MOVER AS A MOVE PIECE
-- ============================================================
-- mk: the mover key; store: its default { x, y }; a: the sample anchor
-- (its parent's scale is the units'); region: what the handle covers
local function MoverPiece(key, label, mk, store, a, region)
    local function Pos() return HUD.MoverPos(mk) end
    -- (a drag shifts the sample anchor itself: what hangs off it - icons
    -- chained to each other too - comes along exactly once)
    return { key = key, label = label, region = region, carry = a,
        move = {
            get = function()
                local pos = Pos()
                if pos then return pos.x or 0, pos.y or 0 end
                return (store and store.x) or 0, (store and store.y) or 0
            end,
            set = function(x, y)
                local pos = Pos()
                ZacUIDB.movers = ZacUIDB.movers or {}
                ZacUIDB.movers[mk] = { point = (pos and pos.point) or "CENTER", x = x, y = y }
                if ns.ApplyMover then ns.ApplyMover(mk) end
            end,
            reset = function() if ns.ResetMover then ns.ResetMover(mk, true) end end,
            snapshot = function()
                local pos = Pos()
                return { had = ZacUIDB.movers ~= nil, pos = pos and { point = pos.point, x = pos.x, y = pos.y } }
            end,
            restore = function(v)
                if v and v.pos then
                    ZacUIDB.movers = ZacUIDB.movers or {}
                    ZacUIDB.movers[mk] = { point = v.pos.point, x = v.pos.x, y = v.pos.y }
                    if ns.ApplyMover then ns.ApplyMover(mk) end
                elseif ns.ResetMover then
                    ns.ResetMover(mk, true)
                end
                -- (a movers table this made goes again)
                if v and not v.had and ZacUIDB.movers and next(ZacUIDB.movers) == nil then ZacUIDB.movers = nil end
            end,
            -- (mover offsets: the sample stage's units, UIParent's at real size)
            eff = function() local par = a:GetParent() return par and par:GetEffectiveScale() or 1 end,
        } }
end

-- what a handle covers for a sample anchor: what it draws, else itself
local function Cover(a)
    local kids = {}
    for _, k in ipairs({ a:GetChildren() }) do if k:IsVisible() then kids[#kids + 1] = k end end
    return (#kids > 0) and kids or a
end

-- The pieces a HUD sample placed with HUD.RealSample (the class HUDs, the
-- Priest and Paladin HUDs): noted on the canvas as they are placed.
local realSample = HUD.RealSample
HUD.RealSample = function(canvas, pieces)
    if canvas then canvas._zRealPieces = pieces end
    return realSample(canvas, pieces)
end
local function RealPieces(canvas, out)
    local MOVERS = ns.MOVERS or {}
    for _, p in ipairs((canvas and canvas._zRealPieces) or {}) do
        local a = p.a
        if a and p.on and p.mover and a:IsVisible() then
            local m = MOVERS[p.mover]
            out[#out + 1] = MoverPiece("mover:" .. p.mover, (m and m.label) or p.mover, p.mover, p.store, a, Cover(a))
        end
    end
end

-- ============================================================
-- ROW ORDER FOR THE WARRIOR AND PRIEST HUDS
-- ============================================================
-- A row is registered by its memo (Priest: HUD.LayoutGrid / LayoutRow's
-- memo) or its anchor (Warrior: W.LayoutMainRow / LayoutHRow's anchor),
-- with a function giving its saved order. The ordered list is kept until
-- the row's icons or the saved order change: the HUD's refresh makes no
-- garbage. An unregistered row, or one with nothing saved, is handed on
-- as it came.
local rowOrder = setmetatable({}, { __mode = "k" })   -- memo / anchor -> fn() -> saved list
local rowCache = setmetatable({}, { __mode = "k" })
local function Ordered(owner, list)
    local get = owner and rowOrder[owner]
    if not get or type(list) ~= "table" then return list end
    local saved = get()
    if type(saved) ~= "table" or #saved == 0 or not ns.OrderedList then
        rowCache[owner] = nil
        return list
    end
    local c = rowCache[owner]
    if c and c.saved == saved and c.n == #list then
        local same = true
        for i = 1, #list do if c.src[i] ~= list[i] then same = false break end end
        if same then return c.out end
    end
    c = c or { src = {} }
    rowCache[owner] = c
    c.saved, c.n = saved, #list
    for i = 1, #list do c.src[i] = list[i] end
    for i = #list + 1, #c.src do c.src[i] = nil end
    c.out = ns.OrderedList(list, saved, IconKey)
    return c.out
end
PD.HudOrdered = Ordered

local layoutGrid, layoutRow = HUD.LayoutGrid, HUD.LayoutRow
HUD.LayoutGrid = function(memo, list, ...) return layoutGrid(memo, Ordered(memo, list), ...) end
HUD.LayoutRow = function(memo, list, ...) return layoutRow(memo, Ordered(memo, list), ...) end
local WHW = ns.WarriorHUD and ns.WarriorHUD.Widgets
if WHW and WHW.LayoutMainRow and WHW.LayoutHRow then
    local mainRow, hRow = WHW.LayoutMainRow, WHW.LayoutHRow
    WHW.LayoutMainRow = function(anchor, frames, ...) return mainRow(anchor, Ordered(anchor, frames), ...) end
    WHW.LayoutHRow = function(anchor, frames, ...) return hRow(anchor, Ordered(anchor, frames), ...) end
end

-- the saved order of a store's row, and its setter (nil = today's)
local function StoreOrder(storeFn, row)
    local get = function()
        local cfg = storeFn()
        local o = type(cfg) == "table" and cfg.order
        return type(o) == "table" and o[row] or nil
    end
    local set = function(list)
        local cfg = storeFn()
        if type(cfg) ~= "table" then return end
        if list then
            cfg.order = cfg.order or {}
            cfg.order[row] = list
        elseif type(cfg.order) == "table" then
            cfg.order[row] = nil
            if next(cfg.order) == nil then cfg.order = nil end
        end
    end
    return get, set
end

-- the live HUDs' rows (the Warrior HUD's anchors are named and exist for
-- warriors only; the Priest HUD's live view is PR.LIVE)
local WH, PR = ns.WarriorHUD, ns.PriestHUD
local function WStore() return WH and WH.Store and WH.Store() end
local function PStore() return PR and PR.Store and PR.Store() end
if WH then
    local mainA, auraA = _G.ZacUIHUD_Warrior_Main, _G.ZacUIHUD_Warrior_AuraRow
    if mainA then rowOrder[mainA] = (StoreOrder(WStore, "main")) end
    if auraA then rowOrder[auraA] = (StoreOrder(WStore, "buffs")) end
end
if PR and PR.LIVE and PR.LIVE.memo then
    rowOrder[PR.LIVE.memo.main] = (StoreOrder(PStore, "main"))
    rowOrder[PR.LIVE.memo.debuff] = (StoreOrder(PStore, "debuffs"))
    rowOrder[PR.LIVE.memo.remind] = (StoreOrder(PStore, "reminders"))
end

-- a reorder group for a row shown as `list` (today's order) on a sample
local function RowGroup(key, label, owner, list, storeFn, axis, refresh, out)
    rowOrder[owner] = (StoreOrder(storeFn, key))
    local shown = Ordered(owner, list)
    local items = {}
    for _, icon in ipairs(shown or {}) do
        local k = IconKey(icon)
        if k ~= nil and icon:IsVisible() then
            items[#items + 1] = { key = k, label = icon.def.label or icon.def.name or tostring(k), region = icon }
        end
    end
    if #items < 2 then return nil end
    local get, set = StoreOrder(storeFn, key)
    local defaults = KeysOfIcons(list)
    local g = { key = key, label = label, items = items, axis = axis, defaults = defaults, get = get,
        set = function(v) set(v) if refresh then refresh() end end }
    PD.OrderPieces(g, out)
    return g
end

-- ============================================================
-- THE PIECES, PAGE BY PAGE
-- ============================================================
-- the class HUDs (Class HUD v2 engine samples)
local ROWS = {
    { row = "main", memo = "main", list = "grid" },
    { row = "utility", memo = "utility", list = "utility" },
    { row = "buffs", memo = "aura", list = "buffRow" },
    { row = "debuffs", memo = "debuff", list = "debuffRow" },
    { row = "reminders", memo = "remind", list = "reminders" },
}
local ROW_MOVER = { main = "Main", utility = "Utility", buffs = "AuraRow", debuffs = "DebuffRow",
    reminders = "Reminders", buffBars = "BuffBars" }

local function ClassPieces(canvas, s, pieces)
    local cfg = s:Store()
    if type(cfg) ~= "table" then return end
    local V2 = HUD.V2
    local function Refresh()
        for _, eng in ipairs(HUD.ClassInstances or {}) do
            if eng.def == s.def and eng.Refresh then pcall(eng.Refresh, eng) end
        end
    end
    local groups = {}
    for _, r in ipairs(ROWS) do
        local memo = s.memo[r.memo]
        local items = {}
        for i = 1, (memo and memo.n or 0) do
            local icon = memo[i]
            local key = IconKey(icon)
            if key ~= nil and icon:IsVisible() then
                items[#items + 1] = { key = key, label = icon.def.label or icon.def.name or tostring(key), region = icon }
            end
        end
        if #items >= 2 then
            local row, list = r.row, r.list
            groups[#groups + 1] = { key = row, items = items, axis = (row == "main") and "grid" or "x",
                defaults = function() return Keys(s.def[list]) end,
                get = function()
                    local v = cfg.v2
                    return v and type(v.order) == "table" and v.order[row] or nil
                end,
                set = function(order)
                    if order then
                        cfg.v2 = cfg.v2 or {}
                        cfg.v2.order = cfg.v2.order or {}
                        cfg.v2.order[row] = order
                    elseif cfg.v2 and cfg.v2.order then
                        cfg.v2.order[row] = nil
                        if V2 and V2.Tidy then V2.Tidy(cfg)
                        elseif next(cfg.v2.order) == nil then cfg.v2.order = nil end
                    end
                    Refresh()
                end }
        end
    end
    -- the tracked buff bars: a stack (buffBars.order: their keys)
    local b = cfg.v2 and cfg.v2.buffBars
    if type(b) == "table" and s.v2barActive and s.V2BarsOrdered then
        local items = {}
        for _, f in ipairs(s:V2BarsOrdered(b, s.v2barActive)) do
            if f._v2gk ~= nil and f:IsVisible() then
                items[#items + 1] = { key = f._v2gk, label = (f.nameFS and f.nameFS:GetText()) or tostring(f._v2gk), region = f }
            end
        end
        if #items >= 2 then
            groups[#groups + 1] = { key = "buffBars", items = items, axis = (b.grow == "UP") and "-y" or "y",
                defaults = function()
                    local out = {}
                    for _, k in ipairs(s:V2BarList(cfg)) do out[#out + 1] = k end
                    return out
                end,
                get = function() local bb = cfg.v2 and cfg.v2.buffBars return bb and bb.order end,
                set = function(order)
                    local bb = cfg.v2 and cfg.v2.buffBars
                    if not bb then return end
                    bb.order = order
                    Refresh()
                end }
        end
    end
    for _, g in ipairs(groups) do PD.OrderPieces(g, pieces) end
    -- every piece at its mover's spot
    local byMover = {}
    if s.Elements and s.anchors then
        for _, e in ipairs(s:Elements()) do
            local a = s.anchors[e.key]
            if a and a:IsVisible() and e.mover then
                local pc = MoverPiece("mover:" .. e.mover, e.label or e.key, e.mover, e.cfg and e.cfg(cfg), a, Cover(a))
                pieces[#pieces + 1] = pc
                byMover[e.key] = pc
            end
        end
    end
    for _, g in ipairs(groups) do g.rowPiece = byMover[ROW_MOVER[g.key]] end
end

-- the Warrior HUD's sample: six anchors at their movers' spots
local W_MOVER = { Main = "whMainRow", AuraRow = "whAuraRow", Stance = "whStance",
    Execute = "whExecute", RageBar = "whRageBar", Swing = "whSwing" }
local W_LABEL = { Main = "Cooldown grid", AuraRow = "Active buffs", Stance = "Stance icon",
    Execute = "Execute helper", RageBar = "Rage bar", Swing = "Swing timers" }
local function WStoreOf(cfg, key)
    local r = cfg.resources or {}
    if key == "Main" then return cfg.mainRow
    elseif key == "AuraRow" then return cfg.auraRow
    elseif key == "Stance" then return r.stance
    elseif key == "Execute" then return r.execute
    elseif key == "RageBar" then return r.rage end
    return r.swing
end
local function WarriorPieces(canvas, st, pieces)
    local cfg = WStore()
    if type(cfg) ~= "table" then return end
    -- (the live HUD lays its rows out again; methods of its display)
    local function Refresh()
        local D = WH.Display
        if D and D.InvalidateLayout then pcall(D.InvalidateLayout, D) end
        if D and D.Refresh then pcall(D.Refresh, D) end
    end
    local gMain = RowGroup("main", "Cooldown grid", st.anchors.Main, st.gridList, WStore, "grid", Refresh, pieces)
    local gAura = RowGroup("buffs", "Active buffs", st.anchors.AuraRow, st.auraList, WStore, "x", Refresh, pieces)
    local byKey = {}
    for _, key in ipairs({ "Main", "AuraRow", "Stance", "Execute", "RageBar", "Swing" }) do
        local a = st.anchors[key]
        if a and a:IsVisible() then
            local pc = MoverPiece("mover:" .. W_MOVER[key], W_LABEL[key], W_MOVER[key], WStoreOf(cfg, key), a, Cover(a))
            pieces[#pieces + 1] = pc
            byKey[key] = pc
        end
    end
    if gMain then gMain.rowPiece = byKey.Main end
    if gAura then gAura.rowPiece = byKey.AuraRow end
end

-- the Priest HUD's sample view: its rows by their memos, its pieces by
-- what it placed with HUD.RealSample
local P_ROWS = { { "main", "main", "Cooldown grid", "grid", "prMainRow" },
    { "debuffs", "debuff", "Target debuffs", "x", "prDebuffs" },
    { "reminders", "remind", "Reminders", "x", "prReminders" } }
local function PriestPieces(canvas, V, pieces)
    local function Refresh() if PR.Display and PR.Display.Refresh then pcall(PR.Display.Refresh, PR.Display) end end
    local groups = {}
    for _, r in ipairs(P_ROWS) do
        local memo = V.memo and V.memo[r[2]]
        if memo then
            -- (the memo holds the row as laid out: its own order is the
            -- list's before ordering, so the defaults come from the view)
            local list = {}
            for i = 1, (memo.n or 0) do list[i] = memo[i] end
            local src = (r[1] == "main" and V.mainActive) or (r[1] == "debuffs" and V.debuffActive) or list
            local g = RowGroup(r[1], r[3], memo, src, PStore, r[4], Refresh, pieces)
            if g then groups[r[5]] = g end
        end
    end
    local before = #pieces
    RealPieces(canvas, pieces)
    for i = before + 1, #pieces do
        local mk = pieces[i].key:match("^mover:(.+)$")
        if mk and groups[mk] then groups[mk].rowPiece = pieces[i] end
    end
end

PD.RegisterMatch("^hud%.", { pieces = function(canvas, P)
    local st = P and P.store
    if not st then return nil end
    local pieces = {}
    local s = st.sample
    if s and s.memo and s.def and s.Store and s.Refresh then
        ClassPieces(canvas, s, pieces)
    elseif P.key == "hud.warrior" and st.anchors and WH then
        WarriorPieces(canvas, st, pieces)
    elseif P.key == "hud.priest" and st.view and PR then
        PriestPieces(canvas, st.view, pieces)
    else
        -- any other HUD sample placed with HUD.RealSample (the Paladin HUD)
        RealPieces(canvas, pieces)
    end
    return pieces, nil
end })

-- (the search: every HUD page)
if PD.Keywords then
    for _, id in ipairs({ "warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid" }) do
        PD.Keywords(id)
    end
end
