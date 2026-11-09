-- UIF_Dialogs - ZacUI's popups: the one popup shell, and the confirm,
-- reload, input, hint and contact popups built on it.
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
local FLAT = ns.FLAT

local confirm, input

-- ============================================================
-- THE POPUP SHELL (2026-11-08)
-- ============================================================
-- Every popup, dialog and small window ZacUI draws wears the settings
-- window's look (UI.S, built to EllesmereUI's numbers - ours is our own
-- code): no title bar; the window's warm near-black, a white 0.05 edge;
-- the title in the page-title type (the settings window's 36 / 14 on a
-- big window, scaled down on a small one) with an optional line under it
-- at white 0.53; the 40 px close box 14 in and 11 down; a button row
-- along the foot - 32 px buttons that fade, the accent one the answer.
-- Text is outlined as ZacUI's font option says (Zac likes the black edge).
--
--   UI.Popup(name, width, height, title, opts) -> f     (UI.Window's shape)
--     opts.desc      a line under the title (white 0.53)
--     opts.icon      a 32 px icon left of the title (tinted the accent)
--     opts.size      "small" | "medium" | "big" (default: from the width)
--     opts.rule      a white 0.06 hairline under the header
--     opts.pad       the side margin (default: the size's), for a window
--                    whose content keeps its own
--     opts.strata, opts.level
--     opts.close     false: no close box
--   f.titleBar     the header strip (drags the window; the title, the line
--                  and the close box sit on it)
--   f.titleText, f.descText, f.titleIcon, f.closeButton
--   f.headerHeight how tall the header is (content starts under it)
--   f.pad          the side margin of this size of popup
--   f.body         a frame from under the header to over the button row,
--                  pad in from the sides
--   f:SetTitle(title, desc)       new words; the header re-lays itself
--   f:SetButtons({ { text, onClick, kind = "primary"|"destructive",
--                    width, tooltip }, ... })   the button row, right to
--                  left from the last; returns the buttons (reused by index)
--   f:LayoutButtons()             after a label changed
--   f:FooterHeight()              the button row's share of the height
--   f:FitHeight(bodyH)            header + body + button row
--   UI.PopupBuild(fn, ...)        builds widgets in the settings look
--                                 (UI.SettingsBuild: 14 px labels, the
--                                 settings buttons, fields and boxes)
--   UI.PopupText(parent, kind)    "body" (14, white 0.80) | "hint" (12,
--                                 white 0.53) | "head" (12, white 0.41)
--   UI.PopupField(box)            a UI.TextBox / UI.Box in the field look
--   UI.FlatBar(bar, opts)         a 30 px title bar some windows keep
--                                 (their layouts hang off it): flat, a
--                                 white 0.06 hairline, title white, X 0.53
local POP = {
    -- (2026-11-08, Zac: "way to big ... huge x button") a small popup is
    -- compact: a 16 title, tighter margins
    small  = { PAD = 18, TOP = 16, T = 16, D = 12, GAP = 10, LINE = 4 },
    medium = { PAD = 30, TOP = 24, T = 24, D = 14, GAP = 18, LINE = 8 },
    big    = { PAD = 45, TOP = 35, T = 36, D = 14, GAP = 24, LINE = 12 },
    BTN_H = 32, BTN_GAP = 10, BTN_MIN = 110, FOOT_GAP = 20,
    BODY = 14, BODY_A = 0.80, HINT = 12, HEAD = 12,
    CLOSE = 40, CLOSE_X = 14, CLOSE_Y = 11, RULE_A = 0.06,
}
UI.POP = POP

function UI.PopupClass(width)
    width = width or 0
    if width >= 900 then return "big" elseif width >= 520 then return "medium" end
    return "small"
end

function UI.PopupBuild(fn, ...) return UI.SettingsBuild(fn, ...) end

local function White(a) return function(self) self:SetTextColor(1, 1, 1, a) end end

function UI.PopupText(parent, kind, opts)
    local S = UI.S
    opts = opts or {}
    local size, a = POP.BODY, POP.BODY_A
    if kind == "hint" then size, a = POP.HINT, S.DIM_A
    elseif kind == "head" then size, a = POP.HEAD, S.SECTION_A
    elseif kind == "title" then size, a = POP.BODY, 1 end
    local fs = UI.SFont(parent, opts.size or size, opts)
    fs._zPaint = White(opts.alpha or a)
    fs:_zPaint()
    return fs
end

-- A box (UI.TextBox, UI.Box) in the settings window's field look: the
-- input colour at 0.35, a white 0.10 edge.
function UI.PopupField(box)
    if not box then return box end
    local S = UI.S
    box._zPaint = function(self)
        local c = S.INPUT
        if self._zFill then self._zFill:SetVertexColor(c.r, c.g, c.b, S.INPUT_A) end
        if self._zBorder then
            for _, t in ipairs(self._zBorder) do t:SetVertexColor(1, 1, 1, S.INPUT_BRD_A) end
        end
    end
    box:_zPaint()
    local eb = box.editBox
    if eb and UI._zFontDress then
        UI._zFontDress(eb, S.F_VALUE, "")
        eb:SetTextColor(1, 1, 1, 0.9)
    end
    return box
end

-- The red one: the settings button's fade, in the negative colour.
local function PaintDestructive(self)
    local S = UI.S
    local t = self._zDisabled and 0 or (self._zP or 0)
    local k = self._zDisabled and 0.5 or 1
    local c = GetColor("text", "red")
    local a = (S.CLOSE_A + (1 - S.CLOSE_A) * t) * k
    if self._zFill then self._zFill:SetVertexColor(S.BG.r, S.BG.g, S.BG.b, S.FOOT_BG_A) end
    if self._zBorder then for _, e in ipairs(self._zBorder) do e:SetVertexColor(c.r, c.g, c.b, a) end end
    if self._zText then self._zText:SetTextColor(c.r, c.g, c.b, a) end
end
local function PaintPopupButton(self)
    if self._zDestructive then return PaintDestructive(self) end
    return UI.PaintSetButton(self)
end

-- A popup button: the settings window's 32 px button; primary = the accent
-- one; destructive = red. The kind is a STATE read by the paint, so one
-- button serves a plain question and a destructive one in turn.
local function PopupButton(parent, text, opts)
    opts = opts or {}
    local b = UI.SettingsBuild(UI.Button, parent, text or "", { width = opts.width or POP.BTN_MIN,
        height = POP.BTN_H, tooltip = opts.tooltip, onClick = opts.onClick })
    b._zPaint = PaintPopupButton
    function b:SetKind(kind)
        self._zStyle = (kind == "primary" or kind == "destructive") and "close" or nil
        self._zDestructive = (kind == "destructive") or nil
        self._zHot, self._zP = nil, 0
        self:_zPaint()
    end
    b:SetKind(opts.kind)
    return b
end
UI.PopupButton = PopupButton

function UI.Popup(name, width, height, title, opts)
    opts = opts or {}
    local S = UI.S
    local P = POP[opts.size or UI.PopupClass(width)] or POP.small
    if opts.pad then
        -- (a window whose content keeps its own margin: the title lines up)
        local q = {}
        for k, v in pairs(P) do q[k] = v end
        q.PAD = opts.pad
        P = q
    end
    local f = UI.Window(name, width, height, title, { bare = true })
    f._zPopup = true
    f.pad, f._zPop = P.PAD, P
    if opts.strata then f:SetFrameStrata(opts.strata) end
    if opts.level then f:SetFrameLevel(opts.level) end
    -- the whole window drags (as the settings window does); the header
    -- strip too, though it sits over the window
    f:RegisterForDrag("LeftButton")
    local function DragStart() f:StartMoving() end
    local function DragStop()
        f:StopMovingOrSizing()
        if f._zOnMoved then f._zOnMoved() end
    end
    f:SetScript("OnDragStart", DragStart)
    f:SetScript("OnDragStop", DragStop)

    -- the header strip: UI.Window's drag surface spans the window; a
    -- popup's is its header only, so the body's own widgets take the mouse
    local bar = f.titleBar
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    bar:SetHeight(P.TOP + P.T + P.GAP)

    local close = f.closeButton
    if opts.close == false and close then close:Hide() end
    -- (a level set on the window after its header was made: the header
    -- and the close box go back above the window's own fill)
    -- (2026-11-08, Zac: "huge x button") the X sized to the popup: the big
    -- settings-size X only on a big popup
    if close and close._zA then
        local g = (P == POP.big) and 38 or (P == POP.medium and 26 or 18)
        close:SetSize(g + 2, g + 2)
        close._zA:SetSize(g, g)
        close:ClearAllPoints()
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(P.PAD - 8), -(P.TOP - 6))
    end
    -- Every child above the popup's own fill, whatever raised it: a raise
    -- moved the popup's level and its children kept the old one - they
    -- drew UNDER the fill (the AH buy window showed its words but no
    -- buttons and no X, 2026-11-08)
    local function Relevel()
        local lv = f:GetFrameLevel() or 1
        bar:SetFrameLevel(lv + 1)
        if close then close:SetFrameLevel(lv + 30) end
        for _, c in ipairs({ f:GetChildren() }) do
            if c ~= bar and c ~= close and c.GetFrameLevel and (c:GetFrameLevel() or 0) <= lv then
                c:SetFrameLevel(lv + 5)
            end
        end
    end
    Relevel()
    hooksecurefunc(f, "SetFrameLevel", Relevel)
    hooksecurefunc(f, "Raise", Relevel)
    f:HookScript("OnShow", Relevel)
    f:HookScript("OnMouseDown", Relevel)

    local icon
    if opts.icon then
        icon = bar:CreateTexture(nil, "ARTWORK")
        icon._zui_own = true
        icon:SetSize(32, 32)
        icon:SetPoint("TOPLEFT", f, "TOPLEFT", P.PAD, -P.TOP)
        icon:SetTexture(opts.icon)
        icon._zPaint = function(self) local a = GetColor("ui", "accent") self:SetVertexColor(a.r, a.g, a.b, 1) end
        icon:_zPaint()
    end
    local x = P.PAD + (icon and 44 or 0)
    local right = POP.CLOSE_X + POP.CLOSE + 6
    local tt = UI.SFont(bar, P.T, { text = title or "" })
    tt:SetPoint("TOPLEFT", f, "TOPLEFT", x, -P.TOP)
    tt:SetJustifyH("LEFT")
    tt:SetWordWrap(false)
    tt:SetWidth(math.max(60, width - x - right))
    tt._zPaint = White(1)
    tt:_zPaint()
    local dt = UI.SFont(bar, P.D, { text = "" })
    dt:SetPoint("TOPLEFT", tt, "BOTTOMLEFT", 0, -P.LINE)
    dt:SetJustifyH("LEFT")
    dt:SetWordWrap(false)
    dt:SetWidth(math.max(60, width - x - right))
    dt._zPaint = White(S.DIM_A)
    dt:_zPaint()

    local rule = bar:CreateTexture(nil, "ARTWORK")
    rule._zui_own = true
    rule:SetTexture(FLAT)
    if ns.Pixel then ns.Pixel.Edge(rule, "BOTTOM", bar) else rule:SetHeight(1) end
    rule:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 1, 0)
    rule:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -1, 0)
    rule:SetVertexColor(1, 1, 1, POP.RULE_A)
    rule:SetShown(opts.rule and true or false)

    local body = CreateFrame("Frame", nil, f)
    f.body = body

    f.buttons = {}
    local function ButtonsShown()
        for _, b in ipairs(f.buttons) do if b:IsShown() then return true end end
        return false
    end
    function f:FooterHeight()
        if ButtonsShown() then return POP.BTN_H + (P.PAD - 4) + POP.FOOT_GAP end
        return P.PAD
    end
    local function PlaceBody()
        body:ClearAllPoints()
        body:SetPoint("TOPLEFT", f, "TOPLEFT", P.PAD, -f.headerHeight)
        body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -P.PAD, f:FooterHeight())
    end
    -- the header's height from what it holds (sizes, not measured strings:
    -- the same on every client and before the first frame is drawn)
    local function LayoutHeader()
        local h = P.TOP + P.T + 2
        local d = dt:GetText()
        if d and d ~= "" then
            dt:Show()
            h = h + P.LINE + P.D + 2
        else
            dt:Hide()
        end
        if icon then h = math.max(h, P.TOP + 32) end
        f.headerHeight = h + P.GAP
        bar:SetHeight(f.headerHeight)
        PlaceBody()
    end
    function f:SetTitle(t, d)
        if t ~= nil then tt:SetText(t) end
        if d ~= nil then dt:SetText(d) end
        LayoutHeader()
    end
    function f:FitHeight(bodyH)
        self:SetHeight(math.floor(self.headerHeight + math.max(0, bodyH or 0) + self:FooterHeight() + 0.5))
    end
    function f:LayoutButtons()
        local prev
        for i = #self.buttons, 1, -1 do
            local b = self.buttons[i]
            if b:IsShown() then
                b:ClearAllPoints()
                if prev then
                    b:SetPoint("RIGHT", prev, "LEFT", -POP.BTN_GAP, 0)
                else
                    b:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -P.PAD, P.PAD - 4)
                end
                prev = b
            end
        end
        PlaceBody()
    end
    function f:SetButtons(specs)
        specs = specs or {}
        for i, s in ipairs(specs) do
            local b = self.buttons[i]
            if not b then
                b = PopupButton(self, s.text, s)
                b:SetFrameLevel(self:GetFrameLevel() + 20)
                self.buttons[i] = b
            else
                b:SetWidth(s.width or POP.BTN_MIN)
                b:SetLabel(s.text or "")
                if s.onClick then b:SetScript("OnClick", s.onClick) end
                if s.tooltip then UI.Tooltip(b, s.text, s.tooltip) end
            end
            b:SetKind(s.kind)
            b:Show()
        end
        for i = #specs + 1, #self.buttons do self.buttons[i]:Hide() end
        self:LayoutButtons()
        return self.buttons
    end

    f.titleText, f.descText, f.titleIcon, f.headerRule = tt, dt, icon, rule
    f:SetTitle(title, opts.desc or "")
    -- a game window of ZacUI's (opts.part: the look part it follows) wears
    -- the look's dialog under a game look (Core_LookPanels' one helper);
    -- under ZacUI's own look Look.Dress returns on its first line
    if opts.part and ns.Look and ns.Look.Dress then
        rawset(f, "_zDialogParts", { title = tt, close = close })
        ns.Look.Dress(f, "dialog", opts.part)
    end
    return f
