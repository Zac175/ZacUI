-- Boot_Slash - /zacui and /zui.
-- Part of ZacUI; load order is set by the TOC.
--
-- /zui is the front door: bare it opens the config window, with a page
-- name it jumps straight there, and with anything else it falls through to
-- /zacui so every command works under either prefix.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local AnchorPanel = ns.AnchorPanel
local ApplyFonts = ns.ApplyFonts
local ArmIdentify = ns.ArmIdentify
local ClassifyAndSkin = ns.ClassifyAndSkin
local DEFAULT_MODULES = ns.DEFAULT_MODULES
local EnableModuleLive = ns.EnableModuleLive
local GetPanelInset = ns.GetPanelInset
local GetPanelLineY = ns.GetPanelLineY
local MODULE_INFO = ns.MODULE_INFO
local MODULE_ORDER = ns.MODULE_ORDER
local MOVERS = ns.MOVERS
local Modules = ns.Modules
local OpenConfig = ns.OpenConfig
local Print = ns.Print
local ResetMover = ns.ResetMover
local ToggleMover = ns.ToggleMover
local ToggleTipMover = ns.ToggleTipMover
local ZUI = ns.ZUI

-- /zui <word> shortcuts onto config pages. Typing the page you want beats
-- opening the window and hunting for it.
local PAGE_ALIAS = {
    general = "general", home = "general",
    font = "font", fonts = "font",
    color = "colors", colors = "colors", colour = "colors", colours = "colors",
    hud = "mod_hud", windows = "mod_windows", window = "mod_windows",
    tooltip = "tooltips", tooltips = "tooltips", tip = "tooltips",
    buff = "buffs", buffs = "buffs", voice = "general", tts = "general",
    engine = "mod_engine",
    minimap = "minimap", mm = "minimap",
    chat = "chat", chatbar = "chat",
    uf = "unitframes", unitframes = "unitframes", zacuf = "unitframes",
    mover = "movers", movers = "movers", move = "movers",
    tool = "tools", tools = "tools",
    module = "mod_hud", modules = "mod_hud",
    aura = "auras", auras = "auras", wa = "auras", weakauras = "auras",
    bar = "bars", bars = "bars", actionbars = "bars", bartender = "bars",
    loadout = "loadouts", loadouts = "loadouts", myslot = "loadouts",
    sbt = "sbt", sct = "sbt", scrolling = "sbt", combattext = "sbt",
    profile = "profiles", profiles = "profiles", import = "import",
    tray = "tray", buttons = "tray",
    plates = "nameplates", nameplates = "nameplates", scripts = "npscripts",
    meter = "meter", details = "meter",
    bags = "bags", bag = "bags", ah = "auction", auction = "auction",
    maps = "maps", map = "maps",
    rm = "raidmods", raidmods = "raidmods", bossmods = "raidmods",
    qol = "qol", leatrix = "qol",
    hesitation = "hesitation", hesitate = "hesitation", noob = "hesitation", late = "hesitation",
}

