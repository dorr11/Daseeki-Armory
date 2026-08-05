--[[
    dev/gen-catalog.lua — BUILD THE SHIPPED ITEM CATALOG.

    WHY THIS EXISTS
    ---------------
    The goal picker's item list is as static as the class locks beside it. Classic
    Era is a FROZEN CLIENT: the set of equippable items it holds does not change
    between two players, between two accounts, or between two Tuesdays. Deriving
    that list at runtime — a minute-long walk of 32 000 item ids, per account,
    behind a first-login timer and a "Rescan Items" button — was asking every user
    to re-measure a constant, and then persisting their private copy of the answer.

    The owner put it plainly: "I thought we decided to move toward a static list."
    Requiring anyone to scan was the old architecture leaking through. So the
    catalog is computed ONCE, here, on a developer's machine, and shipped as
    catalog.lua. A player who has never scanned anything has the complete picker
    on their first login, because the picker is not derived — it is delivered.

    HOW TO RUN
        lua5.1 dev/gen-catalog.lua [REPO_DIR] [SCAN_SV_PATH]

    REPO_DIR      defaults to the parent of this file. catalog.lua is written
                  there (overwritten in place).
    SCAN_SV_PATH  a developer's own Daseeki-Armory SavedVariables, whose
                  DaseekiArmoryScanDB holds a COMPLETED scan. Defaults to the
                  owner's account-1 path. Unlike gen-restrictions.lua there is no
                  "-" mode: a catalog with no evidence behind it is not a catalog.

    THE SOURCE, and why it is trustworthy. A completed scan is an exhaustive census
    of the client's own item space: phase 1 walks ids 1..32000 through
    GetItemInfoInstant — a purely local lookup, no server, no luck involved — and
    keeps every id whose equip location is one Armory manages. So the cache is not
    a sample of what one player happened to see; it is the client's item table,
    filtered to equippable gear. That is why one developer's cache can speak for
    every player on the same build, and why this file can exist at all.

    THE DENYLIST IS BAKED IN HERE, AT GENERATION TIME. Blizzard's own scaffolding —
    placeholders, creature-equipment art, designer test gear, retired duplicates —
    is roughly 12% of everything the walk finds, and none of it is a fact any user
    needs. Rather than ship 1 264 rows so that every client can re-decide, for
    itself, every login, that they are junk, they are simply NOT IN THE FILE. The
    filter is Scan.IsInternalName, loaded out of the shipped itemScan.lua, so the
    patterns that condemned a row here are the identical patterns the addon
    believes in — the catalog and the denylist cannot drift apart.

    Consequence worth stating: growing INTERNAL_PATTERNS no longer reaches into a
    user's cache to re-flag rows, because there is no user cache. It reaches the
    catalog on the NEXT REGENERATION, which is a release. That is the trade: a
    denylist fix ships with a build instead of arriving on a login.

    WHAT IS DELIBERATELY *NOT* BAKED OUT: Addon.StaticUnobtainable. Those ids stay
    in the catalog and are dropped by the row predicate at runtime, exactly as
    before, because that list is a POLICY LIST a person is meant to be able to
    change in one line — "deleting a line puts the item straight back in the
    picker, no code change". Baking it into the catalog would quietly break that
    promise, since the item would then also have to be regenerated back in.

    WHAT IS NOT IN THE CATALOG, and does not need to be: equipLoc, icon, classID
    and subclassID. GetItemInfoInstant answers all four offline, synchronously, for
    any id the client holds — the addon has always re-derived them rather than
    persisting them, precisely so they cannot go stale against a client data
    change. Shipping them would be a second copy of a fact the client already
    volunteers, and there is a second benefit to leaving them out: an id in this
    catalog that the RUNNING client does not have answers nil, and the picker drops
    the row. The catalog is therefore self-limiting to what the player's own client
    actually knows, which is the property the seed it replaces never had.

    HEADLESS DISCIPLINE: guards and ceilings come from gen-shared.lua; every loop
    here is bounded and the memory guard aborts past 300 MB.
--]]

local HERE = ((arg[0] or "gen-catalog.lua"):gsub("\\", "/")):match("^(.*)/[^/]+$") or "."
local Shared = assert(loadfile(HERE .. "/gen-shared.lua"))()

local _, REPO, P = Shared.Locate(arg)
local SV = arg[2] or Shared.DEFAULT_SV

local each, eachi, guard = Shared.each, Shared.eachi, Shared.guard

