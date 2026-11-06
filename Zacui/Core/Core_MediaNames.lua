-- Core_MediaNames - ZacUI's fonts and bar textures, and the names they
-- replaced.
-- Part of ZacUI; load order is set by the TOC (before Core_SharedMedia).
--
-- ZacUI's media is its own: the bar textures and icons are drawn for
-- ZacUI, and the fonts are open-licence faces (SIL Open Font License,
-- Media\Fonts\OFL.txt): Red Hat Display, Barlow Semi Condensed and
-- Roboto Condensed. Earlier versions carried fonts and textures from
-- other packs under those packs' names; a setting saved then still
-- names them. NAMES below is that list, old name -> the name of what
-- replaced it, and PATHS the same for file paths a setting may hold.
--
-- ns.MigrateMediaNames(t) walks a saved table and rewrites any value
-- that is exactly an old name or an old path. It runs once over
-- ZacUIDB and ZacUICharDB (Boot_Events, mediaRev) and over anything
-- imported later (a profile string, ZacLayout's copies).

local ADDON_NAME, ns = ...

local M = [[Interface\AddOns\ZacUI\Media\]]
local FONT_MAIN    = M .. [[Fonts\RedHatDisplay-SemiBold.ttf]]
local FONT_HEAVY   = M .. [[Fonts\BarlowSemiCondensed-Black.ttf]]
local FONT_NARROW  = M .. [[Fonts\RobotoCondensed-Bold.ttf]]

ns.MEDIA_FONTS = {
    { name = "Red Hat Display",             path = FONT_MAIN },
    { name = "Barlow Semi Condensed Black", path = FONT_HEAVY },
    { name = "Roboto Condensed Bold",       path = FONT_NARROW },
}
ns.MEDIA_BARS = {
    { name = "ZacUI Flat",         path = M .. [[Textures\bar_flat]] },
    { name = "ZacUI Smooth",       path = M .. [[normTex]] },
    { name = "ZacUI Fade Left",    path = M .. [[Textures\bar_fade_left]] },
    { name = "ZacUI Fade Right",   path = M .. [[Textures\bar_fade_right]] },
    { name = "ZacUI Tint",         path = M .. [[Textures\bar_tint]] },
    { name = "ZacUI Hover",        path = M .. [[Textures\bar_hover]] },
    { name = "ZacUI Hover Arrows", path = M .. [[Textures\bar_hover_arrows]] },
}
ns.MEDIA_FONT_MAIN, ns.MEDIA_FONT_HEAVY, ns.MEDIA_FONT_NARROW = FONT_MAIN, FONT_HEAVY, FONT_NARROW
ns.MEDIA_TEX_CHEVRON = M .. [[Textures\target_chevron]]

-- names saved by earlier ZacUI versions -> what replaced them
local NAMES = {
    ["Naowh"]                = "Red Hat Display",
    ["GothamNarrowUltra"]    = "Barlow Semi Condensed Black",
    ["Numen"]                = "Barlow Semi Condensed Black",
    ["Melli"]                = "ZacUI Flat",
    -- the raid packs' own names (their media folder is gone; Numen above
    -- was theirs too: a bold condensed display face, so Barlow)
    ["fojjiMelli"]           = "ZacUI Flat",
    ["FojjiArcade"]          = "Barlow Semi Condensed Black",
    ["fojjiKUI"]             = "ZacUI Smooth",
    ["fojjiFlat"]            = [[Interface\Buttons\WHITE8X8]],
    ["fojjiBlank"]           = [[Interface\Buttons\WHITE8X8]],
    ["NaowhLeft"]            = "ZacUI Fade Left",
    ["NaowhRight"]           = "ZacUI Fade Right",
    ["NaowhGradient"]        = "ZacUI Tint",
    ["NaowhMouseover"]       = "ZacUI Hover",
    ["NaowhMouseoverArrows"] = "ZacUI Hover Arrows",
}
-- file paths saved by earlier versions (compared without case, slash
-- direction or extension) -> the file that replaced them
local PATHS = {
    [ [[interface\addons\zacui\media\naowh\fonts\naowh]] ]                = FONT_MAIN,
    [ [[interface\addons\zacui\media\naowh\fonts\gothamnarrowultra]] ]    = FONT_HEAVY,
    [ [[interface\addons\zacui\media\nameplates\numen]] ]                 = FONT_HEAVY,
    [ [[interface\addons\zacui\media\nameplates\naowh]] ]                 = FONT_MAIN,
    [ [[interface\addons\zacui\media\nameplates\melli]] ]                 = M .. [[Textures\bar_flat]],
    [ [[interface\addons\zacui\media\nameplates\fojjimelli]] ]            = M .. [[Textures\bar_flat]],
    [ [[interface\addons\zacui\media\naowh\textures\melli]] ]             = M .. [[Textures\bar_flat]],
    [ [[interface\addons\zacui\media\naowh\textures\naowhleft]] ]         = M .. [[Textures\bar_fade_left]],
    [ [[interface\addons\zacui\media\naowh\textures\naowhright]] ]        = M .. [[Textures\bar_fade_right]],
    [ [[interface\addons\zacui\media\naowh\textures\naowhgradient]] ]     = M .. [[Textures\bar_tint]],
    [ [[interface\addons\zacui\media\naowh\textures\naowhmouseover]] ]    = M .. [[Textures\bar_hover]],
    [ [[interface\addons\zacui\media\naowh\textures\naowhmouseoverarrows]] ] = M .. [[Textures\bar_hover_arrows]],
    [ [[interface\addons\zacui\media\naowh\textures\naowhtarget]] ]       = M .. [[Textures\target_chevron]],
    -- the raid packs' media folder, under both names it had
    [ [[interface\addons\fojjicore\font\numen]] ]                   = FONT_HEAVY,
    [ [[interface\addons\fojjicore\font\fojjiarcade]] ]             = FONT_HEAVY,
    [ [[interface\addons\zacui_fojji\font\numen]] ]                 = FONT_HEAVY,
    [ [[interface\addons\zacui_fojji\font\fojjiarcade]] ]           = FONT_HEAVY,
    [ [[interface\addons\fojjicore\statusbar\melli]] ]              = M .. [[Textures\bar_flat]],
    [ [[interface\addons\fojjicore\statusbar\fojjikui]] ]           = M .. [[normTex]],
    [ [[interface\addons\fojjicore\statusbar\fojjiflat]] ]          = [[Interface\Buttons\WHITE8X8]],
    [ [[interface\addons\fojjicore\statusbar\fojjiblank]] ]         = [[Interface\Buttons\WHITE8X8]],
    [ [[interface\addons\zacui_fojji\statusbar\melli]] ]            = M .. [[Textures\bar_flat]],
    [ [[interface\addons\zacui_fojji\statusbar\fojjikui]] ]         = M .. [[normTex]],
    [ [[interface\addons\zacui_fojji\statusbar\fojjiflat]] ]        = [[Interface\Buttons\WHITE8X8]],
    [ [[interface\addons\zacui_fojji\statusbar\fojjiblank]] ]       = [[Interface\Buttons\WHITE8X8]],
}
ns.MEDIA_OLD_NAMES, ns.MEDIA_OLD_PATHS = NAMES, PATHS

