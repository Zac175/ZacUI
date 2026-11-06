-- Core_Boot - the namespace, the media table and the doctrine.
-- Part of ZacUI; load order is set by the TOC.
-- ============================================================
-- ARCHITECTURE (the doctrine - read before adding anything):
--   1. ONE background implementation: SkinBackdrop = flat texture at
--      BACKGROUND -8 + 1px pixel border. SetBackdrop is never trusted
--      for our own fills (it failed silently on this client).
--   2. ONE panel entry point, FOUR modes (see SkinPanel): standard
--      fitted / modern auto-inset / content-art (keepArt+noPanel,
--      chrome rides the art background) / hands-off.
--   3. THE CLASSIFIER (ClassifyAndSkin): every widget-KIND rule lives
--      in one function - scrollbar sliders, close/arrow buttons by
--      texture-or-ATLAS signature, panel buttons, checkboxes, edit
--      boxes, StaticPopups, and the BLACK-LINES rule (any Blizzard
--      backdrop border -> flat 1px black). A PROTECTED-FRAME FIREWALL
--      runs before every rule: forbidden frames and NamePlate*/
--      Compact*/EditMode* prefixes never reach a write (1.15.9 taint
--      doctrine). Fed by the login sweep AND the new-frame watcher
--      (tail-resume, time-sliced drain - see Modules.watcher), so
--      frames born at any moment self-skin. Add rules HERE, not
--      per-frame code.
--   4. HOOKS: ScrollFrame_OnScrollRangeChanged, ToggleDropDownMenu,
--      PanelTemplates_TabResize - widgets self-skin when the game
--      calls them.
--   5. Atlas awareness: GetTexture() returns a NUMBER for atlas art;
--      always go through GetArtSignature for identity checks.
--   6. Third-party: each supported addon owns ONE file under
--      Modules\AddOns. Prefer the addon's official skin API where one
--      exists (Baganator, and Syndicator through it); fall back to
--      named frames behind a LoD registration otherwise. Never fight
--      an addon for a widget it re-asserts - back off instead.
--   7. Tab GEOMETRY stays Blizzard's unless SkinBottomTabs laid it
--      out; scrollFRAME regions are never stripped (talent-tree
--      lesson); content-art frames use keepArt, never StripTextures.
--   8. EDIT MODE (1.15.9): position/scale of client-managed HUD
--      frames (minimap cluster, buffs/debuffs, chat, action bars,
--      micro menu, bags...) belongs to Edit Mode. ZacUI restyles
--      VISUALS only; movers auto-disable on any frame Edit Mode
--      manages (frame.system set) or that is protected, and saved
--      positions are kept dormant in the DB.
--   9. COLOR flows one way: Core_Colors owns the palette, everything
--      reads it through Col/GetColor at PAINT time. Never cache a
--      color in an upvalue - live recolor depends on the re-read.
-- Media ships inside ZacUI (arrow, arrowLeft, normTex, scrollThumb,
-- Checkmark, mail, addonIcon). Every module defaults ON.
-- ============================================================

local ADDON_NAME, ns = ...

local ZUI = CreateFrame("Frame", "ZacUIFrame")
ZUI.skinned = {}
ZUI.panels  = {}
ZUI.VERSION = "2.0.0"

local MEDIA      = "Interface\\AddOns\\ZacUI\\Media\\"
local TEX_NORM   = MEDIA .. "normTex"
local TEX_ARROW  = MEDIA .. "arrow"       -- points down
local TEX_ARROWL = MEDIA .. "arrowLeft"   -- points left
-- Flat thumbs everywhere: the ridged scrollThumb.tga art read as clutter
-- at 1px-border scale, so every scrollbar/slider thumb is now a plain
-- block wearing the palette's thumb color. One texture, one look.
local TEX_THUMB  = "Interface\\Buttons\\WHITE8X8"
local TEX_CHECK  = MEDIA .. "Checkmark"
local TEX_CHECK_WHITE = MEDIA .. "CheckmarkWhite"   -- a picked tick colour, drawn exactly
local TEX_ICON   = MEDIA .. "addonIcon"
local FLAT       = "Interface\\Buttons\\WHITE8X8"

-- ZUI.skinned is the fence every skinner checks, so its size is also the
-- honest answer to "how much has ZacUI actually touched". Counted on
-- demand rather than tracked with a counter - a counter is one more thing
-- to keep in sync, and this is only ever read by a settings page.
local function SkinnedCount()
    local n = 0
    for _ in pairs(ZUI.skinned) do n = n + 1 end
    return n
end

-- the chat name in the palette's chat colour (Core_Colors loads after
-- this file, so it is looked up when a line is printed)
local function ChatCode()
    local c = ns.GetColor and ns.GetColor("text", "chat")
    if c and ns.Hex then return "|cff" .. ns.Hex(c) end
    return "|cffffd100"
end
ns.ChatCode = ChatCode

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(ChatCode() .. "[ZacUI]|r " .. tostring(msg))
end

-- CRISP ICONS - why icons looked soft next to the rest of the UI.
--
-- On this client every texture is, by default, snapped to the pixel grid
-- and given a texel-snapping bias. That is the right default for chrome
-- that is drawn 1:1 with its source art. It is the WRONG default for an
-- icon, because an icon is essentially never drawn 1:1: the art is 64px
-- and ZacUI draws it at 34 in a bag slot, 28 in the tray, 18 in an
-- auction row. Snapping then quantizes the sample positions and the
-- client resamples the icon, which is exactly the blurry, washed-out
-- "that isn't the HD icon" look - even though the file being drawn is
-- the same one Blizzard uses.
--
-- Turning both off costs nothing and makes the icon look like the file.
-- Guarded because these are modern-engine methods; on a build that lacks
-- them the icon simply keeps the old behaviour rather than erroring.
local function SharpenIcon(tex)
    if not tex then return end
    if tex.SetSnapToPixelGrid then pcall(tex.SetSnapToPixelGrid, tex, false) end
    if tex.SetTexelSnappingBias then pcall(tex.SetTexelSnappingBias, tex, 0) end
end

-- shared with later ZacUI files
-- Is that addon loaded right now? (For decisions made at file load,
-- after an OptionalDep's own files; ns.OnAddonLoaded is the deferred
-- form.) Every part used to carry its own copy.
local function AddonLoaded(name)
    local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if not f then return false end
    local ok, v = pcall(f, name)
    return ok and v and true or false
end

ns.AddonLoaded = AddonLoaded
ns.ADDON_NAME = ADDON_NAME
ns.FLAT = FLAT
ns.MEDIA = MEDIA
ns.Print = Print
ns.SharpenIcon = SharpenIcon
ns.SkinnedCount = SkinnedCount
ns.TEX_ARROW = TEX_ARROW
ns.TEX_ARROWL = TEX_ARROWL
ns.TEX_CHECK = TEX_CHECK
ns.TEX_CHECK_WHITE = TEX_CHECK_WHITE
ns.TEX_ICON = TEX_ICON
ns.TEX_NORM = TEX_NORM
ns.TEX_THUMB = TEX_THUMB
ns.ZUI = ZUI

-- THE PARTS (Zacui_Bars, Zacui_Nameplates, Zacui_Meter, ...) are separate
-- addons that depend on this one. Each of their files begins with
-- `local ns = _G.ZacUI`, so they read and write the same namespace as
-- every file in this TOC. Published here, first thing, so nothing can
-- load before it exists.
_G.ZacUI = ns
