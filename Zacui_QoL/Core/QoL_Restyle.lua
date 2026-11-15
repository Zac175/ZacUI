-- QoL_Restyle - what is on screen follows every settings change.
-- Part of ZacUI; load order is set by the TOC (last).
--
-- The GCD tracker, the pull and break timers and the Snowball button are
-- restyled, once per frame, whenever a setting changes. This listener sat
-- in the settings page's file (Config_PagesQoL), which loads on demand
-- with ZacUI's settings window now (the Zacui_Options addon, 2026-11-13);
-- it listens from login here, as it always did.

local ns = _G.ZacUI
if not ns then return end
if not ns.QoL then return end

-- what is on screen follows every change, once per frame
local Restyle = ns.Coalesce and ns.Coalesce(function()
    local QoL = ns.QoL
    if not QoL then return end
    if QoL.GCDTracker and QoL.GCDTracker.Restyle then QoL.GCDTracker.Restyle() end
    if QoL.RaidTimers and QoL.RaidTimers.Restyle then QoL.RaidTimers.Restyle() end
    if QoL.Snowball and QoL.Snowball.Restyle then QoL.Snowball.Restyle() end
end)
if Restyle and ns.OnSettingsChanged then ns.OnSettingsChanged(function() Restyle() end) end
