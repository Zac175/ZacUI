-- Bags_Frame - ZacUI's combined inventory window.
-- Part of ZacUI; load order is set by the TOC.
--
-- THE ONE STRUCTURAL CONSTRAINT worth understanding before editing this
-- file: Blizzard's container item button template works out WHICH item it
-- is looking at from two places -
--     the slot   = button:GetID()
--     the bag    = button:GetParent():GetID()
-- That is baked into the template's own OnClick, OnEnter and drag
-- handlers, which is exactly why we reuse the template instead of writing
-- our own - it gives us correct click-to-pick-up, right-click-to-use,
-- split-stack, tooltips and drag-and-drop for free, including all the
-- special cases (soulbound prompts, quest items, keyring).
--
-- The consequence is that a button cannot simply be moved between bags:
-- its PARENT encodes its bag. So buttons are allocated per bag against a
-- per-bag holder frame, and layout only ever moves them with SetPoint.
-- Nothing is ever reparented, which also means nothing breaks in combat.
--
-- The holders are full-size, transparent and stacked on top of each other
-- over the grid area. They exist only to carry an ID.

local ADDON_NAME = ...
-- Zacui_Bags is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local AddPixelBorder = ns.AddPixelBorder
local Bags = ns.Bags
local Col = ns.Col
local FLAT = ns.FLAT
local GetColor = ns.GetColor
local Modules = ns.Modules
local Print = ns.Print
local SharpenIcon = ns.SharpenIcon
local TintBorder = ns.TintBorder
local UI = ns.UI
local ZUI = ns.ZUI

local M, F = UI.M, UI.F

local SLOT = 34          -- item button size (slotSize)
local GAP = 3            -- gap between slots (spacing)
local PAD = 10           -- window edge -> grid
local HEADER = 56        -- search / sort row, then the bag-slot row
local BAGBTN = 22        -- bag-slot button size in that row
local FOOTER = 22        -- money + free slots

local views = {}
local buttonSerial = 0