-- The owner's intact cache holds 10 504 rows. A source that has lost most of that
-- is a wiped or half-written cache, and generating from it would ship a catalog
-- with thousands of items silently missing. Refuse rather than guess.
local MIN_CACHE_ROWS = 8000

local log = {}
local function say(fmt, ...)
    local s = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    log[#log + 1] = s
    print(s)
end

say("gen-catalog: repo = %s", REPO)

----------------------------------------------------------------------
-- Load the sources
----------------------------------------------------------------------
local Scan  = Shared.LoadScanModule(P)
local cache = Shared.LoadScanCache(SV, MIN_CACHE_ROWS)
if not cache then
    io.stderr:write("ABORT: gen-catalog has no '-' mode. A catalog needs evidence.\n")
    os.exit(2)
end
say("evidence: %s", SV)
say("  %d rows, build %s, ids %s, scanned %s",
    cache._rowCount, tostring(cache.build), tostring(cache.ranges),
    tostring(cache.scannedAt))

----------------------------------------------------------------------
-- THE RECORD FORMAT, and the measurement that chose it.
--
-- One line per item, inside one long-bracket string:
--
--     <itemID> <quality> <name>
--
-- FIVE FORMATS WERE BUILT AND MEASURED on the real 9 240-row payload, under the
-- vendored Lua 5.1 (file size / deflate / resident KB after load+collect):
--
--   table constructor, [id]="<q><name>"      283 KB /  81 KB / 1 149 KB
--   two parallel tables (name + quality)     363 KB / 107 KB / 1 780 KB
--   one long string, "<id> <q> <name>"       246 KB /  80 KB /   240 KB  <- CHOSEN
--   long strings grouped by quality          227 KB /  78 KB /   223 KB
--   ditto, with delta-encoded ids            195 KB /  59 KB /   191 KB
--
-- THE TABLE CONSTRUCTOR LOSES ON THE ONLY AXIS THAT REALLY COSTS ANYTHING. It is
-- 4.8x the resident memory — 1.1 MB permanently in every player's client, for
-- 9 240 hash nodes and 9 240 interned strings — and it buys random access by id
-- that nothing wants: both consumers (the picker's index build, the icon search
-- index) walk the whole thing exactly once and then never touch it again. A
-- stream is what they need, so a stream is what is shipped, and the addon pays
-- 240 KB instead of 1.1 MB.
--
-- THE TWO SMALLER VARIANTS WERE REJECTED ON PURPOSE, and the reason is the same
-- reason restrictions.lua carries a comment beside every id. This is EVIDENCE,
-- and evidence you cannot read is not evidence. Grouping by quality breaks the
-- single monotone id order; delta-encoding replaces the id with a hop count, so
-- searching this file for "19019" would no longer find Thunderfury. The chosen
-- format costs 18 KB over the grouped form and 51 KB over the delta form, and in
-- exchange every line is a complete, greppable, self-describing record. For a
-- once-per-release download that is the right side of the trade.
--
-- SAFE WITHOUT ESCAPING, and asserted rather than assumed. Censused across all
-- 9 240 shipped names: no tabs, no newlines, no backslashes, and not one ']'
-- anywhere, so a [==[ ]==] block cannot be closed early and the four names that
-- contain a double quote need no handling at all. assertNameSafe below re-checks
-- every row on every run, so a future client build that introduces such a name
-- stops the generator instead of silently corrupting the file.
--
-- READ IT BACK WITH [^\r\n]+, NEVER [^\n]+. The file is written in text mode into
-- a CRLF working tree, so the record separator on disk is "\r\n" and a name
-- captured with [^\n]+ would carry a trailing carriage return into the picker.
-- See the long note on Shared.WriteAndVerify; the same pattern discipline applies
-- to Scan.CatalogEach, which is the addon's own reader.
----------------------------------------------------------------------
local function assertNameSafe(id, name)
    if type(name) ~= "string" or name == "" then
        io.stderr:write(("ABORT: id %d has no usable name\n"):format(id))
        os.exit(3)
    end
    if name:find("[\r\n\t]") then
        io.stderr:write(("ABORT: id %d (%q) contains a tab or newline; the line-per-record\n")
            :format(id, name))
        io.stderr:write("       format cannot carry it. Change the format, not the name.\n")
        os.exit(3)
    end
    if name:find("]", 1, true) then
        io.stderr:write(("ABORT: id %d (%q) contains ']'; the [==[ ]==] wrapper is no\n")
            :format(id, name))
        io.stderr:write("       longer provably safe. Change the wrapper, not the name.\n")
        os.exit(3)
    end
end

----------------------------------------------------------------------
-- Build
----------------------------------------------------------------------
local ids = {}
each(cache.names, "cache rows", function(id) ids[#ids + 1] = id end)
table.sort(ids)
guard("sort")

local rows, dropped, byQuality = {}, 0, {}
local nameBytes, longest, longestName = 0, 0, ""

eachi(ids, "catalog rows", function(_, id)
    local name = cache.names[id]
    local quality = Shared.unpackMeta(cache.meta and cache.meta[id])

    -- THE DENYLIST, RE-DERIVED rather than trusted. The cache carries its own
    -- internal bit, but that bit was written by whatever pattern list was current
    -- when the scan ran. Asking the SHIPPED Scan.IsInternalName again makes the
    -- catalog a function of the code being released, not of the day the evidence
    -- was captured. (On the owner's cache the two agree on all 10 504 rows, which
    -- is reported below as a cross-check rather than assumed.)
    if Scan.IsInternalName(name) then
        dropped = dropped + 1
        return
    end

    assertNameSafe(id, name)
    rows[#rows + 1] = { id = id, q = quality, name = name }
    byQuality[quality] = (byQuality[quality] or 0) + 1
    nameBytes = nameBytes + #name
    if #name > longest then longest, longestName = #name, name end
end)

-- The cross-check the loop above deliberately did not fold into its own counter:
-- how many rows the shipped patterns judge differently from the captured bit.
local disagree = 0
each(cache.names, "denylist cross-check", function(id, name)
    local _, _, _, cachedInternal = Shared.unpackMeta(cache.meta and cache.meta[id])
    if Scan.IsInternalName(name) ~= cachedInternal then disagree = disagree + 1 end
end)

say("denylist: %d rows condemned by Scan.IsInternalName (%d shipped)", dropped, #rows)
say("  cross-check vs the captured internal bit: %d disagreement%s%s",
    disagree, disagree == 1 and "" or "s",
    disagree == 0 and " — the shipped patterns and the evidence agree on every row." or
    " — the SHIPPED patterns were used; the captured bit is older.")
say("  names: %d bytes total, %.1f average, %d longest (%s)",
    nameBytes, nameBytes / math.max(1, #rows), longest, longestName)

----------------------------------------------------------------------
-- Emit
----------------------------------------------------------------------
local out = {}
local function w(s) out[#out + 1] = s end

local qLabel = { [0] = "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Artifact" }
local qLines = {}
for q = 0, 7 do
    if byQuality[q] then
        qLines[#qLines + 1] = ("--     %d %-10s %5d"):format(q, qLabel[q] or "?", byQuality[q])
    end
end

w("--[==[")
w("    Daseeki Armory — THE SHIPPED ITEM CATALOG.")
w("")
w("    GENERATED FILE. Built by dev/gen-catalog.lua; regenerate rather than")
w("    hand-edit. It has no policy in it at all — every judgement call about what")
w("    a player may be offered lives in restrictions.lua, which IS hand-editable.")
w("")
w("    WHY THIS FILE EXISTS. Classic Era is a frozen client, so the set of")
w("    equippable items it holds is a constant — the same on every account, every")
w("    realm and every login. Until 1.3.1 the goal picker measured that constant")
w("    itself: a minute-long walk of 32 000 item ids, once per account, behind a")
w("    first-login timer and a \"Rescan Items\" button, with the private answer")
w("    persisted to SavedVariables. A frozen fact does not need measuring by the")
w("    person reading it. It needs shipping.")
w("")
w("    So the picker now arrives COMPLETE. A brand-new account, first login, no")
w("    scan, no wait: open a slot and the whole list is there.")
w("")
w("    THE CONTRACT the rest of the addon depends on:")
w("")
w("      Addon.StaticCatalogRaw    one long string, one line per item:")
w("")
w("                                    <itemID> <quality> <name>")
w("")
w("                                ids ascending; quality is the client's own")
w("                                0..6; the name runs to end of line and is")
w("                                verbatim from the client.")
w("")
w("      Addon.StaticCatalogCount  how many lines that string holds, as a literal,")
w("                                so counting never costs a parse.")
w("")
w("      Read it through Scan.CatalogEach(fn) in itemScan.lua — the parser lives")
w("      there, with the rest of the pure layer, where the harness can pin it.")
w("")
w("    WHY A STRING AND NOT A TABLE. Both consumers stream this once and never")
w("    look again, so a table would be 1.1 MB of permanent hash nodes to serve two")
w("    linear walks. The string is 240 KB resident. Five formats were built and")
w("    measured on this exact payload; the numbers are in dev/gen-catalog.lua.")
w("")
w("    WHAT IS NOT HERE. equipLoc, icon, classID and subclassID — GetItemInfoInstant")
w("    answers all four offline for any id the client holds, so they are re-derived")
w("    at index time and cannot go stale. That also makes the catalog self-limiting:")
w("    an id this catalog names but the running client does not have is dropped, so")
w("    a build mismatch quietly shrinks the list instead of offering phantoms.")
w("")
w("    BLIZZARD'S SCAFFOLDING IS ALREADY GONE. Placeholders, creature-equipment")
w("    art, designer test gear and retired duplicates were removed at generation")
w("    time by Scan.IsInternalName — the same function, from the same file, that")
w("    the addon would have used at runtime. They are not facts a user needs, so")
w("    they are not shipped. Items that are real but that no player can obtain")
w("    (Ashbringer, the Warglaives, the GM stones) ARE still here, and are hidden")
w("    by Addon.StaticUnobtainable at runtime — that list is policy, and policy")
w("    must stay editable in one line.")
w("--]==]")
w("")
w("local _, Addon = ...")
w("")
w(("-- %d items · %d bytes of names · quality census:"):format(#rows, nameBytes))
for _, l in ipairs(qLines) do w(l) end
w(("-- Generated from a completed scan of build %s over ids %s."):format(
    tostring(cache.build), tostring(cache.ranges)))
w(("-- %d of the client's %d equippable records were withheld as Blizzard's own"):format(
    dropped, cache._rowCount))
w("-- scaffolding (dev/gen-catalog.lua bakes the denylist in; see itemScan.lua).")
w("")
w(("Addon.StaticCatalogCount = %d"):format(#rows))
w("")
w("Addon.StaticCatalogRaw = [==[")

local body = {}
eachi(rows, "emit", function(i, r)
    body[i] = ("%d %d %s"):format(r.id, r.q, r.name)
end)
w(table.concat(body, "\n"))
w("]==]")
w("")

local text = table.concat(out, "\n")
local path = P("catalog.lua")
local A = Shared.WriteAndVerify(path, text)

----------------------------------------------------------------------
-- Verify what we just wrote, by reading it back the way the addon will
----------------------------------------------------------------------
if type(A.StaticCatalogRaw) ~= "string" then
    io.stderr:write("ABORT: the generated file published no StaticCatalogRaw string\n")
    os.exit(2)
end
if A.StaticCatalogCount ~= #rows then
    io.stderr:write(("ABORT: declared count %s but built %d rows\n")
        :format(tostring(A.StaticCatalogCount), #rows))
    os.exit(2)
end

local seen, n, sumId, sumQ, sumLen = {}, 0, 0, 0, 0
for sid, sq, nm in A.StaticCatalogRaw:gmatch("(%d+) (%d+) ([^\r\n]+)") do
    n = n + 1
    if n > Shared.ITER_CEILING then
        io.stderr:write("ABORT: readback exceeded the iteration ceiling\n"); os.exit(3)
    end
    local id = tonumber(sid)
    if seen[id] then
        io.stderr:write(("ABORT: id %d appears twice in the generated catalog\n"):format(id))
        os.exit(2)
    end
    seen[id] = true
    sumId, sumQ, sumLen = sumId + id, sumQ + tonumber(sq), sumLen + #nm
end
guard("readback")

local wantId, wantQ = 0, 0
eachi(rows, "checksum", function(_, r) wantId = wantId + r.id; wantQ = wantQ + r.q end)

if n ~= #rows or sumId ~= wantId or sumQ ~= wantQ or sumLen ~= nameBytes then
    io.stderr:write(("ABORT: readback disagrees — rows %d/%d, id sum %d/%d, quality sum %d/%d, name bytes %d/%d\n")
        :format(n, #rows, sumId, wantId, sumQ, wantQ, sumLen, nameBytes))
    os.exit(2)
end

local fh = io.open(path, "rb")
local bytes = fh and #fh:read("*a") or 0
if fh then fh:close() end

say("WROTE %s", path)
say("VERIFIED: %d rows read back, ids unique, name bytes and quality sums match.", n)
say("FINAL: %d catalog entries, %d bytes on disk (%.1f KB).", #rows, bytes, bytes / 1024)
say("peak lua memory: %.1f MB", collectgarbage("count") / 1024)
