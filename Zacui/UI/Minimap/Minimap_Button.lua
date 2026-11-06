-- Minimap_Button - ZacUI's minimap button.
-- Part of ZacUI; load order is set by the TOC.
--
-- A LibDataBroker object registered with LibDBIcon (both ship in Libs),
-- which is the one way to build a minimap button that every collector
-- understands: HidingBar, MBB, Bazooka and ZacUI's own button tray all
-- pick a LibDBIcon button up by its LibDBIcon10_ name and leave anything
-- hand-rolled where it stands. The same approach as Readycheck's button,
-- so the two behave identically on the minimap and in any tray.
--
-- Left click opens (or closes) the settings window, right click opens a
-- menu of everything ZacUI can do from here - pages, profiles, Edit Mode,
-- the aura engine - and middle click is Edit Mode. The menu is built from
-- the live config menu, so a part that is not loaded is listed as such
-- rather than quietly missing.
--
-- THE AURA ENGINE'S OWN BUTTON. The embedded engine (and upstream
-- WeakAuras when that is the one running) registers a LibDBIcon button of
-- its own. It is one more thing on the minimap for a window this menu
-- already opens, so by default it is hidden here and this button is the
-- way in. A switch on the Minimap page puts it back.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local Print = ns.Print
local Profiles = ns.Profiles
local UI = ns.UI
local ZUI = ns.ZUI

local NAME = "ZacUI"
local ICON = "Interface\\AddOns\\ZacUI\\Media\\addonIcon"
-- the LibDBIcon registration names of the two aura engines
local ENGINE_BUTTONS = { "ZacUI Auras", "WeakAuras" }

local MB = {}
ns.MinimapButton = MB

local function LDB()  return LibStub and LibStub("LibDataBroker-1.1", true) end
local function LDBI() return LibStub and LibStub("LibDBIcon-1.0", true) end

local function DB()
    ZacUIDB.minimapButton = ZacUIDB.minimapButton or {}
    local t = ZacUIDB.minimapButton
    if t.hide == nil then t.hide = false end
    if t.lock == nil then t.lock = false end
    if t.minimapPos == nil then t.minimapPos = 215 end
    if t.hideEngineButton == nil then t.hideEngineButton = true end
    return t
end
MB.DB = DB

-- ============================================================
-- MENU
-- ============================================================
local function Reload()
    if type(ReloadUI) == "function" then ReloadUI()
    elseif C_UI and C_UI.Reload then C_UI.Reload() end
end

