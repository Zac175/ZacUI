-- BR_Menu - the Buff reminders row in ZacUI's settings menu.
-- Part of ZacUI; load order is set by the TOC (last).
--
-- The page itself (BR_Config) loads on demand with the settings window
-- (the Zacui_Options addon, 2026-11-13). Its row is put in the menu here,
-- when the part loads, as it always was: Edit Mode's "Open its settings"
-- and the minimap button's page list look the row up without the window.

local ns = _G.ZacUI
if not ns then return end

local BR = ns.BuffRem
if not (BR and BR.IconUI and BR.TrackerUI) then return end

-- the menu row: Combat > Buff reminders (after Blessings)
do
    local combat
    for _, item in ipairs(ns.ConfigMenu or {}) do
        if item.id == "combat" and item.children then combat = item end
    end
    if combat then
        local have = false
        for _, c in ipairs(combat.children) do if c.id == "buffrem" then have = true end end
        if not have then
            local at = #combat.children + 1
            for i, c in ipairs(combat.children) do if c.id == "blessings" then at = i + 1 end end
            table.insert(combat.children, at, { id = "buffrem", label = "Buff reminders", page = "BuffRem",
                addon = "Zacui_BuffReminders",
                keywords = "buff buffs reminder reminders missing battle shout bs party tracker raid group "
                    .. "arcane intellect brilliance fortitude prayer spirit shadow protection mark of the wild "
                    .. "gift motw gotw thorns trueshot soulstone reagent reagents candle powder thornroot "
                    .. "rebuff buffing click cast readycheck warrior mage priest druid hunter warlock" })
        end
    end
end
