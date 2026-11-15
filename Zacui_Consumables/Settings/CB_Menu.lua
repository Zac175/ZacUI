-- CB_Menu - the Consumable bars row in ZacUI's settings menu.
-- Part of ZacUI; load order is set by the TOC (last).
--
-- The page itself (CB_Config) loads on demand with the settings window
-- (the Zacui_Options addon, 2026-11-13). Its row is put in the menu here,
-- when the part loads, as it always was: Edit Mode's "Open its settings"
-- and the minimap button's page list look the row up without the window.

local ns = _G.ZacUI
if not ns then return end
local D, CB = ns.ConsData, ns.ConsBars
if not (D and CB and CB.Button and CB.Live) then return end

local PAGE = "consbars"

-- the menu row (with the other things that draw in a fight)
do
    local menu = ns.ConfigMenu
    local group
    for _, item in ipairs(menu or {}) do if item.id == "combat" and item.children then group = item end end
    if group then
        local have = false
        for _, c in ipairs(group.children) do if c.id == PAGE then have = true end end
        if not have then
            group.children[#group.children + 1] = { id = PAGE, label = "Consumable bars", page = "ConsBars",
                addon = "Zacui_Consumables", keywords = "consumables consumable bar bars potion potions flask flasks "
                    .. "elixir elixirs juju jujus food buff buffs weapon stone stones sharpening oil oils poison "
                    .. "poisons readycheck helper" }
        end
    end
end
