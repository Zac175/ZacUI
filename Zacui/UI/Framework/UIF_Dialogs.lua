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
