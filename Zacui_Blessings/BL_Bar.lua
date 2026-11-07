-- BL_Bar - the paladin's casting bar: one row per class this paladin
-- blesses, each with the Greater Blessing on a left click and the normal
-- one on a right click, and (optionally) a button per player of that
-- class beside it; the aura button on top. It shows who is missing the
-- blessing, who is out of range, and the time left.
-- Part of ZacUI; load order is set by the TOC.
--
-- SECURE BUTTONS. Casting needs SecureActionButtons, and their spell /
-- unit / shown state can only change out of combat. So the layout is
-- rebuilt out of combat (roster or assignment changed) and waits for the
-- fight to end otherwise; in combat only the colours and timers move.
-- The status is read by one 1 s ticker while the bar is up - never from
-- UNIT_AURA.
--
-- THE LOOK. Sizes, colours, fonts, the fill texture and the two
-- animations are settings (ZacUIDB.blessings.bar; defaults in BL_Core
-- are what the bar always drew). The drawing is split from the casting:
-- Bar.NewView makes a bar, Bar.Arrange lays it out from a plan and
-- Bar.PaintClass / PaintPlayer / PaintAura colour it from a status - the
-- live bar hands them the group and its secure attributes, the settings
-- preview a made-up roster on plain buttons, so both look the same.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local D = ns.BlessingsData
local BL = ns.Blessings
if not (D and BL) then return end

local UI = ns.UI
local Print = ns.Print

local Bar = {}
BL.Bar = Bar

local Fmt       -- time left as text; defined with the status pass below
local FLAT = ns.FLAT or "Interface\\Buttons\\WHITE8X8"

local function GetColor(cat, key)
    if ns.GetColor then return ns.GetColor(cat, key) end
    return { r = 1, g = 1, b = 1, a = 1 }
end

local function BarTexture()
    local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
    if lsm then
        local ok, p = pcall(lsm.Fetch, lsm, "statusbar", "ZacUI Flat", true)
        if ok and p then return p end
    end
    return FLAT
end
Bar.DefaultFillTexture = BarTexture

local function SpellName(id) return id and GetSpellInfo and GetSpellInfo(id) or nil end
local function SpellIcon(id)
    if not GetSpellInfo then return nil end
    local _, _, icon = GetSpellInfo(id or 0)
    return icon
end
Bar.SpellIcon = SpellIcon

-- the Greater Blessing, when this paladin knows it (level 52 / 60 and the
-- book read); else nil and the normal one is cast instead
local function GreaterName(b)
    local e = D.BLESSINGS[b]
    if not (e and e.greater) then return nil end
    local p = BL.pallys[BL.me]
    if p and p.greaterKnown and not p.greaterKnown[b] then return nil end
    return SpellName(e.greater)
end
local function NormalName(b)
    local e = D.BLESSINGS[b]
    if e then return SpellName(e.normal) end
    if D.NORMAL_ONLY[b] then return SpellName(D.NORMAL_ONLY[b]) end
    return nil
end
Bar.GreaterName, Bar.NormalName = GreaterName, NormalName

local function ClassColor(slot)
    local cls = D.CLASSES[slot]
    if cls == "PET" then return D.PET_COLOR end
    return (RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]) or { r = 1, g = 1, b = 1 }
end

local function ClassLabel(slot)
    local cls = D.CLASSES[slot]
    if cls == "PET" then return "Pets" end
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls]) or cls
end
Bar.ClassLabel, Bar.ClassColor = ClassLabel, ClassColor

-- ============================================================
-- SETTINGS - read with today's values for anything missing
-- ============================================================
local function BarCfg()
    local c = BL.Cfg()
    return (c and c.bar) or BL.BAR_DEFAULTS or {}
end
Bar.Cfg = BarCfg

-- row height, class column, player button, gap, title strip
local function Geo(bc)
    return tonumber(bc.rowHeight) or 24, tonumber(bc.classWidth) or 140, tonumber(bc.playerWidth) or 76,
        tonumber(bc.gap) or 2, tonumber(bc.titleHeight) or 20
end
Bar.Geo = Geo

-- r, g, b, a of a colour setting, or of the fallback when it is unset
local function ColorOr(c, fr, fg, fb, fa)
    if type(c) == "table" then
        return c.r or c[1] or fr, c.g or c[2] or fg, c.b or c[3] or fb, c.a or c[4] or fa or 1
    end
    return fr, fg, fb, fa or 1
end

-- the theme colours the bar follows until one is picked
function Bar.BackgroundColor(bc)
    local t = GetColor("ui", "windowBg")
    return ColorOr(bc.bgColor, t.r, t.g, t.b, 0.75)
end
function Bar.StripColor(bc)
    local t = GetColor("ui", "windowBg")
    return ColorOr(bc.stripColor, t.r * 0.6, t.g * 0.6, t.b * 0.6, 0.9)
end
function Bar.BorderColor(bc)
    local t = GetColor("ui", "border")
    return ColorOr(bc.borderColor, t.r, t.g, t.b, 1)
end
function Bar.ButtonColor(bc)
    local t = GetColor("ui", "elementBg")
    return ColorOr(bc.buttonColor, t.r, t.g, t.b, 0.85)
end
function Bar.TitleColor(bc)
    local t = GetColor("text", "gold")
    return ColorOr(bc.titleColor, t.r, t.g, t.b, 1)
end

