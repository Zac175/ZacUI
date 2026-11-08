-- Config_PagesMinimap - the Minimap page.
-- Part of ZacUI; load order is set by the TOC.
--
-- EVERY CONTROL HERE IS LIVE. Nothing asks for a reload, because the
-- options layer shows and hides rather than skipping setup - a setting
-- that needs a reload to take effect is one people assume is broken.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local Print = ns.Print
local RefreshConfig = ns.RefreshConfig
local RegisterPage = ns.RegisterPage
local UI = ns.UI

local M, F = UI.M, UI.F

-- One helper for the whole page: every setting is a key in
-- ZacUIDB.minimap and every change wants the same thing afterwards.
-- Marker settings live in ns.MinimapPins' own defaults table, which is
-- the SAME ZacUIDB.minimap the options layer uses - one store, two files
-- that fill in different keys. Reading through both means a control
-- cannot show a blank because the other file has not run yet.
local PIN_KEYS = {
    pins = true, pinFlight = true, pinGrave = true,
    pinDungeon = true, pinCrossing = true, pinSize = true,
    groupNames = true, groupNameSize = true, groupNameDeclutter = true,
}

local function Bind(L, kind, key, label, desc, opts)
    local MM = ns.MinimapOptions
    if not MM then return end
    local db = (PIN_KEYS[key] and ns.MinimapPins) and ns.MinimapPins.DB()
        or MM.DB()
    opts = opts or {}

    local function changed(v)
        db[key] = v
        MM.Refresh()
    end

    local widget
    if kind == "check" then
        widget = UI.Checkbox(L.current, label, db[key] and true or false, changed)
        L:Row(widget, 17)
    elseif kind == "dropdown" then
        local title = UI.Font(L.current, F.LABEL, { text = label })
        L:Row(title, 16)
        local function TextOf(v)
            for _, it in ipairs(opts.items) do
                if it.value == v then return it.text end
            end
            return tostring(v)
        end
        widget = UI.Dropdown(L.current, {
            width = 260,
            items = function() return opts.items end,
            selectedValue = function() return db[key] end,
            selected = function() return TextOf(db[key]) end,
            onSelect = function(v) changed(v) end,
        })
        L:Row(widget, M.DROPDOWN_H + 6)
    else
        widget = UI.Slider(L.current, {
            width = 200, min = opts.min, max = opts.max, step = opts.step,
            value = opts.get and opts.get(db[key]) or db[key],
            label = label, format = opts.format,
            onChange = function(v) changed(opts.set and opts.set(v) or v) end,
        })
        L:Row(widget, 40)
    end
    if desc then L:Desc(desc) end
    return widget
end

-- ============================================================
-- PREVIEW
-- ============================================================
-- A sample map with the real pills, outline, hover ring, header and
-- footer on it - built and painted by Blz_Minimap's own functions
-- (ns.MinimapLook). Modes show it with the mouse away (the pieces that
-- wait for the mouse are hidden) and over it; Replay plays the fade.
local Kit = ns.CorePageKit
if Kit then
    Kit.Keywords("minimap", "pill pills font text border outline thickness colour color ring "
        .. "edge hover spacing gap darkness opacity fade animation map only panel "
        .. "tray background open opening icon icons mail tracking battleground queue group finder eye "
        .. "corner header footer panel texts layout grow wrap per line")
end

