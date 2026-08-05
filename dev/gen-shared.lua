--[[
    dev/gen-shared.lua — THE PARSING BOTH GENERATORS SHARE.

    Daseeki Armory ships two generated data files, and they are built from the
    same three inputs by the same reading code:

        dev/gen-restrictions.lua  ->  restrictions.lua   (class/faction locks +
                                                          the hidden policy list)
        dev/gen-catalog.lua       ->  catalog.lua        (the item catalog itself)

    Everything below is the part neither generator should own privately: the
    headless guards, the legacy cache codec, and the three loaders. If the two
    generators each kept their own copy of "how to read the developer's scan
    SavedVariables", they could drift, and two shipped files built from the same
    evidence would stop agreeing about it. One reader, one truth.

    HEADLESS DISCIPLINE. Every loop a generator runs goes through each(), which
    carries an explicit iteration ceiling, and guard() aborts past 300 MB. A
    malformed input cannot spin either generator into a runaway.

    USAGE (from a sibling generator in this directory):

        local HERE   = (arg[0]:gsub("\\","/")):match("^(.*)/[^/]+$") or "."
        local Shared = assert(loadfile(HERE .. "/gen-shared.lua"))()
--]]

local Shared = {}

----------------------------------------------------------------------
-- Guards
----------------------------------------------------------------------
Shared.MEM_CEILING_KB = 300 * 1024
Shared.ITER_CEILING   = 250000

function Shared.guard(what)
    if collectgarbage("count") > Shared.MEM_CEILING_KB then
        io.stderr:write(("ABORT: %s exceeded the 300 MB memory ceiling\n"):format(what))
        os.exit(3)
    end
end

-- A bounded pairs(): raises rather than spinning if the input is pathological.
function Shared.each(t, what, fn)
    local n = 0
    for k, v in pairs(t or {}) do
        n = n + 1
        if n > Shared.ITER_CEILING then
            io.stderr:write(("ABORT: %s exceeded %d iterations\n")
                :format(what, Shared.ITER_CEILING))
            os.exit(3)
        end
        fn(k, v)
    end
    Shared.guard(what)
    return n
end

-- A bounded ipairs(), for the same reason.
function Shared.eachi(t, what, fn)
    for i = 1, #(t or {}) do
        if i > Shared.ITER_CEILING then
            io.stderr:write(("ABORT: %s exceeded %d iterations\n")
                :format(what, Shared.ITER_CEILING))
            os.exit(3)
        end
        fn(i, t[i])
    end
    Shared.guard(what)
    return #(t or {})
end

----------------------------------------------------------------------
-- Paths
----------------------------------------------------------------------
function Shared.slash(p) return (tostring(p):gsub("\\", "/")) end

