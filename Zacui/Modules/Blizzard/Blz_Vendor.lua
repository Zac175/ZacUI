-- Blz_Vendor - mailbox and merchant windows.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local Col = ns.Col
local Modules = ns.Modules
local PinFontObject = ns.PinFontObject
local RecolorParchmentFonts = ns.RecolorParchmentFonts
local SkinArrowButton = ns.SkinArrowButton
local SkinEditBox = ns.SkinEditBox
local SkinIconButton = ns.SkinIconButton
local SkinPanel = ns.SkinPanel
local StripDeep = ns.StripDeep
local StripTextures = ns.StripTextures

Modules.mail = function()
    RecolorParchmentFonts()
    SkinPanel(MailFrame, { tabs = "MailFrameTab", tabCount = 2, buttons = {
        "SendMailMailButton", "SendMailCancelButton",
        "OpenMailReplyButton", "OpenMailDeleteButton", "OpenMailCancelButton",
        "OpenMailReportSpamButton",
    }})
    if InboxPrevPageButton then SkinArrowButton(InboxPrevPageButton, "left") end
    if InboxNextPageButton then SkinArrowButton(InboxNextPageButton, "right") end

    for i = 1, 7 do
        local row = _G["MailItem" .. i]
        if row then StripTextures(row) end
        local ib = _G["MailItem" .. i .. "Button"]
        if ib then SkinIconButton(ib) end
    end
    for i = 1, (ATTACHMENTS_MAX_SEND or 12) do
        local ab = _G["SendMailAttachment" .. i]
        if ab then SkinIconButton(ab, true) end
    end
    for i = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
        local ab = _G["OpenMailAttachmentButton" .. i]
        if ab then SkinIconButton(ab) end
    end
    if OpenMailPackageButton then SkinIconButton(OpenMailPackageButton) end
    if OpenMailLetterButton then SkinIconButton(OpenMailLetterButton) end

    if OpenMailFrame then
        SkinPanel(OpenMailFrame)
    end
    -- (2026-11-10, Zac's Send Mail screenshot) the letter's own scroll bars
    -- kept the game's stone art
    if ns.SkinScrollFrame then
        if SendMailScrollFrame then ns.SkinScrollFrame("SendMailScrollFrame") end
        if OpenMailScrollFrame then ns.SkinScrollFrame("OpenMailScrollFrame") end
    end
    if SendMailSubjectEditBox then SkinEditBox(SendMailSubjectEditBox) end
    if SendMailNameEditBox then SkinEditBox(SendMailNameEditBox) end

    -- Page art on the tab CHILD frames, which the MailFrame strip never
    -- reaches: the inbox parchment (stripped by frame, not by its
    -- "InboxFrameBg" global - ItemTextFrame reuses that exact name), the
    -- send page's divider bars.
    if InboxFrame then StripTextures(InboxFrame) end
    if SendMailFrame then
        -- The error coin is a region on the same frame: spared, or a
        -- "not enough money" error would show without its icon.
        for _, region in ipairs({ SendMailFrame:GetRegions() }) do
            if region.IsObjectType and region:IsObjectType("Texture")
                and region ~= SendMailErrorCoin then
                region:SetTexture(nil)
                region:Hide()
            end
        end
    end
    -- STATIONERY: Blizzard re-sets these per letter, so they are blanked by
    -- alpha (which survives SetTexture) rather than stripped once. The body
    -- font is dark-on-parchment, so it is pinned light BEFORE the paper goes.
    PinFontObject(MailTextFontNormal, "text", 0.92, 0.92, 0.92)
    for _, n in ipairs({ "SendStationeryBackgroundLeft", "SendStationeryBackgroundRight",
                         "OpenStationeryBackgroundLeft", "OpenStationeryBackgroundRight" }) do
        local t = _G[n]
        if t and t.SetAlpha then t:SetAlpha(0) end
    end
    -- The letter body is a SimpleHTML: per-tag colours, no FontString pin
    -- applies (and PinTextLight's hook would misread the tag argument).
    if OpenMailFrame and OpenMailBodyText then
        OpenMailFrame:HookScript("OnShow", function()
            C_Timer.After(0, function()
                local c = Col("text")
                for _, tag in ipairs({ "p", "h1", "h2", "h3" }) do
                    pcall(OpenMailBodyText.SetTextColor, OpenMailBodyText, tag, c.r, c.g, c.b)
                end
            end)
        end)
    end
end

-- MERCHANT
Modules.merchant = function()
    SkinPanel(MerchantFrame, { tabs = "MerchantFrameTab", tabCount = 2 })

    if MerchantPrevPageButton then SkinArrowButton(MerchantPrevPageButton, "left") end
    if MerchantNextPageButton then SkinArrowButton(MerchantNextPageButton, "right") end

    for i = 1, 12 do
        local row = _G["MerchantItem" .. i]
        if row then StripTextures(row) end
        local ib = _G["MerchantItem" .. i .. "ItemButton"]
        if ib then SkinIconButton(ib) end
    end
    if MerchantBuyBackItem then StripTextures(MerchantBuyBackItem) end
    if MerchantBuyBackItemItemButton then SkinIconButton(MerchantBuyBackItemItemButton) end

    -- Player-gold footer at shops: the chrome around the coin display.
    -- Explicit appends (hole-in-ipairs law): the two classic globals can
    -- be nil on the modern template, and a nil FIRST slot killed the
    -- whole loop - keyed modern chrome included.
    local moneyChrome = {}
    local function AddMoneyChrome(c)
        if c then moneyChrome[#moneyChrome + 1] = c end
    end
    AddMoneyChrome(MerchantMoneyInset)
    AddMoneyChrome(MerchantMoneyBg)
    AddMoneyChrome(MerchantFrame and MerchantFrame.MoneyFrameBorder)
    AddMoneyChrome(MerchantFrame and MerchantFrame.MoneyFrameInset)
    for _, mchrome in ipairs(moneyChrome) do
        if mchrome then
            if mchrome.IsObjectType and mchrome:IsObjectType("Texture") then
                mchrome:SetTexture(nil)
                mchrome:SetAlpha(0)
            else
                StripDeep(mchrome, 1)
            end
        end
    end

    -- REPAIR ROW (11509 fix for "hidden repair icon"): the anvil/hammer
    -- icons are plain ARTWORK regions on a shared RepairIcons sheet -
    -- NOT the buttons' normal textures, and two of the three don't match
    -- the <Name>Icon global pattern. Adopt each icon under the .Icon key
    -- BEFORE the sweep so the keep-set protects it, and flag no-crop:
    -- re-cropping a sheet texture slides its texcoords onto the wrong
    -- icon.
    if MerchantRepairAllButton and not MerchantRepairAllButton.Icon
        and MerchantRepairAllIcon then
        MerchantRepairAllButton.Icon = MerchantRepairAllIcon
    end
    if MerchantRepairItemButton and not (MerchantRepairItemButton.Icon
        or MerchantRepairItemButton.icon) then
        -- The per-item repair icon is an UNNAMED texture on the BORDER
        -- layer (verified in the 1.15.9 XML - not ARTWORK, so no layer
        -- test). Take the first texture region that is not one of the
        -- button's special textures (pushed/highlight/normal/disabled) -
        -- the button carries exactly one such region: the icon.
        local rb = MerchantRepairItemButton
        local special = {}
        for _, getter in ipairs({ "GetPushedTexture", "GetHighlightTexture",
                                  "GetNormalTexture", "GetDisabledTexture" }) do
            local t = rb[getter] and rb[getter](rb)
            if t then special[t] = true end
        end
        for _, region in ipairs({ rb:GetRegions() }) do
            if region.IsObjectType and region:IsObjectType("Texture")
                and not special[region] then
                rb.Icon = region
                break
            end
        end
    end
    -- HD REPLACEMENT. Adopting Blizzard's own art kept the repair buttons
    -- WORKING, but it did not make them look like the rest of the UI: the
    -- three anvil/hammer glyphs live together on one small shared sheet
    -- (UI-Merchant-RepairIcons), so each one is only a fraction of an
    -- already-tiny file. Drawn at slot size next to real 64px icons they
    -- read as blurry mush - the "repair icons aren't HD" complaint.
    --
    -- There is no HD version of that sheet to switch to, so point the
    -- regions at real Interface\Icons art instead. These are ordinary
    -- square icons, which means the sheet problem goes away entirely and
    -- the standard crop applies again - hence _zui_noCrop is now only set
    -- when the swap did NOT happen.
    -- Every path here is verified to exist in 1.15 (Classic-era icons
    -- only). A path that does NOT exist renders as the flat missing-
    -- texture block, which would be worse than the blurry sheet - so do
    -- not swap any of these for a later-expansion icon without checking
    -- it first. INV_Hammer_20, the obvious pick for the item button, is
    -- a Mists addition and is exactly the trap this note is about.
    --
    -- Built as pairs rather than a keyed table on purpose: the buttons
    -- ARE the keys, MerchantGuildBankRepairButton does not exist on this
    -- client, and `{ [nil] = x }` is a hard "table index is nil" error
    -- that would take the whole merchant skin with it. Same hole-in-
    -- ipairs law as the money chrome above - append only what is real.
    local repairs = {}
    local function AddRepair(btn, hdIcon)
        if btn then repairs[#repairs + 1] = { btn = btn, hd = hdIcon } end
    end
    AddRepair(MerchantRepairAllButton,       "Interface\\Icons\\Trade_BlackSmithing")
    AddRepair(MerchantRepairItemButton,      "Interface\\Icons\\INV_Hammer_15")
    AddRepair(MerchantGuildBankRepairButton, "Interface\\Icons\\INV_Misc_Coin_01")

    -- Resolve the icon the SAME way SkinIconButton does. Reading only
    -- .Icon/.icon was not enough: MerchantGuildBankRepairButton's icon is
    -- the global MerchantGuildBankRepairButtonIcon, which neither key
    -- reaches, so that button fell to the else-branch and came out
    -- UNCROPPED - worse than before the swap. It does not exist on 11509,
    -- but a lookup that silently degrades on the one button nobody can
    -- see is the kind of thing that resurfaces on a later client.
    local function RepairIconOf(rb)
        local n = rb.GetName and rb:GetName()
        return rb.Icon or rb.icon
            or (n and (_G[n .. "IconTexture"] or _G[n .. "Icon"]
                or _G[n:gsub("Button$", "") .. "Icon"]))
    end

    for _, rec in ipairs(repairs) do
        local rb = rec.btn
        local target = RepairIconOf(rb)
        if target and target.SetTexture then
            target:SetTexture(rec.hd)
            -- The sheet coords are still on the region from Blizzard's
            -- XML; a real icon needs the full rect back before the
            -- standard 0.08-0.92 crop means anything.
            if target.SetTexCoord then target:SetTexCoord(0, 1, 0, 1) end
        else
            -- Icon never resolved, so Blizzard's sheet region is still
            -- whatever is drawing. Leave its texcoords alone.
            rb._zui_noCrop = true
        end
        SkinIconButton(rb, true)
    end
end

-- CHARACTER PANE
