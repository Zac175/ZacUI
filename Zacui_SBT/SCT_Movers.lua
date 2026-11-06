-- SCT_Movers - the scroll areas as boxes on the screen that you drag.
-- Part of ZacUI (Zacui_SBT). Written for ZacUI.
--
-- A scroll area is a rectangle: its bottom-left corner sits at an offset
-- from the middle of the screen, and text travels inside its width and
-- height. Numbers on a settings page are a poor way to place a
-- rectangle, so each area can be shown as a box and dragged. Two ways
-- in, same boxes:
--   * the Areas tab of the Scrolling text page ("Show on screen")
--   * ZacUI's Edit Mode, where they sit with every other movable thing
-- Dropping a box writes its position straight into the settings.
local ns = _G.ZacUI
if not ns then return end
local S = ns.SBT
if not S then return end

local UI = ns.UI

local boxes = {}        -- [area key] = frame
local editWanted = {}   -- [area key] = true while Edit Mode has it up
local pageShown = false -- the Areas tab's "show on screen" switch
local watch             -- ticker, alive only while pageShown

local function Round(v)
    return math.floor(v + 0.5)
end

local function Paint(box, state)
    local a = ns.Col and ns.Col("accent") or { r = 1, g = 0.82, b = 0 }
    local picked = S.view and S.view.area == box.areaKey
    local hover = state and state.hover
    box.fill:SetColorTexture(a.r, a.g, a.b, (picked or hover) and 0.45 or 0.22)
end

local function Refresh(box)
    if ns.MoverKit and rawget(box, "_zMover") then ns.MoverKit.Refresh(box) else Paint(box) end
end

-- the area's numbers (bottom-left corner from the middle of the screen),
-- the same ones the Areas tab shows; live while the box is dragged
local function Coords(box)
    local x, y
    if rawget(box, "_zDragging") then
        local cx, cy = UIParent:GetCenter()
        local left, bottom = box:GetLeft(), box:GetBottom()
        if cx and left then x, y = Round(left - cx), Round(bottom - cy) end
    end
    if not x then
        local a = S.Area(box.areaKey)
        if not a then return nil end
        x, y = tonumber(a.x) or 0, tonumber(a.y) or 0
    end
    return ("%d, %d   %d x %d"):format(x, y, Round(box:GetWidth() or 0), Round(box:GetHeight() or 0))
end

local function Place(box)
    local key = box.areaKey
    local a = S.Area(key)
    if not a then
        box:Hide()
        return
    end
    local x, y = tonumber(a.x) or 0, tonumber(a.y) or 0
    box:ClearAllPoints()
    box:SetPoint("BOTTOMLEFT", UIParent, "CENTER", x, y)
    box:SetSize(math.max(10, tonumber(a.w) or 40), math.max(10, tonumber(a.h) or 40))
    Refresh(box)
end

local function Dropped(box)
    box:StopMovingOrSizing()
    local cx, cy = UIParent:GetCenter()
    local left, bottom = box:GetLeft(), box:GetBottom()
    if not (cx and cy and left and bottom) then return end
    local a = S.Area(box.areaKey)
    if not a then return end
    a.x = Round(left - cx)
    a.y = Round(bottom - cy)
    -- re-reads every area and puts every box back on its numbers
    S.Rebuild()
    if ns.ConfigIsOpen and ns.ConfigIsOpen() and ns.RefreshConfig then ns.RefreshConfig() end
end

local function Nudge(box, dx, dy)
    local a = S.Area(box.areaKey)
    if not a then return end
    a.x = (tonumber(a.x) or 0) + dx
    a.y = (tonumber(a.y) or 0) + dy
    S.Rebuild()
    if ns.ConfigIsOpen and ns.ConfigIsOpen() and ns.RefreshConfig then ns.RefreshConfig() end
end