end

-- A 30 px title bar kept where a window's layout hangs off it (the game
-- windows, ZacUI's other small windows): flat in the window's colour (no
-- gradient, no step, no mark), a white 0.06 hairline at its foot, the
-- title in the settings window's white, the X white 0.53 -> 1.0.
--   opts.fill()  -> r, g, b, a   the bar's colour (default: the window's)
--   opts.title   the title string (painted white unless opts.titleColor)
--   opts.titleColor() -> r, g, b, a
--   opts.close   the close button (CloseX)
-- Returns the paint (also set as bar._zPaint).
function UI.FlatBar(bar, opts)
    opts = opts or {}
    if not bar._zFill then UI.Fill(bar, "ui", "windowBg") end
    local line = bar._zFlatRule
    if not line then
        line = bar:CreateTexture(nil, "ARTWORK")
        line._zui_own = true
        line:SetTexture(FLAT)
        if ns.Pixel then ns.Pixel.Edge(line, "BOTTOM", bar) else line:SetHeight(1) end
        line:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
        line:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
        bar._zFlatRule = line
    end
    if opts.close then opts.close._zSet = true end
    local function Paint(self)
        self = self or bar
        local r, g, b, a
        if opts.fill then r, g, b, a = opts.fill()
        else
            local c = GetColor("ui", "windowBg")
            r, g, b, a = c.r, c.g, c.b, 1
        end
        if self._zFill then
            self._zFill:SetTexture(FLAT)
            self._zFill:SetVertexColor(r, g, b, a or 1)
        end
        line:SetVertexColor(1, 1, 1, POP.RULE_A)
        local t = opts.title
        if t then
            if opts.titleColor then t:SetTextColor(opts.titleColor()) else t:SetTextColor(1, 1, 1, 1) end
        end
        if opts.close and opts.close._zPaint then opts.close:_zPaint() end
    end
    bar._zPaint = Paint
    Paint(bar)
    return Paint
