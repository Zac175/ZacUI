-- Mod_Classifier - THE classifier. Every widget-KIND rule lives in one
-- function, fed by the login sweep and the new-frame watcher.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local Col = ns.Col
local FLAT = ns.FLAT
local GetArtSignature = ns.GetArtSignature
local Modules = ns.Modules
local SkinAnyScrollBar = ns.SkinAnyScrollBar
local SkinArrowButton = ns.SkinArrowButton
local SkinBackdrop = ns.SkinBackdrop
local SkinBlizzCheck = ns.SkinBlizzCheck
local SkinButton = ns.SkinButton
local SkinCloseButton = ns.SkinCloseButton
local SkinEditBox = ns.SkinEditBox
local SkinStaticPopup = ns.SkinStaticPopup
local StripDeep = ns.StripDeep
local StripFrameChrome = ns.StripFrameChrome
local StripTextures = ns.StripTextures
local ZUI = ns.ZUI

-- ============================================================
-- THE CLASSIFIER - one function holding EVERY kind rule. The login sweep
-- and the new-frame watcher both feed frames through here; adding a rule
-- here covers the whole UI, past and future. No more per-thing code.
-- ============================================================
-- IS THIS BUTTON'S ART CHROME, OR IS IT THE CONTENT?
--
-- The panel-button rule below keys off the SHAPE of UIPanelButtonTemplate
-- - Left/Middle/Right side pieces plus a label - and that shape is also
-- what most addons build their icon buttons from: create from the
-- template, blank the label, SetNormalTexture(the icon). Gargul's
-- edit/delete squares, every addon's minimap-style toggles, half the
-- toolbars in the game. SkinButton then cleared the normal texture as if
-- it were the gray gradient, and what was left was a bordered empty box:
-- "buttons and icons from other addons just vanish".
--
-- So the normal texture decides. Blizzard's button chrome lives under
-- Interface\Buttons\ (UI-Panel-Button-Up and its family) or is an atlas
-- whose name says "button". Anything else - an addon's own asset path,
-- Interface\Icons\, a spell icon - is what the button IS, and a skin that
-- removes it has not skinned the button, it has deleted it.
local function IsButtonChrome(sig)
    if not sig then return true end                 -- no art: a plain text button
    if sig:find("^interface[\\/]+buttons[\\/]") then return true end
    if not sig:find("[\\/]") and sig:find("button") then return true end  -- atlas
    return false
end

-- THE MODERN TAB (WoW Forever, 2026-11-07). Forever's windows use the
-- Mainline tab template, which has no LeftDisabled piece: its tell is the
-- keyed LeftActive art. Without it those tabs fell to the panel-button
-- rule below and kept Blizzard's overlapping layout. Only on the Forever
-- client, so Classic Era's and TBC's tabs are routed exactly as before.
local function MainlineTab(frame)
    return _G.ZACUI_MODERN and rawget(frame, "LeftActive") ~= nil and rawget(frame, "MiddleActive") ~= nil
end