-- ============================================================
-- THE LOOK (ZacUIDB.bags, Bags & maps > Bags)
-- ============================================================
-- Every default is what this file drew before the setting existed; a
-- colour or font left unset is "as before" (the palette, Blizzard's count
-- font, ZacUI's font). The same functions dress the real slots and the
-- samples on the Bags page: DressSlot builds a slot's look, StyleSlot
-- applies the fonts, PaintSlot paints an item into it.
--   slotSize, spacing, columns           the grid
--   slotColor, emptyAlpha, filledAlpha   a slot's backing
--   borderColor, qualityBorders, questColor
--   fadedAlpha                           a search non-match
--   countFont, countColor, footerFont    text
--   bgColor, frameBorderColor            the window
--   openAnim, closeAnim                  the window opening and closing
local BAG_LOOK = {
    columns = 10, slotSize = SLOT, spacing = GAP,
    emptyAlpha = 0.45, filledAlpha = 0.75, fadedAlpha = 0.25,
    qualityBorders = true,
}
local function BagCfg()
    if not ZacUIDB then return BAG_LOOK end
    ZacUIDB.bags = ZacUIDB.bags or {}
    local t = ZacUIDB.bags
    if ns.FillDefaults then ns.FillDefaults(t, BAG_LOOK)
    else for k, v in pairs(BAG_LOOK) do if t[k] == nil then t[k] = v end end end
    return t
end
local function SlotSize()
    return math.max(20, math.min(64, tonumber(BagCfg().slotSize) or SLOT))
end
local function SlotGap()
    return math.max(0, math.min(20, tonumber(BagCfg().spacing) or GAP))
end
local function Empty(spec) return type(spec) ~= "table" or next(spec) == nil end
-- bumped on every settings change: a slot restyles its fonts when behind
local lookVer = 1
local DressSlot   -- (below, with the item buttons)

-- Money is ns.Money (Core_Services). The account total uses its "gold"
-- form - whole gold with separators and one coin icon. A coin string
-- would give three icons and a silver/copper tail - at five figures,
-- three numbers to read where the question only asked for one.
local Money = ns.Money

-- ============================================================
-- COMBAT GATE
-- ============================================================
-- DEAD WEIGHT IN THE DEFAULT CONFIGURATION, and deliberately kept.
--
-- Plain item buttons are not protected, so none of this runs: the bag
-- lays out, resizes, opens and closes in combat exactly like it does out
-- of it. Everything below exists only for the opt-in secure mode
-- (ZacUIDB.bags.secureUse = true), where the buttons DO carry
-- SecureActionButtonTemplate and ClearAllPoints/SetPoint/Show/Hide/
-- SetAttribute on them - plus SetSize and Show on the window that
-- anchors them - are refused under a lockdown.
--
-- Even then, only view:Layout defers, NEVER view:Paint. Deferring both
-- is the obvious fix and it is wrong: it empties the bag on the pull,
-- because icons, counts and cooldowns are not protected and have no
-- reason to stop.
-- Set by the module once the key hooks exist; drains a bag open/close
-- that the player asked for while the window was frozen.
local DrainBagToggle

local combatWatch
local function StartCombatWatch()
    if combatWatch then return end
    combatWatch = CreateFrame("Frame")
    combatWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
    combatWatch:SetScript("OnEvent", function()
        for _, view in pairs(views) do
            if view._layoutPending then
                pcall(view.Refresh, view)
            end
        end
        if DrainBagToggle then pcall(DrainBagToggle) end
    end)
end

-- ============================================================
-- ITEM BUTTONS
-- ============================================================
-- KILL THE SLOT ART, BY SWEEP RATHER THAN BY NAME.
--
-- The first version of this named the pieces it wanted gone - IconBorder,
-- IconOverlay, NormalTexture. That was wrong twice over. Blizzard's item
-- button carries more texture regions than those on 1.15 (the slot frame,
-- the shadow, the quality glow, the "searching" wash), and the visible
-- result was a blue-grey frame around every occupied slot that looked
-- like a quality colour but was just leftover artwork.
--
-- And naming them would not have been enough anyway: SetItemButtonTexture
-- and its siblings RE-SHOW several of these every time a slot's contents
-- change, so anything done once at creation is undone by the first item
-- you move. Hence a sweep, re-run on every paint.
--
-- Everything except the icon goes. Count is a FontString and Cooldown is
-- a Frame, so neither is touched by a texture sweep; the highlight and
-- pushed states are ours, applied after the sweep.
-- The keyed pieces of a slot button that are not plain regions.
local SLOT_PIECES = { "IconBorder", "IconOverlay", "IconOverlay2",
    "SlotArt", "SlotBackground", "IconQuestTexture",
    "BattlepayItemTexture", "NewItemTexture",
    "ExtendedOverlay", "searchOverlay", "SearchOverlay" }
local function KillSlotArt(btn)
    if not btn.GetRegions then return end
    -- a button's texture regions are fixed at creation, so the list is
    -- read once per button and kept; this runs for ~100 slots per paint
    local regions = btn._zRegions
    if not regions then
        regions = {}
        for _, region in ipairs({ btn:GetRegions() }) do
            if region.IsObjectType and region:IsObjectType("Texture") and not region._zui_own then
                regions[#regions + 1] = region
            end
        end
        btn._zRegions = regions
    end
    for i = 1, #regions do
        local region = regions[i]
        if region ~= btn._zIcon then
            region:SetTexture(nil)
            region:SetAlpha(0)
        end
    end
    -- THE ICON IS RESTORED, NOT MERELY SPARED. Sparing it by identity
    -- assumes we resolved the right region, and if that lookup ever misses
    -- - a template change, a different field name - the sweep silently
    -- eats every icon in the bag and leaves a grid of empty squares with
    -- correct borders and counts. Asking for its alpha back costs nothing
    -- and makes the failure mode "some slot art survives" instead of
    -- "the bag is useless".
    if btn._zIcon then
        btn._zIcon:SetAlpha(1)
        btn._zIcon:SetDrawLayer("ARTWORK")
    end
    -- Keyed pieces that are not plain regions of the button.
    for _, key in ipairs(SLOT_PIECES) do
        local piece = btn[key]
        if piece and piece.SetAlpha then piece:SetAlpha(0) end
    end
    local normal = btn.GetNormalTexture and btn:GetNormalTexture()
    if normal then
        normal:SetTexture(nil)
        normal:SetAlpha(0)
    end
end

-- ============================================================
-- THE SPLIT DIALOG HAS TO BE IN FRONT OF THE BAG
-- ============================================================
-- Blizzard's StackSplitFrame sits at DIALOG strata, and so does every
-- ZacUI window - so the dialog opened behind the bag that asked for it
-- and the split looked like it had done nothing again. Strata beats
-- frame level unconditionally, so raising the level would not have been
-- enough; the dialog has to move up a whole strata.
--
-- Measured against the frame that opened it rather than hardcoded,
-- because the bag and the bank are not guaranteed to stay at the same
-- strata forever, and a constant here would rot silently.
local STRATA_UP = {
    BACKGROUND = "LOW", LOW = "MEDIUM", MEDIUM = "HIGH", HIGH = "DIALOG",
    DIALOG = "FULLSCREEN", FULLSCREEN = "FULLSCREEN_DIALOG",
    FULLSCREEN_DIALOG = "TOOLTIP", TOOLTIP = "TOOLTIP",
}

local function LiftSplitDialog(owner)
    local dialog = _G.StackSplitFrame
    if not dialog or not dialog.SetFrameStrata then return end
    local host = owner
    -- Walk up to the window, not the holder frame the button sits in.
    while host and host.GetParent and host:GetParent()
        and host:GetParent() ~= UIParent do
        host = host:GetParent()
    end
    local base = (host and host.GetFrameStrata and host:GetFrameStrata())
        or "DIALOG"
    dialog:SetFrameStrata(STRATA_UP[base] or "FULLSCREEN_DIALOG")
    if dialog.SetToplevel then dialog:SetToplevel(true) end
    if dialog.Raise then dialog:Raise() end
end

-- INSTALLED ONCE, ON THE GLOBAL, NOT ON ANY BUTTON.
--
-- hooksecurefunc is the one hook that is safe here: the client runs the
-- original first in its own execution context and calls ours afterwards
-- without letting our taint flow back into it. That is exactly the
-- property HookScript does not have, and the difference between the two
-- is the difference between a visible split dialog and a bag where you
-- cannot right-click anything.
local splitHooked = false
local function InstallSplitLift()
    if splitHooked then return end
    if type(_G.OpenStackSplitFrame) ~= "function" then return end
    if type(hooksecurefunc) ~= "function" then return end
    splitHooked = true
    hooksecurefunc("OpenStackSplitFrame", function(_, owner)
        -- Only for our own slots. Blizzard's bags, the guild bank and
        -- everything else keep the layering they were built with.
        if owner and owner._zBagSlot then LiftSplitDialog(owner) end
    end)
end

-- Reads the click path without standing in it. Answers the two questions
-- that have actually come up: is anything of ours sitting on a bag slot's
-- OnClick (which would break using items), and is the split dialog going
-- to be visible when it opens.
function Bags.ClickReport()
    Print("--- bag clicks ---")
    Print("split-dialog lift installed: "
        .. (splitHooked and "|cff66ff66yes|r" or "|cffff9900no|r"))
    local dialog = _G.StackSplitFrame
    Print("split dialog strata: "
        .. (dialog and dialog:GetFrameStrata() or "no dialog"))
    local view = ns.BagViews and ns.BagViews.inventory
    local win = view and view.frame
    Print("bag window strata: "
        .. (win and win:GetFrameStrata() or "bag not built yet"))
    Print("splitter: " .. (Bags.Split and "present" or "|cffff9900missing|r"))
    Print("if using items is refused, something is hooking a slot's OnClick;")
    Print("ZacUI deliberately hooks nothing there - see Bags_Frame.lua.")
end

-- ============================================================
-- SECURE RIGHT-CLICK USE
-- ============================================================
-- These buttons are addon-created clones of Blizzard's template, so a
-- click on them runs Blizzard's handler in a TAINTED execution. Most of
-- the time the client tolerates that - but in combat and right after a
-- zone-in it demands a secure path for UseContainerItem, and refuses:
--
--     AddOn 'Zacui' tried to call the protected function 'UNKNOWN()'
--       [C]: in function 'UseContainerItem'
--
-- Rare (four hits across three accounts in weeks of play), but the
-- moment it hits is exactly the worst one: spamming a potion in combat.
--
-- The fix is to stop asking Blizzard's handler to use items at all.
-- Each button ALSO inherits SecureActionButtonTemplate with
-- type2="item" and a fixed bag/slot attribute pair - a plain
-- right-click then uses whatever is in that physical slot through the
-- SECURE action system, which cannot be tainted by construction and
-- works in combat. Everything else (left-click pickup, modified
-- clicks, selling at a vendor, banking) still runs Blizzard's own
-- handler via PostClick, in the same contexts it always ran - none of
-- those are protected, so taint there costs nothing.
--
-- When a merchant/bank/mail/auction window is open, right-click must
-- mean sell/deposit/attach again, so a context watcher blanks type2
-- while those are up (they can never be open in combat, so the
-- attribute writes are always legal).
local secureButtons = {}

-- Only the opt-in secure mode makes anything here protected. In the
-- default plain mode this is false forever, and every combat gate in
-- this file collapses to a no-op - which is the whole point: the bag
-- opens, closes, relayouts and paints in combat like any other addon's.
local function SecureActive()
    return #secureButtons > 0
end

local SECURE_ONCLICK
do
    local ref = CreateFrame("Button", nil, nil, "SecureActionButtonTemplate")
    SECURE_ONCLICK = ref:GetScript("OnClick")
    ref:Hide()
end

-- PostClick fires on BOTH phases now (secure buttons on this client only
-- act when the down phase is registered, so both are). Legacy behavior
-- runs once, on the up phase, matching how Blizzard's own handler was
-- always driven.
local function SlotPostClick(self, button, down)
    if down then return end
    if button == "RightButton"
        and self:GetAttribute("type2") == "item"
        and not IsModifierKeyDown() then
        return -- the secure path owned this click
    end
    -- everything else is the classic handler, exactly as before
    local handler = _G.ContainerFrameItemButton_OnClick
    if handler then handler(self, button) end
end

local contextWatch
local function InstallContextWatch()
    if contextWatch then return end
    contextWatch = CreateFrame("Frame")
    contextWatch:RegisterEvent("MERCHANT_SHOW")
    contextWatch:RegisterEvent("MERCHANT_CLOSED")
    contextWatch:RegisterEvent("BANKFRAME_OPENED")
    contextWatch:RegisterEvent("BANKFRAME_CLOSED")
    contextWatch:RegisterEvent("MAIL_SHOW")
    contextWatch:RegisterEvent("MAIL_CLOSED")
    contextWatch:RegisterEvent("TRADE_SHOW")
    contextWatch:RegisterEvent("TRADE_CLOSED")
    pcall(contextWatch.RegisterEvent, contextWatch, "AUCTION_HOUSE_SHOW")
    pcall(contextWatch.RegisterEvent, contextWatch, "AUCTION_HOUSE_CLOSED")
    -- PLAYER_REGEN_ENABLED is in the same list so the attribute pass that
    -- combat refused is replayed rather than silently lost - a merchant
    -- opened mid-fight used to leave right-click still wired to "use".
    contextWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
    local open = 0
    contextWatch:SetScript("OnEvent", function(_, event)
        if event ~= "PLAYER_REGEN_ENABLED" then
            if event:find("SHOW") or event:find("OPENED") then
                open = open + 1
            else
                open = math.max(0, open - 1)
            end
        end
        if InCombatLockdown and InCombatLockdown() then return end
        local wantItem = (open == 0) and "item" or nil
        for _, b in ipairs(secureButtons) do
            b:SetAttribute("type2", wantItem)
        end
    end)
end

-- ============================================================
-- WHY THESE ARE PLAIN BUTTONS AGAIN
-- ============================================================
-- SecureActionButtonTemplate was added to fix a rare refusal of
-- UseContainerItem (see the block further down). It worked, and it cost
-- far more than it bought: a frame is protected if ANY DESCENDANT is
-- protected, so one secure slot made the whole ZacUIBagFrame protected
-- by ancestry. Show, Hide, SetPoint and SetSize on the window were then
-- all refused in combat - the bag could not be opened mid-fight at all,
-- and every BAG_UPDATE during a pull filled BugSack with blocked-action
-- reports.
--
-- Every other bag addon - Baganator, Bagnon, ArkInventory - uses plain
-- ContainerFrameItemButtonTemplate buttons and works in combat, because
-- UseContainerItem needs a HARDWARE EVENT, not secure execution. A
-- template OnClick fired by a real mouse click satisfies that whether or
-- not the button was created by an addon.
--
-- Which means the rare refusal was never inherent: it was ZacUI's own
-- taint leaking into the click. Fix the taint, not the bag.
--
-- The secure path is kept, opt-in, behind ZacUIDB.bags.secureUse = true
-- for anyone who would rather have the old trade. Default is off.
local function SecureWanted()
    return ZacUIDB and ZacUIDB.bags and ZacUIDB.bags.secureUse == true
end

-- A slot's own look, on a real item button or a sample: the icon
-- cropped, a flat backing, a pixel border, our highlight and pushed
-- states. btn._zIcon / btn._zCount are set by the caller.
function DressSlot(btn)
    local icon = btn._zIcon
    if icon then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetDrawLayer("ARTWORK")
        SharpenIcon(icon)
    end

    local bg = btn:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg._zui_own = true
    bg:SetAllPoints()
    bg:SetTexture(FLAT)
    btn._zBg = bg

    KillSlotArt(btn)
    AddPixelBorder(btn)

    -- After the sweep, or these get wiped with everything else.
    local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
    if hl then
        hl:SetColorTexture(1, 1, 1, 0.15)
        hl:SetBlendMode("ADD")
        hl._zui_own = true
    end
    local pushed = btn.GetPushedTexture and btn:GetPushedTexture()
    if pushed then
        pushed:SetColorTexture(0, 0, 0, 0.3)
        pushed._zui_own = true
    end
end

-- WHERE THE TEXTS SIT (ZacUI's anchor shape, bags.anchors.<count|free|
-- money>). The stack count's default is wherever its button put it (the
-- game's template on a real slot, read once the first time a spec moves
-- it and put back exactly when the spec goes); the footer texts' are
-- their SetPoints. Nothing saved = never touched.
local function BagAnchor(cfg, key)
    local a = cfg and cfg.anchors
    return type(a) == "table" and a[key] or nil
end
local function PlaceCount(btn, cfg)
    local count = btn._zCount
    if not (count and ns.ApplyAnchor) then return end
    local spec = BagAnchor(cfg, "count")
    if not spec then
        local o = count._zOrigPts
        if o and count._zMoved then
            count:ClearAllPoints()
            for _, p in ipairs(o) do count:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
            if o.justify then count:SetJustifyH(o.justify) end
            count._zMoved = nil
        end
        return
    end
    if not count._zOrigPts then
        local o = {}
        for i = 1, (count.GetNumPoints and count:GetNumPoints() or 0) do
            local p, rel, rp, x, y = count:GetPoint(i)
            if p then o[#o + 1] = { p, rel or btn, rp or p, x or 0, y or 0 } end
        end
        if #o == 0 then o[1] = { "BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 2 } end
        o.justify = count.GetJustifyH and count:GetJustifyH() or nil
        count._zOrigPts = o
    end
    local o = count._zOrigPts
    local D = count._zDef or {}
    count._zDef = D
    D.point, D.to, D.relPoint, D.x, D.y, D.justify = o[1][1], o[1][2], o[1][3], o[1][4], o[1][5], o.justify
    if not btn._zAnchorTo then
        btn._zAnchorTo = function(k) if k == "slot" then return btn elseif k == "icon" then return btn._zIcon end end
    end
    ns.ApplyAnchor(count, spec, D, btn._zAnchorTo)
    count._zMoved = true
end

-- a footer text at its spot (def: the SetPoint it always had), or the
-- saved anchor on top
local function PlaceFooterText(fs, key, cfg, def, resolveTo)
    if not (fs and def) then return end
    local spec = BagAnchor(cfg, key)
    if spec and ns.ApplyAnchor then
        ns.ApplyAnchor(fs, spec, def, resolveTo)
    else
        fs:ClearAllPoints()
        fs:SetPoint(def.point, def.to, def.relPoint, def.x, def.y)
        if def.justify then fs:SetJustifyH(def.justify) end
    end
end

-- your money as text: the game's coins, or the saved format (bags.formats.
-- money, ZacUI's text format: a template over [coins] [g] [s] [c], big
-- numbers for the gold)
local MONEY_VALUES, MONEY_KINDS = {}, { g = "number", s = "text", c = "text", coins = "text" }
local function MoneyText(copper, cfg)
    local spec = cfg and type(cfg.formats) == "table" and cfg.formats.money
    if not (spec and ns.FormatText) then return Money(copper) end
    copper = math.floor(copper or 0)
    local v = MONEY_VALUES
    v.coins = Money(copper)
    v.g = math.floor(copper / 10000)
    v.s = math.floor((copper % 10000) / 100)
    v.c = copper % 100
    return ns.FormatText(spec, nil, v, MONEY_KINDS, "coins")
end

-- The stack count's font and colour (Blizzard's until one is chosen).
local function StyleSlot(btn, cfg)
    cfg = cfg or BagCfg()
    btn._zLookVer = lookVer
    local count = btn._zCount
    if not (count and count.GetFont) then return end
    PlaceCount(btn, cfg)
    if not count._zStock then count._zStock = { count:GetFont() } end
    local stock = count._zStock
    if Empty(cfg.countFont) then
        if count._zCustom and stock[1] then
            count._zCustom = nil
            -- (back in ZacUI's font, which its template wore)
            if ns.FollowFont then ns.FollowFont(count, stock[2], stock[3])
            else pcall(count.SetFont, count, stock[1], stock[2], stock[3]) end
        end
    elseif ns.ApplyFontSpec and stock[1] then
        count._zCustom = true
        ns.ApplyFontSpec(count, cfg.countFont, { fallbackFace = stock[1], size = stock[2] or 14,
            outline = (stock[3] and stock[3] ~= "") and stock[3] or "outline", shadow = false })
    end
    if type(cfg.countColor) == "table" then
        count:SetTextColor(ns.ColorOf(cfg.countColor))
        count._zColored = true
    elseif count._zColored then
        count._zColored = nil
        count:SetTextColor(1, 1, 1, 1)
    end
end

local function NewItemButton(parent)
    buttonSerial = buttonSerial + 1
    local name = "ZacUIBagItem" .. buttonSerial
    -- Frame TYPE differs across builds ("ItemButton" is the modern one),
    -- and getting it wrong is a hard error rather than a nil - so both
    -- are tried.
    local ok, btn
    if SecureWanted() then
        ok, btn = pcall(CreateFrame, "ItemButton", name, parent,
            "ContainerFrameItemButtonTemplate,SecureActionButtonTemplate")
        if not ok or not btn then
            ok, btn = pcall(CreateFrame, "Button", name, parent,
                "ContainerFrameItemButtonTemplate,SecureActionButtonTemplate")
        end
    end
    if not ok or not btn then
        ok, btn = pcall(CreateFrame, "ItemButton", name, parent,
            "ContainerFrameItemButtonTemplate")
    end
    if not ok or not btn then
        ok, btn = pcall(CreateFrame, "Button", name, parent,
            "ContainerFrameItemButtonTemplate")
    end
    if not ok or not btn then return nil end
    btn:SetSize(SlotSize(), SlotSize())
    -- Marks this as one of ours, so the split-dialog lift below can tell
    -- our slots from Blizzard's without hooking anything per button.
    btn._zBagSlot = true
    InstallSplitLift()

    -- ============================================================
    -- BANK CONTAINER TOOLTIPS
    -- ============================================================
    -- Bag -1 is not a container as far as the tooltip API is concerned.
    -- The bank's 28 built-in squares are INVENTORY slots, so the right
    -- call is SetInventoryItem on BankButtonIDToInvSlotID(slot), not
    -- SetBagItem(-1, slot) - which is why items in the purchased bank
    -- BAGS tooltipped correctly while the bank's own squares came up
    -- blank or showed whatever was hovered previously.
    --
    -- OnEnter, not OnClick. The load-bearing absence documented below is
    -- specifically about the click path, where a wrapper puts Blizzard's
    -- item-use handler inside our tainted execution. OnEnter reaches no
    -- protected call at all, so hooking it costs nothing - and the
    -- template's own OnEnter still runs first for the highlight, the
    -- cursor update and the repair/upgrade decorations.
    if parent:GetID() == Bags.BANK_CONTAINER then
        -- REPLACED, not hooked. A hook only runs when something calls the
        -- button's OnEnter SCRIPT; Blizzard refreshes container tooltips
        -- by calling ContainerFrameItemButton_OnEnter(self) directly as a
        -- global, which bypasses hooks entirely. Patching the one
        -- refresher I knew about fixed the symptom I could see and left
        -- any others intact.
        --
        -- The template's tooltip logic cannot work here under any
        -- circumstances - SetBagItem(-1, slot) does not resolve a bank
        -- slot - so there is nothing to preserve by letting it run first.
        -- Owning the handler outright means no code path anywhere can
        -- reach the broken one.
        --
        -- What is given up: the template's OnEnter also arms updateTooltip
        -- and sets the merchant sell-cursor. The refresh only exists to
        -- re-time cooldown text, which a bank slot has none of, and a
        -- vendor window cannot be open while the bank is.
        -- THE REFRESHER IS A METHOD, NOT A SCRIPT, and that is why every
        -- script-level fix failed. GameTooltip's OWN OnUpdate calls
        -- owner:UpdateTooltip() every 0.2s, and the container template
        -- stores ContainerFrameItemButton_OnEnter in that FIELD on the
        -- button. Replacing the OnEnter script leaves the field intact,
        -- so the tooltip itself kept re-running Blizzard's handler -
        -- SetBagItem(-1, slot), zero lines, black box - a beat after our
        -- correct tooltip appeared. Only bag -1 breaks because only
        -- there does SetBagItem fail; the purchased bank bags resolve
        -- fine, which is exactly the "top slots only" symptom.
        -- The field must point at OUR handler so the refresh repaints
        -- the right tooltip instead of erasing it.
        local function BankSlotOnEnter(self)
            local toInv = _G.BankButtonIDToInvSlotID
            if not toInv then return end
            local ok, inv = pcall(toInv, self:GetID())
            if not ok or not inv then return end
            -- ASK BEFORE OWNING. SetOwner clears every line, so calling it
            -- first and only then discovering the slot is empty leaves
            -- GameTooltip owned by this button with nothing in it - and
            -- anything that re-shows it afterwards paints an empty frame
            -- at the previous tooltip's size. That is the black box, and
            -- /dump GameTooltip:GetOwner():GetName() named ZacUIBagItem100
            -- - bank container slot 8, which is empty.
            --
            -- An empty slot now never touches the tooltip at all.
            local itemId = GetInventoryItemID and GetInventoryItemID("player", inv)
            if not itemId then
                if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
                self.updateTooltip = nil
                return
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetInventoryItem("player", inv)
            -- NumLines rather than the return value: "it said yes" and
            -- "it actually wrote something" are different questions, and
            -- only the second one keeps a blank frame off the screen.
            if GameTooltip:NumLines() > 0 then
                GameTooltip:Show()
            else
                GameTooltip:Hide()
            end

            -- AND STOP THE REFRESH LOOP, which is the whole bug.
            -- ContainerFrameItemButton_OnUpdate re-runs the tooltip while
            -- the cursor sits still, and it does so by calling
            -- ContainerFrameItemButton_OnEnter(self) as a PLAIN FUNCTION.
            -- A HookScript hook is attached to the script handler, not to
            -- the global, so that path never reaches this code: the
            -- refresh ran Blizzard's SetBagItem(-1, slot), which cannot
            -- resolve a bank slot, and left an owned tooltip with nothing
            -- in it. That is the "text for a moment, then a black box".
            --
            -- updateTooltip is what arms that loop, so clearing it makes
            -- OnUpdate return immediately and the tooltip we just built
            -- stays put. Belt and braces alongside owning the handler:
            -- if the template's OnEnter ever runs from somewhere else and
            -- arms it, the loop still finds nothing to do.
            self.updateTooltip = nil
        end

        btn:SetScript("OnEnter", BankSlotOnEnter)
        -- THE FIX THAT FINALLY LANDS: the tooltip's refresh calls
        -- owner:UpdateTooltip(), so the field has to point at the same
        -- handler. Refresh now repaints the correct tooltip instead of
        -- running the template's broken one.
        btn.UpdateTooltip = BankSlotOnEnter

        -- The template's OnLeave is gone with its OnEnter, so the tooltip
        -- has to be dismissed explicitly or it follows the cursor around.
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    -- Secure wiring - ONLY if the merge actually gave this button the
    -- secure OnClick (template merge order is not contractual, so it is
    -- verified rather than assumed). If it didn't, the button behaves
    -- exactly as the old all-container one did.
    -- Opt-in: /run ZacUIDB.bags.secureUse = true (then /reload).
    -- Off by default; see the note above NewItemButton for what it costs.
    if SecureWanted() and btn.SetAttribute and SECURE_ONCLICK
        and btn:GetScript("OnClick") == SECURE_ONCLICK then
        btn._zSecureUse = true
        -- BOTH phases: era's secure gate processes mouse clicks on the
        -- phase the ActionButtonUseKeyDown cvar picks, and with only Up
        -- registered the secure action simply never fired - which read
        -- as "right-click does nothing, ever".
        btn:RegisterForClicks("AnyUp", "AnyDown")
        btn:SetAttribute("type2", "item")
        btn:SetAttribute("bag", parent:GetID())
        -- modified right-clicks fall through to the classic handler
        btn:SetAttribute("shift-type2", "")
        btn:SetAttribute("ctrl-type2", "")
        btn:SetAttribute("alt-type2", "")
        btn:SetScript("PostClick", SlotPostClick)
        secureButtons[#secureButtons + 1] = btn
        InstallContextWatch()
    end

    -- ============================================================
    -- NOTHING IS HOOKED ON THIS BUTTON'S OnClick. EVER.
    -- ============================================================
    -- THIS IS A LOAD-BEARING ABSENCE, so it is written down where the
    -- code that caused the damage used to be.
    --
    -- There was a HookScript("OnClick") here, added to make shift-click
    -- splitting work. HookScript does not append to a script - it
    -- REPLACES it with a wrapper owned by whoever installed the hook, and
    -- the original then runs inside that wrapper. So every click on a bag
    -- slot began executing inside ZacUI code, Blizzard's own
    -- ContainerFrameItemButton_OnClick inherited that taint, and the
    -- UseContainerItem call at the end of it was refused by the client:
    --
    --     AddOn 'Zacui' tried to call the protected function 'UNKNOWN()'
    --       [C]: in function 'UseContainerItem'
    --       ContainerFrame_Shared.lua:1341: in ContainerFrameItemButton_OnClick
    --
    -- Right-clicking to use an item is the single most common thing
    -- anybody does in a bag, and the hook broke it to fix a rarer thing.
    -- ElvUI creates its bag buttons from this exact template and never
    -- hooks their OnClick; that is not a coincidence.
    --
    -- The splitting the hook was added for was never actually broken. The
    -- dialog was opening BEHIND the bag window, which looks identical to
    -- nothing happening. Blizzard's template opens it and Blizzard's own
    -- splitter handles the amount; all ZacUI has to do is make sure the
    -- dialog is visible, and that is done once, globally, in Bags_Core -
    -- not per button, and not on the click path.

    -- Resolve the icon FIRST - the sweep spares it by identity, and the
    -- paint restores it by reference. Three name spellings across builds,
    -- then a structural fallback: whichever ARTWORK texture the template
    -- created is the icon, because at this point we have created none.
    local icon = _G[name .. "IconTexture"] or btn.icon or btn.Icon
        or (btn.Icon and btn.Icon.icon)
    if not icon and btn.GetRegions then
        for _, region in ipairs({ btn:GetRegions() }) do
            if region.IsObjectType and region:IsObjectType("Texture")
                and region.GetDrawLayer and region:GetDrawLayer() == "ARTWORK"
                and not region._zui_own then
                icon = region
                break
            end
        end
    end
    btn._zIcon = icon
    btn._zCooldown = _G[name .. "Cooldown"] or btn.Cooldown
    btn._zCount = _G[name .. "Count"] or btn.Count
    DressSlot(btn)
    return btn
end

local NO_EDGES = {}

local function PaintSlot(btn, item, isQuest, faded)
    local empty = not item

    -- Re-swept whenever the slot's CONTENTS change, not just at creation.
    -- Blizzard's item button helpers put the slot art back when a slot's
    -- contents change, so a one-time hide survives only until you move
    -- an item - which is why the blue slot frame kept coming back and
    -- reading as a quality colour it never was. A repaint of the same
    -- item (a lock, a count, a search) has nothing to undo, and the sweep
    -- is ~25 calls a slot.
    local link = item and item.link or false
    if btn._zArtLink ~= link then
        btn._zArtLink = link
        KillSlotArt(btn)
    end

    -- Icon last, after everything that could have wiped it.
    if btn._zIcon then
        btn._zIcon:SetTexture(item and item.icon or nil)
        btn._zIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        SharpenIcon(btn._zIcon)
        btn._zIcon:SetAlpha(item and 1 or 0)
        btn._zIcon:SetDesaturated(item and item.locked and true or false)
    end

    -- a plain read: this runs for every slot on every paint, and every
    -- value below has its default beside it
    local cfg = (ZacUIDB and ZacUIDB.bags) or BAG_LOOK
    if btn._zLookVer ~= lookVer then StyleSlot(btn, cfg) end
    local er, eg, eb
    if type(cfg.slotColor) == "table" then
        er, eg, eb = ns.ColorOf(cfg.slotColor)
    else
        local e = Col("elementBg")
        er, eg, eb = e.r, e.g, e.b
    end
    btn._zBg:SetVertexColor(er, eg, eb,
        empty and (tonumber(cfg.emptyAlpha) or 0.45) or (tonumber(cfg.filledAlpha) or 0.75))

    -- Quality on the border rather than a ring texture. Quest items win
    -- over quality, because a quest item you cannot see is a corpse run.
    if isQuest then
        if type(cfg.questColor) == "table" then TintBorder(btn, ns.ColorOf(cfg.questColor))
        else TintBorder(btn, 1, 0.82, 0, 1) end
    elseif cfg.qualityBorders ~= false and item and item.quality and item.quality > 1
        and _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[item.quality] then
        TintBorder(btn, ns.QualityRGB(item.quality))
    elseif type(cfg.borderColor) == "table" then
        TintBorder(btn, ns.ColorOf(cfg.borderColor))
    else
        TintBorder(btn)
    end

    -- ============================================================
    -- FADING A NON-MATCH
    -- ============================================================
    -- This used to be one line - btn:SetAlpha(0.25) - on the theory that
    -- a frame's alpha carries to everything inside it. It does, right up
    -- until something in the button sets SetIgnoreParentAlpha, which
    -- Blizzard's container item template does for parts of its own art;
    -- and the icon here is Blizzard's own texture, adopted rather than
    -- created, so whatever flags it carries are its own.
    --
    -- The test did not catch it because it asserted btn:GetAlpha(), which
    -- is the value that had just been set - a tautology. What the eye
    -- actually reads is the ICON, so the icon is dimmed and desaturated
    -- directly, and the background and border with it. Nothing here
    -- depends on alpha inheritance.
    local dim = faded and (tonumber(cfg.fadedAlpha) or 0.25) or 1
    btn:SetAlpha(dim)
    if btn._zIcon then
        btn._zIcon:SetAlpha(item and dim or 0)
        -- Greyed as well as dimmed: colour is most of what makes an icon
        -- recognisable at a glance, so removing it is what turns "there
        -- but quiet" into "not what you asked for".
        if btn._zIcon.SetDesaturated then
            btn._zIcon:SetDesaturated(
                (faded or (item and item.locked)) and true or false)
        end
    end
    if btn._zBg then
        btn._zBg:SetAlpha(dim)
    end
    for _, edge in ipairs(btn._zui_borderTex or NO_EDGES) do
        edge:SetAlpha(dim)
    end
    if btn._zCount then btn._zCount:SetAlpha(dim) end
end

-- ============================================================
-- VIEW
-- ============================================================
-- One factory, two instances: the inventory and the bank. They differ
-- only in which bag list they walk and which sort call they make.
-- ============================================================
-- THE BAG SLOTS THEMSELVES
-- ============================================================
-- The window showed the contents of your bags and gave you nowhere to
-- put a new bag. Blizzard's own container frame keeps the four bag
-- slots on the action bar; a combined window replaces that bar, so it
-- has to carry them itself - and the bank's seven purchasable slots too,
-- which stock only exposes on the bank window it hides.
--
-- These are ordinary buttons, not secure ones. Equipping a bag is
-- PutItemInBag(inventorySlot) with a bag on the cursor, and picking one
-- up is PickupBagFromSlot(inventorySlot); neither is protected, both
-- are what BagSlotTemplate runs on click, and the game itself refuses a
-- bag swap in combat before either is reached. The buttons also take a
-- drag-and-drop the same way, because that is how people actually move
-- bags.
local EMPTY_SLOT = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"

-- Which inventory slot a bag-bar entry stands for. Inventory bags map
-- straight through the container id; bank bags are numbered from the
-- bank's own table, 1 to NUM_BANKBAGSLOTS.
-- ContainerIDToInventoryID moved into C_Container on this client, with
-- the rest of the container API; the bare global is nil on 1.15. The
-- first build of this row read only the global, so every slot came back
-- with no inventory id, drew as empty and ignored the click. Both are
-- tried, and failing both the classic offset is used - bag N lives in
-- inventory slot 19 + N, which has not changed since 2004.
local function BagInvSlot(view, index)
    if view.key == "bank" then
        if C_Container and C_Container.BankButtonIDToInvSlotID then
            return C_Container.BankButtonIDToInvSlotID(index, 1)
        end
        return BankButtonIDToInvSlotID and BankButtonIDToInvSlotID(index, 1) or nil
    end
    if C_Container and C_Container.ContainerIDToInventoryID then
        return C_Container.ContainerIDToInventoryID(index)
    end
    if ContainerIDToInventoryID then return ContainerIDToInventoryID(index) end
    return (CONTAINER_BAG_OFFSET or 19) + index
end

local function BagSlotClick(btn)
    local view = btn._zView
    if view.key == "bank" then
        -- Unpurchased bank slot: the click IS the purchase, through the
        -- same confirmation stock uses so the price is shown first.
        local owned = GetNumBankSlots and GetNumBankSlots() or 0
        if btn._zIndex > owned then
            if btn._zIndex == owned + 1 and StaticPopup_Show then
                local cost = GetBankSlotCost and GetBankSlotCost(owned) or 0
                if BankFrame then BankFrame.nextSlotCost = cost end
                StaticPopup_Show("CONFIRM_BUY_BANK_SLOT")
            end
            return
        end
    end
    local inv = btn._zInv
    if not inv then return end
    if CursorHasItem and CursorHasItem() then
        PutItemInBag(inv)
    else
        PickupBagFromSlot(inv)
    end
end

local function BagSlotTooltip(btn)
    local view = btn._zView
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    if view.key == "bank" then
        local owned = GetNumBankSlots and GetNumBankSlots() or 0
        if btn._zIndex > owned then
            if btn._zIndex == owned + 1 then
                local cost = GetBankSlotCost and GetBankSlotCost(owned) or 0
                GameTooltip:AddLine("Bank bag slot")
                GameTooltip:AddLine("Click to buy for "
                    .. Money(cost),
                    1, 1, 1)
            else
                GameTooltip:AddLine("Bank bag slot")
                GameTooltip:AddLine("Buy the previous slot first.", 0.6, 0.6, 0.6)
            end
            GameTooltip:Show()
            return
        end
    end
    local inv = btn._zInv
    if inv and GameTooltip:SetInventoryItem("player", inv) then
        GameTooltip:AddLine("Drop a bag here to swap it. Click to pick it up.",
            0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine("Empty bag slot")
        GameTooltip:AddLine("Drop a bag here to equip it.", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function CreateBagSlot(view, index)
    local btn = CreateFrame("Button", nil, view.frame)
    btn:SetSize(BAGBTN, BAGBTN)
    btn._zView, btn._zIndex = view, index
    btn._zBagSlot = true
    btn:RegisterForClicks("LeftButtonUp")
    btn:RegisterForDrag("LeftButton")

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon._zui_own = true
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn._zIcon = icon
    pcall(UI.Border, btn, "ui", "border")

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl._zui_own = true
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)

    btn:SetScript("OnClick", BagSlotClick)
    btn:SetScript("OnReceiveDrag", function(self)
        if self._zInv and CursorHasItem and CursorHasItem() then PutItemInBag(self._zInv) end
    end)
    btn:SetScript("OnDragStart", function(self)
        if self._zInv and self._zHasBag then PickupBagFromSlot(self._zInv) end
    end)
    btn:SetScript("OnEnter", BagSlotTooltip)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return btn
end

local function BuildBagBar(view)
    local count = view.key == "bank" and (Bags.NUM_BANKBAGSLOTS or 7) or 4
    view.bagSlots = {}
    local x = PAD
    if view.key ~= "bank" then
        -- The backpack is not a slot - nothing goes in or out of it - but
        -- the row reads wrong without it at the front.
        local pack = CreateFrame("Frame", nil, view.frame)
        pack:SetSize(BAGBTN, BAGBTN)
        pack:SetPoint("TOPLEFT", x, -(M.TITLEBAR + HEADER - BAGBTN - 4))
        local ico = pack:CreateTexture(nil, "ARTWORK")
        ico._zui_own = true
        ico:SetAllPoints()
        ico:SetTexture("Interface\\Buttons\\Button-Backpack-Up")
        ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        pcall(UI.Border, pack, "ui", "border")
        x = x + BAGBTN + 3
    end
    for i = 1, count do
        local btn = CreateBagSlot(view, i)
        btn:SetPoint("TOPLEFT", x, -(M.TITLEBAR + HEADER - BAGBTN - 4))
        view.bagSlots[i] = btn
        x = x + BAGBTN + 3
    end
end

local function PaintBagBar(view)
    if not view.bagSlots then return end
    local owned = view.key == "bank" and (GetNumBankSlots and GetNumBankSlots() or 0) or nil
    for i, btn in ipairs(view.bagSlots) do
        btn._zInv = BagInvSlot(view, i)
        local tex = btn._zInv and GetInventoryItemTexture
            and GetInventoryItemTexture("player", btn._zInv) or nil
        btn._zHasBag = tex ~= nil
        btn._zIcon:SetTexture(tex or EMPTY_SLOT)
        if owned and i > owned then
            btn._zIcon:SetVertexColor(0.45, 0.45, 0.45)
            btn._zIcon:SetDesaturated(true)
        else
            btn._zIcon:SetVertexColor(1, 1, 1)
            btn._zIcon:SetDesaturated(false)
        end
    end
end

-- The window's background and edge: UI.Window's own paint, then the
-- chosen colours over it (so a palette change keeps them).
local function PaintWindow(frame)
    local cfg = BagCfg()
    if frame._zFill and type(cfg.bgColor) == "table" then
        frame._zFill:SetVertexColor(ns.ColorOf(cfg.bgColor))
    end
    if frame._zBorder and type(cfg.frameBorderColor) == "table" then
        local r, g, b, a = ns.ColorOf(cfg.frameBorderColor)
        for _, t in ipairs(frame._zBorder) do t:SetVertexColor(r, g, b, a) end
    end
end

-- The footer's text (free slots, money): ZacUI's font until one is chosen.
local function StyleFooter(list)
    local spec = BagCfg().footerFont
    for _, fs in ipairs(list) do
        if fs and fs.SetFont then
            if Empty(spec) then
                if fs._zCustom then
                    fs._zCustom = nil
                    if ns.HouseFont then ns.HouseFont(fs, F.SMALL) end
                    if fs.SetShadowOffset and fs._zShadow then fs:SetShadowOffset(fs._zShadow[1], fs._zShadow[2]) end
                end
            elseif ns.ApplyFontSpec then
                if not fs._zShadow and fs.GetShadowOffset then fs._zShadow = { fs:GetShadowOffset() } end
                fs._zCustom = true
                local f = ZacUIDB and ZacUIDB.font
                ns.ApplyFontSpec(fs, spec, { size = F.SMALL + ((f and f.delta) or 0),
                    outline = (f and f.outline == "NONE") and "none" or "outline", shadow = true })
            end
        end
    end
end

-- A sample slot for the Bags page: a plain button (no template, no bag,
-- no clicks that reach an item) dressed by DressSlot and painted by
-- PaintSlot, like the real ones.
local function NewSampleSlot(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(SlotSize(), SlotSize())
    btn:EnableMouse(false)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    btn._zIcon = icon
    local count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    if count.GetFont and not count:GetFont() then
        pcall(count.SetFont, count, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    end
    count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 2)
    count:SetJustifyH("RIGHT")
    btn._zCount = count
    DressSlot(btn)
    return btn
end

local function CreateView(key, globalName, title, bagList)
    local view = { key = key, title = title, bagList = bagList,
                   buttons = {}, holders = {} }

    local frame = UI.Window(globalName, 400, 400, title)
    view.frame = frame
    local ownPaint = frame._zPaint
    frame._zPaint = function(self)
        if ownPaint then ownPaint(self) end
        PaintWindow(self)
    end
    frame:_zPaint()

    -- Search + sort row
    local search = UI.EditBox(frame, { width = 180, height = 20,
        hint = "Search" })
    search:SetPoint("TOPLEFT", PAD, -(M.TITLEBAR + 5))
    view.search = search

    -- Classic Era has NO sort API, so this runs ZacUI's own engine: it
    -- combines partial stacks, then orders by category, quality and name,
    -- one move per tick. See Bags_Sort for why it cannot be a loop.
    local sort = UI.Button(frame, "Sort", { width = 58, height = 20,
        tooltip = "Combine partial stacks, then sort by type, quality and "
            .. "name. Moves happen one at a time - this client has no "
            .. "server-side sort, so ZacUI does it by hand." })
    sort:SetPoint("TOPRIGHT", -PAD, -(M.TITLEBAR + 5))
    sort:SetScript("OnClick", function()
        local Sorter = ns.BagSort
        if not Sorter then return end
        if Sorter.IsRunning() then
            Sorter.Cancel()
            return
        end
        Sorter.Sort(bagList, view.title or "Bags")
    end)
    view.sortButton = sort

    -- The bag slots, on their own row under the search box.
    BuildBagBar(view)

    -- Footer: free slots on the left, money on the right
    local free = UI.Font(frame, F.SMALL, { cat = "text", key = "gray" })
    free:SetPoint("BOTTOMLEFT", PAD, 7)
    view.freeText = free

    local money = UI.Font(frame, F.SMALL, { justify = "RIGHT" })
    money:SetPoint("BOTTOMRIGHT", -PAD, 7)
    view.moneyText = money
    -- their spots, for a saved anchor to go on top of
    view.footerDef = {
        free = { point = "BOTTOMLEFT", to = frame, relPoint = "BOTTOMLEFT", x = PAD, y = 7 },
        money = { point = "BOTTOMRIGHT", to = frame, relPoint = "BOTTOMRIGHT", x = -PAD, y = 7, justify = "RIGHT" },
    }
    view.footerTo = function(k)
        if k == "window" then return frame elseif k == "free" then return view.freeText
        elseif k == "money" then return view.moneyText elseif k == "total" then return view.totalText end
    end
    function view:PlaceFooter()
        local cfg = BagCfg()
        if not (BagAnchor(cfg, "free") or BagAnchor(cfg, "money") or self._zFooterMoved) then return end
        self._zFooterMoved = (BagAnchor(cfg, "free") or BagAnchor(cfg, "money")) and true or nil
        PlaceFooterText(self.freeText, "free", cfg, self.footerDef.free, self.footerTo)
        PlaceFooterText(self.moneyText, "money", cfg, self.footerDef.money, self.footerTo)
    end

    -- BOTH NUMBERS, ALWAYS VISIBLE. The two answer different questions -
    -- "can I afford this right now" is this character's purse, "how am I
    -- doing overall" is every character - and putting the second one
    -- behind a hover meant the common question needed a mouse.
    --
    -- The account total sits to the LEFT, dimmed and rounded to whole
    -- gold. Rounded because it is a summary: a running silver-and-copper
    -- tail on a five-figure number is noise, and two full coin strings
    -- side by side would crowd the free-slot count out of a narrow bag.
    local total = UI.Font(frame, F.SMALL, { cat = "text", key = "gray",
        justify = "RIGHT" })
    total:SetPoint("RIGHT", money, "LEFT", -8, 0)
    view.totalText = total
    view.footerTexts = { free, money, total }
    StyleFooter(view.footerTexts)

    local moneyHit = CreateFrame("Frame", nil, frame)
    moneyHit:SetPoint("BOTTOMRIGHT", -PAD + 2, 4)
    -- Wide enough to cover BOTH numbers, so the breakdown is still one
    -- hover away from either of them.
    moneyHit:SetSize(260, 16)
    moneyHit:EnableMouse(true)
    moneyHit:SetScript("OnEnter", function(self)
        local rows, total = Bags.GoldRows()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Gold across all characters")
        GameTooltip:AddLine(" ")
        for _, r in ipairs(rows) do
            local cr, cg, cb = 1, 1, 1
            if r.class then cr, cg, cb = ns.ClassColor(r.class) end
            local label = r.name or "?"
            if r.isMe then label = label .. " |cff888888(here)|r" end
            if r.mail and r.mail > 0 then label = label .. " |cff888888(+mail)|r" end
            GameTooltip:AddDoubleLine(label, Money(r.copper or 0),
                cr, cg, cb, 1, 1, 1)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Total", Money(total),
            1, 0.82, 0, 1, 1, 1)
        -- Said out loud, because a total that silently omits half your
        -- characters is worse than one that admits its edges.
        if Bags.FromReadycheck and Bags.FromReadycheck() then
            GameTooltip:AddLine("Your other accounts come from Readycheck's gold "
                .. "sync (Stats Bar > Gold shows how fresh each one is).", 0.6, 0.6, 0.6, true)
        else
            GameTooltip:AddLine("Characters on other WoW accounts are not "
                .. "visible to addons.", 0.6, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end)
    moneyHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    view.moneyHit = moneyHit

    -- The grid area, and one ID-carrying holder per bag on top of it.
    local grid = CreateFrame("Frame", nil, frame)
    grid:SetPoint("TOPLEFT", PAD, -(M.TITLEBAR + HEADER))
    grid:SetPoint("BOTTOMRIGHT", -PAD, FOOTER)
    view.grid = grid

    for _, bag in ipairs(bagList) do
        local holder = CreateFrame("Frame", nil, grid)
        holder:SetAllPoints()
        holder:SetID(bag)          -- THE reason these exist
        view.holders[bag] = holder
    end

    search.editBox:HookScript("OnTextChanged", function()
        view:Refresh()
    end)

    function view:Button(bag, index)
        self.buttons[bag] = self.buttons[bag] or {}
        local list = self.buttons[bag]
        if not list[index] then
            local btn = NewItemButton(self.holders[bag])
            if not btn then return nil end
            btn:SetID(index)
            -- the secure use path addresses the PHYSICAL slot, so the
            -- attribute pair is fixed for the button's whole life -
            -- whatever sits in the slot later is what gets used.
            -- ATTRIBUTE CONTRACT, learned the hard way: "bag"+"slot" is
            -- the container form. A bare NUMBER in the "item" attribute
            -- means an INVENTORY slot - bag indexes 13/14 landed on the
            -- trinket slots and right-clicking a bag item fired a
            -- trinket. Never put a number in "item".
            if btn._zSecureUse then
                btn:SetAttribute("slot", index)
                btn:SetAttribute("item", nil)
            end
            list[index] = btn
        end
        return list[index]
    end

    -- ============================================================
    -- REFRESH IS TWO HALVES, AND THE SPLIT IS THE WHOLE POINT
    -- ============================================================
    -- The buttons carry SecureActionButtonTemplate, so they are PROTECTED
    -- frames. Blocked in combat: creating them, SetAttribute, SetPoint /
    -- ClearAllPoints / Show / Hide on them, and SetSize on the window
    -- that anchors them.
    --
    -- NOT blocked, and this is the part a blanket combat bail got wrong:
    -- textures, font strings, SetAlpha and Cooldown:SetCooldown. Freezing
    -- those too meant every icon vanished the moment a fight started -
    -- a bag you cannot read in combat is worse than the taint it avoided.
    --
    -- So: Layout() is the protected half and defers, Paint() is the safe
    -- half and always runs.

    -- Positions only ever need redoing when the column count or a bag's
    -- size changed. Signature-gated so the common case - a stack moved,
    -- an item looted - never touches a protected call at all.
    local function LayoutSig(self)
        local cols = math.max(4, (ZacUIDB.bags and ZacUIDB.bags.columns) or 10)
        local sig = cols .. ":" .. SlotSize() .. ":" .. SlotGap()
        for _, bag in ipairs(self.bagList) do
            sig = sig .. ":" .. tostring(Bags.Slots(bag))
        end
        return sig, cols
    end

    -- In the default plain mode a closed window is laid out when it next
    -- opens (OnShow refreshes), so a bag event with the bag shut costs
    -- nothing here. Only the opt-in secure mode lays out while closed:
    -- its buttons cannot be created or moved once a fight starts, so the
    -- grid has to be ready before one does.
    function view:Layout(force)
        if not force and not self.frame:IsShown() and not SecureActive() then
            return true
        end
        if SecureActive() and InCombatLockdown and InCombatLockdown() then
            self._layoutPending = true
            return false
        end
        local sig, cols = LayoutSig(self)
        if not force and sig == self._layoutSig then
            self._layoutPending = nil
            return true
        end

        local n = 0
        local size, gap = SlotSize(), SlotGap()
        for _, bag in ipairs(self.bagList) do
            local slots = Bags.Slots(bag)
            for slot = 1, slots do
                local btn = self:Button(bag, slot)
                if btn then
                    local col = n % cols
                    local row = math.floor(n / cols)
                    btn:ClearAllPoints()
                    btn:SetSize(size, size)
                    btn:SetPoint("TOPLEFT", self.grid, "TOPLEFT",
                        col * (size + gap), -row * (size + gap))
                    btn:Show()
                    -- Shown ONCE, here, and never toggled again: the
                    -- cooldown is a child of a protected button, so
                    -- Show/Hide on it is refused in combat as well.
                    -- Paint drives it with SetCooldown alone, which is
                    -- not protected - that is why CooldownFrame_Set,
                    -- which shows and hides internally, is not used.
                    if btn._zCooldown and btn._zCooldown.Show then
                        btn._zCooldown:Show()
                    end
                    n = n + 1
                end
            end
            -- Slots that vanished when a smaller bag was equipped.
            local list = self.buttons[bag]
            if list then
                for i = slots + 1, #list do list[i]:Hide() end
            end
        end

        -- Size the window to the grid it actually drew.
        local rows = math.max(1, math.ceil(n / cols))
        local w = PAD * 2 + cols * size + (cols - 1) * gap
        local h = M.TITLEBAR + HEADER + rows * size + (rows - 1) * gap + FOOTER + 6
        self.frame:SetSize(math.max(300, w), h)

        self._layoutSig = sig
        self._layoutPending = nil
        return true
    end

    local function PaintCooldown(btn, bag, slot)
        if btn._zCooldown and btn._zCooldown.SetCooldown then
            local start, duration, enable = Bags.Cooldown(bag, slot)
            if enable and enable ~= 0 and duration and duration > 0 then
                btn._zCooldown:SetCooldown(start or 0, duration)
            else
                btn._zCooldown:SetCooldown(0, 0)
            end
        end
    end

    -- The footer: free slots (counted off the API, not off the buttons -
    -- a bag equipped in combat has no buttons yet and the count should
    -- still tell the truth), this character's money and everyone's.
    -- Item reads come from the shared cache, so this is cheap after a
    -- partial paint has already refreshed the bags that changed.
    function view:PaintFooter()
        local freeCount, totalCount = 0, 0
        for _, bag in ipairs(self.bagList) do
            local slots = Bags.Slots(bag)
            totalCount = totalCount + slots
            for slot = 1, slots do
                if not Bags.Item(bag, slot) then freeCount = freeCount + 1 end
            end
        end
        self.freeText:SetText(freeCount .. " / " .. totalCount .. " free")
        self:PlaceFooter()
        self:PaintMoney()
    end

    function view:PaintMoney()
        if GetMoney then
            -- This character, exact, to the copper.
            self.moneyText:SetText(MoneyText(GetMoney(), BagCfg()))
            -- Everyone, to the gold. "all" rather than a sigma so it
            -- reads without needing to be explained.
            self.totalText:SetText("all " .. Money(Bags.GoldTotal(), "gold"))
        end
    end

    -- Contents. Nothing in here is a protected call, so it runs in combat
    -- exactly as it does out of it. bags = a set of bag ids to repaint,
    -- or nil for every bag.
    function view:Paint(bags)
        local query = self.search:GetText()
        local searching = query and query ~= ""

        for _, bag in ipairs(self.bagList) do
            local list = self.buttons[bag]
            if list and (not bags or bags[bag]) then
                for slot = 1, Bags.Slots(bag) do
                    local btn = list[slot]
                    if btn then
                        local item = Bags.Item(bag, slot)
                        local isQuest = item and item.isQuest or false
                        if SetItemButtonCount then
                            SetItemButtonCount(btn, item and item.count or 0)
                        end
                        if SetItemButtonDesaturated then
                            SetItemButtonDesaturated(btn, item and item.locked or false)
                        end
                        PaintCooldown(btn, bag, slot)

                        -- PaintSlot sets the icon, because PaintSlot is what
                        -- sweeps the slot art - doing it the other way round
                        -- meant every icon was assigned and then immediately
                        -- wiped on the same pass.
                        local faded = searching
                            and not Bags.Matches(item, query, bag, slot, isQuest)
                        PaintSlot(btn, item, isQuest, faded)
                    end
                end
            end
        end

        self:PaintFooter()
    end

    -- Only the cooldown swipes: no item reads, no slot art. This is what
    -- a BAG_UPDATE_COOLDOWN-only batch gets, which in a fight with the
    -- bags open is every global cooldown.
    function view:PaintCooldowns()
        for _, bag in ipairs(self.bagList) do
            local list = self.buttons[bag]
            if list then
                for slot = 1, Bags.Slots(bag) do
                    local btn = list[slot]
                    if btn then PaintCooldown(btn, bag, slot) end
                end
            end
        end
    end

    -- batch: what changed (see Bags_Core's notification), or nil for
    -- everything. A closed window does nothing but the secure-mode
    -- layout; it is repainted in full when it opens.
    function view:Refresh(batch)
        if batch and not batch.full and not next(batch.bags) then
            if self.frame:IsShown() then
                if batch.cooldown then self:PaintCooldowns() end
                if batch.money then self:PaintMoney() end
            end
            return
        end
        self:Layout()
        if self.frame:IsShown() then
            local bags = batch and not batch.full and batch.bags or nil
            self:Paint(bags)
            if batch and batch.cooldown and bags then self:PaintCooldowns() end
            PaintBagBar(self)
        end
    end

    frame:HookScript("OnShow", function() view:Refresh() end)
    -- A button hidden or re-anchored under the cursor never gets its
    -- OnLeave, so a tooltip it owns is stranded on screen with nothing to
    -- dismiss it. Closing the window takes ours with it.
    frame:HookScript("OnHide", function()
        local owner = GameTooltip:GetOwner()
        if owner and owner._zBagSlot then GameTooltip:Hide() end
    end)
    views[key] = view
    return view
end

-- ============================================================
-- MODULE
-- ============================================================
Modules.inventory = function()
    -- A dedicated bag addon and a combined bag are the same job. Whichever
    -- the user has loaded wins; ZacUI does not draw a second one.
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if isLoaded then
        for _, other in ipairs({ "Baganator", "Bagnon", "AdiBags",
                                 "ArkInventory", "Baggins", "OneBag3" }) do
            local ok, res = pcall(isLoaded, other)
            if ok and res then
                Print("inventory: " .. other .. " is loaded - ZacUI's own bag "
                    .. "stays out of the way. Disable " .. other
                    .. " (or turn this module off) to pick one.")
                return
            end
        end
    end

    ZacUIDB.bags = ZacUIDB.bags or { columns = 10 }

    -- IDEMPOTENT BY CONSTRUCTION. ApplyAll pcalls every module and the
    -- live-enable path can call this again, so a second run must not
    -- build a second pair of windows - the bag keybinding closes over
    -- the FIRST window, and a rebuild would leave it driving an orphan
    -- while the visible one never opens.
    if views.inventory then
        views.inventory:Refresh()
        views.bank:Refresh()
        return
    end

    Bags.StartEvents()
    StartCombatWatch()

    local inv = CreateView("inventory", "ZacUIBagFrame", "Inventory",
        Bags.BACKPACK_BAGS)
    local bank = CreateView("bank", "ZacUIBankFrame", "Bank",
        Bags.BANK_BAGS)
    inv.frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -20, 60)
    bank.frame:SetPoint("LEFT", UIParent, "LEFT", 40, 60)

    Bags.Subscribe(function(batch)
        inv:Refresh(batch)
        bank:Refresh(batch)
    end)

    -- Other accounts' gold arrives with no bag event to repaint on; the
    -- total alone is refreshed every two seconds while a window is up.
    -- One ticker for both windows.
    if C_Timer and C_Timer.NewTicker then
        local ticker = C_Timer.NewTicker(2, function()
            for _, view in pairs(views) do
                if view.frame:IsShown() then
                    view.totalText:SetText("all " .. Money(Bags.GoldTotal(), "gold"))
                end
            end
        end)
        if ns.Profiler then ns.Profiler.TrackTicker(ticker, "Bags gold total") end
    end

    -- Build the grid NOW, while the window is still closed and we are
    -- certainly out of combat. Without this, a character who logs in and
    -- pulls before ever pressing B opens an empty box mid-fight (secure
    -- mode cannot create buttons under a lockdown; plain mode would pay
    -- for creating a hundred buttons on the first open).
    inv:Layout(true)
    bank:Layout(true)

    -- TAKING OVER THE BAG KEYS. These are ordinary Lua globals in
    -- FrameXML, not protected functions, and replacing them is how every
    -- bag addon hooks the B key, the bag buttons and the merchant/bank
    -- auto-open. The originals are kept so turning the module off and
    -- reloading restores stock behaviour exactly.
    if not ZUI._bagHooked then
        ZUI._bagHooked = {
            ToggleAllBags = ToggleAllBags, OpenAllBags = OpenAllBags,
            CloseAllBags = CloseAllBags, ToggleBackpack = ToggleBackpack,
            OpenBackpack = OpenBackpack, CloseBackpack = CloseBackpack,
            ToggleBag = ToggleBag, OpenBag = OpenBag, CloseBag = CloseBag,
        }
        -- ============================================================
        -- THE WINDOW ITSELF CANNOT OPEN IN COMBAT
        -- ============================================================
        -- A frame counts as protected if any DESCENDANT is protected -
        -- Blizzard closes the obvious hole where you would hide the
        -- parent of a secure button instead of the button. Every slot in
        -- here inherits SecureActionButtonTemplate, so ZacUIBagFrame is
        -- protected by ancestry and Show/Hide on it is refused under a
        -- lockdown. There is no wrapper around that; it is the standing
        -- price of the secure right-click use path, the same reason
        -- action bars cannot be shown or hidden mid-fight either.
        --
        -- SetAlpha is not protected and would fake it visually - but
        -- EnableMouse IS protected, so an alpha-0 window would still be
        -- sitting there eating clicks over live item slots. Not worth it.
        --
        -- So the keys QUEUE. The window does what you asked the instant
        -- the lockdown lifts, and you are told once instead of watching
        -- BugSack fill up with blocked-action reports.
        local pendingBag, warned = nil, false
        local function Locked()
            -- Plain mode: never locked. Nothing in the window is
            -- protected, so Show and Hide are ordinary calls.
            return SecureActive() and InCombatLockdown and InCombatLockdown()
        end
        local function WarnOnce()
            if warned then return end
            warned = true
            Print("bags: the window can't open or close in combat - its "
                .. "slots are secure buttons, so the frame is protected. "
                .. "Queued; it will follow the moment you drop combat. "
                .. "/run ZacUIDB.bags.secureUse = false (then /reload) "
                .. "trades combat right-click-use for a window that opens.")
        end
        -- The open and close animations (none unless chosen on the Bags
        -- page). A window still playing its close counts as closed, so a
        -- toggle mid-close opens it again rather than closing it twice.
        local function Anim(key)
            local spec = BagCfg()[key]
            if type(spec) == "table" and spec.style and spec.style ~= "none" and ns.Motion then
                return spec
            end
        end
        local function Closing()
            local m = inv.frame._zMotion
            return m and m.how == "out"
        end
        local function Open()
            if Locked() then pendingBag = true WarnOnce() return end
            pendingBag = nil
            local spec = Anim("openAnim")
            if spec and (not inv.frame:IsShown() or Closing()) then
                ns.Motion.Play(inv.frame, spec, "in")
            else
                inv.frame:Show()
            end
        end
        local function Close()
            local was = inv.frame:IsShown() and not Closing()
            if Locked() then pendingBag = false WarnOnce() return was end
            pendingBag = nil
            local spec = Anim("closeAnim")
            if spec and was then
                ns.Motion.Play(inv.frame, spec, "out")
            elseif not Closing() then
                inv.frame:Hide()
            end
            return was
        end
        local function Toggle()
            if Locked() then
                local want = pendingBag
                if want == nil then want = inv.frame:IsShown() end
                pendingBag = not want
                WarnOnce()
                return
            end
            if inv.frame:IsShown() and not Closing() then Close() else Open() end
        end
        DrainBagToggle = function()
            if pendingBag == nil then return end
            local want = pendingBag
            pendingBag = nil
            if want then inv.frame:Show() else inv.frame:Hide() end
        end
        ToggleAllBags, OpenAllBags, CloseAllBags = Toggle, Open, Close
        ToggleBackpack, OpenBackpack, CloseBackpack = Toggle, Open, Close
        ToggleBag, OpenBag, CloseBag = Toggle, Open, Close
    end

    -- Blizzard still shows its own frames from paths we have not replaced
    -- (looting a full bag, a vendor opening bags). Hiding on show is the
    -- catch-all; it is safe because these frames are not protected.
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local cf = _G["ContainerFrame" .. i]
        if cf then
            cf:HookScript("OnShow", function(self) self:Hide() end)
            cf:Hide()
        end
    end

    -- ============================================================
    -- BLIZZARD'S BANK: NEVER SHOWN, SO NEVER HIDDEN
    -- ============================================================
    -- The ContainerFrame trick above does not transfer. BankFrame's
    -- OnHide runs CloseBankFrame(), so hiding it does not just remove a
    -- window - it ENDS THE BANKING SESSION. You would get a clean screen
    -- and no bank.
    --
    -- Parking it off-screen lost: the UI panel manager re-anchors the
    -- frame after OnShow, so the panel kept walking back on screen. The
    -- next fix hid it with CloseBankFrame swapped for a stub for the
    -- length of the call - but writing a Blizzard global from addon code
    -- taints it for the session, and every secure path that reads it
    -- after that (Esc closing the panels, among others) runs tainted.
    --
    -- So BankFrame is never shown at all. The only thing that shows it is
    -- its own BANKFRAME_OPENED handler (ShowUIPanel, and CloseBankFrame
    -- if that failed); with that one event unregistered the panel stays
    -- hidden, its OnHide never runs, and the session stays open until
    -- the player walks away (BANKFRAME_CLOSED), as before. Nothing is
    -- written - no global, no method, no script. Deposit, withdraw, bag
    -- slots and buying a slot are container / bank API calls that only
    -- need the session, not Blizzard's window. Its other events
    -- (BANKFRAME_CLOSED, slot changes) stay: they only touch a hidden
    -- frame.
    --
    -- The panel manager never sees it either, so the other open panels
    -- no longer shuffle for one frame while it showed and hid.
    --
    -- Turned on live while Blizzard's bank is already open, the safety net
    -- below hides its window for that visit; the next one never shows it.
    local bankHost = _G.BankFrame
    if bankHost and bankHost.UnregisterEvent then
        bankHost:UnregisterEvent("BANKFRAME_OPENED")
    end

    -- Safety net. If this client shows BankFrame some other way than its
    -- own BANKFRAME_OPENED handler, the old hide is used for that visit:
    -- alpha 0 at once, then HideUIPanel with CloseBankFrame stubbed for
    -- the length of the call (its OnHide would otherwise end the
    -- session). That path writes a Blizzard global, so it only ever runs
    -- if the panel shows despite the event being gone.
    local function HideBlizzardBank()
        local bf = _G.BankFrame
        if not bf or not bf:IsShown() then return end
        local realClose = _G.CloseBankFrame
        _G.CloseBankFrame = function() end
        if _G.HideUIPanel then
            pcall(_G.HideUIPanel, bf)
        else
            pcall(bf.Hide, bf)
        end
        _G.CloseBankFrame = realClose
    end
    if _G.BankFrame then
        _G.BankFrame:HookScript("OnShow", function()
            -- Alpha first so not even one frame of it is drawn, then
            -- hidden outright on the next tick - hiding inside OnShow
            -- itself re-enters the panel manager mid-show.
            _G.BankFrame:SetAlpha(0)
            if C_Timer and C_Timer.After then
                C_Timer.After(0, HideBlizzardBank)
            else
                HideBlizzardBank()
            end
        end)
        if _G.BankFrame:IsShown() then
            _G.BankFrame:SetAlpha(0)
            HideBlizzardBank()
        end
    end

    -- The bank window follows the bank itself.
    local bankEvents = CreateFrame("Frame")
    bankEvents:RegisterEvent("BANKFRAME_OPENED")
    bankEvents:RegisterEvent("BANKFRAME_CLOSED")
    bankEvents:SetScript("OnEvent", function(_, event)
        if event == "BANKFRAME_OPENED" then
            bank.frame:Show()
            inv.frame:Show()
        else
            bank.frame:Hide()
        end
    end)

    ns.BagViews = views
end

-- shared with later ZacUI files
ns.BagViews = views

-- The Bags page: its samples are built and painted by these, and a
-- change there restyles and re-lays out the open windows at once.
ns.BagLook = {
    DEFAULTS = BAG_LOOK,
    Cfg = BagCfg,
    SlotSize = SlotSize,
    SlotGap = SlotGap,
    NewSample = NewSampleSlot,
    Paint = PaintSlot,
    Style = StyleSlot,
    PaintWindow = PaintWindow,
    StyleFooter = StyleFooter,
    PlaceFooterText = PlaceFooterText,
    MoneyText = MoneyText,
    COUNT_TARGETS = { { value = "slot", text = "The slot" }, { value = "icon", text = "The icon" } },
    FOOTER_TARGETS = { { value = "window", text = "The window" }, { value = "free", text = "Free slots" },
        { value = "money", text = "Your money" } },
    Changed = function()
        lookVer = lookVer + 1
        for _, view in pairs(views) do
            if view.frame then view.frame:_zPaint() end
            if view.footerTexts then StyleFooter(view.footerTexts) end
            if view.PlaceFooter then view:PlaceFooter() end
            view:Refresh()
        end
    end,
}
if ns.OnSettingsChanged and ns.Coalesce then
    ns.OnSettingsChanged(ns.Coalesce(function()
        local s = ns.ConfigState and ns.ConfigState()
        if s and s.selected == "bags" then ns.BagLook.Changed() end
    end))
end