-- One entry per config page, in the sidebar's order. A category becomes a
-- submenu; a page whose part is off says so instead of vanishing.
local function PageItems(list)
    local items = {}
    local pages = ns.ConfigPages or {}
    for _, item in ipairs(list or ns.ConfigMenu or {}) do
        if item.children then
            items[#items + 1] = { text = item.label, children = function() return PageItems(item.children) end }
        elseif item.page and pages[item.page] then
            local id = item.id
            items[#items + 1] = { text = item.label, func = function() ns.OpenConfig(id) end }
        elseif item.page and item.addon then
            items[#items + 1] = { text = item.label .. "  (" .. item.addon .. " off)", disabled = true,
                tooltip = "Enable " .. item.addon .. " in the AddOns list to get this page back." }
        end
    end
    return items
end

local function ProfileItems()
    local items = {}
    if not Profiles then return items end
    Profiles.WriteBack()
    local current = Profiles.Current()
    for _, name in ipairs(Profiles.List()) do
        items[#items + 1] = {
            text = name,
            checked = (name == current),
            func = function()
                if name == current then return end
                UI.Confirm({
                    title = "Switch profile",
                    text = "Put '" .. name .. "' on this character? What it has now is written back "
                        .. "into '" .. tostring(current) .. "' first. A reload follows.",
                    acceptText = "Switch",
                    onAccept = function()
                        local ok, err = Profiles.Use(name)
                        if ok then Reload() else Print(tostring(err)) end
                    end,
                })
            end,
        }
    end
    items[#items + 1] = { separator = true }
    items[#items + 1] = { text = "Manage profiles...", func = function() ns.OpenConfig("profiles") end }
    return items
end

local function OpenAuras()
    if WeakAuras and WeakAuras.OpenOptions then
        WeakAuras.OpenOptions()
    else
        ns.OpenConfig("auras")
    end
end

function MB.ShowMenu()
    local items = {
        { text = "ZacUI v" .. tostring(ZUI.VERSION), isTitle = true },
        { text = "Settings", func = function() ns.OpenConfig() end,
          tooltip = "The options window (/zui)." },
        { text = "Edit Mode", func = function() if ns.ToggleEditMode then ns.ToggleEditMode() end end,
          tooltip = "Every movable ZacUI frame at once over a grid. Drag them into place, then close it to lock." },
        { text = "Pages", children = function() return PageItems() end },
        { text = "Profiles", children = ProfileItems },
        { text = "Aura engine", func = OpenAuras,
          tooltip = (WeakAuras and WeakAuras.OpenOptions) and "Opens the aura editor."
              or "The aura engine is not loaded; opens its page." },
        { separator = true },
        { text = "Reload UI", func = Reload },
        { separator = true },
        { text = "Lock minimap button", checked = function() return DB().lock end, keepOpen = true,
          func = function() MB.SetLocked(not DB().lock) end,
          tooltip = "Stops the button from being dragged around the minimap." },
        { text = "Hide minimap button", func = function() MB.SetShown(false) end,
          tooltip = "Hides this button. Bring it back from the Minimap page, or /zui minimap button." },
    }
    UI.ContextMenu(items)
end

-- ============================================================
-- THE BUTTON
-- ============================================================
local function OnClick(_, button)
    if button == "RightButton" then
        MB.ShowMenu()
    elseif button == "MiddleButton" then
        if ns.ToggleEditMode then ns.ToggleEditMode() end
    else
        if ns.ToggleConfig then ns.ToggleConfig() else ns.OpenConfig() end
    end
end

local function OnTooltip(tt)
    if not (tt and tt.AddLine) then return end
    tt:SetText("ZacUI", 1, 1, 1)
    tt:AddLine(" ")
    tt:AddLine("Left-click: settings", 0.2, 1, 0.2)
    tt:AddLine("Right-click: menu", 0.7, 0.85, 1)
    tt:AddLine("Middle-click: Edit Mode", 0.7, 0.85, 1)
    tt:AddLine("Drag: move around the minimap", 0.6, 0.6, 0.6)
end

function MB.Create()
    if MB.registered then return true end
    local ldb, ldbi = LDB(), LDBI()
    if not (ldb and ldbi) then return false end
    local db = DB()
    MB.object = ldb:GetDataObjectByName(NAME) or ldb:NewDataObject(NAME, {
        type = "launcher",
        text = "ZacUI",
        icon = ICON,
        OnClick = OnClick,
        OnTooltipShow = OnTooltip,
    })
    if not ldbi:IsRegistered(NAME) then
        ldbi:Register(NAME, MB.object, db)
    end
    MB.registered = true
    if db.lock then ldbi:Lock(NAME) end
    if db.hide then ldbi:Hide(NAME) end
    -- the mark turns when the mouse crosses the button
    local btn = ldbi.GetMinimapButton and ldbi:GetMinimapButton(NAME)
    if btn and btn.icon and btn.icon.CreateAnimationGroup and not btn._zSpin then
        local spin = btn.icon:CreateAnimationGroup()
        local rot = spin:CreateAnimation("Rotation")
        rot:SetDegrees(-360) rot:SetDuration(0.5) rot:SetSmoothing("IN_OUT")
        btn._zSpin = spin
        btn:HookScript("OnEnter", function() if not spin:IsPlaying() then spin:Play() end end)
    end
    return true
end

function MB.SetShown(on)
    local db = DB()
    db.hide = not on
    local ldbi = LDBI()
    if not (ldbi and MB.registered) then return end
    if on then ldbi:Show(NAME) else ldbi:Hide(NAME) end
    if not on then Print("minimap button hidden - /zui minimap button brings it back.") end
end

function MB.SetLocked(on)
    local db = DB()
    db.lock = on and true or false
    local ldbi = LDBI()
    if not (ldbi and MB.registered) then return end
    if on then ldbi:Lock(NAME) else ldbi:Unlock(NAME) end
end

function MB.ResetPosition()
    local db = DB()
    db.minimapPos = 215
    local ldbi = LDBI()
    if ldbi and MB.registered then ldbi:Refresh(NAME, db) end
end

-- The aura engine's own button, both engines. LibDBIcon keeps each
-- button's saved table on the button, so the hide flag lands in the
-- engine's own saved variables and the choice survives a reload with the
-- engine doing exactly what it would do for a user who hid it in its own
-- options. Showing it again clears the same flag.
function MB.ApplyEngineButton()
    local ldbi = LDBI()
    if not ldbi then return end
    local hide = DB().hideEngineButton
    for _, name in ipairs(ENGINE_BUTTONS) do
        if ldbi:IsRegistered(name) then
            local btn = ldbi:GetMinimapButton(name)
            if btn and btn.db then btn.db.hide = hide and true or false end
            if hide then ldbi:Hide(name) else ldbi:Show(name) end
        end
    end
end

-- ============================================================
-- START
-- ============================================================
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not MB.Create() then
        Print("minimap button: LibDBIcon did not load.")
    end
    -- the engine registers its icon from its own ADDON_LOADED; by now it
    -- exists, and a second pass catches the engine's late re-show
    MB.ApplyEngineButton()
    C_Timer.After(3, MB.ApplyEngineButton)
    local ldbi = LDBI()
    if ldbi and ldbi.RegisterCallback then
        pcall(ldbi.RegisterCallback, ldbi, MB, "LibDBIcon_IconCreated", function(_, _, name)
            for _, n in ipairs(ENGINE_BUTTONS) do
                if n == name then C_Timer.After(0, MB.ApplyEngineButton) end
            end
        end)
    end
end)