local function BuildMapPreview(canvas, P)
    local ML = ns.MinimapLook
    local UIF = ns.UI
    local st = P.store
    local map = CreateFrame("Frame", nil, canvas)
    local water = map:CreateTexture(nil, "BACKGROUND")
    water:SetAllPoints()
    water:SetTexture(ns.FLAT)
    water:SetVertexColor(0.16, 0.22, 0.15, 1)
    local road = map:CreateTexture(nil, "BORDER")
    road:SetTexture(ns.FLAT)
    road:SetVertexColor(0.33, 0.29, 0.2, 1)
    road:SetPoint("LEFT", map, "LEFT", 0, 10)
    road:SetPoint("RIGHT", map, "RIGHT", 0, -20)
    road:SetHeight(5)
    local arrow = map:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    arrow:SetSize(24, 24)
    arrow:SetPoint("CENTER")
    st.map = map

    -- the panel look's header and footer
    local head = CreateFrame("Frame", nil, map)
    head:SetHeight(ML.HEAD_H)
    head:SetPoint("BOTTOMLEFT", map, "TOPLEFT", 0, 0)
    head:SetPoint("BOTTOMRIGHT", map, "TOPRIGHT", 0, 0)
    UIF.Fill(head, "ui", "headerBg")
    local rule = ML.Rule(head, "ui", "accent", 0.6)
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    head._zRule = rule
    -- the zone name sits in a button inset in the header, as the real one does
    local headHost = CreateFrame("Frame", nil, head)
    headHost:SetPoint("TOPLEFT", head, "TOPLEFT", 4, 0)
    headHost:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", -4, 1)
    st.headHost = headHost
    head._zText = UIF.Font(headHost, 12, { justify = "CENTER" })
    head._zText:SetPoint("LEFT", headHost, "LEFT", 0, 0)
    head._zText:SetPoint("RIGHT", headHost, "RIGHT", 0, 0)
    st.head = head
    local foot = CreateFrame("Frame", nil, map)
    foot:SetHeight(ML.FOOT_H)
    foot:SetPoint("TOPLEFT", map, "BOTTOMLEFT", 0, 0)
    foot:SetPoint("TOPRIGHT", map, "BOTTOMRIGHT", 0, 0)
    UIF.Fill(foot, "ui", "headerBg")
    local top = ML.Rule(foot, "ui", "border")
    top:SetHeight(1)
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    foot._zRule = top
    st.foot = foot
    st.fFriends, st.fClock, st.fGuild = ML.Segment(foot), ML.Segment(foot), ML.Segment(foot)
    st.fClock:SetWidth(52)
    st.fClock:SetPoint("TOP", foot, "TOP", 0, -1)
    st.fClock:SetPoint("BOTTOM", foot, "BOTTOM", 0, 0)
    st.fFriends:SetPoint("TOPLEFT", foot, "TOPLEFT", 0, -1)
    st.fFriends:SetPoint("BOTTOMRIGHT", st.fClock, "BOTTOMLEFT", -1, 0)
    st.fGuild:SetPoint("TOPLEFT", st.fClock, "TOPRIGHT", 1, 0)
    st.fGuild:SetPoint("BOTTOMRIGHT", foot, "BOTTOMRIGHT", 0, 0)
    -- the clock's time sits in the middle of its cell (the real ticker's spot)
    st.fClock._zText:ClearAllPoints()
    st.fClock._zText:SetPoint("CENTER", st.fClock, "CENTER", 0, 0)

    -- the outline round it all, and the hover ring outside that
    local outline = CreateFrame("Frame", nil, map)
    outline:SetFrameLevel(map:GetFrameLevel() + 1)
    UIF.Border(outline, "ui", "border")
    st.outline = outline
    local edge = CreateFrame("Frame", nil, outline)
    edge:SetPoint("TOPLEFT", outline, "TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", outline, "BOTTOMRIGHT", 1, -1)
    UIF.Border(edge, "ui", "accent")
    st.edge = edge

    -- the map-only look's pills
    local function PillWith(text)
        local pill = ML.Pill(map)
        pill._zText = UIF.Font(pill, 12, { justify = "CENTER" })
        pill._zText:SetPoint("CENTER", 0, 0)
        pill._zText:SetText(text)
        return pill
    end
    st.zone = PillWith("Elwynn Forest")
    st.clock = PillWith("9:41 PM")
    st.friends = PillWith("Fr 3")
    st.guild = PillWith("G 12")
    st.coords = PillWith("42.1, 65.3")
    -- the corner icons, dressed by the real map's CornerIcon (mail and
    -- tracking) or placed as the module places Blizzard's (the battleground
    -- crest and the group finder eye show while picked or placed)
    st.icons = {}
    for _, e in ipairs({ { "mail", ns.MEDIA and (ns.MEDIA .. "mail") or "Interface\\Icons\\INV_Letter_15", true },
                         { "tracking", "Interface\\Icons\\INV_Misc_Flower_02", true },
                         { "battlefield", "Interface\\Icons\\INV_BannerPVP_02", false, 22 },
                         { "lfg", "Interface\\Icons\\INV_Misc_Eye_01", false, 28 } }) do
        local k = e[1]
        local f = CreateFrame("Frame", nil, map)
        local tex = f:CreateTexture(nil, "ARTWORK")
        tex:SetTexture(e[2])
        local d = ML.IconDefault(k, map)
        if e[3] then
            ML.CornerIcon(f, tex, d.point, d.x, d.y, nil, map)
        else
            f:SetSize(e[4], e[4])
            f:SetPoint(d.point, map, d.relPoint, d.x, d.y)
            f:SetFrameLevel(map:GetFrameLevel() + 5)
            tex:SetAllPoints()
            -- (icons standing in for the game's buttons: cropped as icons)
            ns.Look.CropIcon(tex, e[4], e[4])
        end
        st.icons[k] = f
    end
    -- everything Blz_Minimap's PlacePanelTexts / PlaceIcons place, by name
    st.parts = { map = map, header = head, footer = foot, coords = st.coords,
        zone = head._zText, zoneHost = headHost, clock = st.fClock._zText, clockHost = st.fClock,
        friends = st.fFriends._zText, friendsHost = st.fFriends, guild = st.fGuild._zText, guildHost = st.fGuild,
        icons = st.icons }
    -- the pick hook: a click on a sample pill opens its fine placement, a
    -- panel text its position on Text, an icon its spot on Position
    if ns.TagElement then
        for _, k in ipairs({ "zone", "clock", "friends", "guild", "coords" }) do ns.TagElement(st[k], "minimap." .. k) end
        ns.TagElement(head, "minimap.panelZone")
        ns.TagElement(st.fClock, "minimap.panelClock")
        ns.TagElement(st.fFriends, "minimap.panelFriends")
        ns.TagElement(st.fGuild, "minimap.panelGuild")
        for k, f in pairs(st.icons) do ns.TagElement(f, "minimap." .. k) end
    end
    st.reveal = 1
    -- the fade on Replay: an OnUpdate on a sample-only frame
    st.fader = CreateFrame("Frame", nil, canvas)
    st.fader:Hide()
end

local REVEAL = {
    { key = "zoneHover",   pieces = { "zone" } },
    { key = "coordsHover", pieces = { "coords" } },
    { key = "socialHover", pieces = { "friends", "guild" } },
    { key = "clockHover",  pieces = { "clock" } },
}

local function ApplyMapReveal(st, a)
    local ML = ns.MinimapLook
    local overlay = ML.Overlay()
    for _, part in ipairs(REVEAL) do
        local alpha = (overlay and ML.Setting(part.key)) and a or 1
        for _, k in ipairs(part.pieces) do st[k]:SetAlpha(alpha) end
    end
    st.edge:SetAlpha((overlay and ML.Setting("hoverEdge")) and a or 0)
end

local function UpdateMapPreview(canvas, P)
    local ML = ns.MinimapLook
    local MM = ns.MinimapOptions
    local st = P.store
    local d = MM.DB()
    local overlay = ML.Overlay()
    local S = tonumber(d.mapSize) or 0
    if S <= 0 then S = 140 end
    S = math.max(100, math.min(260, S))
    local map = st.map
    if ns.Motion then ns.Motion.Stop(st.fader) end
    st.fader:SetScript("OnUpdate", nil)
    st.fader:Hide()
    map:SetSize(S, S)

    -- panel look
    st.head:SetShown(not overlay and d.zoneName ~= false)
    st.foot:SetShown(not overlay and (d.clock ~= false or d.infoBar ~= false))
    -- the canvas is the map with its header and footer, at its real size;
    -- the strip scales it
    local headH = st.head:IsShown() and ML.HEAD_H or 0
    local footH = st.foot:IsShown() and ML.FOOT_H or 0
    map:ClearAllPoints()
    map:SetPoint("CENTER", canvas, "CENTER", 0, (footH - headH) / 2)
    if P.Resize then P.Resize(S + 6, S + headH + footH + 6) end
    if not overlay then
        st.head._zText:SetText("Elwynn Forest")
        ML.StyleFS(st.head._zText, 12)
        ns.UI.PaintBox(st.head)
        ML.PaintRule(st.head._zRule)
        ns.UI.PaintBox(st.foot)
        ML.PaintRule(st.foot._zRule)
        for _, pair in ipairs({ { st.fFriends, "Friends |cffffd1003|r" }, { st.fClock, "9:41 PM" },
                                { st.fGuild, "Guild |cffffd10012|r" } }) do
            pair[1]:_zPaint()
            pair[1]._zText:SetText(pair[2])
            ML.StyleFS(pair[1]._zText, ns.UI.F.SMALL)
        end
    end
    st.outline:ClearAllPoints()
    st.outline:SetPoint("TOPLEFT", (st.head:IsShown() and st.head) or map, "TOPLEFT", -1, 1)
    st.outline:SetPoint("BOTTOMRIGHT", (st.foot:IsShown() and st.foot) or map, "BOTTOMRIGHT", 1, -1)
    ML.PaintOutline(st.outline, "borderColor", tonumber(ML.Look("borderSize")) or 1)
    ML.PaintOutline(st.edge, "edgeColor")

    -- map-only look: the pills, sized and stacked the way the real ones are
    local size = ML.TextSize()
    local pillH = size + 7
    local want = {
        zone = overlay and d.zoneName ~= false, clock = overlay and d.clock ~= false,
        friends = overlay and d.infoBar ~= false, guild = overlay and d.infoBar ~= false,
        coords = d.coords ~= false,
    }
    local pad = { zone = 16, clock = 14, friends = 12, guild = 12, coords = 14 }
    -- the coordinates as your saved format reads them
    local cf = type(d.formats) == "table" and d.formats.coords
    st.coords._zText:SetText((cf and ML.CoordsText) and ML.CoordsText(0.421, 0.653) or "42.1, 65.3")
    for k, on in pairs(want) do
        local pill = st[k]
        pill:SetShown(on)
        local fsz = (k == "zone" or k == "clock") and size or (size - 1)
        if not overlay then fsz = ns.UI.F.SMALL end
        ML.StyleFS(pill._zText, fsz)
        pill:SetHeight(overlay and pillH or 14)
        pill:SetWidth(math.ceil(pill._zText:GetStringWidth() or 40) + pad[k])
        pill:_zPaint()
        local c = ns.GetColor("text", "normal")
        pill._zText:SetTextColor(c.r, c.g, c.b, 1)
    end
    if d.zoneColor == "accent" then
        local a = ns.GetColor("ui", "accent")
        st.zone._zText:SetTextColor(a.r, a.g, a.b, 1)
        st.head._zText:SetTextColor(a.r, a.g, a.b, 1)
    else
        st.zone._zText:SetTextColor(0.1, 1, 0.1, 1)
        st.head._zText:SetTextColor(0.1, 1, 0.1, 1)
    end
    -- the corner icons: mail and tracking as their options say, the crest
    -- and the eye while picked on Position or placed; each at its spot
    local pickedIcon = ZacUIDB.config and ZacUIDB.config.mmIcon
    local placed = type(d.anchors) == "table" and d.anchors or {}
    st.icons.mail:SetShown(d.mail ~= false)
    st.icons.tracking:SetShown(d.tracking ~= false)
    st.icons.battlefield:SetShown(pickedIcon == "battlefield" or placed.battlefield ~= nil)
    st.icons.lfg:SetShown(pickedIcon == "lfg" or placed.lfg ~= nil)
    if ML.PlaceIcons then ML.PlaceIcons(st.parts) end
    if overlay then
        -- a corner icon that is up pushes its corner's pills along, as on the map
        local corner = { TOPLEFT = "mail", BOTTOMLEFT = "tracking", BOTTOMRIGHT = "battlefield", TOPRIGHT = "lfg" }
        ML.PlacePillsOn(map, {
            { frame = st.clock,   key = "clockPos",   def = "BOTTOM" },
            { frame = st.friends, key = "friendsPos", def = "BOTTOMLEFT" },
            { frame = st.guild,   key = "guildPos",   def = "BOTTOMRIGHT" },
            { frame = st.coords,  key = "coordsPos",  def = "BOTTOM" },
            { frame = st.zone,    key = "zonePos",    def = "TOP" },
        }, function(point)
            local f = st.icons[corner[point] or ""]
            return f and f:IsShown() and not f._zIconPlaced
        end)
        if ML.PlacePanelTexts then ML.PlacePanelTexts(st.parts, false) end
    else
        st.coords:ClearAllPoints()
        st.coords:SetPoint("BOTTOM", map, "BOTTOM", 0, 3)
        -- the panel's texts where you put them (Text tab)
        if ML.PlacePanelTexts then ML.PlacePanelTexts(st.parts, true) end
    end
    st.reveal = ((P.mode or "over") == "over") and 1 or 0
    ApplyMapReveal(st, st.reveal)
end

local function ReplayMapPreview(canvas, P)
    local st = P.store
    local d = ns.MinimapOptions.DB()
    local fade = tonumber(d.fadeTime) or 0.2
    local over = (P.mode or "over") == "over"
    local from, to = over and 0 or 1, over and 1 or 0
    if not (ns.Motion and ns.Motion.Enabled()) or fade <= 0 then
        ApplyMapReveal(st, to)
        return
    end
    fade = fade / ns.Motion.Speed()
    local a = from
    ApplyMapReveal(st, a)
    st.fader:Show()
    st.fader:SetScript("OnUpdate", function(self, dt)
        a = (to > from) and math.min(1, a + dt / fade) or math.max(0, a - dt / fade)
        ApplyMapReveal(st, a)
        if a == to then
            self:SetScript("OnUpdate", nil)
            self:Hide()
        end
    end)
end

RegisterPage("Minimap", function(L)
    local MM = ns.MinimapOptions
    L:Header("Minimap",
        "What the minimap shows, how it looks and how big it is, and the button "
        .. "tray that collects addon buttons.")

    if not MM then
        L:Notice("missing", "The minimap options layer did not load.")
        return
    end
    if not (ZacUIDB.modules and ZacUIDB.modules.minimap) then
        L:Notice("off", "The Minimap module is off, so Blizzard's own round minimap is in use.",
            "Modules > HUD", "minimap")
    end
    local function DB() return MM.DB() end
    local function Refresh() MM.Refresh() end
    -- a sample pill picked in the preview: that piece's fine placement
    if ns.CustomPick then
        ns.CustomPick.SetHandler("screen.minimap", function(el)
            local k = type(el) == "string" and el:match("^minimap%.(.+)$")
            local ML = ns.MinimapLook
            if not (k and ML and ML.PIECE_KEYS) then return end
            ZacUIDB.config = ZacUIDB.config or {}
            ZacUIDB.config.tabs = ZacUIDB.config.tabs or {}
            -- the coordinates on the panel look are a panel text
            if k == "coords" and ML.Overlay and not ML.Overlay() then k = "panelCoords" end
            if ML.PIECE_KEYS[k] then
                ZacUIDB.config.mmPiece = k
                ZacUIDB.config.tabs.minimap = "pos"
            elseif ML.PANEL_LABELS and ML.PANEL_HOST_LABELS[k] then
                ZacUIDB.config.mmText = k
                ZacUIDB.config.tabs.minimap = "text"
            elseif ML.ICON_LABELS and ML.ICON_LABELS[k] and k ~= "map" then
                ZacUIDB.config.mmIcon = k
                ZacUIDB.config.tabs.minimap = "pos"
            else
                return
            end
            ns.RefreshConfig()
        end)
    end

    if ns.MinimapLook then
        L:Preview({
            key = "screen.minimap", title = "Minimap",
            width = 146, height = 180,
            -- the cluster's Size (Position tab) scales the live minimap
            gameScale = function() return tonumber(MM.DB().scale) or 1 end,
            modes = { { id = "over", label = "Mouse over" }, { id = "away", label = "Mouse away" } },
            build = BuildMapPreview, update = UpdateMapPreview, replay = ReplayMapPreview,
        })
    end

    local function Tab_general(L)
        L:Card("What to show")
        Bind(L, "check", "zoneName", "Zone name",
            "The header above the map (or its pill on the map-only look). "
            .. "Hiding it does not affect the zone text anywhere else.")
        Bind(L, "check", "clock", "Clock",
            "The middle of the footer (or its pill). Click it for Blizzard's alarm and "
            .. "stopwatch. Arrives with Blizzard's time manager, which loads on "
            .. "demand - so this may take a moment to apply the first time.")
        Bind(L, "check", "infoBar", "Friends and guild",
            "Either side of the clock (or their pills): how many friends (Battle.net included) "
            .. "and guild members are online. Hover for who and where; click to "
            .. "open the list.")
        Bind(L, "check", "coords", "Coordinates",
            "Your position along the bottom edge of the map (or its pill). Blank inside "
            .. "instances, which report no position.")
        Bind(L, "check", "mail", "New mail envelope",
            "Top-left corner. Only ever visible when you have mail waiting.")
        Bind(L, "check", "tracking", "Tracking icon",
            "Bottom-left corner: the tracking spell you have on (Find Herbs, "
            .. "Find Minerals, a hunter track). Right-click it to turn tracking "
            .. "off.")
        L:EndCard()

        L:Card("On mouseover")
        L:Desc("Map only. Ticked pieces wait until your mouse is over the map; "
            .. "unticked ones stay up all the time.")
        Bind(L, "check", "zoneHover", "Zone name")
        Bind(L, "check", "coordsHover", "Coordinates")
        Bind(L, "check", "socialHover", "Friends and guild")
        Bind(L, "check", "clockHover", "Clock")
        L:EndCard()

        L:Card("Zoom")
        Bind(L, "check", "wheelZoom", "Zoom with the mouse wheel",
            "ZacUI hides Blizzard's + and - buttons because the wheel replaces "
            .. "them, so turning this off leaves no way to zoom at all.")
        Bind(L, "check", "smoothZoom", "  ... easing between the zoom levels",
            "The map has six fixed zoom steps; this grows or shrinks the picture over "
            .. "a sixth of a second across each step instead of snapping.")
        Bind(L, "check", "farZoom", "  ... and on out into the map",
            "Past the game's widest level the wheel keeps going a little further, up to "
            .. "three times as wide: the live minimap shrinks in the middle and the zone's "
            .. "map paints in round it at the same scale. Not with a rotating minimap.")
        Bind(L, "check", "autoZoom", "Zoom back out on its own",
            "Fifteen seconds after you last zoomed in, the map returns to fully "
            .. "zoomed out.")
        L:EndCard()

        L:Card("Group names")
        Bind(L, "check", "groupNames", "Names over your group's dots",
            "Each party or raid member's name in their class colour, just above "
            .. "their dot. Out in the world only: inside dungeons and raids the "
            .. "game does not tell addons where anyone is, so there it is just "
            .. "the dots.")
        Bind(L, "check", "groupNameDeclutter", "Leave off names that would overlap")
        L:EndCard()

        L:Card("Markers on the minimap")
        L:Desc("The same icons the world map uses, drawn where they are "
            .. "relative to you. Nothing here takes the mouse, so they cannot "
            .. "eat a click meant for the map underneath.")
        Bind(L, "check", "pins", "Show markers",
            "|cffff9900Off by default.|r Placing these needs a map position "
            .. "turned into yards and yards turned into pixels, and none of "
            .. "that can be checked outside the game - it shipped on once and "
            .. "put markers in fixed spots rather than real ones. Turn it on "
            .. "and run /zui minimapinfo: it prints each marker's distance "
            .. "and offset so you can see whether they line up.")
        Bind(L, "check", "pinFlight", "Flight paths, boats and zeppelins",
            "Yours only - the other faction's are on the world map page.")
        Bind(L, "check", "pinGrave", "Graveyards")
        Bind(L, "check", "pinDungeon", "Dungeon and raid entrances")
        Bind(L, "check", "pinCrossing", "Zone crossings")
        L:Desc("If you see none at all, /zui minimapinfo says why - most "
            .. "often nothing of yours is inside the minimap's current zoom.")
        L:EndCard()

        L:Card("ZacUI's button")
        local MB = ns.MinimapButton
        if MB then
            local mdb = MB.DB()
            local show = UI.Checkbox(L.current, "Show the ZacUI minimap button", not mdb.hide, function(v)
                MB.SetShown(v)
            end)
            L:Row(show, 17)
            L:Desc("Left-click opens the settings, right-click is a menu of pages, profiles, Edit Mode "
                .. "and the aura engine. A proper LibDBIcon button, so HidingBar, MBB and the button "
                .. "tray all collect it like any other.")
            local lock = UI.Checkbox(L.current, "Lock it in place", mdb.lock and true or false, function(v)
                MB.SetLocked(v)
            end)
            L:Row(lock, 17)
            local eng = UI.Checkbox(L.current, "Hide the aura engine's own button", mdb.hideEngineButton and true or false,
                function(v)
                    mdb.hideEngineButton = v and true or false
                    MB.ApplyEngineButton()
                end)
            L:Row(eng, 17)
            L:Desc("The embedded engine (or WeakAuras, when that is the one running) puts a second "
                .. "button on the minimap. ZacUI's menu opens the same editor, so it is hidden by default.")
        else
            L:Desc("The minimap button did not load.")
        end
        L:EndCard()
    end

    local function Tab_look(L)
        L:Card("Map")
        Bind(L, "dropdown", "layout", "Layout", nil, { items = {
            { text = "Map only, details on the map", value = "overlay" },
            { text = "Panel: zone above, clock below", value = "panel" },
        } })
        L:Desc("Panel: the zone name in a strip above the map and friends, clock "
            .. "and guild in a strip below it. Map only: each of those sits on "
            .. "the map in a small pill, where you put it on the Position tab, and can wait "
            .. "for your mouse.")
        Bind(L, "slider", "mapSize", "Map size", nil, {
            min = 100, max = 320, step = 10,
            get = function(v) return (v and v > 0) and v or 140 end,
            set = function(v) return v == 140 and 0 or v end,
            format = function(v) return v == 140 and "140 px (Blizzard's)" or (v .. " px") end,
        })
        L:Desc("The map itself, grown down and to the left from its top-right "
            .. "corner. Size on the Position tab scales everything, text included.")
        if Kit then
            Kit.Color(L, "Outline", DB, "borderColor", Kit.Palette("ui", "border"),
                { alpha = true, after = Refresh })
            Kit.Slider(L, "Outline thickness", DB, "borderSize", { min = 0, max = 4, step = 1,
                get = function(v) return v or 1 end, after = Refresh,
                format = function(v) return v == 0 and "None" or (v .. " px") end })
        end
        Bind(L, "check", "hoverEdge", "Light up the edge",
            "A ring around the map while the mouse is over it (map only).")
        if Kit then
            Kit.Color(L, "Ring colour", DB, "edgeColor", Kit.Palette("ui", "accent"), { after = Refresh })
        end
        Bind(L, "dropdown", "zoneColor", "Zone name colour", nil, { items = {
            { text = "By PvP status (Blizzard's colours)", value = "pvp" },
            { text = "Accent colour", value = "accent" },
        } })
        L:EndCard()

        L:Card("Pills (map only)")
        Bind(L, "slider", "pillAlpha", "Pill darkness", nil, {
            min = 0, max = 100, step = 5,
            get = function(v) return math.floor((v or 0.82) * 100 + 0.5) end,
            set = function(v) return v / 100 end,
            format = function(v) return v .. "%" end,
        })
        L:Desc("How dark the backing behind each piece of text is. "
            .. "Lower lets more of the map show through.")
        if Kit then
            Kit.Color(L, "Pill colour", DB, "pillColor", Kit.Palette("ui", "windowBg"), { after = Refresh })
            Kit.Check(L, "Border round each pill", DB, "pillBorder", nil,
                { after = function() Refresh() RefreshConfig() end })
            if DB().pillBorder then
                Kit.Color(L, "Pill border colour", DB, "pillBorderColor", Kit.Palette("ui", "border"),
                    { alpha = true, after = Refresh })
            end
        end
        L:EndCard()

        L:Card("Markers")
        Bind(L, "slider", "pinSize", "Marker size", nil, { min = 8, max = 24, step = 1 })
        L:EndCard()
    end

    local function Tab_text(L)
        L:Card("Map text")
        local f = ZacUIDB.font
        local fp = UI.FontPicker(L.current, { label = "Zone name, clock, coordinates, friends and guild",
            defaults = { size = 12, outline = (f and f.outline == "NONE") and "none" or "outline", shadow = true },
            minSize = 8, maxSize = 20, sample = "Elwynn Forest  9:41",
            get = function()
                local d, t = DB(), {}
                for k, v in pairs(d.pillFont or {}) do t[k] = v end
                t.size = d.textSize
                return t
            end,
            set = function(spec)
                local d, font = DB(), {}
                if spec.size then d.textSize = spec.size end
                for k, v in pairs(spec) do if k ~= "size" then font[k] = v end end
                d.pillFont = next(font) and font or nil
                Refresh()
            end })
        L:Add(fp, 8)
        L:Desc("The size is the map-only look's (the panel keeps its own small sizes); the "
            .. "font, outline and shadow are both looks'.")
        -- how the coordinates read (minimap.formats.coords; nothing saved = 42.1, 65.3)
        local ML = ns.MinimapLook
        if ML and ML.CoordsText then
            local fg, fs = ns.CustomAccess(DB, "formats", "coords", Refresh)
            L:Add(UI.TextFormatPicker(L.current, { label = "Coordinates", width = UI.CardInnerWidth(L),
                get = fg, set = fs, defaults = ML.COORD_DEFAULTS, kinds = { percent = true },
                tokens = { { token = "x", label = "across" }, { token = "y", label = "down" } },
                sample = function() return ML.CoordsText(0.421, 0.653) end }), 6)
        end
        L:EndCard()

        -- the panel look's texts, freely (ZacUIDB.minimap.anchors.<panel...>):
        -- any point of the map, the header, the footer or another text
        if ML and ML.PANEL_TEXTS then
            L:Card("Panel texts (panel look)")
            ZacUIDB.config = ZacUIDB.config or {}
            local function Which()
                local v = ZacUIDB.config.mmText
                return ML.PANEL_HOST_LABELS[v] and v or "panelZone"
            end
            local which = Which()
            L:Add(UI.Field(L.current, "Text", function(h)
                return UI.Dropdown(h, { width = 200,
                    items = function()
                        local out = {}
                        for _, k in ipairs(ML.PANEL_TEXTS) do out[#out + 1] = { text = ML.PANEL_LABELS[k], value = k } end
                        return out
                    end,
                    selected = function() return ML.PANEL_LABELS[Which()] end,
                    selectedValue = Which,
                    onSelect = function(v) ZacUIDB.config.mmText = v ns.RefreshConfig() end })
            end, { width = 200 }), 8)
            local targets = { { value = "map", text = ML.PANEL_LABELS.map },
                { value = "header", text = ML.PANEL_LABELS.header }, { value = "footer", text = ML.PANEL_LABELS.footer } }
            for _, k in ipairs(ML.PANEL_TEXTS) do
                if k ~= which then targets[#targets + 1] = { value = k, text = ML.PANEL_LABELS[k] } end
            end
            local get, set = ns.CustomAccess(function() return MM.DB() end, "anchors", which, Refresh)
            UI.TextElement(L, { key = "minimap." .. which, anchorGet = get, anchorSet = set, targets = targets,
                anchorDefaults = function() return ML.PanelDefault(which) end,
                defaultTargetLabel = ML.PANEL_HOST_LABELS[which], anchorMin = -150, anchorMax = 150,
                width = UI.CardInnerWidth(L) })
            L:Desc("Only on the panel look (Look tab); the map-only look keeps its pills.")
            L:EndCard()
        end

        L:Card("Group names")
        Bind(L, "slider", "groupNameSize", "Name size", nil, { min = 6, max = 14, step = 1 })
        L:EndCard()
    end

    local function Tab_anim(L)
        L:Card("On mouseover")
        Bind(L, "slider", "fadeTime", "Fade time", nil, {
            min = 0, max = 100, step = 5,
            get = function(v) return math.floor((v or 0.2) * 100 + 0.5) end,
            set = function(v) return v / 100 end,
            format = function(v) return string.format("%.2f s", v / 100) end,
        })
        L:Desc("How long the pieces that wait for the mouse take to fade in and out. "
            .. "Zero is instant. Replay in the preview plays it.")
        L:EndCard()
    end

    local function Tab_pos(L)
        L:Card("Where things go (map only)")
        L:Desc("Pieces at the same spot stack inward from the edge. A corner "
            .. "spot moves along the edge while Blizzard's icon for that "
            .. "corner (mail, tracking, group finder, battleground) is up.")
        local SPOT_ITEMS = {
            { text = "Top left", value = "TOPLEFT" },
            { text = "Top", value = "TOP" },
            { text = "Top right", value = "TOPRIGHT" },
            { text = "Bottom left", value = "BOTTOMLEFT" },
            { text = "Bottom", value = "BOTTOM" },
            { text = "Bottom right", value = "BOTTOMRIGHT" },
        }
        Bind(L, "dropdown", "zonePos", "Zone name", nil, { items = SPOT_ITEMS })
        Bind(L, "dropdown", "clockPos", "Clock", nil, { items = SPOT_ITEMS })
        Bind(L, "dropdown", "coordsPos", "Coordinates", nil, { items = SPOT_ITEMS })
        Bind(L, "dropdown", "friendsPos", "Friends", nil, { items = SPOT_ITEMS })
        Bind(L, "dropdown", "guildPos", "Guild", nil, { items = SPOT_ITEMS })
        if Kit then
            Kit.Slider(L, "Gap from the edge", DB, "pillPad", { min = 0, max = 20, step = 1,
                get = function(v) return v or 4 end, after = Refresh,
                format = function(v) return v .. " px" end })
            Kit.Slider(L, "Gap between pills", DB, "pillGap", { min = 0, max = 12, step = 1,
                get = function(v) return v or 2 end, after = Refresh,
                format = function(v) return v .. " px" end })
        end
        L:EndCard()

        -- every piece, freely: any point of the map or of another piece
        -- (ZacUIDB.minimap.anchors.<piece>), on top of its spot above
        local ML = ns.MinimapLook
        if ML and ML.PIECES then
            L:Card("Fine placement (map only)")
            ZacUIDB.config = ZacUIDB.config or {}
            local function Piece()
                local v = ZacUIDB.config.mmPiece
                return ML.PIECE_KEYS[v] and v or "zone"
            end
            local piece = Piece()
            local pdd = UI.Field(L.current, "Piece", function(h)
                return UI.Dropdown(h, { width = 200,
                    items = function()
                        local out = {}
                        for _, k in ipairs(ML.PIECES) do out[#out + 1] = { text = ML.PIECE_LABELS[k], value = k } end
                        return out
                    end,
                    selected = function() return ML.PIECE_LABELS[Piece()] end,
                    selectedValue = Piece,
                    onSelect = function(v) ZacUIDB.config.mmPiece = v ns.RefreshConfig() end })
            end, { width = 200 })
            L:Add(pdd, 8)
            local targets = { { value = "map", text = ML.PIECE_LABELS.map } }
            for _, k in ipairs(ML.PIECES) do
                if k ~= piece then targets[#targets + 1] = { value = k, text = ML.PIECE_LABELS[k] } end
            end
            local get, set = ns.CustomAccess(function() return MM.DB() end, "anchors", piece, Refresh)
            UI.TextElement(L, { key = "minimap." .. piece, anchorGet = get, anchorSet = set, targets = targets,
                anchorDefaults = function() return ML.PillDefault(ML.PIECE_KEYS[piece]) end,
                defaultTargetLabel = "The map", anchorMin = -150, anchorMax = 150 })
            L:Desc("A placed piece leaves the stack at its spot. Reset puts it back in it.")
            L:EndCard()
        end

        -- Blizzard's corner icons, freely (ZacUIDB.minimap.anchors.<icon>)
        if ML and ML.ICONS then
            L:Card("Corner icons")
            ZacUIDB.config = ZacUIDB.config or {}
            local function Icon()
                local v = ZacUIDB.config.mmIcon
                return (ML.ICON_LABELS[v] and v ~= "map") and v or "mail"
            end
            local icon = Icon()
            L:Add(UI.Field(L.current, "Icon", function(h)
                return UI.Dropdown(h, { width = 200,
                    items = function()
                        local out = {}
                        for _, k in ipairs(ML.ICONS) do out[#out + 1] = { text = ML.ICON_LABELS[k], value = k } end
                        return out
                    end,
                    selected = function() return ML.ICON_LABELS[Icon()] end,
                    selectedValue = Icon,
                    onSelect = function(v) ZacUIDB.config.mmIcon = v ns.RefreshConfig() end })
            end, { width = 200 }), 8)
            local targets = { { value = "map", text = ML.ICON_LABELS.map } }
            for _, k in ipairs(ML.ICONS) do
                if k ~= icon then targets[#targets + 1] = { value = k, text = ML.ICON_LABELS[k] } end
            end
            local get, set = ns.CustomAccess(function() return MM.DB() end, "anchors", icon, Refresh)
            UI.FrameElement(L, { key = "minimap." .. icon, anchorGet = get, anchorSet = set, targets = targets,
                anchorDefaults = function() return ML.IconDefault(icon) end,
                defaultTargetLabel = ML.ICON_LABELS.map, anchorMin = -150, anchorMax = 150 })
            L:Desc("A placed icon leaves its corner, so the pills there stop stepping aside for it.")
            L:EndCard()
        end

        L:Card("Size and spot")
        Bind(L, "slider", "scale", "Size", nil, {
            min = 50, max = 200, step = 5,
            get = function(v) return math.floor((v or 1) * 100 + 0.5) end,
            set = function(v) return v / 100 end,
            format = function(v) return v .. "%" end,
        })
        L:Desc("Scales the whole cluster, so the zone name, clock and day "
            .. "number travel with the map rather than staying behind at the "
            .. "old size.")
        if Kit then Kit.Mover(L, "minimap", "minimap") end
        local MB = ns.MinimapButton
        if MB then
            local prow = UI.Holder(L.current)
            prow:SetSize(300, M.BUTTON_H)
            local resetPos = UI.Button(prow, "Reset ZacUI's button", { width = 150,
                tooltip = "Puts the ZacUI minimap button back at its default spot on the minimap rim.",
                onClick = function() MB.ResetPosition() end })
            resetPos:SetPoint("LEFT")
            L:Row(prow, M.BUTTON_H + 4)
        end
        L:EndCard()
    end

    local function Tab_adv(L)
        L:Card("Tools")
        L:Desc("Addon buttons around the minimap are swept into the "
            .. "button tray - see the Button tray tab.")

        local row = UI.Holder(L.current)
        row:SetSize(300, M.BUTTON_H)
        local diag = UI.Button(row, "Diagnose", { width = 90,
            tooltip = "Prints which minimap pieces this client actually has, "
                .. "and whether each one is where you asked for it. Several of "
                .. "them changed names in 11509.",
            onClick = function() MM.Diagnose() end })
        diag:SetPoint("LEFT")
        local reset = UI.Button(row, "Reset", { width = 90,
            tooltip = "Puts every option on this page back to the default.",
            onClick = function()
                ZacUIDB.minimap = nil
                MM.DB()
                MM.Refresh()
                RefreshConfig()
                Print("minimap options reset.")
            end })
        reset:SetPoint("LEFT", diag, "RIGHT", 8, 0)
        L:Row(row, M.BUTTON_H + 4)
        L:EndCard()
    end

    L:Tabs({
        { id = "general", label = "General",   build = Tab_general },
        { id = "look",    label = "Look",      build = Tab_look },
        { id = "text",    label = "Text",      build = Tab_text },
        { id = "anim",    label = "Animation", build = Tab_anim },
        { id = "pos",     label = "Position",  build = Tab_pos },
        { id = "adv",     label = "Advanced",  build = Tab_adv },
        -- the button tray page, as a tab here rather than a row of its own
        -- (its id is what the old "tray" page id opens)
        { id = "tray", label = "Button tray", build = function(TL)
            local page = ns.ConfigPages and ns.ConfigPages["Tray"]
            if page then
                TL.asTab = true
                page(TL)
            end
        end },
    })
end)
