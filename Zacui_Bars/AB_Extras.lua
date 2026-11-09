-- AB_Extras - the pet bar, the stance bar, the bag strip, the micro menu
-- and the XP / reputation strip, each on its own ZacUI header.
-- Part of ZacUI; load order is set by the TOC.
--
-- Pet and stance buttons are built from Blizzard's templates
-- (PetActionButtonTemplate, StanceButtonTemplate) so the secure click is
-- the client's; their event wiring is dropped and the display is driven
-- from the header's events instead, which keeps them independent of the
-- stock bars this system hides. Bag slots and micro buttons are
-- Blizzard's existing buttons, moved onto a ZacUI header and laid out
-- again whenever the client re-lays them.

local ADDON_NAME = ...
-- Zacui_Bars is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local AB = ns.Bars
local Print = ns.Print
local SkinSecureIcon = ns.SkinSecureIcon
local ZUI = ns.ZUI

local function CooldownSet(cd, start, duration, enable)
    if not cd then return end
    if CooldownFrame_Set then CooldownFrame_Set(cd, start, duration, enable)
    elseif cd.SetCooldown then
        if enable and enable ~= 0 and start and duration and duration > 0 then cd:SetCooldown(start, duration)
        else cd:Clear() end
    end
end

local function Hotkey(fs, key, hidden)
    if not fs then return end
    if key and not hidden then
        fs:SetText(AB.ShortKey(key))
        fs:Show()
        fs:SetAlpha(1)
    else
        fs:SetText("")
        fs:SetAlpha(0)
    end
end

-- Keys on a Blizzard binding name are taken onto our button by override.
local function OverrideKeys(header, blizzName, buttonName)
    for k = 1, select("#", GetBindingKey(blizzName)) do
        local key = select(k, GetBindingKey(blizzName))
        if key then SetOverrideBindingClick(header, false, key, buttonName, "LeftButton") end
    end
end

local function SmallBarCommon(header, cfg, buttons, size, count, initial)
    header.cfg = cfg
    if not cfg.enabled then
        UnregisterStateDriver(header, "visibility")
        header:Hide()
        AB.RegisterFade(header, { fade = false, alpha = 1 })
        return false
    end
    AB.Place(header, cfg, initial)
    AB.LayoutButtons(header, buttons, cfg, size, count)
    for _, b in ipairs(buttons) do b:EnableMouse(not cfg.clickthrough) end
    -- pet and stance buttons wear the bar's button look (bag slots and
    -- micro buttons are the client's own art and keep it)
    if header.styled then
        for _, b in ipairs(buttons) do AB.StyleButton(b, cfg) end
    end
    header:SetAlpha(cfg.alpha or 1)
    header:Show()
    UnregisterStateDriver(header, "visibility")
    RegisterStateDriver(header, "visibility", AB.VisibilityDriver(cfg))
    AB.RegisterFade(header, cfg)
    AB.MoverFor(header, cfg, function() if ns.RefreshConfig then ns.RefreshConfig() end end)
    return true
end

-- ============================================================
-- PET BAR
-- ============================================================
local pet
local function PetUpdate()
    if not (pet and pet:IsShown()) then return end
    local usable = GetPetActionsUsable and GetPetActionsUsable()
    local cfg = pet.cfg or {}
    for i, btn in ipairs(pet.buttons) do
        local name, texture, isToken, isActive, autoCastAllowed, autoCastEnabled = GetPetActionInfo(i)
        local icon = AB.Region(btn, "icon", "Icon")
        if name then
            if isToken and texture then texture = _G[texture] or texture end
            if icon then icon:SetTexture(texture) icon:Show() end
            btn:SetChecked(isActive and true or false)
            if icon then
                if usable == false then icon:SetVertexColor(AB.UnusableTint()) else icon:SetVertexColor(1, 1, 1) end
            end
            local castable = AB.Region(btn, "AutoCastable", "AutoCastable")
            if castable then castable:SetShown(autoCastAllowed and true or false) end
            local shine = AB.Region(btn, "AutoCastShine", "Shine")
            if shine and AutoCastShine_AutoCastStart and AutoCastShine_AutoCastStop then
                if autoCastEnabled then AutoCastShine_AutoCastStart(shine) else AutoCastShine_AutoCastStop(shine) end
            elseif btn.AutoCastOverlay and btn.AutoCastOverlay.ShowAutoCastEnabled then
                pcall(btn.AutoCastOverlay.ShowAutoCastEnabled, btn.AutoCastOverlay, autoCastEnabled and true or false)
            end
            btn:SetAlpha(1)
        else
            if icon then icon:SetTexture(nil) end
            btn:SetChecked(false)
            local castable = AB.Region(btn, "AutoCastable", "AutoCastable")
            if castable then castable:Hide() end
            btn:SetAlpha(cfg.showgrid and 1 or 0)
        end
        local start, duration, enable = GetPetActionCooldown(i)
        CooldownSet(AB.Region(btn, "cooldown", "Cooldown"), start, duration, enable)
        Hotkey(btn.zHotkey, GetBindingKey("BONUSACTIONBUTTON" .. i), cfg.hideHotkey and not AB.keyMode)
    end
end

local function PetCooldowns()
    if not (pet and pet:IsShown()) then return end
    for i, btn in ipairs(pet.buttons) do
        local start, duration, enable = GetPetActionCooldown(i)
        CooldownSet(AB.Region(btn, "cooldown", "Cooldown"), start, duration, enable)
    end
end

