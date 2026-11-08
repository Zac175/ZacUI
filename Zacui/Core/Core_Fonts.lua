-- Core_Fonts - the global font-object system. One place decides which
-- font face, size delta and outline every Blizzard font object wears.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME, ns = ...

-- The game's own font, as the client set it before ZacUI's font replaced
-- STANDARD_TEXT_FONT at load: what "Blizzard default" means for the rest
-- of the session.
ns.GAME_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
-- STANDARD_TEXT_FONT handed in as "the game's font" by a caller: once
-- ZacUI's font has replaced it at load, that is ZacUI's font of the time
function ns.GameFace(p)
    if p ~= nil and p == STANDARD_TEXT_FONT then return ns.GAME_FONT end
    return p
end

-- THE LOOK'S FACE (Core_Look, which loads after this file, so it is looked
-- up when asked). Under the Classic look the world's texts wear the game's
-- own font whatever Fonts & Textures says: `part` is whose text (nil: the
-- global look). The /zui window (FontDress, UIF_Controls) and Readycheck
-- (Media.FontName) never come through here, so they keep the chosen font.
local function LookGameFont(part)
    local L = ns.Look
    if L and L.For(part).font == "game" then return ns.GAME_FONT end
    return nil
end

-- ============================================================
-- FONT SYSTEM (/zacui font|fontsize|fontoutline|fontlist)
-- ============================================================
local FONT_OBJECTS = {
    "GameFontNormal", "GameFontNormalSmall", "GameFontNormalLarge", "GameFontNormalHuge",
    "GameFontHighlight", "GameFontHighlightSmall", "GameFontHighlightLarge",
    "GameFontDisable", "GameFontDisableSmall", "GameFontDisableLarge",
    "GameFontGreen", "GameFontGreenSmall", "GameFontRed", "GameFontRedSmall",
    "GameFontWhite", "GameFontBlack", "GameFontNormalMed3",
    "NumberFontNormal", "NumberFontNormalSmall", "NumberFontNormalLarge", "NumberFontNormalHuge",
    "QuestFont", "QuestFontNormalSmall", "QuestTitleFont", "QuestFontHighlight",
    "DialogButtonNormalText", "DialogButtonHighlightText",
    "ZoneTextFont", "SubZoneTextFont", "PVPInfoTextFont", "ErrorFont",
    "TextStatusBarText", "CombatLogFont",
    "GameTooltipText", "GameTooltipTextSmall", "GameTooltipHeaderText",
    "ChatFontNormal", "ChatFontSmall",
    "SystemFont_Tiny", "SystemFont_Small", "SystemFont_Med1", "SystemFont_Med3",
    "SystemFont_Large", "SystemFont_Huge1",
    "SystemFont_Shadow_Small", "SystemFont_Shadow_Med1", "SystemFont_Shadow_Med3",
    "SystemFont_Shadow_Large", "SystemFont_Shadow_Huge1",
    "SystemFont_Outline_Small", "SystemFont_OutlineThick_Huge2",
    "FriendsFont_Normal", "FriendsFont_Small", "FriendsFont_Large",
}

-- A SharedMedia name LSM knows -> its file; a file path -> itself.
-- Anything else is nil: a font name whose addon is gone (an imported
-- profile naming "Merfin Font 1", say) used to come back unchanged, and
-- SetFont on a bare name throws - which took whole frames down with it.
-- Every caller already falls back on nil.
local function LooksLikeFontFile(s)
    if s:find("\\", 1, true) or s:find("/", 1, true) then return true end
    local l = s:lower()
    return l:match("%.ttf$") ~= nil or l:match("%.otf$") ~= nil
end
local function ResolveFontPath(nameOrPath)
    if type(nameOrPath) ~= "string" or nameOrPath == "" then return nil end
    -- a font saved under the name of one ZacUI used to carry (Core_MediaNames)
    if ns.NewMediaName then nameOrPath = ns.NewMediaName(nameOrPath) or nameOrPath end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local fetched = LSM:Fetch("font", nameOrPath, true)
        if fetched then return fetched end
    end
    if LooksLikeFontFile(nameOrPath) then return nameOrPath end
    -- one of ZacUI's own, by name, when SharedMedia does not have it
    for _, f in ipairs(ns.MEDIA_FONTS or {}) do
        if f.name == nameOrPath then return f.path end
    end
    return nil
end

