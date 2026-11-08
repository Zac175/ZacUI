-- Config_PagesMotion - Appearance > Motion: whether ZacUI animates at
-- all, how fast, and a place to try every animation style.
-- Part of ZacUI; load order is set by the TOC.
--
-- The two settings live in ZacUIDB.motion ({ enabled, speed }, its own
-- profile section) and are read by ns.Motion (UIF_Anim) each time an
-- animation starts - every module's show/hide/highlight animations and
-- ZacUI's own windows opening and closing.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local GetColor = ns.GetColor
local Motion = ns.Motion
local RefreshConfig = ns.RefreshConfig
local RegisterPage = ns.RegisterPage
local UI = ns.UI

local M, F = UI.M, UI.F

local function DB()
    ZacUIDB.motion = ZacUIDB.motion or {}
    return ZacUIDB.motion
end

-- The playground's animation. Window state like the rest of
-- ZacUIDB.config: it shapes nothing but this page's preview.
local TRY_DEFAULT = { style = "slide", duration = 0.35, delay = 0,
                      easing = "easeOutBack", dir = "down", distance = 24 }
local function Try()
    ZacUIDB.config = ZacUIDB.config or {}
    local c = ZacUIDB.config
    if type(c.motionTry) ~= "table" then c.motionTry = ns.CopySetting(TRY_DEFAULT) end
    return c.motionTry
end

-- ============================================================
-- PREVIEW
-- ============================================================
-- A small ZacUI panel - title, a bar, a line of text - played with the
-- playground's animation at the global speed, as Show, Hide or Highlight.
-- Wide and short for the preview strip: the panel's title and bar side by
-- side over its line of text, the "animations are off" note beside it.
local MOTION_PV_W, MOTION_PV_H = 470, 58

local function BuildMotionPreview(canvas, P)
    local panel = UI.Box(canvas, "ui", "windowBg")
    panel:SetSize(240, 46)
    panel:SetPoint("LEFT", canvas, "LEFT", 10, 0)
    local title = UI.Font(panel, F.CARD, { text = "Sample", cat = "text", key = "gold" })
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -7)
    local bar = CreateFrame("StatusBar", nil, panel)
    bar:SetPoint("TOPLEFT", panel, "TOPLEFT", 74, -9)
    bar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -9)
    bar:SetHeight(11)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0.64)
    UI.Border(bar, "ui", "border")
    local line = UI.Font(panel, F.SMALL, { text = "Shown, hidden or highlighted", cat = "text", key = "gray" })
    line:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -28)
    local note = UI.Font(canvas, F.SMALL, { text = "Animations are off - changes are instant.",
        cat = "text", key = "orange", justify = "RIGHT", width = 200 })
    note:SetPoint("RIGHT", canvas, "RIGHT", -10, 0)
    P.store.panel, P.store.bar, P.store.note = panel, bar, note
    P.store.serial = 0
end

local function ReplayMotionPreview(canvas, P)
    local st = P.store
    local panel = st.panel
    st.serial = st.serial + 1
    local mine = st.serial
    Motion.Stop(panel)
    local spec = Try()
    local mode = P.mode or "in"
    if mode == "in" then
        panel:Hide()
        Motion.Play(panel, spec, "in")
    elseif mode == "out" then
        panel:Show()
        -- gone, then back after a beat so there is something to replay
        Motion.Play(panel, spec, "out", function()
            C_Timer.After(0.6, function()
                if st.serial == mine then panel:Show() end
            end)
        end)
    else
        panel:Show()
        Motion.Play(panel, spec, "update")
    end
end

local function UpdateMotionPreview(canvas, P)
    local st = P.store
    local tex = ns.Media and ns.Media.BarPath() or ns.TEX_NORM
    local a = GetColor("ui", "accent")
    st.bar:SetStatusBarTexture(tex)
    st.bar:SetStatusBarColor(a.r, a.g, a.b, 1)
    UI.Repaint(st.panel)
    st.note:SetShown(not Motion.Enabled())
    -- every setting on this page is about motion: show it moving
    ReplayMotionPreview(canvas, P)
end

-- ============================================================
-- PAGE
-- ============================================================
RegisterPage("Motion", function(L)
    L:Header("Motion",
        "How ZacUI animates: windows opening and closing, frames appearing "
        .. "and going, alerts that want your eye.")

    L:Preview({
        key = "appearance.motion",
        title = "Animation",
        width = MOTION_PV_W, height = MOTION_PV_H,
        modes = {
            { id = "in", label = "Show" },
            { id = "out", label = "Hide" },
            { id = "update", label = "Highlight" },
        },
        build = BuildMotionPreview,
        update = UpdateMotionPreview,
        replay = ReplayMotionPreview,
    })

    L:Card("Animations")
    local on = UI.Checkbox(L.current, "Play animations", Motion.Enabled(), function(v)
        DB().enabled = v
        RefreshConfig()
    end)
    L:Row(on, 17)
    L:Desc("Off makes every ZacUI animation an instant change: windows, frames "
        .. "and alerts simply appear and go. For anyone who finds motion "
        .. "distracting or uncomfortable.")
    L:Gap(4)
    local speed = UI.Slider(L.current, {
        width = 220, min = 0.25, max = 3, step = 0.05,
        value = Motion.Speed(), label = "Speed",
        format = function(v) return string.format("%.2fx", v) end,
        onChange = function(v) DB().speed = math.floor(v * 100 + 0.5) / 100 end,
    })
    L:Row(speed, 40)
    UI.SetEnabled(speed, Motion.Enabled(), 'Needs "Play animations" turned on.')
    L:Desc("Higher is faster. At 1x every animation runs at the length it was set to.")
    L:Gap(4)
    local reset = UI.Button(L.current, "Reset", { width = 80,
        tooltip = "Animations on, at 1x speed.",
        onClick = function()
            ZacUIDB.motion = nil
            RefreshConfig()
        end })
    L:Row(reset, M.BUTTON_H + 6)
    L:EndCard()

    L:Card("Try an animation")
    L:Desc("Pick a style and watch it in the preview - Show, Hide and Highlight "
        .. "are above it. This is a playground: each part of ZacUI has its own "
        .. "animation settings on its own page.")
    L:Gap(4)
    local picker = UI.AnimationPicker(L.current, {
        get = Try,
        set = function(spec) ZacUIDB.config.motionTry = spec end,
    })
    L:Add(picker, 6)
    L:EndCard()
end)
