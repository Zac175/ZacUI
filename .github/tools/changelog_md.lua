-- Writes CHANGELOG.md for one ZacUI version from Zacui/UI/Changelog/Changelog_Data.lua
-- (the in-game changelog), for the release workflow.
-- usage: lua5.1 .github/tools/changelog_md.lua <version> [path to Changelog_Data.lua]
local want = arg[1]
local path = arg[2] or "Zacui/UI/Changelog/Changelog_Data.lua"
if not want or want == "" then io.stderr:write("no version given\n") os.exit(1) end
local chunk, err = loadfile(path)
if not chunk then io.stderr:write(tostring(err) .. "\n") os.exit(1) end
local ns = {}
chunk("Zacui", ns)
local HEAD = { added = "Added", changed = "Changed", fixed = "Fixed", removed = "Removed" }
for _, e in ipairs(ns.CHANGELOG or {}) do
    if e.version == want then
        local out = { "# ZacUI " .. e.version .. (e.title and e.title ~= "" and e.title ~= "Changelog" and (": " .. e.title) or "") }
        for _, s in ipairs(e.sections or {}) do
            out[#out + 1] = ""
            out[#out + 1] = "## " .. (HEAD[s.type] or s.type or "Changes")
            for _, it in ipairs(s.items or {}) do out[#out + 1] = "- " .. it end
        end
        io.write(table.concat(out, "\n"), "\n")
        os.exit(0)
    end
end
io.write("# ZacUI " .. want .. "\n")