end

-- TOOLTIPS on the settings window and the popups: the title white, the
-- words white 0.80, as the window's own text (not the gold title of the
-- game's tooltips). The words are the caller's (UI.Tooltip, UIF_Controls);
-- this only recolours them once they are up.
local function InPopupLook(frame)
    local n = 0
    while frame and n < 14 do
        if rawget(frame, "_zSet") or rawget(frame, "_zPopup") then return true end
        local nm = frame.GetName and frame:GetName()
        if nm == "ZacUIConfigFrame" then return true end
        frame = frame.GetParent and frame:GetParent()
        n = n + 1
    end
    return false
end
UI.InPopupLook = InPopupLook

local function RecolourTip(owner)
    local tip = GameTooltip
    if not (tip and tip.IsShown and tip:IsShown()) then return end
    if tip.GetOwner and tip:GetOwner() ~= owner then return end
    local n = tip.NumLines and tip:NumLines() or 0
    if type(n) ~= "number" then return end
    for i = 1, n do
        local l = _G["GameTooltipTextLeft" .. i]
        if l and l.SetTextColor then l:SetTextColor(1, 1, 1, i == 1 and 1 or POP.BODY_A) end
    end
end

do
    local BaseTooltip = UI.Tooltip
    if BaseTooltip and not UI._zPopupTipWrapped then
        UI._zPopupTipWrapped = true
        function UI.Tooltip(frame, title, body)
            BaseTooltip(frame, title, body)
            if frame and not frame._zPopTipHooked and frame.HookScript then
                frame._zPopTipHooked = true
                frame:HookScript("OnEnter", function(self)
                    -- (a greyed control's reason is UIF_Pickers' own look)
                    if self._zDisabled and self._zWhy then return end
                    if InPopupLook(self) then pcall(RecolourTip, self) end
                end)
            end
        end
    end
