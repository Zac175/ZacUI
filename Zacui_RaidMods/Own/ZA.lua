-- ZA - ZacUI's own Zul'Aman boss module: what each piece does.
-- Part of ZacUI (Zacui_RaidMods). Facts in Own\ZA_Data.lua, built by
-- Own\TBC_Kit.lua (T.Build): Akil'zon's storms, Nalorakk's forms,
-- Jan'alai's bombs and hatchers, Halazzi's totems, the Hex Lord's
-- Spirit Bolts and Zul'jin's forms. Every piece wakes on its boss's
-- ENCOUNTER_START by name (see ZA_Data).
local ns = _G.ZacUI
local RM = ns and ns.RaidMods
local T = RM and RM.Own and RM.Own.TBC
if not (T and T.on and T.facts.ZA) then return end

T.Build("ZA")
