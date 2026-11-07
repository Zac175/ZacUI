-- ML - ZacUI's own Magtheridon's Lair boss module: what each piece does.
-- Part of ZacUI (Zacui_RaidMods). Facts in Own\ML_Data.lua, built by
-- Own\TBC_Kit.lua (T.Build): the two minutes until he is free, Blast Nova
-- (bar, heads-up and "click the cubes"), Quake, the channelers' heal,
-- the 30% cave-ins and the berserk bar.
local ns = _G.ZacUI
local RM = ns and ns.RaidMods
local T = RM and RM.Own and RM.Own.TBC
if not (T and T.on and T.facts.ML) then return end

T.Build("ML")
