-- Core_Fonts - the global font-object system. One place decides which
-- font face, size delta and outline every Blizzard font object wears.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME, ns = ...

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
local function ApplyFonts()
    local cfg = ZacUIDB and ZacUIDB.font
    if not cfg then return end
    local path = ResolveFontPath(cfg.name)
    local delta = cfg.delta or 0
    -- Deliberately NO early-out once anything has been applied: returning
    -- to defaults has to be able to walk the objects and put them back.
    if not path and delta == 0 and not cfg.outline and not next(fontBase) then
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
end


-- One string in the house font: the configured face (else whatever the
-- string already has, else `fallback`) at size + the font delta, with
-- `flags` (default: OUTLINE unless the outline option is NONE). Several
-- modules carried their own copy of exactly this.
local function HouseFont(fs, size, flags, fallback)
    if type(fs) ~= "table" or not fs.SetFont then return end
    local cfg = ZacUIDB and ZacUIDB.font or {}
    -- (a string made without a template has no font: the game's, then)
    local path = ResolveFontPath(cfg.name) or (fs.GetFont and fs:GetFont()) or fallback or STANDARD_TEXT_FONT
    if not path then return end
    if flags == nil then flags = (cfg.outline == "NONE") and "" or "OUTLINE" end
    -- a face whose file will not load returns false and leaves the string
    -- with no font (its next SetText errors): the fallback, then the game's
    local ok, set = pcall(fs.SetFont, fs, path, size + (cfg.delta or 0), flags)
    if not (ok and set) then
        ok, set = pcall(fs.SetFont, fs, fallback or STANDARD_TEXT_FONT, size + (cfg.delta or 0), flags)
        if not (ok and set) then pcall(fs.SetFont, fs, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size + (cfg.delta or 0), flags) end
    end
end

-- shared with later ZacUI files
ns.ApplyFonts = ApplyFonts
ns.ResolveFontPath = ResolveFontPath
ns.HouseFont = HouseFont