-- what a font field left out means: ZacUI's font (the game's while none
-- is chosen), outlined, no shadow, at the size each text always had
Bar.FONT_DEFAULTS = {
    titleFont = { fallbackFace = STANDARD_TEXT_FONT, size = 11, outline = "outline", shadow = false },
    textFont = { fallbackFace = STANDARD_TEXT_FONT, size = 10, outline = "outline", shadow = false },
    countFont = { fallbackFace = STANDARD_TEXT_FONT, size = 10, outline = "outline", shadow = false },
}
-- SetFont that says whether the face took: pcall catches a nil path, the
-- return value a font file that would not load - which leaves the string
-- with no font, so its next SetText errors ("Font not set")
local function TrySetFont(fs, path, size, flags)
    local ok, set = pcall(fs.SetFont, fs, path, size, flags)
    return (ok and set) and true or false
end
local function ApplyFont(fs, spec, dflt)
    if ns.ApplyFontSpec then
        ns.ApplyFontSpec(fs, spec, dflt)
    else
        if not TrySetFont(fs, dflt.face or dflt.fallbackFace or STANDARD_TEXT_FONT, dflt.size or 10, "OUTLINE") then
            fs:SetFont(STANDARD_TEXT_FONT, dflt.size or 10, "OUTLINE")
        end
    end
end

local function FillPath(bc)
    if bc.fillTexture and ns.ResolveBarTexture then return ns.ResolveBarTexture(bc.fillTexture) end
    return BarTexture()
end

