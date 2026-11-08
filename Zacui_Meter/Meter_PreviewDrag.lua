-- Meter_PreviewDrag - the meter window's pieces for ZacUI's drag-to-
-- customise preview (UIF_PreviewDrag): the header icons reorder by
-- dragging them along the strip (look.toolbarOrder, a list of the icons'
-- keys; nil = the shipped order, Meter.TOOLBAR_ORDER).
-- Part of ZacUI; load order is set by the TOC (after Config_PagesMeter).

local ns = _G.ZacUI
if not ns then return end
local PD = ns.PreviewDrag
if not (PD and PD.Register and PD.OrderPieces) then return end

local LABEL = { winaction = "New / close window", reset = "Reset data", mode = "Mode", segment = "Fight",
    report = "Report", settings = "This window" }

PD.Register("meter.window", { pieces = function(canvas, P)
    local Meter = ns.Meter
    local win = P and P.store and P.store.win
    if not (Meter and Meter.Look and Meter.TOOLBAR_ORDER and win and win.toolbarButtons) then return nil end
    if not (win.toolbar and win.toolbar:IsVisible()) then return nil end
    local d = Meter.Look()
    -- In the header bar the two that stay (Meter.HEADER_REST) keep the
    -- right edge and the rest come with the mouse; the order holds within
    -- each, so each is a row of its own (both write the one list - a key
    -- not in the row keeps its place in it).
    local rest = (Meter.HeaderMode and Meter.HeaderMode(d) == "bar") and Meter.HEADER_REST or nil
    local rows = { toolbar = {}, toolbarRest = {} }
    for _, key in ipairs(ns.OrderedList(Meter.TOOLBAR_ORDER, d.toolbarOrder)) do
        local b = win.toolbarButtons[key]
        if b and b:IsVisible() then
            local row = (rest and rest[key]) and rows.toolbarRest or rows.toolbar
            row[#row + 1] = { key = key, label = LABEL[key] or key, region = b }
        end
    end
    local out
    for _, gkey in ipairs({ "toolbar", "toolbarRest" }) do
        if #rows[gkey] >= 2 then
            out = PD.OrderPieces({ key = gkey, items = rows[gkey], axis = "x", pick = "meter.headerIcons",
                defaults = Meter.TOOLBAR_ORDER,
                get = function() return Meter.Look().toolbarOrder end,
                set = function(list)
                    Meter.Look().toolbarOrder = list
                    if Meter.RestyleAll then Meter.RestyleAll() end
                end }, out)
        end
    end
    if not out then return nil end
    return out, win.toolbar
end })
if PD.Keywords then PD.Keywords("meter") end
