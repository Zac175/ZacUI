-- BT - ZacUI's own Black Temple boss module: what each piece does.
-- Part of ZacUI (Zacui_RaidMods). Facts in Own\BT_Data.lua, built by
-- Own\TBC_Kit.lua (T.Build): spines and shields, Supremus' phases,
-- Teron's Shadow of Death (bar, call-out, marks), Gurtogg's Fel Rage,
-- the Reliquary's interrupts, Shahraz's Fatal Attraction, the Council's
-- heals and blessings on their plates, and Illidan's phases and forms.
local ns = _G.ZacUI
local RM = ns and ns.RaidMods
local T = RM and RM.Own and RM.Own.TBC
if not (T and T.on and T.facts.BT) then return end

T.Build("BT")