-- ============================================================
-- FRAMES
-- ============================================================
-- a font string with its default font already on (the client refuses
-- text on a string that has no font yet); the style pass re-fonts it
local function Text(parent, justify, dflt)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ApplyFont(fs, nil, dflt or Bar.FONT_DEFAULTS.textFont)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- a 1 px border as four textures, coloured by the style pass
local function Edges(frame, layer)
    local list = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local e = frame:CreateTexture(nil, layer or "OVERLAY", nil, 7)
        e:SetTexture(FLAT)
        if side == "TOP" or side == "BOTTOM" then
            e:SetPoint(side .. "LEFT"); e:SetPoint(side .. "RIGHT"); e:SetHeight(1)
        else
            e:SetPoint("TOP" .. side); e:SetPoint("BOTTOM" .. side); e:SetWidth(1)
        end
        list[#list + 1] = e
    end
    return list
end

-- A bar: the root with its title strip, ready for Arrange. preview: no
-- global names, no secure buttons, no clicks or tooltips.
function Bar.NewView(parent, preview)
    local view = { preview = preview, classBtns = {}, playerBtns = {} }
    local root = CreateFrame("Frame", (not preview) and "ZacUIBlessingsBar" or nil, parent)
    root:SetSize(140, 20)
    root.bg = root:CreateTexture(nil, "BACKGROUND")
    root.bg:SetAllPoints()
    root.bg:SetTexture(FLAT)
    -- the title strip, a shade darker, with a border round it all
    local strip = root:CreateTexture(nil, "BORDER")
    strip:SetPoint("TOPLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", 0, 0)
    strip:SetTexture(FLAT)
    root.strip = strip
    root.edges = Edges(root)
    root.title = Text(root, "LEFT", Bar.FONT_DEFAULTS.titleFont)
    root.title:SetPoint("LEFT", strip, "LEFT", 5, 0)
    root.title:SetText("Blessings")
    root.symbols = Text(root, "RIGHT")
    root.symbols:SetPoint("RIGHT", strip, "RIGHT", -5, 0)
    root.anchorTo = function(k)
        if k == "strip" then return strip elseif k == "bar" then return root
        elseif k == "title" then return root.title elseif k == "symbols" then return root.symbols end
    end
    if preview and ns.TagElement then
        -- the pick hook: a click on the sample's title opens its spot
        ns.TagElement(root.title, "blessings.title") ns.TagElement(root.symbols, "blessings.symbols")
    end
    view.root = root
    return view
end

-- WHERE THE TEXTS AND THE ICON SIT. Each has its built-in spot (exactly
-- the SetPoint it always had); the bar's saved anchor (bar.anchors.<title|
-- symbols|name|count|icon>, ZacUI's anchor shape) goes on top: any corner
-- of the title strip, the bar, a button, its icon or the other texts.
-- Nothing saved = the old points, exactly.
Bar.ANCHOR_LABELS = { strip = "The title strip", bar = "The whole bar", title = "Title", symbols = "Symbols count",
    button = "The button", icon = "Blessing icon", name = "Name", count = "Count / time left" }
Bar.ROOT_TARGETS = { "strip", "bar", "title", "symbols" }
Bar.BUTTON_TARGETS = { "button", "icon", "name", "count" }
local function AnchorOf(bc, key)
    local a = bc and bc.anchors
    return type(a) == "table" and a[key] or nil
end
Bar.AnchorOf = AnchorOf
local function DefOf(owner, key)
    local D = owner.anchorDef
    if not D then D = {} owner.anchorDef = D end
    local t = D[key]
    if not t then t = {} D[key] = t end
    return t
end
-- what each spot is, for the page's pickers (no frame needed)
function Bar.AnchorDefaults(key, bc)
    bc = bc or BarCfg()
    if key == "title" then return { point = "LEFT", relPoint = "LEFT", x = 5, y = 0, justify = "LEFT" }
    elseif key == "symbols" then return { point = "RIGHT", relPoint = "RIGHT", x = -5, y = 0, justify = "RIGHT" }
    elseif key == "count" then return { point = "RIGHT", relPoint = "RIGHT", x = -4, y = 0, justify = "RIGHT" }
    elseif key == "icon" then return { point = "LEFT", relPoint = "LEFT", x = 2, y = 0 } end
    if bc.icons ~= false then return { point = "LEFT", relPoint = "RIGHT", x = 4, y = 0, justify = "LEFT" } end
    return { point = "LEFT", relPoint = "LEFT", x = 5, y = 0, justify = "LEFT" }
end

-- the title and the symbols count on the strip
local function PlaceRootTexts(root, bc)
    local t = DefOf(root, "title")
    t.point, t.to, t.relPoint, t.x, t.y, t.justify = "LEFT", root.strip, "LEFT", 5, 0, "LEFT"
    ns.ApplyAnchor(root.title, AnchorOf(bc, "title"), t, root.anchorTo)
    t = DefOf(root, "symbols")
    t.point, t.to, t.relPoint, t.x, t.y, t.justify = "RIGHT", root.strip, "RIGHT", -5, 0, "RIGHT"
    ns.ApplyAnchor(root.symbols, AnchorOf(bc, "symbols"), t, root.anchorTo)
end

-- one button: the class, aura or player kind. Live ones are secure (they
-- cast); a preview's are plain.
local function MakeButton(view, kind, name)
    local b
    if view.preview then
        b = CreateFrame("Button", nil, view.root)
    else
        b = CreateFrame("Button", name, view.root, "SecureActionButtonTemplate")
        -- The secure template acts only on the press that matches the "cast
        -- on key down" setting (on by default), so a button registered for
        -- the mouse-up alone never cast anything. useOnKeyDown false is the
        -- per-button override for that, and pairs with the up-click (as the
        -- spellbook rows do).
        b:SetAttribute("useOnKeyDown", false)
        b:RegisterForClicks("AnyUp")
    end
    b.kind = kind
    b.anchorTo = function(k)
        if k == "button" then return b elseif k == "icon" then return b.icon
        elseif k == "name" then return b.text elseif k == "count" then return b.right end
    end
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetTexture(FLAT)
    b.fill = b:CreateTexture(nil, "BORDER")
    b.fill:SetPoint("TOPLEFT", 1, -1)
    b.fill:SetPoint("BOTTOMLEFT", 1, 1)
    b.fill:SetWidth(1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("LEFT", 2, 0)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.right = Text(b, "RIGHT")
    b.right:SetPoint("RIGHT", -4, 0)
    b.text = Text(b, "LEFT")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture(FLAT)
    hl:SetVertexColor(1, 1, 1, 0.08)
    b.edges = Edges(b)
    -- the alert: a tint over the button that the "blessing ran out"
    -- animation plays on. A plain frame of its own, so it can animate in
    -- combat while the secure button under it cannot be touched.
    local alert = CreateFrame("Frame", nil, b)
    alert:SetAllPoints()
    alert.tex = alert:CreateTexture(nil, "OVERLAY")
    alert.tex:SetAllPoints()
    alert.tex:SetTexture(FLAT)
    alert:Hide()
    b.alert = alert
    if view.preview and ns.TagElement then
        ns.TagElement(b.text, "blessings.name") ns.TagElement(b.right, "blessings.count")
        ns.TagElement(b.icon, "blessings.icon")
    end
    if not view.preview then
        b:SetScript("OnEnter", function(self) if self.tip then self.tip(self) end end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    b:Hide()
    return b
end

local function Need(view, kind, idx)
    if kind == "aura" then
        if not view.aura then
            view.aura = MakeButton(view, "aura", "ZacUIBlessingsAura")
            if not view.preview then
                view.aura:SetAttribute("type1", "spell")
                view.aura:SetAttribute("unit1", "player")
            end
        end
        return view.aura
    elseif kind == "class" then
        local b = view.classBtns[idx]
        if not b then b = MakeButton(view, "class", "ZacUIBlessingsClass" .. idx) view.classBtns[idx] = b end
        return b
    end
    local b = view.playerBtns[idx]
    if not b then b = MakeButton(view, "player", "ZacUIBlessingsPlayer" .. idx) view.playerBtns[idx] = b end
    return b
end

-- every setting onto one button
local function StyleButton(b, bc, w)
    local rh = Geo(bc)
    b:SetSize(w, rh)
    b.bg:SetVertexColor(Bar.ButtonColor(bc))
    b.fill:SetTexture(FillPath(bc))
    local showIcon = b.kind ~= "player" and bc.icons ~= false
    b.icon:SetSize(math.max(1, rh - 4), math.max(1, rh - 4))
    b.icon:SetShown(showIcon)
    local t = DefOf(b, "icon")
    t.point, t.to, t.relPoint, t.x, t.y = "LEFT", b, "LEFT", 2, 0
    ns.ApplyAnchor(b.icon, AnchorOf(bc, "icon"), t, b.anchorTo)
    t = DefOf(b, "count")
    t.point, t.to, t.relPoint, t.x, t.y, t.justify = "RIGHT", b, "RIGHT", -4, 0, "RIGHT"
    ns.ApplyAnchor(b.right, AnchorOf(bc, "count"), t, b.anchorTo)
    t = DefOf(b, "name")
    if showIcon then
        t.point, t.to, t.relPoint, t.x, t.y = "LEFT", b.icon, "RIGHT", 4, 0
        t.x2 = -3
    else
        t.point, t.to, t.relPoint, t.x, t.y = "LEFT", b, "LEFT", 5, 0
        t.x2 = b.kind == "player" and -2 or -3
    end
    t.justify = "LEFT"
    t.point2, t.to2, t.relPoint2, t.y2 = "RIGHT", b.right, "LEFT", 0
    local _, two = ns.ApplyAnchor(b.text, AnchorOf(bc, "name"), t, b.anchorTo)
    -- one point once moved: the button's width less its edges, cut past it
    if not two then b.text:SetWidth(math.max(10, w - 8)) end
    ApplyFont(b.text, bc.textFont, Bar.FONT_DEFAULTS.textFont)
    ApplyFont(b.right, bc.countFont, Bar.FONT_DEFAULTS.countFont)
    local r, g, bl, a = ColorOr(bc.buttonBorderColor, Bar.BorderColor({}))
    for _, e in ipairs(b.edges) do e:SetVertexColor(r, g, bl, a) end
    local mr, mg, mb = ColorOr(bc.colorMissing, 1, 0.35, 0.3, 1)
    b.alert.tex:SetVertexColor(mr, mg, mb, 0.35)
end

-- the root: background, strip, border, title
local function StyleView(view, bc)
    local root = view.root
    local _, _, _, _, head = Geo(bc)
    root:SetScale(bc.scale or 1)
    root.bg:SetVertexColor(Bar.BackgroundColor(bc))
    root.strip:SetHeight(math.max(1, head - 2))
    root.strip:SetVertexColor(Bar.StripColor(bc))
    local r, g, b, a = Bar.BorderColor(bc)
    for _, e in ipairs(root.edges) do e:SetVertexColor(r, g, b, a) end
    ApplyFont(root.title, bc.titleFont, Bar.FONT_DEFAULTS.titleFont)
    root.title:SetTextColor(Bar.TitleColor(bc))
    ApplyFont(root.symbols, bc.countFont, Bar.FONT_DEFAULTS.countFont)
    PlaceRootTexts(root, bc)
    -- shadow and glow round the bar (bar.chrome; its fill and edge stay the
    -- colours above). Nothing saved = nothing made.
    if ns.ApplyChrome and (bc.chrome or root._zcShadow or root._zcGlow) then ns.ApplyChrome(root, bc.chrome) end
    if root.grip then root.grip:SetHeight(math.max(1, head - 2)) end
end

-- Lay a bar out from a plan:
--   plan.aura  { name, icon } or nil
--   plan.rows  { { slot, b, members, label, color, icon }, ... }
-- hook(kind, button, row, member, j) runs for each button placed (the
-- live bar sets its secure attributes and tooltips there); for the aura
-- it also runs with a nil row when the aura button is put away.
function Bar.Arrange(view, bc, plan, hook)
    local rh, cw, pw, gap, head = Geo(bc)
    StyleView(view, bc)
    local root = view.root
    local y = -head
    local widest = cw
    if bc.aura and plan.aura then
        local ab = Need(view, "aura")
        ab:ClearAllPoints()
        ab:SetPoint("TOPLEFT", root, "TOPLEFT", 0, y)
        StyleButton(ab, bc, cw)
        ab.icon:SetTexture(plan.aura.icon)
        ab.text:SetText(Bar.NameText(bc, plan.aura.name))
        if hook then hook("aura", ab, plan.aura) end
        ab:Show()
        y = y - rh - gap
    elseif view.aura then
        view.aura:Hide()
        if hook then hook("aura", view.aura, nil) end
    end
    local maxP = math.max(0, math.min(15, bc.maxPlayers or 8))
    local used = {}
    for r, row in ipairs(plan.rows) do
        local cb = Need(view, "class", r)
        cb:ClearAllPoints()
        cb:SetPoint("TOPLEFT", root, "TOPLEFT", 0, y)
        StyleButton(cb, bc, cw)
        cb.icon:SetTexture(row.icon)
        local col = row.color or { r = 1, g = 1, b = 1 }
        cb.text:SetText(Bar.NameText(bc, row.label))
        cb.text:SetTextColor(col.r, col.g, col.b)
        cb.row = row
        if hook then hook("class", cb, row) end
        cb:Show()
        if bc.players then
            for j, m in ipairs(row.members) do
                if j > maxP then break end
                local idx = (r - 1) * 15 + j
                local pb = Need(view, "player", idx)
                pb:ClearAllPoints()
                pb:SetPoint("TOPLEFT", root, "TOPLEFT", cw + gap + (j - 1) * (pw + gap), y)
                StyleButton(pb, bc, pw)
                pb.icon:SetTexture(nil)
                pb.text:SetText(Bar.NameText(bc, m.name))
                pb.member = m
                if hook then hook("player", pb, row, m, j) end
                pb:Show()
                used[idx] = true
                local right = cw + gap + j * (pw + gap)
                if right > widest then widest = right end
            end
        end
        y = y - rh - gap
    end
    for r = #plan.rows + 1, #view.classBtns do view.classBtns[r]:Hide() end
    for idx, pb in pairs(view.playerBtns) do if not used[idx] then pb:Hide() end end
    root:SetSize(widest, -y)
end

-- ---- painting a status -------------------------------------------------
local function Paint(b, frac, col)
    local w = math.max(1, (b:GetWidth() - 2) * math.max(0, math.min(1, frac or 0)))
    b.fill:SetWidth(w)
    b.fill:SetVertexColor(col.r or col[1] or 1, col.g or col[2] or 1, col.b or col[3] or 1, col.a or col[4] or 0.55)
end
local function Col(bc, key)
    local c = bc[key]
    if type(c) == "table" then return c end
    return (BL.BAR_DEFAULTS and BL.BAR_DEFAULTS[key]) or { r = 1, g = 1, b = 1, a = 0.55 }
end

-- the alert animation on one button (a blessing just ran out)
function Bar.Alert(b, bc)
    local spec = bc.alertAnim
    local Motion = ns.Motion
    if not (Motion and type(spec) == "table" and spec.style ~= "none" and b:IsVisible()) then return end
    local a = b.alert
    Motion.Stop(a)
    a:Show()
    Motion.Play(a, spec, "update", function() a:Hide() end)
end

-- the names on the buttons (bar.formats.name: longest, case, before /
-- after); nothing saved = the name as it is
function Bar.NameText(bc, name)
    local spec = bc and type(bc.formats) == "table" and bc.formats.name
    if not spec or not ns.FormatName then return name end
    return ns.FormatName(name, spec)
end

-- a class row: missing / total, the shortest time left
function Bar.PaintClass(cb, bc, missing, total, least)
    cb.right:SetText(missing > 0 and ("|cffe04d4d" .. missing .. "|r/" .. total) or Fmt(least, bc))
    local frac = total > 0 and ((total - missing) / total) or 0
    if missing == 0 and least then frac = math.min(1, least / D.GREATER_DURATION) end
    Paint(cb, frac, missing > 0 and Col(bc, "colorMissing") or Col(bc, "colorHave"))
    -- someone more is missing it than at the last look: the alert
    if cb.lastMissing ~= nil and missing > cb.lastMissing then
        Bar.Alert(cb, bc)
        -- and its sound (bar.sounds.expire; nothing saved = silent, as ever)
        local snd = type(bc.sounds) == "table" and bc.sounds.expire
        if snd and ns.PlaySoundSpec then ns.PlaySoundSpec(snd, nil, "blessings.expire") end
    end
    cb.lastMissing = missing
end

-- a player: dead (or gone), has it (time left), or missing (in range?)
function Bar.PaintPlayer(pb, bc, dead, left, inRange)
    if dead then
        pb.text:SetTextColor(0.5, 0.5, 0.5)
        Paint(pb, 0, Col(bc, "colorDead"))
        pb.right:SetText("")
    elseif left then
        pb.text:SetTextColor(1, 1, 1)
        local frac = (left == math.huge) and 1 or (left / D.GREATER_DURATION)
        local low = (tonumber(bc.lowAt) or 20) / 100
        Paint(pb, frac, frac < low and Col(bc, "colorLow") or Col(bc, "colorHave"))
        pb.right:SetText(Fmt(left, bc))
    else
        pb.text:SetTextColor(inRange and 1 or 0.6, inRange and 0.35 or 0.6, inRange and 0.35 or 0.6)
        Paint(pb, 0, Col(bc, "colorMissing"))
        pb.right:SetText("")
    end
end

function Bar.PaintAura(ab, bc, on)
    Paint(ab, on and 1 or 0, Col(bc, "colorAura"))
    ab.right:SetText(on and "" or "|cffe04d4doff|r")
end

function Bar.PaintSymbols(view, syms)
    view.root.symbols:SetText(syms > 0 and ("|cffffd100" .. syms .. "|r symbols") or "|cffe04d4dno symbols|r")
end

-- the bar appearing (out of combat only: it holds secure buttons)
function Bar.ShowAnimated(view, bc)
    local root = view.root
    local Motion = ns.Motion
    if Motion and type(bc.showAnim) == "table" and bc.showAnim.style ~= "none" and not InCombatLockdown() then
        Motion.Show(root, bc.showAnim)
    else
        root:Show()
    end
end

-- ============================================================
-- THE LIVE BAR
-- ============================================================
local view, root


-- SETTING ANY PALADIN'S BLESSINGS FROM THE BAR (2026-10-20): a right
-- click on the title opens a menu - each paladin in the group, then each
-- class here (and the aura), then the blessings that paladin knows, the
-- one picked ticked and who else gives it shown. A pick goes through the
-- same setters as the assignment window, so it is said on the paladin
-- channel at once and every ZacUI and PallyPower paladin sees it. Others'
-- blessings can be changed as leader or assistant, or when they allow it
-- (PallyPower's free assignment); otherwise their entries are read-only.
local function AssignMenu(anchor)
    local G = BL.Grid
    if not (UI and UI.ContextMenu) then
        if G then G.Toggle() end
        return
    end
    local function BName(b) return NormalName(b) end
    local items = { { text = "Who gives what", isTitle = true } }
    for _, name in ipairs(BL.PallyNames()) do
        local may = BL.CanControl(name)
        local p = BL.Pally(name)
        local kids = {}
        if not may then
            kids[#kids + 1] = { text = "Only " .. name .. ", the leader or an assistant can change these", disabled = true }
        end
        -- every class at once
        local all = {}
        for b = 1, D.NUM_BLESSINGS do
            if BL.Knows(name, b) and BName(b) then
                local bb = b
                all[#all + 1] = { text = BName(b), func = function() BL.SetAllClasses(name, bb) end }
            end
        end
        all[#all + 1] = { text = "Nothing", func = function() BL.SetAllClasses(name, 0) end }
        if may then kids[#kids + 1] = { text = "Every class", children = all } end
        for slot = 1, D.NUM_CLASSES do
            local n = BL.bySlot[slot] and #BL.bySlot[slot] or 0
            if n > 0 then
                local cur = p.assign[slot] or 0
                local s = slot
                local opts = { { text = "Nothing", checked = cur == 0, func = function() BL.SetAssign(name, s, 0) end } }
                for b = 1, D.NUM_BLESSINGS do
                    if BL.Knows(name, b) and BName(b) then
                        local bb = b
                        local who = BL.WhoGives(slot, b, name)
                        opts[#opts + 1] = { text = BName(b) .. (who and ("  |cff8c8c8c(" .. who .. ")|r") or ""),
                            checked = cur == b, func = function() BL.SetAssign(name, s, bb) end }
                    end
                end
                local col = ClassColor(slot)
                local label = string.format("|cff%02x%02x%02x%s|r  %s", (col.r or 1) * 255, (col.g or 1) * 255,
                    (col.b or 1) * 255, ClassLabel(slot), cur > 0 and (BName(cur) or "?") or "-")
                kids[#kids + 1] = { text = label, children = may and opts or nil, disabled = not may or nil }
            end
        end
        local acur = p.aura or 0
        local aopts = { { text = "Nothing", checked = acur == 0, func = function() BL.SetAura(name, 0) end } }
        for a = 1, D.NUM_AURAS do
            local e = D.AURAS[a]
            local an = e and GetSpellInfo(e.id)
            if an and BL.KnowsAura(name, a) then
                local aa = a
                aopts[#aopts + 1] = { text = an, checked = acur == a, func = function() BL.SetAura(name, aa) end }
            end
        end
        local acurName = acur > 0 and D.AURAS[acur] and GetSpellInfo(D.AURAS[acur].id) or "-"
        kids[#kids + 1] = { text = "Aura  " .. acurName, children = may and aopts or nil, disabled = not may or nil }
        items[#items + 1] = { text = name .. (BL.IsLeader(name) and "  |cff8c8c8c(lead)|r" or ""), children = kids }
    end
    if #items == 1 then items[#items + 1] = { text = "No paladins in the group yet", disabled = true } end
    if G then items[#items + 1] = { text = "The full assignment window", func = function() G.Open() end } end
    items[#items + 1] = { text = "Ask everyone again", func = function() BL.Comm.Request() BL.ScanRoster() end }
    UI.ContextMenu(items, { anchor = anchor })
end
Bar.AssignMenu = AssignMenu

local function Build()
    if root then return end
    view = Bar.NewView(UIParent, false)
    root = view.root
    root:SetPoint("LEFT", UIParent, "LEFT", 40, 120)
    root:SetClampedToScreen(true)
    -- the title strip: click opens the assignment window, drag moves the
    -- bar (out of combat only - it carries secure buttons). Its own drag,
    -- not ZacUI's movers: those skip frames that read as protected, and a
    -- frame holding secure buttons may.
    root:SetMovable(true)
    local grip = CreateFrame("Button", nil, root)
    grip:SetPoint("TOPLEFT", 0, 0)
    grip:SetPoint("TOPRIGHT", 0, 0)
    grip:SetHeight(18)
    grip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnClick", function(self, button)
        if button == "RightButton" then AssignMenu(self) return end
        if BL.Grid then BL.Grid.Toggle() end
    end)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Blessings")
        GameTooltip:AddLine("Right click: set any paladin's blessings and aura", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Left click: the assignment window   Drag: move", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    grip:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        root:StartMoving()
    end)
    grip:SetScript("OnDragStop", function()
        root:StopMovingOrSizing()
        local point, _, _, x, y = root:GetPoint(1)
        local c = BL.Cfg()
        if c then c.barPos = { point or "CENTER", x or 0, y or 0 } end
    end)
    root.grip = grip
    -- in ZacUI's mover mode too (Movers page, Edit Mode), with its spot
    -- kept where the grip keeps it (bar.barPos); a box that locks in a
    -- fight, since the bar carries the casting buttons
    if ns.RegisterMover then
        ns.RegisterMover("blessingsBar", "Blessings bar", function() return root end, "LEFT", 40, 120, nil, {
            get = function()
                local c = BL.Cfg()
                local p = c and c.barPos
                if type(p) == "table" then return p[1] or "CENTER", p[2] or 0, p[3] or 0 end
            end,
            set = function(point, x, y)
                local c = BL.Cfg()
                if c then c.barPos = point and { point, x or 0, y or 0 } or nil end
            end,
            reset = function() Bar.Place() end,
            secure = true, own = true,
        })
    end
    Need(view, "aura")
    root:Hide()
    Bar.Place()
    -- when the bar shows (bar.visibility, ZacUI's visibility shape: in
    -- combat, in a raid, opacity, mouseover...). Alpha only - the bar holds
    -- the casting buttons, and alpha is the one thing safe in a fight.
    -- Nothing saved = never touched, as before.
    if ns.Visibility and ns.Visibility.Register then
        ns.Visibility.Register(root, function() return BarCfg().visibility end, { control = "alpha" })
    end
end

-- the saved spot (or the first one)
function Bar.Place()
    if not root or InCombatLockdown() then return end
    local c = BL.Cfg()
    root:ClearAllPoints()
    if c and type(c.barPos) == "table" then
        root:SetPoint(c.barPos[1] or "CENTER", UIParent, c.barPos[1] or "CENTER", c.barPos[2] or 0, c.barPos[3] or 0)
    else
        root:SetPoint("LEFT", UIParent, "LEFT", 40, 120)
    end
end

-- ============================================================
-- WHAT EACH ROW SHOWS
-- ============================================================
-- the rows this paladin casts: { slot, b (class blessing), members }
local rows = {}

-- my blessing for one player: their per-player one, else the class one
local function BlessingFor(p, slot, name)
    local over = p.normal[slot] and p.normal[slot][name]
    if over and over > 0 then return over, true end
    return p.assign[slot] or 0, false
end

local function Wanted()
    local out = {}
    local p = BL.pallys[BL.me]
    if not p then return out end
    for slot = 1, D.NUM_CLASSES do
        local members = BL.bySlot[slot]
        local b = p.assign[slot] or 0
        local anyOver = p.normal[slot] and next(p.normal[slot]) ~= nil
        if members and #members > 0 and (b > 0 or anyOver) then
            out[#out + 1] = { slot = slot, b = b, members = members }
        end
    end
    return out
end

local layoutPending = false
local function Shown()
    local c = BL.Cfg()
    if not (c and c.enabled and c.bar.enabled and BL.isPaladin and BL.Running()) then return false end
    local inGroup = (GetNumGroupMembers and GetNumGroupMembers() or 0) > 0
    return inGroup or c.bar.solo
end

-- the live bar's secure side of each button: what it casts on whom, and
-- its tooltip
local function SecureHook(kind, btn, row, m, j)
    if kind == "aura" then
        if not row then btn.auraName = nil return end
        local auraName = row.name
        btn:SetAttribute("spell1", auraName)
        btn.auraName = auraName
        btn.tip = function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(auraName)
            GameTooltip:AddLine("Click: put it up", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end
    elseif kind == "class" then
        local gname, nname = GreaterName(row.b), NormalName(row.b)
        local first = row.members[1]
        btn:SetAttribute("type1", "spell")
        btn:SetAttribute("spell1", gname or nname)
        btn:SetAttribute("unit1", first and first.unit or nil)
        btn:SetAttribute("type2", "spell")
        btn:SetAttribute("spell2", nname)
        btn:SetAttribute("unit2", first and first.unit or nil)
        btn.tip = function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(ClassLabel(row.slot) .. ": " .. (gname or nname or "-"))
            GameTooltip:AddLine("Left click: " .. (gname or nname or "-") .. " on the class", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Right click: " .. (nname or "-") .. " on the first who needs it", 0.8, 0.8, 0.8)
            for _, mm in ipairs(row.members) do
                -- the 1 s status pass stores numbers and flags; the words
                -- are only put together here, when someone is looking
                local st = self.status and self.status[mm.name]
                local s
                if st then
                    if st.dead then s = "dead / offline"
                    elseif st.left then s = "has it " .. Fmt(st.left)
                    else s = "MISSING" end
                    if st.far then s = s .. " (out of range)" end
                end
                GameTooltip:AddLine(mm.name .. (s and ("  " .. s) or ""), 1, 1, 1)
            end
            GameTooltip:Show()
        end
    else
        local p = BL.Pally(BL.me)
        local b, over = BlessingFor(p, row.slot, m.name)
        btn:SetAttribute("type1", "spell")
        btn:SetAttribute("spell1", over and NormalName(b) or (GreaterName(b) or NormalName(b)))
        btn:SetAttribute("unit1", m.unit)
        btn:SetAttribute("type2", "spell")
        btn:SetAttribute("spell2", NormalName(b))
        btn:SetAttribute("unit2", m.unit)
        btn.blessing, btn.over = b, over
        btn.tip = function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(m.name)
            if over then
                GameTooltip:AddLine("Their own blessing: " .. (NormalName(b) or "-"), 1, 0.82, 0)
            end
            GameTooltip:AddLine("Left click: " .. (self:GetAttribute("spell1") or "-"), 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Right click: " .. (NormalName(b) or "-"), 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end
    end
end

function Bar.Layout()
    if not BL.isPaladin then return end
    -- nothing secure may be made or changed in combat (a reload mid-fight
    -- builds the bar when the fight ends)
    if InCombatLockdown() then layoutPending = true return end
    Build()
    layoutPending = false
    local c = BL.Cfg()
    if not Shown() then root:Hide() return end
    local p = BL.Pally(BL.me)
    rows = Wanted()
    local plan = { rows = rows }
    local aura = p.aura or 0
    local auraName = aura > 0 and D.AURAS[aura] and SpellName(D.AURAS[aura].id)
    if auraName then plan.aura = { name = auraName, icon = SpellIcon(D.AURAS[aura].id) } end
    for _, row in ipairs(rows) do
        row.label = ClassLabel(row.slot)
        row.color = ClassColor(row.slot)
        local e = D.BLESSINGS[row.b]
        row.icon = SpellIcon((e and (e.greater or e.normal)) or 0)
    end
    Bar.Arrange(view, c.bar, plan, SecureHook)
    if not root:IsShown() then Bar.ShowAnimated(view, c.bar) end
    Bar.Status()
end

-- ============================================================
-- STATUS - who has it, how long, in range (1 s, while shown)
-- ============================================================
local nameSets = {}   -- blessing id -> { [buff name] = true }, reused each pass
local function BuffLeft(unit, names)
    for i = 1, 40 do
        local name, _, _, _, duration, expires = UnitBuff(unit, i)
        if not name then return nil end
        if names[name] then
            if expires and expires > 0 then return expires - GetTime() end
            return math.huge
        end
    end
    return nil
end

-- time left: "13m" / "45s" - or the bar's own time format (bar.formats.
-- time, ZacUI's text format shape) once one is saved
Fmt = function(t, bc)
    if not t or t == math.huge then return "" end
    local spec = bc and type(bc.formats) == "table" and bc.formats.time
    if spec and ns.FormatTime then return ns.FormatTime(t, spec, Bar.TIME_FORMAT_DEFAULTS) end
    if t >= 60 then return math.floor(t / 60 + 0.5) .. "m" end
    return math.floor(t) .. "s"
end
-- what the format picker starts from: today's "13m / 45s"
Bar.TIME_FORMAT_DEFAULTS = { time = "short" }
Bar.FormatLeft = function(t, bc) return Fmt(t, bc) end


function Bar.Status()
    if not (root and root:IsShown()) then return end
    local p = BL.pallys[BL.me]
    if not p then return end
    local bc = BarCfg()
    Bar.PaintSymbols(view, p.symbols or 0)
    local auraBtn = view.aura
    if auraBtn and auraBtn:IsShown() and auraBtn.auraName then
        Bar.PaintAura(auraBtn, bc, ns.PlayerAuras.BuffNamed(auraBtn.auraName) ~= nil)
    end
    for r, row in ipairs(rows) do
        local cb = view.classBtns[r]
        if cb and cb:IsShown() then
            local missing, total, least = 0, 0, nil
            local needUnit, nearUnit
            -- per-member status tables are kept and refilled (this runs
            -- every second for every blessed raider); the blessing-name
            -- set is built once per blessing, not once per member
            local status = cb.status
            if not status then status = {} cb.status = status end
            local lastB, names, g, n
            for j, m in ipairs(row.members) do
                local b = BlessingFor(p, row.slot, m.name)
                if b ~= lastB or not names then
                    lastB = b
                    names = nameSets[b]
                    if not names then names = {} nameSets[b] = names end
                    g, n = GreaterName(b), NormalName(b)
                    for k in pairs(names) do names[k] = nil end
                    if g then names[g] = true end
                    if n then names[n] = true end
                end
                -- in combat the roster may have shuffled under the
                -- buttons (they follow when it ends): a token that no
                -- longer holds this player shows grey
                local moved = UnitName(m.unit) ~= m.name
                local dead = moved or UnitIsDeadOrGhost(m.unit) or not UnitIsConnected(m.unit)
                local left = (not dead) and BuffLeft(m.unit, names) or nil
                local inRange = true
                if n and IsSpellInRange then inRange = IsSpellInRange(n, m.unit) == 1 end
                total = total + 1
                if not left and not dead then
                    missing = missing + 1
                    if inRange and not needUnit then needUnit = m.unit end
                end
                if inRange and not dead and not nearUnit then nearUnit = m.unit end
                if left and left ~= math.huge and (not least or left < least) then least = left end
                local st = status[m.name]
                if not st then st = {} status[m.name] = st end
                st.dead, st.left, st.far = dead and true or false, left, (not inRange and not dead) and true or false
                local pb = view.playerBtns[(r - 1) * 15 + j]
                if pb and pb:IsShown() and pb.member == m then
                    Bar.PaintPlayer(pb, bc, dead, left, inRange)
                end
            end
            -- out of combat the buttons follow the group: the Greater
            -- Blessing on someone in range, the normal one on the first
            -- in range who lacks it
            if not InCombatLockdown() then
                local u1 = needUnit or nearUnit
                local u2 = needUnit or nearUnit
                if u1 and cb:GetAttribute("unit1") ~= u1 then cb:SetAttribute("unit1", u1) end
                if u2 and cb:GetAttribute("unit2") ~= u2 then cb:SetAttribute("unit2", u2) end
            end
            Bar.PaintClass(cb, bc, missing, total, least)
        end
    end
end

-- ============================================================
-- DRIVING IT
-- ============================================================
local ticker
local function Tick()
    if not (root and root:IsShown()) then
        if ticker then ticker:Cancel(); ticker = nil end
        return
    end
    Bar.Status()
end

local function Refresh()
    Bar.Layout()
    if root and ns.Visibility and ns.Visibility.Refresh then ns.Visibility.Refresh(root) end
    if root and root:IsShown() and not ticker then
        ticker = C_Timer.NewTicker(1.0, Tick)
        if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(ticker, "blessings.bar") end
    end
end
Bar.Refresh = Refresh

BL.OnChange("bar", Refresh)

-- the Blessings settings page: its changes reach the live bar on the
-- next frame (out of combat; in a fight they wait for it to end)
if ns.OnSettingsChanged and ns.Coalesce then
    local soon = ns.Coalesce(function() if root then Refresh() end end)
    ns.OnSettingsChanged(function()
        local P = ns.ConfigPreview
        if BL.isPaladin and P and P.Current and P.Current() == "blessings.bar" then soon() end
    end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function()
    if layoutPending then Refresh() end
end)
