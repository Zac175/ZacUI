-- Config_EditLinks - "Move in Edit Mode" on the settings pages.
-- Part of ZacUI; load order is set by the TOC (after Config_Base).
--
-- Every settings page that styles a frame Edit Mode can move gets a small
-- button at the right of its header: Edit Mode opens with that frame (or
-- the page's frames) picked out - shown, selected for the arrow keys, its
-- row in view, a short flash. Leaving Edit Mode comes back to the page.
-- The way back is each mover's "Open its settings" (UIF_EditMode). Which
-- page styles which frame is UIF_EditSession's PageFor.
--
-- Built by wrapping the page header (ns.ConfigLayout.Header), so no page
-- has to ask for it: a page build that is on screen (layout.live) with a
-- page id gets the button; the unseen build for the search index never
-- does. One button per page, moved onto each new header.

local ADDON_NAME, ns = ...

local UI = ns.UI
local Layout = ns.ConfigLayout
if not (UI and Layout and Layout.Header) then return end

local ICON = (ns.MEDIA or "Interface\\AddOns\\ZacUI\\Media\\") .. "Icons\\unlock"
local buttons = {}       -- [pageId] = button
local cache = {}         -- [pageId] = { at = time, keys = { ... } }
local CACHE_FOR = 3      -- seconds: a page rebuilds on every change

local function KeysFor(pageId)
    local now = GetTime and GetTime() or 0
    local c = cache[pageId]
    if c and now - c.at < CACHE_FOR then return c.keys end
    local keys = ns.EditModeKeysForPage and ns.EditModeKeysForPage(pageId) or {}
    cache[pageId] = { at = now, keys = keys }
    return keys
end

local function Button(pageId)
    local b = buttons[pageId]
    if b then return b end
    b = UI.Button(UIParent, "Move in Edit Mode", { height = 20, size = UI.F.SMALL })
    local icon = b:CreateTexture(nil, "OVERLAY")
    icon._zui_own = true
    icon:SetSize(12, 12)
    icon:SetTexture(ICON)
    icon:SetPoint("LEFT", 6, 0)
    b._zText:ClearAllPoints()
    b._zText:SetPoint("LEFT", icon, "RIGHT", 5, 0)
    -- as wide as its label at the font size in use (fitted on every build)
    b._zFitIcon = function(self)
        self:SetWidth(math.ceil((self._zText:GetStringWidth() or 90) + 6 + 12 + 5 + 10))
    end
    b:_zFitIcon()
    local function Tint(on)
        local c = on and ns.GetColor("ui", "accent") or ns.GetColor("text", "normal")
        icon:SetVertexColor(c.r, c.g, c.b, 1)
    end
    Tint(false)
    b:HookScript("OnEnter", function() Tint(true) end)
    b:HookScript("OnLeave", function() Tint(false) end)
    UI.Tooltip(b, "Move in Edit Mode",
        "Opens Edit Mode with this page's frame picked out: drag it, nudge it with the arrow keys, "
            .. "attach it to another frame. Leaving Edit Mode brings you back here.")
    b:SetScript("OnClick", function(self)
        local keys = self._zKeys
        if keys and #keys > 0 and ns.EnterEditMode then ns.EnterEditMode({ focus = keys }) end
    end)
    buttons[pageId] = b
    return b
end

local Header = Layout.Header
function Layout:Header(title, subtitle)
    local f = Header(self, title, subtitle)
    -- (2026-11-08, Zac: "the move in edit mode in the top right i really
    -- dont like that") off: Edit Mode stays one click away in the sidebar
    if false and self.live and self.pageId and f and ns.EnterEditMode then
        local ok, keys = pcall(KeysFor, self.pageId)
        local b = buttons[self.pageId]
        if ok and keys and #keys > 0 then
            b = Button(self.pageId)
            b._zKeys = keys
            b:_zFitIcon()
            b:SetParent(f)
            b:ClearAllPoints()
            b:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
            b:SetFrameLevel((f:GetFrameLevel() or 0) + 5)
            b:Show()
        elseif b then
            b:Hide()
        end
    end
    return f
end
