--[[
    dev/gen-restrictions.lua — BUILD THE SHIPPED RESTRICTION TABLE.

    WHY THIS EXISTS
    ---------------
    Class and faction locks are STATIC FACTS of a frozen game. Deriving them at
    runtime, per account, per session, off an asynchronous tooltip that may or may
    not have the item behind it, produced four generations of state machinery
    (tooltip scan -> retries -> data gate -> repair passes, stamps and latches)
    that fought each other and still left Bonescythe on a warrior. A fact that
    never changes belongs in the addon, not in a state machine.

    So the locks are computed ONCE, here, on a developer's machine, and shipped as
    restrictions.lua. The addon reads the table; it never derives a lock again.

    HOW TO RUN
        lua5.1 dev/gen-restrictions.lua [REPO_DIR] [SCAN_SV_PATH]

    REPO_DIR      defaults to the parent of this file. restrictions.lua is written
                  there (overwritten in place).
    SCAN_SV_PATH  the developer's own Daseeki-Armory SavedVariables file, whose
                  DaseekiArmoryScanDB holds the class/faction locks a real client
                  did read off real tooltips. Defaults to the owner's account-1
                  path. Pass "-" to build with NO evidence source (seed + static
                  knowledge only) — supported, but it drops ~260 real locks, so it
                  is for emergencies, not for a release.

    THE THREE SOURCES, in precedence order (higher wins; disagreements are logged):

      a) EVIDENCE   the scan cache's captured locks. A tooltip that rendered
                    "Classes: Rogue" is the client telling us the truth about its
                    own item. Highest confidence.
      b) SEED       Addon.ItemClassMask in the bundled itemDB.lua (AtlasLoot-
                    derived). Covers the Tier-3 band the owner's client never
                    loaded, which is the exact hole that started this saga.
      c) STATIC     knowledge written down here: the Naxxramas Tier-3 sets
                    (cross-checked against b, see T3_SETS) and the four Atiesh
                    variants, which no source in this repo can distinguish because
                    all four carry the identical name.

    NOT A SOURCE, deliberately: weapon/armour proficiency. Librams, Idols and
    Totems are not class-LOCKED, they are class-PROFICIENT — armour subclasses
    7/8/9 reachable only by Paladin/Druid/Shaman respectively — and Scan.PROF in
    itemScan.lua already filters them numerically and locale-free. Duplicating that
    as data would be two mechanisms for one fact.

    HEADLESS DISCIPLINE: every loop below carries an explicit iteration ceiling and
    the memory guard aborts past 300 MB, so a malformed input cannot spin this into
    a runaway.
--]]

----------------------------------------------------------------------
-- Guards
----------------------------------------------------------------------
local MEM_CEILING_KB = 300 * 1024
local ITER_CEILING   = 250000

local function guard(what)
    if collectgarbage("count") > MEM_CEILING_KB then
        io.stderr:write(("ABORT: %s exceeded the 300 MB memory ceiling\n"):format(what))
        os.exit(3)
    end
end

-- A bounded pairs(): raises rather than spinning if the input is pathological.
local function each(t, what, fn)
    local n = 0
    for k, v in pairs(t or {}) do
        n = n + 1
        if n > ITER_CEILING then
            io.stderr:write(("ABORT: %s exceeded %d iterations\n"):format(what, ITER_CEILING))
            os.exit(3)
        end
        fn(k, v)
    end
    guard(what)
    return n
end