end

-- ============================================================
-- CONFIRM
-- ============================================================
local DIALOG_W = 390

local function Dialog(name, title)
    local f = UI.Popup(name, DIALOG_W, 200, title, { strata = "FULLSCREEN_DIALOG", level = 120 })
    f.message = UI.PopupText(f, "body", { justify = "LEFT", width = DIALOG_W - 2 * f.pad })
    f.message:SetPoint("TOPLEFT", f, "TOPLEFT", f.pad, -f.headerHeight)
    return f
end

-- Height follows the message. A two-line and a five-line warning in
-- the same fixed box either clips or floats.
local function MessageH(fs)
    local ok, h = pcall(fs.GetStringHeight, fs)
    return math.max(POP.BODY + 4, math.ceil((ok and type(h) == "number") and h or 0))
end

function UI.Confirm(opts)
    opts = opts or {}
    if not confirm then
        confirm = Dialog("ZacUIConfirmDialog", "ZacUI")
        local b = confirm:SetButtons({
            { text = CANCEL or "Cancel" },
            { text = ACCEPT or "Okay", kind = "primary" },
        })
        confirm.cancel, confirm.accept = b[1], b[2]
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

    confirm:SetTitle(opts.title or "ZacUI")
    confirm.message:SetText(opts.text or "")
    confirm.accept:SetWidth(POP.BTN_MIN)   -- (a longer label widens it; the next question starts narrow)
    confirm.accept:SetLabel(opts.acceptText or (ACCEPT or "Okay"))
    confirm._onCancel = opts.onCancel
    -- noCancel: a notice with one button (Okay)
    confirm.cancel:SetShown(not opts.noCancel)
    confirm._zDestructive = nil
    confirm.accept:SetKind(opts.destructive and "destructive" or "primary")
    confirm:LayoutButtons()
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

    confirm:FitHeight(MessageH(confirm.message))
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
        reload = Dialog("ZacUIReloadDialog", "Reload needed")
        local b = reload:SetButtons({
            { text = "Later", tooltip = "Keeps playing. The change waits for your next reload or login." },
            { text = "Reload now", kind = "primary" },
        })
        reload.later, reload.accept = b[1], b[2]
        reload.accept:SetActive(true)
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
    reload:SetTitle(opts.title or "Reload needed")
    reload.message:SetText(reason or "This change takes hold after a reload.")
    reload.accept:SetWidth(POP.BTN_MIN)   -- (a longer label widens it; the next question starts narrow)
    reload.accept:SetLabel(opts.acceptText or "Reload now")
    reload:LayoutButtons()
    reload._apply, reload._onCancel = opts.apply, opts.onCancel
    reload:FitHeight(MessageH(reload.message))
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
-- A hint that points at the thing it is about (finish pass): a box in the
-- popups' colour with an accent edge, an accent arrow at the thing, the
-- words, Okay. Anchored to the thing itself, so it moves with it and goes
-- when it hides (not an answer: it may show again). One at a time - a
-- second asked for while one is up waits its turn. Once-per-account
-- bookkeeping is the caller's (ns.Hints.Callout, Tutorial_Hints).
--   UI.Callout(target, { text, side = "BELOW"|"ABOVE"|"RIGHT"|"LEFT",
--       width = 250, onOkay = fn, key = "..." })   -> the frame, or false
--   UI.CalloutShown()                               -> the key up now
local callout
local calloutQueue = {}
local CALLOUT_W, ARROW = 250, 12
local CO_PAD, CO_BOT, CO_BTN_H, CO_BTN_W = 16, 14, 26, 80

