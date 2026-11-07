-- SSC - ZacUI's own Serpentshrine Cavern boss module: what each piece does.
-- Part of ZacUI (Zacui_RaidMods). Facts in Own\SSC_Data.lua, built by
-- Own\TBC_Kit.lua (T.Build): Hydross' marks every 15 seconds and his form
-- changes, the Lurker's dives and Spout, Leotheras' whirlwinds, demons
-- and split, Karathress' council, Morogrim's graves and murlocs, and
-- Vashj's static charges, adds and mind controls.
local ns = _G.ZacUI
local RM = ns and ns.RaidMods
local T = RM and RM.Own and RM.Own.TBC
if not (T and T.on and T.facts.SSC) then return end

T.Build("SSC")