local function PathKey(s)
    s = s:lower():gsub("/", "\\")
    s = s:gsub("%.tga$", ""):gsub("%.blp$", ""):gsub("%.ttf$", ""):gsub("%.otf$", "")
    return s
end

-- the replacement for one saved value, or nil when it is not an old one
-- A name something has registered again (Zac's own setup keeps Naowh,
-- Gotham and Melli in ZacLayout) is not old: it is left as it is.
local function Registered(v)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return false end
    return (LSM:Fetch("font", v, true) or LSM:Fetch("statusbar", v, true)) ~= nil
end

function ns.NewMediaName(v)
    if type(v) ~= "string" or v == "" then return nil end
    local n = NAMES[v]
    if n then
        if Registered(v) then return nil end
        return n
    end
    if v:find("\\", 1, true) or v:find("/", 1, true) then
        return PATHS[PathKey(v)]
    end
    return nil
end

-- ZacUI's own font or bar by its name, without asking SharedMedia (which
-- may not be loaded, or may have loaded after ZacUI registered with it).
-- kind "font" or "statusbar"; a path comes back as it is.
function ns.OwnMediaPath(kind, name)
    if type(name) ~= "string" or name == "" then return nil end
    local list = kind == "font" and ns.MEDIA_FONTS or ns.MEDIA_BARS
    for _, m in ipairs(list or {}) do
        if m.name == name then return m.path end
    end
    if name:find("\\", 1, true) or name:find("/", 1, true) then return name end
    return nil
end

-- every value in t (and the tables in it) that is an old name or path,
-- rewritten in place; returns how many
function ns.MigrateMediaNames(t)
    if type(t) ~= "table" then return 0 end
    local seen, n = {}, 0
    local function Walk(x, depth)
        if seen[x] or depth > 40 then return end
        seen[x] = true
        for k, v in pairs(x) do
            if type(v) == "table" then
                Walk(v, depth + 1)
            else
                local new = ns.NewMediaName(v)
                if new then x[k] = new n = n + 1 end
            end
        end
    end
    Walk(t, 0)
    return n
end
