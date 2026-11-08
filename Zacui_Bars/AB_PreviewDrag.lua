-- AB_PreviewDrag - the action bars' pieces for ZacUI's drag-to-customise
-- preview (UIF_PreviewDrag): on the bar being edited, the key text, the
-- count and the macro name move through the bar's anchor spec
-- (bars[n].anchors.<hotkey|count|macro>, what the Text tab's position
-- pickers write), from the first sample button that shows each. Phase 4:
-- the bar's edges set its rows, the first button's corner the button size.
-- Part of ZacUI; load order is set by the TOC (after Config_PagesBars).

local ns = _G.ZacUI
if not ns then return end
local PD = ns.PreviewDrag
if not (PD and PD.Register) then return end

local function AB() return ns.Bars end
local ApplyNow = function()
    local A = AB()
    if A and A.active and A.ApplyAll then A.ApplyAll() end
end
local Apply = ns.Coalesce and ns.Coalesce(ApplyNow) or ApplyNow

local TEXTS = {
    { key = "hotkey", field = "zHotkey", label = "Key text" },
    { key = "count", field = "zCount", label = "Count" },
    { key = "macro", field = "zName", label = "Macro name" },
}

PD.Register("bars.bar", { pieces = function(canvas, P)
    local A = AB()
    if not (A and A.EditingId and A.KindOf and A.CfgFor and A.TextAnchorDefaults) then return nil end
    local id = A.EditingId()
    if A.KindOf(id) ~= "action" then return nil end
    local cfg = A.CfgFor(id)
    local g = P and P.store and P.store.current
    if not (type(cfg) == "table" and type(cfg.fonts) == "table" and g and g.buttons) then return nil end
    local list, container = {}, nil
    for _, t in ipairs(TEXTS) do
        for _, b in ipairs(g.buttons) do
            local r = b[t.field]
            if b:IsVisible() and r and r:IsVisible() and (r:GetText() or "") ~= "" then
                local get, set = ns.CustomAccess(cfg, "anchors", t.key, Apply)
                local el = cfg.fonts[t.key]
                list[#list + 1] = { key = t.key, pick = "ab." .. t.key, label = t.label, region = r,
                    anchor = { get = get, set = set, defaults = function() return A.TextAnchorDefaults(el, nil, t.key) end } }
                container = container or b
                break
            end
        end
    end
    -- (phase 4) the bar's grid by its edges: the right edge sets how many
    -- buttons go on a row (bars[n].rows from the count), the bottom edge
    -- the rows; the first button's corner the button size (buttonSize).
    -- A saved layout with its own buttons per line (bars[n].layout.perLine,
    -- the Position tab's layout picker) keeps that picker: no grid grips.
    local count = tonumber(cfg.buttons) or 12
    local size = tonumber(cfg.buttonSize) or A.BUTTON or 36
    local pad = tonumber(cfg.padding) or 2
    local lay = type(cfg.layout) == "table" and cfg.layout or nil
    local shown = {}
    for _, b in ipairs(g.buttons) do if b:IsVisible() then shown[#shown + 1] = b end end
    if #shown > 0 and not (lay and tonumber(lay.perLine)) then
        local function Rows(n) return math.max(1, math.min(12, math.min(count, n))) end
        local step = size + pad
        -- the rows a width / height gives, and the size the grid then takes
        -- (whole columns and rows: the outline shows where the edge lands)
        local function RowsForW(w)
            local per = math.max(1, math.min(count, math.floor((w + pad) / step + 0.5)))
            return Rows(math.ceil(count / per))
        end
        local function RowsForH(h) return Rows(math.floor((h + pad) / step + 0.5)) end
        local function Extent(rows)
            local per = math.ceil(count / rows)
            return per * step - pad, rows * step - pad
        end
        list[#list + 1] = { key = "grid", label = "The bar", region = shown, noMove = true, pick = "ab.button",
            size = { min = 1, max = 4000, minH = 1, maxH = 4000,
                -- (no setting is the width itself: the drag works out the
                -- rows from the width or height it is dragged to)
                get = function() return nil, nil end,
                snapshot = function() return { rows = cfg.rows } end,
                restore = function(v) cfg.rows = v and v.rows Apply() end,
                fit = function(w, h)
                    if w then return Extent(RowsForW(w)) end
                    if h then return Extent(RowsForH(h)) end
                    return nil, nil
                end,
                set = function(w, h)
                    if w then
                        cfg.rows = RowsForW(w)
                    elseif h then
                        cfg.rows = RowsForH(h)
                    end
                    Apply()
                end } }
    end
    if shown[1] then
        local def = A.BUTTON or 36
        list[#list + 1] = { key = "button", label = "Button size", region = shown[1], noMove = true, pick = "ab.button",
            size = { square = true, min = 16, max = 64,
                get = function() local v = cfg.buttonSize or def return v, v end,
                set = function(w) if w then cfg.buttonSize = w Apply() end end,
                snapshot = function() return { v = cfg.buttonSize } end,
                restore = function(v) cfg.buttonSize = v and v.v Apply() end } }
    end
    return list, container
end })
if PD.Keywords then PD.Keywords("bars") end
