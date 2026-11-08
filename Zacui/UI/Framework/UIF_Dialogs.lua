-- UIF_Dialogs - confirm and input prompts in ZacUI's own shell.
-- Part of ZacUI; load order is set by the TOC.
--
-- Why not StaticPopup: StaticPopupDialogs is a shared global table, its
-- frames are recycled across every addon in the game, and ZacUI already
-- SKINS those frames - asking the skinner to also be the caller is how
-- you get a popup that is styled twice and sized for neither. These are
-- ours end to end.
--
-- Destructive actions get a red confirm button. "Reset every colour" and
-- "reset every setting" are both one click from real work being lost, and
-- a flat grey button gives no warning at all.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local GetColor = ns.GetColor
local UI = ns.UI

local M, F = UI.M, UI.F

local confirm, input

local function BuildBase(name, width, height, title)
    local f = UI.Window(name, width, height, title)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(120)
    -- Whole-frame drag: a 300px dialog with a 30px grab strip is fiddly.
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    return f
end

-- Red styling for the button that does the irreversible thing.
--
-- THE DIALOGS ARE REUSED, and that is what makes this delicate. There is
-- one Accept button for every confirm ZacUI will ever show, so the styling
-- has to be a STATE on the button, re-evaluated each time, not a closure
-- swapped in and out. The first version of this replaced _zPaint on a
-- destructive dialog and then set it to nil on the next ordinary one -
-- which does not restore the default paint, it deletes it, leaving a red
-- Okay button and an OnEnter handler calling a method that no longer
-- exists. HookScript cannot be undone, so the hooks are installed exactly
-- once, here, and read the flag rather than assuming a mode.
local function SetupAcceptButton(btn)
    if btn._zDestructiveReady then return end
    btn._zDestructiveReady = true

    local Default = btn._zPaint
    btn._zPaint = function(self)
        if not self._zDestructive then
            return Default(self)
        end
        local base = GetColor("text", "red")
        if self._zFill then
            self._zFill:SetVertexColor(base.r * 0.34, base.g * 0.12, base.b * 0.12,
                self._zHot and 0.55 or 0.4)
        end
        if self._zBorder then
            for _, t in ipairs(self._zBorder) do
                t:SetVertexColor(base.r * 0.7, base.g * 0.3, base.b * 0.3, 1)
            end
        end
        if self._zText then self._zText:SetTextColor(base.r, base.g, base.b, 1) end
    end
    btn:HookScript("OnEnter", function(self)
        if self._zDestructive then self._zHot = true; self:_zPaint() end
    end)
    btn:HookScript("OnLeave", function(self)
        if self._zDestructive then self._zHot = nil; self:_zPaint() end
    end)
end

