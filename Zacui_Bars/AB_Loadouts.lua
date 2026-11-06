-- AB_Loadouts - what is ON the bars: every action slot, your macros,
-- your key bindings and the pet bar, saved under a name, moved between
-- characters and accounts as a string, and put back on a character
-- automatically when it logs in. Replaces Myslot, and reads Myslot's own
-- export strings so nothing already saved is lost.
-- Part of ZacUI; load order is set by the TOC.
--
-- A LOADOUT is plain data: slots keyed by action id (spell / item /
-- macro / equipment set / empty), the macros those slots point at (by
-- name + body, never by index - indices change the moment a macro is
-- added), every binding command with its keys, and the pet bar. Applying
-- one is the same sequence Myslot used, because it is the only sequence
-- that works with the client's drag-and-drop API: macros first (found
-- by name and body, created if missing, in the pool they came from),
-- then each slot picked up and placed, then slots the loadout does not
-- mention emptied (optional), then keys, then the pet bar. Spells the
-- character has not learned yet are skipped and listed; running the
-- loadout again later fills them in.
--
-- SECURITY. A Myslot string is binary (base64 of a protobuf message with
-- a CRC in front); the reader below is a hand-written, bounds-checked
-- decoder that only ever produces data - nothing in a string is executed.
-- ZacUI's own strings go through Core_Profiles' parser for the same
-- reason. Everything that touches the bars is a protected write and runs
-- out of combat only; an apply asked for in combat waits for the fight
-- to end.

local ADDON_NAME = ...
-- Zacui_Bars is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local AB = ns.Bars
local Print = ns.Print
local Profiles = ns.Profiles

local LO = {}
ns.Loadouts = LO

local CLASS = select(2, UnitClass("player"))
local MAX_SLOTS = 120
local PREFIX = "ZacUILoadout"

