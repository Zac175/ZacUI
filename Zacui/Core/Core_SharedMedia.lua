-- ============================================================
-- SHARED MEDIA
-- ZacUI's fonts and bar textures, published to LibSharedMedia so every
-- font and texture picker (ZacUI's own and other addons') lists them.
-- The list itself is Core_MediaNames (ns.MEDIA_FONTS / MEDIA_BARS).
-- ============================================================

local ADDON_NAME, ns = ...
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
if not LSM then return end

local MediaType_FONT = LSM.MediaType.FONT
local MediaType_STATUSBAR = LSM.MediaType.STATUSBAR

for _, f in ipairs(ns.MEDIA_FONTS or {}) do LSM:Register(MediaType_FONT, f.name, f.path) end
for _, b in ipairs(ns.MEDIA_BARS or {}) do LSM:Register(MediaType_STATUSBAR, b.name, b.path) end
