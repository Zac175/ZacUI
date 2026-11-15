--------------------------------------------------------------------------------
-- Init: loaded last. Settings at ADDON_LOADED; the map, options and slash
-- commands at PLAYER_LOGIN.
--
--   /openmap (/omap)        options
--   /openmap status         what the map is doing
--   /openmap notes          map notes (paint areas, say what's there, export them)
--   /openmap debug          the debug overlay (frame rate, frame times, what OpenMap costs)
--   /openmap bench [zoom]   times the map at several zooms, each part off in turn (Bench.lua)
--   /openmap pins           the map pins (Pins.lua)
--   /openmap news           what's new in this version (News.lua)
--   /openmap draw           the quill: draw on the map (Sketch.lua)
--   /openmap dungeons       which map each dungeon entrance opens (Dungeons.lua)
--   /openmap entrance <name>  where you stand, as a dungeon entrance for tools/map-data (Dungeons.lua)
--------------------------------------------------------------------------------

local ADDON, ns = ...
if ns.flavorOff then return end   -- (ZacUI: not on this game version, Core.lua: nothing here loads)
if ns.loadMs.start then ns.loadMs.files = debugprofilestop() - ns.loadMs.start end

local function Options()
	local mod = ns:GetModule("worldmap")
	local args = mod.Options and mod:Options() or {}
	args.enabled = { type = "toggle", name = ns.L["Enable ZacUI Map"], order = 0, width = "full",
		desc = ns.L["Turning ZacUI Map off takes a reload."],
		get = function() return mod.db.enabled end,
		set = function(_, v) mod.db.enabled = v; ns:Print(ns.L["Takes effect after a /reload."]) end }
	args.padWaits = { type = "description", order = 0.5, fontSize = "medium",
		name = function() return "|cffff8040" .. mod.PadOffText() .. "|r" end,
		hidden = function() return not mod.padWaits end }
	return { type = "group", name = "|cff" .. ns.ACCENT .. "ZacUI Map|r " .. ns.version, args = args }
end

-- OpenMap's settings are the map's own menu (Panel.lua); with the map off (no menu), the options window,
-- which can turn it back on
-- (ZacUI, 2026-11-14, Zac: "why is the seemless map settings not built into the main ui?") They are
-- - ZacUI's settings window, Maps page, World map tab - but with the map off this still opened the
-- engine's separate options window. Now every way in (the slash command, the minimap and
-- compartment buttons, the game's AddOns settings page, the Maps page's own button) opens that tab,
-- map on or off; the separate window is only for a ZacUI whose settings part is not there.
local function OpenOptions()
	local mod = ns:GetModule("worldmap")
	if mod.enabled and mod.OpenMenu and mod:OpenMenu() then return end
	local z = _G.ZacUI
	if type(z) == "table" and z.OpenConfig then
		local cfg = type(_G.ZacUIDB) == "table" and _G.ZacUIDB.config
		if type(cfg) == "table" then cfg.tabs = cfg.tabs or {} cfg.tabs.maps = "worldmap" end
		z.OpenConfig("maps")
		return
	end
	local ACD = LibStub("AceConfigDialog-3.0", true)
	if ACD then ACD:Open("ZacUI Map") end
end
ns.OpenOptions = OpenOptions

local function Slash(msg)
	local raw = (msg or ""):match("^%s*(.-)%s*$")
	msg = raw:lower()
	local mod = ns:GetModule("worldmap")
	local word, rest = msg:match("^(%S+)%s+(.+)$")
	local takes = { bench = true, entrance = true }  -- (/openmap bench 16: at that zoom; /openmap entrance Dire Maul - East)
	if takes[word] then msg, rest = word, raw:match("^%S+%s+(.+)$") end
	local run = {
		status = "Diag", paint = "TogglePaint", notes = "TogglePaint", debug = "ToggleDebugOverlay",
		bench = "Bench", pins = "TogglePins", news = "ToggleNews", entrance = "Entrance", draw = "ToggleSketch", dungeons = "DungeonDiag",
		welcome = "ShowWelcome",
	}
	if msg == "welcome" and mod.ShowWelcome then
		mod:ShowWelcome()                       -- (the choice of map: asked with the map on or off)
	elseif run[msg] then
		if mod.enabled and mod[run[msg]] then mod[run[msg]](mod, takes[msg] and rest or nil)
		elseif mod.padWaits then ns:Print(mod.PadOffText())
		else ns:Print(ns.L["The map is off."]) end
	else
		OpenOptions()
	end
end

