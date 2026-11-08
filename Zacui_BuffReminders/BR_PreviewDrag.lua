-- BR_PreviewDrag - the buff reminders' pieces for ZacUI's drag-to-customise
-- preview (UIF_PreviewDrag): the reminder icon's count, missing names and
-- art, the tracker's title, title icon and the first row's name, status
-- and icon, each through the anchor spec its Text / Position picker writes
-- (icon.anchors.<count|names|icon>, tracker.anchors.<title|titleIcon|
-- rowName|rowStatus|rowIcon>). The samples are found by the element tags
-- they already carry for click-to-pick. The icons themselves reorder
-- along their row (icon.order, phase 3).
-- Part of ZacUI; load order is set by the TOC (after BR_Config).

local ns = _G.ZacUI
if not ns then return end
local BR = ns.BuffRem
local PD = ns.PreviewDrag
if not (BR and PD and PD.Register) then return end

local function IC() return BR.Icon() end
local function TC() return BR.Tracker() end

-- element tag -> owner, saved key, label, defaults (from the page's own pickers)
local PIECES = {
    { tag = "buffrem.count", owner = IC, key = "count", label = "Count", def = function() return BR.IconUI.AnchorDefaults("count") end },
    { tag = "buffrem.names", owner = IC, key = "names", label = "Missing names", def = function() return BR.IconUI.AnchorDefaults("names") end },
    { tag = "buffrem.icon", owner = IC, key = "icon", label = "Icon art", def = function() return BR.IconUI.AnchorDefaults("icon") end },
    { tag = "buffrem.title", owner = TC, key = "title", label = "Tracker title", def = function() return BR.TrackerUI.AnchorDefaults("title") end },
    { tag = "buffrem.titleIcon", owner = TC, key = "titleIcon", label = "Tracker title icon", def = function() return BR.TrackerUI.AnchorDefaults("titleIcon") end },
    { tag = "buffrem.rowName", owner = TC, key = "rowName", label = "Row name", def = function() return BR.TrackerUI.AnchorDefaults("rowName") end },
    { tag = "buffrem.rowStatus", owner = TC, key = "rowStatus", label = "Row status and time", def = function() return BR.TrackerUI.AnchorDefaults("rowStatus") end },
    { tag = "buffrem.rowIcon", owner = TC, key = "rowIcon", label = "Row icon", def = function() return BR.TrackerUI.AnchorDefaults("rowIcon") end },
}

PD.Register("buffrem.frames", { pieces = function(canvas, P)
    if not (BR.IconUI and BR.TrackerUI) then return nil end
    local list, container = {}, nil
    for _, p in ipairs(PIECES) do
        local r = PD.FindTagged(canvas, p.tag)
        if r then
            local get, set = ns.CustomAccess(p.owner, "anchors", p.key)
            list[#list + 1] = { key = p.key, pick = p.tag, label = p.label, region = r,
                anchor = { get = get, set = set, defaults = p.def } }
            if p.key == "icon" then container = r:GetParent() end
        end
    end
    -- the reminder icons themselves reorder along their row (icon.order:
    -- buff keys; nil = the list's own order)
    local st = P and P.store
    if st and st.icons and PD.OrderPieces and BR.IconUI.Ordered then
        local shown = {}
        for _, def in ipairs(BR.Data and BR.Data.BUFFS or {}) do
            local f = st.icons[def.key]
            if f and f:IsVisible() then shown[#shown + 1] = f end
        end
        local items = {}
        for _, f in ipairs(BR.IconUI.Ordered(shown)) do
            items[#items + 1] = { key = f.def.key, label = f.def.label or f.def.key, region = f }
        end
        if #items >= 2 then
            -- (the icon art fills its icon: with the icons draggable as a
            -- row, the art keeps its picker on the Position tab)
            for i = #list, 1, -1 do if list[i].key == "icon" then table.remove(list, i) end end
            PD.OrderPieces({ key = "icons", items = items, axis = "x", pick = "buffrem.icon",
                defaults = function()
                    local out = {}
                    for _, def in ipairs(BR.Data.BUFFS or {}) do out[#out + 1] = def.key end
                    return out
                end,
                get = function() return IC().order end,
                set = function(order)
                    IC().order = order
                    if BR.IconUI.Restyle then BR.IconUI.Restyle() end
                end }, list)
        end
    end
    return list, container
end })
if PD.Keywords then PD.Keywords("buffrem") end