local function Build(key)
    local box = CreateFrame("Frame", nil, UIParent)
    box.areaKey = key
    -- Above ZacUI's own windows (DIALOG): with the config window in the
    -- middle of the screen, the boxes for the usual areas either side
    -- of your character are otherwise behind it and cannot be reached.
    box:SetFrameStrata("FULLSCREEN")
    -- Not clamped to the screen: a clamped frame is nudged back on screen
    -- even when placed by its numbers, and the box would then lie about
    -- where an area that runs off the edge really is.
    box.fill = box:CreateTexture(nil, "BACKGROUND")
    box.fill._zui_own = true
    box.fill:SetAllPoints()
    -- ZacUI's handle kit: the name outside the box when it is too small to
    -- hold it, the numbers on hover / while dragging, arrow keys and the
    -- wheel nudge, right-click puts the area back where it started
    if ns.MoverKit then
        ns.MoverKit.Dress(box, {
            label = function(self) return S.AreaName(self.areaKey) end,
            coords = Coords,
            paint = Paint,
            dragStop = Dropped,
            nudge = function(dx, dy, self) Nudge(self, dx, dy) end,
            reset = function(self) if S.ResetAreaPosition then S.ResetAreaPosition(self.areaKey) end end,
            -- a click makes it the area the page is editing
            click = function(self)
                S.view = S.view or {}
                if S.view.area == self.areaKey then return end
                S.view.area = self.areaKey
                for _, other in pairs(boxes) do Refresh(other) end
                if ns.ConfigIsOpen and ns.ConfigIsOpen() and ns.RefreshConfig then ns.RefreshConfig() end
            end,
            clamp = false,
        })
        box.label = box._zLabel
    end
    box:Hide()
    boxes[key] = box
    return box
end

local function Sync()
    for key, box in pairs(boxes) do
        if not ((pageShown or editWanted[key]) and S.Area(key)) then box:Hide() end
    end
    local function Up(key)
        local box = boxes[key] or Build(key)
        Place(box)
        box:Show()
    end
    if pageShown then
        for _, area in ipairs(S.Areas()) do Up(area.key) end
    end
    for key in pairs(editWanted) do
        if S.Area(key) then Up(key) else editWanted[key] = nil end
    end
end

-- Called after any change to the areas: new ones get a box, deleted
-- ones lose theirs, and every box goes back to its numbers.
function S.RefreshMovers()
    Sync()
end

function S.MoversShown()
    return pageShown
end

-- The page's boxes belong to the Areas tab. Leave the tab, the page or
-- the window and they go: a box left on screen with nothing in sight to
-- explain it is the kind of thing that gets reported as a bug.
local function OnAreasTab()
    if not (ns.ConfigIsOpen and ns.ConfigIsOpen()) then return false end
    local state = ns.ConfigState and ns.ConfigState()
    if not state then return true end
    return state.selected == "sbt" and state.tabs ~= nil and state.tabs.sbt == "areas"
end

function S.ShowMovers(on)
    pageShown = on and true or false
    if watch then
        watch:Cancel()
        watch = nil
    end
    if pageShown and C_Timer and C_Timer.NewTicker then
        watch = C_Timer.NewTicker(0.5, function()
            if not OnAreasTab() then S.ShowMovers(false) end
        end)
    end
    Sync()
end


-- ============================================================
-- EDIT MODE - one movable per scroll area, alongside everything else
-- ZacUI can place.
-- ============================================================
ns.EditModeProviders = ns.EditModeProviders or {}
ns.EditModeProviders[#ns.EditModeProviders + 1] = function()
    local list = {}
    for _, area in ipairs(S.Areas()) do
        local key = area.key
        list[#list + 1] = {
            key = "sbt_" .. key,
            label = "Scrolling text: " .. area.name,
            show = function()
                editWanted[key] = true
                Sync()
            end,
            hide = function()
                editWanted[key] = nil
                Sync()
            end,
            reset = function() S.ResetAreaPosition(key) end,
            frames = function()
                local box = boxes[key]
                return box and { box } or nil
            end,
        }
    end
    return list
end
