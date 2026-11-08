-- Core_Look - the Look: which ART the world wears. The looks the model
-- knows (Look.Looks(); which are OFFERED depends on the client's files
-- and on what is dressed yet, Look.Offered):
--   zacui     flat and dark - thin pixel borders, flat fills, ZacUI's own
--             bar gradient, the one font. Exactly today's constants, read
--             from the same places (ns.FLAT, ns.TEX_NORM...), so picking it
--             changes nothing at all. Every client; the default.
--   classic   "Classic WoW UI": the vanilla art by its own paths - gold
--             dialog borders, UI-StatusBar fills, the client's font, the
--             Quickslot ring on every icon button, the round minimap. No
--             third-party media. Every client that ships that art (Era,
--             TBC, Forever, Retail).
--   forever   "WoW Forever": the client's own art on Forever - its bronze
--             window rims, button rings, gryphons and round level badge.
--   blizzard  "Blizzard style": the client's own art on Retail (its metal
--             rims and rings). On Forever the client's own art IS WoW
--             Forever, on Era / TBC it is Classic: never two cards that draw
--             the same thing (Look.Available). The art names of both modern
--             looks are read in wow-ui-source (see THE MODERN LOOKS below).
-- Part of ZacUI; load order is set by the TOC (after Core_Media, before
-- the UI framework, so every primitive can read it).
--
-- A look is a TABLE of art decisions. The primitives that draw art
-- (AddPixelBorder, SkinBackdrop, SkinStatusBar, SkinSecureIcon /
-- SkinIconButton, SkinButton and friends, SkinPanel, the font resolvers,
-- Media.BarPath / ResolveBarTexture, UI.Window via Dress, the Kit's
-- covers) consult it at BUILD or REFRESH time, store the answer in a
-- local and never read it in OnUpdate or a high-frequency event.
--
-- WHAT NEVER CHANGES LOOK: the /zui settings window and everything built
-- from UI.* in UIF_Controls (dialogs, pickers, Edit Mode, movers, the
-- Tutorial, the aura editor, the unit frames' own Options window) and
-- Readycheck. They never call these accessors (a mover passes "pixel"
-- explicitly). Only the WORLD - frames, plates, bars, skinned Blizzard
-- windows - wears the look.
--
-- SAVED: ZacUIDB.look = { global = "zacui" | "classic",
--                         parts = { [partKey] = "zacui" | "classic" } }
-- A Core_Profiles section, so it travels in every profile, export and
-- copy. Absent = zacui (no migration, no prompt). LATCHED ONCE a session:
-- the live look is read lazily on the first For() after the saved
-- variables exist (so the worn profile's copy is what it sees), re-read
-- once at PLAYER_LOGIN (Boot_Events calls Look.Relatch) in case a profile
-- was worn after that, and never again: every change is reload-gated,
-- and the ONLY place ZacUIDB.look is
-- written is a reload confirm (Config_Style: the Style page, the
-- first-run popup) or the setup wizard's reload, through Look.Commit().
--
-- API
--   ns.Look.For(partKey)          the look table for that part (its
--                                 override, else the global one)
--   ns.Look.Is(partKey, lookId)   boolean
--   ns.Look.Pick(x, defaultPart)  what a primitive takes as its `look`
--                                 argument: nil (-> For(defaultPart or
--                                 "blizzard")), a part key, a look table,
--                                 or the explicit style "pixel" / "edge"
--                                 (used by movers; never overridden)
--   ns.Look.With(lookId, fn, ...) run fn with every part answering that
--                                 look - the preview miniatures draw the
--                                 OTHER look through the real code paths
--   ns.Look.Dress(frame, role, partKey)  the post-pass for frames built
--                                 from UI.* (windows); returns at once
--                                 under zacui (phase 2 fills the roles)
--   ns.Look.Active()              the live global look id
--   ns.Look.Looks()               the look tables in display order
--
-- FOR THE PICKERS (Config_Style: the Style page, the first-run popup, the
-- setup wizard's look step):
--   ns.Look.Choices()             { { id=, name=, tag=, desc= }, ... } in
--                                 card order: the looks OFFERED here
--   ns.Look.Available(lookId)     whether this client ships that art
--   ns.Look.Offered(lookId)       ...and the look is dressed (a card)
--   ns.Look.Cards(parent, opts)   the card row (Config_Style documents it)
--   ns.Look.Preview(parent, lookId, w, h)  a miniature drawn in that
--                                 look by the real primitives: a player
--                                 frame, a bar of four buttons (WoW
--                                 Forever's gryphons), a cast bar
--   ns.Look.Set(lookId)           RECORDS the choice as pending (nothing
--                                 written, nothing re-dressed);
--   ns.Look.StageEverywhere(id)   ...for every part (overrides dropped);
--   ns.Look.StagePart(part, id)   one part into a look;
--   ns.Look.Commit()              writes the pending choice (global and
--                                 per-part) into ZacUIDB.look - the one
--                                 writer; call it right AFTER asking for
--                                 the reload, in the same click (WoW
--                                 Forever wants the reload asked first;
--                                 Look.ConfirmApply wraps the confirm);
--   ns.Look.Pending() / PendingParts() / PendingFor(part) / Discard() /
--   Dirty()                       the staged state;
--   ns.Look.EffectiveFor(part)    what a part wears once applied;
--   ns.Look.LiveFor(part)         what it wears this session;
--   ns.Look.LiveUniform()         the look every part wears, nil if mixed.
--   ns.Look.MinimapSpec(part)     the minimap's shape / mask / chrome.
--
-- CLIENTS. Every Blizzard file below is native on Classic Era and TBC;
-- Forever (a retail-based client) still ships the dialog, tooltip and
-- status-bar files (its own Backdrop presets name them) and the Quickslot
-- set. The three "verify" files (MinimapMask, the Panel buttons, the
-- Character tabs) have a fallback each in CLASSIC_FOREVER below and are
-- checked on the real client before phase 2 leans on them.

local ADDON_NAME, ns = ...

local Look = {}
ns.Look = Look

local FLAT = ns.FLAT
local TEX_NORM = ns.TEX_NORM
local TEX_THUMB = ns.TEX_THUMB

-- ============================================================
-- THE TWO LOOKS
-- ============================================================
-- Fields (every primitive reads only what it needs):
--   id, name, desc            identity and the one-line description
--   bgTexture / bgAlpha       a window fill (nil alpha: the caller's own)
--   bgSmall                   the fill of a small box (tooltip, slot, bar)
--   border = { style = "pixel", size }   four 1px strips (as today)
--          | { style = "edge", file, edgeSize, inset }   a Blizzard edge
--   borderWindow              the edge a window wears (classic only)
--   barTexture                the status-bar fill when none is chosen
--   barBacking                "flat" (FLAT at half elementBg) | "same"
--                             (the fill's own file, dark)
--   font                      nil = follow Fonts & Textures | "game"
--   button / iconButton / tabs / windowChrome / tooltip / scrollbar /
--   widgets / closeX          "flat" (ZacUI's) | "stock" (Blizzard's)
--   iconCrop                  the texcoord inset of an icon (0.11 | 0):
--                             ZacUI's cuts the game's bevel off at every
--                             size (Look.CropIcon), Classic keeps it
--   iconRing                  the icon button's ring files (classic)
--   minimap                   { shape, mask, chrome }
--   castBorder                "pixel" | { file = ..., nine-slice facts }
--   tag                       the two-word line under the name (cards)
--   rule / ruleKey            the card's top rule: a palette key pair for
--                             ZacUI's own, the look's badge colour else
local LOOKS = {}
local ORDER = { "zacui", "forever", "blizzard", "classic" }

LOOKS.zacui = {
    id = "zacui",
    name = "ZacUI",
    tag = "Flat & dark",
    desc = "Thin edges, flat fills, ZacUI's bars and font.",
    ruleKey = { "ui", "accent" },
    bgTexture = FLAT,
    bgAlpha = nil,
    bgSmall = FLAT,
    border = { style = "pixel", size = 1 },
    borderWindow = { style = "pixel", size = 1 },
    -- HD polish (2026-11-07): a flat fill, like the reference UI's; the
    -- gradient (normTex, "ZacUI Smooth") stays a pick on Fonts & Textures
    barTexture = FLAT,
    barBacking = "flat",
    font = nil,
    button = "flat",
    iconButton = "flat",
    -- 0.11 of each edge (7 of an icon's 64 texels): the game's icons carry
    -- a bevelled frame about 4 texels wide with a soft dark rim of 1-2
    -- more, and an upscaled icon (48-64 px) blends the next texel in at
    -- its edge - 4 + 2 + 1 = 7. The old 0.08 (5 texels) left that rim
    -- showing on big icons. Player-tunable (Look.IconCrop: ZacUIDB.iconZoom).
    iconCrop = 0.11,
    tabs = "flat",
    windowChrome = "flat",
    tooltip = "flat",
    scrollbar = "flat",
    scrollThumb = TEX_THUMB,
    widgets = "flat",
    closeX = "flat",
    minimap = { shape = "SQUARE", mask = "Interface\\ChatFrame\\ChatFrameBackground", chrome = "hide" },
    castBorder = "pixel",
}

-- Blizzard's art, by path. The same names retail's Backdrop presets still
-- carry, so Forever draws them too.
local DIALOG_BG     = "Interface\\DialogFrame\\UI-DialogBox-Background"
local DIALOG_BORDER = "Interface\\DialogFrame\\UI-DialogBox-Border"
local TIP_BG        = "Interface\\Tooltips\\UI-Tooltip-Background"
local TIP_BORDER    = "Interface\\Tooltips\\UI-Tooltip-Border"
local STATUSBAR     = "Interface\\TargetingFrame\\UI-StatusBar"
local CAST_BORDER   = "Interface\\CastingBar\\UI-CastingBar-Border"

LOOKS.classic = {
    id = "classic",
    name = "Classic WoW UI",
    tag = "Old gold",
    desc = "The 2004 gold borders, rings and round minimap.",
    -- the card's colour (match pass, 2026-11-07: each look its own accent,
    -- the reference picker's values, zui_tests/MATCH_SPEC_1107.md): bronze
    rule = { r = 0.86, g = 0.65, b = 0.42 },
    bgTexture = DIALOG_BG,
    bgAlpha = 1,
    bgSmall = TIP_BG,
    border = { style = "edge", file = TIP_BORDER, edgeSize = 16, inset = 4 },
    borderWindow = { style = "edge", file = DIALOG_BORDER, edgeSize = 32, inset = 11 },
    barTexture = STATUSBAR,
    barBacking = "same",
    font = "game",
    button = "stock",
    iconButton = "stock",
    iconCrop = 0,
    -- the vanilla template's ring: 66x66 on a 36 button, centred 1 down
    iconRing = {
        normal = "Interface\\Buttons\\UI-Quickslot2",
        empty = "Interface\\Buttons\\UI-Quickslot",
        pushed = "Interface\\Buttons\\UI-Quickslot-Depress",
        highlight = "Interface\\Buttons\\ButtonHilight-Square",
        checked = "Interface\\Buttons\\CheckButtonHilight",
        scale = 66 / 36, dy = -1 / 36,
    },
    tabs = "stock",
    windowChrome = "stock",
    tooltip = "stock",
    scrollbar = "stock",
    scrollThumb = "Interface\\Buttons\\UI-ScrollBar-Knob",
    widgets = "stock",
    closeX = "stock",
    minimap = { shape = "ROUND", mask = "Textures\\MinimapMask", chrome = "keep" },
    -- the 256x64 sheet: the reference cut is columns 16/48/208/240 and
    -- rows 16/28/37/48, only the window band stretched (phase 2 draws it)
    castBorder = { file = CAST_BORDER, cols = { 16, 48, 208, 240 }, rows = { 16, 28, 37, 48 }, w = 256, h = 64 },
    -- a ZacUI window (a Kit cover, a meter window) in this look: the dialog
    -- rim OUTSIDE the window's box (the rim's art is its outer ~11 px), so
    -- the title-bar icon, the title and the footer corners stay clear
    borderCover = { style = "edge", file = DIALOG_BORDER, edgeSize = 32, inset = 11, out = 11 },
}

-- WoW Forever: the files above that could not be confirmed on that client
-- yet, each with the fallback used until /zacui id has checked them.
local CLASSIC_FOREVER = {
    minimapMask = "Interface\\CharacterFrame\\TempPortraitAlphaMask",
}
Look.CLASSIC_FOREVER = CLASSIC_FOREVER

-- THE MODERN LOOKS (phase 1b). The client's own current art, by the
-- names its UI code uses - every one read in Gethe/wow-ui-source, branch
-- "forever" (2026-11-07; the same names on "live"):
--   window rim   NineSliceLayouts.ButtonFrameTemplateNoPortrait
--                (UI-Frame-Metal-*; Blizzard_SharedXML/Mainline/
--                NineSliceLayouts.lua)
--   small boxes  NineSliceLayouts.TooltipDefaultLayout (Tooltip-NineSlice-*,
--                its own Center piece)
--   window fill  Interface\FrameGeneral\UI-Background-Rock (the Bg file of
--                ButtonFrameTemplate, Mainline SharedUIPanelTemplates.xml)
--   button ring  the Mainline ActionButtonTemplate's own UI-HUD-ActionBar-
--                IconFrame atlases, kept as the template draws them
--                (iconRing nil: SkinSecureIcon leaves the NormalTexture)
--   gryphons     ui-hud-actionbar-gryphon-left / -right (Blizzard_ActionBar/
--                Camelot/MainMenuBarEndCaps.xml on Forever)
--   level badge  UI-HUD-UnitFrame-SmallCircle (Blizzard_UnitFrame/Camelot/
--                PlayerFrameTemplates.xml)
-- Each nine-slice is drawn through NineSliceUtil.ApplyLayoutByName (the
-- client's own layout table, nothing copied) only where the client has
-- the utility and the layout's corner atlas (C_Texture.GetAtlasInfo);
-- anywhere else the edge falls back to the Classic files, so a missing
-- piece never leaves a frame bare. Fonts, bars and every other field are
-- the Classic table's.
--
-- WHICH CLIENT GETS WHICH. Forever draws its own bronze art under the
-- Mainline names, so on Forever "the client's own art" IS WoW Forever:
-- Blizzard style collapses into it there, exactly as it collapses into
-- Classic on Era and TBC - never two cards that draw the same thing.
--   Era / TBC   ZacUI, Classic WoW UI
--   Forever     ZacUI, WoW Forever, Blizzard style, Classic WoW UI
--               (match pass, 2026-11-07: Blizzard style offered there too,
--               as the reference picker does; on that client its frames
--               are the client's modern layouts without WoW Forever's
--               gryphons, badge and bronze rim pieces)
--   Retail      ZacUI, Blizzard style, Classic WoW UI
local ROCK_BG = "Interface\\FrameGeneral\\UI-Background-Rock"
local MODERN_BORDER = { style = "edge", nineslice = "TooltipDefaultLayout", minSize = 24,
    file = TIP_BORDER, edgeSize = 16, inset = 4 }
local MODERN_WINDOW = { style = "edge", nineslice = "ButtonFrameTemplateNoPortrait", minSize = 80,
    -- the rim's pieces sit this far outside / inside the frame's box
    out = 8, inset = 4, file = DIALOG_BORDER, edgeSize = 32 }

LOOKS.blizzard = {}
for k, v in pairs(LOOKS.classic) do LOOKS.blizzard[k] = v end
LOOKS.blizzard.id = "blizzard"
LOOKS.blizzard.name = "Blizzard style"
LOOKS.blizzard.tag = "Live client"
LOOKS.blizzard.desc = "This client's frames and buttons as drawn today."
LOOKS.blizzard.rule = { r = 1.0, g = 0.80, b = 0.18 }       -- gold (match pass)
LOOKS.blizzard.iconRing = nil
LOOKS.blizzard.modern = true
LOOKS.blizzard.border = MODERN_BORDER
LOOKS.blizzard.borderWindow = MODERN_WINDOW
LOOKS.blizzard.borderCover = MODERN_WINDOW
LOOKS.blizzard.bgTexture = ROCK_BG

LOOKS.forever = {}
for k, v in pairs(LOOKS.blizzard) do LOOKS.forever[k] = v end
LOOKS.forever.id = "forever"
LOOKS.forever.name = "WoW Forever"
LOOKS.forever.tag = "Bronze chrome"
LOOKS.forever.desc = "Forever's bronze rims, gryphons and level badge."
LOOKS.forever.rule = { r = 0.47, g = 0.75, b = 0.95 }       -- a cool blue (match pass)
LOOKS.forever.art = {
    rim = { tl = "UI-Frame-Metal-CornerTopLeft", tr = "UI-Frame-Metal-CornerTopRight",
            bl = "UI-Frame-Metal-CornerBottomLeft", br = "UI-Frame-Metal-CornerBottomRight",
            top = "_UI-Frame-Metal-EdgeTop", bottom = "_UI-Frame-Metal-EdgeBottom",
            left = "!UI-Frame-Metal-EdgeLeft", right = "!UI-Frame-Metal-EdgeRight" },
    gryphonLeft = "ui-hud-actionbar-gryphon-left",
    gryphonRight = "ui-hud-actionbar-gryphon-right",
    badge = "UI-HUD-UnitFrame-SmallCircle",
}
-- the gryphons on ZacUI's first action bar (AB_Core reads it)
LOOKS.forever.gryphons = true

-- THE PORTRAIT each game look puts on the unit frames (Zacui_UnitFrames/
-- Portrait.lua reads look.portrait; ZacUI's own look has none). A name
-- without a backslash is an atlas, feature-detected there. Names: the
-- wow-ui-source forever branch (Blizzard_UnitFrame/Camelot/
-- PlayerFrameTemplates.xml:11, the SmallCircle level badge) and Mainline
-- (PlayerFrame.xml:32, the mask); Mainline's level circle has no atlas, so
-- Blizzard style gets no badge. Set after the copies above, so no look
-- inherits another's.
LOOKS.forever.portrait = { mask = "UI-HUD-UnitFrame-Player-Portrait-Mask", badge = "UI-HUD-UnitFrame-SmallCircle" }
LOOKS.blizzard.portrait = { mask = "UI-HUD-UnitFrame-Player-Portrait-Mask" }
LOOKS.classic.portrait = { mask = "Interface\\CharacterFrame\\TempPortraitAlphaMask" }

-- (kept for callers and tests from phase 1: every known look is dressed now)
Look.OFFER_1B = true

-- WHICH LOOKS THIS CLIENT CAN DRAW - a fact about the real client's files,
-- never the "Test as" override (Core_Flavor's real flavor).
local function RealFlavor()
    if ns.RealFlavor then return ns.RealFlavor() end
    if ns.DetectFlavor then return ns.DetectFlavor() end
    return "era"
end
function Look.Available(id)
    local l = LOOKS[id]
    if not l then return false end
    if l.unverified then return false end
    local fl = RealFlavor()
    if id == "zacui" then return true end
    if id == "classic" then return true end          -- vanilla art ships on every client (section 4 of the plan)
    -- Blizzard style: the modern client's own frames, on Retail and (match
    -- pass, 2026-11-07: offered beside WoW Forever, as the reference picker
    -- does) on Forever, whose client draws the same modern layouts
    if id == "blizzard" then return fl == "retail" or fl == "forever" end
    if id == "forever" then return fl == "forever" end
    return false
end

-- OFFERED here: the art is on the client AND the look is dressed (a
-- phase-1b look waits for OFFER_1B). What the cards show, what Set takes
-- and what a saved look may name.
function Look.Offered(id)
    local l = LOOKS[id]
    if not l or not Look.Available(id) then return false end
    if l.pending and not Look.OFFER_1B then return false end
    return true
end

-- ============================================================
-- THE PART KEYS (the registry's module keys; no new vocabulary)
-- ============================================================
Look.PARTS = {
    { key = "unitframes", label = "Unit frames" },
    { key = "nameplates", label = "Nameplates" },
    { key = "bars",       label = "Action bars" },
    { key = "windows",    label = "Game windows" },
    { key = "bags",       label = "Bags" },
    { key = "minimap",    label = "Minimap" },
    { key = "chat",       label = "Chat" },
    { key = "tooltip",    label = "Tooltips" },
    { key = "auras",      label = "Buffs" },
    { key = "meter",      label = "Damage meter" },
    { key = "auraengine", label = "Aura engine" },
    { key = "sct",        label = "Combat text" },
    { key = "maps",       label = "Maps" },
    { key = "blizzard",   label = "Blizzard windows" },
}
local PART_OK = {}
for _, p in ipairs(Look.PARTS) do PART_OK[p.key] = true end
-- part keys the code also asks for, folded onto a listed one
local PART_ALIAS = { actionbars = "bars", castbar = "unitframes", lootroll = "blizzard", inventory = "bags",
    hud = "unitframes", consumables = "bars", blessings = "bars", buffrem = "auras", raidtools = "blizzard" }

-- ============================================================
-- THE LATCH
-- ============================================================
local active            -- { global = id, parts = { key = id } } once latched
local forced            -- a look table every For() answers during With()
local saidBad = false

local function Valid(id) return type(id) == "string" and LOOKS[id] ~= nil end

local function ReadSaved()
    local saved = type(ZacUIDB) == "table" and ZacUIDB.look or nil
    local out = { global = "zacui", parts = {} }
    if type(saved) ~= "table" then return out end
    if Valid(saved.global) and Look.Offered(saved.global) then
        out.global = saved.global
    elseif saved.global ~= nil and not saidBad then
        saidBad = true
        if ns.Print then ns.Print("Look \"" .. tostring(saved.global) .. "\" is not one this client can draw; wearing ZacUI's own.") end
    end
    if type(saved.parts) == "table" then
        for k, v in pairs(saved.parts) do
            -- an unknown part or look is ignored, not an error
            if PART_OK[k] and Valid(v) and Look.Offered(v) then out.parts[k] = v end
        end
    end
    return out
end

local function Latch()
    -- nothing to read before the saved variables exist (file load): the
    -- answer is zacui and nothing is latched yet
    if type(ZacUIDB) ~= "table" then return nil end
    active = ReadSaved()
    return active
end

-- the worn profile is in place by PLAYER_LOGIN: Boot_Events asks for one
-- re-read there (before ApplyAll), so a For() that ran before the profile
-- copy does not pin the wrong look. Nothing after that re-reads.
local settled = false
function Look.Relatch()
    if active then Latch() end
    settled = true
end
-- true once the PLAYER_LOGIN re-read has run: from then on every answer is
-- the worn profile's. A decision made ONCE from the look (the match
-- overlays of the unit frames and the nameplates, 2026-11-08) waits for
-- it - before it, a For() may answer ZacUI's look for a Classic save.
function Look.Settled() return settled end

local function Live()
    return active or Latch()
end

function Look.Active()
    local a = Live()
    return a and a.global or "zacui"
end

function Look.ActiveParts()
    local a = Live()
    return a and a.parts or {}
end

function Look.Looks()
    local out = {}
    for _, id in ipairs(ORDER) do out[#out + 1] = LOOKS[id] end
    return out
end

function Look.Get(id) return LOOKS[id] end

-- ============================================================
-- THE ACCESSORS
-- ============================================================
function Look.For(part)
    if forced then return forced end
    local a = Live()
    if not a then return LOOKS.zacui end
    if type(part) == "string" then
        part = PART_ALIAS[part] or part
        local id = a.parts[part]
        if id then return LOOKS[id] end
    end
    return LOOKS[a.global] or LOOKS.zacui
end

function Look.Is(part, id)
    return Look.For(part).id == id
end

-- ============================================================
-- THE GAME'S OWN UI UNDER A GAME LOOK (2026-11-07, Zac: "zui styling
-- should be off for blizzard default stuff")
-- ============================================================
-- Under WoW Forever, Blizzard style and Classic WoW UI the game's own UI
-- is the game's: its windows, chat, tooltips, minimap and loot rolls show
-- their stock art. Every module below that SKINS or COVERS one of those
-- stands down for a part wearing a game look: it is never run, so it makes
-- no cover, strips nothing and hooks nothing. ZacUI's own features (the
-- meter, the combined bag, the map's behaviour, the button tray, chat's
-- history / links / fade) keep running; only the skin goes. The looks a client offers are Look.Available's (Era
-- and TBC: ZacUI and Classic; Forever: all four; Retail: ZacUI, Blizzard
-- style, Classic), and a saved look this client cannot draw latches as
-- ZacUI's, so a stood-down part is always one the client can show stock.
-- LATCHED like every look answer: a change applies at the reload the look
-- picker asks for anyway, so a skin that ran this session is never undone
-- live (that would need the reload for taint) and one stood down is never
-- started live. Boot_Apply's RunModule asks Look.StandsDown(module).
-- (2026-11-08) The skins of Blizzard's HUD too (the end of the list).
--   module key -> the look part that decides it
Look.STOCK = {
    -- the game's windows: Blizzard's own skins (the "blizzard" part) ...
    dialogs = "blizzard", gamemenu = "blizzard", mail = "blizzard", merchant = "blizzard",
    character = "blizzard", inspect = "blizzard", spellbook = "blizzard", questlog = "blizzard",
    friends = "blizzard", trade = "blizzard", loot = "blizzard", gossip = "blizzard", taxi = "blizzard",
    readycheck = "blizzard", addons = "blizzard", guild = "blizzard", pvp = "blizzard",
    trainer = "blizzard", misc = "blizzard", options = "blizzard", panels = "blizzard",
    lootroll = "blizzard",
    -- ... the generic passes that skin whatever the game makes ...
    hooks = "blizzard", sweep = "blizzard", watcher = "blizzard",
    -- ... the bags and bank (Blizzard's frames; ZacUI's combined bag is a
    -- feature and stays) ...
    bags = "bags", bank = "bags",
    -- ... the world map's skin (Zacui_Maps' behaviour stays) ...
    worldmap = "maps",
    -- ... and ZacUI's covers over them (Zacui_Windows)
    merchantwin = "windows", spellbookwin = "windows", talentswin = "windows", tradeskillwin = "windows",
    craftwin = "windows", trainerwin = "windows", paperdollwin = "windows", petpaperdollwin = "windows",
    chartabswin = "windows", skillswin = "windows", reputationwin = "windows", honorwin = "windows",
    inspectwin = "windows", questlogwin = "windows", mailwin = "windows", mailtabswin = "windows",
    friendswin = "windows", whowin = "windows", ignorewin = "windows", raidwin = "windows",
    friendtabswin = "windows", guildwin = "windows", tradewin = "windows", lootwin = "windows",
    gossipwin = "windows", questdialogwin = "windows", taxiwin = "windows", battlefieldwin = "windows",
    scorewin = "windows", macroswin = "windows", lfgwin = "windows",
    -- chat, tooltips and the minimap
    chat = "chat", tooltip = "tooltip", minimap = "minimap",
    -- THE HUD'S SKINS (2026-11-08): ZacUI's skins of Blizzard's own unit
    -- frames and cast bars, and the quest tracker's recolour. Under a game
    -- look the game's art is the point: a Blizzard frame on screen (one
    -- ZacUI does not replace) keeps its own art. ZacUI's replacements -
    -- the unit frames, the nameplates - keep running and draw the look's
    -- kit themselves (the reference UI's way: its modules render stock
    -- styles on their own frames and leave Blizzard's alone).
    unitframes = "unitframes", castbar = "unitframes", tracker = "blizzard",
}

-- the part wears a game look this session: its Blizzard UI stays stock
function Look.Stock(part)
    if forced then return false end         -- (a preview never decides a module)
    local l = Look.For(part)
    return l ~= nil and l.id ~= "zacui"
end

-- the module is a skin or cover of the game's UI and its part wears a game look
function Look.StandsDown(module)
    local part = Look.STOCK[module]
    if not part then return false end
    return Look.Stock(part)
end

-- ============================================================
-- STYLE DEFAULTS THAT FOLLOW THE LOOK (2026-11-08, Zac: "for the classic
-- style or forever style etc make sure its actually default to what it
-- suppose to look like dont just add things")
-- ============================================================
-- Under a game look a part's ZacUI-only STYLE settings (glows, arrows,
-- texts, fades, class colours where the stock UI is green, motion) default
-- to the stock UI's value; features stay as they are. A setting still on
-- ZacUI's shipped default follows the look; one set by hand never moves.
--   Look.FollowDefaults(save, defaults, spec, part)
--     save      the part's saved settings table (ZacUIDB.<part>)
--     defaults  its defaults table (what a fresh save is filled from)
--     spec      { { key..., stockValue }, ... } - paths in both tables
--     part      the look part that decides
-- Under a game look: the defaults take the stock values (a fresh save
-- fills with them) and a saved value equal to ZacUI's shipped one moves to
-- the stock value; the save is marked (save._zLookDef). Back under ZacUI's
-- look a marked save's values still on the stock value move back to
-- ZacUI's and the mark goes: a save that never wore a game look is never
-- touched, so ZacUI's look is exactly as it was. Waits for the settled
-- latch (Look.Settled); a call before it does nothing. Idempotent.
local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local o = {}
    for k, x in pairs(v) do o[k] = DeepCopy(x) end
    return o
end
local function Same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then
        if type(a) == "number" then return math.abs(a - b) < 0.0005 end
        return a == b
    end
    for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function Walk(t, e)
    for j = 1, #e - 2 do
        if type(t) ~= "table" then return nil end
        t = t[e[j]]
    end
    return type(t) == "table" and t or nil
end
function Look.FollowDefaults(save, defaults, spec, part)
    if type(save) ~= "table" or type(defaults) ~= "table" or type(spec) ~= "table" then return false end
    if not settled then return false end
    local game = Look.Stock(part)
    -- ZacUI's shipped values, read once before anything is changed
    for _, e in ipairs(spec) do
        if e.zacui == nil then
            local d = Walk(defaults, e)
            e.zacui = { v = DeepCopy(d and d[e[#e - 1]]) }
        end
    end
    if game then
        for _, e in ipairs(spec) do
            local k, stock = e[#e - 1], e[#e]
            local d = Walk(defaults, e)
            if d then d[k] = DeepCopy(stock) end
            local s = Walk(save, e)
            if s and s[k] ~= nil and Same(s[k], e.zacui.v) then s[k] = DeepCopy(stock) end
        end
        save._zLookDef = Look.For(part).id
        return true
    end
    if save._zLookDef then
        for _, e in ipairs(spec) do
            local k, stock = e[#e - 1], e[#e]
            local s = Walk(save, e)
            if s and s[k] ~= nil and Same(s[k], stock) then s[k] = DeepCopy(e.zacui.v) end
        end
        save._zLookDef = nil
    end
    return false
end

-- What a primitive's `look` argument means. The explicit styles are for
-- frames that must never change look (movers): nothing overrides them.
function Look.Pick(x, defaultPart)
    if x == nil then return Look.For(defaultPart or "blizzard") end
    if type(x) == "table" then return x end
    if x == "pixel" or x == "zacui" then return LOOKS.zacui end
    if x == "edge" or x == "classic" then return LOOKS.classic end
    return Look.For(x)
end

-- Run fn with every part answering `id`: how a miniature of the OTHER
-- look is drawn through the real code paths. Nested calls restore.
function Look.With(id, fn, ...)
    local before = forced
    forced = LOOKS[id] or LOOKS.zacui
    local ok, a, b, c = pcall(fn, ...)
    forced = before
    if not ok then
        if ns.Print then ns.Print("look preview: " .. tostring(a)) end
        return nil
    end
    return a, b, c
end

-- The post-pass for a frame built from UI.* (a window, a cover, a meter
-- window). Under zacui it returns on its first line: UI.* already drew
-- ZacUI's look. Otherwise the role's dresser lays the look's window
-- chrome over it (Look.dressers below). Idempotent: covers re-style on
-- every repaint and call it again.
function Look.Dress(frame, role, part)
    local look = Look.For(part or "windows")
    if look.id == "zacui" then return end
    if not frame then return end
    rawset(frame, "_zLook", look.id)
    local fn = Look.dressers and Look.dressers[role or "window"]
    if fn then pcall(fn, frame, look, part) end
end
Look.dressers = {}

-- A window in another look: ZacUI's flat fill and pixel strips step back
-- (alpha 0, so a later return to ZacUI's look at the next reload finds
-- them as they were) and the look's window backdrop goes on: the dialog
-- border and background (Classic), the client's metal / bronze rim on
-- the rock fill (the modern looks). Only frames ZacUI made reach here.
local function DressWindow(f, look)
    local fill = rawget(f, "_zFill")
    if fill and fill.SetAlpha then fill:SetAlpha(0) end
    for _, t in ipairs(rawget(f, "_zBorder") or {}) do if t.SetAlpha then t:SetAlpha(0) end end
    local cbg = rawget(f, "_zui_cbg")
    if cbg and cbg ~= rawget(f, "_zui_edge") and cbg.SetAlpha then cbg:SetAlpha(0) end
    local strips = rawget(f, "_zui_borderTex")
    if strips and not strips._zEdge then
        for _, t in ipairs(strips) do if t.SetAlpha then t:SetAlpha(0) end end
    end
    -- the edge sits UNDER the window's own regions and children (a level
    -- below the window), its rim outside the box (borderCover.out)
    local edge = Look.AddFill(f, look.borderCover or look.borderWindow or look.border, look.bgTexture or look.bgSmall, 1)
    if edge and edge.SetFrameLevel and f.GetFrameLevel then edge:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1)) end
    -- a title bar ZacUI drew keeps its words, loses its flat band
    local bar = rawget(f, "titleBar")
    if bar then
        local bfill = rawget(bar, "_zFill")
        if bfill and bfill.SetAlpha then bfill:SetAlpha(0) end
        local art = rawget(bar, "_zArt")
        if art and art.SetAlpha then art:SetAlpha(0) end
    end
end
Look.dressers.window = DressWindow
Look.dressers.cover = DressWindow
Look.dressers.meterWindow = DressWindow

-- The minimap's shape in a part's look: ZacUI's square, or the round map
-- with the game's ring (Classic and the modern looks). The round mask is
-- the vanilla file on Era / TBC; on Forever and Retail the portrait mask
-- every Mainline round frame uses (CLASSIC_FOREVER), since the vanilla
-- MinimapMask path is not confirmed there.
function Look.MinimapSpec(part)
    local mm = Look.For(part or "minimap").minimap or LOOKS.zacui.minimap
    if mm.shape == "ROUND" then
        local fl = RealFlavor()
        if fl == "forever" or fl == "retail" then
            return { shape = "ROUND", mask = CLASSIC_FOREVER.minimapMask, chrome = mm.chrome }
        end
    end
    return mm
end

-- ============================================================
-- ICON ZOOM: one helper for every icon ZacUI draws
-- ============================================================
--   ns.Look.IconCrop(part)            the crop an icon takes now: the
--                                     look's iconCrop (ZacUI 0.11, Classic
--                                     0), or under ZacUI's look the
--                                     player's "Icon zoom" (ZacUIDB.iconZoom,
--                                     0-0.25; nil = the look's own)
--   ns.Look.CropIcon(tex, w, h, opts) crops `tex` (an icon texture) by that,
--                                     trimming the short axis further on a
--                                     non-square icon so nothing stretches
--                                     (w, h: the icon's size, else its own
--                                     size, else square). Under ZacUI's look
--                                     it also frames the icon in a 1px dark
--                                     border of ZacUI's own unless its parent
--                                     already wears one (opts.border = false:
--                                     never). opts.part: the part's look;
--                                     opts.look: a fixed look (settings
--                                     windows pass "zacui"); opts.minCrop:
--                                     a floor the crop never goes under
--                                     (kept for RecropAll too).
--                                     Remembered (weakly) and re-cropped by
--                                     Look.RecropAll() when the zoom changes.
--                                     Returns tex. Build / refresh time only.
local ICON_ZOOM_MAX = 0.25
local cropped = setmetatable({}, { __mode = "k" })

function Look.IconCrop(part)
    local lk = Look.For(part)
    if lk.id == "zacui" then
        local z = type(ZacUIDB) == "table" and tonumber(ZacUIDB.iconZoom)
        if z then return math.max(0, math.min(ICON_ZOOM_MAX, z)) end
    end
    return lk.iconCrop or 0
end

-- the coords for crop c on a w x h icon: the long axis cut by c, the
-- short one by as much more as keeps the art's aspect
function Look.IconCoords(c, w, h)
    local l, r, t, b = c, 1 - c, c, 1 - c
    if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 and math.abs(w - h) > 0.5 then
        local span = 1 - 2 * c
        if w > h then
            local sy = span * h / w
            t, b = 0.5 - sy / 2, 0.5 + sy / 2
        else
            local sx = span * w / h
            l, r = 0.5 - sx / 2, 0.5 + sx / 2
        end
    end
    return l, r, t, b
end

-- The frame follows its icon: shown only while the icon is shown, has a
-- picture and is not faded out (alpha mirrored), so a hidden cast icon
-- or an empty slot leaves no outline behind. Hooks on the icon's own
-- show / hide / alpha / texture calls - run when the caller changes it,
-- never per frame.
local function SyncFrame(tex)
    local strips = rawget(tex, "_zIconFrame")
    if not strips then return end
    local on = rawget(tex, "_zIconFrameOn") and tex:IsShown() and tex:GetTexture() ~= nil
    local a = tex.GetAlpha and tex:GetAlpha() or 1
    if type(a) ~= "number" then a = 1 end
    for _, st in ipairs(strips) do
        if on and a > 0 then st:Show() st:SetAlpha(a) else st:Hide() end
    end
end

local function FrameIcon(tex, on)
    local strips = rawget(tex, "_zIconFrame")
    rawset(tex, "_zIconFrameOn", on or nil)
    if not on then
        if strips then SyncFrame(tex) end
        return
    end
    if not strips then
        local host = tex.GetParent and tex:GetParent()
        if not (host and host.CreateTexture) then return end
        strips = {}
        local c = ns.Col and ns.Col("border") or { r = 0, g = 0, b = 0, a = 1 }
        for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local st = host:CreateTexture(nil, "OVERLAY", nil, 6)
            st._zui_own = true
            st:SetColorTexture(c.r, c.g, c.b, c.a or 1)
            if side == "TOP" or side == "BOTTOM" then
                st:SetPoint(side .. "LEFT", tex, side .. "LEFT", 0, 0)
                st:SetPoint(side .. "RIGHT", tex, side .. "RIGHT", 0, 0)
            else
                st:SetPoint("TOP" .. side, tex, "TOP" .. side, 0, 0)
                st:SetPoint("BOTTOM" .. side, tex, "BOTTOM" .. side, 0, 0)
            end
            -- one physical pixel under the ZacUI look (Core_Pixel, which
            -- loads after this file: looked up when the frame is made)
            if ns.Pixel then ns.Pixel.Edge(st, side, host)
            elseif side == "TOP" or side == "BOTTOM" then st:SetHeight(1)
            else st:SetWidth(1) end
            st._zPaint = function(self)
                local k = ns.Col and ns.Col("border") or c
                self:SetColorTexture(k.r, k.g, k.b, k.a or 1)
            end
            strips[#strips + 1] = st
        end
        rawset(tex, "_zIconFrame", strips)
        for _, m in ipairs({ "Show", "Hide", "SetShown", "SetAlpha", "SetTexture" }) do
            if tex[m] then hooksecurefunc(tex, m, SyncFrame) end
        end
    end
    SyncFrame(tex)
end

local function ApplyCrop(tex, e)
    local lk = e.look and LOOKS[e.look] or nil
    local c
    if lk then
        local before = forced
        forced = lk
        c = Look.IconCrop(e.part)
        forced = before
    else
        c = Look.IconCrop(e.part)
    end
    local w, h = e.w, e.h
    if not (w and h) and tex.GetWidth then
        local ok1, gw = pcall(tex.GetWidth, tex)
        local ok2, gh = pcall(tex.GetHeight, tex)
        if ok1 and ok2 and type(gw) == "number" and type(gh) == "number" then w, h = gw, gh end
    end
    -- a caller's own floor (opts.minCrop: the Class HUD keeps its crop)
    if e.minCrop and c < e.minCrop then c = e.minCrop end
    tex:SetTexCoord(Look.IconCoords(c, w, h))
    local zacui = (lk or Look.For(e.part)).id == "zacui"
    if e.border then FrameIcon(tex, zacui) end
end

function Look.CropIcon(tex, w, h, opts)
    if not (tex and tex.SetTexCoord) then return tex end
    opts = opts or {}
    local e = cropped[tex]
    if not e then
        e = {}
        cropped[tex] = e
        -- framed only when the caller asks (opts.border = true) and nothing
        -- frames it yet: ZacUI's buttons already carry their own 1px edge,
        -- and a second frame doubled it (the consumables bars)
        local host = tex.GetParent and tex:GetParent()
        e.border = opts.border == true and not (host and rawget(host, "_zui_borderTex"))
    end
    e.w, e.h, e.part = w or e.w, h or e.h, opts.part or e.part
    if opts.minCrop ~= nil then e.minCrop = tonumber(opts.minCrop) end
    -- drawn inside Look.With (a preview of another look), or a settings
    -- window's icon (opts.look = "zacui": settings never change look):
    -- keeps that look
    e.look = (opts.look and LOOKS[opts.look] and opts.look) or (forced and forced.id) or e.look
    ApplyCrop(tex, e)
    return tex
end

-- an icon whose crop is the player's own again (a zoom set by hand on a
-- bar or the buffs): the helper lets go of it
function Look.ForgetIcon(tex)
    if tex then cropped[tex] = nil end
end

-- the zoom changed (the Icon zoom slider): every icon cropped so far again
function Look.RecropAll()
    for tex, e in pairs(cropped) do pcall(ApplyCrop, tex, e) end
end

-- The Icon zoom slider's preview: a few spell icons at 12 to 64 px, in
-- the live look, cropped by the helper (so the slider re-crops them).
local SAMPLE_ICONS = { 132333, 136243, 135358, 134830, 133035, 132109 }
local SAMPLE_SIZES = { 12, 16, 24, 32, 48, 64 }
function Look.IconSamples(parent)
    local f = CreateFrame("Frame", nil, parent)
    local x, gap = 0, 8
    for i, size in ipairs(SAMPLE_SIZES) do
        local holder = CreateFrame("Frame", nil, f)
        holder:SetSize(size, size)
        holder:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 0)
        local t = holder:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints()
        t:SetTexture(SAMPLE_ICONS[(i - 1) % #SAMPLE_ICONS + 1])
        Look.CropIcon(t, size, size)
        x = x + size + gap
    end
    f:SetSize(x - gap, SAMPLE_SIZES[#SAMPLE_SIZES])
    return f
end

-- ============================================================
-- EDGE BORDERS (the classic branch of AddPixelBorder lives here, so the
-- primitive file keeps its pixel branch byte for byte)
-- ============================================================
-- A frame too small for the edge gets a smaller one: the art is drawn
-- at the edge size, and a 16px edge on a 12px plate bar is all edge.
local function EdgeSizeFor(frame, spec)
    local size = spec.edgeSize or 16
    local w = frame.GetWidth and frame:GetWidth() or 0
    local h = frame.GetHeight and frame:GetHeight() or 0
    local m = math.min(type(w) == "number" and w > 0 and w or 9999, type(h) == "number" and h > 0 and h or 9999)
    if m < 9999 and m < size * 2 then size = math.max(4, math.floor(m / 2)) end
    return size
end

-- Four proxy entries stand in frame._zui_borderTex for the four strips,
-- so TintBorder, AdoptQualityBorder, AB.TintButtonBorder and the per-side
-- walk in AB.StyleButton keep working untouched: colour goes to the one
-- backdrop's border colour, size and show/hide to the edge frame.
local Proxy = {}
Proxy.__index = Proxy
-- the nine pieces a NineSliceUtil layout hangs on its container
local NINE_KEYS = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge" }
local function TintEdge(e, r, g, b, a)
    if not e then return end
    if rawget(e, "_zNine") then
        for _, k in ipairs(NINE_KEYS) do
            local t = rawget(e, k)
            if type(t) == "table" and t.SetVertexColor then t:SetVertexColor(r or 1, g or 1, b or 1, a or 1) end
        end
    elseif e.SetBackdropBorderColor then
        e:SetBackdropBorderColor(r or 1, g or 1, b or 1, a or 1)
    end
end
Look.TintEdge = TintEdge

-- whether `spec` can be drawn as the client's own nine-slice on `frame`:
-- the utility, the layout and its corner art exist, and the frame is big
-- enough for the pieces (the art has a size of its own)
local function NineFor(frame, spec)
    local name = spec and spec.nineslice
    if not name then return nil end
    local util, layouts = rawget(_G, "NineSliceUtil"), rawget(_G, "NineSliceLayouts")
    if type(util) ~= "table" or type(util.ApplyLayoutByName) ~= "function" or type(layouts) ~= "table" then return nil end
    local layout = layouts[name]
    if type(layout) ~= "table" then return nil end
    local corner = layout.TopLeftCorner and layout.TopLeftCorner.atlas
    if corner and C_Texture and C_Texture.GetAtlasInfo and not C_Texture.GetAtlasInfo(corner) then return nil end
    local w = frame.GetWidth and frame:GetWidth() or 0
    local h = frame.GetHeight and frame:GetHeight() or 0
    local m = math.min(type(w) == "number" and w > 0 and w or 9999, type(h) == "number" and h > 0 and h or 9999)
    if spec.minSize and m < spec.minSize then return nil end
    return name
end
Look.NineFor = NineFor

function Proxy:SetColorTexture(r, g, b, a)
    TintEdge(self.edge, r, g, b, a)
end
function Proxy:SetVertexColor(r, g, b, a) return self:SetColorTexture(r, g, b, a) end
function Proxy:SetHeight() end
function Proxy:SetWidth() end
function Proxy:SetAlpha(a) if self.edge then self.edge:SetAlpha(a) end end
function Proxy:Show() if self.edge then self.edge:Show() end end
function Proxy:Hide() if self.edge then self.edge:Hide() end end
function Proxy:IsShown() return self.edge and self.edge:IsShown() or false end
function Proxy:SetPoint() end
function Proxy:ClearAllPoints() end
function Proxy:SetTexture() end
function Proxy:SetDrawLayer() end

-- The edge on `frame`: a BackdropTemplate child wearing spec.file at the
-- edge size, white (the art's own gold); `r,g,b,a` tint it (quality,
-- selection, the accent). Re-calling re-tints. Returns the edge frame.
function Look.AddEdge(frame, spec, r, g, b, a)
    local edge = frame._zui_edge
    if not edge then
        edge = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        edge:SetAllPoints(frame)
        local lvl = frame.GetFrameLevel and frame:GetFrameLevel() or 0
        edge:SetFrameLevel(lvl + 1)
        if edge.EnableMouse then edge:EnableMouse(false) end
        frame._zui_edge = edge
        local strips = frame._zui_borderTex or {}
        frame._zui_borderTex = strips
        strips._zEdge = true
        for i = 1, 4 do strips[#strips + 1] = setmetatable({ edge = edge, side = i }, Proxy) end
    end
    -- a modern look: the client's own nine-slice (Blizzard's layout by
    -- name), the frame's box grown by the rim's reach
    local nine = NineFor(frame, spec)
    if nine then
        if rawget(edge, "_zNine") ~= nine then
            if edge.SetBackdrop then pcall(edge.SetBackdrop, edge, nil) end
            local out = spec.out or 0
            edge:ClearAllPoints()
            edge:SetPoint("TOPLEFT", frame, "TOPLEFT", -out, out)
            edge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", out, -out)
            pcall(NineSliceUtil.ApplyLayoutByName, edge, nine)
            rawset(edge, "_zNine", nine)
        end
        -- a BORDER only: the layout's own Center piece (a tooltip's fill)
        -- would sit over the frame's content - a nameplate's health fill
        -- read as an empty grey bar under WoW Forever (2026-11-08). AddFill
        -- shows it again where a fill is wanted.
        local center = rawget(edge, "Center")
        if center and center.Hide and not rawget(edge, "_zFillOn") then center:Hide() end
        TintEdge(edge, r, g, b, a)
        rawset(edge, "_zEdgeSpec", spec)
        return edge
    end
    local size = EdgeSizeFor(frame, spec)
    local inset = spec.inset or 4
    if size < (spec.edgeSize or 16) then inset = math.max(1, math.floor(inset * size / (spec.edgeSize or 16))) end
    -- a rim that must not cover the frame's own content (a window cover's
    -- title and corner buttons) sits outside the box by spec.out
    if spec.out and not rawget(edge, "_zNine") then
        edge:ClearAllPoints()
        edge:SetPoint("TOPLEFT", frame, "TOPLEFT", -spec.out, spec.out)
        edge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", spec.out, -spec.out)
    end
    if edge.SetBackdrop then
        edge:SetBackdrop({ edgeFile = spec.file, edgeSize = size,
            insets = { left = inset, right = inset, top = inset, bottom = inset } })
    end
    if edge.SetBackdropBorderColor then edge:SetBackdropBorderColor(r or 1, g or 1, b or 1, a or 1) end
    rawset(edge, "_zEdgeSpec", spec)
    return edge
end

-- The fill of a classic box: the look's background file as a backdrop on
-- the same edge frame (one SetBackdrop carries both), at alpha.
function Look.AddFill(frame, spec, file, alpha)
    local edge = Look.AddEdge(frame, spec)
    -- a modern nine-slice: its Center piece is the small box's fill; a
    -- window rim has none, so the window's file is laid inside the rim
    if rawget(edge, "_zNine") then
        rawset(edge, "_zFillOn", true)
        local center = rawget(edge, "Center")
        if center and center.Show then center:Show() end
        local bg = rawget(edge, "_zBg")
        if not rawget(edge, "Center") then
            if not bg then
                bg = edge:CreateTexture(nil, "BACKGROUND", nil, -8)
                bg._zui_own = true
                rawset(edge, "_zBg", bg)
            end
            local inset = (spec.out or 0) + (spec.inset or 0)
            bg:ClearAllPoints()
            bg:SetPoint("TOPLEFT", edge, "TOPLEFT", inset, -inset)
            bg:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", -inset, inset)
            bg:SetTexture(file, true, true)
            if bg.SetHorizTile then bg:SetHorizTile(true) bg:SetVertTile(true) end
            bg:SetVertexColor(1, 1, 1, alpha or 1)
        end
        if not rawget(edge, "SetVertexColor") then
            rawset(edge, "SetVertexColor", function(self, r, g, b, a)
                local t = rawget(self, "_zBg") or rawget(self, "Center")
                if t and t.SetVertexColor then t:SetVertexColor(r or 1, g or 1, b or 1, a or 1) end
            end)
        end
        return edge
    end
    local size = EdgeSizeFor(frame, spec)
    local inset = spec.inset or 4
    if size < (spec.edgeSize or 16) then inset = math.max(1, math.floor(inset * size / (spec.edgeSize or 16))) end
    if edge.SetBackdrop then
        edge:SetBackdrop({ bgFile = file, edgeFile = spec.file, edgeSize = size, tile = true, tileSize = 32,
            insets = { left = inset, right = inset, top = inset, bottom = inset } })
    end
    if edge.SetBackdropColor then edge:SetBackdropColor(1, 1, 1, alpha or 1) end
    if edge.SetBackdropBorderColor then edge:SetBackdropBorderColor(1, 1, 1, 1) end
    -- the callers that retint a fill (frame._zui_cbg:SetVertexColor) find
    -- the same method here, onto the backdrop's colour
    if not rawget(edge, "SetVertexColor") then
        rawset(edge, "SetVertexColor", function(self, r, g, b, a)
            if self.SetBackdropColor then self:SetBackdropColor(r or 1, g or 1, b or 1, a or 1) end
        end)
    end
    return edge
end

-- ============================================================
-- PENDING CHOICE (the General card and the setup wizard stage here)
-- ============================================================
local pending = { global = nil, parts = nil }

function Look.Set(id)
    if not Valid(id) or not Look.Offered(id) then return false end
    pending.global = id
    return true
end

function Look.SetPart(part, id)
    if not PART_OK[part] then return false end
    pending.parts = pending.parts or {}
    if id == nil or id == "" or id == "follow" then
        pending.parts[part] = false         -- staged: follow the look
    elseif Valid(id) and Look.Offered(id) then
        pending.parts[part] = id
    else
        return false
    end
    return true
end

function Look.Pending() return pending.global end
function Look.PendingParts() return pending.parts end

-- what the part would wear once applied: pending over live
function Look.PendingFor(part)
    local p = pending.parts and pending.parts[part]
    if p == false then return nil end
    if p then return p end
    local live = Look.ActiveParts()[part]
    return live
end

function Look.Discard()
    pending.global, pending.parts = nil, nil
end

function Look.Dirty()
    local a = Live() or { global = "zacui", parts = {} }
    if pending.global and pending.global ~= a.global then return true end
    if pending.parts then
        for k, v in pairs(pending.parts) do
            local live = a.parts[k]
            if v == false then
                if live ~= nil then return true end
            elseif v ~= live then
                return true
            end
        end
    end
    return false
end

-- THE ONE WRITER. Called from the reload confirm (and the wizard's own
-- reload step) only; the live tables are untouched until the reload.
function Look.Commit()
    if type(ZacUIDB) ~= "table" then return false end
    local a = Live() or { global = "zacui", parts = {} }
    local out = { global = pending.global or a.global, parts = {} }
    for k, v in pairs(a.parts) do out.parts[k] = v end
    if pending.parts then
        for k, v in pairs(pending.parts) do
            if v == false then out.parts[k] = nil else out.parts[k] = v end
        end
    end
    -- shipped state saves as nothing at all
    if out.global == "zacui" and next(out.parts) == nil then
        ZacUIDB.look = nil
    else
        ZacUIDB.look = out
    end
    pending.global, pending.parts = nil, nil
    -- a look was chosen: the first-run look popup never asks after this
    -- (account-wide bookkeeping, outside every profile)
    if type(ZacUIDB.tutorial) == "table" then ZacUIDB.tutorial.lookPicked = true end
    return true
end

-- What a part wears once the pending choice is applied: its own staged or
-- saved look, else the staged or live global one.
function Look.EffectiveFor(part)
    return Look.PendingFor(part) or Look.Pending() or Look.Active()
end

-- What a part wears now (the latched session): its saved override, else
-- the live global look.
function Look.LiveFor(part)
    return Look.ActiveParts()[part] or Look.Active()
end

-- Stage one look for EVERY part: the global look, and every part
-- override dropped. Nothing is written (the caller's confirm commits).
function Look.StageEverywhere(id)
    if not Look.Set(id) then return false end
    for _, p in ipairs(Look.PARTS) do Look.SetPart(p.key, "follow") end
    return true
end

-- Stage one part into a look: an override only where it differs from the
-- staged global look, so a part that matches it simply follows.
function Look.StagePart(part, id)
    if not Look.Offered(id) then return false end
    local global = Look.Pending() or Look.Active()
    return Look.SetPart(part, id == global and "follow" or id)
end

-- The look every part wears live, or nil while the parts are mixed.
function Look.LiveUniform()
    local g = Look.Active()
    for _, p in ipairs(Look.PARTS) do
        if Look.LiveFor(p.key) ~= g then return nil end
    end
    return g
end

-- the looks offered here, in card order
function Look.Choices()
    local out = {}
    for _, id in ipairs(ORDER) do
        local l = LOOKS[id]
        if Look.Offered(id) then
            out[#out + 1] = { id = l.id, name = l.name, tag = l.tag, desc = l.desc }
        end
    end
    return out
end

-- ============================================================
-- THE MINIATURE
-- ============================================================
-- A sample of a look at w x h (default 168 x 104: the Style cards'
-- stage), drawn by the real primitives under Look.With, so it shows what
-- the look really draws: a player frame (its box, health and power bars,
-- a name; WoW Forever's round level badge), a bar of four action buttons
-- (ZacUI's cropped icons in pixel frames, the vanilla Quickslot rings, or
-- the client's modern ring; WoW Forever's gryphons at its ends, as its
-- first bar wears them) and a cast bar. The stage around it is the
-- caller's (a card): nothing here is settings chrome. frame._zPaint
-- repaints the colours (the Colours page calls it like any widget's).
local SAMPLE_ICONS4 = { 132333, 136243, 132109, 135358 }   -- shout, strike, rend, execute
local MODERN_RING = "UI-HUD-ActionBar-IconFrame"

local function AtlasOK(name)
    return name and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) and true or false
end
Look.AtlasOK = AtlasOK

function Look.Preview(parent, id, w, h)
    w, h = w or 168, h or 104
    local look = LOOKS[id] or LOOKS.zacui
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)
    rawset(f, "_zLookId", look.id)
    local paint = {}

    Look.With(look.id, function()
        local SkinStatusBar, SkinBackdrop = ns.SkinStatusBar, ns.SkinBackdrop
        local AddPixelBorder = ns.AddPixelBorder
        local edged = look.border.style == "edge"
        -- the miniature's texts: a game-font look shows the game's face on
        -- purpose (marked, so the one-font sweep leaves it be); ZacUI's
        -- shows the chosen font and follows a change of it (a house string)
        local function ZacFace()
            local cfg = type(ZacUIDB) == "table" and ZacUIDB.font
            return (cfg and cfg.name and ns.ResolveFontPath and ns.ResolveFontPath(cfg.name)) or ns.GAME_FONT
        end
        local function Text(host, size, txt)
            local fs = host:CreateFontString(nil, "OVERLAY")
            if look.font == "game" then
                fs:SetFont(ns.GAME_FONT, size, "")
                fs:SetShadowOffset(1, -1)
                rawset(fs, "_zOwnFace", true)
            else
                local function Dress(s)
                    local okf, set = pcall(s.SetFont, s, ZacFace(), size, "OUTLINE")
                    if not (okf and set) then s:SetFont(ns.GAME_FONT, size, "OUTLINE") end
                end
                Dress(fs)
                if ns.TrackHouseFont then ns.TrackHouseFont(fs, Dress) end
            end
            fs:SetText(txt)
            return fs
        end

        -- the player frame, centred at the top: under a game look the kit
        -- ZacUI's unit frames wear in it (Zacui_UnitFrames/Kit.lua: the
        -- frame sheet, the round portrait, the bars in the art's tracks, the
        -- name and the level), drawn small; ZacUI's own flat frame else
        local fh
        local kits = look.id ~= "zacui" and ns.UFKit and ns.UFKit.KITS
        local kit = kits and (kits[look.id] or kits.classic)
        local G = kit and kit.player
        if G and G.atlas and not AtlasOK(G.atlas) then kit = kits.classic G = kit.player end
        if G then
            local s = math.min((w * 0.86) / G.w, (h * 0.5) / G.h)
            local box = CreateFrame("Frame", nil, f)
            box:SetSize(G.w, G.h)
            box:SetScale(s)
            box:SetPoint("TOP", f, "TOP", 0, -2 / s)
            fh = G.h * s
            local base = box:GetFrameLevel()
            -- the portrait in the ring (your own face), under the art
            local pf = CreateFrame("Frame", nil, box)
            pf:SetFrameLevel(base + 1)
            pf:SetSize(G.portrait.size, G.portrait.size)
            pf:SetPoint(G.portrait.point, box, G.portrait.point, G.portrait.x, G.portrait.y)
            local face = pf:CreateTexture(nil, "ARTWORK")
            face:SetAllPoints(pf)
            if SetPortraitTexture and UnitExists and UnitExists("player") then SetPortraitTexture(face, "player")
            else face:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
            if pf.CreateMaskTexture and face.AddMaskTexture then
                local m = pf:CreateMaskTexture()
                m:SetAllPoints(pf)
                local mask = G.portrait.mask
                if mask and AtlasOK(mask) then ns.UFKit.SetMask(m, mask, false, kit.id)
                else m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") end
                face:AddMaskTexture(m)
            end
            -- the plaque and the bars in the tracks, in the game's bar texture
            if G.back then
                local bk = box:CreateTexture(nil, "BACKGROUND")
                bk:SetColorTexture(0, 0, 0, 0.5)
                bk:SetPoint("TOPLEFT", box, "TOPLEFT", G.back.x, -G.back.y)
                bk:SetSize(G.back.w, G.back.h)
            end
            local function KitBar(B, v, r, g, b)
                local sb = CreateFrame("StatusBar", nil, box)
                sb:SetFrameLevel(base + (kit.artAbove and 2 or 4))
                sb:SetPoint("TOPLEFT", box, "TOPLEFT", B.x, -B.y)
                sb:SetSize(B.w, B.h)
                sb:SetStatusBarTexture(look.barTexture or STATUSBAR)
                sb:SetMinMaxValues(0, 1)
                sb:SetValue(v)
                sb:SetStatusBarColor(r, g, b, 1)
                return sb
            end
            f.health = KitBar(G.health, 0.72, 0, 1, 0)
            f.power = KitBar(G.power, 0.45, 0.25, 0.45, 0.9)
            -- the art: over the bars (classic) or under them (modern)
            local af = CreateFrame("Frame", nil, box)
            af:SetAllPoints(box)
            af:SetFrameLevel(base + (kit.artAbove and 3 or 2))
            local art = af:CreateTexture(nil, "ARTWORK")
            if G.atlas then
                -- (Blizzard style on WoW Forever: the retail art, as the
                -- frames paint it - Kit.lua's SetArt)
                ns.UFKit.SetArt(art, G.atlas, true, kit.id)
                art:SetPoint("CENTER", box, "CENTER", 0, 0)
            else
                local A = G.art
                art:SetTexture(A.file)
                art:SetTexCoord(A.l, A.r, A.t, A.b)
                art:SetSize(A.w, A.h)
                art:SetPoint(A.point or "CENTER", box, A.point or "CENTER", A.x or 0, A.y or 0)
            end
            f.kitArt = art
            local tf = CreateFrame("Frame", nil, box)
            tf:SetAllPoints(box)
            tf:SetFrameLevel(base + 6)
            local nm = Text(tf, 12, UnitName and UnitName("player") or "Zac")
            nm:SetPoint(G.name.point, box, G.name.point, G.name.x, G.name.y)
            nm:SetTextColor(1, 0.82, 0, 1)
            local L = G.level
            if L then
                local rel, relPoint = box, L.relPoint or L.point
                if G.badge and AtlasOK(G.badge.atlas) then
                    local bd = tf:CreateTexture(nil, "OVERLAY", nil, -1)
                    bd:SetAtlas(G.badge.atlas)
                    bd:SetSize(G.badge.size, G.badge.size)
                    bd:SetPoint(G.badge.point, box, G.badge.point, G.badge.x, G.badge.y)
                    rel, relPoint = bd, "CENTER"
                    f.badge = bd
                end
                local lv = Text(tf, 12, tostring((UnitLevel and UnitLevel("player")) or 60))
                lv:SetPoint(L.point, rel, relPoint, L.x, L.y)
                lv:SetTextColor(1, 0.82, 0, 1)
            end
            f.unitFrame = box
        else
            -- the player frame, centred at the top
            local fw = math.floor(w * 0.68)
            fh = math.max(26, math.floor(h * 0.32))
            local uf = CreateFrame("Frame", nil, f, "BackdropTemplate")
            uf:SetSize(fw, fh)
            uf:SetPoint("TOP", f, "TOP", look.badge and 6 or 0, -8)
            if SkinBackdrop then SkinBackdrop(uf, "elementBg", 0.95, "unitframes") end
            local inner = edged and 4 or 1
            local hp = CreateFrame("StatusBar", nil, uf)
            hp:SetPoint("TOPLEFT", uf, "TOPLEFT", inner, -inner)
            hp:SetPoint("TOPRIGHT", uf, "TOPRIGHT", -inner, -inner)
            hp:SetHeight(math.max(6, math.floor((fh - inner * 2) * 0.64)))
            hp:SetMinMaxValues(0, 1)
            hp:SetValue(0.72)
            if SkinStatusBar then SkinStatusBar(hp, { look = "unitframes", border = false }) end
            local cc = RAID_CLASS_COLORS and UnitClass and RAID_CLASS_COLORS[select(2, UnitClass("player"))]
            hp:SetStatusBarColor(cc and cc.r or 0.78, cc and cc.g or 0.61, cc and cc.b or 0.43, 1)
            local pw = CreateFrame("StatusBar", nil, uf)
            pw:SetPoint("TOPLEFT", hp, "BOTTOMLEFT", 0, edged and -1 or -1)
            pw:SetPoint("TOPRIGHT", hp, "BOTTOMRIGHT", 0, -1)
            pw:SetPoint("BOTTOM", uf, "BOTTOM", 0, inner)
            pw:SetMinMaxValues(0, 1)
            pw:SetValue(0.45)
            if SkinStatusBar then SkinStatusBar(pw, { look = "unitframes", border = false }) end
            pw:SetStatusBarColor(0.25, 0.45, 0.9, 1)
            local name = Text(hp, 9, UnitName and UnitName("player") or "Zac")
            name:SetPoint("LEFT", hp, "LEFT", 3, 0)
            name:SetTextColor(1, 1, 1, 1)
            f.unitFrame = uf
            -- WoW Forever's round level badge on the frame's corner
            local art = look.art
            if art and art.badge and AtlasOK(art.badge) then
                local b = uf:CreateTexture(nil, "OVERLAY", nil, 6)
                b:SetSize(20, 20)
                b:SetPoint("CENTER", uf, "BOTTOMLEFT", 0, 2)
                b:SetAtlas(art.badge, false)
                local lv = Text(uf, 8, "60")
                lv:SetPoint("CENTER", b, "CENTER", 0, 0)
                f.badge = b
            end


        end
        -- the bar of four buttons
        local n, bs, gap = 4, math.max(14, math.floor(h * 0.19)), 4
        local rowW = n * bs + (n - 1) * gap
        -- (the kit's box carries the art's own transparent margin: tighter)
        local barTop = G and -(fh + 4) or -(8 + fh + 10)
        f.buttons = {}
        for i = 1, n do
            local btn = CreateFrame("Button", nil, f)
            btn:SetSize(bs, bs)
            btn:SetPoint("TOPLEFT", f, "TOP", -rowW / 2 + (i - 1) * (bs + gap), barTop)
            local icon = btn:CreateTexture(nil, "BACKGROUND")
            icon:SetAllPoints()
            icon:SetTexture(SAMPLE_ICONS4[i])
            btn.icon = icon
            if look.iconButton == "stock" then
                local ring = btn:CreateTexture(nil, "ARTWORK")
                if look.iconRing then
                    ring:SetTexture(look.iconRing.normal)
                    local rs = bs * look.iconRing.scale
                    ring:SetSize(rs, rs)
                    ring:SetPoint("CENTER", btn, "CENTER", 0, bs * look.iconRing.dy)
                elseif AtlasOK(MODERN_RING) then
                    ring:SetAtlas(MODERN_RING, false)
                    ring:SetPoint("TOPLEFT", btn, "TOPLEFT", -2, 2)
                    ring:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -2)
                else
                    -- the modern ring is not on this client: the vanilla one
                    local q = LOOKS.classic.iconRing
                    ring:SetTexture(q.normal)
                    ring:SetSize(bs * q.scale, bs * q.scale)
                    ring:SetPoint("CENTER", btn, "CENTER", 0, bs * q.dy)
                end
                btn._zRing = ring
                icon:SetTexCoord(0, 1, 0, 1)
            else
                if AddPixelBorder then AddPixelBorder(btn, nil, nil, "bars") end
                Look.CropIcon(icon, bs, bs, { border = false })
            end
            f.buttons[i] = btn
        end
        f.button = f.buttons[1]
        -- WoW Forever's gryphons at the bar's ends (its first bar wears them)
        if look.gryphons and art then
            for side = 1, 2 do
                local an = side == 1 and art.gryphonLeft or art.gryphonRight
                local info = AtlasOK(an) and C_Texture.GetAtlasInfo(an)
                if info then
                    local gh = bs + 8
                    local gw = (info.width and info.height and info.height > 0) and gh * info.width / info.height or gh
                    local g = f:CreateTexture(nil, "ARTWORK", nil, 2)
                    g:SetSize(gw, gh)
                    if side == 1 then
                        g:SetPoint("BOTTOMRIGHT", f, "TOP", -rowW / 2 + 4, barTop - bs - 2)
                    else
                        g:SetPoint("BOTTOMLEFT", f, "TOP", rowW / 2 - 4, barTop - bs - 2)
                    end
                    g:SetAtlas(an, false)
                    f["gryphon" .. side] = g
                end
            end
        end

        -- the cast bar along the bottom
        local cb = CreateFrame("StatusBar", nil, f)
        cb:SetSize(math.floor(w * 0.76), math.max(8, math.floor(h * 0.1)))
        cb:SetPoint("BOTTOM", f, "BOTTOM", 0, 8)
        cb:SetMinMaxValues(0, 1)
        cb:SetValue(0.6)
        if SkinStatusBar then SkinStatusBar(cb, { look = "unitframes" }) end
        cb:SetStatusBarColor(1, 0.7, 0, 1)
        local ct = Text(cb, 7, "Slam")
        ct:SetPoint("CENTER")
        ct:SetTextColor(1, 1, 1, 1)
        f.castBar = cb
    end)

    f._zPaint = function(self)
        for _, fn in ipairs(paint) do pcall(fn) end
    end
    return f
end
