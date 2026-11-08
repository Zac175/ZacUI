-- ============================================================================
-- Zacui_UnitFrames - Kit.lua
-- The game looks on ZacUI's own unit frames (2026-11-08, Zac: "even on era
-- the classic mode is just wrong for player and target frames"). Under
-- Classic WoW UI, Blizzard style and WoW Forever the player, target,
-- target-of-target, pet and focus frames wear the game's own frame
-- art, drawn by these frames: the frame sheet, a round portrait in its
-- ring, the bars in the art's tracks in Blizzard's bar texture, the name
-- where the art has its name, the level in the level circle, the rest and
-- combat icons in it on your own frame, the target's name plaque in its
-- reaction colour and its elite / rare / boss art. ZacUI's features on the
-- frames keep working (heals, auras, glows, click casting, the cast bar,
-- move mode); only the box, the bars' places and the art change. Under
-- ZacUI's look nothing here runs past one table read.
--
-- The kits: geometry and art names are the reference UI's measurements
-- (EllesmereUI's stock styles - numbers and Blizzard's own file / atlas
-- names reused, no code; zui_tests/GAMELOOK_STUDY_1108.md has each with
-- its file:line):
--   classic   the vanilla sheets by path (Interface\TargetingFrame\...),
--             every client: Era, TBC, Forever and Retail ship them
--   blizzard  the modern client's atlases (UI-HUD-UnitFrame-*), used only
--             where C_Texture.GetAtlasInfo knows them; a frame whose art
--             the client lacks wears the classic kit
--   forever   the blizzard kit with Forever's own fits and its round level
--             badge (UI-HUD-UnitFrame-SmallCircle)
-- Party, raid, tank and boss frames keep ZacUI's layout in the look's bar
-- texture and border (the reference draws no kit for party / raid either).
--
-- Wired like Portrait.lua: StyleElements is wrapped (this file loads after
-- Portrait.lua, so the kit pass runs last), the frame's colours come from
-- two wrapped colour helpers. Nothing saved is changed: the frame's own
-- width and height stay as they are and come back under ZacUI's look.
-- Latched like every look answer: a change of look is a reload.
-- ============================================================================
local ADDON, ns = ...

local K = {}
ns.Kit = K

local SHEET = "Interface\\TargetingFrame\\UI-TargetingFrame"
local STATE_ICON = "Interface\\CharacterFrame\\UI-StateIcon"
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local CAST_BORDER = "Interface\\CastingBar\\UI-CastingBar-Border"

