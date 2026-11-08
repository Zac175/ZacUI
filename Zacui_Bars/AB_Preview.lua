-- AB_Preview - which bar the Action bars page is editing, and the dock
-- preview that shows it: sample buttons drawn by the bars' own styling.
-- Part of ZacUI; load order is set by the TOC.
--
-- LOOK-ALIKES, NEVER ACTION BUTTONS. A sample is a plain CheckButton
-- (the stock art template when the client has it, which is visuals only,
-- never the secure one), parented to the dock's canvas, with no events,
-- no action, no binding and no place in the bars' own lists. It is
-- skinned and styled by exactly the functions the live buttons use -
-- ns.SkinSecureIcon, AB.StyleButton, AB.ApplyText, AB.FitText,
-- AB.LayoutButtons, AB.ButtonTint, AB.SetGlow, AB.FadeTo - so what the
-- dock shows is what the bars draw.
--
-- THE FAKE STATE. One action bar shows everything at once: a spell on
-- cooldown, one that cannot be used yet, a spell alert, the queued
-- attack, a target out of range, not enough rage, a macro name, a potion
-- stack and an empty slot - each in the colours and fonts the bar uses.

local ADDON_NAME = ...
-- Zacui_Bars is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

local AB = ns.Bars
local UI = ns.UI