----------------------------------------------------------------------
-- Paths
----------------------------------------------------------------------
local function slash(p) return (tostring(p):gsub("\\", "/")) end
local HERE = slash(arg[0]):match("^(.*)/[^/]+$") or "."
local REPO = slash(arg[1] or (HERE .. "/.."))
local SV   = arg[2] or
    [[C:\Program Files (x86)\World of Warcraft\_classic_era_\WTF\Account\309992577#1\SavedVariables\Daseeki-Armory.lua]]

local function P(rel) return REPO .. "/" .. rel end

----------------------------------------------------------------------
-- The model (kept in step with Scan.CLASS_BIT in itemScan.lua)
----------------------------------------------------------------------
local CLASS_BIT = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
    SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024,
}
local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
                      "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local ALL_CLASSES = 0
for _, c in ipairs(CLASS_ORDER) do ALL_CLASSES = ALL_CLASSES + CLASS_BIT[c] end

local FACTION_NONE, FACTION_ALLIANCE, FACTION_HORDE = 0, 1, 2
local FACTION_NAME = { [1] = "ALLIANCE", [2] = "HORDE" }

-- The shipped packing: classMask (0..4095) in the low bits, faction (0..2) above.
local STATIC_SHIFT = 4096
local function pack(classMask, faction)
    return (tonumber(classMask) or 0) + (tonumber(faction) or 0) * STATIC_SHIFT
end

local function hasBit(mask, b) return math.floor(mask / b) % 2 == 1 end

-- "ROGUE" / "MAGE+PRIEST+WARLOCK+DRUID" / "" for a mask
local function maskNames(mask)
    local parts = {}
    for _, c in ipairs(CLASS_ORDER) do
        if hasBit(mask, CLASS_BIT[c]) then parts[#parts + 1] = c end
    end
    return table.concat(parts, "+")
end

-- A mask that permits every one of the nine classes says nothing at all; it is
-- the seed's way of writing "any class may wear this", which is what an ABSENT
-- entry already means. Shipping it would be a row that can never hide anything.
local function isNoOpMask(mask)
    if mask <= 0 then return true end
    for _, c in ipairs(CLASS_ORDER) do
        if not hasBit(mask, CLASS_BIT[c]) then return false end
    end
    return true
end

----------------------------------------------------------------------
-- The cache codec, as itemScan.lua wrote it (legacy meta layout).
--   quality 4 bits | classMask 12 bits | faction 2 bits | internal | unread
----------------------------------------------------------------------
local function unpackMeta(n)
    n = math.floor(tonumber(n) or 0); if n < 0 then n = 0 end
    return n % 16,                        -- quality
           math.floor(n / 16) % 4096,     -- classMask
           math.floor(n / 65536) % 4,     -- faction
           math.floor(n / 262144) % 2 == 1,   -- internal
           math.floor(n / 524288) % 2 == 1    -- unread
end

----------------------------------------------------------------------
-- (c) STATIC KNOWLEDGE
----------------------------------------------------------------------

-- The nine Naxxramas Tier-3 sets. Matched inside the T3 id band ONLY: id 22406
-- is a green sword literally named "Redemption" and a bare prefix match would
-- lock it to paladins.
local T3_BAND = { 22416, 22519 }
local T3_SETS = {
    { class = "WARRIOR", prefix = "Dreadnaught",  label = "Dreadnaught"          },
    { class = "PALADIN", prefix = "Redemption",   label = "Redemption"           },
    { class = "HUNTER",  prefix = "Cryptstalker", label = "Cryptstalker"         },
    { class = "ROGUE",   prefix = "Bonescythe",   label = "Bonescythe"           },
    { class = "SHAMAN",  prefix = "Earthshatter", label = "Earthshatter"         },
    { class = "MAGE",    prefix = "Frostfire",    label = "Frostfire"            },
    { class = "WARLOCK", prefix = "Plagueheart",  label = "Plagueheart"          },
    { class = "DRUID",   prefix = "Dreamwalker",  label = "Dreamwalker"          },
    -- The priest set is the one named by SUFFIX: "Robe of Faith", "Circlet of
    -- Faith" … There is no "Vestments of Faith" item; that is the set's name.
    { class = "PRIEST",  suffix = " of Faith",    label = "Vestments of Faith"   },
}

-- ATIESH. Four ids, one name, and nothing in this repo or in the client cache can
-- tell them apart: the owner's scan captured all four as "Atiesh, Greatstaff of
-- the Guardian" with no mask, the bundled seed carries the same four names and no
-- mask at all, and every variant is the same staff (weapon subclass 10) so
-- proficiency cannot separate them either.
--
-- The mapping below is therefore STATIC KNOWLEDGE and is flagged as such in the
-- generated file: 22589 Mage, 22630 Warlock, 22631 Priest, 22632 Druid.
--
-- WHAT IS AND IS NOT AT RISK IF ONE PAIR IS SWAPPED. The load-bearing fact — the
-- owner's actual bug — is that NO Atiesh may be offered to a warrior, paladin,
-- hunter, rogue or shaman, and that holds however the four caster classes are
-- distributed across the four ids. A swap would cost a mage seeing the druid copy
-- and not his own; it is one line of data to correct and the harness pins the
-- shape (a permutation of exactly those four classes, none of the other five).
local ATIESH = {
    [22589] = "MAGE",
    [22630] = "WARLOCK",
    [22631] = "PRIEST",
    [22632] = "DRUID",
}

-- UNOBTAINABLE BY HISTORY. Real client records for items no player can acquire on
-- a live Era realm: never itemised into the loot tables, or removed before the
-- game froze. They are not "unusable" (a different character cannot get one
-- either), so — exactly like Blizzard's internal placeholders — "Show unusable"
-- does not reveal them.
--
-- OWNER-REVIEWED, PER ENTRY. This list is no longer an open question: the owner
-- has walked it twice on 2026-08-04, and every surviving row now carries its own
-- sign-off below. Deleting a line here puts an item straight back in the picker
-- with no code change and no rescan, which is why it is data — and which is why
-- three lines left it on the second pass rather than being argued about in code.
--
-- THE ANNIVERSARY CORRECTION, and the lesson in it. The first pass reasoned from
-- ORIGINAL VANILLA history: Highlord Kruul was a Scourge Invasion boss whose
-- blades never settled into a permanent loot table, so they were filed here as
-- unobtainable. That framing was wrong for the realm this addon is actually used
-- on. Classic Era ANNIVERSARY realms re-ran the Scourge Invasion and the blades
-- are genuine, farmable drops there. Owner correction 2026-08-04, verbatim:
-- "Gressil Iblis and Neretzek are all obtainable unless there is another version
-- in the code that reads as legendary."
--
-- That caveat was checked before acting, not assumed away. A census of the
-- owner's account-1 scan cache AND the bundled seed for every id whose name
-- mentions Gressil, Iblis, Neretzek or Untamed returned FOUR ids, no twins: each
-- blade exists exactly once, in both sources, under one name, at quality 4 (Epic)
-- — 21856, 23014, 23054, plus 19334 The Untamed Blade, which was never on this
-- list and stays offerable. There is no legendary display twin to keep hiding, so
-- all three were removed outright rather than split. The one legendary in the
-- neighbourhood is 22736 Andonisus, and it stays — for a different reason, given
-- on its own line.
--
-- The standing rule this leaves behind: "no player can get one" must be judged
-- against ERA-AS-PLAYED, including Anniversary event re-runs, not against a
-- 2006 loot table. Removed 2026-08-04 per the correction above: 21856 Neretzek,
-- The Blood Drinker · 23014 Iblis, Blade of the Fallen Seraph · 23054 Gressil,
-- Dawn of Ruin.
local UNOBTAINABLE = {
    -- OWNER DECISION 2026-08-04, verbatim: "only corrupted ashbringer stays".
    -- The original Ashbringer never reached a live Era loot table; the client
    -- carries the record and nothing else. Its sibling 22691 Corrupted
    -- Ashbringer is a genuine Naxxramas drop and a legitimate goal, so it is
    -- DELIBERATELY ABSENT from this list and stays offerable.
    { 13262, "Ashbringer" },

    -- SIGNED OFF IMPLICITLY 2026-08-04, by surviving both owner passes (the
    -- Ashbringer decision and the Kruul correction) untouched. Never itemised on
    -- any Era realm, Anniversary included: these are Burning Crusade records the
    -- frozen client happens to carry.
    { 18582, "The Twin Blades of Azzinoth" },
    { 18583, "Warglaive of Azzinoth (Right)" },
    { 18584, "Warglaive of Azzinoth (Left)" },

    -- SIGNED OFF IMPLICITLY 2026-08-04, and NOT an oversight in the Kruul pass:
    -- Andonisus is the fourth Scourge Invasion reward and IS obtainable on an
    -- Anniversary realm, but it is a TEMPORARY DECAYING weapon that destroys
    -- itself. A goal you cannot still own once you have it is not a goal, so it
    -- is hidden on the decay, not on the history — the one row here that would
    -- survive even if the Anniversary reasoning were applied to it.
    { 22736, "Andonisus, Reaper of Souls" },
}

----------------------------------------------------------------------
-- Load the sources
----------------------------------------------------------------------
local log = {}
local function say(fmt, ...)
    local s = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    log[#log + 1] = s
    print(s)
end

say("gen-restrictions: repo = %s", REPO)

-- (b) the bundled seed
local seedAddon = {}
do
    local fn, err = loadfile(P("itemDB.lua"))
    if not fn then
        io.stderr:write("ABORT: cannot compile itemDB.lua -> " .. tostring(err) .. "\n")
        os.exit(2)
    end
    fn("Daseeki-Armory", seedAddon)
end
local SEED_MASK = seedAddon.ItemClassMask or {}
local SEED_NAME = seedAddon.ItemNameDB or {}

-- (a) the evidence cache
local cache
if SV ~= "-" then
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
    cache = env.DaseekiArmoryScanDB
    if type(cache) ~= "table" or type(cache.names) ~= "table" then
        io.stderr:write("ABORT: that file holds no DaseekiArmoryScanDB with a names table\n")
        os.exit(2)
    end
end

----------------------------------------------------------------------
-- Build
----------------------------------------------------------------------
-- entry[id] = { mask=, faction=, src="evidence"|"seed"|"static", name=, note= }
local entry, order = {}, {}
local disagreements, normalized = {}, {}

local function place(id, mask, faction, src, name, note)
    id = tonumber(id)
    if not id then return false end
    mask    = math.floor(tonumber(mask) or 0)
    faction = math.floor(tonumber(faction) or 0)
    if mask <= 0 and faction == FACTION_NONE then return false end
    local prev = entry[id]
    if prev then
        if prev.mask ~= mask or prev.faction ~= faction then
            disagreements[#disagreements + 1] = string.format(
                "id %d: %s says mask=%d faction=%d, %s (kept) says mask=%d faction=%d — %s",
                id, src, mask, faction, prev.src, prev.mask, prev.faction,
                tostring(prev.name or name or "?"))
        end
        return false
    end
    entry[id] = { mask = mask, faction = faction, src = src, name = name, note = note }
    order[#order + 1] = id
    return true
end

local names = {}   -- id -> best display name we have, for the provenance comments
each(SEED_NAME, "seed names", function(id, nm) names[id] = nm end)

-- ── (a) evidence ─────────────────────────────────────────────────────────────
local evClass, evFaction, evInternalSkipped, cacheTotal = 0, 0, 0, 0
if cache then
    each(cache.names, "evidence rows", function(id, nm)
        cacheTotal = cacheTotal + 1
        names[id] = nm                       -- the client's own name beats the seed's
        local _, m, f, internal = unpackMeta((cache.meta or {})[id])
        if internal then
            if m > 0 or f ~= FACTION_NONE then evInternalSkipped = evInternalSkipped + 1 end
            return                            -- placeholders never reach the picker
        end
        if m > 0 or f ~= FACTION_NONE then
            if m > 0 and isNoOpMask(m) then
                normalized[#normalized + 1] = string.format(
                    "id %d: evidence mask %d permits all nine classes (a no-op) — dropped · %s",
                    id, m, tostring(nm))
                m = 0
                if f == FACTION_NONE then return end
            end
            if place(id, m, f, "evidence", nm) then
                if m > 0 then evClass = evClass + 1 end
                if f ~= FACTION_NONE then evFaction = evFaction + 1 end
            end
        end
    end)
    say("(a) evidence: %s — %d rows, %d class locks, %d faction locks%s",
        SV, cacheTotal, evClass, evFaction,
        evInternalSkipped > 0
            and (", " .. evInternalSkipped .. " locked rows skipped as internal") or "")
else
    say("(a) evidence: SKIPPED (built without a scan cache)")
end

-- ── (b) the bundled seed ─────────────────────────────────────────────────────
local seedTotal, seedAdded, seedNoOp = 0, 0, 0
each(SEED_MASK, "seed masks", function(id, m)
    seedTotal = seedTotal + 1
    m = math.floor(tonumber(m) or 0)
    if isNoOpMask(m) then
        seedNoOp = seedNoOp + 1
        normalized[#normalized + 1] = string.format(
            "id %d: seed mask %d permits all nine classes (a no-op) — dropped · %s",
            id, m, tostring(names[id]))
        return
    end
    -- A seed mask that agrees with the evidence still goes through place(), which
    -- is where agreement is checked and disagreement recorded.
    if place(id, m, FACTION_NONE, "seed", names[id]) then seedAdded = seedAdded + 1 end
end)
say("(b) seed itemDB.ItemClassMask: %d entries, %d added (%d were already evidence), "
    .. "%d dropped as all-class no-ops", seedTotal, seedAdded,
    seedTotal - seedAdded - seedNoOp, seedNoOp)

-- ── (c) static knowledge: Tier 3 ─────────────────────────────────────────────
-- Resolved from the cache by name inside the T3 id band, then cross-checked
-- against whatever (a) and (b) already said. On the owner's data every piece is
-- already supplied by the seed, so this section normally ADDS nothing and its
-- value is the cross-check: nine sets, eight pieces each, no disagreement.
local t3Found, t3Added, t3Confirmed = 0, 0, 0
if cache then
    local band = {}
    for id = T3_BAND[1], T3_BAND[2] do
        local nm = cache.names[id]
        if nm then band[#band + 1] = { id = id, name = nm } end
        if id - T3_BAND[1] > ITER_CEILING then break end
    end
    guard("T3 band")
    for _, set in ipairs(T3_SETS) do
        local bit, hits = CLASS_BIT[set.class], 0
        for _, row in ipairs(band) do
            local hit = false
            if set.prefix then
                hit = row.name:sub(1, #set.prefix) == set.prefix
            elseif set.suffix then
                hit = row.name:sub(-#set.suffix) == set.suffix
            end
            if hit then
                hits = hits + 1
                t3Found = t3Found + 1
                local prev = entry[row.id]
                if prev then
                    if prev.mask == bit and prev.faction == FACTION_NONE then
                        t3Confirmed = t3Confirmed + 1
                    else
                        disagreements[#disagreements + 1] = string.format(
                            "id %d: static T3 (%s) says mask=%d, %s (kept) says mask=%d — %s",
                            row.id, set.label, bit, prev.src, prev.mask, row.name)
                    end
                elseif place(row.id, bit, FACTION_NONE, "static", row.name,
                             "T3 " .. set.label) then
                    t3Added = t3Added + 1
                end
            end
        end
        if hits ~= 8 then
            say("  !! T3 %s (%s): %d pieces matched in %d-%d, expected 8",
                set.label, set.class, hits, T3_BAND[1], T3_BAND[2])
        end
    end
end
say("(c) static — Naxxramas Tier 3: %d pieces resolved in the %d-%d band, "
    .. "%d confirmed against a higher source, %d added",
    t3Found, T3_BAND[1], T3_BAND[2], t3Confirmed, t3Added)

-- ── (c) static knowledge: Atiesh ─────────────────────────────────────────────
local atieshAdded = 0
local atieshIds = {}
each(ATIESH, "atiesh", function(id) atieshIds[#atieshIds + 1] = id end)
table.sort(atieshIds)
for _, id in ipairs(atieshIds) do
    local class = ATIESH[id]
    if place(id, CLASS_BIT[class], FACTION_NONE, "static",
             names[id] or "Atiesh, Greatstaff of the Guardian",
             "Atiesh " .. class .. " — UNVERIFIABLE from any local source") then
        atieshAdded = atieshAdded + 1
    end
end
say("(c) static — Atiesh: %d of 4 ids added (%s)", atieshAdded,
    "id->class is static knowledge; see the note in the generated file")

----------------------------------------------------------------------
-- Report the cross-source findings
----------------------------------------------------------------------
if #disagreements > 0 then
    say("DISAGREEMENTS (%d) — the higher-precedence source was kept:", #disagreements)
    for i = 1, math.min(#disagreements, 200) do say("    " .. disagreements[i]) end
else
    say("DISAGREEMENTS: none. Every id claimed by more than one source got the "
        .. "same mask from each.")
end
if #normalized > 0 then
    say("NORMALISED (%d) — masks that permit all nine classes cannot hide anything, "
        .. "so they are left out; an absent id already means unrestricted:", #normalized)
    for i = 1, math.min(#normalized, 200) do say("    " .. normalized[i]) end
end

----------------------------------------------------------------------
-- Emit
----------------------------------------------------------------------
table.sort(order)

local bySrc = { evidence = {}, seed = {}, static = {} }
for _, id in ipairs(order) do
    local e = entry[id]
    local b = bySrc[e.src]
    b[#b + 1] = id
end

local out = {}
local function w(s) out[#out + 1] = s end

local function lineFor(id)
    local e = entry[id]
    local bits = {}
    if e.mask > 0 then bits[#bits + 1] = maskNames(e.mask) end
    if e.faction ~= FACTION_NONE then bits[#bits + 1] = FACTION_NAME[e.faction] or ("faction " .. e.faction) end
    local tag = table.concat(bits, " / ")
    if e.note then tag = tag .. "  [" .. e.note .. "]" end
    return string.format("[%d]=%d,%s-- %s · %s", id, pack(e.mask, e.faction),
        string.rep(" ", math.max(1, 22 - #string.format("[%d]=%d,", id, pack(e.mask, e.faction)))),
        tag, tostring(e.name or "?"))
end

w([[--[==[
    Daseeki Armory — SHIPPED CLASS AND FACTION LOCKS.

    GENERATED FILE. Built by dev/gen-restrictions.lua; regenerate rather than
    hand-edit — except the unobtainable-by-history list at the bottom, which is a
    deliberate policy list a human is meant to be able to change in one line.

    WHY THIS FILE EXISTS. Class and faction locks are static facts of a frozen
    game. Reading them at runtime off an asynchronous tooltip — which may render
    without the item behind it, differently on every account and every session —
    is what produced four generations of retry queues, data gates, repair passes,
    capture stamps and session latches, and it still left every Tier-3 piece
    unlocked in the owner's cache. Facts that never change are shipped as data.

    THE CONTRACT the rest of the addon depends on:

      Addon.StaticRestrictions[itemID] = classMask + faction * 4096

        classMask   bitfield: WARRIOR 1, PALADIN 2, HUNTER 4, ROGUE 8, PRIEST 16,
                    SHAMAN 64, MAGE 128, WARLOCK 256, DRUID 1024. Zero means
                    "no class lock". A mask that names every class is NOT stored:
                    it cannot hide anything, and an absent id already means that.
        faction     0 none, 1 Alliance, 2 Horde.

      AN ABSENT ID IS UNRESTRICTED. That is the fail-open rule, unchanged — but it
      is now a DATA GAP, fixable by regenerating this file, and not a runtime state
      that can differ between two accounts on the same client.

      Addon.StaticUnobtainable[itemID] = true

        Items the client ships that no player can obtain on a live Era realm.
        Hidden exactly like Blizzard's internal placeholders: "Show unusable" does
        not reveal them, because there is no character anywhere that can get one.
]==]

local _, Addon = ...
]])
w("")

local function section(title, ids, blurb)
    w(("-- ═══════════════════════════════════════════════════════════════════════════"))
    w(("-- %s  (%d entries)"):format(title, #ids))
    if blurb then
        for chunk in tostring(blurb):gmatch("[^\n]+") do w("-- " .. chunk) end
    end
    w(("-- ═══════════════════════════════════════════════════════════════════════════"))
end

w("Addon.StaticRestrictions = {")
w("")
section("(a) EVIDENCE — locks a real client read off its own tooltips", bySrc.evidence,
    "Captured by the 1.3.0/1.3.1 in-game scan on the owner's account and frozen here.\n"
    .. "Highest confidence: the client rendered the line, we recorded what it said.")
for _, id in ipairs(bySrc.evidence) do w(lineFor(id)) end
w("")
section("(b) SEED — Addon.ItemClassMask from the bundled itemDB.lua", bySrc.seed,
    "AtlasLoot-derived, and it speaks only for ids the evidence never captured.\n"
    .. "This is where the whole Naxxramas Tier-3 band comes from: the owner's client\n"
    .. "never had those items loaded, so no tooltip of his ever named their class.")
for _, id in ipairs(bySrc.seed) do w(lineFor(id)) end
w("")
section("(c) STATIC — knowledge no local source can supply", bySrc.static,
    "See dev/gen-restrictions.lua for the reasoning behind each of these.\n"
    .. "The four Atiesh ids share one name, carry no mask in either other source,\n"
    .. "and are the same staff, so nothing local can tell them apart. What IS pinned\n"
    .. "by the harness is the part the owner's bug was about: no Atiesh is offered to\n"
    .. "a warrior, paladin, hunter, rogue or shaman, whichever caster holds which id.")
for _, id in ipairs(bySrc.static) do w(lineFor(id)) end
w("}")
w("")

w("-- ═══════════════════════════════════════════════════════════════════════════")
w(("-- UNOBTAINABLE BY HISTORY  (%d entries)"):format(#UNOBTAINABLE))
w("--")
w("-- Real records in the client for items no player can acquire on a live Era")
w("-- realm — never itemised into a loot table, or removed before the game froze.")
w("-- They are hidden like Blizzard's internal placeholders rather than like an")
w("-- unusable item: \"Show unusable\" is about gear a DIFFERENT character could")
w("-- wear, and there is no such character for these.")
w("--")
w("-- THIS IS A POLICY LIST, NOT A DERIVED FACT. Deleting a line puts the item")
w("-- straight back into the picker — no code change, no rescan, no migration.")
w("-- ═══════════════════════════════════════════════════════════════════════════")
w("Addon.StaticUnobtainable = {")
for _, row in ipairs(UNOBTAINABLE) do
    w(string.format("[%d]=true,%s-- %s", row[1],
        string.rep(" ", math.max(1, 22 - #string.format("[%d]=true,", row[1]))), row[2]))
end
w("}")
w("")
w(("-- Entry count at generation time: %d restrictions, %d unobtainable.")
  :format(#order, #UNOBTAINABLE))
w("")

local path = P("restrictions.lua")
local f, ferr = io.open(path, "w")
if not f then
    io.stderr:write("ABORT: cannot write " .. path .. " -> " .. tostring(ferr) .. "\n")
    os.exit(2)
end
f:write(table.concat(out, "\n"))
f:close()

say("WROTE %s", path)
say("FINAL: %d restriction entries (%d evidence, %d seed, %d static) + %d unobtainable.",
    #order, #bySrc.evidence, #bySrc.seed, #bySrc.static, #UNOBTAINABLE)
say("peak lua memory: %.1f MB", collectgarbage("count") / 1024)

-- Compile what we just wrote, so a generator bug cannot ship a file that will not
-- load at login.
do
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
    local n = 0
    each(A.StaticRestrictions, "verify", function() n = n + 1 end)
    if n ~= #order then
        io.stderr:write(("ABORT: wrote %d entries but the file loads %d\n"):format(#order, n))
        os.exit(2)
    end
    say("VERIFIED: the generated file compiles and loads %d entries.", n)
end
