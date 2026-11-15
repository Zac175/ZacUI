-- ============================================================================
-- Zacui_UnitFrames - OptionsLink.lua
-- What used to sit in Options.lua and is needed without the settings
-- page. The page itself loads on demand with ZacUI's settings window (the
-- Zacui_Options addon, 2026-11-13); these are wanted from login:
--   * ns.RefreshOptions, ns.ToggleConfig - a castbar dragged on screen,
--     /zuf, the position dialog's "All settings"
--   * the unit frames as a target of ZacUI's global font and bar texture
--   * the unit frames' place in ZacUI's Edit Mode
-- Part of ZacUI; load order is set by the TOC.
-- ============================================================================
local ADDON, ns = ...

local function ZUI() return ns.ZUI or _G.ZacUI end
local function PageOpen()
    local Z = ZUI()
    return Z and Z.ConfigIsOpen and Z.ConfigIsOpen()
        and Z.ConfigState and Z.ConfigState().selected == "unitframes"
end
local function Refresh()
    local Z = ZUI()
    if Z and Z.RefreshConfig then Z.RefreshConfig() end
end

-- A castbar dragged on screen moves its offsets: the open page shows them.
function ns.RefreshOptions()
    if PageOpen() then Refresh() end
end

-- /zuf and the position dialog's "All settings": the page, or closed when
-- it is already the one up.
function ns.ToggleConfig()
    local Z = ZUI()
    if not (Z and Z.OpenConfig) then return end
    if PageOpen() and Z.ToggleConfig then Z.ToggleConfig() return end
    Z.OpenConfig("unitframes")
end

-- ============================================================================
-- THE ZACUI SIDE: the global font/texture target, Edit Mode.
-- ============================================================================
do
    local ZUI = ns.ZUI or _G.ZacUI
    -- the global font and bar texture (ZacUI > Fonts & Textures) land in
    -- the unit frames' font, bar texture and name-strip texture
    if ZUI and ZUI.Media and ZUI.Media.RegisterTarget then
        ZUI.Media.RegisterTarget("unitframes", {
            label = "Unit frames",
            desc = "Frame font, bar texture and name-strip texture.",
            order = 10,
            -- still on its shipped font
            untouched = function()
                local f = ns.db and ns.db.media and ns.db.media.font
                return f == nil or f == "" or f == "Friz Quadrata TT"
            end,
            apply = function(font, bar, cleared)
                if not (ns.db and ns.db.media) then return end
                if font then ns.db.media.font = font
                elseif cleared then ns.db.media.font = "Friz Quadrata TT" end
                if bar then ns.db.media.bar = bar; ns.db.media.nameBar = bar end
                if ns.ApplySettings then ns.ApplySettings() end
            end,
        })
    end
    -- ZACUI'S EDIT MODE. The unit frames join the pass as one element:
    -- entering unlocks them through their own move mode (every frame
    -- shown and draggable, the party and raid previews up when you are
    -- not in one), leaving locks them again. ZacUI's grid is already on
    -- screen, so this one's grid and position dialog are not opened; the
    -- dialog (exact coordinates, raid groups per row) comes up when a
    -- frame is clicked - see ns.SelectMoveFrame. Only what was unlocked
    -- here is locked on the way out, so frames you unlocked yourself with
    -- /zmove before entering are left as you had them.
    if ZUI then
        ZUI.EditModeProviders = ZUI.EditModeProviders or {}
        -- what Edit Mode outlines and lines its guides up on: each single
        -- frame, and ONE box round a whole party or raid block (its handle,
        -- its real members and its previews). The same frames are what
        -- Edit Mode fades while the unit frames are hidden there.
        local function EditFrames()
            local list = {}
            for key, f in pairs(ns.frames) do
                if key == "party" or key == "raid" then
                    local u = {}
                    if f.mover then u[#u + 1] = f.mover end
                    for _, h in ipairs(f.headers or {}) do
                        for _, child in ipairs({ h:GetChildren() }) do u[#u + 1] = child end
                    end
                    local mf, n = nil, 0
                    if ns.MockFrames then mf, n = ns.MockFrames(key) end
                    for i = 1, n do u[#u + 1] = mf[i] end
                    if #u > 0 then list[#list + 1] = { union = u } end
                else
                    list[#list + 1] = f
                end
            end
            return list
        end
        -- one group's members and samples (not its drag handle)
        local function GroupSample(kind)
            local out = {}
            local f = ns.frames and ns.frames[kind]
            for _, h in ipairs(f and f.headers or {}) do
                for _, child in ipairs({ h:GetChildren() }) do out[#out + 1] = child end
            end
            local mf, n = nil, 0
            if ns.MockFrames then mf, n = ns.MockFrames(kind) end
            for i = 1, n or 0 do out[#out + 1] = mf[i] end
            return out
        end
        ZUI.EditModeProviders[#ZUI.EditModeProviders + 1] = function()
            if not (ns.db and ns.frames and ns.ApplySettings) then return nil end
            return { {
                key = "unitframes",
                label = "Unit frames (player, target, party, raid)",
                show = function()
                    if ns.db.locked == false then return end
                    ns._zuiEdit = true
                    -- remembered in the save too: a /reload (or an error)
                    -- before Edit Mode closes must not leave the frames
                    -- unlocked for good (Core.lua puts the lock back)
                    ns.db._editUnlocked = true
                    ns.db.locked = false
                    ns.ApplySettings()
                end,
                hide = function()
                    if not ns._zuiEdit then return end
                    ns._zuiEdit = nil
                    ns.db._editUnlocked = nil
                    if ns.HideMoveDialog then ns.HideMoveDialog() end
                    ns.db.locked = true
                    ns.ApplySettings()
                end,
                frames = EditFrames,
                content = EditFrames,
                -- (2026-11-11) the party's and the raid's samples can each
                -- be switched off on their own (Edit Mode's previewParts)
                previewParts = {
                    { key = "party", label = "party preview", content = function() return GroupSample("party") end },
                    { key = "raid", label = "raid preview", content = function() return GroupSample("raid") end },
                },
                -- every frame's spot, for Edit Mode's undo and Cancel
                snapshot = function()
                    local out = {}
                    for k, cfg in pairs(ns.db.frames or {}) do
                        if type(cfg) == "table" and cfg.point then
                            out["frames." .. k] = { point = cfg.point, x = cfg.x, y = cfg.y }
                        end
                    end
                    for k, cfg in pairs(ns.db) do
                        if k ~= "frames" and type(cfg) == "table" and cfg.point and cfg.x ~= nil then
                            out[k] = { point = cfg.point, x = cfg.x, y = cfg.y }
                        end
                    end
                    return out
                end,
                restore = function(v)
                    if type(v) ~= "table" or InCombatLockdown() then return end
                    for path, spot in pairs(v) do
                        local k = path:match("^frames%.(.+)$")
                        local cfg = k and ns.db.frames and ns.db.frames[k] or (not k and ns.db[path])
                        if type(cfg) == "table" then cfg.point, cfg.x, cfg.y = spot.point, spot.x, spot.y end
                    end
                    ns.ApplySettings()
                    if ns.RefreshMoveDialog then ns.RefreshMoveDialog() end
                end,
                page = "unitframes",
            } }
        end
    end
end