-- ============================================================
-- CONFIRM
-- ============================================================
function UI.Confirm(opts)
    opts = opts or {}
    if not confirm then
        confirm = BuildBase("ZacUIConfirmDialog", 320, 140, "ZacUI")
        confirm.message = UI.Font(confirm, F.LABEL, { justify = "LEFT", width = 288 })
        confirm.message:SetPoint("TOPLEFT", 16, -(M.TITLEBAR + 14))
        confirm.accept = UI.Button(confirm, "", { width = 100, height = 22 })
        confirm.accept:SetPoint("BOTTOMRIGHT", confirm, "BOTTOM", -5, 12)
        SetupAcceptButton(confirm.accept)
        confirm.cancel = UI.Button(confirm, CANCEL or "Cancel", { width = 100, height = 22 })
        confirm.cancel:SetPoint("BOTTOMLEFT", confirm, "BOTTOM", 5, 12)
        local function Dismiss()
            local fn = confirm._onCancel
            confirm._onCancel = nil
            UI.CloseWindow(confirm)
            if fn then fn() end
        end
        confirm.cancel:SetScript("OnClick", Dismiss)
        -- Escape routes through UISpecialFrames, which just hides the frame.
        -- Without this, closing with Escape skips the cancel callback that
        -- clicking Cancel would have run.
        confirm:HookScript("OnHide", function()
            local fn = confirm._onCancel
            confirm._onCancel = nil
            if fn then fn() end
        end)
    end

    confirm.titleText:SetText(opts.title or "ZacUI")
    confirm.message:SetText(opts.text or "")
    confirm.accept:SetLabel(opts.acceptText or (ACCEPT or "Okay"))
    confirm._onCancel = opts.onCancel
    -- noCancel: a notice with one button (Okay), centred
    confirm.accept:ClearAllPoints()
    if opts.noCancel then
        confirm.cancel:Hide()
        confirm.accept:SetPoint("BOTTOM", confirm, "BOTTOM", 0, 12)
    else
        confirm.cancel:Show()
        confirm.accept:SetPoint("BOTTOMRIGHT", confirm, "BOTTOM", -5, 12)
    end
    confirm._zDestructive = nil
    confirm.accept._zDestructive = opts.destructive or nil
    confirm.accept._zHot = nil
    confirm.accept:_zPaint()
    confirm.accept:SetScript("OnClick", function()
        confirm._onCancel = nil   -- accepting is not cancelling
        -- ============================================================
        -- THE WORK FIRST, THE ANIMATION SECOND
        -- ============================================================
        -- This used to close the window and then run onAccept, which
        -- reads better and breaks protected actions. Closing goes through
        -- PopOut, which starts an animation, and by the time the callback
        -- ran the client no longer credited it to the button press -
        -- CancelAuction came back as ADDON_ACTION_BLOCKED from a dialog
        -- the player had very definitely just clicked.
        --
        -- Nothing belongs between a click and the protected call it
        -- authorises. The window is a tenth of a second slower to leave
        -- and the action actually happens.
        if opts.onAccept then opts.onAccept() end
        UI.CloseWindow(confirm)
    end)

    -- Height follows the message. A two-line and a five-line warning in
    -- the same fixed box either clips or floats.
    local h = math.max(40, confirm.message:GetStringHeight() + 8)
    confirm:SetHeight(M.TITLEBAR + 14 + h + 46)
    UI.OpenWindow(confirm)
    return confirm
end

-- ============================================================
-- RELOAD
-- ============================================================
-- ONE WAY TO ASK FOR A RELOAD. Every change that only takes hold after a
-- reload asks with ns.AskReload(reason) - not a chat line the player
-- misses, not a button of its own on each page:
--
--   ns.AskReload(reason)                    "Reload needed": reason, Reload now / Later
--   ns.AskReload(reason, { apply = fn,      fn writes the change; it runs only on
--       onCancel = fn, title = "..." })     Reload now, so Later leaves nothing half done
--   ns.RequestReload()                      reload, no question (a click that says so)
--
-- THE RELOAD IS ASKED FOR FIRST. WoW Forever reloads only when the reload
-- is asked for at the very start of a click: build 70425 turned down one
-- asked for after the click had saved things. So Reload now asks for it
-- first and runs the change's own writes (apply) after, still inside the
-- same click; the client reloads once the click has finished, so those
-- writes are what the reload saves. Era and TBC do not mind the order.
local reload

function ns.RequestReload()
    if type(ReloadUI) == "function" then ReloadUI()
    elseif C_UI and C_UI.Reload then C_UI.Reload() end
end

function UI.AskReload(reason, opts)
    if type(reason) == "table" then opts, reason = reason, reason.text end
    opts = opts or {}
    if not reload then
        reload = BuildBase("ZacUIReloadDialog", 320, 140, "Reload needed")
        reload.message = UI.Font(reload, F.LABEL, { justify = "LEFT", width = 288 })
        reload.message:SetPoint("TOPLEFT", 16, -(M.TITLEBAR + 14))
        reload.accept = UI.Button(reload, "Reload now", { width = 100, height = 22 })
        reload.accept:SetPoint("BOTTOMRIGHT", reload, "BOTTOM", -5, 12)
        reload.accept:SetActive(true)
        reload.later = UI.Button(reload, "Later", { width = 100, height = 22,
            tooltip = "Keeps playing. The change waits for your next reload or login." })
        reload.later:SetPoint("BOTTOMLEFT", reload, "BOTTOM", 5, 12)
        reload.later:SetScript("OnClick", function() UI.CloseWindow(reload) end)
        reload.accept:SetScript("OnClick", function()
            -- the reload first (see above), then the change's own writes
            local apply = reload._apply
            reload._apply, reload._onCancel = nil, nil
            ns.RequestReload()
            if apply then
                local ok, err = pcall(apply)
                if not ok and ns.Print then ns.Print("reload: " .. tostring(err)) end
            end
            UI.CloseWindow(reload)
        end)
        -- Later, the X and Escape all land here: not reloading
        reload:HookScript("OnHide", function()
            local fn = reload._onCancel
            reload._apply, reload._onCancel = nil, nil
            if fn then fn() end
        end)
    end
    reload.titleText:SetText(opts.title or "Reload needed")
    reload.message:SetText(reason or "This change takes hold after a reload.")
    reload.accept:SetWidth(100)   -- (a longer label widens it; the next question starts narrow)
    reload.accept:SetLabel(opts.acceptText or "Reload now")
    reload._apply, reload._onCancel = opts.apply, opts.onCancel
    local h = math.max(40, reload.message:GetStringHeight() + 8)
    reload:SetHeight(M.TITLEBAR + 14 + h + 46)
    UI.OpenWindow(reload)
    -- a question raised at login waits its turn with the login popups
    -- (Core_Popups), so the next one does not land on top of it
    if ns.Popups and ns.Popups.Hold then ns.Popups.Hold(reload) end
    return reload