local function ClassifyAndSkin(frame)
    if ZUI.skinned[frame] then return end

    -- PROTECTED-FRAME FIREWALL (1.15.9 doctrine): nameplates, Compact*
    -- unit frames, and Edit Mode systems are secure/managed frames on
    -- the shared-code client. No current rule happens to fire on them -
    -- this guard makes that structural instead of accidental: a single
    -- insecure write to a CompactUnitFrame taints raid-frame updates
    -- in combat, and one future edgeFile in the black-lines rule is
    -- all it would take. Forbidden frames are fenced FIRST, before any
    -- other method call can throw; both cases are marked skinned so no
    -- later pass ever probes them again.
    if frame.IsForbidden and frame:IsForbidden() then
        ZUI.skinned[frame] = true
        return
    end
    local name = frame.GetName and frame:GetName()
    if name and (name:find("^NamePlate") or name:find("^Compact")
        or name:find("^EditMode")) then
        ZUI.skinned[frame] = true
        return
    end

    local otype = frame.GetObjectType and frame:GetObjectType()

    if otype == "Slider" and frame.GetThumbTexture then
        local parent = frame.GetParent and frame:GetParent()
        if (name and name:find("ScrollBar"))
            or (parent and parent.GetObjectType
                and parent:GetObjectType() == "ScrollFrame") then
            SkinAnyScrollBar(frame)
        end

    elseif otype == "Button" then
        local sig = GetArtSignature(frame)
        if name and name:find("Close") and not name:find("Closed") then
            -- Name-based catch: strip passes can erase a close's art
            -- BEFORE the signature check sees it (the bag X survived
            -- exactly this way). The name survives everything.
            SkinCloseButton(frame)
        elseif sig and (sig:find("closebutton") or sig:find("minimizebutton")
            or sig:find("redbutton%-exit") or sig:find("%-close")) then
            SkinCloseButton(frame)
        elseif sig and sig:find("nextpage") then
            SkinArrowButton(frame, "right")
        elseif sig and sig:find("prevpage") then
            SkinArrowButton(frame, "left")
        elseif sig and sig:find("scrollupbutton") then
            SkinArrowButton(frame, "up")
        elseif sig and sig:find("scrolldownbutton") then
            SkinArrowButton(frame, "down")
        elseif name and (_G[name .. "LeftDisabled"] or MainlineTab(frame)) and name:find(".Tab%d+$")
            and not name:find("^AuctionFrameTab")
            and frame.GetFontString and frame:GetFontString()
            and IsButtonChrome(sig) and ns.SkinBottomTabs then
            -- TAB-template buttons (LeftDisabled is the tab templates'
            -- tell; panel buttons lack it). Skinned as a panel button they
            -- kept Blizzard's overlap geometry - flat AND overlapping.
            -- Route the whole sibling row through the one tab layout.
            local prefix = name:match("^(.+Tab)%d+$")
            local n = 0
            for i = 1, 16 do
                if _G[prefix .. i] then n = i end
            end
            ns.SkinBottomTabs(prefix, n)
        elseif ((name and _G[name .. "Left"]) or frame.Left)
            and frame.GetFontString and frame:GetFontString() then
            -- Panel-style button: named OR keyed side art + a label -
            -- and the art is chrome, not an icon somebody put there.
            if IsButtonChrome(sig) then
                SkinButton(frame)
            else
                -- Marked so the watcher never re-probes it, and left
                -- exactly as its addon drew it.
                ZUI.skinned[frame] = true
            end
        end

    elseif otype == "CheckButton" then
        local sig = GetArtSignature(frame)
        if (sig and (sig:find("ui%-checkbox") or sig:find("checkbox")))
            or (name and name:find("^ChatConfig")) then
            SkinBlizzCheck(frame)
        end

    elseif otype == "EditBox" then
        if (name and _G[name .. "Left"]) or frame.Left then
            SkinEditBox(frame)
        end

    elseif otype == "Frame" and name and name:find("^StaticPopup%d+$") then
        SkinStaticPopup(frame)

    elseif otype == "Frame" and name and name:find("^Baganator_")
        and name:find("Blizzard") then
        -- Baganator's Blizzard-THEME layer child carries default border
        -- art its skin API never routes through the listener. Kill the
        -- layer, dark-panel the view frame it decorates.
        ZUI.skinned[frame] = true
        StripDeep(frame, 1)
        -- The layer's OWN close (…BlizzardCloseButton) loses its art to
        -- the StripDeep above before any signature check can identify it
        -- - skin Close-named button children explicitly, after the strip.
        for _, child in ipairs({ frame:GetChildren() }) do
            if child.IsObjectType and child:IsObjectType("Button") then
                local cn = child.GetName and child:GetName()
                if cn and cn:find("Close") then
                    SkinCloseButton(child)
                end
            end
        end
        local parent = frame.GetParent and frame:GetParent()
        if parent then SkinBackdrop(parent, "windowBg", 0.97) end

    elseif otype == "Frame" and frame.GetBackdrop and not frame._zui_cbg then
        -- THE BLACK-LINES RULE (the ElvUI long-tail move): any frame
        -- wearing a Blizzard backdrop border - tooltip-border, dialogbox-
        -- border, all the ornate edge files - gets it replaced with the
        -- flat 1px black backdrop. One rule, every bordered box in the
        -- game, past and future (macro edit area included).
        local ok, bd = pcall(frame.GetBackdrop, frame)
        if ok and type(bd) == "table" and type(bd.edgeFile) == "string" then
            local edge = bd.edgeFile:lower()
            if edge:find("tooltip%-border") or edge:find("dialogbox%-border")
                or edge:find("ui%-frame") or edge:find("chatbubble%-backdrop")
                or edge:find("dialogbox%-gold") then
                ZUI.skinned[frame] = true
                frame:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
                local w = Col("windowBg")
                local b = Col("border")
                frame:SetBackdropColor(w.r, w.g, w.b, 0.9)
                frame:SetBackdropBorderColor(b.r, b.g, b.b, 1)
            end
        end
    end