-- The owner's own account-1 SavedVariables. This is the intact evidence source:
-- a completed scan of a real Era client (build 68940), 10 504 equippable ids.
Shared.DEFAULT_SV =
    [[C:\Program Files (x86)\World of Warcraft\_classic_era_\WTF\Account\309992577#1\SavedVariables\Daseeki-Armory.lua]]

-- Where a generator lives, and the repo it writes into.
function Shared.Locate(argv)
    local here = Shared.slash(argv[0]):match("^(.*)/[^/]+$") or "."
    local repo = Shared.slash(argv[1] or (here .. "/.."))
    return here, repo, function(rel) return repo .. "/" .. rel end
end

----------------------------------------------------------------------
-- THE CACHE CODEC, as itemScan.lua wrote it (legacy meta layout).
--
--   quality 4 bits | classMask 12 bits | faction 2 bits | internal | unread
--
-- The classMask/faction field is DEAD in the shipped addon (1.3.1 moved the locks
-- into restrictions.lua and stopped writing those bits), but the owner's evidence
-- cache was written by a build that still populated them, and it is precisely
-- those bits that gen-restrictions.lua harvests. So the generator reads the FULL
-- legacy word while the addon reads only the two live fields.
----------------------------------------------------------------------
-- -> quality, classMask, faction, internal, unread
function Shared.unpackMeta(n)
    n = math.floor(tonumber(n) or 0); if n < 0 then n = 0 end
    return n % 16,                          -- quality
           math.floor(n / 16) % 4096,       -- classMask  (legacy; dead in the addon)
           math.floor(n / 65536) % 4,       -- faction    (legacy; dead in the addon)
           math.floor(n / 262144) % 2 == 1, -- internal
           math.floor(n / 524288) % 2 == 1  -- unread     (legacy; dead in the addon)
end

----------------------------------------------------------------------
-- Loaders
----------------------------------------------------------------------

-- (a) THE EVIDENCE CACHE — a developer's own Daseeki-Armory SavedVariables.
--
-- Pass "-" for SV to build with no evidence at all. Supported, and it is how the
-- generators stay runnable on a machine that has never played the game, but it is
-- for emergencies, not for a release.
--
-- REFUSES A DAMAGED SOURCE. A file that loads but holds a truncated or empty
-- names table is worse than no file: it would silently generate a catalog missing
-- thousands of items, and the missing rows would look exactly like items that do
-- not exist. minRows is the floor a caller is willing to accept.
-- -> cache | nil (when SV == "-")
function Shared.LoadScanCache(SV, minRows)
    if SV == "-" then return nil end
    local fn, err = loadfile(SV)
    if not fn then
        io.stderr:write("ABORT: cannot read the scan SavedVariables -> " .. tostring(err) .. "\n")
        io.stderr:write("       pass its path as argument 2, or '-' to build without evidence.\n")
        os.exit(2)
    end
    local env = {}
    setfenv(fn, env)
    local ok, rerr = pcall(fn)
    if not ok then
        io.stderr:write("ABORT: the SavedVariables file raised -> " .. tostring(rerr) .. "\n")
        os.exit(2)
    end
    local cache = env.DaseekiArmoryScanDB
    if type(cache) ~= "table" or type(cache.names) ~= "table" then
        io.stderr:write("ABORT: that file holds no DaseekiArmoryScanDB with a names table\n")
        os.exit(2)
    end
    local n = 0
    Shared.each(cache.names, "cache integrity count", function() n = n + 1 end)
    if n < (minRows or 1) then
        io.stderr:write(("ABORT: that cache holds only %d rows; at least %d were required.\n")
            :format(n, minRows or 1))
        io.stderr:write("       A partial or wiped cache must not be used to generate shipped\n")
        io.stderr:write("       data — the missing rows would be indistinguishable from items\n")
        io.stderr:write("       that do not exist. Restore an intact cache and re-run.\n")
        os.exit(2)
    end
    cache._rowCount = n
    return cache
end

-- (b) THE SEED — dev/itemDB-seed.lua, the AtlasLoot-derived snapshot.
--
-- NOT SHIPPED ANY MORE (1.3.1). It was itemDB.lua in the addon root until the
-- catalog superseded it as a name source; it survives here because it is still
-- the ONLY source for the Tier-3 class masks that the owner's client never loaded
-- (Addon.ItemClassMask), and gen-restrictions.lua needs that for every future
-- regeneration. Keeping the file is cheaper and far more honest than telling the
-- next person to go dig it out of git history.
-- -> a table carrying .ItemNameDB and .ItemClassMask
function Shared.LoadSeed(P)
    local seed = {}
    local path = P("dev/itemDB-seed.lua")
    local fn, err = loadfile(path)
    if not fn then
        io.stderr:write("ABORT: cannot compile " .. path .. " -> " .. tostring(err) .. "\n")
        os.exit(2)
    end
    fn("Daseeki-Armory", seed)
    return seed
end

-- (c) THE ADDON'S OWN DENYLIST. itemScan.lua touches no WoW API at load — that is
-- a property the headless harness already depends on — so a generator can load it
-- and ask Scan.IsInternalName the very same question the addon will ask at
-- runtime. This is what BAKES THE DENYLIST AT GENERATION TIME: the catalog is
-- filtered by the shipped patterns, by the shipped code, so a pattern the addon
-- believes in and a row the catalog contains can never disagree.
function Shared.LoadScanModule(P)
    local A = {}
    local path = P("itemScan.lua")
    local fn, err = loadfile(path)
    if not fn then
        io.stderr:write("ABORT: cannot compile " .. path .. " -> " .. tostring(err) .. "\n")
        os.exit(2)
    end
    local ok, rerr = pcall(fn, "Daseeki-Armory", A)
    if not ok then
        io.stderr:write("ABORT: " .. path .. " raised at load -> " .. tostring(rerr) .. "\n")
        os.exit(2)
    end
    if type(A.ItemScan) ~= "table" or type(A.ItemScan.IsInternalName) ~= "function" then
        io.stderr:write("ABORT: " .. path .. " did not publish Addon.ItemScan.IsInternalName\n")
        os.exit(2)
    end
    return A.ItemScan
end

----------------------------------------------------------------------
-- Emitting
----------------------------------------------------------------------

-- Write a generated file and then COMPILE WHAT WE JUST WROTE, so a generator bug
-- cannot ship a file that will not load at login. -> the loaded Addon table.
--
-- TEXT MODE, DELIBERATELY, AND THE TRAP THAT COMES WITH IT. The repo is checked
-- out with core.autocrlf=true, so every other file in the working tree has CRLF
-- endings; writing "wb" here would make the generated files the odd ones out, and
-- git would convert them back to CRLF on the next checkout anyway. So text mode
-- it is, and the generated files match their neighbours.
--
-- The trap is that catalog.lua carries its payload INSIDE a long-bracket string
-- with a newline between every record, so those newlines become CRLF too, and a
-- reader that splits on "\n" alone would hand back every item name with a
-- trailing carriage return. The answer is not to fight the line endings — a zip
-- tool, an editor or a future .gitattributes could reintroduce them at any time —
-- but to make the reader immune: every parse of that payload, here and in
-- Scan.CatalogEach, matches [^\r\n]+ and is therefore correct under either
-- convention. This comment is the reason that pattern looks over-careful.
function Shared.WriteAndVerify(path, text)
    local f, ferr = io.open(path, "w")
    if not f then
        io.stderr:write("ABORT: cannot write " .. path .. " -> " .. tostring(ferr) .. "\n")
        os.exit(2)
    end
    f:write(text)
    f:close()

    local fn, err = loadfile(path)
    if not fn then
        io.stderr:write("ABORT: the generated file does not compile -> " .. tostring(err) .. "\n")
        os.exit(2)
    end
    local A = {}
    local ok, rerr = pcall(fn, "Daseeki-Armory", A)
    if not ok then
        io.stderr:write("ABORT: the generated file raised at load -> " .. tostring(rerr) .. "\n")
        os.exit(2)
    end
    return A
end

return Shared
