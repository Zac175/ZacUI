--------------------------------------------------------------------------------
-- Ways into OpenMap's menu besides its button on the map (which can be hidden:
-- Panel.lua's mapButtons): the game's addon compartment (the minimap's AddOns
-- list) and, when turned on, a button on the minimap's edge, dragged round it.
-- Click: the map with its menu open; right-click: the options window.
--------------------------------------------------------------------------------

local _, ns = ...
-- (ZacUI: not on this game version, Core.lua. Nothing loads; only the
-- globals the game itself calls by name stay - the AddOns-list entry the
-- .toc names, and the key bindings - and they say why.)
if ns.flavorOff then
	local function Why()
		local Z = _G.ZacUI
		return (Z and Z.FeatureOffNote and Z.FeatureOffNote("worldmap")) or "off on this game version"
	end
	local function Say()
		local Z = _G.ZacUI
		if Z and Z.Print then Z.Print("World map: " .. Why()) end
	end
	_G.ZacuiWorldMap_OnAddonCompartmentClick = Say
	_G.ZacuiWorldMap_OnAddonCompartmentEnter = function(_, owner)
		GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
		GameTooltip:AddLine("ZacUI Map")
		GameTooltip:AddLine(Why(), nil, nil, nil, true)
		GameTooltip:Show()
	end
	_G.ZacuiWorldMap_OnAddonCompartmentLeave = function() GameTooltip:Hide() end
	_G.ZacuiWorldMap_Binding = Say
	return
end
local mod = ns:GetModule("worldmap")
local L = ns.L

local d = mod.defaults
d.minimapButton = false         -- a button on the minimap's edge
d.minimapAngle = 200            -- where round the minimap it sits (degrees, counter-clockwise from east)

local ICON = "Interface\\Icons\\Achievement_Zone_EasternKingdoms_01"   -- (the toc's)
local button

local function OpenMenu()
	if ns.OpenOptions then ns.OpenOptions() end
end

local function OpenWindow()
	local ACD = LibStub("AceConfigDialog-3.0", true)
	if ACD then ACD:Open("ZacUI Map") end
end

local function Click(mouse)
	if mouse == "RightButton" then OpenWindow() else OpenMenu() end
end

local function Tip(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
	GameTooltip:AddLine("|cff" .. ns.ACCENT .. "ZacUI|r Map")
	GameTooltip:AddLine(L["Click: the map and its menu"], 1, 1, 1)
	GameTooltip:AddLine(L["Right-click: the options window"], 1, 1, 1)
	if owner == button then GameTooltip:AddLine(L["Drag: move it round the minimap"], 0.6, 0.6, 0.6) end
	GameTooltip:Show()
end

-- the addon compartment (the toc's AddonCompartmentFunc*): globals, as the game looks them up by name
_G.ZacuiWorldMap_OnAddonCompartmentClick = function(_, mouse)
	-- (ZacUI: off on this game version - say why instead of opening nothing)
	if ns.flavorOff then
		local Z = _G.ZacUI
		if Z and Z.Print and Z.FeatureOffNote then Z.Print("World map: " .. (Z.FeatureOffNote("worldmap") or "off")) end
		return
	end
	Click(mouse)
end
_G.ZacuiWorldMap_OnAddonCompartmentEnter = function(_, owner) Tip(owner) end
_G.ZacuiWorldMap_OnAddonCompartmentLeave = function() GameTooltip:Hide() end

local function Place()
	local a = math.rad(mod.db.minimapAngle or 200)
	local r = Minimap:GetWidth() / 2 + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

-- Blizzard's own minimap button: the tracking button's border round the icon
local function Make()
	button = CreateFrame("Button", "ZacuiWorldMapMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local bg = button:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetSize(20, 20)
	bg:SetPoint("TOPLEFT", 7, -5)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICON)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetScript("OnClick", function(_, mouse) Click(mouse) end)
	button:SetScript("OnEnter", Tip)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local s = Minimap:GetEffectiveScale()
			if mx then mod.db.minimapAngle = math.deg(math.atan2(cy / s - my, cx / s - mx)) end
			Place()
		end)
	end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
end

function mod.RefreshLauncher()
	if mod.db.minimapButton and Minimap then
		if not button then Make() end
		Place()
		button:Show()
	elseif button then
		button:Hide()
	end
end

function mod:LauncherOptions(opts, get, off)
	local function set(info, v) mod.db[info[#info]] = v mod.RefreshLauncher() end
	opts.minimapButton = { type = "toggle", name = L["Minimap button"], order = 28.5, get = get, set = set, disabled = off,
		desc = L["A button on the minimap's edge that opens the map and its menu (right-click: this window). Drag it round the minimap. ZacUI Map is in the minimap's AddOns list too."] }
	opts.mapButtons = { type = "toggle", name = L["ZacUI Map button on the map"], order = 28.6, get = get, disabled = off,
		set = function(_, v) mod.db.mapButtons = v mod:Refresh() end,
		desc = L["The ZacUI Map button and your favourites on the map. Off, the menu opens with /zuimap, the minimap button or the minimap's AddOns list."] }
end

-- (at login, before the map is first opened: the button doesn't wait for the map)
if ns.flavorOff then return end   -- (ZacUI: off on this game version, Core.lua)
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_LOGIN")
	if mod.db and mod.db.enabled then mod.RefreshLauncher() end
end)