local function CreatePetBar()
    pet = AB.NewHeader("pet", "ZacUIPetBar", "Pet bar")
    pet.buttons = {}
    pet.styled = true
    for i = 1, 10 do
        local name = "ZacUIPetButton" .. i
        local btn = CreateFrame("CheckButton", name, pet, "PetActionButtonTemplate")
        btn:SetID(i)
        btn:UnregisterAllEvents()
        btn:SetScript("OnEvent", nil)
        btn:SetAttribute("type", "pet")
        btn:SetAttribute("action", i)
        btn.commandName = "BONUSACTIONBUTTON" .. i      -- Quick Keybind Mode binds this
        btn.zHotkey = AB.Region(btn, "HotKey", "HotKey")
        if AB.KitCapture then AB.KitCapture(btn) end      -- (a game look's kit: AB_Core)
        SkinSecureIcon(btn)
        local cd = AB.Region(btn, "cooldown", "Cooldown")
        if cd and cd.SetDrawEdge then cd:SetDrawEdge(false) end
        pet.buttons[i] = btn
    end
    pet:RegisterEvent("PET_BAR_UPDATE")
    pet:RegisterEvent("PET_BAR_UPDATE_COOLDOWN")
    pet:RegisterEvent("PET_BAR_UPDATE_USABLE")
    pet:RegisterEvent("PLAYER_CONTROL_LOST")
    pet:RegisterEvent("PLAYER_CONTROL_GAINED")
    pet:RegisterEvent("PLAYER_FARSIGHT_FOCUS_CHANGED")
    pet:RegisterEvent("PLAYER_ENTERING_WORLD")
    pet:RegisterEvent("UNIT_PET")
    -- only the pet's own: unfiltered, every raider's aura change walked
    -- in here just to be thrown away
    pet:RegisterUnitEvent("UNIT_FLAGS", "pet")
    pet:RegisterUnitEvent("UNIT_AURA", "pet")
    pet:RegisterEvent("PET_UI_UPDATE")
    pet:RegisterEvent("UPDATE_BINDINGS")
    -- UNIT_AURA / UNIT_FLAGS / cooldowns fire often in a fight: coalesced
    -- onto a short timer rather than redrawn per event
    pet:SetScript("OnEvent", function(self, event, unit)
        if event == "PET_BAR_UPDATE_COOLDOWN" then
            if self._cdQueued then return end
            self._cdQueued = true
            C_Timer.After(0.1, function() self._cdQueued = nil PetCooldowns() end)
            return
        end
        if (event == "UNIT_AURA" or event == "UNIT_FLAGS") and unit ~= "pet" then return end
        if event == "UNIT_PET" and unit ~= "player" then return end
        if self._upQueued then return end
        self._upQueued = true
        C_Timer.After(0.1, function() self._upQueued = nil PetUpdate() end)
    end)
    return pet
end

local function ApplyPet(profile)
    local cfg = profile.pet
    local header = pet or CreatePetBar()
    ClearOverrideBindings(header)
    if SmallBarCommon(header, cfg, header.buttons, cfg.buttonSize or AB.PET_BUTTON, 10, cfg.initial) then
        for i = 1, 10 do OverrideKeys(header, "BONUSACTIONBUTTON" .. i, "ZacUIPetButton" .. i) end
        PetUpdate()
    end
end
AB.RegisterApplier(ApplyPet)

-- ============================================================
-- STANCE BAR
-- ============================================================
local stance
local function StanceUpdate()
    if not stance then return end
    local num = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
    local cfg = stance.cfg or {}
    for i, btn in ipairs(stance.buttons) do
        if i <= num then
            local texture, isActive, isCastable = GetShapeshiftFormInfo(i)
            local icon = AB.Region(btn, "icon", "Icon")
            if icon then
                icon:SetTexture(texture)
                if isCastable then icon:SetVertexColor(1, 1, 1) else icon:SetVertexColor(AB.UnusableTint()) end
            end
            btn:SetChecked(isActive and true or false)
            local start, duration, enable = GetShapeshiftFormCooldown(i)
            CooldownSet(AB.Region(btn, "cooldown", "Cooldown"), start, duration, enable)
            Hotkey(btn.zHotkey, GetBindingKey("SHAPESHIFTBUTTON" .. i), cfg.hideHotkey and not AB.keyMode)
        end
    end
end

local function CreateStanceBar()
    stance = AB.NewHeader("stance", "ZacUIStanceBar", "Stance bar")
    stance.buttons = {}
    stance.styled = true
    for i = 1, 10 do
        local name = "ZacUIStanceButton" .. i
        local btn = CreateFrame("CheckButton", name, stance, "StanceButtonTemplate")
        btn:SetID(i)
        btn:UnregisterAllEvents()
        btn:SetScript("OnEvent", nil)
        btn.commandName = "SHAPESHIFTBUTTON" .. i       -- Quick Keybind Mode binds this
        btn.zHotkey = AB.Region(btn, "HotKey", "HotKey")
        if AB.KitCapture then AB.KitCapture(btn) end      -- (a game look's kit: AB_Core)
        SkinSecureIcon(btn)
        local cd = AB.Region(btn, "cooldown", "Cooldown")
        if cd and cd.SetDrawEdge then cd:SetDrawEdge(false) end
        stance.buttons[i] = btn
    end
    stance:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
    stance:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    stance:RegisterEvent("UPDATE_SHAPESHIFT_USABLE")
    stance:RegisterEvent("UPDATE_SHAPESHIFT_COOLDOWN")
    stance:RegisterEvent("PLAYER_ENTERING_WORLD")
    stance:RegisterEvent("UPDATE_BINDINGS")
    stance:SetScript("OnEvent", function(self, event)
        if event == "UPDATE_SHAPESHIFT_FORMS" or event == "PLAYER_ENTERING_WORLD" then
            -- the number of forms changed (a trainer, a talent): relayout.
            -- A loading screen re-applies everything (it also re-takes the
            -- pet and stance keys after a rebind, and the loading screen
            -- hides the cost); UPDATE_SHAPESHIFT_FORMS can also fire on a
            -- plain stance swap, so it re-applies only when the count moved.
            local num = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
            if (event == "PLAYER_ENTERING_WORLD" or num ~= stance.appliedForms)
               and not InCombatLockdown() then
                AB.ApplyAll()
            else
                StanceUpdate()
            end
            return
        end
        if self._upQueued then return end
        self._upQueued = true
        C_Timer.After(0.05, function() self._upQueued = nil StanceUpdate() end)
    end)
    return stance
end

local function ApplyStance(profile)
    local cfg = profile.stance
    local header = stance or CreateStanceBar()
    ClearOverrideBindings(header)
    local num = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
    header.appliedForms = num          -- what the layout was built for
    if num == 0 then
        -- nothing to show on this class (yet): the bar stands down
        UnregisterStateDriver(header, "visibility")
        header:Hide()
        AB.RegisterFade(header, { fade = false, alpha = 1 })
        header.cfg = cfg
        return
    end
    if SmallBarCommon(header, cfg, header.buttons, cfg.buttonSize or AB.PET_BUTTON, num, cfg.initial) then
        for i = 1, num do OverrideKeys(header, "SHAPESHIFTBUTTON" .. i, "ZacUIStanceButton" .. i) end
        StanceUpdate()
    end
end
AB.RegisterApplier(ApplyStance)

-- THE PET AND STANCE KEYS, taken again whenever the keys change (AB.
-- ReassignBindings runs this after UPDATE_BINDINGS, out of combat - it
-- queues itself for after the fight). Before, they were only taken when
-- the bars were applied, so a key moved off a pet or stance button kept
-- firing that button, over whatever it had been bound to, until the next
-- loading screen. Same keys, same buttons as ApplyPet / ApplyStance.
function AB.RebindSmallBars()
    if InCombatLockdown() then return end
    if pet then
        ClearOverrideBindings(pet)
        if pet.cfg and pet.cfg.enabled then
            for i = 1, 10 do OverrideKeys(pet, "BONUSACTIONBUTTON" .. i, "ZacUIPetButton" .. i) end
        end
    end
    if stance then
        ClearOverrideBindings(stance)
        local num = stance.appliedForms or 0
        if stance.cfg and stance.cfg.enabled and num > 0 then
            for i = 1, num do OverrideKeys(stance, "SHAPESHIFTBUTTON" .. i, "ZacUIStanceButton" .. i) end
        end
    end
end

-- ============================================================
-- BAG BAR
-- ============================================================
local bagbar
local function BagButtons(cfg)
    local list = {}
    if cfg.onebag then
        if MainMenuBarBackpackButton then list[1] = MainMenuBarBackpackButton end
        return list
    end
    if cfg.keyring and KeyRingButton then list[#list + 1] = KeyRingButton end
    for _, name in ipairs({ "CharacterBag3Slot", "CharacterBag2Slot", "CharacterBag1Slot",
                            "CharacterBag0Slot", "MainMenuBarBackpackButton" }) do
        if _G[name] then list[#list + 1] = _G[name] end
    end
    return list
end

-- the client's own bag buttons and micro menu, read just before ZacUI
-- puts Blizzard's bars away (AB.HideBlizzard): the spots a never-placed
-- bag bar / micro menu takes (AB.SeatFromStock)
function AB.CaptureStockSpots()
    AB._stock = AB._stock or {}
    local p = AB.Profile and AB.Profile()
    local bags = BagButtons((p and p.bagbar) or {})
    local l, b, r, t = AB.StockRect(bags)
    if l then AB._stock.bagbar = { l, b, r, t } end
    local list = {}
    for _, name in ipairs(AB.MICRO_BUTTONS or {}) do if _G[name] then list[#list + 1] = _G[name] end end
    l, b, r, t = AB.StockRect(list)
    if l then AB._stock.micro = { l, b, r, t } end
end

local function ApplyBagBar(profile)
    local cfg = profile.bagbar
    if not bagbar then
        bagbar = AB.NewHeader("bagbar", "ZacUIBagBar", "Bag bar")
        bagbar.buttons = {}
        if KeyRingButton then KeyRingButton:SetScript("OnShow", nil) end
        if BagsBar and BagsBar.Layout then
            hooksecurefunc(BagsBar, "Layout", function()
                if bagbar.cfg and bagbar.cfg.enabled and not InCombatLockdown() then
                    AB.LayoutButtons(bagbar, bagbar.buttons, bagbar.cfg, 37, #bagbar.buttons)
                end
            end)
        end
    end
    -- hand back anything held that this layout no longer uses, to where
    -- the client had it (parent and anchors remembered on first takeover)
    local keep = {}
    if cfg.enabled then for _, b in ipairs(BagButtons(cfg)) do keep[b] = true end end
    for _, b in ipairs(bagbar.buttons) do
        if not keep[b] and b.zHome then
            b:SetParent(b.zHome.parent)
            b:ClearAllPoints()
            for _, pt in ipairs(b.zHome.points) do b:SetPoint(unpack(pt)) end
            if b.zHome.w then b:SetSize(b.zHome.w, b.zHome.h) end
        end
    end
    bagbar.buttons = {}
    if not cfg.enabled then
        SmallBarCommon(bagbar, cfg, bagbar.buttons, 37, 0, cfg.initial)
        return
    end
    -- a bar never placed (a fresh install): where the client's own bag
    -- buttons sit now, before they are taken (AB.SeatFromStock)
    if cfg.point == nil and AB.SeatFromStock then
        AB.SeatFromStock(cfg, BagButtons(cfg), 37, "bagbar")
    end
    for i, b in ipairs(BagButtons(cfg)) do
        if not b.zHome then
            local pts = {}
            for k = 1, b:GetNumPoints() do pts[k] = { b:GetPoint(k) } end
            b.zHome = { parent = b:GetParent(), points = pts, w = b:GetWidth(), h = b:GetHeight() }
        end
        b:SetParent(bagbar)
        b:SetFrameLevel(bagbar:GetFrameLevel() + 1)
        b:Show()
        bagbar.buttons[i] = b
        -- keepNormal: on a bag slot the NormalTexture IS the bag art
        SkinSecureIcon(b, { keepNormal = true })
    end
    SmallBarCommon(bagbar, cfg, bagbar.buttons, 37, #bagbar.buttons, cfg.initial)
    if KeyRingButton and cfg.keyring and not cfg.onebag then
        local kb = KeyRingButton
        if AB.Kit and AB.Kit() == "zacui" then
            -- (2026-11-08, Zac: "key ring in tbc is still wrong ... icon looks
            -- bad") ZacUI's look: a square slot like the bags beside it,
            -- wearing the key ring's own bag icon, cropped like every icon
            local first = bagbar.buttons[1] ~= kb and bagbar.buttons[1] or bagbar.buttons[2]
            local s = first and first.GetHeight and first:GetHeight() or 37
            if type(s) ~= "number" or s <= 0 then s = 37 end
            kb:SetSize(s, s)
            for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture" }) do
                local t = kb[get] and kb[get](kb)
                if t and t.SetTexture then
                    t:SetTexture("Interface\\ContainerFrame\\KeyRing-Bag-Icon")
                    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    t:ClearAllPoints()
                    t:SetPoint("TOPLEFT", kb, "TOPLEFT", 1, -1)
                    t:SetPoint("BOTTOMRIGHT", kb, "BOTTOMRIGHT", -1, 1)
                    t:SetAlpha(1)
                    if t.SetVertexColor then
                        if get == "GetPushedTexture" then t:SetVertexColor(0.75, 0.75, 0.75, 1) else t:SetVertexColor(1, 1, 1, 1) end
                    end
                end
            end
        else
            kb:SetSize(18, 37)
        end
    end
    -- a game look: each bag slot at the client's own size (the backpack
    -- bigger than the bag slots, the slot art never stretched); the row
    -- stays centred on its line (LayoutButtons chains side middles)
    if AB.Kit and AB.Kit() ~= "zacui" then
        for _, b in ipairs(bagbar.buttons) do
            local hm = b.zHome
            if hm and hm.w and hm.w > 0 and hm.h and hm.h > 0 and b ~= KeyRingButton then b:SetSize(hm.w, hm.h) end
            if AB.Kit() == "classic" and AB.Modern2004() then AB.ClassicBagSlot(b) end
        end
    end
end
AB.RegisterApplier(ApplyBagBar)

-- ============================================================
-- CLASSIC WOW UI ON A MODERN CLIENT: THE 2004 BAG SLOTS AND MICRO MENU
-- ============================================================
-- Era and TBC draw these in the 2004 art themselves. Forever and Retail
-- draw their bronze bag borders and micro buttons (Zac 2026-11-08: "they
-- still have Forever's gold/bronze borders"), so under Classic WoW UI on
-- those clients:
--   bag slots   the vanilla bag slot: the Quickslot ring (64 on a 37
--               slot, one down) as the slot's frame, the square hilight,
--               the checked hilight while its bag is open
--   micro menu  each button's vanilla file (UI-MicroButton-<name>-Up /
--               -Down, the 32 x 40 button in the lower 40 rows of its
--               32 x 64 sheet; the shared hilight), the character
--               button's portrait in the vanilla face window (18 x 25,
--               4 under the top, texcoords 0.2-0.8 / 0.0666-0.9); a
--               button with no vanilla file (professions, the store...)
--               or a client without the file keeps its art, gone grey.
-- Region calls only (the client's buttons; some are protected). The
-- client re-sets a micro button's atlases on press and release
-- (MainMenuBarMicroButtonMixin SetPushed / SetNormal): each puts ours
-- back after it. Under every other look none of this runs.
local QUICKSLOT = "Interface\\Buttons\\UI-Quickslot2"
local HILIGHT_SQ = "Interface\\Buttons\\ButtonHilight-Square"
local CHECK_HI = "Interface\\Buttons\\CheckButtonHilight"
local MICRO_HI = "Interface\\Buttons\\UI-MicroButton-Hilight"
local MICRO_TC = { 0, 1, 24 / 64, 1 }
-- the vanilla / TBC sheet each button wears (by the client's button name)
AB.MICRO_2004 = {
    CharacterMicroButton = "Character", SpellbookMicroButton = "Spellbook", TalentMicroButton = "Talents",
    QuestLogMicroButton = "Quest", SocialsMicroButton = "Socials", WorldMapMicroButton = "World",
    MainMenuMicroButton = "MainMenu", HelpMicroButton = "Help", LFDMicroButton = "LFG",
}

function AB.Modern2004()
    local P = ns.Look and ns.Look.Panels
    return (P and P.Modern and P.Modern()) and true or false
end
local function FileOK(path)
    local P = ns.Look and ns.Look.Panels
    if P and P.FileOK then return P.FileOK(path) end
    return true
end
local function Grey(t)
    local P = ns.Look and ns.Look.Panels
    if P and P.Grey then P.Grey(t) end
end
local function IsTex(t) return type(t) == "table" and t.SetTexture ~= nil end

local function Art(t, file, tc)
    if not IsTex(t) then return end
    t:SetTexture(file)
    if t.SetTexCoord then
        if tc then t:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) else t:SetTexCoord(0, 1, 0, 1) end
    end
    if t.SetDesaturated then t:SetDesaturated(false) end
    if t.SetVertexColor then t:SetVertexColor(1, 1, 1, 1) end
end

function AB.ClassicBagSlot(b)
    if type(b) ~= "table" or b == KeyRingButton then return end
    local w, h = b:GetWidth(), b:GetHeight()
    if type(w) ~= "number" or w <= 0 then w = 37 end
    if type(h) ~= "number" or h <= 0 then h = w end
    local nt = b.GetNormalTexture and b:GetNormalTexture()
    if not IsTex(nt) then nt = rawget(b, "NormalTexture") end
    if IsTex(nt) then
        Art(nt, QUICKSLOT)
        nt:SetAlpha(1)
        nt:ClearAllPoints()
        nt:SetSize(w * 64 / 37, h * 64 / 37)
        nt:SetPoint("CENTER", b, "CENTER", 0, -h / 37)
    end
    local hl = b.GetHighlightTexture and b:GetHighlightTexture()
    if IsTex(hl) then
        Art(hl, HILIGHT_SQ)
        if hl.SetBlendMode then hl:SetBlendMode("ADD") end
        hl:ClearAllPoints() hl:SetAllPoints(b)
    end
    local sh = rawget(b, "SlotHighlightTexture")
    if IsTex(sh) then
        Art(sh, CHECK_HI)
        if sh.SetBlendMode then sh:SetBlendMode("ADD") end
        sh:ClearAllPoints() sh:SetAllPoints(b)
    end
    rawset(b, "_zKit2004", nt or true)
    -- the client puts its own border back on some updates
    if not rawget(b, "_zKit2004Hook") then
        rawset(b, "_zKit2004Hook", true)
        for _, m in ipairs({ "SetNormalAtlas", "SetNormalTexture" }) do
            if type(b[m]) == "function" then
                hooksecurefunc(b, m, function(self)
                    if AB.Kit() == "classic" and AB.Modern2004() then AB.ClassicBagSlot(self) end
                end)
            end
        end
    end
end

-- the character button's portrait in the vanilla face window
local function MicroPortrait(b, pushed)
    local pt = rawget(b, "Portrait")
    if not IsTex(pt) then return end
    local mask = rawget(b, "PortraitMask")
    if mask and pt.RemoveMaskTexture then pcall(pt.RemoveMaskTexture, pt, mask) end
    local w, h = b:GetWidth(), b:GetHeight()
    if type(w) ~= "number" or w <= 0 then w = 32 end
    if type(h) ~= "number" or h <= 0 then h = 40 end
    local kw, kh = w / 32, h / 40
    pt:ClearAllPoints()
    pt:SetSize(18 * kw, 25 * kh)
    pt:SetPoint("TOP", b, "TOP", (pushed and 1 or 0) * kw, -(pushed and 5 or 4) * kh)
    if pt.SetTexCoord then pt:SetTexCoord(0.2, 0.8, 0.0666, 0.9) end
    for _, k in ipairs({ "Shadow", "PushedShadow" }) do
        local s = rawget(b, k)
        if s and s.SetAlpha then s:SetAlpha(0) end
    end
end

function AB.ClassicMicro(b)
    if type(b) ~= "table" then return end
    local name = b.GetName and b:GetName()
    local sheet = name and AB.MICRO_2004[name]
    local base = sheet and ("Interface\\Buttons\\UI-MicroButton-" .. sheet .. "-")
    local own = base and FileOK(base .. "Up") and FileOK(base .. "Down")
    local nt = b.GetNormalTexture and b:GetNormalTexture()
    local pt = b.GetPushedTexture and b:GetPushedTexture()
    local dt = b.GetDisabledTexture and b:GetDisabledTexture()
    local ht = b.GetHighlightTexture and b:GetHighlightTexture()
    if own then
        Art(nt, base .. "Up", MICRO_TC)
        Art(pt, base .. "Down", MICRO_TC)
        Art(dt, FileOK(base .. "Disabled") and (base .. "Disabled") or (base .. "Up"), MICRO_TC)
        if dt and dt.SetDesaturated and not FileOK(base .. "Disabled") then dt:SetDesaturated(true) end
        if FileOK(MICRO_HI) then
            Art(ht, MICRO_HI, MICRO_TC)
            if ht and ht.SetBlendMode then ht:SetBlendMode("ADD") end
        end
        for _, k in ipairs({ "Background", "PushedBackground" }) do
            local x = rawget(b, k)
            if x and x.SetAlpha then x:SetAlpha(0) end
        end
        if rawget(b, "Portrait") then MicroPortrait(b, rawget(b, "_zKitPushed")) end
        rawset(b, "_zKit2004", base)
    else
        Grey(nt) Grey(pt) Grey(dt) Grey(ht)
        Grey(rawget(b, "Background")) Grey(rawget(b, "PushedBackground"))
        rawset(b, "_zKit2004", "grey")
    end
    if not rawget(b, "_zKit2004Hook") then
        rawset(b, "_zKit2004Hook", true)
        local function again(self) if AB.Kit() == "classic" and AB.Modern2004() then AB.ClassicMicro(self) end end
        for _, m in ipairs({ "SetNormal", "SetPushed", "SetNormalAtlas", "SetPushedAtlas", "SetHighlightAtlas" }) do
            if type(b[m]) == "function" then
                hooksecurefunc(b, m, function(self)
                    if m == "SetPushed" then rawset(self, "_zKitPushed", true)
                    elseif m == "SetNormal" then rawset(self, "_zKitPushed", nil) end
                    again(self)
                end)
            end
        end
    end
end

-- ============================================================
-- MICRO MENU
-- ============================================================
local micro
local MICRO_BUTTONS = {
    "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton",
    "QuestLogMicroButton", "SocialsMicroButton", "WorldMapMicroButton",
    "MainMenuMicroButton", "HelpMicroButton",
}
-- WoW Forever's micro menu (2026-11-07; Blizzard_MicroMenu/Camelot):
-- professions, the Legacy system, guild, the group finder, collections,
-- the adventure guide and the store sit beside the ones above. Taken in
-- Blizzard's own order on that client only (Classic's list stays as it
-- is), each only when the client has it.
if _G.ZACUI_IS_FOREVER then
    MICRO_BUTTONS = {
        "CharacterMicroButton", "ProfessionMicroButton", "SpellbookMicroButton", "TalentMicroButton",
        "LegacyMicroButton", "QuestLogMicroButton", "SocialsMicroButton", "GuildMicroButton",
        "LFDMicroButton", "WorldMapMicroButton", "CollectionsMicroButton", "EJMicroButton",
        "HelpMicroButton", "StoreMicroButton", "MainMenuMicroButton",
    }
end
-- Retail's (2026-11-07; Blizzard_MicroMenu/Mainline/MainMenuBarMicroButtons.xml
-- on the live branch): the spellbook and talents are one PlayerSpells
-- button, achievements and housing have buttons of their own, and there
-- is no world map or socials button (the map is a key, friends are in
-- the Guild & Communities window). Each only when the client has it.
if _G.ZACUI_IS_RETAIL then
    MICRO_BUTTONS = {
        "CharacterMicroButton", "ProfessionMicroButton", "PlayerSpellsMicroButton", "AchievementMicroButton",
        "QuestLogMicroButton", "HousingMicroButton", "GuildMicroButton", "LFDMicroButton",
        "CollectionsMicroButton", "EJMicroButton", "HelpMicroButton", "StoreMicroButton", "MainMenuMicroButton",
    }
end
AB.MICRO_BUTTONS = MICRO_BUTTONS
-- Lays a row (or column) of micro buttons out on `header`: shared by
-- the live menu and the preview's look-alikes. Micro buttons are 32 wide
-- and 40 tall; LayoutButtons sizes square, so it sizes by width and the
-- height is put back after.
function AB.LayoutMicro(header, buttons, cfg)
    local lay = { padding = cfg.padding, rows = cfg.vertical and #buttons or 1,
                  growH = cfg.growH, growV = cfg.growV }
    AB.LayoutButtons(header, buttons, lay, 32, #buttons)
    for _, b in ipairs(buttons) do b:SetSize(32, 40) end
    if header.overlay then header.overlay:SetHeight(math.max(header.overlay:GetHeight(), 48)) end
end

local function MicroLayout()
    if not (micro and micro.cfg and micro.cfg.enabled) or InCombatLockdown() then return end
    AB.LayoutMicro(micro, micro.buttons, micro.cfg)
end

local function ApplyMicro(profile)
    local cfg = profile.micro
    if not micro then
        micro = AB.NewHeader("micro", "ZacUIMicroMenu", "Micro menu")
        micro.buttons = {}
        for _, name in ipairs(MICRO_BUTTONS) do
            local b = _G[name]
            if b then micro.buttons[#micro.buttons + 1] = b end
        end
        if UpdateMicroButtons then hooksecurefunc("UpdateMicroButtons", MicroLayout) end
        if UpdateMicroButtonsParent then
            hooksecurefunc("UpdateMicroButtonsParent", function(parent)
                if parent ~= micro and micro.cfg and micro.cfg.enabled then
                    C_Timer.After(0, function()
                        if not InCombatLockdown() then
                            UpdateMicroButtonsParent(micro)
                            MicroLayout()
                        end
                    end)
                end
            end)
        end
        if _G.MicroMenu and _G.MicroMenu.SetParent then
            hooksecurefunc(_G.MicroMenu, "SetParent", function(_, parent)
                if micro.cfg and micro.cfg.enabled and not InCombatLockdown() then
                    for _, b in ipairs(micro.buttons) do b:SetParent(micro) end
                    MicroLayout()
                end
            end)
        end
    end
    if not cfg.enabled then
        -- give the buttons back to whoever the client wants them on
        if micro.owned then
            local home = _G.MicroMenu or _G.MainMenuBarArtFrame or UIParent
            for _, b in ipairs(micro.buttons) do b:SetParent(home) end
            if UpdateMicroButtonsParent and _G.MicroMenu then pcall(UpdateMicroButtonsParent, _G.MicroMenu) end
            micro.owned = nil
        end
        SmallBarCommon(micro, cfg, {}, 32, 0, cfg.initial)
        return
    end
    if cfg.point == nil and not micro.owned and AB.SeatFromStock then
        AB.SeatFromStock(cfg, micro.buttons, 32, "micro", 40)
    end
    -- (a game look keeps each button's own art: the game's micro menu)
    local stockArt = AB.Kit and AB.Kit() ~= "zacui"
    for _, b in ipairs(micro.buttons) do
        b:SetParent(micro)
        b:SetFrameLevel(micro:GetFrameLevel() + 1)
        if not stockArt then
            if ns.HideRegions then ns.HideRegions(b:GetName(), { "Border", "Flash" }) end
            if b.Background then b.Background:SetAlpha(0) end
            if b.PushedBackground then b.PushedBackground:SetAlpha(0) end
        end
        b:Show()
    end
    -- Forever: Blizzard's menu frame keeps its bar art (BorderArt and
    -- BackgroundArt) around a grid the buttons have left; away with it
    local mm = _G.MicroMenu
    if mm then
        if type(rawget(mm, "BorderArt")) == "table" then mm.BorderArt:SetAlpha(0) end
        if type(rawget(mm, "BackgroundArt")) == "table" then mm.BackgroundArt:SetAlpha(0) end
    end
    micro.owned = true
    if UpdateMicroButtonsParent then pcall(UpdateMicroButtonsParent, micro) end
    SmallBarCommon(micro, cfg, micro.buttons, 32, #micro.buttons, cfg.initial)
    MicroLayout()
    -- Classic WoW UI on Forever / Retail: the 2004 micro buttons (after
    -- the layout: the portrait is fitted to the laid-out button)
    if stockArt and AB.Kit() == "classic" and AB.Modern2004() then
        for _, b in ipairs(micro.buttons) do AB.ClassicMicro(b) end
    end
end
AB.RegisterApplier(ApplyMicro)

-- ============================================================
-- XP / REPUTATION STRIP
-- ============================================================
local status

-- ------------------------------------------------------------
-- THE GAME'S XP BARS ON A ZacUI HOLDER (2026-11-08, Zac: "xp bar is super
-- long by default and overlap the action bar"). The bars the player sees
-- are not StatusTrackingBarManager itself but its two children,
-- MainStatusTrackingBarContainer and SecondaryStatusTrackingBarContainer.
-- Each is an Edit Mode system of its own: Edit Mode anchors it to
-- UIParent (UpdateBottomActionBarPositions stacks it over the stock main
-- bar) and sizes it to the client's full width (Forever 1192, Era / TBC
-- 1024), and the bars inside it were sized once at load. Moving and
-- sizing the manager therefore moved nothing on screen. So the containers
-- themselves are seated: anchored on the holder, sized to it, their bars,
-- 20 dividers and frame art fitted to that width.
-- Taint care: widget calls only (SetPoint / SetWidth / SetFrameStrata), out
-- of combat; no Blizzard mixin method is called and no field is written on
-- a Blizzard frame (what is remembered lives in the weak tables below).
-- Edit Mode puts a container back on its layout passes; a hook on the
-- container's SetPoint / SetSize puts it back on the holder - at once out
-- of combat, after the fight in combat, and not at all while Edit Mode is
-- open (it is the player's to move then; the seat returns when it closes).
-- ------------------------------------------------------------
local STATUS_KEYS = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }
local stockFit = setmetatable({}, { __mode = "k" })   -- container -> its stock geometry
local seatHooked = setmetatable({}, { __mode = "k" })
local seat = { on = false }                            -- the holder the bars sit on, while seated
local seatBusy = false

local function StatusContainers(mgr)
    local list = {}
    if not mgr then return list end
    for _, key in ipairs(STATUS_KEYS) do
        local c = rawget(mgr, key)
        if type(c) ~= "table" then c = _G[key] end
        if type(c) == "table" and c.SetPoint and c.GetWidth then list[#list + 1] = c end
    end
    return list
end

-- the container's own art, in its groups: Forever's frame atlas, Classic's
-- main-bar strip and standalone strip (each a row of pieces end to end)
local function ArtGroups(c)
    local out = {}
    local one = rawget(c, "BarFrameTexture")
    if type(one) == "table" and one.SetWidth then out[#out + 1] = { one } end
    for _, key in ipairs({ "MainMenuBarTextures", "StandaloneTextures" }) do
        local arr = rawget(c, key)
        if type(arr) == "table" then
            local g = {}
            for _, t in ipairs(arr) do
                if type(t) == "table" and t.SetWidth then g[#g + 1] = t end
            end
            if #g > 0 then out[#out + 1] = g end
        end
    end
    return out
end
-- a piece this narrow or less is an end or a tick (Classic's 16 px left edge,
-- its 9 px cap ticks): it keeps its size; the long pieces take the rest
local ART_FIXED = 32

-- read once, before anything is changed: the container's stock width, the
-- gap its bars leave inside it, and each art piece's width
local function StockFit(c)
    local o = stockFit[c]
    if o then return o end
    local w = c:GetWidth()
    if type(w) ~= "number" or w <= 0 then return nil end
    o = { w = w, inset = 0, art = {} }
    local bars = rawget(c, "bars")
    if type(bars) == "table" then
        for _, b in pairs(bars) do
            if type(b) == "table" and b.GetWidth then
                local bw = b:GetWidth()
                if type(bw) == "number" and bw > 0 and bw <= w then o.inset = w - bw break end
            end
        end
    end
    -- each group: its long pieces stretch so the row still spans what it
    -- spanned beyond (or short of) the container's own edges
    for _, g in ipairs(ArtGroups(c)) do
        local long, pieces = 0, {}
        for _, t in ipairs(g) do
            local tw = t:GetWidth()
            if type(tw) == "number" and tw > ART_FIXED then
                pieces[t] = tw
                long = long + tw
            end
        end
        if long > 0 then o.art[#o.art + 1] = { pieces = pieces, long = long, rest = w - long } end
    end
    stockFit[c] = o
    return o
end

-- one container at `w` (its own units): the container, its bars, its art,
-- and the dividers spread evenly across it again
local function FitContainer(c, w)
    local o = StockFit(c)
    if not o then return end
    c:SetWidth(w)
    local bw = math.max(1, w - o.inset)
    local bars = rawget(c, "bars")
    if type(bars) == "table" then
        for _, b in pairs(bars) do
            if type(b) == "table" and b.SetWidth then
                b:SetWidth(bw)
                local sb = rawget(b, "StatusBar")
                if type(sb) == "table" and sb.SetWidth then sb:SetWidth(bw) end
            end
        end
    end
    for _, g in ipairs(o.art) do
        local k = math.max(0, w - g.rest) / g.long
        for t, tw in pairs(g.pieces) do t:SetWidth(tw * k) end
    end
    local pool = rawget(c, "HorizontalDividersPool")
    if type(pool) == "table" and pool.EnumerateActive then
        local divs = {}
        for d in pool:EnumerateActive() do
            local x = d.GetPoint and select(4, d:GetPoint(1)) or 0
            divs[#divs + 1] = { d = d, x = tonumber(x) or 0 }
        end
        table.sort(divs, function(a, b) return a.x < b.x end)
        local step = w / (#divs + 1)
        for i, e in ipairs(divs) do
            e.d:ClearAllPoints()
            e.d:SetPoint("LEFT", c, "LEFT", step * i, 0)
        end
    end
end

-- every container onto the holder: the main bar at its bottom, the second
-- (a watched reputation beside the XP) right above it
local function Reseat()
    local mgr = _G.StatusTrackingBarManager
    local holder = seat.holder
    if not (seat.on and mgr and holder) then return end
    if InCombatLockdown() then return AB.AfterCombat("statusSeat", Reseat) end
    seatBusy = true
    local hs = holder:GetEffectiveScale() or 1
    local below
    for _, c in ipairs(StatusContainers(mgr)) do
        local cs = c:GetEffectiveScale() or 1
        local w = seat.w * hs / ((cs > 0) and cs or 1)
        pcall(FitContainer, c, w)
        c:ClearAllPoints()
        if below then
            c:SetPoint("BOTTOMLEFT", below, "TOPLEFT", 0, 0)
        else
            c:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
        end
        below = c
    end
    seatBusy = false
end

local function OnStatusMoved()
    if seatBusy or not seat.on then return end
    local em = _G.EditModeManagerFrame
    if em and em.IsShown and em:IsShown() then return end
    if InCombatLockdown() then AB.AfterCombat("statusSeat", Reseat) return end
    Reseat()
end

local function HookStatus(mgr)
    for _, c in ipairs(StatusContainers(mgr)) do
        if not seatHooked[c] then
            seatHooked[c] = true
            hooksecurefunc(c, "SetPoint", OnStatusMoved)
            if c.SetSize then hooksecurefunc(c, "SetSize", OnStatusMoved) end
        end
    end
    -- Classic scales the manager on its own layout pass (UpdateBarVisuals)
    if not seatHooked[mgr] and mgr.SetScale then
        seatHooked[mgr] = true
        hooksecurefunc(mgr, "SetScale", OnStatusMoved)
    end
    local em = _G.EditModeManagerFrame
    if em and em.HookScript and not seatHooked[em] then
        seatHooked[em] = true
        em:HookScript("OnHide", function() C_Timer.After(0, OnStatusMoved) end)
    end
end

-- the manager and its bars on `holder` at `w` (holder units). strata: the
-- seat on bar 1 sits a layer under the bar (LOW), so bar 1's gryphons draw
-- over its ends as they do over the game's own; ZacUI's strip keeps the
-- manager's own MEDIUM.
local function SeatStatus(mgr, holder, w, strata)
    seat.on, seat.holder, seat.w = true, holder, w
    mgr:SetParent(holder)
    mgr:ClearAllPoints()
    mgr:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
    if mgr.SetFrameStrata then mgr:SetFrameStrata(strata or "MEDIUM") end
    mgr:SetWidth(w)
    HookStatus(mgr)
    Reseat()
    mgr:Show()
end
AB.StatusSeat = seat   -- (read by the tests)

local function ApplyStatus(profile)
    local cfg = profile.status
    local mgr = _G.StatusTrackingBarManager
    if not status then
        status = AB.NewHeader("status", "ZacUIStatusBar", "XP / reputation bar")
        status.content = CreateFrame("Frame", nil, status)
        status.content:SetFrameLevel(status:GetFrameLevel() + 1)
    end
    status.cfg = cfg
    -- A GAME LOOK'S SEAT (2026-11-08): with ZacUI's strip off, the game's
    -- own XP / reputation bars sit on top of bar 1's chrome at its width, as
    -- the game's main bar carries them (nothing saved; ZacUI's look and a
    -- strip of ZacUI's own are never moved). Its width is bar 1's FRAME:
    -- WoW Forever's frame art reaches past the buttons (AB.KIT_FRAME), the
    -- caps-only looks' frame is the button grid.
    local seatOn, seatFrame, seatFramed
    if not cfg.enabled and mgr and cfg.kitSeat ~= false and AB.Kit and AB.Kit() ~= "zacui" then
        local b1 = AB.actionBars and AB.actionBars[1]
        seatFrame, seatFramed = AB.KitGridFrame(b1)
        seatOn = seatFrame ~= nil and b1:IsShown()
    end
    if seatOn then
        local F = AB.KIT_FRAME
        local k = ((AB.actionBars[1].cfg and AB.actionBars[1].cfg.buttonSize or AB.BUTTON) / 45)
        local left = seatFramed and (F.l * k) or 0
        local w = seatFrame:GetWidth() + (seatFramed and ((F.r - F.l) * k) or 0)
        local lift = seatFramed and (F.t * k) or 0
        -- bar 1's units to the holder's (bar 1 may be scaled; the holder is not)
        status:SetScale(1)
        local ss = status:GetEffectiveScale() or 1
        local u = (seatFrame:GetEffectiveScale() or ss) / ((ss > 0) and ss or 1)
        status:SetFrameStrata("LOW")
        status:ClearAllPoints()
        status:SetPoint("TOPLEFT", seatFrame, "TOPLEFT", left * u, (lift + 14 + 1) * u)
        status.content:ClearAllPoints()
        status.content:SetPoint("TOPLEFT", status, "TOPLEFT", 0, 0)
        status.content:SetSize(w * u, 14)
        SeatStatus(mgr, status.content, w * u, "LOW")
        status.owned = true
        status:SetAlpha(1)
        status:Show()
        UnregisterStateDriver(status, "visibility")
        AB.RegisterFade(status, { fade = false, alpha = 1 })
        return
    end
    status:SetFrameStrata("MEDIUM")
    if not cfg.enabled or not mgr then
        seat.on = false
        UnregisterStateDriver(status, "visibility")
        status:Hide()
        AB.RegisterFade(status, { fade = false, alpha = 1 })
        if status.owned and mgr then
            mgr:SetParent(AB.Hider() or UIParent)
            if mgr.SetFrameStrata then mgr:SetFrameStrata("MEDIUM") end
            status.owned = nil
        end
        return
    end
    local w = cfg.width or 1024
    AB.Place(status, cfg, cfg.initial)
    status.content:ClearAllPoints()
    status.content:SetPoint("TOPLEFT", status, "TOPLEFT", 0, 0)
    status.content:SetSize(w, 14)
    SeatStatus(mgr, status.content, w, "MEDIUM")
    status.owned = true
    if status.overlay then
        status.overlay:ClearAllPoints()
        status.overlay:SetPoint("TOPLEFT", status, "TOPLEFT", -4, 4)
        status.overlay:SetSize(w + 8, 22)
    end
    status:SetAlpha(cfg.alpha or 1)
    status:Show()
    UnregisterStateDriver(status, "visibility")
    RegisterStateDriver(status, "visibility", AB.VisibilityDriver(cfg))
    AB.RegisterFade(status, cfg)
    AB.MoverFor(status, cfg, function() if ns.RefreshConfig then ns.RefreshConfig() end end)
end
AB.RegisterApplier(ApplyStatus)
