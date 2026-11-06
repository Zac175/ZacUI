-- Boot_Identify - /zacui id, the click-to-identify frame inspector.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local Col = ns.Col
local Print = ns.Print

-- CLICK IDENTIFIER: the next mouse-down prints what was clicked - name,
-- type, parent and normal texture. That name is what /zacui inset and
-- /zacui line take, so this is the first step of every panel fix.
local idFrame
local function ArmIdentify()
    if not idFrame then
        idFrame = CreateFrame("Frame")
    end
    local ok = pcall(idFrame.RegisterEvent, idFrame, "GLOBAL_MOUSE_DOWN")
    if not ok then
        Print("Identify unavailable on this client build.")
        return
    end
    idFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        -- Modern 1.15 removed GetMouseFocus() in favor of GetMouseFoci()
        -- (a list). The old guard fell through to nil silently, which is
        -- why identify printed "clicked the world" no matter what - and
        -- why this tool never produced output all project.
        local f
        if GetMouseFoci then
            local foci = GetMouseFoci()
            if foci then
                for _, cand in ipairs(foci) do
                    if cand ~= WorldFrame then
                        f = cand
                        break
                    end
                end
                f = f or foci[1]
            end
        elseif GetMouseFocus then
            f = GetMouseFocus()
        end
        if not f or f == WorldFrame then
            Print("id: clicked the world / nothing named.")
            return
        end
        local chain, node, hops = {}, f, 0
        while node and hops < 5 do
            local n = node.GetName and node:GetName()
            chain[#chain + 1] = n or ("<" .. (node.GetObjectType and node:GetObjectType() or "?") .. ">")
            node = node.GetParent and node:GetParent()
            hops = hops + 1
        end
        Print("id: " .. table.concat(chain, "  <-  "))
        -- TEXT DIAGNOSTIC: the clicked element's actual text color plus
        -- where the palette value comes from - one click on a black line
        -- is ground truth, not another guess.
        local fs
        if f.IsObjectType and f:IsObjectType("FontString") then
            fs = f
        elseif f.GetFontString and f:GetFontString() then
            fs = f:GetFontString()
        elseif f.GetRegions then
            for _, region in ipairs({ f:GetRegions() }) do
                if region.IsObjectType and region:IsObjectType("FontString")
                    and region.GetText and region:GetText() then
                    fs = region
                    break
                end
            end
        end
        if fs then
            local tr, tg, tb = fs:GetTextColor()
            local fobj = fs.GetFontObject and fs:GetFontObject()
            local fname = (fobj and fobj.GetName and fobj:GetName()) or "?"
            local _, _, _, ta = fs:GetTextColor()
            local fpath = (fs.GetFont and select(1, fs:GetFont())) or "?"
            local sr, sg, sb = 0, 0, 0
            if fs.GetShadowColor then sr, sg, sb = fs:GetShadowColor() end
            local snippet = (fs.GetText and fs:GetText()) or ""
            snippet = snippet:sub(1, 40):gsub("|", "||")
            Print(string.format("id text: color %.2f %.2f %.2f a%.2f  font %s  pinned=%s",
                tr or -1, tg or -1, tb or -1, ta or -1, fname,
                tostring(fs._zui_textPinned or false)))
            Print(string.format("id text2: face %s  shadow %.2f %.2f %.2f  layer %s",
                tostring(fpath):match("[^\\/]+$") or "?",
                sr or -1, sg or -1, sb or -1,
                (fs.GetDrawLayer and select(1, fs:GetDrawLayer())) or "?"))
            Print("id text3: [" .. snippet .. "]")
        end
        local pc = Col("text")
        local src = (ZacUIDB and ZacUIDB.colors and ZacUIDB.colors.text)
            and "SAVED OVERRIDE" or "default palette"
        Print(string.format("id palette: text = %.2f %.2f %.2f (%s)",
            pc.r or -1, pc.g or -1, pc.b or -1, src))
        if f.GetNormalTexture then
            local nt = f:GetNormalTexture()
            local tex = nt and nt.GetTexture and nt:GetTexture()
            if tex then Print("id normal texture: " .. tostring(tex)) end
        end
    end)
    Print("Identify armed - click the element.")
end


-- shared with later ZacUI files
ns.ArmIdentify = ArmIdentify