end
ns.AskReload = UI.AskReload

-- ============================================================
-- CALLOUT
-- ============================================================
-- A hint that points at the thing it is about (finish pass): a dark box
-- with an accent edge, an accent arrow at the thing, the words, Okay.
-- Anchored to the thing itself, so it moves with it and goes when it
-- hides (not an answer: it may show again). One at a time - a second
-- asked for while one is up waits its turn. Once-per-account bookkeeping
-- is the caller's (ns.Hints.Callout, Tutorial_Hints).
--   UI.Callout(target, { text, side = "BELOW"|"ABOVE"|"RIGHT"|"LEFT",
--       width = 230, onOkay = fn, key = "..." })   -> the frame, or false
--   UI.CalloutShown()                               -> the key up now
local callout
local calloutQueue = {}
local CALLOUT_W, ARROW = 230, 12

local function NextCallout()
    local nxt = table.remove(calloutQueue, 1)
    while nxt and not (nxt.target and nxt.target:IsVisible()) do nxt = table.remove(calloutQueue, 1) end
    if nxt then UI.Callout(nxt.target, nxt.opts) end
end

local function BuildCallout()
    local f = CreateFrame("Frame", "ZacUICallout", UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(130)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:Hide()
    UI.Fill(f, "ui", "windowBg", 0.97)
    local a = GetColor("ui", "accent")
    if ns.Pixel and ns.Pixel.Border then
        f._zEdges = ns.Pixel.Border(f, a.r, a.g, a.b, 1, "BORDER")
    else
        UI.Border(f, "ui", "accent")
    end
    f.text = UI.Font(f, F.LABEL, { justify = "LEFT", width = CALLOUT_W - 24 })
    f.text:SetPoint("TOPLEFT", 12, -12)
    f.okay = UI.Button(f, "Okay", { width = 60, height = 18 })
    f.okay:SetPoint("BOTTOMRIGHT", -12, 10)
    local arrow = f:CreateTexture(nil, "OVERLAY")
    arrow._zui_own = true
    arrow:SetSize(ARROW, ARROW)
    arrow:SetVertexColor(a.r, a.g, a.b, 1)
    f.arrow = arrow
    f.okay:SetScript("OnClick", function()
        local fn = f._onOkay
        f._onOkay, f._zAnswered = nil, true
        f:Hide()
        if fn then pcall(fn) end
    end)
    f:SetScript("OnHide", function()
        f._key, f._target, f._onOkay = nil, nil, nil
        -- the next one a breath later, never stacked on this one
        if #calloutQueue > 0 and C_Timer and C_Timer.After then C_Timer.After(0.3, NextCallout) end
    end)
    callout = f
    return f
end

function UI.CalloutShown() return callout and callout:IsShown() and callout._key or nil end

function UI.Callout(target, opts)
    opts = opts or {}
    if not (target and target.IsVisible and target:IsVisible()) then return false end
    if callout and callout:IsShown() then
        if opts.key and callout._key == opts.key then return callout end
        for _, q in ipairs(calloutQueue) do if opts.key and q.opts.key == opts.key then return false end end
        calloutQueue[#calloutQueue + 1] = { target = target, opts = opts }
        return false
    end
    local f = callout or BuildCallout()
    local w = opts.width or CALLOUT_W
    f.text:SetWidth(w - 24)
    f.text:SetText(opts.text or "")
    f:SetSize(w, 12 + math.ceil(f.text:GetStringHeight() or 12) + 8 + 18 + 10)
    f._key, f._target, f._onOkay, f._zAnswered = opts.key, target, opts.onOkay, nil
    local side, arrow = opts.side or "BELOW", f.arrow
    f:ClearAllPoints()
    arrow:ClearAllPoints()
    if side == "ABOVE" then
        f:SetPoint("BOTTOM", target, "TOP", 0, ARROW - 2)
        arrow:SetTexture(ns.TEX_ARROW) arrow:SetTexCoord(0, 1, 0, 1)            -- points down
        arrow:SetPoint("TOP", f, "BOTTOM", 0, 1)
    elseif side == "RIGHT" then
        f:SetPoint("LEFT", target, "RIGHT", ARROW - 2, 0)
        arrow:SetTexture(ns.TEX_ARROWL) arrow:SetTexCoord(0, 1, 0, 1)           -- points left
        arrow:SetPoint("RIGHT", f, "LEFT", 1, 0)
    elseif side == "LEFT" then
        f:SetPoint("RIGHT", target, "LEFT", -(ARROW - 2), 0)
        arrow:SetTexture(ns.TEX_ARROWL) arrow:SetTexCoord(1, 0, 0, 1)           -- points right
        arrow:SetPoint("LEFT", f, "RIGHT", -1, 0)
    else
        f:SetPoint("TOP", target, "BOTTOM", 0, -(ARROW - 2))
        arrow:SetTexture(ns.TEX_ARROW) arrow:SetTexCoord(0, 1, 1, 0)            -- points up
        arrow:SetPoint("BOTTOM", f, "TOP", 0, -1)
    end
    -- the thing goes away: so does its callout (not an answer)
    if not target._zCalloutHooked and target.HookScript then
        target._zCalloutHooked = true
        target:HookScript("OnHide", function(self)
            if callout and callout:IsShown() and callout._target == self then callout:Hide() end
        end)
    end
    f:Show()
    if ns.PopIn and not (ns.Motion and ns.Motion.Enabled and not ns.Motion.Enabled()) then pcall(ns.PopIn, f, 0.15) end
    return f
end

-- ============================================================
-- INPUT
-- ============================================================
function UI.Prompt(opts)
    opts = opts or {}
    if not input then
        input = BuildBase("ZacUIInputDialog", 340, 160, "ZacUI")
        input.message = UI.Font(input, F.LABEL, { justify = "LEFT", width = 308 })
        input.message:SetPoint("TOPLEFT", 16, -(M.TITLEBAR + 14))
        input.box = UI.EditBox(input, { width = 308 })
        input.accept = UI.Button(input, OKAY or "Okay", { width = 100, height = 22 })
        input.accept:SetPoint("BOTTOMRIGHT", input, "BOTTOM", -5, 12)
        input.cancel = UI.Button(input, CANCEL or "Cancel", { width = 100, height = 22 })
        input.cancel:SetPoint("BOTTOMLEFT", input, "BOTTOM", 5, 12)
        input.cancel:SetScript("OnClick", function() UI.CloseWindow(input) end)
    end

    input.titleText:SetText(opts.title or "ZacUI")
    input.message:SetText(opts.text or "")
    input.box:SetText(opts.default or "")

    local function Submit()
        local value = input.box:GetText()
        UI.CloseWindow(input)
        if opts.onAccept then opts.onAccept(value) end
    end
    input.accept:SetScript("OnClick", Submit)
    input.box.editBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        Submit()
    end)

    local h = math.max(20, input.message:GetStringHeight() + 6)
    input.message:ClearAllPoints()
    input.message:SetPoint("TOPLEFT", 16, -(M.TITLEBAR + 14))
    input.box:ClearAllPoints()
    input.box:SetPoint("TOPLEFT", 16, -(M.TITLEBAR + 18 + h))
    input:SetHeight(M.TITLEBAR + 18 + h + M.EDIT_H + 50)

    UI.OpenWindow(input)
    input.box.editBox:SetFocus()
    return input
end