-- ----------------------------------------------------------------------------
-- THE KITS (sizes at 1x; x / y from the frame box's top-left, y down)
-- ----------------------------------------------------------------------------
local CLASSIC = {
    id = "classic", artAbove = true,
    player = {
        w = 232, h = 100, hit = { 21, 19, 12, 15 },
        art = { file = SHEET, l = 1, r = 0.1015625, t = 0.0078125, b = 0.78125, w = 230, h = 99, x = -18.5, y = -4 },
        back = { x = 89.5, y = 26, w = 119, h = 41 },
        portrait = { point = "TOPLEFT", x = 24, y = -16, size = 64 },
        health = { x = 90, y = 45, w = 119, h = 12 },
        power  = { x = 90, y = 56, w = 119, h = 12 },
        name   = { point = "CENTER", x = 34, y = 15, w = 100, justify = "CENTER" },
        level  = { point = "CENTER", relPoint = "BOTTOMLEFT", x = 36, y = 30.5 },
    },
    target = {
        w = 232, h = 100, hit = { 19, 21, 12, 15 },
        art = { file = SHEET, l = 0.1015625, r = 1, t = 0.0078125, b = 0.78125, w = 230, h = 99, x = 18.5, y = -4 },
        artByClass = {
            elite     = SHEET .. "-Elite",
            rareelite = SHEET .. "-Rare-Elite",
            rare      = SHEET .. "-Rare",
            worldboss = "Interface\\TargetingFrame\\UI-UnitFrame-Boss",
        },
        back = { x = 23.5, y = 26, w = 119, h = 41 },
        portrait = { point = "TOPRIGHT", x = -24, y = -16, size = 64 },
        health = { x = 23, y = 45, w = 119, h = 12 },
        power  = { x = 23, y = 56, w = 119, h = 12 },
        plaque = { file = "Interface\\TargetingFrame\\UI-TargetingFrame-LevelBackground", point = "TOPRIGHT", x = -90, y = -26, w = 119, h = 19 },
        name   = { point = "CENTER", x = -34, y = 15, w = 100, justify = "CENTER" },
        level  = { point = "CENTER", relPoint = "BOTTOMRIGHT", x = -36, y = 30.5 },
    },
    mini = {
        w = 93, h = 45, hit = { 0, 0, 0, 0 },
        art = { file = "Interface\\TargetingFrame\\UI-TargetofTargetFrame", l = 0.015625, r = 0.7265625, t = 0, b = 0.703125, w = 93, h = 45, x = 0, y = 0 },
        back = { x = 42, y = 17, w = 46, h = 15 },
        portrait = { point = "TOPLEFT", x = 6, y = -6, size = 35 },
        health = { x = 45, y = 15, w = 46, h = 7 },
        power  = { x = 45, y = 23, w = 46, h = 7 },
        name   = { point = "TOPLEFT", x = 42, y = -33, w = 49, justify = "LEFT" },
    },
    pet = {
        w = 128, h = 53, hit = { 7, 10, 6, 7 },
        art = { file = "Interface\\TargetingFrame\\UI-SmallTargetingFrame", l = 0, r = 1, t = 0, b = 1, w = 128, h = 64, point = "TOPLEFT", x = 0, y = -2 },
        portrait = { point = "TOPLEFT", x = 7, y = -6, size = 37 },
        health = { x = 47, y = 22, w = 69, h = 8 },
        power  = { x = 47, y = 29, w = 69, h = 8 },
        name   = { point = "TOPLEFT", x = 50, y = -9, w = 70, justify = "LEFT" },
    },
}

local BLIZZARD = {
    id = "blizzard", artAbove = false,
    player = {
        w = 232, h = 100, hit = { 6, 0, 4, 9 },
        atlas = "UI-HUD-UnitFrame-Player-PortraitOn",
        portrait = { point = "TOPLEFT", x = 24, y = -19, size = 60, mask = "UI-HUD-UnitFrame-Player-Portrait-Mask" },
        health = { x = 85, y = 40, w = 124, h = 20, mask = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health-Mask", mx = -2, my = 6 },
        power  = { x = 85, y = 61, w = 124, h = 10, mask = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana-Mask", mx = -2, my = 2 },
        name   = { point = "TOPLEFT", x = 88, y = -27, w = 96, justify = "LEFT" },
        level  = { point = "TOPRIGHT", x = -24.5, y = -28, justify = "RIGHT" },
    },
    target = {
        w = 232, h = 100, hit = { 0, 5, 4, 9 },
        atlas = "UI-HUD-UnitFrame-Target-PortraitOn",
        atlasRare = "UI-HUD-UnitFrame-Target-Rare-PortraitOn",
        portrait = { point = "TOPRIGHT", x = -26, y = -19, size = 58, mask = "CircleMask" },
        health = { x = 23, y = 40, w = 126, h = 20, mask = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health-Mask", mx = -1, my = 6 },
        power  = { x = 23, y = 61, w = 134, h = 10, mask = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Mana-Mask", mx = -61, my = 3 },
        strip  = { atlas = "UI-HUD-UnitFrame-Target-PortraitOn-Type", point = "TOPRIGHT", x = -75, y = -25 },
        name   = { point = "TOPLEFT", x = 30, y = -26, w = 94, justify = "LEFT" },
        level  = { point = "TOPRIGHT", x = -91, y = -27, justify = "RIGHT" },
    },
    mini = {
        w = 120, h = 49, hit = { 0, 0, 0, 0 },
        atlas = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn",
        portrait = { point = "TOPLEFT", x = 5, y = -5, size = 37, mask = "CircleMask" },
        health = { x = 44, y = 17, w = 70, h = 10, mask = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health-Mask", mx = -29, my = 3 },
        power  = { x = 40, y = 28, w = 74, h = 7, mask = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Mana-Mask", mx = -27, my = 4 },
        name   = { point = "TOPLEFT", x = 44, y = -5, w = 68, justify = "LEFT" },
    },
}

-- WoW Forever: Blizzard style's frames with Forever's own fits (each bar in
-- the rect inside the bronze rim), the names centred on their strips and
-- the level in a round badge at the frame's bottom corner.
local function Copy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = Copy(v) end
    return o
end
local FOREVER = Copy(BLIZZARD)
FOREVER.id = "forever"
do
    local P, T, M = FOREVER.player, FOREVER.target, FOREVER.mini
    local CIRCLE = "UI-HUD-UnitFrame-SmallCircle"
    P.health.x, P.health.y, P.health.w, P.health.h = 88, 45.5, 123, 15
    P.power.x, P.power.y, P.power.w, P.power.h = 88, 61.5, 123, 10
    P.health.mask, P.power.mask = nil, nil
    P.name = { point = "CENTER", x = 33, y = 13, w = 116, justify = "CENTER" }
    P.badge = { point = "BOTTOMLEFT", x = 13, y = 7, size = 39, atlas = CIRCLE }
    P.level = { point = "CENTER", x = 0, y = -0.5, justify = "CENTER", onBadge = true }
    T.health.x, T.health.y, T.health.w, T.health.h = 22, 44, 123, 15
    T.power.x, T.power.y, T.power.w, T.power.h = 22, 60, 123, 10
    T.health.mask, T.power.mask = nil, nil
    T.strip.x, T.strip.y = -82, -26
    T.badge = { point = "BOTTOMRIGHT", x = -13, y = 7, size = 39, atlas = CIRCLE }
    T.level = { point = "CENTER", x = 0, y = -0.5, justify = "CENTER", onBadge = true }
    T.name = { point = "TOPLEFT", x = 24, y = -30, w = 117, justify = "CENTER" }
    M.health.x, M.health.y, M.health.w, M.health.h = 45, 18, 70, 11
    M.power.x, M.power.y, M.power.w, M.power.h = 45, 30, 70, 7
    M.health.mask, M.power.mask = nil, nil
    M.name = { point = "TOPLEFT", x = 44, y = -6, w = 68, justify = "CENTER" }
end

K.KITS = { classic = CLASSIC, blizzard = BLIZZARD, forever = FOREVER }
-- the Style page's look cards draw their miniature player frame from these
-- (Core_Look's Look.Preview), so a card shows the kit the frames will wear
do
    local Z = _G.ZacUI
    if type(Z) == "table" then Z.UFKit = K end
end

-- ----------------------------------------------------------------------------
-- What draws: the look's kit, and a frame's kind in it
-- ----------------------------------------------------------------------------
local function AtlasOK(name)
    local CT = _G.C_Texture
    if not (name and CT and CT.GetAtlasInfo) then return false end
    local ok, info = pcall(CT.GetAtlasInfo, name)
    return ok and info and true or false
end
K.AtlasOK = AtlasOK

local function LookNow()
    local Z = _G.ZacUI
    local L = Z and Z.Look
    if not (L and L.For) then return nil end
    local ok, look = pcall(L.For, "unitframes")
    return ok and type(look) == "table" and look or nil
end

-- the kit this look draws, nil under ZacUI's own look
function K.Active()
    local look = LookNow()
    if not look or look.id == "zacui" then return nil end
    return K.KITS[look.id] or CLASSIC, look
end

-- frame key -> kind. (The boss frames keep ZacUI's layout in the look's
-- bar texture: five of them stack by their own height and spacing, which
-- the kit's 100-tall box would overlap.)
local KIND = {
    player = "player", target = "target", focus = "target", softtarget = "target",
    targettarget = "mini", focustarget = "mini", pet = "pet",
}
-- which frame key a cfg belongs to (a live frame's, a preview sample's: the
-- table itself or a proxy over it)
local function KeyOf(frame)
    local cfg = frame and frame.cfg
    local frames = ns.db and ns.db.frames
    if not (cfg and frames) then return nil end
    for k, c in pairs(frames) do
        if c == cfg then return k end
    end
    local mt = getmetatable(cfg)
    local base = mt and type(mt.__index) == "table" and mt.__index
    if base then
        for k, c in pairs(frames) do if c == base then return k end end
    end
    return rawget(cfg, "_key")
end

-- the kit and the geometry for this frame, or nil
function K.For(frame)
    if not frame or frame.isGroupUnit then return nil end
    local kit, look = K.Active()
    if not kit then return nil end
    local key = KeyOf(frame)
    if not key and frame.unit then key = frame.unit end
    local own = key and KIND[key]
    if not own then return nil end
    -- (a kit without pet art draws the pet on its small frame)
    local kind = (own == "pet" and not kit.pet) and "mini" or own
    local G = kit[kind]
    -- a modern kit whose art this client lacks: the classic kit, whole
    if G and G.atlas and not AtlasOK(G.atlas) then
        kit, kind = CLASSIC, own
        G = CLASSIC[kind]
    end
    return G, kit, kind, look
end

-- ----------------------------------------------------------------------------
-- BLIZZARD STYLE ON WOW FOREVER (2026-11-08, Zac: "the player frame looks
-- kinda weird"). Forever redrew the retail unit frame atlases under the
-- same names (its bronze art), so SetAtlas there drew Forever's frame round
-- Blizzard style's geometry. The retail sheets still ship with that client:
-- where a name's own atlas resolves to another file and the retail file is
-- present, the retail member is painted from its sheet (file + texcoords),
-- as the reference does (its records of those boxes and file ids, reused:
-- EllesmereUI_RetailAtlas.lua ROWS / MASK_FILES). Retail draws them natively.
-- ----------------------------------------------------------------------------
local UF1 = { 4631591, "Interface\\HUD\\UIUnitFrame", 1024, 512 }
local UF2 = { 4642466, "Interface\\HUD\\UIUnitFrame2x", 2048, 1024 }
local RETAIL = {   -- name: 1x box (l, r, t, b), 2x box
    ["ui-hud-unitframe-player-portraiton"]         = { 1, 199, 87, 158, 1, 397, 171, 313 },
    ["ui-hud-unitframe-target-portraiton"]         = { 1, 193, 229, 296, 1, 385, 451, 585 },
    ["ui-hud-unitframe-target-rare-portraiton"]    = { 1, 193, 298, 365, 1, 385, 587, 721 },
    ["ui-hud-unitframe-targetoftarget-portraiton"] = { 330, 450, 160, 209, 1113, 1353, 315, 413 },
    ["ui-hud-unitframe-target-portraiton-type"]    = { 311, 446, 260, 278, 887, 1157, 461, 497 },
}
local RETAIL_MASK = {   -- name: 1x path, its id, 2x path, its id, width, height
    ["ui-hud-unitframe-player-portraiton-bar-health-mask"] = { "Interface\\HUD\\UIUnitFramePlayerHealthMask", 4697851, "Interface\\HUD\\UIUnitFramePlayerHealthMask2x", 5321215, 128, 32 },
    ["ui-hud-unitframe-player-portraiton-bar-mana-mask"]   = { "Interface\\HUD\\UIUnitFramePlayerManaMask", 4697854, "Interface\\HUD\\UIUnitFramePlayerManaMask2x", 5321218, 128, 16 },
    ["ui-hud-unitframe-target-portraiton-bar-health-mask"] = { "Interface\\HUD\\UIUnitFrameTargetHealthMask", 4680792, "Interface\\HUD\\UIUnitFrameTargetHealthMask2x", 5321212, 128, 32 },
    ["ui-hud-unitframe-target-portraiton-bar-mana-mask"]   = { "Interface\\HUD\\UIUnitFrameTargetManaMask", 4680795, "Interface\\HUD\\UIUnitFrameTargetManaMask2x", 5321221, 256, 16 },
    ["ui-hud-unitframe-player-portrait-mask"]              = { "Interface\\HUD\\UIUnitFramePlayerPortraitMask", 4682541, "Interface\\HUD\\UIUnitFramePlayerPortraitMask2x", 5321198, 64, 64 },
}
local function FileHere(path, id)
    local f = _G.GetFileIDFromPath
    if type(f) ~= "function" then return false end
    local ok, got = pcall(f, path)
    return ok and got == id
end
local function NativeFile(name)
    local CT = _G.C_Texture
    if not (CT and CT.GetAtlasInfo) then return nil end
    local ok, info = pcall(CT.GetAtlasInfo, name)
    return ok and type(info) == "table" and (info.file or info.filename) or nil
end
-- name -> { path, l, r, t, b, w, h } of the retail member, or false (native)
local retailMemo = {}
local function Retail(name)
    local key = type(name) == "string" and name:lower()
    local e = key and retailMemo[key]
    if e ~= nil then return e end
    e = false
    local row = key and RETAIL[key]
    local nf = row and NativeFile(name)
    if row and nf ~= UF1[1] and nf ~= UF2[1] then
        local w, h = row[2] - row[1], row[4] - row[3]
        if FileHere(UF2[2], UF2[1]) then
            e = { UF2[2], row[5] / UF2[3], row[6] / UF2[3], row[7] / UF2[4], row[8] / UF2[4], w, h }
        elseif FileHere(UF1[2], UF1[1]) then
            e = { UF1[2], row[1] / UF1[3], row[2] / UF1[3], row[3] / UF1[4], row[4] / UF1[4], w, h }
        end
    end
    retailMemo[key or ""] = e
    return e
end
local maskMemo = {}
local function RetailMask(name)
    local key = type(name) == "string" and name:lower()
    local e = key and maskMemo[key]
    if e ~= nil then return e end
    e = false
    local row = key and RETAIL_MASK[key]
    local nf = row and NativeFile(name)
    if row and nf ~= row[2] and nf ~= row[4] then
        if FileHere(row[3], row[4]) then e = { row[3], row[5], row[6] }
        elseif FileHere(row[1], row[2]) then e = { row[1], row[5], row[6] } end
    end
    maskMemo[key or ""] = e
    return e
end

-- The kit's art on a texture: under Blizzard style the retail member where
-- the client drew another art under that name, else the client's atlas.
-- useSize: the art's own size. (Plain textures only.)
function K.SetArt(tex, name, useSize, kitId)
    local r = kitId == "blizzard" and Retail(name)
    if r then
        tex:SetTexture(r[1])
        tex:SetTexCoord(r[2], r[3], r[4], r[5])
        if useSize then tex:SetSize(r[6], r[7]) end
        return true
    end
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetAtlas(name, useSize)
    return false
end
-- the same for a mask: the retail mask file at the atlas's size
function K.SetMask(mask, name, useSize, kitId)
    local r = kitId == "blizzard" and RetailMask(name)
    if r then
        mask:SetTexture(r[1], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        if useSize then mask:SetSize(r[2], r[3]) end
        return true
    end
    mask:SetAtlas(name, useSize)
    return false
end

-- ----------------------------------------------------------------------------
-- FRESH-INSTALL SPOTS UNDER A KIT (2026-11-08, Zac: "make sure everything
-- has good defaults for positions"). The kit's boxes are bigger than ZacUI's
-- own frames, so ZacUI's spots would crowd them. Under a game look the
-- DEFAULTS of the kitted frames are moved before InitDB fills a new save
-- from them (Core.lua, right after the match overlay): a save that already
-- holds a spot keeps it, a fresh install gets these. The HUD stays where
-- ZacUI's is (player left, target right of centre, 170 below it); the rest
-- is laid round them with the stock UI's relations and no art overlapping:
--   target-of-target  right of the target, on the target's bars (the stock
--                     frame hangs off the target's lower right; there it
--                     sat over the target's cast bar)
--   pet               under the player's cast bar
--   focus             above the target; its target right of it
-- (vis: the kit art's own transparent margin, measured by the reference)
local VIS = { classic = { player = 19.5, target = 19.5 }, modern = { player = 18, target = 20 } }
function ns.ApplyKitDefaults()
    if ns._kitDefaults ~= nil then return ns._kitDefaults end
    local kit = K.Active()
    ns._kitDefaults = kit and true or false
    if not kit then return false end
    local d = ns.defaults and ns.defaults.frames
    if type(d) ~= "table" then return false end
    -- a modern kit on a client without its art draws the classic one
    local modern = kit.player.atlas and AtlasOK(kit.player.atlas)
    local K2 = modern and kit or CLASSIC
    local mini = K2.mini
    local vis = modern and VIS.modern or VIS.classic
    local T = d.target or {}
    local tx, ty = tonumber(T.x) or 240, tonumber(T.y) or -170
    local px, py = tonumber(d.player and d.player.x) or -240, tonumber(d.player and d.player.y) or -170
    -- the target's visible right edge, 6 clear, then the small frame
    local rightOfTarget = tx + K2.target.w / 2 - vis.target + 6 + mini.w / 2
    local function Set(key, x, y)
        local c = d[key]
        if type(c) == "table" then c.point, c.x, c.y = "CENTER", math.floor(x + 0.5), math.floor(y + 0.5) end
    end
    Set("targettarget", rightOfTarget, ty - 15)
    -- the player's cast bar hangs 2 under its box (its height: the shared one)
    local cbH = (ns.defaults.castbar and tonumber(ns.defaults.castbar.height)) or 16
    local pet = K2.pet or mini
    Set("pet", px, py - K2.player.h / 2 - 2 - cbH - 6 - pet.h / 2)
    Set("focus", tx, ty + K2.target.h + 10)
    Set("focustarget", rightOfTarget, ty + K2.target.h + 10 - 15)
    return true
end

-- ----------------------------------------------------------------------------
-- THE GAME LOOKS' STOCK STYLE DEFAULTS (Core_Look's Look.FollowDefaults):
-- under a game look the unit frames' ZacUI-only style settings default to
-- what the game's own frames do; a value set by hand stays. Features (heal
-- prediction, range fade, raid class colours - Blizzard's raid frames have
-- them too - the auras, the indicators the stock frames carry) stay.
--   health / name text   the stock frames show no number on the bar
--   party health colour  Blizzard's party frames are green, names gold
--   combat / PvP icon    the kit draws the stock combat state; the PvP
--                        icon is ZacUI's red text
--   cast bar time, icon  the stock player cast bar has neither
--   smooth bars          the stock bars jump
--   dispel glow          ZacUI's glow (the stock frames have none)
-- ----------------------------------------------------------------------------
local UF_STOCK = {
    { "frames", "player", "healthText", "none" },
    { "frames", "target", "healthText", "none" },
    { "frames", "player", "combatIcon", false },
    { "frames", "player", "pvpIcon", false },
    { "party", "healthText", "none" },
    { "party", "healthClassColor", false },
    { "party", "healthColor", { 0, 1, 0, 1 } },
    { "party", "nameClassColor", false },
    { "party", "nameColor", { 1, 0.82, 0, 1 } },
    { "castbar", "showTime", false },
    { "castbar", "showIcon", false },
    { "smoothBars", false },
    { "dispelGlow", "enabled", false },
}
K.UF_STOCK = UF_STOCK
function ns.FollowLookDefaults()
    local Z = _G.ZacUI
    local L = Z and Z.Look
    if not (L and L.FollowDefaults and ns.db and ns.defaults) then return false end
    return L.FollowDefaults(ns.db, ns.defaults, UF_STOCK, "unitframes")
end

-- the frames wearing a kit, for the colours (weak; filled by Apply)
local kitCfg = setmetatable({}, { __mode = "k" })
local kitFrames = setmetatable({}, { __mode = "k" })

-- ----------------------------------------------------------------------------
-- Pieces
-- ----------------------------------------------------------------------------
local function ArtFrame(frame)
    local af = frame._zKitArt
    if af then return af end
    af = CreateFrame("Frame", nil, frame)
    af:SetAllPoints(frame)
    if af.EnableMouse then af:EnableMouse(false) end
    af.art = af:CreateTexture(nil, "BACKGROUND")
    af.plaque = af:CreateTexture(nil, "BACKGROUND", nil, -1)
    af.plaque:Hide()
    frame._zKitArt = af
    -- the plaque behind the name and both bars (classic): its own frame, under the bars
    local bf = CreateFrame("Frame", nil, frame)
    bf:SetAllPoints(frame)
    if bf.EnableMouse then bf:EnableMouse(false) end
    bf.tex = bf:CreateTexture(nil, "BACKGROUND")
    bf.tex:SetColorTexture(0, 0, 0, 0.5)
    bf:Hide()
    af.back = bf
    return af
end

-- the art on the frame: a file with its sheet coords, or an atlas
local function PaintArt(frame, G, file)
    local af = frame._zKitArt
    local art = af.art
    if G.atlas and not file then
        K.SetArt(art, G.atlas, true, frame._zKitId)
        art:ClearAllPoints()
        art:SetPoint("CENTER", frame, "CENTER", 0, 0)
        art:Show()
        return
    end
    local a = G.art
    if not a then art:Hide() return end
    art:SetTexture(file or a.file)
    art:SetTexCoord(a.l or 0, a.r or 1, a.t or 0, a.b or 1)
    art:SetSize(a.w, a.h)
    art:ClearAllPoints()
    local p = a.point or "CENTER"
    art:SetPoint(p, frame, p, a.x or 0, a.y or 0)
    art:Show()
end

local function Bar(frame, bar, B, tex)
    if not (bar and B) then return end
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", B.x, -B.y)
    bar:SetSize(B.w, B.h)
    bar:SetStatusBarTexture(tex)
    if bar.bg then
        bar.bg:ClearAllPoints()
        bar.bg:SetAllPoints(bar)
        bar.bg:SetTexture(tex)
        bar.bg:SetVertexColor(0, 0, 0, 0)
    end
    -- the track's rounded ends (a modern kit's mask, where the client has it)
    local fill = bar:GetStatusBarTexture()
    if B.mask and AtlasOK(B.mask) and bar.CreateMaskTexture and type(fill) == "table" and fill.AddMaskTexture then
        local m = bar._zKitMask
        if not m then
            m = bar:CreateMaskTexture()
            bar._zKitMask = m
        end
        K.SetMask(m, B.mask, true, frame._zKitId)
        m:ClearAllPoints()
        m:SetPoint("TOPLEFT", bar, "TOPLEFT", B.mx or 0, B.my or 0)
        if not bar._zKitMasked then pcall(fill.AddMaskTexture, fill, m) bar._zKitMasked = fill end
    end
end

local function Unmask(bar)
    local m, fill = bar and bar._zKitMask, bar and bar._zKitMasked
    if m and fill and fill.RemoveMaskTexture then pcall(fill.RemoveMaskTexture, fill, m) end
    if bar then bar._zKitMasked = nil end
end

-- the round portrait in the art's ring, always on under a kit
local function Portrait(frame, G, kit)
    local p = frame.Portrait
    local P = G.portrait
    if not (p and P) then return end
    p:ClearAllPoints()
    p:SetPoint(P.point, frame, P.point, P.x, P.y)
    p:SetSize(P.size, P.size)
    if p.SetBackdrop then pcall(p.SetBackdrop, p, nil) end
    if p.tex then
        p.tex:ClearAllPoints()
        p.tex:SetAllPoints(p)
    end
    -- the classic ring sits in the art, which draws over the face; the
    -- modern art draws under the bars and over the face as well
    p:SetFrameLevel(frame:GetFrameLevel() + (kit.artAbove and 3 or 1))
    if p._lookMask then
        if P.mask and AtlasOK(P.mask) then K.SetMask(p._lookMask, P.mask, false, kit.id)
        else p._lookMask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") end
    end
    -- (the kit draws the level itself)
    if p._lookBadge then p._lookBadge:Hide() end
    if p._lookLevel then p._lookLevel:Hide() end
    p._badgeOn = nil
    if p._lookRing then p._lookRing:Hide() end
    p:Show()
end

-- the level: in the art's circle, gold; the creature's difficulty colour on
-- something you can attack; a skull for a level the game will not tell.
-- Your own frame shows the rest / combat icon in the circle instead, as
-- the game's does.
local function LevelHost(frame)
    local h = frame._zKitLevel
    if h then return h end
    local host = CreateFrame("Frame", nil, frame)
    host:SetAllPoints(frame)
    if host.EnableMouse then host:EnableMouse(false) end
    host:SetFrameLevel(frame:GetFrameLevel() + 7)
    h = { host = host }
    h.fs = host:CreateFontString(nil, "OVERLAY")
    if not pcall(h.fs.SetFontObject, h.fs, "GameNormalNumberFont") then
        h.fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 11, "")
    end
    rawset(h.fs, "_zOwnFace", true)   -- the game's number font on purpose
    h.skull = host:CreateTexture(nil, "OVERLAY", nil, 1)
    h.skull:SetTexture(SKULL)
    h.skull:SetSize(16, 16)
    h.skull:Hide()
    h.state = host:CreateTexture(nil, "OVERLAY", nil, 2)
    h.state:SetTexture(STATE_ICON)
    h.state:SetSize(26, 26)
    h.state:Hide()
    h.badge = host:CreateTexture(nil, "OVERLAY", nil, -1)
    h.badge:Hide()
    frame._zKitLevel = h
    return h
end

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end

function K.RefreshLevel(frame)
    local h = frame and frame._zKitLevel
    if not (h and frame._zKitOn) then return end
    local unit = frame.unit
    local fs, skull, state = h.fs, h.skull, h.state
    state:Hide()
    skull:Hide()
    if not unit then
        -- a sample: your level (or a stand-in)
        local lv = UnitLevel and UnitLevel("player")
        fs:SetText((type(lv) == "number" and lv > 0) and lv or 60)
        fs:SetTextColor(1, 0.82, 0)
        fs:Show()
        return
    end
    if not (UnitExists and UnitExists(unit)) then fs:SetText("") return end
    -- your own frame: resting / in combat, in the circle (the game's way)
    if unit == "player" and frame._zKitKind == "player" then
        local fighting = UnitAffectingCombat and UnitAffectingCombat("player")
        if not Secret(fighting) and fighting then
            state:SetTexCoord(0.5, 1, 0, 0.484375)
            state:Show() fs:Hide() return
        elseif IsResting and IsResting() then
            state:SetTexCoord(0, 0.5, 0, 0.421875)
            state:Show() fs:Hide() return
        end
    end
    local lv = UnitLevel(unit)
    fs:Show()
    if Secret(lv) then
        -- (a hidden value is shown, never compared)
        fs:SetText(lv)
        fs:SetTextColor(1, 0.82, 0)
        return
    end
    if type(lv) ~= "number" or lv <= 0 then
        fs:SetText("")
        skull:Show()
        return
    end
    fs:SetText(lv)
    local attack = UnitCanAttack and UnitCanAttack("player", unit)
    if not Secret(attack) and attack then
        local c = (GetCreatureDifficultyColor and GetCreatureDifficultyColor(lv))
            or (GetQuestDifficultyColor and GetQuestDifficultyColor(lv))
        if type(c) == "table" and c.r then fs:SetTextColor(c.r, c.g, c.b) return end
    end
    fs:SetTextColor(1, 0.82, 0)
end

local function Level(frame, G)
    local L = G.level
    local h = frame._zKitLevel
    if not L then
        if h then h.fs:Hide() h.skull:Hide() h.state:Hide() h.badge:Hide() end
        return
    end
    h = LevelHost(frame)
    local rel = frame
    local B = G.badge
    if B and AtlasOK(B.atlas) then
        h.badge:SetAtlas(B.atlas)
        h.badge:SetSize(B.size, B.size)
        h.badge:ClearAllPoints()
        h.badge:SetPoint(B.point, frame, B.point, B.x, B.y)
        h.badge:Show()
        rel = h.badge
    else
        h.badge:Hide()
    end
    local relPoint = (L.onBadge and rel ~= frame) and "CENTER" or (L.relPoint or L.point)
    h.fs:ClearAllPoints()
    h.fs:SetPoint(L.point, rel, relPoint, L.x, L.y)
    if L.justify and h.fs.SetJustifyH then h.fs:SetJustifyH(L.justify) end
    for _, t in ipairs({ h.skull, h.state }) do
        t:ClearAllPoints()
        t:SetPoint("CENTER", h.fs, "CENTER", 0, 0)
    end
    -- the level's spot is a centre for the classic circle
    if L.point == "CENTER" then
        h.skull:ClearAllPoints()
        h.skull:SetPoint("CENTER", rel, relPoint, L.x, L.y + 1)
        h.state:ClearAllPoints()
        h.state:SetPoint("CENTER", rel, relPoint, L.x, L.y + 1)
    end
    K.RefreshLevel(frame)
end

-- the target's art that follows the unit: the elite / rare / boss sheet
-- (classic) or the rare art (modern), and the name plaque in the unit's
-- reaction colour
function K.RefreshTarget(frame)
    local G = frame and frame._zKitGeom
    if not (G and frame._zKitOn and frame._zKitKind == "target") then return end
    local unit = frame.unit
    local cls = unit and UnitExists and UnitExists(unit) and UnitClassification and UnitClassification(unit)
    if Secret(cls) then cls = nil end
    if G.artByClass then
        PaintArt(frame, G, cls and G.artByClass[cls] or nil)
    elseif G.atlasRare and (cls == "rare" or cls == "rareelite") and AtlasOK(G.atlasRare) then
        local art = frame._zKitArt.art
        K.SetArt(art, G.atlasRare, true, frame._zKitId)
    elseif G.atlas then
        PaintArt(frame, G)
    end
    local pl = frame._zKitArt and frame._zKitArt.plaque
    if pl and pl:IsShown() then
        local r, g, b = 0.5, 0.5, 0.5
        if unit and UnitExists and UnitExists(unit) and UnitSelectionColor then
            local rr, gg, bb = UnitSelectionColor(unit)
            if not Secret(rr) and type(rr) == "number" then r, g, b = rr, gg, bb end
        elseif not unit then
            r, g, b = 1, 0, 0
        end
        pl:SetVertexColor(r, g, b, 1)
    end
end

-- one listener for every kitted frame, made with the first
local events
local function Events()
    if events then return end
    events = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP",
        "UNIT_LEVEL", "UNIT_FACTION", "UNIT_CLASSIFICATION_CHANGED", "PLAYER_UPDATE_RESTING",
        "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_PET", "INSTANCE_ENCOUNTER_ENGAGE_UNIT" }) do
        pcall(events.RegisterEvent, events, e)
    end
    events:SetScript("OnEvent", function()
        for f in pairs(kitFrames) do
            if f._zKitOn and f.unit then
                K.RefreshLevel(f)
                K.RefreshTarget(f)
            end
        end
    end)
end

-- the classic cast bar frame round ZacUI's cast bar: the 256 x 64 sheet cut
-- at columns 16 | 48 | 208 | 240 and rows 16 | 28 | 37 | 48, caps and rims
-- at the sheet's own size, the window band stretched to the bar (the
-- reference's measurements)
local CX = { 16 / 256, 48 / 256, 208 / 256, 240 / 256 }
local CY = { 16 / 64, 28 / 64, 37 / 64, 48 / 64 }
local CAP, TOP, BOT, REACH = 32, 12, 11, 14.5
-- each piece by its two corners on the bar: { relPoint, x, y } for its
-- top-left and its bottom-right
local COLS = {   -- the top-left's side and x, the bottom-right's side and x
    { "LEFT", -REACH, "LEFT", CAP - REACH },              -- the left cap
    { "LEFT", CAP - REACH, "RIGHT", REACH - CAP },        -- the middle
    { "RIGHT", REACH - CAP, "RIGHT", REACH },             -- the right cap
}
local ROWS = {   -- the top-left's side and y, the bottom-right's side and y
    { "TOP", TOP, "TOP", 0 },                             -- the top band
    { "TOP", 0, "BOTTOM", 0 },                            -- the window
    { "BOTTOM", 0, "BOTTOM", -BOT },                      -- the bottom band
}
local function CastFrame(cb, on)
    local pieces = cb._zKitCast
    if not on then
        if pieces then for _, t in ipairs(pieces) do t:Hide() end end
        return
    end
    if not pieces then
        pieces = {}
        for i = 1, 9 do
            local t = cb:CreateTexture(nil, "OVERLAY", nil, 2)
            t:SetTexture(CAST_BORDER)
            pieces[i] = t
        end
        cb._zKitCast = pieces
    end
    local i = 0
    for r, R in ipairs(ROWS) do
        for c, C in ipairs(COLS) do
            i = i + 1
            local t = pieces[i]
            t:SetTexCoord(CX[c], CX[c + 1], CY[r], CY[r + 1])
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", cb, R[1] .. C[1], C[2], R[2])
            t:SetPoint("BOTTOMRIGHT", cb, R[3] .. C[3], C[4], R[4])
            t:Show()
        end
    end
end

-- ----------------------------------------------------------------------------
-- THE PASS (after StyleElements and the portrait)
-- ----------------------------------------------------------------------------
local function Off(frame)
    if not frame._zKitOn then return end
    frame._zKitOn = nil
    kitCfg[frame.cfg or false] = nil
    local af = frame._zKitArt
    if af then af:Hide() af.back:Hide() end
    local h = frame._zKitLevel
    if h then h.host:Hide() end
    Unmask(frame.Health)
    Unmask(frame.Power)
    if frame.Castbar then CastFrame(frame.Castbar, false) end
    -- the frame's own levels back (Elements.lua's)
    local base = frame:GetFrameLevel()
    if frame.Health then frame.Health:SetFrameLevel(base + 1) end
    if frame.Power then frame.Power:SetFrameLevel(base + 2) end
    if frame.Portrait then frame.Portrait:SetFrameLevel(base + 3) end
end

function K.Apply(frame)
    local G, kit, kind, look = K.For(frame)
    if not G then Off(frame) return end
    frame._zKitOn, frame._zKitGeom, frame._zKitKind, frame._zKitId = true, G, kind, kit.id
    kitCfg[frame.cfg] = true
    kitFrames[frame] = true
    Events()
    local secureFight = frame.IsProtected and frame:IsProtected() and InCombatLockdown and InCombatLockdown()
    -- the frame takes the art's box (its saved size is left as it is)
    if not secureFight then
        frame:SetSize(G.w, G.h)
        if G.hit and frame.SetHitRectInsets then pcall(frame.SetHitRectInsets, frame, G.hit[1], G.hit[2], G.hit[3], G.hit[4]) end
    end
    -- ZacUI's box steps back: no backdrop at all, so a later border tint
    -- (the dispel highlight) has nothing to colour. Every restyle lays the
    -- frame's own backdrop first (LeanRestyle, the preview's Style), so
    -- ZacUI's look gets it back on its own.
    if frame.SetBackdrop then pcall(frame.SetBackdrop, frame, nil) end

    local base = frame:GetFrameLevel()
    local af = ArtFrame(frame)
    af:Show()
    -- classic: the art over the bars (its tracks are windows in opaque
    -- art), under the texts; modern: the art under the bars
    if kit.artAbove then
        af:SetFrameLevel(base + 4)
    else
        af:SetFrameLevel(base + 2)
        if frame.Health then frame.Health:SetFrameLevel(base + 3) end
        if frame.Power then frame.Power:SetFrameLevel(base + 3) end
    end
    PaintArt(frame, G)
    -- the dark plaque behind the bars (classic)
    if G.back then
        local bf = af.back
        bf:SetFrameLevel(math.max(0, base))
        bf.tex:ClearAllPoints()
        bf.tex:SetPoint("TOPLEFT", frame, "TOPLEFT", G.back.x, -G.back.y)
        bf.tex:SetSize(G.back.w, G.back.h)
        bf:Show()
    else
        af.back:Hide()
    end
    -- the target's name plaque (classic: under the art, seen through its
    -- name window) or the type strip (modern: over the art)
    local pl = af.plaque
    local PQ = G.plaque or G.strip
    if PQ and (PQ.file or AtlasOK(PQ.atlas)) then
        if PQ.file then pl:SetTexture(PQ.file) pl:SetSize(PQ.w, PQ.h) pl:SetDrawLayer("BACKGROUND", -1)
        else K.SetArt(pl, PQ.atlas, true, kit.id) pl:SetDrawLayer("BACKGROUND", 1) end
        pl:ClearAllPoints()
        pl:SetPoint(PQ.point, frame, PQ.point, PQ.x, PQ.y)
        pl:Show()
    else
        pl:Hide()
    end

    -- the bars in the art's tracks, in the game's bar texture
    local tex = (look and look.barTexture) or "Interface\\TargetingFrame\\UI-StatusBar"
    Bar(frame, frame.Health, G.health, tex)
    Bar(frame, frame.Power, G.power, tex)
    if frame.Power then frame.Power:Show() end
    if frame.Overlay then
        frame.Overlay:ClearAllPoints()
        frame.Overlay:SetAllPoints(frame)
    end
    if frame.Portrait then frame.Portrait._shrunk = nil end

    -- the name where the art has its name
    local nm = frame.Name
    if nm and G.name then
        nm:ClearAllPoints()
        nm:SetPoint(G.name.point, frame, G.name.point, G.name.x, G.name.y)
        nm:SetWidth(G.name.w)
        if nm.SetJustifyH then nm:SetJustifyH(G.name.justify or "LEFT") end
        nm:Show()
    end
    if frame.NameStrip then frame.NameStrip:Hide() end

    Portrait(frame, G, kit)
    Level(frame, G)
    if frame._zKitLevel then frame._zKitLevel.host:Show() end
    K.RefreshTarget(frame)

    -- the cast bar in the game's texture and its classic frame
    local cb = frame.Castbar
    if cb then
        cb:SetStatusBarTexture(tex)
        if cb.border then for _, t in pairs(cb.border) do t:SetAlpha(0) end end
        CastFrame(cb, true)
    end
end

-- ----------------------------------------------------------------------------
-- Wiring: after Elements.lua's StyleElements and Portrait.lua's portrait
-- ----------------------------------------------------------------------------
do
    local style = ns.StyleElements
    if style then
        ns.StyleElements = function(frame, ...)
            -- the kind first, so the portrait (Portrait.lua) knows it is forced on
            local G, _, kind = K.For(frame)
            frame._zKitKind = G and kind or nil
            style(frame, ...)
            K.Apply(frame)
        end
    end
    -- the game's colours on a kitted frame: Blizzard's green health and
    -- gold name (every health tick reads these: one table lookup)
    local hc, nc = ns.HealthColorFor, ns.NameColorFor
    if hc then
        ns.HealthColorFor = function(cfg, ...)
            if cfg and kitCfg[cfg] then return 0, 1, 0 end
            return hc(cfg, ...)
        end
    end
    if nc then
        ns.NameColorFor = function(cfg, ...)
            if cfg and kitCfg[cfg] then return 1, 0.82, 0 end
            return nc(cfg, ...)
        end
    end
end