SLASH_ZACUI1 = "/zacui"
SlashCmdList["ZACUI"] = function(msg)
    local raw = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    msg = raw:lower()

    local cmd, rest = raw:match("^(%S+)%s*(.-)$")
    cmd = cmd and cmd:lower() or ""

    if cmd == "plate" or cmd == "preview" then
        -- the sample nameplate with everything on
        local Pv = ns.Nameplates and ns.Nameplates.Preview
        if Pv then Print(Pv.Toggle() and "preview plate up - /zui plate again to hide it." or "preview plate hidden.")
        else Print("The nameplate module is not loaded.") end
        return
    elseif cmd == "noob" or cmd == "bt" then
        -- the hesitation scorecard: the last pull (or the last n) in chat
        local H = ns.Hesitation
        if H and H.Report then H:Report(rest) else Print("The HUD module (hesitation alerts) is not loaded.") end
        return
    elseif cmd == "flavor" or cmd == "flavour" then
        -- what runs on this game version, and the "test as" override
        -- (General > Game versions; Core_Flavor)
        if ns.FlavorCommand then ns.FlavorCommand(rest) end
        return
    elseif cmd == "version" or cmd == "ver" then
        -- this client's version and the newest one heard (Core_VersionCheck)
        if ns.VersionCommand then ns.VersionCommand() else Print("v" .. ZUI.VERSION) end
        return
    elseif cmd == "raid" or cmd == "summary" then
        -- the raid summary: the last raid (or /zui raid n, counted back)
        if ns.FeatureOn and not ns.FeatureOn("raid_summary") then
            Print(ns.FeatureOffNote("raid_summary"))
            return
        end
        local RSm = ns.RaidSummary
        local arg = rest and rest:lower() or ""
        if RSm and RSm.Demo and (arg == "demo" or arg == "test" or arg == "example") then
            RSm.Demo()  -- made-up numbers, to see the page
        elseif RSm then
            local st = RSm.Store()
            local n = tonumber(rest)
            RSm.Toggle(n and (#st - n + 1) or nil)
        else Print("The meter module (raid summary) is not loaded.") end
        return
    elseif cmd == "bless" or cmd == "blessings" or cmd == "pp" then
        -- the blessing assignments: who gives which class what
        local BL = ns.Blessings
        if BL and BL.Grid and BL.Grid.Toggle then BL.Grid.Toggle()
        else Print("The blessings module is not loaded.") end
        return
    elseif cmd == "mount" then
        -- the smart mount macro: what it picks here, written now
        local SM = ns.QoL and ns.QoL.SmartMount
        if SM then SM.Status() else Print("The quality-of-life module (and its mount macro) is not loaded.") end
        return
    elseif cmd == "msgs" then
        -- raid chat: stop / start the messages popping over the raid frames
        local RM = ns.Chat and ns.Chat.RaidMode
        if RM then Print(RM.ToggleMsgs() and "raid messages hidden (the Chat count still counts them)." or "raid messages showing again.")
        else Print("The chat module is not loaded.") end
        return
    elseif cmd == "raidchat" then
        -- the raid frames in the chat box while in a raid: on / off (this account)
        local RM = ns.Chat and ns.Chat.RaidMode
        local d = ns.Chat and ns.Chat.DB and ns.Chat.DB()
        if not (RM and d) then Print("The chat module is not loaded.") return end
        local v = rest:lower()
        if v == "why" or v == "status" then
            -- everything that decides whether the raid frames are in the box
            local own = ZacUICharDB and ZacUICharDB.chatRaidMode
            local UF = _G.ZacUF
            local rc = UF and UF.db and UF.db.raid
            local l, r, t, b = RM.Area and RM.Area(true)
            Print(string.format("raid chat: account %s, this character %s -> %s; in a raid: %s; the box holds: %s; raid frames fit to chat: %s (growth %s / %s); box room: %s",
                tostring(d.raidMode), own == nil and "no override" or tostring(own), RM.Enabled() and "ON" or "OFF",
                tostring(IsInRaid()), tostring(RM.Kind and RM.Kind() or "nothing"),
                tostring(rc and rc.fitChat), tostring(rc and rc.growth), tostring(rc and rc.columnGrowth),
                l and string.format("%.0fx%.0f", r - l, t - b) or "not measured"))
            if UF and UF.FitRaidToChat then Print("fit now: " .. tostring(UF.FitRaidToChat())) end
            return
        end
        if v == "on" then d.raidMode = true elseif v == "off" then d.raidMode = false else d.raidMode = not d.raidMode end
        if ZacUICharDB then ZacUICharDB.chatRaidMode = nil end
        RM.Update()
        Print("raid chat " .. (d.raidMode and "on: in a raid the chat box holds the raid frames." or "off."))
        return
    elseif cmd == "font" and rest ~= "" then
        ZacUIDB.font.name = rest
        ApplyFonts()
        Print("Font set to '" .. rest .. "'. Most text updates now; /reload finishes cached strings.")
        return
    elseif cmd == "fontsize" and rest ~= "" then
        local d = tonumber(rest)
        if d and d >= -3 and d <= 6 then
            ZacUIDB.font.delta = d
            ApplyFonts()
            Print("Font size delta " .. d .. ".")
        else
            Print("Usage: /zacui fontsize <-3 .. +6>")
        end
        return
    elseif cmd == "fontoutline" then
        local v = rest:lower()
        if v == "on" then ZacUIDB.font.outline = "OUTLINE"
        elseif v == "off" then ZacUIDB.font.outline = "NONE"
        else ZacUIDB.font.outline = nil end
        ApplyFonts()
        Print("Font outline: " .. (ZacUIDB.font.outline or "default") .. ".")
        return
    elseif cmd == "fontlist" then
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if LSM then
            Print("LSM fonts: " .. table.concat(LSM:List("font"), ", "))
        else
            Print("LibSharedMedia not found - pass a file path to /zacui font instead.")
        end
        return
    elseif cmd == "inset" then
        local fname, a1, a2, a3, a4 = rest:match("^(%S+)%s*(%-?%d*)%s*(%-?%d*)%s*(%-?%d*)%s*(%-?%d*)$")
        if not fname or fname == "" then
            Print("Usage: /zacui inset <FrameName> [l r t b | reset]")
            return
        end
        if rest:lower():match("^%S+%s+reset$") then
            ZacUIDB.insets[fname] = nil
        elseif a1 ~= "" and a2 ~= "" and a3 ~= "" and a4 ~= "" then
            ZacUIDB.insets[fname] = {
                l = tonumber(a1) or 0, r = tonumber(a2) or 0,
                t = tonumber(a3) or 0, b = tonumber(a4) or 0,
            }
        end
        local ins = GetPanelInset(fname)
        local frame = ZUI.panels[fname]
        if frame and frame._zui_artbg then
            frame._zui_artbg:ClearAllPoints()
            frame._zui_artbg:SetPoint("TOPLEFT", frame, "TOPLEFT", ins.l or 0, -(ins.t or 0))
            frame._zui_artbg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(ins.r or 0), ins.b or 0)
            Print(string.format("%s art-bg inset: l=%d r=%d t=%d b=%d (applied live, saved)",
                fname, ins.l, ins.r, ins.t, ins.b))
        elseif frame and frame._zui_panel then
            AnchorPanel(frame._zui_panel, frame, ins)
            Print(string.format("%s inset: l=%d r=%d t=%d b=%d (applied live, saved)",
                fname, ins.l, ins.r, ins.t, ins.b))
        else
            Print(string.format("%s inset: l=%d r=%d t=%d b=%d (saved; opens skinned)",
                fname, ins.l, ins.r, ins.t, ins.b))
        end
        return
    elseif cmd == "line" then
        local fname, val = rest:match("^(%S+)%s*(%S*)$")
        if not fname or fname == "" then
            Print("Usage: /zacui line <FrameName> <y | reset>   (y is negative, e.g. -46)")
            return
        end
        if val:lower() == "reset" then
            ZacUIDB.lines[fname] = nil
        elseif tonumber(val) then
            ZacUIDB.lines[fname] = tonumber(val)
        end
        local y = GetPanelLineY(fname)
        local frame = ZUI.panels[fname]
        if frame and frame._zui_line and (frame._zui_artbg or frame._zui_panel)
            and ns.FitPanelChrome then
            -- band, rule and X move together: the header is one unit
            ns.FitPanelChrome(frame, y)
            Print(fname .. " header line y=" .. y .. " (applied live, saved)")
        else
            Print(fname .. " header line y=" .. y .. " (saved; opens skinned)")
        end
        return
    elseif cmd == "reset" then
        ZacUIDB.modules = {}
        for m, v in pairs(DEFAULT_MODULES) do ZacUIDB.modules[m] = v end
        ZacUIDB.insets, ZacUIDB.lines = {}, {}
        ZacUIDB.colors, ZacUIDB.palette = {}, {}
        ZacUIDB.tooltipPos = nil
        ZacUIDB.config = nil
        ZacUIDB.font = { name = nil, delta = 0, outline = nil }
        Print("Settings reset to defaults - /reload to apply.")
        return
    elseif cmd == "xray" then
        -- Dump every visible text renderer under the quest/gossip trees:
        -- name, colour+alpha, pin state, snippet. The black one will be in
        -- this list with its true identity - no click-aiming required.
        local count = 0
        local function Dump(root, depth, label)
            if not root or depth > 8 or count >= 25 then return end
            if root.IsObjectType and root:IsObjectType("SimpleHTML") then
                count = count + 1
                Print(string.format("xray %d: SimpleHTML under %s", count, label))
            end
            if root.GetRegions then
                for _, region in ipairs({ root:GetRegions() }) do
                    if count >= 25 then return end
                    if region.IsObjectType and region:IsObjectType("FontString")
                        and region:IsVisible() then
                        local txt = region.GetText and region:GetText()
                        if txt and txt ~= "" then
                            count = count + 1
                            local r, g, b, a = region:GetTextColor()
                            local sr2, sg2, sb2, sa2 = 0, 0, 0, 0
                            if region.GetShadowColor then
                                sr2, sg2, sb2, sa2 = region:GetShadowColor()
                            end
                            local par = region.GetParent and region:GetParent()
                            local ea = (par and par.GetEffectiveAlpha
                                and par:GetEffectiveAlpha()) or -1
                            Print(string.format(
                                "xray %d: [%s] c=%.2f,%.2f,%.2f a=%.2f ea=%.2f sh=%.2f/%.2f pin=%s <%s>",
                                count, txt:sub(1, 22):gsub("|", "||"),
                                r or -1, g or -1, b or -1, a or -1, ea,
                                sr2 or -1, sa2 or -1,
                                tostring(region._zui_textPinned or false),
                                (region.GetName and region:GetName()) or label))
                        end
                    end
                end
            end
            if root.GetChildren then
                for _, child in ipairs({ root:GetChildren() }) do
                    local cl = (child.GetName and child:GetName()) or label
                    Dump(child, depth + 1, cl)
                end
            end
        end
        for _, root in ipairs({ QuestFrame, GossipFrame, ItemTextFrame }) do
            if root and root:IsShown() then
                Dump(root, 0, root:GetName() or "?")
            end
        end
        if count == 0 then
            Print("xray: open the quest/gossip page first, then run this.")
        end
        return
    elseif cmd == "profile" then
        local Profiles = ns.Profiles
        local action, arg = rest:match("^(%S*)%s*(.-)$")
        action = (action or ""):lower()
        local usage = "usage: /zacui profile use|new|copy|delete <name>  |  list  |  default <name>"
        if action == "list" or action == "" then
            local names = Profiles.List()
            local cur = Profiles.Current()
            local shown = {}
            for _, n in ipairs(names) do
                shown[#shown + 1] = (n == cur) and (n .. " (this character)") or n
            end
            Print("profiles: " .. (#shown > 0 and table.concat(shown, ", ") or "none"))
            Print("new characters start on '" .. Profiles.DefaultName() .. "'.")
            Print(usage)
        elseif action == "use" and arg ~= "" then
            local ok, err = Profiles.Use(arg)
            if ok then
                Print("this character now wears '" .. arg .. "' - /reload to apply everywhere.")
            else
                Print("switch failed: " .. tostring(err))
            end
        elseif action == "new" and arg ~= "" then
            local ok, err = Profiles.New(arg, true)
            Print(ok and ("created '" .. arg .. "' with shipped defaults - /zacui profile use " .. arg .. " to wear it.")
                     or ("create failed: " .. tostring(err)))
        elseif action == "copy" and arg ~= "" then
            Profiles.WriteBack()
            local ok, err = Profiles.New(arg, false)
            Print(ok and ("copied this character's settings to '" .. arg .. "'.")
                     or ("copy failed: " .. tostring(err)))
        elseif action == "delete" and arg ~= "" then
            local ok, err = Profiles.Delete(arg)
            Print(ok and ("deleted '" .. arg .. "'.") or ("delete failed: " .. tostring(err)))
        elseif action == "default" then
            if arg == "" then
                Print("new characters start on '" .. Profiles.DefaultName() .. "'.")
            elseif Profiles.Store()[arg] then
                ZacUIDB.defaultProfile = arg
                Print("new characters will start on '" .. arg .. "'.")
            else
                Print("no profile called '" .. arg .. "'.")
            end
        elseif action == "export" or action == "import" then
            -- Chat cannot hold a full profile string, and pasting one out
            -- of the log is lossy. Send them to the box built for it.
            OpenConfig("profiles")
            Print("opened Profiles - the Export and Import boxes are selectable.")
        else
            Print(usage)
        end
        return
    elseif cmd == "minimap" and (rest or ""):lower():match("^button") then
        -- /zui minimap button [show|hide]
        local MB = ns.MinimapButton
        if not MB then Print("the minimap button did not load.") return end
        local what = (rest or ""):lower():match("^button%s*(%S*)")
        if what == "hide" then MB.SetShown(false)
        else MB.SetShown(true) Print("minimap button shown.") end
        return
    elseif cmd == "tray" then
        if ns.Tray then ns.Tray.Diagnose() end
        return
    elseif cmd == "taint" then
        -- /zacui taint                 blocked-call count this session
        -- /zacui taint CompactRaidFrame1   which of its fields are ours
        if rest == "" then
            Print((ns.BlockedCount and ns.BlockedCount() or 0)
                .. " protected call(s) blocked and credited to ZacUI this "
                .. "session. /zacui taint <FrameName> probes a frame.")
            -- The raid container is the usual suspect, so probe it
            -- unasked when it exists.
            for _, n in ipairs({ "CompactRaidFrameContainer", "CompactRaidFrameManager",
                                 "CompactRaidFrame1", "CompactPartyFrame" }) do
                if _G[n] and ns.ProbeTaint then ns.ProbeTaint(n) end
            end
            return
        end
        if not _G[rest] then Print("No frame named '" .. rest .. "'."); return end
        if ns.ProbeTaint then ns.ProbeTaint(rest) end
        return
    elseif cmd == "auras" then
        -- where the aura engine stands, and the way to its page
        local A = ns.Auras
        local s = A and A.Status and A.Status()
        if not s then Print("The aura part is not loaded."); return end
        local E = ns.AuraEngine
        local n = 0
        if E and E.data then for _ in pairs(E.data) do n = n + 1 end end
        Print("Aura engine: " .. (s.engineUp and ("running, " .. n .. " auras") or (s.want and "on, not loaded (reload?)" or "off"))
            .. (s.upstreamUp and " - WeakAuras is loaded too" or "") .. ".")
        if ns.OpenConfig then ns.OpenConfig("auras") end
        return
    elseif cmd == "traydump" then
        if ns.Tray then ns.Tray.Dump() end
        return
    elseif cmd == "maps" then
        if ns.MapsDiagnose then
            ns.MapsDiagnose()
        else
            Print("the map layer did not load.")
        end
        return
    elseif cmd == "popupwatch" then
        -- Names every popup the client shows. "Which dialog is that?"
        -- cannot be answered from a screenshot, and the key is the answer.
        ZUI.popupWatch = not ZUI.popupWatch
        Print("popup watch " .. (ZUI.popupWatch and "on - every popup will be named"
            or "off"))
        return
    elseif cmd == "mapdump" then
        -- "there is still Blizzard art visible" cannot be answered from a
        -- screenshot; this says which frame owns each remaining pixel.
        if ns.MapsDump then ns.MapsDump() else Print("the map layer did not load.") end
        return
    elseif cmd == "minimapinfo" then
        -- Several minimap pieces changed names in 11509, and a name that
        -- moved looks exactly like an option that does not work. This
        -- says which ones this client actually has.
        if ns.MinimapOptions then
            ns.MinimapOptions.Diagnose()
        else
            Print("the minimap options layer did not load.")
        end
        return
    elseif cmd == "chatinfo" then
        -- The chat bar and the docked edit box cannot be checked outside
        -- the game; this says what each chat window, edit box and bar
        -- item is actually doing on this client.
        if ns.Chat then ns.Chat.Diagnose() else Print("the chat module did not load.") end
        return
    elseif cmd == "copychat" then
        if ns.Chat then ns.Chat.CopyChat() else Print("the chat module did not load.") end
        return
    elseif cmd == "mapcanvas" then
        -- mapdump stops AT the canvas by design, so every pin, blip and
        -- marker in the game was invisible to it. This is the other half:
        -- what is drawn ON the map, where, and how big.
        if ns.MapsCanvasDump then
            ns.MapsCanvasDump()
        else
            Print("the map layer did not load.")
        end
        return
    elseif cmd == "roll" then
        -- What auto-roll would do with an item, without rolling.
        local AR = ns.QoL and ns.QoL.AutoRoll
        local id = tonumber(rest) or tonumber((rest or ""):match("item:(%d+)"))
        if not AR then
            Print("auto-roll hasn't loaded - it lives in the Quality of life module.")
        elseif not id then
            Print("Usage: /zacui roll <item id or link>")
        else
            AR.Explain(id)
        end
        return
    elseif cmd == "testroll" then
        -- Fake loot roll bars, so the layout is inspectable (and the
        -- mover placeable) without waiting for an actual group drop.
        if ns.LootRollTest then
            ns.LootRollTest()
            Print("test rolls up: buttons dismiss their bar, timers "
                .. "drain on their own. Move them under Movers > Loot rolls.")
        else
            Print("the loot roll module hasn't run - enable it under "
                .. "Modules > Windows > Loot rolls, then try again.")
        end
        return
    elseif cmd == "clickwatch" then
        -- "shift-right-click does nothing" is unanswerable from outside
        -- the client: the click may not arrive, the modifier may not be
        -- the one bound to SPLITSTACK, the bag and slot may resolve
        -- wrong, or the dialog may open and call the wrong method. Each
        -- of those looks identical on screen. This says which.
        -- A REPORT, NOT A WATCH. The first version of this toggled a flag
        -- that a HookScript on the item button read - and that hook was
        -- itself the bug it was meant to help find, because hooking a bag
        -- slot's OnClick taints UseContainerItem and stops you using
        -- anything. A diagnostic that has to sit on the click path to
        -- work does not belong on this particular path, so this reads the
        -- state instead of instrumenting the click.
        if ns.Bags and ns.Bags.ClickReport then
            ns.Bags.ClickReport()
        else
            Print("the bag layer did not load.")
        end
        return
    elseif cmd == "postwatch" then
        -- Same idea for posting. Every step of a post has a checkable
        -- answer - is the Auctions tab up, did the item reach the slot,
        -- what does the client say is in it - and printing them turns a
        -- silent failure into a named one.
        if ns.AH then
            ns.AH.postWatch = not ns.AH.postWatch
            Print("post watch " .. (ns.AH.postWatch
                and "on - press Post and read the lines below" or "off"))
        else
            Print("the auction layer did not load.")
        end
        return
    elseif cmd == "trayfocus" then
        -- Answers "what is eating my clicks" from the client rather than
        -- from a theory about strata. Optional delay: /zui trayfocus 5
        if ns.Tray then ns.Tray.Focus(rest) end
        return
    elseif cmd == "id" then
        ArmIdentify()
        return
    elseif cmd == "ui" or cmd == "config" or cmd == "options" then
        OpenConfig(PAGE_ALIAS[rest:lower()])
        return
    elseif cmd == "auras" or cmd == "aura" then
        -- The engine registers no slash command of its own, so this is the
        -- only way in. Bare "/zacui auras" opens the page; anything else is
        -- handed to the engine's own handler, which still exists as
        -- SlashCmdList.WEAKAURAS. That covers profiling and the repair tool
        -- without reimplementing either, and means nothing was lost by
        -- taking the second command away.
        if rest == "" then
            OpenConfig("auras")
            return
        end
        local sub = rest:lower()
        if sub == "editor" or sub == "edit" or sub == "options" then
            Print("The aura editor lives on the Aura engine page now - "
                .. "/zacui auras.")
            OpenConfig("auras")
            return
        end
        local handler = SlashCmdList and SlashCmdList["WEAKAURAS"]
        if type(WeakAuras) ~= "table" or not WeakAuras.ZacUI or not handler then
            Print("The aura engine is not running. /zacui auras to turn it "
                .. "on, or to see why it did not load.")
            return
        end
        handler(rest)
        return
    elseif cmd == "tour" or cmd == "tutorial" then
        -- the guided tour of the settings window; "reset" offers the
        -- first-run welcome again at the next login
        local T = ns.Tutorial
        if not T then Print("The tutorial did not load.") return end
        if rest:lower() == "reset" then
            T.Reset()
            Print("The welcome will show at your next login.")
        else
            T.StartTour()
        end
        return
    elseif cmd == "setup" or cmd == "wizard" then
        if ns.Tutorial then ns.Tutorial.OpenSetup() else Print("The tutorial did not load.") end
        return
    elseif cmd == "edit" or cmd == "editmode" then
        if ns.ToggleEditMode then ns.ToggleEditMode() end
        return
    elseif cmd == "crosshair" then
        -- /zui crosshair: toggle the centre-screen crosshair and report
        -- what the module thinks it is doing (NP_Crosshair).
        if ns.Crosshair and (rest or ""):lower() == "range" and ns.Crosshair.RangeReport then
            ns.Crosshair.RangeReport()
        elseif ns.Crosshair and ns.Crosshair.Toggle then
            ns.Crosshair.Toggle()
        else
            Print("the crosshair module did not load.")
        end
        return
    elseif cmd == "soft" then
        -- The soft-target lab (NP_SoftTarget): /zui soft dump | grassy |
        -- set <CVar> <value> | off. Bare prints the current values.
        if ns.SoftTarget and ns.SoftTarget.Slash then
            ns.SoftTarget.Slash(rest)
        else
            Print("the soft-target module did not load.")
        end
        return
    elseif cmd == "movetip" then
        ToggleTipMover()
        return
    elseif cmd == "resettip" then
        ZacUIDB.tooltipPos = nil
        Print("Tooltip position reset to Blizzard default.")
        return
    elseif cmd == "moveloot" then
        ToggleMover("lootroll") -- legacy alias
        return
    elseif cmd == "resetloot" then
        ResetMover("lootroll") -- legacy alias
        return
    elseif cmd == "move" or cmd == "resetmove" then
        local key = msg:match("^%S+%s+(%S+)")
        if key == "tip" or key == "tooltip" then
            if cmd == "move" then
                ToggleTipMover()
            else
                ZacUIDB.tooltipPos = nil
                Print("Tooltip position reset to Blizzard default.")
            end
        elseif key and MOVERS[key] then
            if cmd == "move" then
                ToggleMover(key)
            else
                ResetMover(key)
            end
        else
            local keys = { "tip" }
            for _, mv in ipairs(MOVERS) do keys[#keys + 1] = mv.key end
            Print("movers: " .. table.concat(keys, ", "))
        end
        return
    elseif cmd == "rescan" then
        -- Full head-walk through the classifier. The skinned fence makes
        -- it idempotent, and the watcher's tail is deliberately NOT
        -- touched - rescan is a repair tool, not a reset.
        if not EnumerateFrames then
            Print("rescan: EnumerateFrames unavailable on this client.")
            return
        end
        local f, n = EnumerateFrames(), 0
        while f do
            pcall(ClassifyAndSkin, f)
            n = n + 1
            f = EnumerateFrames(f)
        end
        Print("rescan: walked " .. n .. " frames (fence skips finished ones; watcher tail untouched).")
        return
    elseif cmd == "bars" and rest ~= "" then
        -- /zui bars lock | unlock | import | keys | reset
        local AB = ns.Bars
        local sub = rest:lower()
        if not AB then Print("The bar system did not load.") return end
        if sub == "unlock" then AB.SetUnlocked(true)
        elseif sub == "lock" then AB.SetUnlocked(false) Print("Bars locked.")
        elseif sub == "import" then
            local n, err = AB.ImportBartender()
            Print(n and ("Imported " .. n .. " Bartender4 profile(s).") or ("Import failed: " .. tostring(err)))
        elseif sub == "keys" then AB.MigrateBartenderKeys(true)
        elseif sub == "apply" then AB.ApplyAll() Print("Bars re-applied.")
        elseif sub == "kb" or sub == "keybind" or sub == "bind" then AB.QuickKeybind()
        else Print("/zui bars lock | unlock | kb | import | keys | apply") end
        return
    elseif cmd == "loadout" and rest ~= "" then
        -- /zui loadout save <name> | apply <name> | list | export [name]
        local LO = ns.Loadouts
        if not LO then Print("The loadout system did not load.") return end
        local sub, arg = rest:match("^(%S+)%s*(.-)$")
        sub = (sub or ""):lower()
        if sub == "save" and arg ~= "" then
            local ok, err = LO.Save(arg)
            Print(ok and ("Saved loadout '" .. arg .. "'.") or tostring(err))
        elseif sub == "apply" and arg ~= "" then
            LO.ApplyNamed(arg)
        elseif sub == "list" then
            local names = LO.List()
            Print(#names > 0 and ("Loadouts: " .. table.concat(names, ", ")) or "No loadouts saved.")
        elseif sub == "export" then
            OpenConfig("loadouts")
            Print("Use the Export buttons on the Loadouts page - the string lands in a box you can copy from.")
        else
            Print("/zui loadout save <name> | apply <name> | list | export [name]")
        end
        return
    elseif cmd == "status" then
        local on, off = {}, {}
        for _, m in ipairs(MODULE_ORDER) do
            local t = ZacUIDB.modules[m] and on or off
            t[#t + 1] = m
        end
        Print("v" .. ZUI.VERSION .. " (TOC 11509 - 1.15.9 Edit Mode client)")
        Print("on:  " .. (#on > 0 and table.concat(on, ", ") or "-"))
        Print("off: " .. (#off > 0 and table.concat(off, ", ") or "-"))
        return
    end

    local module, action = msg:match("^(%S+)%s+(%S+)$")
    if module and Modules[module] and (action == "on" or action == "off") then
        if action == "on" then
            EnableModuleLive(module)
        else
            ZacUIDB.modules[module] = false
            Print(module .. " off - /reload to restore the stock look.")
        end
        return
    end

    Print("v" .. ZUI.VERSION .. " - /zui opens the options window. Modules (/zacui <module> on|off):")
    for _, m in ipairs(MODULE_ORDER) do
        local state = ZacUIDB.modules[m] and "|cFF66FF66on|r" or "|cFF999999off|r"
        local info = MODULE_INFO[m]
        Print("  " .. m .. " - " .. state
            .. (info and ("  |cFF808080" .. info.label .. "|r") or ""))
    end
end

-- /zui: the front door. Bare opens the window; a page name jumps there;
-- anything else routes through the full handler, so /zui reset,
-- /zui font <name> and /zui character on all keep working.
SLASH_ZACUIUI1 = "/zui"
SlashCmdList["ZACUIUI"] = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" then
        OpenConfig()
        return
    end
    local page = PAGE_ALIAS[msg:lower()]
    if page then
        OpenConfig(page)
        return
    end
    SlashCmdList["ZACUI"](msg)
end