-- (ZacUI: off on this game version, Core.lua - nothing starts)
if ns.flavorOff then return end

-- UNDER A GAME LOOK THE WORLD MAP IS THE GAME'S OWN (ZacUI, 2026-11-14). Zac on WoW Forever, under
-- the WoW Forever look, with this map up: "in forever style this is not the forever map on forever
-- you need to do a better job with the styling stuff". A game look (WoW Forever, Blizzard style,
-- Classic WoW UI on the "Maps" part) means the game's own UI, and this stitched map is ZacUI's
-- alone: it could wear the look's chrome, it could not be that look's map. So the first login under
-- a game look turns it off (the game's map opens), and remembers what it was; "Enable ZacUI Map"
-- ticked by hand after that stays ticked (the choice is the player's, under any look); back under
-- ZacUI's look it is what it was before. Asked once a login, before the modules start: the look is
-- latched for the session and changes with a reload, as turning this map on or off does.
--   db.lookMap     nil: never under a game look (or back under ZacUI's);  false: turned off for one
--   db.lookMapWas  what `enabled` was under ZacUI's look
function ns.FollowLook()
	local Z = _G.ZacUI
	local L = type(Z) == "table" and Z.Look
	if not (L and L.Stock) then return end
	local mod = ns:GetModule("worldmap")
	local db = mod and mod.db
	if not db then return end
	if L.Stock("maps") then
		if db.lookMap == nil then
			db.lookMapWas = db.enabled and true or false
			db.enabled = false
			db.lookMap = false
		end
	elseif db.lookMap ~= nil then
		if db.lookMapWas ~= nil then db.enabled = db.lookMapWas end
		db.lookMap, db.lookMapWas = nil, nil
	end
end
-- WHO IS ASKED WHICH MAP (2026-11-14, Zac: "also should prompt on map first open why did you get rid
-- of that"). The engine's "Choose your map" at the first opening was switched off on 2026-10-31. It
-- is back, as the choice that matters now (Welcome.lua): the game's own map, or ZacUI's seamless
-- one. Asked the first time the map opens on a new install, and on a save whose seamless map was
-- turned off by a game look and not by its player (lookMap false, lookMapWas true); a save that has
-- had the seamless map on or off by its own choice is never asked. Decided once, here, after FollowLook.
--   db.mapAsked   nil: not decided;  false: to be asked at the map's next opening;  true: done
function ns.MapAskDecide()
	local mod = ns:GetModule("worldmap")
	local db = mod and mod.db
	if not db or db.mapAsked ~= nil then return end
	db.mapAsked = not (mod.fresh or (db.lookMap == false and db.lookMapWas == true))
end
-- the game look the map stands down for, by name (nil: none, or the map is on)
function ns.LookStandDown()
	local Z = _G.ZacUI
	local L = type(Z) == "table" and Z.Look
	local mod = ns:GetModule("worldmap")
	if not (L and L.Stock and L.For and mod and mod.db) or mod.db.enabled or not L.Stock("maps") then return nil end
	local look = L.For("maps")
	return look and look.name or nil
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" and name == ADDON then
		ns:InitDB()
		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_LOGIN" then
		local t0 = debugprofilestop and debugprofilestop()
		ns.FollowLook()
		ns.MapAskDecide()
		ns:EnableModules()
		if t0 then ns.loadMs.login = debugprofilestop() - t0 end
		local AC = LibStub("AceConfig-3.0", true)
		if AC then AC:RegisterOptionsTable("ZacUI Map", Options) end
		-- a page in Blizzard's settings that opens the options window
		if Settings and Settings.RegisterCanvasLayoutCategory then
			local panel = CreateFrame("Frame")
			local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
			title:SetPoint("TOPLEFT", 16, -16)
			title:SetText("ZacUI |cff33ff99World map|r")
			local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
			button:SetSize(180, 26)
			button:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
			button:SetText(ns.L["Open ZacUI Map's settings"])
			button:SetScript("OnClick", function()
				if SettingsPanel then HideUIPanel(SettingsPanel) end
				OpenOptions()
			end)
			Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(panel, "ZacUI World map"))
		end
		SLASH_ZACUIMAP1, SLASH_ZACUIMAP2 = "/zuimap", "/zmap"
		SlashCmdList.ZACUIMAP = Slash
		self:UnregisterEvent("PLAYER_LOGIN")
	end
end)

function ns.NotifyOptions()
	local ACR = LibStub("AceConfigRegistry-3.0", true)
	if ACR then ACR:NotifyChange("ZacUI Map") end
end