local function NextCallout()
    local nxt = table.remove(calloutQueue, 1)
    while nxt and not (nxt.target and nxt.target:IsVisible()) do nxt = table.remove(calloutQueue, 1) end
    if nxt then UI.Callout(nxt.target, nxt.opts) end
end

local function BuildCallout()
    local S = UI.S
    local f = CreateFrame("Frame", "ZacUICallout", UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(130)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:Hide()
    f._zPopup = true
    -- (2026-11-08) the fill is painted here: a bare UI.Fill has no colour
    -- until a box paint runs, and nothing paints this one (it showed white)
    local fill = UI.Fill(f, "ui", "windowBg", 0.98)
    fill:SetVertexColor(S.BG.r, S.BG.g, S.BG.b, 0.98)
    local a = GetColor("ui", "accent")
    if ns.Pixel and ns.Pixel.Border then
        f._zEdges = ns.Pixel.Border(f, a.r, a.g, a.b, 0.8, "BORDER")
    else
        UI.Border(f, "ui", "accent")
    end
    f.text = UI.PopupText(f, "body", { justify = "LEFT", width = CALLOUT_W - 2 * CO_PAD, alpha = 0.9 })
    f.text:SetPoint("TOPLEFT", CO_PAD, -CO_PAD)
    f.okay = UI.SettingsBuild(UI.Button, f, "Okay", { width = CO_BTN_W, height = CO_BTN_H })
    f.okay:SetPoint("BOTTOMRIGHT", -CO_PAD, CO_BOT)
    local arrow = f:CreateTexture(nil, "OVERLAY")
    arrow._zui_own = true
    arrow:SetSize(ARROW, ARROW)
    arrow:SetVertexColor(a.r, a.g, a.b, 1)
    f.arrow = arrow
    f._zPaint = function(self)
        fill:SetVertexColor(S.BG.r, S.BG.g, S.BG.b, 0.98)
        local c = GetColor("ui", "accent")
        if self._zEdges then for _, t in ipairs(self._zEdges) do t:SetColorTexture(c.r, c.g, c.b, 0.8) end end
        arrow:SetVertexColor(c.r, c.g, c.b, 1)
    end
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
    f.text:SetWidth(w - 2 * CO_PAD)
    f.text:SetText(opts.text or "")
    f:SetSize(w, CO_PAD + math.ceil(f.text:GetStringHeight() or POP.BODY) + 12 + CO_BTN_H + CO_BOT)
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
    f:_zPaint()
    f:Show()
    if ns.PopIn and not (ns.Motion and ns.Motion.Enabled and not ns.Motion.Enabled()) then pcall(ns.PopIn, f, 0.15) end
    return f
end

-- ============================================================
-- CONTACT (2026-11-08): "Need help? Message Zac on Discord"
-- ============================================================
-- Opened from the settings window (the speech-bubble button by the ZacUI
-- name, the Overview page's "Need help?" card). An addon cannot open a
-- link or reach the clipboard, so the name sits selected in a box, ready
-- for Ctrl+C. The name cannot be typed over; Escape closes it.
ns.CONTACT_DISCORD = "Zac12"
ns.CONTACT_TWITCH = "twitch.tv/zac984"
ns.ICON_TWITCH = (ns.MEDIA or "Interface\\AddOns\\ZacUI\\Media\\") .. "Icons\\twitch"
ns.ICON_DISCORD = (ns.MEDIA or "Interface\\AddOns\\ZacUI\\Media\\") .. "Icons\\discord"
local contact
local CONTACT_W = 400

local function BuildContact()
    local f = UI.Popup("ZacUIContactDialog", CONTACT_W, 200, "Need help?", { desc = "Message Zac on Discord",
        icon = ns.ICON_DISCORD, strata = "FULLSCREEN_DIALOG", level = 120 })
    local pad = f.pad
    local box = UI.SettingsBuild(UI.EditBox, f, { width = CONTACT_W - 2 * pad })
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -f.headerHeight)
    local eb = box.editBox
    -- the name cannot be typed over: any edit puts it back, selected
    eb:SetScript("OnTextChanged", function(self, user)
        local want = f._zText or ns.CONTACT_DISCORD
        if user and self:GetText() ~= want then
            self:SetText(want)
            self:HighlightText()
        end
    end)
    eb:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
    eb:SetScript("OnEnterPressed", function(self) self:HighlightText() end)
    -- Escape in the box closes the popup (the box holds the keyboard, so
    -- UISpecialFrames never sees that Escape)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() UI.CloseWindow(f) end)

    local hint = UI.PopupText(f, "hint", { text = "Ctrl+C to copy" })
    hint:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 1, -8)

    local done = f:SetButtons({ { text = "Close", kind = "primary", onClick = function() UI.CloseWindow(f) end } })[1]
    f:FitHeight(UI.S.EDIT_H + 8 + POP.HINT + 2)

    f.icon, f.title, f.line, f.box, f.editBox, f.hint, f.done = f.titleIcon, f.titleText, f.descText, box, eb, hint, done
    contact = f
    return f
