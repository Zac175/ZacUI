-- QoL_RaidPerf - automatic raid performance mode. Zoning into a raid
-- instance lowers the purely cosmetic graphics cvars; zoning out puts
-- back exactly what you had. Part of ZacUI; load order is set by the TOC.
--
-- THE VISIBILITY CONTRACT. Nothing here can hide a mechanic:
--   * projectedTextures is FORCED ON while active - that cvar is ground
--     markers (void zones, fire). If it was somehow off, raids turn it on.
--   * particle density, spell effects, view distance, nameplates, fog:
--     untouched. Only shadows, SSAO/depth, water, reflections, ground
--     clutter, and weather go down - none of which encode information.
--
-- RELOAD HONESTY. Originals are persisted in ZacUIDB before the first
-- write, with an `active` flag beside them. A /reload or crash inside
-- the raid does NOT re-save (the flag is still up, so the lowered
-- values are never captured as "originals"), and a login back in
-- Ironforge after a crash still restores from the persisted set.
--
-- CVAR HONESTY, same contract as QoL_Core: every name is existence-
-- checked through C_CVar at apply time. A build that lacks one skips
-- it; the applied count is printed so a silent skip is visible.

local ADDON_NAME = ...
-- Zacui_QoL is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local Print = ns.Print
local QoL = ns.QoL

local DB = QoL.DB

-- ============================================================
-- THE PRESET - name, raid value, and the label the chat line uses.
-- Order is the print order. Values are strings: that is what GetCVar
-- returns and what the restore writes back.
-- ============================================================
local PRESET = {
    { "shadowMode",          "0",  "shadows" },
    { "ssao",                "0",  "SSAO" },
    { "depthBasedOpacity",   "0",  "depth effects" },
    { "liquidDetail",        "0",  "water" },
    { "rippleDetail",        "0",  "ripples" },
    { "reflectionMode",      "0",  "reflections" },
    { "refraction",          "0",  "refraction" },
    { "sunShafts",           "0",  "sunshafts" },
    { "weatherDensity",      "0",  "weather" },
    { "groundEffectDensity", "16", "ground clutter" },
    { "groundEffectDist",    "70", nil },  -- rides the clutter label
    { "projectedTextures",   "1",  nil },  -- forced ON, never advertised as a cut
}

-- ============================================================
-- CVAR ACCESS - guarded, existence-checked. GetCVar on a name this
-- build does not know returns nil (or errors, on some builds); either
-- way the answer is "skip it".
-- ============================================================
local function ReadCVar(name)
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    if not get then return nil end
    local ok, v = pcall(get, name)
    if ok and v ~= nil then return tostring(v) end
    return nil
end

local function WriteCVar(name, value)
    -- SETUP2: through ns.CVar (recorded; put back when Quality of life is off)
    if ns.CVar then ns.CVar.Set(name, value, "qol") else pcall(SetCVar, name, value) end
end

-- ============================================================
-- STATE - lives in the QoL table of ZacUIDB so it survives /reload.
--   enabled : the config toggle
--   active  : the preset is currently applied (originals are held)
--   saved   : name -> original string value
-- Nil-filled, never rev-wiped: adding this must not reset his QoL page.
-- ============================================================
local function State()
    local d = DB()
    if d.raidPerf == nil then
        d.raidPerf = { enabled = true, active = false, saved = {} }
    end
    d.raidPerf.saved = d.raidPerf.saved or {}
    return d.raidPerf
end
QoL.RaidPerfState = State

local function Apply(st)
    local labels, applied = {}, 0
    for _, row in ipairs(PRESET) do
        local name, value, label = row[1], row[2], row[3]
        local current = ReadCVar(name)
        if current ~= nil then
            -- save first, write second - and only save on the FIRST
            -- apply (st.saved may already hold a persisted original)
            if st.saved[name] == nil then st.saved[name] = current end
            if current ~= value then WriteCVar(name, value) end
            applied = applied + 1
            if label then labels[#labels + 1] = label end
        end
    end
    st.active = true
    Print("raid performance on - " .. applied .. " settings lowered ("
        .. table.concat(labels, ", ") .. "). Ground markers stay on; "
        .. "everything restores when you leave.")
end

local function Restore(st)
    local restored = 0
    for name, original in pairs(st.saved) do
        WriteCVar(name, original)
        restored = restored + 1
    end
    wipe(st.saved)
    st.active = false
    if restored > 0 then
        Print("raid performance off - your " .. restored
            .. " graphics settings are back.")
    end
end

-- ============================================================
-- EVALUATE - the one decision, shared by the zone event and the
-- config toggle: preset up exactly when (module on, toggle on, in a
-- raid instance), otherwise down. Idempotent by the `active` flag.
-- ============================================================
local function Evaluate()
    local st = State()
    -- module off (or standing down for Leatrix): never apply, but a
    -- held preset still restores - lowered settings must not outlive
    -- the module that lowered them.
    if not QoL.enabled then
        if st.active then Restore(st) end
        return
    end
    local shouldBeActive = st.enabled and ns.InRaidInstance()
    if shouldBeActive and not st.active then
        Apply(st)
    elseif not shouldBeActive and st.active then
        Restore(st)
    end
end
QoL.RaidPerfRefresh = Evaluate

-- PLAYER_ENTERING_WORLD covers every path in and out: login, /reload,
-- the instance portal, hearthing, being summoned. At login it fires
-- after PLAYER_LOGIN, so QoL.enabled is already settled by ApplyAll.
local zoneFrame = CreateFrame("Frame")
zoneFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
zoneFrame:SetScript("OnEvent", Evaluate)