-- ============================================================
-- WHICH BAR THE PAGE EDITS
-- ============================================================
AB.BAR_CHOICES = {}
for n = 1, AB.NUM_BARS do AB.BAR_CHOICES[#AB.BAR_CHOICES + 1] = { id = "bar" .. n, label = "Bar " .. n } end
for _, c in ipairs({ { id = "pet", label = "Pet bar" }, { id = "stance", label = "Stance bar" },
                     { id = "bagbar", label = "Bag bar" }, { id = "micro", label = "Micro menu" },
                     { id = "status", label = "XP bar" } }) do
    AB.BAR_CHOICES[#AB.BAR_CHOICES + 1] = c
end
local VALID, LABEL = {}, {}
for _, c in ipairs(AB.BAR_CHOICES) do VALID[c.id], LABEL[c.id] = true, c.label end

-- "action" for the ten bars, else the id itself
function AB.KindOf(id)
    if type(id) == "string" and id:match("^bar%d+$") then return "action" end
    return id
end

function AB.BarLabel(id) return LABEL[id] or tostring(id) end

-- the settings table behind a choice (and the bar number for bars 1-10)
function AB.CfgFor(id, profile)
    profile = profile or AB.Profile()
    local n = tonumber(type(id) == "string" and id:match("^bar(%d+)$") or nil)
    if n then return profile.bars[n], n end
    return profile[id]
end

-- Window state (ZacUIDB.config), like the page's remembered tab. The
-- page used to have one tab per bar: a tab remembered from then names
-- the bar to start on.
local OLD_TABS = { bags = "bagbar" }
function AB.EditingId()
    ZacUIDB.config = ZacUIDB.config or {}
    local s = ZacUIDB.config
    if VALID[s.barsEdit] then return s.barsEdit end
    local old = s.tabs and s.tabs.bars
    old = OLD_TABS[old] or old
    s.barsEdit = VALID[old] and old or "bar1"
    return s.barsEdit
end

function AB.SetEditing(id)
    if not VALID[id] then return end
    ZacUIDB.config = ZacUIDB.config or {}
    ZacUIDB.config.barsEdit = id
end

-- ============================================================
-- SAMPLE DATA
-- ============================================================
local I = "Interface\\Icons\\"
local ACTION_SAMPLE = {
    { icon = I .. "Spell_Nature_BloodLust", key = "1", cd = { 3.5, 6 } },
    { icon = I .. "Ability_Whirlwind", key = "2" },
    { icon = I .. "INV_Sword_48", key = "3", usable = false },
    { icon = I .. "Ability_MeleeDamage", key = "4", proc = true },
    { icon = I .. "Ability_Rogue_Ambush", key = "5", checked = true },
    { icon = I .. "Ability_ShockWave", key = "Q", oor = true },
    { icon = I .. "INV_Gauntlets_04", key = "E", noMana = true },
    { icon = I .. "Ability_Warrior_BattleShout", key = "R", macro = "Shout" },
    { icon = I .. "INV_Potion_54", key = "F", count = 5 },
    { icon = I .. "Ability_Racial_BloodRage", key = "SHIFT-1", cd = { 42, 60 } },
    { icon = I .. "Spell_Shadow_DeathPact", key = "CTRL-MOUSEWHEELUP" },
    { empty = true, key = "ALT-BUTTON4" },
}
local PET_SAMPLE = {
    { icon = I .. "Ability_GhoulFrenzy", checked = true }, { icon = I .. "Ability_Tracking" },
    { icon = I .. "Spell_Nature_TimeStop" }, { icon = I .. "Ability_Druid_Rake", cd = { 2, 4 } },
    { icon = I .. "Ability_Racial_Cannibalize" }, { icon = I .. "Spell_Nature_Reincarnation", usable = false },
    { icon = I .. "Ability_Hunter_Pet_Wolf" }, { icon = I .. "Ability_Defend" },
    { icon = I .. "Ability_Seal" }, { icon = I .. "Ability_Racial_BloodRage" },
}
local STANCE_SAMPLE = {
    { icon = I .. "Ability_Warrior_OffensiveStance", checked = true },
    { icon = I .. "Ability_Warrior_DefensiveStance" },
    { icon = I .. "Ability_Racial_Avatar" },
}
local BAG_SAMPLE = {
    { icon = "Interface\\Buttons\\UI-Button-KeyRing", keyring = true },
    { icon = I .. "INV_Misc_Bag_10_Blue" }, { icon = I .. "INV_Misc_Bag_10_Green" },
    { icon = I .. "INV_Misc_Bag_10_Red" }, { icon = I .. "INV_Misc_Bag_10" },
    { icon = "Interface\\Buttons\\Button-Backpack-Up" },
}
local MICRO_SAMPLE = { "Character", "Spellbook", "Talents", "Quest", "Socials", "World", "MainMenu", "Help" }

-- The canvas: the bar at its real size (its own scale included) plus the
-- caption under it; update sizes it from the bar and hands it to
-- P.Resize. The preview strip shows it at the real size, or scaled down
-- to fit (and says so).
local W, H = 496, 76
local W_MIN, H_MIN = 300, 60
local CAPTION_H = 30

-- ============================================================
-- SAMPLE FRAMES
-- ============================================================
local serialName = 0
local function NewName(kind)
    serialName = serialName + 1
    return "ZacUIBarSample" .. kind .. serialName
end

local function SampleButton(parent, kind)
    local name = NewName(kind)
    local ok, b = pcall(CreateFrame, "CheckButton", name, parent, "ActionButtonTemplate")
    if not ok or not b then b = CreateFrame("CheckButton", name, parent) end
    b.zSample = true
    if not AB.Region(b, "icon", "Icon") then
        local t = b:CreateTexture(nil, "BACKGROUND")
        t:SetAllPoints(b)
        b.icon = t
    end
    if not AB.Region(b, "cooldown", "Cooldown") then
        local okc, cd = pcall(CreateFrame, "Cooldown", nil, b, "CooldownFrameTemplate")
        if not okc or not cd then cd = CreateFrame("Cooldown", nil, b) end
        cd:SetAllPoints(b)
        b.cooldown = cd
    end
    local cd = AB.Region(b, "cooldown", "Cooldown")
    if cd and cd.SetDrawEdge then cd:SetDrawEdge(false) end
    for key, tmpl in pairs({ HotKey = "NumberFontNormalSmallGray", Count = "NumberFontNormal",
                             Name = "GameFontHighlightSmallOutline" }) do
        if not AB.Region(b, key, key) then
            local okf, fs = pcall(b.CreateFontString, b, nil, "OVERLAY", tmpl)
            if not okf or not fs then fs = b:CreateFontString(nil, "OVERLAY") end
            b[key] = fs
        end
    end
    b.zHotkey = AB.Region(b, "HotKey", "HotKey")
    b.zCount = AB.Region(b, "Count", "Count")
    b.zName = AB.Region(b, "Name", "Name")
    -- tagged for ZacUI's pick hook: a click on a sample text opens its spot
    if ns.TagElement then
        ns.TagElement(b.zHotkey, "ab.hotkey") ns.TagElement(b.zCount, "ab.count") ns.TagElement(b.zName, "ab.macro")
        ns.TagElement(b, "ab.button")
    end
    local flat = ns.FLAT or "Interface\\Buttons\\WHITE8X8"
    if b.SetHighlightTexture and not (b.GetHighlightTexture and b:GetHighlightTexture()) then b:SetHighlightTexture(flat) end
    if b.SetPushedTexture and not (b.GetPushedTexture and b:GetPushedTexture()) then b:SetPushedTexture(flat) end
    if b.SetCheckedTexture and not (b.GetCheckedTexture and b:GetCheckedTexture()) then b:SetCheckedTexture(flat) end
    -- a look-alike: no drag, and a click puts the fake state back
    if b.RegisterForDrag then b:RegisterForDrag() end
    b:SetScript("OnClick", function(self) if self.SetChecked then self:SetChecked(self.zChecked and true or false) end end)
    -- (the template's own sizes first, for a game look's kit: AB_Core)
    if AB.KitCapture then AB.KitCapture(b) end
    if ns.SkinSecureIcon then ns.SkinSecureIcon(b) end
    return b
end

-- the game's own spell alert, drawn as a look-alike (the client's alert
-- frames are a shared pool its secure buttons use; an addon frame never
-- borrows one)
local function StockAlert(b)
    local t = b.zStockAlert
    if not t then
        t = b:CreateTexture(nil, "OVERLAY", nil, 6)
        t._zui_own = true
        t:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
        t:SetTexCoord(0.0078125, 0.5078125, 0.27734375, 0.52734375)
        if t.SetBlendMode then t:SetBlendMode("ADD") end
        b.zStockAlert = t
    end
    local w = b:GetWidth() or AB.BUTTON
    t:ClearAllPoints()
    t:SetPoint("CENTER", b, "CENTER", 0, 0)
    t:SetSize(w * 1.4, w * 1.4)
    return t
end

local function NewGroup(canvas, kind, data, size)
    local g = { kind = kind, buttons = {} }
    g.root = CreateFrame("Frame", nil, canvas)
    g.root:SetSize(1, 1)
    g.root:Hide()
    if kind == "micro" then
        for i, part in ipairs(data) do
            local b = CreateFrame("Button", nil, g.root)
            local t = b:CreateTexture(nil, "ARTWORK")
            t:SetAllPoints(b)
            t:SetTexture("Interface\\Buttons\\UI-MicroButton-" .. part .. "-Up")
            t:SetTexCoord(0, 1, 0.34, 1)
            b.zTex = t
            g.buttons[i] = b
        end
    elseif kind == "status" then
        local bar = CreateFrame("StatusBar", nil, g.root)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0.62)
        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(bar)
        bg:SetColorTexture(0, 0, 0, 0.6)
        if ns.AddPixelBorder then ns.AddPixelBorder(bar) end
        g.bar = bar
    else
        for i, d in ipairs(data) do
            local b = SampleButton(g.root, kind)
            b.zData = d
            g.buttons[i] = b
        end
    end
    -- cooldowns that run out start again while the dock is up; an
    -- OnUpdate on the sample, so it stops by itself when the dock hides
    g.root:SetScript("OnUpdate", function(self, elapsed)
        self.zTick = (self.zTick or 0) + elapsed
        if self.zTick < 0.25 then return end
        self.zTick = 0
        local now = GetTime()
        for _, b in ipairs(g.buttons) do
            if b.zCdEnd and now >= b.zCdEnd then g.StartCooldown(b) end
        end
    end)
    function g.StartCooldown(b)
        local d = b.zData
        local cd = AB.Region(b, "cooldown", "Cooldown")
        if not (d and d.cd and cd) then return end
        local left, dur = d.cd[1], d.cd[2]
        local now = GetTime()
        if cd.SetCooldown then cd:SetCooldown(now - (dur - left), dur) end
        b.zCdEnd = now + left
    end
    for _, b in ipairs(g.buttons) do g.StartCooldown(b) end
    return g
