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
        KeyRingButton:SetSize(18, 37)
    end
    -- a game look: each bag slot at the client's own size (the backpack
    -- bigger than the bag slots, the slot art never stretched); the row
    -- stays centred on its line (LayoutButtons chains side middles)
    if AB.Kit and AB.Kit() ~= "zacui" then
        for _, b in ipairs(bagbar.buttons) do
            local hm = b.zHome
            if hm and hm.w and hm.w > 0 and hm.h and hm.h > 0 and b ~= KeyRingButton then b:SetSize(hm.w, hm.h) end
        end
    end
end
AB.RegisterApplier(ApplyBagBar)

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
end
AB.RegisterApplier(ApplyMicro)

-- ============================================================
-- XP / REPUTATION STRIP
-- ============================================================
local status
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
    -- strip of ZacUI's own are never moved)
    local seatOn, seatFrame, seatFramed
    if not cfg.enabled and mgr and cfg.kitSeat ~= false and AB.Kit and AB.Kit() ~= "zacui" then
        local b1 = AB.actionBars and AB.actionBars[1]
        seatFrame, seatFramed = AB.KitGridFrame(b1)
        seatOn = seatFrame ~= nil and b1:IsShown()
    end
    if seatOn then
        local w = seatFrame:GetWidth()
        local lift = seatFramed and (6 * ((AB.actionBars[1].cfg and AB.actionBars[1].cfg.buttonSize or AB.BUTTON) / 45)) or 0
        status:ClearAllPoints()
        status:SetPoint("TOPLEFT", seatFrame, "TOPLEFT", 0, lift + 14 + 1)
        status:SetScale(1)
        status.content:ClearAllPoints()
        status.content:SetPoint("TOPLEFT", status, "TOPLEFT", 0, 0)
        status.content:SetSize(w, 14)
        mgr:SetParent(status.content)
        mgr:ClearAllPoints()
        mgr:SetPoint("BOTTOMLEFT", status.content, "BOTTOMLEFT", 0, 0)
        mgr:SetWidth(w)
        for _, key in ipairs({ "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }) do
            local c = rawget(mgr, key)
            if type(c) == "table" and c.SetWidth then c:SetWidth(w) end
        end
        mgr:Show()
        status.owned = true
        status:SetAlpha(1)
        status:Show()
        UnregisterStateDriver(status, "visibility")
        AB.RegisterFade(status, { fade = false, alpha = 1 })
        return
    end
    if not cfg.enabled or not mgr then
        UnregisterStateDriver(status, "visibility")
        status:Hide()
        AB.RegisterFade(status, { fade = false, alpha = 1 })
        if status.owned and mgr then
            mgr:SetParent(AB.Hider() or UIParent)
            status.owned = nil
        end
        return
    end
    local w = cfg.width or 1024
    AB.Place(status, cfg, cfg.initial)
    status.content:ClearAllPoints()
    status.content:SetPoint("TOPLEFT", status, "TOPLEFT", 0, 0)
    status.content:SetSize(w, 14)
    mgr:SetParent(status.content)
    mgr:ClearAllPoints()
    mgr:SetPoint("BOTTOMLEFT", status.content, "BOTTOMLEFT", 0, 0)
    mgr:SetWidth(w)
    if mgr.MainStatusTrackingBarContainer then mgr.MainStatusTrackingBarContainer:SetWidth(w) end
    if mgr.SecondaryStatusTrackingBarContainer then mgr.SecondaryStatusTrackingBarContainer:SetWidth(w) end
    mgr:Show()
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