end

-- GLOBAL SWEEP: one pass over everything alive at login.
Modules.sweep = function()
    if not EnumerateFrames then return end
    local frame = EnumerateFrames()
    while frame do
        pcall(ClassifyAndSkin, frame)
        ZUI._sweepTail = frame
        frame = EnumerateFrames(frame)
    end

    -- Named stragglers the signatures can miss on this build
    local mapClose = WorldMapFrameCloseButton
        or (WorldMapFrame and WorldMapFrame.BorderFrame
            and WorldMapFrame.BorderFrame.CloseButton)
        or (WorldMapFrame and WorldMapFrame.CloseButton)
    if mapClose then SkinCloseButton(mapClose) end

    -- ChatConfig panels themselves
    if ChatConfigFrame and not ZUI.skinned[ChatConfigFrame] then
        ZUI.skinned[ChatConfigFrame] = true
        StripTextures(ChatConfigFrame)
        StripFrameChrome(ChatConfigFrame)
        SkinBackdrop(ChatConfigFrame, "windowBg", 0.97)
        for _, sub in ipairs({ ChatConfigCategoryFrame, ChatConfigBackgroundFrame,
                               ChatConfigChatSettingsLeft, ChatConfigChannelSettingsLeft,
                               ChatConfigOtherSettingsCombat }) do
            if sub then
                StripTextures(sub)
                SkinBackdrop(sub, "elementBg", 0.5)
            end
        end
        local close = ChatConfigFrame.CloseButton or _G["ChatConfigFrameCloseButton"]
        if close then SkinCloseButton(close) end
    end
end

-- NEW-FRAME WATCHER v3 - PER-FRAME PUMP. v2 fixed the tail restart and
-- drained bursts across frames, but DETECTION still waited on a 0.5s
-- ticker: frames born when a window opens sat unstyled in front of the
-- player until the next tick - the visible "it reskins after it's
-- already open" pop. v3 removes the poll entirely: a self-chaining
-- C_Timer.After(0) pump runs once per rendered frame. Settled cost is
-- one EnumerateFrames probe per frame (a single C call - cheaper than
-- one OnUpdate script), and anything new is classified on the very
-- next frame, before a human can see it naked. Burst behavior is
-- unchanged: time-capped slices (monotonic GetTimePreciseSec), a
-- SLICE_FLOOR guarantee of forward progress, and a tail that NEVER
-- resets - a nil probe from the tail means settled, not start-over.
Modules.watcher = function()
    if not EnumerateFrames then return end
    if ZUI._watcherOn then return end -- live re-enable must not stack pumps
    ZUI._watcherOn = true
    local SLICE_SEC   = 0.0015 -- max classifier time per rendered frame
    local SLICE_FLOOR = 40     -- frames processed per slice regardless
    local now = GetTimePreciseSec or GetTime

    local function Pump()
        local frame = ZUI._sweepTail and EnumerateFrames(ZUI._sweepTail)
        if not frame and not ZUI._sweepTail then
            -- Only a truly virgin tail (sweep module off) starts from
            -- the head. A nil result FROM a tail means settled.
            frame = EnumerateFrames()
        end
        if frame then
            local t0, n = now(), 0
            while frame do
                pcall(ClassifyAndSkin, frame)
                ZUI._sweepTail = frame
                n = n + 1
                frame = EnumerateFrames(frame)
                if n >= SLICE_FLOOR and (now() - t0) >= SLICE_SEC then break end
            end
        end
        -- Every rendered frame out of combat, so a window opening is
        -- styled before it is seen. In combat nothing new opens that the
        -- player is looking at, and a 60/s timer plus probe is a cost
        -- with no return there: five a second until the fight ends.
        C_Timer.After(InCombatLockdown() and 0.2 or 0, Pump)
    end
    C_Timer.After(0, Pump)
end


-- shared with later ZacUI files
ns.ClassifyAndSkin = ClassifyAndSkin