end

-- kind: nil (Discord: Zac's name to message) or "twitch" (his channel)
function UI.ShowContact(kind)
    local f = contact or BuildContact()
    local eb = f.editBox
    local tw = kind == "twitch"
    f._zText = tw and ns.CONTACT_TWITCH or ns.CONTACT_DISCORD
    f:SetTitle(tw and "Watch on Twitch" or "Need help?", tw and "Zac's channel" or "Message Zac on Discord")
    if f.titleIcon then f.titleIcon:SetTexture(tw and ns.ICON_TWITCH or ns.ICON_DISCORD) end
    eb:SetText(f._zText)
    UI.OpenWindow(f)
    f:Raise()
    eb:SetFocus()
    eb:HighlightText()
    return f
end
ns.ShowContact = UI.ShowContact

-- The settings window's contact button: the speech bubble, white at the
-- window's dim alpha, full under the mouse; a tooltip says what it does.
function UI.ContactButton(parent, size, kind)
    local S = UI.S
    size = size or 28
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    local t = b:CreateTexture(nil, "ARTWORK")
    t._zui_own = true
    t:SetAllPoints()
    t:SetTexture(kind == "twitch" and ns.ICON_TWITCH or ns.ICON_DISCORD)
    b._zIcon = t
    b._zPaint = function(self)
        if self._zHot then
            local a = GetColor("ui", "accent")
            t:SetVertexColor(a.r, a.g, a.b, 1)
        else
            t:SetVertexColor(1, 1, 1, S.DIM_A)
        end
    end
    b:HookScript("OnEnter", function(self) self._zHot = true self:_zPaint() end)
    b:HookScript("OnLeave", function(self) self._zHot = nil self:_zPaint() end)
    b:SetScript("OnClick", function() UI.ShowContact(kind) end)
    if kind == "twitch" then
        UI.Tooltip(b, "Watch on Twitch", ns.CONTACT_TWITCH .. ". Click to copy the link.")
    else
        UI.Tooltip(b, "Need help?", "Message Zac on Discord: " .. ns.CONTACT_DISCORD .. ". Click to copy the name.")
    end
    b:_zPaint()
    return b
end

-- ============================================================
-- INPUT
-- ============================================================
function UI.Prompt(opts)
    opts = opts or {}
    if not input then
        input = Dialog("ZacUIInputDialog", "ZacUI")
        input.box = UI.SettingsBuild(UI.EditBox, input, { width = DIALOG_W - 2 * input.pad })
        local b = input:SetButtons({
            { text = CANCEL or "Cancel", onClick = function() UI.CloseWindow(input) end },
            { text = OKAY or "Okay", kind = "primary" },
        })
        input.cancel, input.accept = b[1], b[2]
    end

    input:SetTitle(opts.title or "ZacUI")
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

    local h = MessageH(input.message)
    input.message:ClearAllPoints()
    input.message:SetPoint("TOPLEFT", input, "TOPLEFT", input.pad, -input.headerHeight)
    input.box:ClearAllPoints()
    input.box:SetPoint("TOPLEFT", input, "TOPLEFT", input.pad, -(input.headerHeight + h + 10))
    input:FitHeight(h + 10 + UI.S.EDIT_H)

    UI.OpenWindow(input)
    input.box.editBox:SetFocus()
    return input
end