-- ============================================================
-- MYSLOT KEY TABLES (its wire codes -> the client's names)
-- ============================================================
local MS_BINDS = {
    [1]="MOVEANDSTEER",[2]="MOVEFORWARD",[3]="MOVEBACKWARD",[4]="TURNLEFT",[5]="TURNRIGHT",
    [6]="STRAFELEFT",[7]="STRAFERIGHT",[8]="JUMP",[9]="SITORSTAND",[10]="TOGGLESHEATH",
    [11]="TOGGLEAUTORUN",[12]="PITCHUP",[13]="PITCHDOWN",[14]="TOGGLERUN",[15]="FOLLOWTARGET",
    [16]="OPENCHAT",[17]="OPENCHATSLASH",[18]="CHATPAGEUP",[19]="CHATPAGEDOWN",
    [20]="CHATBOTTOM",[21]="REPLY",[22]="REPLY2",[23]="COMBATLOGPAGEUP",
    [24]="COMBATLOGPAGEDOWN",[25]="COMBATLOGBOTTOM",[26]="ACTIONBUTTON1",[27]="ACTIONBUTTON2",
    [28]="ACTIONBUTTON3",[29]="ACTIONBUTTON4",[30]="ACTIONBUTTON5",[31]="ACTIONBUTTON6",
    [32]="ACTIONBUTTON7",[33]="ACTIONBUTTON8",[34]="ACTIONBUTTON9",[35]="ACTIONBUTTON10",
    [36]="ACTIONBUTTON11",[37]="ACTIONBUTTON12",[38]="SHAPESHIFTBUTTON1",
    [39]="SHAPESHIFTBUTTON2",[40]="SHAPESHIFTBUTTON3",[41]="SHAPESHIFTBUTTON4",
    [42]="SHAPESHIFTBUTTON5",[43]="SHAPESHIFTBUTTON6",[44]="SHAPESHIFTBUTTON7",
    [45]="SHAPESHIFTBUTTON8",[46]="SHAPESHIFTBUTTON9",[47]="SHAPESHIFTBUTTON10",
    [48]="BONUSACTIONBUTTON1",[49]="BONUSACTIONBUTTON2",[50]="BONUSACTIONBUTTON3",
    [51]="BONUSACTIONBUTTON4",[52]="BONUSACTIONBUTTON5",[53]="BONUSACTIONBUTTON6",
    [54]="BONUSACTIONBUTTON7",[55]="BONUSACTIONBUTTON8",[56]="BONUSACTIONBUTTON9",
    [57]="BONUSACTIONBUTTON10",[58]="ACTIONPAGE1",[59]="ACTIONPAGE2",[60]="ACTIONPAGE3",
    [61]="ACTIONPAGE4",[62]="ACTIONPAGE5",[63]="ACTIONPAGE6",[64]="PREVIOUSACTIONPAGE",
    [65]="NEXTACTIONPAGE",[66]="TOGGLEACTIONBARLOCK",[67]="TOGGLEAUTOSELFCAST",
    [68]="MULTICASTSUMMONBUTTON1",[69]="MULTICASTACTIONBUTTON1",[70]="MULTICASTACTIONBUTTON2",
    [71]="MULTICASTACTIONBUTTON3",[72]="MULTICASTACTIONBUTTON4",[73]="MULTICASTSUMMONBUTTON2",
    [74]="MULTICASTACTIONBUTTON5",[75]="MULTICASTACTIONBUTTON6",[76]="MULTICASTACTIONBUTTON7",
    [77]="MULTICASTACTIONBUTTON8",[78]="MULTICASTSUMMONBUTTON3",[79]="MULTICASTACTIONBUTTON9",
    [80]="MULTICASTACTIONBUTTON10",[81]="MULTICASTACTIONBUTTON11",
    [82]="MULTICASTACTIONBUTTON12",[83]="MULTICASTRECALLBUTTON1",[84]="TARGETNEARESTENEMY",
    [85]="TARGETPREVIOUSENEMY",[86]="TARGETNEARESTFRIEND",[87]="TARGETPREVIOUSFRIEND",
    [88]="TARGETNEARESTENEMYPLAYER",[89]="TARGETPREVIOUSENEMYPLAYER",
    [90]="TARGETNEARESTFRIENDPLAYER",[91]="TARGETPREVIOUSFRIENDPLAYER",[92]="TARGETSELF",
    [93]="TARGETPARTYMEMBER1",[94]="TARGETPARTYMEMBER2",[95]="TARGETPARTYMEMBER3",
    [96]="TARGETPARTYMEMBER4",[97]="TARGETPET",[98]="TARGETPARTYPET1",[99]="TARGETPARTYPET2",
    [100]="TARGETPARTYPET3",[101]="TARGETPARTYPET4",[102]="TARGETLASTHOSTILE",
    [103]="TARGETLASTTARGET",[104]="NAMEPLATES",[105]="FRIENDNAMEPLATES",[106]="ALLNAMEPLATES",
    [107]="INTERACTMOUSEOVER",[108]="INTERACTTARGET",[109]="ASSISTTARGET",[110]="ATTACKTARGET",
    [111]="STARTATTACK",[112]="PETATTACK",[113]="FOCUSTARGET",[114]="TARGETFOCUS",
    [115]="TARGETMOUSEOVER",[116]="TARGETTALKER",[117]="TOGGLECHARACTER0",
    [118]="TOGGLEBACKPACK",[119]="TOGGLEBAG1",[120]="TOGGLEBAG2",[121]="TOGGLEBAG3",
    [122]="TOGGLEBAG4",[123]="OPENALLBAGS",[124]="TOGGLEKEYRING",[125]="TOGGLESPELLBOOK",
    [126]="TOGGLEPROFESSIONBOOK",[127]="TOGGLEPETBOOK",[128]="TOGGLEINSCRIPTION",
    [129]="TOGGLETALENTS",[130]="TOGGLECHARACTER4",[131]="TOGGLECHARACTER3",
    [132]="TOGGLECHARACTER2",[133]="TOGGLEQUESTLOG",[134]="TOGGLEGAMEMENU",
    [135]="TOGGLEMINIMAP",[136]="TOGGLEWORLDMAP",[137]="TOGGLEWORLDMAPSIZE",
    [138]="TOGGLESOCIAL",[139]="TOGGLEFRIENDSTAB",[140]="TOGGLEWHOTAB",[141]="TOGGLEGUILDTAB",
    [142]="TOGGLECHATTAB",[143]="TOGGLERAIDTAB",[144]="TOGGLELFGPARENT",[145]="TOGGLELFRPARENT",
    [146]="TOGGLEWORLDSTATESCORES",[147]="TOGGLEBATTLEFIELDMINIMAP",
    [148]="TOGGLEMINIMAPROTATION",[149]="TOGGLECHANNELPULLOUT",[150]="TOGGLEACHIEVEMENT",
    [151]="TOGGLESTATISTICS",[152]="TOGGLECURRENCY",[153]="STOPCASTING",[154]="STOPATTACK",
    [155]="DISMOUNT",[156]="MINIMAPZOOMIN",[157]="MINIMAPZOOMOUT",[158]="TOGGLEMUSIC",
    [159]="TOGGLESOUND",[160]="MASTERVOLUMEUP",[161]="MASTERVOLUMEDOWN",[162]="TOGGLESELFMUTE",
    [163]="TOGGLEUI",[164]="TOGGLEFPS",[165]="SCREENSHOT",[166]="TOGGLESTATS",
    [167]="TOGGLETRIS",[168]="TOGGLEPORTALS",[169]="TOGGLECOLLISION",
    [170]="TOGGLECOLLISIONDISPLAY",[171]="TOGGLEPLAYERBOUNDS",[172]="TOGGLEPERFORMANCEDISPLAY",
    [173]="TOGGLEPERFORMANCEPAUSE",[174]="TOGGLEPERFORMANCEVALUES",
    [175]="RESETPERFORMANCEVALUES",[176]="TOGGLEANIMKITDISPLAY",[177]="TOGGLECOMMENTATOR",
    [178]="NEXTVIEW",[179]="PREVVIEW",[180]="CAMERAZOOMIN",[181]="CAMERAZOOMOUT",
    [182]="SETVIEW1",[183]="SETVIEW2",[184]="SETVIEW3",[185]="SETVIEW4",[186]="SETVIEW5",
    [187]="SAVEVIEW1",[188]="SAVEVIEW2",[189]="SAVEVIEW3",[190]="SAVEVIEW4",[191]="SAVEVIEW5",
    [192]="RESETVIEW1",[193]="RESETVIEW2",[194]="RESETVIEW3",[195]="RESETVIEW4",
    [196]="RESETVIEW5",[197]="FLIPCAMERAYAW",[198]="MULTIACTIONBAR1BUTTON1",
    [199]="MULTIACTIONBAR1BUTTON2",[200]="MULTIACTIONBAR1BUTTON3",
    [201]="MULTIACTIONBAR1BUTTON4",[202]="MULTIACTIONBAR1BUTTON5",
    [203]="MULTIACTIONBAR1BUTTON6",[204]="MULTIACTIONBAR1BUTTON7",
    [205]="MULTIACTIONBAR1BUTTON8",[206]="MULTIACTIONBAR1BUTTON9",
    [207]="MULTIACTIONBAR1BUTTON10",[208]="MULTIACTIONBAR1BUTTON11",
    [209]="MULTIACTIONBAR1BUTTON12",[210]="MULTIACTIONBAR2BUTTON1",
    [211]="MULTIACTIONBAR2BUTTON2",[212]="MULTIACTIONBAR2BUTTON3",
    [213]="MULTIACTIONBAR2BUTTON4",[214]="MULTIACTIONBAR2BUTTON5",
    [215]="MULTIACTIONBAR2BUTTON6",[216]="MULTIACTIONBAR2BUTTON7",
    [217]="MULTIACTIONBAR2BUTTON8",[218]="MULTIACTIONBAR2BUTTON9",
    [219]="MULTIACTIONBAR2BUTTON10",[220]="MULTIACTIONBAR2BUTTON11",
    [221]="MULTIACTIONBAR2BUTTON12",[222]="MULTIACTIONBAR3BUTTON1",
    [223]="MULTIACTIONBAR3BUTTON2",[224]="MULTIACTIONBAR3BUTTON3",
    [225]="MULTIACTIONBAR3BUTTON4",[226]="MULTIACTIONBAR3BUTTON5",
    [227]="MULTIACTIONBAR3BUTTON6",[228]="MULTIACTIONBAR3BUTTON7",
    [229]="MULTIACTIONBAR3BUTTON8",[230]="MULTIACTIONBAR3BUTTON9",
    [231]="MULTIACTIONBAR3BUTTON10",[232]="MULTIACTIONBAR3BUTTON11",
    [233]="MULTIACTIONBAR3BUTTON12",[234]="MULTIACTIONBAR4BUTTON1",
    [235]="MULTIACTIONBAR4BUTTON2",[236]="MULTIACTIONBAR4BUTTON3",
    [237]="MULTIACTIONBAR4BUTTON4",[238]="MULTIACTIONBAR4BUTTON5",
    [239]="MULTIACTIONBAR4BUTTON6",[240]="MULTIACTIONBAR4BUTTON7",
    [241]="MULTIACTIONBAR4BUTTON8",[242]="MULTIACTIONBAR4BUTTON9",
    [243]="MULTIACTIONBAR4BUTTON10",[244]="MULTIACTIONBAR4BUTTON11",
    [245]="MULTIACTIONBAR4BUTTON12",[246]="RAIDTARGET1",[247]="RAIDTARGET2",[248]="RAIDTARGET3",
    [249]="RAIDTARGET4",[250]="RAIDTARGET5",[251]="RAIDTARGET6",[252]="RAIDTARGET7",
    [253]="RAIDTARGET8",[254]="RAIDTARGETNONE",[255]="VEHICLEEXIT",[256]="VEHICLEPREVSEAT",
    [257]="VEHICLENEXTSEAT",[258]="VEHICLEAIMUP",[259]="VEHICLEAIMDOWN",
    [260]="VEHICLEAIMINCREMENT",[261]="VEHICLEAIMDECREMENT",[262]="VEHICLECAMERAZOOMIN",
    [263]="VEHICLECAMERAZOOMOUT",[264]="TURNORACTION",[265]="CAMERAORSELECTORMOVE",
    [266]="ITUNES_PLAYPAUSE",[267]="ITUNES_NEXTTRACK",[268]="ITUNES_BACKTRACK",
    [269]="ITUNES_VOLUMEUP",[270]="ITUNES_VOLUMEDOWN",[271]="MOVIE_RECORDING_STARTSTOP",
    [272]="MOVIE_RECORDING_CANCEL",[273]="MOVIE_RECORDING_COMPRESS",[274]="MOVIE_RECORDING_GUI",
    [275]="HEADER_MOVEMENT",[276]="HEADER_CHAT",[277]="HEADER_ACTIONBAR",
    [278]="HEADER_MULTICASTFUNCTIONS",[279]="HEADER_BLANK",[280]="HEADER_BLANK2",
    [281]="HEADER_BLANK3",[282]="HEADER_TARGETING",[283]="HEADER_INTERFACE",[284]="HEADER_MISC",
    [285]="HEADER_CAMERA",[286]="HEADER_MULTIACTIONBAR",[287]="HEADER_BLANK4",
    [288]="HEADER_BLANK5",[289]="HEADER_BLANK6",[290]="HEADER_RAID_TARGET",
    [291]="HEADER_VEHICLE",[292]="HEADER_ITUNES_REMOTE",[293]="HEADER_MOVIE_RECORDING_SECTION",
    [294]="TOGGLEENCOUNTERJOURNAL",[295]="TARGETNEAREST",[296]="TARGETPREVIOUS",
    [297]="EXTRAACTIONBUTTON1",[298]="TARGETARENA1",[299]="TARGETARENA2",[300]="TARGETARENA3",
    [301]="TARGETARENA4",[302]="TARGETARENA5",[303]="FOCUSARENA1",[304]="FOCUSARENA2",
    [305]="FOCUSARENA3",[306]="FOCUSARENA4",[307]="FOCUSARENA5",[308]="TOGGLECOREABILITIESBOOK",
    [309]="TOGGLEGROUPFINDER",[310]="TOGGLEDUNGEONSANDRAIDS",[311]="TOGGLECOLLECTIONS",
    [312]="TOGGLECOLLECTIONSMOUNTJOURNAL",[313]="TOGGLECOLLECTIONSPETJOURNAL",
    [314]="TOGGLECOLLECTIONSTOYBOX",[315]="TOGGLEGARRISONLANDINGPAGE",
    [316]="ITEMCOMPARISONCYCLING",[317]="TOGGLEGRAPHICSSETTINGS",
}
local MS_KEYS = {
    [0]="KEYCODE",[1]="F1",[2]="F2",[3]="F3",[4]="F4",[5]="F5",[6]="F6",[7]="F7",[8]="F8",
    [9]="F9",[10]="F10",[11]="F11",[12]="F12",[13]="F13",[14]="BUTTON1",[15]="BUTTON2",
    [16]="BUTTON3",[17]="BUTTON4",[18]="BUTTON5",[19]="BUTTON6",[20]="BUTTON7",[21]="BUTTON8",
    [22]="BUTTON9",[23]="BUTTON10",[24]="BUTTON11",[25]="BUTTON12",[26]="BUTTON13",
    [27]="BUTTON14",[28]="BUTTON15",[29]="BUTTON16",[30]="BUTTON17",[31]="BUTTON18",
    [32]="BUTTON19",[33]="BUTTON20",[34]="BUTTON21",[35]="BUTTON22",[36]="BUTTON23",
    [37]="BUTTON24",[38]="BUTTON25",[39]="BUTTON26",[40]="BUTTON27",[41]="BUTTON28",
    [42]="BUTTON29",[43]="BUTTON30",[44]="BUTTON31",[45]="NUMPAD0",[46]="NUMPAD1",
    [47]="NUMPAD2",[48]="NUMPAD3",[49]="NUMPAD4",[50]="NUMPAD5",[51]="NUMPAD6",[52]="NUMPAD7",
    [53]="NUMPAD8",[54]="NUMPAD9",[55]="0",[56]="1",[57]="2",[58]="3",[59]="4",[60]="5",
    [61]="6",[62]="7",[63]="8",[64]="9",[65]="A",[66]="B",[67]="C",[68]="D",[69]="E",[70]="F",
    [71]="G",[72]="H",[73]="I",[74]="J",[75]="K",[76]="L",[77]="M",[78]="N",[79]="O",[80]="P",
    [81]="Q",[82]="R",[83]="S",[84]="T",[85]="U",[86]="V",[87]="W",[88]="X",[89]="Y",[90]="Z",
    [91]="`",[92]="-",[93]="=",[94]="[",[95]="]",[96]=";",[97]="'",[98]="\\\\",[99]=",",
    [100]=".",[101]="/",[102]="CAPSLOCK",[103]="NUMLOCK",[104]="PAGEDOWN",[105]="PAGEUP",
    [106]="END",[107]="HOME",[108]="DELETE",[109]="INSERT",[110]="DOWN",[111]="RIGHT",
    [112]="UP",[113]="LEFT",[114]="TAB",[115]="BACKSPACE",[116]="ENTER",[117]="ESCAPE",
    [118]="NUMPAD",[119]="NUMPADEQUALS",[120]="NUMPADDECIMAL",[121]="NUMPADDIVIDE",
    [122]="NUMPADMULTIPLY",[123]="NUMPADMINUS",[124]="NUMPADPLUS",[125]="SPACE",
    [126]="MOUSEWHEELUP",[127]="MOUSEWHEELDOWN",[128]="SHIFT",[129]="PRINTSCREEN",
}
local MS_MODS = {
    [0]="NONE",[1]="SHIFT",[2]="CTRL",[3]="ALT",[4]="META",[100]="SHIFT-CTRL",[101]="SHIFT-ALT",
    [106]="CTRL-ALT",[107]="CTRL-SHIFT",[108]="ALT-CTRL",[109]="ALT-SHIFT",
    [110]="ALT-CTRL-SHIFT",[111]="ALT-SHIFT-CTRL",[112]="CTRL-ALT-SHIFT",[113]="CTRL-SHIFT-ALT",
    [114]="SHIFT-ALT-CTRL",[115]="SHIFT-CTRL-ALT",[116]="ALT-META",[117]="CTRL-META",
    [118]="SHIFT-META",[119]="ALT-CTRL-META",[120]="ALT-SHIFT-META",[121]="CTRL-SHIFT-META",
    [255]="CUSTOM",
}

local MS_TYPE = { [1] = "spell", [2] = "item", [3] = "macro", [4] = "flyout", [5] = "empty",
                  [6] = "equipmentset", [7] = "summonpet", [8] = "companion", [9] = "summonmount" }
local MS_CUSTOM_BIND = 65535

-- ============================================================
-- STORE
-- ============================================================
function LO.DB()
    ZacUIDB.loadouts = ZacUIDB.loadouts or {}
    return ZacUIDB.loadouts
end

function LO.Rules()
    ZacUIDB.loadoutRules = ZacUIDB.loadoutRules or {}
    local r = ZacUIDB.loadoutRules
    r.byClass = r.byClass or {}
    if r.mode == nil then r.mode = "always" end       -- always | once | off
    if r.clearSlots == nil then r.clearSlots = true end
    if r.clearBinds == nil then r.clearBinds = false end
    return r
end

function LO.List()
    local names = {}
    for name in pairs(LO.DB()) do names[#names + 1] = name end
    table.sort(names)
    return names
end

function LO.Get(name) return LO.DB()[name] end

function LO.Save(name, loadout)
    if not name or name == "" then return false, "give the loadout a name" end
    loadout = loadout or LO.Capture()
    loadout.name = name
    loadout.rev = (LO.DB()[name] and LO.DB()[name].rev or 0) + 1
    LO.DB()[name] = loadout
    return true
end

function LO.Delete(name)
    if not LO.DB()[name] then return false, "no such loadout" end
    LO.DB()[name] = nil
    local r = LO.Rules()
    for class, n in pairs(r.byClass) do if n == name then r.byClass[class] = nil end end
    if r.all == name then r.all = nil end
    if ZacUICharDB and ZacUICharDB.loadout and ZacUICharDB.loadout.name == name then
        ZacUICharDB.loadout = nil
    end
    return true
end

function LO.Rename(from, to)
    local db = LO.DB()
    if not db[from] then return false, "no such loadout" end
    if not to or to == "" then return false, "give the loadout a name" end
    if db[to] then return false, "'" .. to .. "' already exists" end
    db[to], db[from] = db[from], nil
    db[to].name = to
    local r = LO.Rules()
    for class, n in pairs(r.byClass) do if n == from then r.byClass[class] = to end end
    if r.all == from then r.all = to end
    if ZacUICharDB and ZacUICharDB.loadout and ZacUICharDB.loadout.name == from then
        ZacUICharDB.loadout.name = to
    end
    return true
end

-- ============================================================
-- MACROS
-- ============================================================
local function Unify(body)
    body = tostring(body or ""):gsub("\r", "")
    return (body:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function MacroLimits()
    local acc = tonumber(_G.MAX_ACCOUNT_MACROS) or 120
    local chr = tonumber(_G.MAX_CHARACTER_MACROS) or 18
    return acc, chr
end

-- A body without the buff remover's lines (a "#ZB" or "#ZacUIBuffs" line
-- and the /click lines under it): those differ character to character,
-- so two copies of the same macro only match without them.
local function Core(body)
    body = Unify(body)
    local cut = body:find("\n#ZB", 1, true) or body:find("\n#ZacUIBuffs", 1, true)
    if body:sub(1, 3) == "#ZB" or body:sub(1, 11) == "#ZacUIBuffs" then cut = 1 end
    if cut then body = body:sub(1, cut - 1) end
    return Unify(body)
end
LO.MacroCore = Core

-- A macro another module writes (the smart mount macro, QoL_SmartMount):
-- a loadout matches it by name without regard to case, never rewrites
-- its text, and makes it with the owner's text when it is missing.
--   LO.OwnMacro(isMine(name) -> bool, body() -> string)
local owners = {}
function LO.OwnMacro(isMine, body) owners[#owners + 1] = { isMine = isMine, body = body } end
local function Owner(name)
    for _, o in ipairs(owners) do if o.isMine(name) then return o end end
end

-- The macros on this character, indexed once per change of the macro
-- list (ZacUI's ns.Macros says when: its Version moves on UPDATE_MACROS,
-- on login and whenever this file creates or edits one and calls
-- Invalidate). Bodies are read here - ns.Macros keeps names only.
local macroIndex = { version = nil }
local function MacroIndex()
    local M = ns.Macros
    local v = M.Version()
    if macroIndex.version == v then return macroIndex end
    local acc, chr = MacroLimits()
    local names = M.Names()
    local list, byBoth, byBody = {}, {}, {}
    for i = 1, acc + chr do
        if names[i] then
            local name, _, body = GetMacroInfo(i)
            if name then
                body = Core(body)
                list[#list + 1] = { i = i, name = name, lower = string.lower(name), char = i > acc }
                if not byBoth[name .. "\n" .. body] then byBoth[name .. "\n" .. body] = i end
                if not byBody[body] then byBody[body] = i end
            end
        end
    end
    macroIndex = { version = v, list = list, byBoth = byBoth, byBody = byBody }
    return macroIndex
end

-- name+body first, body alone second; the icon is never compared.
-- byName: then a macro of that name (in the pool the loadout's came from
-- first) - its body may differ, as one character's own version of it.
local function FindMacro(info, byName)
    local idx = MacroIndex()
    -- charOnly: this character's own copy (a macro made for its weapons) -
    -- never an account-wide one shared with another character
    if info.charOnly then
        local want = Core(info.body)
        for _, e in ipairs(idx.list) do
            if e.char and e.name == info.name then
                -- already that text: found as it is, nothing to rewrite
                local _, _, b = GetMacroInfo(e.i)
                return e.i, (Core(b) == want) and "both" or "name"
            end
        end
        return nil
    end
    local body = Core(info.body)
    local hit = idx.byBoth[(info.name or "") .. "\n" .. body]
    if hit then return hit, "both" end
    hit = idx.byBody[body]
    if hit then return hit, "body" end
    if not byName then return nil end
    local wantChar = info.perchar and true or false
    local owned = info.name and Owner(info.name) ~= nil
    local wantLower = owned and string.lower(info.name) or nil
    local named, namedOther
    for _, e in ipairs(idx.list) do
        if e.name == info.name or (owned and e.lower == wantLower) then
            if e.char == wantChar then named = named or e.i else namedOther = namedOther or e.i end
        end
    end
    hit = named or namedOther
    if hit then return hit, "name" end
    return nil
end

-- The macro FindOrCreateMacro last made: macros are kept sorted by name,
-- so every macro made moves the indexes of the ones after it, and the
-- ids handed out earlier in the same apply have to be looked up again.
local lastMade = {}

-- overwrite: a macro found by its NAME whose text differs is given the
-- loadout's text (its icon stays, and the buff remover's lines at its end
-- are kept so a linked macro keeps working). Returns id, made, rewritten.
-- overwrite "perchar": only a character macro is rewritten, never an
-- account-wide one (the caller's source shares those with this account).
local function FindOrCreateMacro(info, byName, overwrite)
    local found, how = FindMacro(info, byName)
    local owner = info.name and Owner(info.name)
    if owner then overwrite = false end
    if overwrite == "perchar" then overwrite = (found or 0) > (MacroLimits()) end
    if found and how == "name" and overwrite and EditMacro then
        local name, icon, body = GetMacroInfo(found)
        body = tostring(body or ""):gsub("\r", "")
        local cut = body:find("\n#ZB", 1, true) or body:find("\n#ZacUIBuffs", 1, true)
        local tail = cut and body:sub(cut) or ""
        local newBody = (Core(info.body) .. tail):sub(1, 255)
        if pcall(EditMacro, found, name, icon, newBody) then
            ns.Macros.Invalidate()
            return found, false, true
        end
        return found, false
    end
    if found then return found, false end
    local acc, chr = MacroLimits()
    local numGlobal, numPerChar = GetNumMacros()
    local wantPerChar = info.perchar and true or false
    local roomGlobal, roomPerChar = numGlobal < acc, numPerChar < chr
    local perChar
    if wantPerChar and roomPerChar then perChar = true
    elseif not wantPerChar and roomGlobal then perChar = false
    elseif roomPerChar then perChar = true
    elseif roomGlobal then perChar = false
    else return nil, "no room" end
    local icon = info.icon
    if type(icon) == "string" and tonumber(icon) then icon = tonumber(icon) end
    if icon == nil or icon == "" then icon = "INV_Misc_QuestionMark" end
    local name = tostring(info.name or "macro"):sub(1, 16)
    local body = Core(info.body):sub(1, 255)
    if owner and owner.body then
        local ob = owner.body()
        if type(ob) == "string" and ob ~= "" then body = ob:sub(1, 255) end
        perChar = false      -- the owner's macro is one per account
    end
    local ok, id = pcall(CreateMacro, name, icon, body, perChar)
    if not (ok and id) then
        -- an icon the client does not know: try the question mark
        ok, id = pcall(CreateMacro, name, "INV_Misc_QuestionMark", body, perChar)
    end
    if ok and id then
        ns.Macros.Invalidate()
        lastMade.name, lastMade.body, lastMade.char = name, Core(body), perChar and true or false
        return id, true
    end
    return nil, "create failed"
end

-- Where a macro this apply made sits now: its name in its pool, the body
-- it was made with breaking a tie.
local function WhereMade(made)
    local idx = MacroIndex()
    local first
    for _, e in ipairs(idx.list) do
        if e.name == made.name and e.char == made.char then
            first = first or e.i
            local _, _, body = GetMacroInfo(e.i)
            if Core(body) == made.body then return e.i end
        end
    end
    return first
end

-- ============================================================
-- CAPTURE
-- ============================================================
function LO.Capture(opts)
    opts = opts or {}
    local acc, chr = MacroLimits()
    local out = { v = 1, player = UnitName("player"), realm = GetRealmName(), class = CLASS,
                  level = UnitLevel("player"), time = time(), slots = {}, macros = {}, binds = {}, pet = {} }
    -- macros, by index, so slots can point at them
    local macroIndex = {}
    for i = 1, acc + chr do
        local name, icon, body = GetMacroInfo(i)
        if name then
            out.macros[#out.macros + 1] = { name = name, icon = icon, body = Unify(body), perchar = i > acc }
            macroIndex[i] = #out.macros
        end
    end
    for slot = 1, MAX_SLOTS do
        local kind, id, sub = GetActionInfo(slot)
        if kind == "spell" and id then
            out.slots[slot] = { t = "spell", id = id, name = GetSpellInfo(id) }
        elseif kind == "item" and id then
            out.slots[slot] = { t = "item", id = id }
        elseif kind == "macro" and id then
            if macroIndex[id] then out.slots[slot] = { t = "macro", m = macroIndex[id] } end
        elseif kind == "equipmentset" and id then
            out.slots[slot] = { t = "equipmentset", id = id }
        elseif kind == "companion" and id then
            out.slots[slot] = { t = "companion", id = id }
        end
    end
    if opts.binds ~= false then
        for i = 1, GetNumBindings() do
            local command = GetBinding(i)
            if command and not command:find("^HEADER_") then
                local keys = { GetBindingKey(command) }
                if #keys > 0 then out.binds[#out.binds + 1] = { cmd = command, keys = keys } end
            end
        end
    end
    if IsPetActive and IsPetActive() then
        for i = 1, (NUM_PET_ACTION_SLOTS or 10) do
            local name, _, isToken, _, _, _, spellID = GetPetActionInfo(i)
            if name then
                if isToken then out.pet[i] = { token = name } elseif spellID then out.pet[i] = { spell = spellID } end
            else
                out.pet[i] = { empty = true }
            end
        end
    end
    return out
end

-- ============================================================
-- APPLY
-- ============================================================
local function PlaceCursor(slot)
    if GetCursorInfo() then PlaceAction(slot) end
    ClearCursor()
end

local function SlotMatches(slot, want, macroIds)
    local kind, id = GetActionInfo(slot)
    if want.t == "empty" then return kind == nil end
    if want.t == "macro" then return kind == "macro" and id == macroIds[want.m] end
    if want.t == "equipmentset" then return kind == "equipmentset" and id == want.id end
    return kind == want.t and id == want.id
end

local function PickupSpellSmart(id, name)
    PickupSpell(id)
    if GetCursorInfo() then return true end
    local n = name or (GetSpellInfo(id))
    if n then PickupSpell(n) end
    return GetCursorInfo() ~= nil
end

-- The bar-slot commands: with trimKeys, one of these the loadout does
-- not list has no key at all. The stock names always; our buttons' own
-- CLICK names (bars 2 and 7-10 take their keys on those) only when the
-- loadout names at least one of them itself - proof its capture saw
-- them - or every key on those bars would come off and never go back.
local function IsBarCommand(cmd, withClick)
    return cmd:match("^ACTIONBUTTON%d+$") or cmd:match("^MULTIACTIONBAR%dBUTTON%d+$")
        or (withClick and cmd:match("^CLICK ZacUIActionButton%d+:")) or false
end

-- opts: slots, macros, binds, pet (default true), clearSlots, clearBinds
-- (default false), trimKeys (default false: the loadout's keys are the
-- whole set for the commands it lists - a key still on one of them that
-- the loadout does not name comes off, so a key moved from one button to
-- another does not stay on both - and a bar slot it does not list loses
-- its keys), quiet. Returns a report table.
function LO.Apply(loadout, opts)
    opts = opts or {}
    local rep = { placed = 0, cleared = 0, skipped = {}, macrosMade = 0, macrosRewritten = 0, keys = 0, waiting = false }
    if type(loadout) ~= "table" then rep.error = "not a loadout" return rep end
    if InCombatLockdown() then
        rep.waiting = true
        AB.AfterCombat("loadout", function()
            local r = LO.Apply(loadout, opts)
            if not opts.quiet then LO.Report(r, loadout.name) end
        end)
        return rep
    end
    local acc = MacroLimits()
    -- 1. macros
    local macroIds = {}
    if opts.macros ~= false then
        local madeAt = {}          -- k -> { name, body, char } for macros made here
        for k, m in ipairs(loadout.macros or {}) do
            local id, made, rewritten = FindOrCreateMacro(m, opts.macrosByName, opts.macrosOverwrite)
            if id then
                macroIds[k] = id
                if made == true then
                    rep.macrosMade = rep.macrosMade + 1
                    madeAt[k] = { name = lastMade.name, body = lastMade.body, char = lastMade.char }
                end
                if rewritten then rep.macrosRewritten = rep.macrosRewritten + 1 end
            else
                rep.skipped[#rep.skipped + 1] = "macro " .. tostring(m.name) .. " (" .. tostring(made) .. ")"
            end
        end
        -- every macro made moved the indexes after it: look them all up
        -- again before any slot is pointed at one
        if rep.macrosMade > 0 then
            for k, m in ipairs(loadout.macros or {}) do
                if macroIds[k] then
                    if madeAt[k] then
                        macroIds[k] = WhereMade(madeAt[k]) or macroIds[k]
                    else
                        macroIds[k] = FindMacro(m, opts.macrosByName) or macroIds[k]
                    end
                end
            end
        end
    else
        for k, m in ipairs(loadout.macros or {}) do macroIds[k] = FindMacro(m, opts.macrosByName) end
    end
    -- 2. slots
    local mentioned = {}
    if opts.slots ~= false then
        for slot, want in pairs(loadout.slots or {}) do
            slot = tonumber(slot)
            if slot and slot >= 1 and slot <= MAX_SLOTS then
                mentioned[slot] = true
                if not SlotMatches(slot, want, macroIds) then
                    ClearCursor()
                    local ok = false
                    if want.t == "spell" then
                        ok = PickupSpellSmart(want.id, want.name)
                        if not ok then rep.skipped[#rep.skipped + 1] = "spell " .. tostring(want.name or want.id) .. " (not learned)" end
                    elseif want.t == "item" then
                        PickupItem(want.id)
                        ok = GetCursorInfo() ~= nil
                        if not ok then rep.skipped[#rep.skipped + 1] = "item " .. tostring(want.id) .. " (not in bags)" end
                    elseif want.t == "macro" then
                        if macroIds[want.m] then PickupMacro(macroIds[want.m]) ok = GetCursorInfo() ~= nil end
                    elseif want.t == "equipmentset" then
                        if C_EquipmentSet and C_EquipmentSet.PickupEquipmentSet then
                            local setId = want.id
                            if type(setId) == "string" and C_EquipmentSet.GetEquipmentSetID then
                                setId = C_EquipmentSet.GetEquipmentSetID(setId)
                            end
                            if setId then C_EquipmentSet.PickupEquipmentSet(setId) ok = GetCursorInfo() ~= nil end
                        end
                    elseif want.t == "companion" then
                        PickupSpell(want.id)
                        ok = GetCursorInfo() ~= nil
                    elseif want.t == "empty" then
                        if GetActionInfo(slot) then PickupAction(slot) ClearCursor() rep.cleared = rep.cleared + 1 end
                    end
                    if ok then
                        PlaceCursor(slot)
                        rep.placed = rep.placed + 1
                    else
                        ClearCursor()
                    end
                end
            end
        end
        -- 3. the rest
        if opts.clearSlots then
            for slot = 1, MAX_SLOTS do
                if not mentioned[slot] and GetActionInfo(slot) then
                    PickupAction(slot)
                    ClearCursor()
                    rep.cleared = rep.cleared + 1
                end
            end
        end
    end
    -- 4. keys
    if opts.binds ~= false and loadout.binds and #loadout.binds > 0 then
        local cleared = false
        if opts.clearBinds then
            for i = 1, GetNumBindings() do
                local command = GetBinding(i)
                if command then
                    for _, key in ipairs({ GetBindingKey(command) }) do
                        SetBinding(key, nil)
                        cleared = true
                    end
                end
            end
        end
        if opts.trimKeys and not opts.clearBinds then
            local want, withClick = {}, false
            for _, b in ipairs(loadout.binds) do
                if b.cmd then
                    local set = want[b.cmd] or {}
                    for _, key in ipairs(b.keys or {}) do if key and key ~= "" then set[key] = true end end
                    want[b.cmd] = set
                    if b.cmd:match("^CLICK ZacUIActionButton%d+:") then withClick = true end
                end
            end
            for i = 1, GetNumBindings() do
                local command = GetBinding(i)
                local set = command and want[command]
                if command and (set or IsBarCommand(command, withClick)) then
                    for _, key in ipairs({ GetBindingKey(command) }) do
                        if not (set and set[key]) then
                            SetBinding(key, nil)
                            cleared = true
                        end
                    end
                end
            end
        end
        for _, b in ipairs(loadout.binds) do
            if b.cmd then
                for _, key in ipairs(b.keys or {}) do
                    if key and key ~= "" and GetBindingAction(key) ~= b.cmd then
                        if SetBinding(key, b.cmd) then rep.keys = rep.keys + 1 end
                    end
                end
            end
        end
        -- written to the server only when something changed (every login
        -- applies the auto loadout; an unchanged set is not saved again)
        if rep.keys > 0 or cleared then SaveBindings(GetCurrentBindingSet()) end
    end
    -- 5. pet bar
    if opts.pet ~= false and loadout.pet and next(loadout.pet) and IsPetActive and IsPetActive() then
        local tokenAt = {}
        for i = 1, (NUM_PET_ACTION_SLOTS or 10) do
            local name, _, isToken = GetPetActionInfo(i)
            if name and isToken then tokenAt[name] = i end
        end
        for i, want in pairs(loadout.pet) do
            i = tonumber(i)
            if i then
                ClearCursor()
                if want.token and tokenAt[want.token] and tokenAt[want.token] ~= i then
                    PickupPetAction(tokenAt[want.token])
                    PickupPetAction(i)
                elseif want.spell then
                    local cur = select(7, GetPetActionInfo(i))
                    if cur ~= want.spell then
                        PickupPetSpell(want.spell)
                        if GetCursorInfo() then PickupPetAction(i) end
                    end
                end
                ClearCursor()
            end
        end
    end
    return rep
end

function LO.Report(rep, name)
    if rep.error then Print("Loadout: " .. rep.error) return end
    if rep.waiting then Print("Loadout '" .. tostring(name) .. "' will be applied when combat ends.") return end
    local parts = {}
    parts[#parts + 1] = rep.placed .. " slot" .. (rep.placed == 1 and "" or "s") .. " set"
    if rep.cleared > 0 then parts[#parts + 1] = rep.cleared .. " cleared" end
    if rep.macrosMade > 0 then parts[#parts + 1] = rep.macrosMade .. " macro" .. (rep.macrosMade == 1 and "" or "s") .. " created" end
    if rep.keys > 0 then parts[#parts + 1] = rep.keys .. " key" .. (rep.keys == 1 and "" or "s") .. " bound" end
    Print("Loadout '" .. tostring(name) .. "': " .. table.concat(parts, ", ") .. ".")
    if #rep.skipped > 0 then
        local shown = {}
        for i = 1, math.min(#rep.skipped, 8) do shown[i] = rep.skipped[i] end
        Print("  skipped: " .. table.concat(shown, "; ")
            .. (#rep.skipped > 8 and ("; +" .. (#rep.skipped - 8) .. " more") or ""))
    end
end

function LO.ApplyNamed(name, opts)
    local lo = LO.Get(name)
    if not lo then Print("No loadout called '" .. tostring(name) .. "'.") return end
    local r = LO.Rules()
    opts = opts or {}
    if opts.clearSlots == nil then opts.clearSlots = r.clearSlots end
    if opts.clearBinds == nil then opts.clearBinds = r.clearBinds end
    local rep = LO.Apply(lo, opts)
    if not opts.quiet then LO.Report(rep, name) end
    return rep
end

-- ============================================================
-- STRINGS
-- ============================================================
function LO.Export(name)
    local lo = name and LO.Get(name) or LO.Capture()
    if not lo then return nil, "no such loadout" end
    return Profiles.PackString(PREFIX, lo)
end

-- ---- Myslot reader -------------------------------------------
local B64 = {}
do
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, #alphabet do B64[alphabet:sub(i, i)] = i - 1 end
end

-- bytes out as a Lua string; whitespace and anything foreign dropped
local function Base64ToBytes(text)
    text = text:gsub("[^A-Za-z0-9%+/]", "")
    local out, acc, bits = {}, 0, 0
    for i = 1, #text do
        acc = acc * 64 + B64[text:sub(i, i)]
        bits = bits + 6
        if bits >= 8 then
            bits = bits - 8
            local byte = math.floor(acc / (2 ^ bits))
            out[#out + 1] = string.char(byte % 256)
            acc = acc - byte * (2 ^ bits)
        end
    end
    return table.concat(out)
end

local CRC
local function Crc32(s)
    if not CRC then
        CRC = {}
        for i = 0, 255 do
            local c = i
            for _ = 1, 8 do
                if c % 2 == 1 then c = bit.bxor(bit.rshift(c, 1), 0xEDB88320) else c = bit.rshift(c, 1) end
            end
            CRC[i] = c
        end
    end
    local crc = 0xFFFFFFFF
    for i = 1, #s do
        crc = bit.bxor(CRC[bit.band(bit.bxor(crc, s:byte(i)), 0xFF)], bit.rshift(crc, 8))
    end
    return bit.band(bit.bxor(crc, 0xFFFFFFFF), 0xFFFFFFFF)
end

-- proto2 varint / length-delimited only; anything else is skipped by
-- its wire type, unknown fields ignored.
local function Varint(s, pos)
    local n, shift = 0, 0
    while pos <= #s do
        local b = s:byte(pos)
        pos = pos + 1
        n = n + (b % 128) * (2 ^ shift)
        shift = shift + 7
        if b < 128 then return n, pos end
        if shift > 63 then break end
    end
    return nil, pos
end

local function Fields(s)
    local out, pos = {}, 1
    while pos <= #s do
        local tag
        tag, pos = Varint(s, pos)
        if not tag then break end
        local field, wire = math.floor(tag / 8), tag % 8
        local value
        if wire == 0 then
            value, pos = Varint(s, pos)
            if value == nil then break end
        elseif wire == 2 then
            local len
            len, pos = Varint(s, pos)
            if not len or pos + len - 1 > #s then break end
            value = s:sub(pos, pos + len - 1)
            pos = pos + len
        elseif wire == 1 then pos = pos + 8 value = false
        elseif wire == 5 then pos = pos + 4 value = false
        else break end
        if value ~= false then
            out[field] = out[field] or {}
            out[field][#out[field] + 1] = value
        end
    end
    return out
end
local function One(f, n) return f[n] and f[n][1] end

local function MsKey(bytes)
    local f = Fields(bytes)
    local code, mod, literal = One(f, 1), One(f, 2), One(f, 15)
    local keyName = (code == 0) and literal or MS_KEYS[code]
    if not keyName or keyName == "KEYCODE" then return nil end
    local modName = MS_MODS[mod or 0] or "NONE"
    if modName == "NONE" then return keyName end
    return modName .. "-" .. keyName
end

function LO.DecodeMyslot(text)
    if type(text) ~= "string" then return nil, "nothing to read" end
    local body = text:gsub("@[^\n]*\n?", ""):gsub("#[^\n]*\n?", "")
    local bytes = Base64ToBytes(body)
    if #bytes < 8 then return nil, "not a Myslot string" end
    local crc = bytes:byte(5) * 16777216 + bytes:byte(6) * 65536 + bytes:byte(7) * 256 + bytes:byte(8)
    local zeroed = bytes:sub(1, 4) .. string.char(0, 0, 0, 0) .. bytes:sub(9)
    if Crc32(zeroed) ~= crc then return nil, "the Myslot string is damaged or incomplete" end
    local msg = Fields(bytes:sub(9))
    local out = { v = 1, source = "myslot", slots = {}, macros = {}, binds = {}, pet = {},
                  player = One(msg, 15), time = time() }
    -- the header's class line is localized; map it back to the token
    local shown = text:match("#%s*[^:\n]-:%s*(%a+)%s*\r?\n#%s*[^:\n]-:%s*%d+/%d+/%d+")
    if shown then
        for token, loc in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do
            if loc == shown then out.class = token end
        end
        for token, loc in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do
            if loc == shown then out.class = token end
        end
        out.class = out.class or shown:upper()
    end
    local acc = MacroLimits()
    -- macros: old index -> position in our list
    local byOldId = {}
    for _, m in ipairs(msg[3] or {}) do
        local f = Fields(m)
        local id = One(f, 3)
        local icon = One(f, 4)
        if icon and tonumber(icon) then icon = tonumber(icon) end
        out.macros[#out.macros + 1] = { name = One(f, 1) or "macro", body = Unify(One(f, 2)),
                                        icon = icon, perchar = (id or 0) > acc }
        if id then byOldId[id] = #out.macros end
    end
    for _, sl in ipairs(msg[1] or {}) do
        local f = Fields(sl)
        local slot, kind, index, str = One(f, 1), MS_TYPE[One(f, 2) or 0], One(f, 3), One(f, 4)
        if slot and slot >= 1 and slot <= MAX_SLOTS then
            if kind == "spell" and index and index > 0 then
                out.slots[slot] = { t = "spell", id = index, name = GetSpellInfo(index) }
            elseif kind == "item" and index then
                out.slots[slot] = { t = "item", id = index }
            elseif kind == "macro" and index and byOldId[index] then
                out.slots[slot] = { t = "macro", m = byOldId[index] }
            elseif kind == "equipmentset" and index then
                out.slots[slot] = { t = "equipmentset", id = index }
            elseif kind == "empty" then
                out.slots[slot] = { t = "empty" }
            end
        end
    end
    for _, b in ipairs(msg[2] or {}) do
        local f = Fields(b)
        local id = One(f, 1)
        local cmd = (id == MS_CUSTOM_BIND) and One(f, 15) or MS_BINDS[id or 0]
        if cmd then
            local keys = {}
            for _, n in ipairs({ 2, 3 }) do
                local kb = One(f, n)
                local k = kb and MsKey(kb)
                if k then keys[#keys + 1] = k end
            end
            if #keys > 0 then out.binds[#out.binds + 1] = { cmd = cmd, keys = keys } end
        end
    end
    for _, sl in ipairs(msg[4] or {}) do
        local f = Fields(sl)
        local slot, kind, index, str = One(f, 1), MS_TYPE[One(f, 2) or 0], One(f, 3), One(f, 4)
        if slot then
            if str and str ~= "" then out.pet[slot] = { token = str }
            elseif kind == "spell" and index and index > 0 then out.pet[slot] = { spell = index }
            elseif kind == "empty" then out.pet[slot] = { empty = true } end
        end
    end
    local n = 0
    for _ in pairs(out.slots) do n = n + 1 end
    if n == 0 and #out.binds == 0 and #out.macros == 0 then return nil, "the Myslot string holds nothing" end
    return out
end

-- Either kind of string.
function LO.Import(text)
    if type(text) ~= "string" then return nil, "nothing to import" end
    local trimmed = text:gsub("^%s+", "")
    if trimmed:find("^" .. PREFIX .. ":") then
        local lo, err = Profiles.UnpackString(PREFIX, text)
        if not lo then return nil, err end
        if type(lo.slots) ~= "table" then return nil, "the string holds no loadout" end
        return lo
    end
    return LO.DecodeMyslot(text)
end

-- Myslot's own saved variables, when that addon is still enabled: every
-- export it kept, decoded, so they can be adopted with one click.
function LO.MyslotSaved()
    local sv = _G.MyslotExports
    if type(sv) ~= "table" then return nil end
    local list = {}
    for _, e in ipairs(sv.exports or {}) do
        if type(e) == "table" and type(e.value) == "string" then
            local lo = LO.DecodeMyslot(e.value)
            if lo then list[#list + 1] = { name = e.name or lo.player or "Myslot", loadout = lo } end
        end
    end
    for i, v in ipairs(sv.backups or {}) do
        if type(v) == "string" then
            local lo = LO.DecodeMyslot(v)
            if lo then list[#list + 1] = { name = "Backup " .. i .. (lo.player and (" (" .. lo.player .. ")") or ""), loadout = lo, backup = true } end
        end
    end
    return list
end

function LO.AdoptMyslot()
    local list = LO.MyslotSaved()
    if not list then return 0, "Myslot's saved variables are not loaded (is Myslot enabled?)" end
    local db, n = LO.DB(), 0
    for _, e in ipairs(list) do
        local name = e.name
        if db[name] and not (db[name].source == "myslot") then name = name .. " (Myslot)" end
        e.loadout.name = name
        e.loadout.rev = (db[name] and db[name].rev or 0) + 1
        db[name] = e.loadout
        n = n + 1
    end
    LO.DB().adoptedMyslot = time()
    return n
end

-- ============================================================
-- AUTO-APPLY ON LOGIN
-- ============================================================
-- Which loadout this character gets: its own choice first, else the
-- account rule for its class, else the rule for everyone. Mode "always"
-- re-applies on every login (slots already right are left alone, so it
-- is cheap), "once" only the first time, "off" never.
function LO.ResolveAuto()
    ZacUICharDB = ZacUICharDB or {}
    local rec = ZacUICharDB.loadout
    local r = LO.Rules()
    if rec and rec.name and not LO.Get(rec.name) then rec = nil ZacUICharDB.loadout = nil end
    if not rec then
        local name = r.byClass[CLASS] or r.all
        if name and LO.Get(name) then
            rec = { name = name, mode = r.mode, fromRule = true }
            ZacUICharDB.loadout = rec
        end
    elseif rec.fromRule then
        -- still following the account rule: pick up rule changes
        local name = r.byClass[CLASS] or r.all
        if name and LO.Get(name) and name ~= rec.name then rec.name = name rec.appliedAt = nil end
        rec.mode = r.mode
    end
    return rec
end

function LO.AutoApply()
    local rec = LO.ResolveAuto()
    if not rec or not rec.name then return end
    local mode = rec.mode or "always"
    if mode == "off" then return end
    local lo = LO.Get(rec.name)
    if not lo then return end
    if mode == "once" and rec.appliedAt and rec.appliedRev == lo.rev then return end
    local r = LO.Rules()
    local rep = LO.Apply(lo, { clearSlots = r.clearSlots, clearBinds = r.clearBinds })
    if not rep.waiting then
        rec.appliedAt = time()
        rec.appliedRev = lo.rev
        -- quiet when nothing changed: an alt that is missing spells it
        -- has not learned yet should not be told so on every login
        if rep.placed > 0 or rep.cleared > 0 or rep.keys > 0 or rep.macrosMade > 0 then
            LO.Report(rep, rec.name)
        end
    end
end

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_ENTERING_WORLD")
login:SetScript("OnEvent", function(self, event, isLogin, isReload)
    if LO._autoDone then return end
    LO._autoDone = true
    -- the spellbook needs a moment after the world appears
    C_Timer.After(4, function()
        local ok, err = pcall(LO.AutoApply)
        if not ok then Print("Loadout auto-apply failed: " .. tostring(err)) end
    end)
end)