-- BASELINE CACHE. Two problems, one cache.
--
--   SIZE: delta used to be added to the CURRENT size on every call, so
--   each slider notch stacked on the last one (0->+2 then +2->+4 landed
--   at +6). Size is always computed base + delta, so re-applying is
--   idempotent.
--
--   PATH: the same argument applies to the typeface, and missing it was
--   why "Blizzard default" did not undo anything - with no cached
--   original, `path or curPath` fell back to the CUSTOM font that was
--   already applied, and the only way back was a reload. The stock path
--   is captured on first touch alongside the stock size.
local fontBase = {}

-- THE ONE FONT, KEPT UP. Every string ZacUI dresses in its font (HouseFont,
-- UI.Font, ns.ApplyFontSpec with no face of its own, a part's own helper
-- through ns.TrackHouseFont) is remembered here, weakly, with how to dress
-- it again; a change of the font, its size or its outline re-dresses them
-- all at once - on the change, never per frame. A string something else
-- has since given a face of its own (a part's own pick) is left alone:
-- only one still wearing the face it was last given here is redone.
local houseStrings = setmetatable({}, { __mode = "k" })
local function TrackHouseFont(fs, redo)
    if type(fs) ~= "table" or not fs.GetFont then return end
    if redo == nil then houseStrings[fs] = nil return end
    houseStrings[fs] = redo
    rawset(fs, "_zHouseFace", (fs:GetFont()))
end
local function ReapplyHouseFonts()
    local list = {}
    for fs in pairs(houseStrings) do list[#list + 1] = fs end
    local n = 0
    for _, fs in ipairs(list) do
        local redo = houseStrings[fs]
        local last = rawget(fs, "_zHouseFace")
        if redo and (last == nil or fs:GetFont() == last) then
            if pcall(redo, fs) then n = n + 1 end
            -- (what it wears now is what the next change looks for)
            if houseStrings[fs] then rawset(fs, "_zHouseFace", (fs:GetFont())) end
        end
    end
    return n
end
-- what the strings were last dressed for: a re-dress runs only when it moved
local houseEpoch
local function FontEpoch()
    local cfg = ZacUIDB and ZacUIDB.font or {}
    return tostring(ResolveFontPath(cfg.name)) .. "/" .. tostring(cfg.delta or 0) .. "/" .. tostring(cfg.outline)
end

-- The face a string had before ZacUI's font reached it, kept on the string
-- the first time it is asked: what "Blizzard default" puts back. A string
-- made from one of the game's font objects that ZacUI already dressed
-- answers that object's stock face, not ZacUI's.
local function HouseOrig(fs)
    local o = rawget(fs, "_zHouseOrig")
    if o ~= nil then return o or nil end
    local cur = fs.GetFont and fs:GetFont()
    local fo = fs.GetFontObject and fs:GetFontObject()
    if type(fo) == "string" then fo = _G[fo] end
    if fo then
        for objName, base in pairs(fontBase) do
            if _G[objName] == fo then cur = base.path or cur break end
        end
    end
    local cfg = ZacUIDB and ZacUIDB.font or {}
    local house = ResolveFontPath(cfg.name)
    if cur and house and cur == house then cur = ns.GAME_FONT end
    rawset(fs, "_zHouseOrig", cur or false)
    return cur
end

local function ApplyFonts()
    local cfg = ZacUIDB and ZacUIDB.font
    if not cfg then return end
    local path = ResolveFontPath(cfg.name)
    -- Classic look: the game's font objects keep their stock face (size
    -- and outline still follow the sliders)
    if LookGameFont(nil) then path = nil end
    local delta = cfg.delta or 0
    -- Deliberately NO early-out once anything has been applied: returning
    -- to defaults has to be able to walk the objects and put them back.
    if not path and delta == 0 and not cfg.outline and not next(fontBase) then
        houseEpoch = houseEpoch or FontEpoch()
        return
    end

    for _, objName in ipairs(FONT_OBJECTS) do
        local obj = _G[objName]
        if obj and obj.GetFont then
            local curPath, curSize, curFlags = obj:GetFont()
            local base = fontBase[objName]
            if not base then
                base = { path = curPath, size = curSize or 12, flags = curFlags }
                fontBase[objName] = base
            end
            local newFlags = base.flags
            if cfg.outline == "OUTLINE" then
                newFlags = "OUTLINE"
            elseif cfg.outline == "NONE" then
                newFlags = ""
            end
            -- SetFont refuses a nil path and silently keeps the old font,
            -- so a font object we somehow have no baseline for is skipped
            -- rather than half-applied.
            local usePath = path or base.path or curPath
            if usePath then
                -- a face whose file will not load returns false and leaves
                -- the object with no font - and every string the game made
                -- from it then errors on SetText: put the stock face back
                local ok, set = pcall(obj.SetFont, obj, usePath, base.size + delta, newFlags)
                if not (ok and set) and base.path and base.path ~= usePath then
                    pcall(obj.SetFont, obj, base.path, base.size + delta, newFlags)
                end
            end
        end
    end
    -- and every string ZacUI dressed itself, when the font moved
    local epoch = FontEpoch()
    if houseEpoch ~= nil and epoch ~= houseEpoch then ReapplyHouseFonts() end
    houseEpoch = epoch
end


-- One string in the house font: the configured face (else whatever the
-- string already has, else `fallback`) at size + the font delta, with
-- `flags` (default: OUTLINE unless the outline option is NONE). Several
-- modules carried their own copy of exactly this.
local HouseFont
function HouseFont(fs, size, flags, fallback)
    if type(fs) ~= "table" or not fs.SetFont then return end
    local cfg = ZacUIDB and ZacUIDB.font or {}
    -- the face the string had before ZacUI's font first reached it: what
    -- "Blizzard default" puts back on a re-dress
    local orig = HouseOrig(fs)
    local askFlags = flags
    -- (a string made without a template has no font: the game's, then)
    local path = LookGameFont(nil) or ResolveFontPath(cfg.name) or orig or ns.GameFace(fallback) or ns.GAME_FONT
    if not path then return end
    if flags == nil then flags = (cfg.outline == "NONE") and "" or "OUTLINE" end
    -- a face whose file will not load returns false and leaves the string
    -- with no font (its next SetText errors): the fallback, then the game's
    local ok, set = pcall(fs.SetFont, fs, path, size + (cfg.delta or 0), flags)
    if not (ok and set) then
        ok, set = pcall(fs.SetFont, fs, fallback or STANDARD_TEXT_FONT, size + (cfg.delta or 0), flags)
        if not (ok and set) then pcall(fs.SetFont, fs, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size + (cfg.delta or 0), flags) end
    end
    -- (the flags as asked: nil follows the outline option on a re-dress too)
    TrackHouseFont(fs, function(s) HouseFont(s, size, askFlags, fallback) end)
end

-- A string ZacUI restyles but did not make (a Blizzard frame's name, a
-- message frame, a skinned label) or one a part sizes itself: ZacUI's
-- face when one is chosen, else the face the string had before ZacUI
-- first touched it (`fallback`, else the game's, for a string that had
-- none), at `size` (nil: the size it has) with `flags` (nil: the flags it
-- has). Kept up like every house string.
local function FollowFont(fs, size, flags, fallback)
    if type(fs) ~= "table" or not (fs.SetFont and fs.GetFont) then return end
    local curPath, curSize, curFlags = fs:GetFont()
    local orig = HouseOrig(fs)
    if not orig then
        orig = ns.GameFace(fallback) or ns.GAME_FONT
        rawset(fs, "_zHouseOrig", orig or false)
    end
    local cfg = ZacUIDB and ZacUIDB.font or {}
    local path = LookGameFont(nil) or ResolveFontPath(cfg.name) or orig or curPath
    if not path then return end
    local useSize, useFlags = size or curSize or 12, flags
    if useFlags == nil then useFlags = curFlags or "" end
    local ok, set = pcall(fs.SetFont, fs, path, useSize, useFlags)
    if not (ok and set) and orig and orig ~= path then pcall(fs.SetFont, fs, orig, useSize, useFlags) end
    TrackHouseFont(fs, function(s) FollowFont(s, size, flags, fallback) end)
end

-- THE ONE FACE. ZacUI's font, when one is chosen on Fonts & Textures: the
-- face of every text ZacUI draws, whatever a part, an element or an
-- imported aura asks for. nil while none is chosen (each text then wears
-- its own shipped face, the game's for most). Sizes, outlines and
-- shadows stay each text's own; only the face is forced.
-- `part`: whose text (a look part key, nil: the global look) - under the
-- Classic look the answer is the game's own font.
local function OneFace(part)
    local game = LookGameFont(part)
    if game then return game end
    local cfg = ZacUIDB and ZacUIDB.font
    return cfg and ResolveFontPath(cfg.name) or nil
end
-- the one face when chosen, else `fallback`
local function OneFaceOr(fallback, part) return OneFace(part) or fallback end

-- shared with later ZacUI files
ns.OneFace = OneFace
ns.OneFaceOr = OneFaceOr
ns.FollowFont = FollowFont
ns.ApplyFonts = ApplyFonts
ns.ResolveFontPath = ResolveFontPath
ns.HouseFont = HouseFont
ns.HouseOrig = HouseOrig
ns.TrackHouseFont = TrackHouseFont
ns.ReapplyHouseFonts = ReapplyHouseFonts
