-- Win_Menu - this part's rows in ZacUI's settings menu.
-- Part of ZacUI; load order is set by the TOC (last).
--
-- The pages themselves (Game windows, Flight times, Talents & spellbook)
-- load on demand with the settings window (the Zacui_Options addon,
-- 2026-11-13). Their rows are put in the menu here, when the part loads,
-- as they always were: Edit Mode's "Open its settings" and the minimap
-- button's page list look a row up without the window. Each row under
-- the same conditions as its page.

local ns = _G.ZacUI
if not ns then return end
if not (ns.RegisterPage and ns.UI) then return end

-- the "Bags & maps" group, with the other windows you open
local function Windows()
    for _, group in ipairs(ns.ConfigMenu or {}) do
        if group.id == "windows" and group.children then return group end
    end
end
-- after: the id of the row this one sits under (the end when it is not there)
local function Row(row, after)
    local group = Windows()
    if not group then return end
    local at
    for i, child in ipairs(group.children) do
        if child.id == row.id then return end
        if after and child.id == after then at = i end
    end
    table.insert(group.children, (at or #group.children) + 1, row)
end

-- Game windows
if ns.Kit then
    Row({
        id = "gamewindows", label = "Game windows", page = "GameWindows", addon = "Zacui_Windows",
        keywords = "windows window character sheet paperdoll spellbook spell book talents "
            .. "professions tradeskill crafting enchanting trainer merchant vendor mail mailbox "
            .. "social friends who guild ignore raid quest log gossip loot trade taxi flight "
            .. "macros inspect pvp battlemaster scoreboard group finder lfg pet "
            .. "scale size bigger smaller background colour color opacity transparent border "
            .. "title font animation open opening fade slide pop preview position anchor icon",
    })
end

-- Flight times, under Game windows
if ns.FlightTimes then
    Row({
        id = "flighttimes", label = "Flight times", page = "FlightTimes", addon = "Zacui_Windows",
        keywords = "flight flights flight time flight times flight path flight master taxi "
            .. "gryphon wind rider bat hippogryph countdown timer landing how long travel route",
    }, "gamewindows")
end

-- Talents & spellbook (Forever only), under Game windows
if _G.ZACUI_IS_FOREVER and not (ns.FeatureOn and not ns.FeatureOn("classic_book")) and ns.ClassicTalents then
    Row({
        id = "classicbook", label = "Talents & spellbook", page = "ClassicBook", addon = "Zacui_Windows",
        keywords = "talents talent tree trees classic vanilla spellbook spell book ranks rank "
            .. "all ranks learn points arms fury protection spec",
    }, "gamewindows")
end