end

local function Group(P, canvas, kind)
    local st = P.store
    st.groups = st.groups or {}
    local g = st.groups[kind]
    if g then return g end
    local data = (kind == "action" and ACTION_SAMPLE) or (kind == "pet" and PET_SAMPLE)
        or (kind == "stance" and STANCE_SAMPLE) or (kind == "bagbar" and BAG_SAMPLE)
        or (kind == "micro" and MICRO_SAMPLE) or {}
    g = NewGroup(canvas, kind, data)
    st.groups[kind] = g
    return g
end

-- ============================================================
-- STYLING THE SAMPLES (the bars' own functions, fake data)
-- ============================================================
local function StyleActionLike(g, cfg, core, kind)
    local size = cfg.buttonSize or ((kind == "action") and AB.BUTTON or AB.PET_BUTTON)
    local f = cfg.fonts or {}
    for _, b in ipairs(g.buttons) do
        local d = b.zData or {}
        local icon = AB.Region(b, "icon", "Icon")
        if icon then
            icon:SetTexture(not d.empty and d.icon or nil)
            if d.empty then icon:Hide() else icon:Show() end
        end
        b.zChecked = d.checked and true or false
        if b.SetChecked then b:SetChecked(b.zChecked) end
        if kind == "action" then
            if b.zHotkey then b.zHotkey:SetText(AB.ShortKey(d.key)) end
            if b.zCount then b.zCount:SetText(d.count and tostring(d.count) or "") end
            if b.zName then b.zName:SetText(d.macro or "") end
            AB.ApplyText(b, b.zHotkey, f.hotkey, cfg.hideHotkey, "hotkey", cfg)
            AB.ApplyText(b, b.zCount, f.count, cfg.hideCount, "count", cfg)
            AB.ApplyText(b, b.zName, f.macro, cfg.hideMacro, "macro", cfg)
        else
            -- the pet and stance bars keep the template's text; only
            -- whether the key shows is theirs (KeyText, below)
            if b.zCount then b.zCount:SetText("") end
            if b.zName then b.zName:SetText("") end
        end
        if kind == "action" then AB.FitText(b, size) end
        b.zCfg = cfg
        -- (a game look's Classic ring: the empty-slot art on the empty one)
        if AB.KitSlot then AB.KitSlot(b, not d.empty) end
        AB.StyleButton(b, cfg)
        -- the colours the bar would put on a button in this state
        local ir, ig, ib, hr, hg, hb = AB.ButtonTint(core, d.oor, d.usable ~= false, d.noMana)
        if icon then icon:SetVertexColor(ir, ig, ib) end
        if b.zHotkey and hr then b.zHotkey:SetTextColor(hr, hg, hb, 1) end
        -- an empty slot is there only while the bar shows its grid
        if d.empty then b:SetAlpha(cfg.showgrid and 1 or 0) else b:SetAlpha(1) end
        -- and its backing, when that is on (AB_ActionBars)
        if kind == "action" and AB.EmptyBacking then AB.EmptyBacking(b, d.empty and cfg.showgrid and true or false) end
    end
    return size
end

local function KeyText(g, cfg, keys)
    for i, b in ipairs(g.buttons) do
        if b.zHotkey then
            b.zHotkey:SetText((not cfg.hideHotkey and keys[i]) and AB.ShortKey(keys[i]) or "")
            b.zHotkey:SetAlpha(cfg.hideHotkey and 0 or 1)
        end
    end
end

local function GlowSig(core)
    local r, g, b, a = ns.ColorOf(core.glowColor, { 1, 0.82, 0, 1 })
    local m = ns.Motion and ns.Motion.Normalize(core.glowAnim) or {}
    return table.concat({ tostring(core.glow), tostring(core.glowSize), r, g, b, a,
        tostring(m.style), tostring(m.duration), tostring(m.loop), tostring(m.easing) }, ":")
end

-- the spell alert on the sample's proc button, in the bar's chosen way
local function ShowGlow(g, core, force)
    local b
    for _, x in ipairs(g.buttons) do if x.zData and x.zData.proc then b = x end end
    if not b then return end
    local sig = GlowSig(core)
    if not force and g.glowSig == sig then return end
    g.glowSig = sig
    local mode = core.glow or "game"
    if mode == "zacui" then
        if b.zStockAlert then b.zStockAlert:Hide() end
        AB.SetGlow(b, true, true)
    else
        AB.SetGlow(b, false)
        if mode == "game" then StockAlert(b):Show()
        elseif b.zStockAlert then b.zStockAlert:Hide() end
    end
end

-- the extent of `count` buttons of w x h laid out in cfg.rows rows
local function Extent(count, rowsWanted, w, h, pad)
    count = math.max(count, 1)
    local rows = math.max(1, math.min(rowsWanted or 1, count))
    local perRow = math.ceil(count / rows)
    rows = math.ceil(count / perRow)
    return perRow * (w + pad) - pad, rows * (h + pad) - pad
end

-- the same through the bar's layout (cfg.layout: buttons per row and two
-- gaps); nothing saved = Extent exactly
local function ExtentFor(cfg, count, w, h, pad)
    if not (AB.LayoutSpec and AB.LayoutSpec(cfg)) then return Extent(count, cfg.rows, w, h, pad) end
    local perRow, rows, padX, padY = AB.LayoutShape(cfg, count)
    return perRow * (w + padX) - padX, rows * (h + padY) - padY
end

-- Hangs the group's root so its content sits in the middle of the
-- canvas above the caption, at the bar's own scale.
local function Center(g, canvas, cfg, w, h, layoutCfg)
    local want = cfg.scale or 1
    if want <= 0 then want = 1 end
    local s = want
    g.root:SetScale(s)
    local anchor, v, hz = AB.AnchorOf(layoutCfg or cfg)
    local ox = (hz == "LEFT") and 5 or -3
    local oy = (v == "TOP") and -3 or 5
    local cx = ((hz == "LEFT") and -w / 2 or w / 2) - ox
    local cy = ((v == "TOP") and h / 2 or -h / 2) - oy + (CAPTION_H / 2) / s
    g.root:ClearAllPoints()
    g.root:SetPoint(anchor, canvas, "CENTER", cx, cy)
    return want, s
end

local function Pct(v) return math.floor((v or 0) * 100 + 0.5) .. "%" end

-- what the bar does that a picture cannot show: when it hides, how it pages
local function Conditions(kind, cfg)
    local out = {}
    if cfg.fade then out[#out + 1] = "fades to " .. Pct(cfg.fadeAlpha or 0.1) .. " until pointed at" end
    local v = cfg.visibility or {}
    if v.custom and v.customdata and v.customdata ~= "" then
        out[#out + 1] = "custom show / hide condition"
    elseif v.always then
        out[#out + 1] = "always hidden"
    else
        local hide = {}
        if v.combat then hide[#hide + 1] = "in combat" end
        if v.nocombat then hide[#hide + 1] = "out of combat" end
        if v.pet then hide[#hide + 1] = "with a pet" end
        if v.nopet then hide[#hide + 1] = "without a pet" end
        if v.mounted then hide[#hide + 1] = "mounted" end
        if #hide > 0 then out[#out + 1] = "hidden " .. table.concat(hide, " / ") end
    end
    if kind == "action" and cfg.paging and cfg.paging.enabled then
        local p = cfg.paging
        if p.customEnabled and p.custom ~= "" then out[#out + 1] = "custom paging"
        else
            local st = p.stance and p.stance[AB.PLAYER_CLASS]
            if st and next(st) then out[#out + 1] = "pages with your stance" end
            if (p.ctrl or 0) > 0 or (p.alt or 0) > 0 or (p.shift or 0) > 0 then out[#out + 1] = "pages on modifiers" end
            if p.actionbar then out[#out + 1] = "follows the page keys" end
        end
    end
    if cfg.clickthrough then out[#out + 1] = "click-through" end
    if #out == 0 then return "Always shown" end
    local s = table.concat(out, ", ")
    return s:sub(1, 1):upper() .. s:sub(2)
end

-- the alpha the bar sits at in the chosen preview mode
local function ModeAlpha(P, cfg)
    local off = (cfg.enabled == false) and 0.35 or 1
    if P.mode == "faded" and cfg.fade then return (cfg.fadeAlpha or 0.1) * off end
    return (cfg.alpha or 1) * off
end

local function Update(canvas, P)
    local st = P.store
    local id = AB.EditingId()
    local kind = AB.KindOf(id)
    local p = AB.Profile()
    local cfg = AB.CfgFor(id, p) or {}
    local core = p.core or {}
    if st.picker then st.picker:SetText(AB.BarLabel(id)) end
    for k, other in pairs(st.groups or {}) do
        if k ~= kind then other.root:Hide() end
    end
    local g = Group(P, canvas, kind)
    st.current, st.currentId = g, id
    g.root:Show()

    local w, h, count, lay = 0, 0, 0, cfg
    local pad = cfg.padding or 2
    if kind == "action" or kind == "pet" or kind == "stance" then
        local size = StyleActionLike(g, cfg, core, kind)
        count = (kind == "action") and (cfg.buttons or 12) or #g.buttons
        if kind == "stance" then
            local n = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
            count = (n > 0) and math.min(n, #g.buttons) or #g.buttons
        end
        if kind == "pet" then KeyText(g, cfg, { "CTRL-1", "CTRL-2", "CTRL-3", "CTRL-4", "CTRL-5" }) end
        if kind == "stance" then KeyText(g, cfg, { "F1", "F2", "F3" }) end
        AB.LayoutButtons(g.root, g.buttons, cfg, size, count)
        w, h = ExtentFor(cfg, count, size, size, pad)
        if kind == "action" then ShowGlow(g, core) end
        -- a game look's end caps / frame, as the bar draws them (AB_Core)
        if kind == "action" and AB.KitChrome then
            AB.KitChrome(g.root, cfg, size, count, tonumber(id:match("^bar(%d+)$") or "") or 0)
        end
    elseif kind == "bagbar" then
        -- the live strip's order: key ring, bags 4-1, backpack
        local list, ring = {}, nil
        for i, b in ipairs(g.buttons) do
            local d = b.zData
            local show
            if cfg.onebag then show = (i == #g.buttons)
            elseif d.keyring then show = cfg.keyring and true or false
            else show = true end
            if show then list[#list + 1] = b else b:Hide() end
            if show and d.keyring then ring = b end
            local icon = AB.Region(b, "icon", "Icon")
            if icon then icon:SetTexture(d.icon) end
            b.zCfg = cfg
        end
        AB.LayoutButtons(g.root, list, cfg, 37, #list)
        if ring then ring:SetSize(18, 37) end
        count = #list
        w, h = ExtentFor(cfg, count, 37, 37, pad)
        if ring then w = w - 19 end
    elseif kind == "micro" then
        AB.LayoutMicro(g.root, g.buttons, cfg)
        count = #g.buttons
        local rows = cfg.vertical and count or 1
        w, h = Extent(count, rows, 32, 40, pad)
        lay = { growH = cfg.growH, growV = cfg.growV }
    elseif kind == "status" then
        local bw = cfg.width or 1024
        g.bar:ClearAllPoints()
        g.bar:SetPoint("TOPLEFT", g.root, "TOPLEFT", 0, 0)
        g.bar:SetSize(bw, 14)
        g.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        g.bar:SetStatusBarColor(0.58, 0.0, 0.55, 1)
        w, h = bw, 14
        lay = { growH = "RIGHT", growV = "DOWN" }
        -- the strip hangs from its top-left corner, not the button offset
        local want = cfg.scale or 1
        if want <= 0 then want = 1 end
        local s = want
        W = math.max(W_MIN, math.ceil(bw * s) + 16)
        if P.Resize then P.Resize(W, H_MIN) end
        g.root:SetScale(s)
        g.root:ClearAllPoints()
        g.root:SetPoint("TOPLEFT", canvas, "CENTER", -bw / 2, 7 + (CAPTION_H / 2) / s)
        st.want, st.shown = want, s
    end
    if kind ~= "status" then
        -- the canvas is the bar at its own scale, and the caption
        local want = (cfg.scale and cfg.scale > 0) and cfg.scale or 1
        W = math.max(W_MIN, math.ceil(w * want) + 16)
        H = math.max(H_MIN, math.ceil(h * want) + CAPTION_H + 14)
        if P.Resize then P.Resize(W, H) end
        st.want, st.shown = Center(g, canvas, cfg, w, h, lay)
    else
        H = H_MIN
    end

    -- where the bar sits: the chosen mode (shown / faded), never mid-fade
    st.serial = (st.serial or 0) + 1
    AB.FadeTo(g.root, ModeAlpha(P, cfg), nil)

    -- the caption
    local line1 = AB.BarLabel(id)
    if cfg.enabled == false then
        line1 = line1 .. " - off (turn it on under General)"
    else
        if kind ~= "status" then line1 = line1 .. " - " .. count .. (count == 1 and " button" or " buttons") end
        line1 = line1 .. " - " .. Pct(st.want)
        if Pct(st.shown) ~= Pct(st.want) then line1 = line1 .. " (shown at " .. Pct(st.shown) .. " to fit)" end
    end
    local line2 = Conditions(kind, cfg)
    if P.mode == "faded" and not cfg.fade then line2 = "Fading is off for this bar (General tab). " .. line2 end
    st.caption1:SetText(line1)
    st.caption2:SetText(line2)
end

-- Replay: the bar's fade out and back (or in and back, when the dock
-- shows it faded), at the bar's own fade settings, and its spell alert
-- glow started again. Each step checks the dock is still on screen.
local function Replay(canvas, P)
    local st = P.store
    local g = st.current
    if not g then return end
    local p = AB.Profile()
    local cfg = AB.CfgFor(st.currentId, p) or {}
    if g.kind == "action" then ShowGlow(g, p.core or {}, true) end
    if not cfg.fade then return end
    st.serial = (st.serial or 0) + 1
    local mine = st.serial
    local off = (cfg.enabled == false) and 0.35 or 1
    local full, faded = (cfg.alpha or 1) * off, (cfg.fadeAlpha or 0.1) * off
    local inS, outS, wait = AB.FadeSpecs(cfg)
    local M = ns.Motion
    local speed = (M and M.Enabled()) and M.Speed() or 1
    local function Len(spec, extra)
        if not (M and M.Enabled()) then return 0 end
        local s = M.Normalize(spec)
        if s.style == "none" then return 0 end
        return ((extra or s.delay or 0) + s.duration) / speed
    end
    local startFaded = (P.mode == "faded")
    local first, back = startFaded and full or faded, startFaded and faded or full
    local firstSpec, backSpec = startFaded and inS or outS, startFaded and outS or inS
    local firstWait, backWait = startFaded and nil or wait, startFaded and wait or nil
    AB.FadeTo(g.root, back, nil)
    local function Live() return st.serial == mine and g.root:IsVisible() end
    C_Timer.After(0.35, function()
        if not Live() then return end
        AB.FadeTo(g.root, first, firstSpec, firstWait)
        C_Timer.After(Len(firstSpec, firstWait) + 0.8, function()
            if not Live() then return end
            AB.FadeTo(g.root, back, backSpec, backWait)
        end)
    end)
end

local function Build(canvas, P)
    local st = P.store
    st.caption1 = UI.Font(canvas, UI.F.SMALL, { cat = "text", key = "normal", justify = "CENTER" })
    st.caption1:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", 4, 16)
    st.caption1:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", -4, 16)
    st.caption2 = UI.Font(canvas, UI.F.SMALL, { cat = "text", key = "gray", justify = "CENTER" })
    st.caption2:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", 4, 2)
    st.caption2:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", -4, 2)
    for _, fs in ipairs({ st.caption1, st.caption2 }) do
        if fs.SetWordWrap then fs:SetWordWrap(false) end
    end
end

-- the dock's own bar chooser, next to the mode buttons
local function Controls(row, P)
    local items = {}
    for _, c in ipairs(AB.BAR_CHOICES) do items[#items + 1] = { text = c.label, value = c.id } end
    local dd = UI.Dropdown(row, { width = 112,
        items = function() return items end,
        selected = function() return AB.BarLabel(AB.EditingId()) end,
        selectedValue = function() return AB.EditingId() end,
        onSelect = function(v)
            AB.SetEditing(v)
            if ns.RefreshConfig then ns.RefreshConfig() end
        end })
    dd:SetPoint("LEFT", row, "LEFT", 0, 0)
    P.store.picker = dd
end

-- The spec the page hands L:Preview (one key for every bar: the samples
-- for each kind are made once and kept).
function AB.PreviewSpec()
    return {
        key = "bars.bar",
        title = AB.BarLabel(AB.EditingId()),
        width = W, height = H,
        modes = { { id = "normal", label = "Shown" }, { id = "faded", label = "Faded" } },
        modesLabel = "Show",
        build = Build,
        update = Update,
        replay = Replay,
        controls = Controls,
    }
end
