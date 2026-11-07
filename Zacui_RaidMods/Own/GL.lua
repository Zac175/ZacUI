-- GL - ZacUI's own Gruul's Lair boss module: what each piece does.
-- Part of ZacUI (Zacui_RaidMods). Facts in Own\GL_Data.lua, built by
-- Own\TBC_Kit.lua (T.Build): Maulgar's council call-outs, Krosh's Spell
-- Shield on his plate, the polymorphs on raid frames, Gruul's Growth
-- every 30 seconds and the Ground Slam / Shatter calls.
local ns = _G.ZacUI
local RM = ns and ns.RaidMods
local T = RM and RM.Own and RM.Own.TBC
if not (T and T.on and T.facts.GL) then return end

T.Build("GL")
