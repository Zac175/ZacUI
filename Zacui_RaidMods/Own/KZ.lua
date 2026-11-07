-- KZ - ZacUI's own Karazhan boss module: what each piece does.
-- Part of ZacUI (Zacui_RaidMods). The facts are in Own\KZ_Data.lua; the
-- pieces are built from them by Own\TBC_Kit.lua (T.Build): a controller
-- and a bar for each timed ability, call-outs for the casts and debuffs
-- raiders react to, "on you" icons, raid-frame marks, phase calls from
-- the boss's health, Netherspite's portal / banish cycle and the berserk
-- bars. Karazhan needs nothing on top of the kit.
local ns = _G.ZacUI
local RM = ns and ns.RaidMods
local T = RM and RM.Own and RM.Own.TBC
if not (T and T.on and T.facts.KZ) then return end

T.Build("KZ")
