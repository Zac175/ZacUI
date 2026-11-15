--------------------------------------------------------------------------------
-- The first time the map opens: which map. (The engine asked "Classic" or its own full map here;
-- ZacUI switched the question off on 2026-10-31 and put it back on 2026-11-14 - Zac: "also should
-- prompt on map first open why did you get rid of that" - as the choice that matters in ZacUI:)
--   The game's map      the world map as the game draws it; the seamless map is off
--   Seamless, classic   the seamless map, started closer to the game's: unexplored areas hidden,
--                       none of its own icons or zone levels, the favourites folded away
--   Seamless map        the seamless map with everything it ships with
-- Who is asked is Init.lua's (ns.MapAskDecide): a new install, and a save whose seamless map a game
-- look turned off; settings saved before this are never asked about, or changed. Closing the
-- window without choosing asks again at the first opening of the next login. /zuimap welcome asks
-- any time, map on or off. The window is ZacUI's own popup (UI.Popup: its look, its scale, and the
-- game look's dialog under a game look), not a frame of this engine's.
--------------------------------------------------------------------------------

local _, ns = ...
if ns.flavorOff then return end   -- (ZacUI: not on this game version, Core.lua: nothing here loads)
local mod = ns:GetModule("worldmap")
local L = ns.L

-- (presetAsked isn't in the defaults, where old saves would get it too: nil until the first login
-- with this version, then false on a new install, asked when the map opens, and true on one that
-- had settings)
local CLASSIC = { unexplored = "hide", icons = false, boats = false, zeppelins = false, flight = false, routes = false, zoneLevels = false,
	dungeonLevels = false, trayOpen = false }

local dialog
local askedThisLogin

local function AskReload(text)
	local z = _G.ZacUI
	if type(z) == "table" and z.AskReload then z.AskReload(text) else ns:Print(text) end
end

-- which: "game" | "classic" | "full"
local function Choose(which)
	local db = mod.db
	db.mapAsked, db.presetAsked = true, true
	local want = which ~= "game"
	if which == "classic" then
		for k, v in pairs(CLASSIC) do db[k] = v end
	end
	db.enabled = want
	local z = _G.ZacUI
	if dialog and z and z.UI and z.UI.CloseWindow then z.UI.CloseWindow(dialog) end
	local running = mod.enabled and true or false
	if want == running then
		-- (no change of map: the preset alone, where the map is drawn)
		if which == "classic" and running then
			mod:Refresh()
			if ns.NotifyOptions then ns.NotifyOptions() end
		end
		return
	end
	AskReload(want and L["The seamless map is on after a reload."] or L["The game's own map is back after a reload."])
end
mod.ChooseMap = Choose

local W, BTN_W = 500, 144
local function Build()
	local z = _G.ZacUI
	local UI = type(z) == "table" and z.UI
	if not (UI and UI.Popup and UI.PopupText and UI.OpenWindow) then return nil end
	local f = UI.Popup("ZacUIMapChoice", W, 240, L["Choose your map style"], { strata = "FULLSCREEN_DIALOG", level = 120, part = "maps" })
	f.message = UI.PopupText(f, "body", { justify = "LEFT", width = W - 2 * f.pad })
	f.message:SetPoint("TOPLEFT", f, "TOPLEFT", f.pad, -f.headerHeight)
	f.message:SetText(L["ZacUI has a seamless world map: every zone stitched into one, the wheel from the whole world down to street level."]
		.. "\n\n" .. L["The game's map"] .. ": " .. L["The world map as the game draws it."]
		.. "\n" .. L["Seamless, classic"] .. ": " .. L["The seamless map with unexplored areas hidden and no dungeon, flight master or zone level marks."]
		.. "\n" .. L["Seamless map"] .. ": " .. L["The whole map, with dungeon entrances, flight masters, zone levels and favourite buttons."]
		.. "\n\n" .. L["You can change this any time: /zui, Maps."])
	f:SetButtons({
		{ text = L["The game's map"], width = BTN_W, onClick = function() Choose("game") end },
		{ text = L["Seamless, classic"], width = BTN_W, onClick = function() Choose("classic") end },
		{ text = L["Seamless map"], width = BTN_W, onClick = function() Choose("full") end },
	})
	local ok, h = pcall(f.message.GetStringHeight, f.message)
	f:FitHeight(math.max(18, math.ceil((ok and type(h) == "number") and h or 0)))
	return f
end

function mod:ShowWelcome()
	if not dialog then dialog = Build() end
	if not dialog then return end
	-- the accent button is the map in use now
	local b = dialog.buttons
	if b and b[1] and b[1].SetKind then
		local on = mod.enabled and true or false
		b[1]:SetKind((not on) and "primary" or nil)
		b[2]:SetKind(nil)
		b[3]:SetKind(on and "primary" or nil)
	end
	_G.ZacUI.UI.OpenWindow(dialog)
end

if ns.flavorOff then return end   -- (ZacUI: off on this game version, Core.lua)
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_LOGIN")
	-- (the engine's own preset question is part of the one above: never asked by itself)
	if mod.db.presetAsked == nil then mod.db.presetAsked = true end
	-- asked at the map's first opening of this login while db.mapAsked is false (Init.lua decides
	-- that after this handler may have run, so it is read when the map opens); never in a fight
	local function Hook()
		WorldMapFrame:HookScript("OnShow", function()
			if mod.db.mapAsked ~= false or askedThisLogin then return end
			if InCombatLockdown and InCombatLockdown() then return end
			askedThisLogin = true
			mod:ShowWelcome()
		end)
	end
	-- (as the map itself waits, WorldMap.lua: the frame is there already, or comes with its addon)
	if WorldMapFrame then Hook()
	elseif EventUtil and EventUtil.ContinueOnAddOnLoaded then EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", Hook) end
end)
