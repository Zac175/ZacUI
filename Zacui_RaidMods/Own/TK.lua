-- TK - ZacUI's own Tempest Keep (The Eye) boss module: what each piece does.
-- Part of ZacUI (Zacui_RaidMods). Facts in Own\TK_Data.lua, built by
-- Own\TBC_Kit.lua (T.Build): Al'ar's Melt Armor and Dive Bomb timers,
-- Void Reaver's calls, Solarian's splits and Wrath, and Kael'thas' long
-- fight - the weapons and revived advisors after the fourth advisor
-- falls, his shield, mind controls and Gravity Lapse.
local ns = _G.ZacUI
local RM = ns and ns.RaidMods
local T = RM and RM.Own and RM.Own.TBC
if not (T and T.on and T.facts.TK) then return end

T.Build("TK")
