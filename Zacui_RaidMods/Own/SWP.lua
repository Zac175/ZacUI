-- SWP - ZacUI's own Sunwell Plateau boss module: what each piece does.
-- Part of ZacUI (Zacui_RaidMods). Facts in Own\SWP_Data.lua, built by
-- Own\TBC_Kit.lua (T.Build): Kalecgos' portals and curse, Brutallus'
-- Burn and berserk, Felmyst's Encapsulate and Gas Nova, the Twins'
-- Conflagration, M'uru's humanoid waves and Entropius, and Kil'jaeden's
-- phases and Darkness. The last TBC raid file: it also hands the
-- settings page's preview strip its TBC samples.
local ns = _G.ZacUI
local RM = ns and ns.RaidMods
local T = RM and RM.Own and RM.Own.TBC
if not (T and T.on and T.facts.SWP) then return end

T.Build("SWP")
T.Samples()
