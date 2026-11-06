--------------------------------------------------------------------------------
-- OpenMap's core: saved settings, events, chat output, options plumbing and
-- the few look helpers the map uses. Loaded first; the map files (Map/*.lua)
-- add a module with ns:NewModule and Init.lua starts it at login.
--
-- Settings: ZacuiWorldMapDB (account), ZacuiWorldMapCharDB (per character), filled from
-- the module's defaults (missing keys only, so new defaults reach old saves).
--------------------------------------------------------------------------------

local ADDON, ns = ...
-- (ZacUI: the stitched map holds Classic Era's Azeroth only, so on TBC - or
-- under the game-version override's TBC - the part stands down: it is not
-- published, and its login, slash and launcher are never set up. The map
-- files still load, but only define; nothing of theirs starts. Core_Flavor.)
do
	local Z = _G.ZacUI
	ns.flavorOff = (Z and Z.PartOff and Z.PartOff("Zacui_WorldMap")) and true or false
end
if not ns.flavorOff then _G.ZacuiWorldMap = ns end

ns.name = ADDON
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON, "Version") or "dev"
if ns.version:find("^@") then ns.version = "dev" end   -- (a checkout: the packager fills it in for releases)
ns.ACCENT = "e6b85c"
do	-- (ZacUI's accent, as a hex string for the chat and the titles)
	local z = _G.ZacUI
	local c = z and z.Col and z.Col("accent")
	if c then ns.ACCENT = string.format("%02x%02x%02x", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5)) end
end
-- where players send reports (the "Report a problem" button shows it to copy): OpenMap's comments on
-- CurseForge (the GitHub repository's issues, map-problem.yml, are out of reach for now)
ns.ISSUES_URL = "https://www.curseforge.com/wow/addons/zacui"
ns.Media = { path = "Interface\\AddOns\\" .. ADDON .. "\\Media\\" }
-- what loading costs (ms): its files, the login, the map's setup and its parts (/openmap status)
ns.loadMs = { start = debugprofilestop and debugprofilestop(), parts = {} }

-- Translations: ns.L["English text"] gives the text for the player's language once a
-- translation fills it in (none yet), else the English. Place names come from the game.
ns.L = setmetatable({}, { __index = function(_, k) return k end })

function ns:Print(fmt, ...)
	local msg = select("#", ...) > 0 and fmt:format(...) or tostring(fmt)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ZacUI|r map: " .. msg)
end

--------------------------------------------------------------------------------
-- Secret-safe reads (clients with secret values, e.g. WoW Forever)
--------------------------------------------------------------------------------

local Safe = {}
ns.Safe = Safe

function Safe.IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v) or false
end

function Safe.Value(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

-- a position's x, y: Blizzard's vectors have GetXY, but some APIs on this client hand back
-- a plain { x, y } table
function Safe.XY(vec)
	if type(vec) ~= "table" then return end
	if vec.GetXY then return vec:GetXY() end
	return vec.x, vec.y
end

-- calls fn(...) and returns its first result when it is plain, else nil
function Safe.Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn, ...)
	if not ok then return nil end
	return Safe.Value(v)
end

--------------------------------------------------------------------------------
-- Events: any number of handlers per event, keyed by owner
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}
eventFrame:SetScript("OnEvent", function(_, event, ...)
	for owner, fn in pairs(handlers[event] or {}) do
		local ok, err = pcall(fn, owner, event, ...)
		if not ok then geterrorhandler()(err) end
	end
end)

function ns.RegisterEvent(owner, event, fn)
	if not handlers[event] then
		if not pcall(eventFrame.RegisterEvent, eventFrame, event) then return false end
		handlers[event] = {}
	end
	handlers[event][owner] = fn or owner[event]
	return true
end

function ns.UnregisterEvent(owner, event)
	local list = handlers[event]
	if not list then return end
	list[owner] = nil
	if next(list) == nil then
		handlers[event] = nil
		eventFrame:UnregisterEvent(event)
	end
end

--------------------------------------------------------------------------------
-- Modules (OpenMap has one, "worldmap")
--------------------------------------------------------------------------------

ns.modules = {}

function ns:NewModule(key, spec)
	local mod = spec or {}
	mod.key = key
	mod.defaults = mod.defaults or {}
	if mod.defaults.enabled == nil then mod.defaults.enabled = true end
	ns.modules[key] = mod
	return mod
end

function ns:GetModule(key)
	return ns.modules[key]
end

-- missing keys from defaults, recursively
local function Fill(t, defaults)
	for k, v in pairs(defaults) do
		if t[k] == nil then
			t[k] = type(v) == "table" and Fill({}, v) or v
		elseif type(v) == "table" and type(t[k]) == "table" then
			Fill(t[k], v)
		end
	end
	return t
end

function ns:InitDB()
	ZacuiWorldMapDB = ZacuiWorldMapDB or {}
	ZacuiWorldMapCharDB = ZacuiWorldMapCharDB or {}
	for key, mod in pairs(ns.modules) do
		mod.fresh = ZacuiWorldMapDB[key] == nil       -- (no saved settings yet: a new install)
		-- (an old save's settings carried to the keys that replace them, before the defaults fill those)
		if not mod.fresh and mod.Migrate then mod.Migrate(ZacuiWorldMapDB[key]) end
		ZacuiWorldMapDB[key] = Fill(ZacuiWorldMapDB[key] or {}, mod.defaults)
		ZacuiWorldMapCharDB[key] = ZacuiWorldMapCharDB[key] or {}
		mod.db, mod.char = ZacuiWorldMapDB[key], ZacuiWorldMapCharDB[key]
	end
end

function ns:EnableModules()
	for _, mod in pairs(ns.modules) do
		if mod.db.enabled and not mod.enabled then
			mod.enabled = true
			if mod.OnEnable then
				local ok, err = pcall(mod.OnEnable, mod)
				if not ok then
					mod.enabled = false
					ns:Print("|cffff6060failed to start|r: %s", tostring(err):sub(1, 300))
					geterrorhandler()(err)
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Options (AceConfig tables)
--------------------------------------------------------------------------------

-- get / set for options stored in getTable(info)[key]; refresh() after a change
function ns.Bind(getTable, refresh)
	local function get(info)
		local v = getTable(info)[info[#info]]
		if info.type == "color" then
			v = v or { 1, 1, 1, 1 }
			return v[1], v[2], v[3], v[4] or 1
		end
		return v
	end
	local function set(info, a, b, c, d)
		local t = getTable(info)
		if info.type == "color" then
			t[info[#info]] = { a, b, c, d or 1 }
		else
			t[info[#info]] = a
		end
		if refresh then refresh(info) end
	end
	return get, set
end

function ns.Header(name, order)
	return { type = "header", name = name, order = order }
end

function ns.Desc(text, order)
	return { type = "description", name = text, order = order, fontSize = "medium" }
end

--------------------------------------------------------------------------------
-- Look: ZacUI's. Every window, panel, dropdown and font of the map engine comes
-- through here, and here it is drawn with ZacUI's own primitives (Col for the
-- palette, ResolveFontPath for the font, SkinCloseButton for the X), so the
-- engine's windows are ZacUI windows: flat fill, one-pixel border, a 22 px
-- header with the gold hairline under it, the title in the window font. The
-- engine's original look (Blizzard's nine-slice over rock, a plain dark panel)
-- is the fallback when the ZacUI namespace is somehow not there.
--------------------------------------------------------------------------------

local Look = {}
ns.Look = Look

local HEADER_H = 22

local function Z() return _G.ZacUI end
local function ZCol(key)
	local z = Z()
	if z and z.Col then return z.Col(key) end
end

-- SetFont that says whether the face took: pcall catches a nil path, the
-- return value a font file that would not load - which leaves the string
-- with no font, so its next SetText errors ("Font not set")
local function TrySetFont(fs, path, size, flags)
	local ok, set = pcall(fs.SetFont, fs, path, size, flags)
	return (ok and set) and true or false
end
function Look:Font(fs, size, flags)
	local z = Z()
	local cfg = _G.ZacUIDB and _G.ZacUIDB.font or {}
	local path = z and z.ResolveFontPath and z.ResolveFontPath(cfg.name)
	if flags == nil then flags = (cfg.outline == "NONE") and "" or "OUTLINE" end
	local sz = (size or 12) + (cfg.delta or 0)
	if not (path and TrySetFont(fs, path, sz, flags)) then
		if not fs:SetFont(STANDARD_TEXT_FONT, sz, flags or "") then fs:SetFontObject(GameFontHighlight) end
	end
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetShadowOffset(1, -1)
	return fs
end

-- a flat fill with a one-pixel border behind `frame`; opts: inset, alpha
function Look:Panel(frame, opts)
	opts = opts or {}
	local bd = frame.omBackdrop
	if not bd then
		bd = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		bd:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
		frame.omBackdrop = bd
	end
	local inset = opts.inset or 0
	bd:ClearAllPoints()
	bd:SetPoint("TOPLEFT", -inset, inset)
	bd:SetPoint("BOTTOMRIGHT", inset, -inset)
	bd:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	local bg, br = ZCol("windowBg"), ZCol("border")
	if bg then bd:SetBackdropColor(bg.r, bg.g, bg.b, opts.alpha or bg.a or 0.95)
	else bd:SetBackdropColor(0.06, 0.06, 0.07, opts.alpha or 0.9) end
	if br then bd:SetBackdropBorderColor(br.r, br.g, br.b, br.a or 1)
	else bd:SetBackdropBorderColor(0, 0, 0, 1) end
	return bd
end

-- a dropdown list: the same flat panel. Returns the room to leave inside it: left, top, right, bottom
function Look:Dropdown(frame)
	Look:Panel(frame, { alpha = 0.97 })
	return 6, 6, 6, 6
end

-- the header band of a window: a fill a shade lighter than the window, a gold hairline under it
local function Header(frame)
	local bar = CreateFrame("Frame", nil, frame)
	bar:SetHeight(HEADER_H)
	bar:SetPoint("TOPLEFT", 1, -1)
	bar:SetPoint("TOPRIGHT", -1, -1)
	bar:SetFrameLevel(frame:GetFrameLevel())
	local fill = bar:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	fill:SetTexture("Interface\\Buttons\\WHITE8X8")
	local h = ZCol("headerBg")
	if h then fill:SetVertexColor(h.r, h.g, h.b, h.a or 1) else fill:SetVertexColor(0.12, 0.12, 0.12, 1) end
	local rule = bar:CreateTexture(nil, "ARTWORK")
	rule:SetTexture("Interface\\Buttons\\WHITE8X8")
	rule:SetHeight(1)
	rule:SetPoint("BOTTOMLEFT")
	rule:SetPoint("BOTTOMRIGHT")
	local a = ZCol("accent")
	if a then rule:SetVertexColor(a.r, a.g, a.b, 0.5) else rule:SetVertexColor(0.85, 0.65, 0.25, 0.5) end
	frame.omHeader = bar
	return bar
end

-- a ZacUI window on `frame`: the flat panel, the header band, a gold title in it and a
-- ZacUI close button. Returns the header's height (content starts below it), the title and the X.
function Look:Window(frame, title, onClose)
	Look:Panel(frame, { alpha = 0.96 })
	local bar = Header(frame)
	local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	Look:Font(text, 12)
	local gold = ZCol("accent")
	if gold then text:SetTextColor(gold.r, gold.g, gold.b, 1) end
	text:SetPoint("LEFT", bar, "LEFT", 10, 0)
	text:SetPoint("RIGHT", bar, "RIGHT", -28, 0)
	text:SetJustifyH("CENTER")
	text:SetWordWrap(false)
	text:SetText(title or "")
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetFrameLevel(frame:GetFrameLevel() + 20)
	close:SetSize(HEADER_H, HEADER_H)
	close:SetHitRectInsets(-4, -4, -4, -4)
	close:SetPoint("TOPRIGHT", -1, -1)
	local z = Z()
	if z and z.SkinCloseButton then pcall(z.SkinCloseButton, close, 16) end
	close:SetScript("OnClick", onClose or function() frame:Hide() end)
	return HEADER_H, text, close
end

-- the same chrome on a frame that is its own backdrop (the menu): header height back
function Look:Chrome(frame)
	Look:Panel(frame, { alpha = 0.96 })
	Header(frame)
	return HEADER_H
end
