--[[
    Daseeki Armory — the item database, the usability model, and the developer
    tool that captures the first of those two.

    WHY THIS FILE EXISTS, AND WHAT CHANGED UNDER IT (1.3.1)
    ------------------------------------------------------
    THE ITEM DATABASE IS SHIPPED. catalog.lua carries all 9 240 equippable items
    the Era client holds, by id, with the client's own name and quality, and the
    goal picker builds its index straight from it. A player who has never scanned
    anything — a brand-new account, five seconds after first login — opens a slot
    and sees the complete list. Scan.CatalogEach is the reader; see the section on
    it below.

    THAT REPLACED A SCAN, AND THE REASONING IS THE SAME ONE THAT REPLACED THE
    RUNTIME RESTRICTION CAPTURE ONE RELEASE EARLIER. Classic Era is a frozen
    client: the set of equippable items in it is a constant, identical on every
    account, every realm and every login. Until now each user measured that
    constant for themselves — a minute-long walk of 32 000 ids, announced in chat,
    armed by a first-login timer, repeatable through a "Rescan Items" button, and
    persisted to a per-account SavedVariable. The owner's objection was exactly
    right: "I thought we decided to move toward a static list." A constant does not
    need measuring by the person reading it. It needs shipping.

    So the user-facing scan is gone — no auto-run, no button, no progress text, no
    "unscanned" suffix on the picker's count, and nothing writes
    DaseekiArmoryScanDB on any path a player can reach.

    THE SCAN ITSELF SURVIVES AS A DEVELOPER TOOL, because it is how the shipped
    files get REGENERATED for a new client build: a developer arms a flag, runs it
    against a live client, logs out, and points dev/gen-catalog.lua and
    dev/gen-restrictions.lua at the resulting SavedVariables. It is gated behind an
    undocumented command and a global flag; see THE SCAN SURVIVES AS A DEVELOPER
    TOOL near the bottom of this file. Its two phases are unchanged:

        phase 1  "instant"  — walk the id space with GetItemInfoInstant and keep
                              the ids whose equip location is one Armory manages.
                              Free, offline, no throttle risk.
        phase 2  "resolve"  — for each survivor, load the item (C_Item.
                              RequestLoadItemDataByID / GetItemInfo) under a
                              credit-limited window and record name + quality.

    Only name / quality / the internal flag are persisted; everything else is
    re-derived instantly from GetItemInfoInstant, which keeps the capture small
    and immune to client data changes.

    THE SCAN NO LONGER READS RESTRICTIONS AT ALL  (1.3.1, and this is the whole
    point of the release). Class and faction locks are STATIC FACTS of a frozen
    game, but 1.3.0 derived them at runtime from a hidden tooltip — which is
    asynchronous, depends on whether the client happens to hold the item, and
    answers differently on every account and every session. Four generations of
    machinery grew out of trying to make that reliable: a tooltip scan, then retry
    queues, then a data gate, then repair passes with capture stamps, session
    latches and blocked-reason plumbing. They fought each other, and every Tier-3
    armour piece in the owner's cache was STILL unlocked, so rogue-only Bonescythe
    offered itself to a warrior.

    All of it is gone. The locks are computed once on a developer's machine by
    dev/gen-restrictions.lua and SHIPPED as restrictions.lua:

        Addon.StaticRestrictions[itemID] = classMask + faction * 4096

    The filter reads that table and nothing else. An id that is absent is
    unrestricted — the same fail-open rule as before, except that it is now a DATA
    GAP fixable by regenerating one file, not a runtime state that can differ
    between two accounts on one client. Nothing about a restriction is per-account,
    per-session, asynchronous, retried, repaired, stamped or latched any more.

    WHAT IS NOT IN THE TABLE, deliberately: weapon and armour PROFICIENCY. Librams,
    Idols and Totems are not class-locked, they are class-proficient (armour
    subclasses 7/8/9), and Scan.PROF below filters them numerically and locale-free.
    That mechanism stays exactly as it was.

    THE ID WALK SWEEPS UP BLIZZARD'S OWN SCAFFOLDING. The client's item space is not
    the game's item list: it also holds placeholders ("[PH] …"), creature-equipment
    art ("Monster - Sword, Katana"), designer test gear and retired duplicates.
    Roughly 12% of everything the walk finds is of that kind and none of it can be
    obtained by any player, so INTERNAL_PATTERNS below condemns it.

    THAT DENYLIST IS NOW APPLIED AT GENERATION TIME, NOT AT RUNTIME. dev/gen-
    catalog.lua loads this very file, asks this very function, and simply does not
    write the 1 264 condemned rows into catalog.lua. They are not facts a user
    needs, so they are not shipped, and no client re-decides every login that
    "Monster - Sword, Katana" is not a goal. The patterns stay here because they
    are the definition — and because the generator reads them from here, the
    shipped catalog and the shipped denylist cannot drift apart.

    The trade that comes with baking it in: a new pattern used to reach an existing
    cache on the next login (Normalize re-derived the flag on a stamp bump). It now
    reaches users on the next RELEASE, with the regenerated catalog. For a frozen
    client that is the right trade — the junk is not moving.

    Published surface:
        Addon.ItemScan            -- the PURE layer (no WoW API at load; harness-gated)
        Scan.CatalogEach(fn)      -- stream the shipped item catalog
        Scan.CatalogCount()       -- how many items this build ships
        Scan.StatusReport()       -- the /darmory data lines (shipped data only)
        Addon:ScanContext(showUnusable)  -- the viewing character's filter context

    …and the DEVELOPER surface, which no player path reaches:
        Addon:IsDevScanEnabled()  -- is the dev flag armed?
        Addon:StartDevScan()      -- the gated entry point (/darmory devscan)
        Addon:ItemScanCache()     -- the SavedVariables capture, normalised
        Addon:StartItemScan(opts) -- opts = { force=, onProgress=, onDone= }
        Addon:StopItemScan()
        Addon:IsScanning()
        Addon:ItemScanStatus()    -- progress record, or nil when idle

    SavedVariables: DaseekiArmoryScanDB is RETIRED (1.3.1). It is still declared in
    the TOC — a declaration is removed a couple of releases after its last writer,
    not in the same build, so a downgrade cannot meet an undeclared global — but
    nothing in normal play reads it, writes it or even creates it. Whatever an
    older build left on disk stays there, inert, until the declaration goes. The
    only writer left is the developer scan above. The per-character DaseekiArmoryDB
    is untouched.
--]]

local ADDON, Addon = ...

local Scan = {}
Addon.ItemScan = Scan

-- ═══════════════════════════════════════════════════════════════════════════
-- PURE LAYER — no WoW API is touched at load, which is the property the
-- headless harness depends on (same contract as borders.lua / trinkets.lua).
-- ═══════════════════════════════════════════════════════════════════════════

----------------------------------------------------------------------
-- Bit helpers. WoW ships `bit`, stock Lua 5.1 (the harness) does not, so the
-- masks are packed and tested with plain arithmetic and stay identical in both.
----------------------------------------------------------------------
local function hasBit(mask, b)
    mask, b = tonumber(mask) or 0, tonumber(b) or 0
    if b <= 0 or mask <= 0 then return false end
    return math.floor(mask / b) % 2 == 1
end
Scan.HasBit = hasBit

----------------------------------------------------------------------
-- Class model. CLASS_BIT matches Addon.ItemClassMask in dev/itemDB-seed.lua
-- verbatim — that AtlasLoot-derived table is a generator input for the same
-- field, and dev/gen-restrictions.lua keeps its own copy of this model in step.
----------------------------------------------------------------------
Scan.CLASS_BIT = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
    SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024,
}

Scan.FACTION_NONE     = 0
Scan.FACTION_ALLIANCE = 1
Scan.FACTION_HORDE    = 2

----------------------------------------------------------------------
-- THE SHIPPED RESTRICTION TABLE
--
-- restrictions.lua (generated by dev/gen-restrictions.lua, loaded BEFORE this
-- file) publishes:
--
--     Addon.StaticRestrictions[itemID]  = classMask + faction * STATIC_SHIFT
--     Addon.StaticUnobtainable[itemID]  = true
--
-- Both are plain data. Reading them is a table lookup with no state, no cache, no
-- session, no retry and no repair — which is the entire architectural point.
--
-- AN ABSENT ID IS UNRESTRICTED. Fail-open is unchanged from every earlier build:
-- showing an item the character cannot use is a nuisance, hiding one he can is a
-- defect. What HAS changed is what a gap means. It used to mean "this account's
-- scan never managed to read that tooltip", which was unfixable from outside the
-- game; it now means "the generator did not know about that id", which is one
-- regeneration away and identical for every player.
----------------------------------------------------------------------
Scan.STATIC_SHIFT = 4096            -- classMask occupies the low 12 bits

function Scan.PackStatic(classMask, faction)
    local m = math.floor(tonumber(classMask) or 0)
    local f = math.floor(tonumber(faction)   or 0)
    if m < 0 then m = 0 elseif m > Scan.STATIC_SHIFT - 1 then m = Scan.STATIC_SHIFT - 1 end
    if f < 0 then f = 0 elseif f > 3 then f = 3 end
    return m + f * Scan.STATIC_SHIFT
end

-- -> classMask, faction
function Scan.UnpackStatic(n)
    n = math.floor(tonumber(n) or 0)
    if n < 0 then n = 0 end
    return n % Scan.STATIC_SHIFT, math.floor(n / Scan.STATIC_SHIFT) % 4
end

-- The one and only lookup. -> classMask, faction (0, FACTION_NONE when absent).
function Scan.StaticFor(id)
    local t = Addon.StaticRestrictions
    local packed = t and t[tonumber(id) or -1]
    if not packed then return 0, Scan.FACTION_NONE end
    return Scan.UnpackStatic(packed)
end

function Scan.IsUnobtainable(id)
    local t = Addon.StaticUnobtainable
    return (t and t[tonumber(id) or -1]) and true or false
end

-- How many ids the shipped table speaks for (for /darmory scanstatus). Counted
-- once: the table is shipped data and cannot change while the client runs.
local staticCount
function Scan.StaticCount()
    if staticCount then return staticCount end
    local n = 0
    for _ in pairs(Addon.StaticRestrictions or {}) do n = n + 1 end
    staticCount = n
    return n
end

function Scan.UnobtainableCount()
    local n = 0
    for _ in pairs(Addon.StaticUnobtainable or {}) do n = n + 1 end
    return n
end

----------------------------------------------------------------------
-- THE SHIPPED ITEM CATALOG
--
-- catalog.lua (generated by dev/gen-catalog.lua, loaded BEFORE this file)
-- publishes:
--
--     Addon.StaticCatalogRaw    one long string, one line per item:
--                                   <itemID> <quality> <name>
--     Addon.StaticCatalogCount  the number of lines, as a literal
--
-- THIS IS THE ITEM DATABASE. Not a seed for one, not a fallback while something
-- else warms up — the whole thing, 9 240 equippable items, shipped. Nobody scans
-- anything to get it.
--
-- WHY IT IS A STRING. Both consumers (the picker's index build, the icon search
-- index) walk it once and never look again, so the only thing a hash table would
-- add is 1.1 MB of permanent residency in every client to serve two linear
-- passes. As a string it is 240 KB. The measurements behind that choice — five
-- formats, on this exact payload, under the vendored Lua 5.1 — are recorded in
-- dev/gen-catalog.lua.
--
-- THE PARSER LIVES HERE, not in the generated file, because generated files
-- should be data and nothing else. It is pure, so the harness drives it directly.
--
-- [^\r\n]+ IS NOT PARANOIA. catalog.lua is written into a CRLF working tree, so
-- the separator between two records on disk is "\r\n". A name captured with
-- [^\n]+ would arrive carrying a trailing carriage return, which would corrupt
-- every display name and every search key in the picker, subtly, on Windows only.
----------------------------------------------------------------------

-- A hard ceiling on the walk. The shipped payload is ~9 240 rows; 60 000 is far
-- past any plausible growth and still finite, so a corrupted string cannot spin
-- the login frame. (Headless discipline, same rule the generators run under.)
Scan.CATALOG_CEILING = 60000

-- fn(id, name, quality) for every catalog row, in the file's order (ids ascending).
-- `raw` overrides the shipped string, which is how the harness feeds fixtures.
-- -> the number of rows visited
function Scan.CatalogEach(fn, raw)
    local s = raw or Addon.StaticCatalogRaw
    if type(s) ~= "string" or s == "" or type(fn) ~= "function" then return 0 end
    local n = 0
    for sid, sq, name in s:gmatch("(%d+) (%d+) ([^\r\n]+)") do
        n = n + 1
        if n > Scan.CATALOG_CEILING then return n - 1 end
        fn(tonumber(sid), name, tonumber(sq))
    end
    return n
end

-- How many items the addon ships. Reads the LITERAL the generator wrote rather
-- than parsing 240 KB to count newlines — which is the whole reason that literal
-- is in the file. Zero means catalog.lua did not load, and that is the one item-
-- database fault that can still exist; /darmory data shows it at a glance.
function Scan.CatalogCount()
    return tonumber(Addon.StaticCatalogCount) or 0
end

-- Per-class weapon/armor proficiency by numeric subclass id (locale-safe).
-- classID 2 = Weapon, 4 = Armor. Weapon subclasses: 0 axe1h, 1 axe2h, 2 bow,
-- 3 gun, 4 mace1h, 5 mace2h, 6 polearm, 7 sword1h, 8 sword2h, 10 staff, 13 fist,
-- 15 dagger, 16 thrown, 18 crossbow, 19 wand. Armor subclasses: 0 misc (necks,
-- rings, trinkets, cloaks — every class), 1 cloth, 2 leather, 3 mail, 4 plate,
-- 6 shield, 7 libram, 8 idol, 9 totem.
-- (Moved here verbatim from goalPicker.lua so the predicate is harness-testable.)
local function S(...) local t = {}; for _, v in ipairs({...}) do t[v] = true end; return t end
Scan.PROF = {
    WARRIOR = { weapon = S(0,1,2,3,4,5,6,7,8,10,13,15,16,18), armor = S(0,1,2,3,4,6) },
    PALADIN = { weapon = S(0,1,4,5,6,7,8),                     armor = S(0,1,2,3,4,6,7) },
    HUNTER  = { weapon = S(0,1,2,3,6,7,8,10,13,15,18),         armor = S(0,1,2,3) },
    ROGUE   = { weapon = S(0,2,3,4,7,13,15,16,18),             armor = S(0,1,2) },
    PRIEST  = { weapon = S(4,10,15,19),                        armor = S(0,1) },
    SHAMAN  = { weapon = S(0,1,4,5,10,13,15),                  armor = S(0,1,2,3,6,9) },
    MAGE    = { weapon = S(7,10,15,19),                        armor = S(0,1) },
    WARLOCK = { weapon = S(7,10,15,19),                        armor = S(0,1) },
    DRUID   = { weapon = S(4,5,6,10,13,15),                    armor = S(0,1,2,8) },
}

Scan.ITEM_CLASS_WEAPON = 2
Scan.ITEM_CLASS_ARMOR  = 4

----------------------------------------------------------------------
-- THE FILTER PREDICATE — A RULE TABLE, IN PRECEDENCE ORDER
--
-- rec = { id=, classID=, subclassID=, internal= }   (a goal-picker entry)
-- ctx = { class="WARRIOR", classBit=1, faction=2, showUnusable=false }
--
-- ONE ordered list decides every row. It is written as a rule table rather than a
-- chain of ifs because the ORDER is the contract — notably that the two
-- "not a real item" rules sit ABOVE "Show unusable", and the three restriction
-- rules sit below it. Each rule has a name, RowVerdict returns the name of the
-- rule that decided, and the harness pins one case per rule.
--
--   1  no-row        the argument is not an entry at all              -> hidden
--   2  not-an-item   Blizzard's own scaffolding (INTERNAL_PATTERNS)   -> hidden
--                    "Show unusable" cannot reveal it: it is not unusable, it is
--                    not real, and no character anywhere can obtain one.
--   3  unobtainable  a real record no player can acquire on a live realm
--                    (StaticUnobtainable) — same reasoning, same answer  -> hidden
--   4  no-context    no viewing character supplied (a raw list)        -> shown
--   5  show-unusable the reader asked to see gear he cannot equip      -> shown
--   6  class         StaticRestrictions names classes, and his is not one -> hidden
--   7  faction       StaticRestrictions names a faction, and it is not his -> hidden
--   8  proficiency   his class cannot use that armour/weapon subclass  -> hidden
--   9  usable        nothing objected                                  -> shown
--
-- The class and faction locks come from the SHIPPED table via the row's ID, never
-- from a field on the row: an entry cannot carry a stale copy of a fact it does
-- not own, and there is exactly one place to look.
----------------------------------------------------------------------
Scan.RULES = { "no-row", "not-an-item", "unobtainable", "no-context",
               "show-unusable", "class", "faction", "proficiency", "usable" }

-- -> shown(boolean), rule(string)
function Scan.RowVerdict(rec, ctx)
    if type(rec) ~= "table" then return false, "no-row" end
    if rec.internal then return false, "not-an-item" end
    if Scan.IsUnobtainable(rec.id) then return false, "unobtainable" end
    if not ctx then return true, "no-context" end
    if ctx.showUnusable then return true, "show-unusable" end

    local mask, faction = Scan.StaticFor(rec.id)

    if mask > 0 and (ctx.classBit or 0) > 0 and not hasBit(mask, ctx.classBit) then
        return false, "class"
    end
    if faction ~= Scan.FACTION_NONE and (ctx.faction or 0) ~= Scan.FACTION_NONE
       and faction ~= ctx.faction then
        return false, "faction"
    end

    local prof = ctx.class and Scan.PROF[ctx.class]
    if prof and rec.classID then
        if rec.classID == Scan.ITEM_CLASS_WEAPON and not prof.weapon[rec.subclassID] then
            return false, "proficiency"
        end
        if rec.classID == Scan.ITEM_CLASS_ARMOR and not prof.armor[rec.subclassID] then
            return false, "proficiency"
        end
    end

    return true, "usable"
end

function Scan.Usable(rec, ctx)
    local shown = Scan.RowVerdict(rec, ctx)
    return shown
end

----------------------------------------------------------------------
-- String helper (the query normaliser is its only remaining caller — the
-- tooltip list splitter that used to live beside it went with the parser).
----------------------------------------------------------------------
local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end
Scan.Trim = trim

----------------------------------------------------------------------
-- INTERNAL / UNOBTAINABLE ITEM NAMES
--
-- The 1..32000 id walk is a walk of the CLIENT's item space, and the client
-- ships Blizzard's own working records alongside the live game's items:
-- placeholder art ("[PH] Brilliant Dawn Cap"), creature-equipment records
-- ("Monster - Sword, Katana"), designer test gear ("Test Glaive A", "90 Epic
-- Warrior Helm"), retired duplicates ("Deprecated Dented Skullcap") and a
-- handful of one-off dev scraps. None of them exists on a live realm; no
-- player can obtain any of them. They are not "unusable" — they are not real —
-- so "Show unusable" deliberately does NOT reveal them. That tick box is about
-- items a DIFFERENT character could equip; there is no character, anywhere,
-- that can equip these.
--
-- THE PATTERN LIST IS EVIDENCE-DERIVED, NOT GUESSED. It was built by sweeping a
-- real completed scan cache (10 504 equippable ids, Era build 68940) and reading
-- every match; each pattern below is followed by its hit count in that sweep.
-- 1 263 of the 10 504 (12.0%) are internal; the 9 241 survivors were checked for
-- collisions against genuine Era names and there are none. Conservatism rule:
-- letting one placeholder through is cheaper than hiding one real item, so every
-- pattern is anchored or word-bounded rather than a loose substring.
--
-- The near-misses that FORCED the anchoring (all real, all must survive):
--   "Testament of Hope"        vs  the word "test"      -> %f[%a]test%f[%A]
--   "Contest Winner's Tabard"  vs  the word "test"      -> ditto
--   "Old Blanchy's Blanket"    vs  the OLD prefix       -> ^old%a (glued, no space)
--   "Adept's Cloak"            vs  "dep"                -> ^deprecated / " dep$"
--   "10 Pound Mud Snapper"     vs  the level templates  -> ^%d+ <quality> %a
--   "Doomcaller's Footwraps"   vs  "foo"                -> %f[%a]foo%f[%A]
--
-- Matching is CASE-INSENSITIVE: every pattern is written lowercase and tested
-- against name:lower().
----------------------------------------------------------------------

-- Bump when the pattern list changes; Normalize re-derives every cached flag on
-- a mismatch, so a pattern fix reaches an existing cache WITHOUT a rescan.
Scan.INTERNAL_STAMP = 2

Scan.INTERNAL_PATTERNS = {
    "%[ph%]",              --  79  "[PH] Brilliant Dawn Cap" — Blizzard's placeholder tag
    "monster %- ",         -- 515  creature-equipment art records (incl. "OLDMonster - …")
    "%f[%a]test%f[%A]",    -- 248  the WORD test: "Test Glaive A", "JEFF TEST SWORD", "(Test)"
    "%f[%a]testing%f[%A]", --   4  "Ring of Critical Testing 2"
    "^testboots",          --   1  "TestBoots - Puffed Mail Green" (glued, so the word misses it)
    "qatest",              --   1  "QATest +1000 Spell Dmg Ring"
    "jefftest",            --   1  "Fishing Pole (JEFFTEST)"
    "%(delete me%)",       --   1  "Shane Test (DELETE ME)" (already caught; kept as intent)
    "^deprecated ",        -- 219  "Deprecated Dented Skullcap"
    " deprecated$",        --   7  "Thunderfury, Blessed Blade of the Windseeker DEPRECATED"
    " dep$",               --   2  "Lok'delar, Stave of the Ancient Keepers DEP"
    "^old%a",              --  27  "OLDThug Belt" — GLUED prefix; "Old Blunderbuss" is real
    "%(old%)",             --   4  "(OLD)Medium Throwing Knife"
    "%f[%a]unused%f[%A]",  --  20  "Unused Feathered Leggings", "…Staff UNUSED", "[UNUSED]"
    "%(dnd%)",             --   2  "Charm Pouch (DND)"
    "%f[%a]foo%f[%A]",     --   1  "Twain Random Sword FOO"
    "^pvp %a+ %a+ %a",     --  12  "PVP Plate Helm Alliance" — the internal set templates
    -- the "<level> <quality> <spec> <slot>" balance templates. Anchored on the
    -- QUALITY word, because "<number> <word> …" alone is also how vanilla names
    -- its fish ("103 Pound Mightfish").
    "^%d+ epic %a",        --  39  "90 Epic Warrior Helm"
    "^%d+ green %a",       --  78  "63 Green Rogue Cap"
    "^%d+ blue %a",        --   0  (not present in the sweep; the family's other colours)
    "^%d+ purple %a",      --   0
    "^%d+ white %a",       --   0
    "^%d+ grey %a",        --   0
    "^%d+ gray %a",        --   0
    -- art-variant tokens: a lone letter plus two digits ("Black Leather D02 Boots",
    -- "Unused Cloth Shoulder A01 Gray"). %f[%a] keeps it a whole token, so
    -- "TEST GUN Horde50" and "BKP 42 \"Ultra\"" are not what trips it.
    "%f[%a]%a%d%d ",       --  74  (10 of them caught by nothing else)
    "%f[%a]%a%d%d$",       --  16
    -- SPELL-EFFECT CARRIERS (added 1.3.1 from the owner's screenshot: the picker
    -- offered "Enchant Cloak - Resistance"). "Enchant <slot> - <effect>" is the
    -- name of the enchantment EFFECT, not of anything a player can wear; the
    -- bundled AtlasLoot seed carries 123 of them under ids that mean something
    -- else entirely on this client. Swept across the owner's cache survivors PLUS
    -- every seed row the cache does not cover (11 129 names): 90 hits, all of that
    -- family, zero collisions. The anchor is what keeps the REAL neighbours:
    --   "Formula: Enchant Cloak - Greater Resistance"  (34 recipes) — not at ^
    --   "Enchanted Thorium Helm" / "Enchanter's Cowl"  (24 real)    — no space after "enchant"
    "^enchant %w.* %- %a",  --  90  "Enchant Cloak - Resistance", "Enchant 2H Weapon - Agility"
    "%f[%a]nax ph%f[%A]",   --   1  "Nax PH Crit Plate Shoulders" — a bare-PH placeholder
                            --      that "%[ph%]" cannot see (no brackets)
}

-- -> the pattern that condemned this name, or nil when the name is a real item.
-- Returning the pattern (not just a boolean) is what lets the harness prove that
-- every pattern in the list is the one doing the work on its own fixture.
function Scan.InternalPattern(name)
    if type(name) ~= "string" or name == "" then return nil end
    local s = name:lower()
    for _, p in ipairs(Scan.INTERNAL_PATTERNS) do
        if s:find(p) then return p end
    end
    return nil
end

function Scan.IsInternalName(name)
    return Scan.InternalPattern(name) ~= nil
end

----------------------------------------------------------------------
-- THE PICKER ROW PREDICATE
--
-- Lifted out of goalPicker.lua's local `filtered` so the EMPTY-SEARCH state is
-- pinned by a test rather than by reading the source.
--
-- EMPTY-QUERY VERDICT (owner question, 1.3.1): an empty search box lists EVERY
-- item that fits the slot and that this character could equip. That is not a
-- bug and not a min-length gate that failed to fire — it is what the picker has
-- done since 1.0.0 (the pre-scan picker's own filter read
-- `query == "" or e.name:find(query)`, and ShowGoalPicker opened with
-- `filtered("", …)`). The box is a FILTER over a browsable list, not a
-- required search term, so it stays that way. What was actually wrong is that
-- the 1.3.0 client scan poured Blizzard's internal records into that browsable
-- list, so the first rows of it were placeholder junk — which is what the
-- denylist above removes. No row is ever the "current goal" echoed back; the
-- picker has never done that.
--
-- `query` must already be normalised (Scan.NormalizeQuery); the caller does it
-- once per keystroke instead of once per row.
----------------------------------------------------------------------
function Scan.NormalizeQuery(q)
    return trim(tostring(q or "")):lower()
end

function Scan.Matches(e, query, validLoc, ctx)
    if type(e) ~= "table" then return false end
    if not (validLoc and validLoc[e.equipLoc]) then return false end
    if query and query ~= "" and not tostring(e.name or ""):find(query, 1, true) then return false end
    return Scan.Usable(e, ctx) and true or false
end

----------------------------------------------------------------------
-- CACHE CODEC
--
-- Layout (SavedVariables):
--   { version, build, ranges, scannedAt, count, internalCount, internalStamp,
--     autoScanTried,
--     names = { [id] = "Corehound Belt" },
--     meta  = { [id] = packedNumber } }
--
-- meta packs quality (4 bits) + the internal/unobtainable flag into a single
-- integer well inside Lua's exact-double range. equipLoc / icon / classID /
-- subclassID are deliberately NOT stored: GetItemInfoInstant answers them offline
-- and instantly for any id, so persisting them would only let the cache go stale
-- against a client data change.
--
-- THE MIDDLE OF THE WORD IS DEAD SPACE, ON PURPOSE (1.3.1). Bits 5..18 used to
-- hold a per-item classMask and faction — the runtime restriction capture, now
-- deleted; the locks are shipped in restrictions.lua. Removing bits from a
-- persisted layout is a layout change, and the compatible way to make it is to
-- leave the hole where it is rather than to re-pack around it:
--
--   * an OLD cache reads back exactly as it always did. UnpackMeta still decodes
--     the quality and the internal flag from the same positions, so nothing on
--     disk needs migrating, no version bump is needed and nobody is asked to
--     rescan for a field that no longer means anything;
--   * the stale restriction bits are simply never read again. Normalize does NOT
--     strip them — that would be a full rewrite of every meta value on the next
--     login to erase data nothing consults. Inert is cheaper than clean here, and
--     the FIRST rescan clears them anyway, because Put now writes zero there.
--
-- The internal flag stays where it was (bit 19) precisely so that leaving the hole
-- costs nothing: a cache written by any 1.3.x build keeps its denylist verdict.
----------------------------------------------------------------------
Scan.CACHE_VERSION = 1

local Q_BITS, M_BITS = 16, 4096      -- quality < 16, the dead restriction field
local F_SHIFT = Q_BITS * M_BITS      -- 65536
local I_SHIFT = F_SHIFT * 4          -- 262144  (the internal flag)

function Scan.PackMeta(quality, internal)
    local q = math.floor(tonumber(quality) or 0)
    if q < 0 then q = 0 elseif q > Q_BITS - 1 then q = Q_BITS - 1 end
    return q + (internal and I_SHIFT or 0)
end

-- -> quality, internal(boolean).  Legacy words decode without complaint: the
-- restriction bits between them are skipped rather than reported.
function Scan.UnpackMeta(n)
    n = math.floor(tonumber(n) or 0)
    if n < 0 then n = 0 end
    return n % Q_BITS, math.floor(n / I_SHIFT) % 2 == 1
end

function Scan.NewCache()
    return { version = Scan.CACHE_VERSION, names = {}, meta = {}, count = 0,
             internalCount = 0, internalStamp = Scan.INTERNAL_STAMP }
end

-- Bind / repair a table that came back off disk. A version bump discards the old
-- payload rather than trying to migrate it — the cache is a derived artefact and
-- a rescan rebuilds it, so there is nothing of the user's to lose.
--
-- The internal flag is re-derived here whenever the cache's internalStamp does
-- not match the current pattern list. That is the whole reason the flag is a
-- cheap derived bit rather than a rescan trigger: a placeholder the denylist
-- learns about tomorrow is filtered on the NEXT LOGIN of an existing cache,
-- with no minute-long walk of the id space, and a rescan re-derives it anyway
-- (Scan.Put reads the name), so the two paths can never disagree.
--
-- WHAT NORMALIZE NO LONGER DOES. It used to re-flag every row "restrictions
-- unread" whenever a capture stamp moved, which is how one shipped build's
-- mistake was made to re-arm a repair pass on every cache in the field. There is
-- no capture, no stamp and no pass to re-arm; the locks are in the addon.
function Scan.Normalize(cache)
    if type(cache) ~= "table" or cache.version ~= Scan.CACHE_VERSION then
        return Scan.NewCache()
    end
    if type(cache.names) ~= "table" then cache.names = {} end
    if type(cache.meta)  ~= "table" then cache.meta  = {} end

    local restamp = cache.internalStamp ~= Scan.INTERNAL_STAMP
    local n, internal = 0, 0
    for id, nm in pairs(cache.names) do
        n = n + 1
        local q, flag = Scan.UnpackMeta(cache.meta[id])
        if restamp then
            flag = Scan.IsInternalName(nm)
            cache.meta[id] = Scan.PackMeta(q, flag)
        end
        if flag then internal = internal + 1 end
    end
    cache.count         = n
    cache.internalCount = internal
    cache.internalStamp = Scan.INTERNAL_STAMP

    -- Fields the restriction machinery kept here. They are meaningless now and
    -- they are the only things that would make a stale cache LOOK like it owed
    -- work, so they go on the next normalise rather than lingering in
    -- SavedVariables to confuse the next person who opens the file.
    cache.unreadCount, cache.restrictStamp        = nil, nil
    cache.restrictRepairedAt, cache.repairBlocked = nil, nil
    cache.restrictLocked, cache.restrictUnreadable = nil, nil
    return cache
end

-- Record one scanned item. Name and quality come from GetItemInfo, which has
-- already answered by the time this is called; the internal flag is DERIVED from
-- the name, never passed in, so the denylist is the only thing that can decide it
-- and a rescan cannot disagree with a normalise.
--
-- There is no precedence rule here any more. The old one existed to stop a failed
-- tooltip re-read from erasing a class lock an earlier pass had managed to read —
-- a whole ordering problem that only existed because restrictions were captured at
-- runtime. A name and a quality either arrived or the caller did not call.
function Scan.Put(cache, id, name, quality)
    if type(cache) ~= "table" then return false end
    id = tonumber(id)
    if not id or type(name) ~= "string" or name == "" then return false end
    cache.names = cache.names or {}
    cache.meta  = cache.meta  or {}
    if cache.names[id] == nil then cache.count = (cache.count or 0) + 1 end
    cache.names[id] = name
    cache.meta[id]  = Scan.PackMeta(quality, Scan.IsInternalName(name))
    return true
end

-- -> name, quality, internal   (nil when the id was never scanned)
function Scan.Get(cache, id)
    if type(cache) ~= "table" or type(cache.names) ~= "table" then return nil end
    id = tonumber(id)
    local nm = id and cache.names[id]
    if not nm then return nil end
    local q, i = Scan.UnpackMeta(cache.meta and cache.meta[id])
    return nm, q, i
end

-- True once a scan has run to completion at least once on this account.
function Scan.IsComplete(cache)
    return (type(cache) == "table" and cache.scannedAt and (cache.count or 0) > 0) and true or false
end

----------------------------------------------------------------------
-- THE QUERYABLE STATE  (/darmory data)
--
-- IT IS A REPORT ON SHIPPED DATA NOW, AND THAT IS THE WHOLE RELEASE (1.3.1).
--
-- Every previous version of this report answered questions about a PROCESS: is
-- the scan still running, how far has it got, when did it last finish, how many
-- rows are still unread, why did the last repair pass refuse, which capture stamp
-- is current. Those were real questions, because the item database was something
-- each user had to produce for themselves and the production could fail.
--
-- The database is shipped. So the questions are gone — all of them — and what is
-- left is a three-line inventory of what this build contains:
--
--     catalog:      9240 items
--     restrictions: 910 class/faction locks
--     hidden:       12 unobtainable-by-history
--
-- A zero on any line means that shipped file did not load, which is the only
-- item-database fault that can still exist in this design and is now visible at a
-- glance instead of being inferred from an empty picker.
--
-- PURE, and it no longer takes any arguments. There is no cache to walk and no
-- live status to interrogate; it reads the three shipped tables and returns text.
--   -> array of plain strings, one per line, no colour codes
----------------------------------------------------------------------
function Scan.StatusReport()
    local out = {}
    local function line(s) out[#out + 1] = s end

    local items  = Scan.CatalogCount()
    local locks  = Scan.StaticCount()
    local hidden = Scan.UnobtainableCount()

    line(("catalog:      %d items%s"):format(items,
        items == 0 and "   <- catalog.lua did not load" or ""))
    line(("restrictions: %d class/faction locks%s"):format(locks,
        locks == 0 and "   <- restrictions.lua did not load" or ""))
    line(("hidden:       %d unobtainable-by-history"):format(hidden))
    line("shipped with the addon — identical on every account. Nothing to scan.")
    return out
end

----------------------------------------------------------------------
-- SCAN RANGES + BATCH MATH
--
-- CEILING RATIONALE. Vanilla's highest live item id is a little over 24 000
-- (the Naxxramas / AQ tail). 32 000 gives comfortable headroom for anything
-- Blizzard has appended in the low id space on Era / Anniversary realms, and the
-- phase-1 walk is FREE (GetItemInfoInstant is a local lookup), so the headroom
-- costs about a second of wall clock and nothing on the server.
--
-- The high id blocks (the 180k Era additions and the 200k+ Season of Discovery
-- block) are deliberately NOT scanned by default: on an Era realm they are pure
-- noise in a goal picker, since none of it is obtainable there. EXTRA_RANGES is
-- the one-line extension point if that ever changes.
----------------------------------------------------------------------
Scan.RANGES       = { { 1, 32000 } }
Scan.EXTRA_RANGES = {}

function Scan.ActiveRanges()
    local out = {}
    for _, r in ipairs(Scan.RANGES) do out[#out + 1] = { r[1], r[2] } end
    for _, r in ipairs(Scan.EXTRA_RANGES) do out[#out + 1] = { r[1], r[2] } end
    return out
end

function Scan.RangesLabel(ranges)
    local parts = {}
    for _, r in ipairs(ranges or {}) do parts[#parts + 1] = tostring(r[1]) .. "-" .. tostring(r[2]) end
    return table.concat(parts, ",")
end

function Scan.RangeTotal(ranges)
    local n = 0
    for _, r in ipairs(ranges or {}) do
        local a, b = tonumber(r[1]), tonumber(r[2])
        if a and b and b >= a then n = n + (b - a + 1) end
    end
    return n
end

-- 1-based virtual index across the concatenated ranges -> item id (nil past the end).
function Scan.IdAt(ranges, index)
    index = tonumber(index)
    if not index or index < 1 then return nil end
    local i = math.floor(index)
    for _, r in ipairs(ranges or {}) do
        local a, b = tonumber(r[1]), tonumber(r[2])
        if a and b and b >= a then
            local n = b - a + 1
            if i <= n then return a + i - 1 end
            i = i - n
        end
    end
    return nil
end

-- WHICH SILENT REQUEST GETS THE RETRY, and which runs out of tries. (ARM-8,
-- SUITE_ASYNC_AUDIT.md §3, Class 8.)
--
-- The expiry sweep in ScanTick used to re-append straight out of its
-- `pairs(ST.inflight)` walk. pairs() order differs per table lifetime, and the
-- re-appended ids land in a queue drained under MAX_TRIES = 2, one request
-- credit per tick (REQUEST_PER_TICK) and a MAX_INFLIGHT ceiling — so the walk
-- order decides which id spends the last credit of a tick and, at the end of a
-- run, which ids end up in the failed set. Two runs of the same scan over the
-- same client answered with different failure lists.
--
-- The scan's overall correctness never depended on this (there are three
-- independent retirement paths), which is exactly why it could sit unnoticed:
-- the defect is not "wrong result", it is "a different result each time".
--
-- COLLECT, SORT, THEN RE-QUEUE. Same shape as Nexus friends.lua:423, which
-- sorts BEFORE its ceiling, and as goalPicker.lua's Rows.SortAndCap, which
-- sorts before the picker's row cap. Pure — no WoW API, no ST — so the harness
-- drives the real function.
--
-- `inflight` is the id -> deadline map; `now` is GetTime(). Returns the expired
-- ids in ascending order, never nil.
function Scan.ExpiredIds(inflight, now)
    local out = {}
    if type(inflight) ~= "table" then return out end
    now = tonumber(now)
    if not now then return out end
    for id, deadline in pairs(inflight) do
        if type(deadline) == "number" and now > deadline then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end

-- The batching contract: given how many virtual indices are already consumed,
-- yield the inclusive [from, to] slice for this tick and whether that finishes
-- the walk. Returns nil, nil, true when there is nothing left.
function Scan.BatchPlan(total, cursor, perBatch)
    total    = math.floor(tonumber(total)    or 0); if total    < 0 then total    = 0 end
    cursor   = math.floor(tonumber(cursor)   or 0); if cursor   < 0 then cursor   = 0 end
    perBatch = math.floor(tonumber(perBatch) or 1); if perBatch < 1 then perBatch = 1 end
    if cursor >= total then return nil, nil, true end
    local from = cursor + 1
    local to   = math.min(total, cursor + perBatch)
    return from, to, to >= total
end

function Scan.Percent(cursor, total)
    total = tonumber(total) or 0
    if total <= 0 then return 100 end
    local p = (tonumber(cursor) or 0) / total * 100
    if p < 0 then p = 0 elseif p > 100 then p = 100 end
    return math.floor(p + 0.5)
end

function Scan.EstimateSeconds(remaining, ratePerSec)
    remaining  = tonumber(remaining) or 0
    ratePerSec = tonumber(ratePerSec) or 0
    if remaining <= 0 then return 0 end
    if ratePerSec <= 0 then return nil end
    return remaining / ratePerSec
end

function Scan.FormatDuration(sec)
    sec = tonumber(sec)
    if not sec or sec < 0 then return nil end
    sec = math.floor(sec + 0.5)
    if sec < 60 then return sec .. "s" end
    return string.format("%dm %02ds", math.floor(sec / 60), sec % 60)
end

----------------------------------------------------------------------
-- THROTTLE
--
-- The server rate-limits item queries and has historically disconnected clients
-- that flood it, so the resolve phase is credit-limited two ways at once: a hard
-- per-tick dispatch count AND a ceiling on outstanding requests. The in-flight
-- window means the real throughput self-regulates DOWN to whatever the server is
-- actually delivering — the per-tick number is only ever the peak.
--
-- 15 dispatches / 0.05 s = 300 requests/second peak.
-- RECORD_BUDGET caps how many items are written down per tick, so a warm client
-- cache — where every item resolves locally and instantly — cannot drain
-- thousands of items in a single frame and hitch the client. (It was
-- TOOLTIP_BUDGET when a tooltip build was the expensive step in a record; there
-- are no tooltips left, and the budget is now simply a per-frame record ceiling.)
----------------------------------------------------------------------
Scan.TICK             = 0.05
Scan.INSTANT_PER_TICK = 1200   -- phase 1: local lookups only, no server traffic
Scan.REQUEST_PER_TICK = 15
Scan.MAX_INFLIGHT     = 200
Scan.RECORD_BUDGET    = 25
Scan.REQUEST_TIMEOUT  = 6      -- seconds before a silent request is retried
Scan.MAX_TRIES        = 2

function Scan.PeakRequestsPerSecond() return Scan.REQUEST_PER_TICK / Scan.TICK end
function Scan.PeakRecordsPerSecond()  return Scan.RECORD_BUDGET    / Scan.TICK end
function Scan.InstantIdsPerSecond()   return Scan.INSTANT_PER_TICK / Scan.TICK end

-- ═══════════════════════════════════════════════════════════════════════════
-- IN-GAME LAYER — everything below reaches for the WoW API, and so is only ever
-- reached through a function call, never at file scope.
-- ═══════════════════════════════════════════════════════════════════════════

----------------------------------------------------------------------
-- SavedVariables
----------------------------------------------------------------------
-- Normalize walks the whole name table to recount, so it runs ONCE per session
-- (this is called on every picker refresh) and the count is maintained
-- incrementally by Scan.Put thereafter.
local boundCache
function Addon:ItemScanCache()
    if boundCache and rawequal(boundCache, DaseekiArmoryScanDB) then return boundCache end
    DaseekiArmoryScanDB = Scan.Normalize(DaseekiArmoryScanDB)
    boundCache = DaseekiArmoryScanDB
    return boundCache
end

----------------------------------------------------------------------
-- The viewing character's filter context (§ owner directive: filter by the
-- character who OPENED the picker, resolved at open time).
----------------------------------------------------------------------
function Addon:ScanContext(showUnusable)
    local _, class = UnitClass("player")
    local tag = UnitFactionGroup("player")
    return {
        class    = class,
        classBit = Scan.CLASS_BIT[class or ""] or 0,
        faction  = (tag == "Alliance" and Scan.FACTION_ALLIANCE)
                or (tag == "Horde"    and Scan.FACTION_HORDE)
                or Scan.FACTION_NONE,
        showUnusable = showUnusable and true or false,
    }
end

----------------------------------------------------------------------
-- The scan runner
----------------------------------------------------------------------
local ST      -- active scan state; nil when idle
local runner

-- Every equip location Armory can actually place. Scanning wider would pull in
-- bags, quivers and ammo, which the goal picker can never offer.
local function slotUnion()
    local u = {}
    for _, t in pairs(Addon.SLOT_INVTYPES or {}) do
        for loc in pairs(t) do u[loc] = true end
    end
    return u
end

local function runnerFrame()
    if runner then return runner end
    runner = CreateFrame("Frame")
    runner:Hide()
    runner:SetScript("OnUpdate", function(_, elapsed) Addon:ScanTick(elapsed) end)
    runner:SetScript("OnEvent", function(_, _, itemID, success) Addon:ScanItemLoaded(itemID, success) end)
    Addon._scanRunner = runner
    return runner
end

function Addon:IsScanning() return ST ~= nil end

function Addon:ItemScanStatus()
    if not ST then return nil end
    if ST.phase == "instant" then
        return { phase = "instant", cursor = ST.cursor, total = ST.total,
                 percent = Scan.Percent(ST.cursor, ST.total),
                 found = ST.found, resolved = ST.resolved, failed = ST.failed, pending = 0 }
    end
    local total = ST.queueTotal or 0
    local done  = ST.resolved + ST.failed
    return { phase = "resolve", cursor = done, total = total,
             percent = Scan.Percent(done, total),
             found = ST.found, resolved = ST.resolved, failed = ST.failed,
             pending = math.max(0, total - done) }
end

local function report()
    if ST and ST.onProgress then ST.onProgress(Addon:ItemScanStatus()) end
end

-- opts.force   wipe the cache and re-walk the whole id space
--
-- THERE IS ONE MODE NOW. `opts.repair` — the pass that re-read restrictions for
-- the rows a tooltip had failed on — is gone with everything else that existed to
-- make a runtime capture reliable. A scan walks ids and records names; that is the
-- whole job, and the only reason to run it twice is a client data change.
-- -> started(boolean)
function Addon:StartItemScan(opts)
    if ST then return false, "a scan is already running" end
    opts = opts or {}
    local cache = Addon:ItemScanCache()
    if opts.force then cache.names, cache.meta, cache.count = {}, {}, 0 end

    local ranges = Scan.ActiveRanges()
    ST = {
        cache = cache, ranges = ranges, total = Scan.RangeTotal(ranges),
        cursor = 0, phase = "instant",
        queue = {}, qHead = 1, queueTotal = 0,
        ready = {}, rHead = 1,
        inflight = {}, nInflight = 0, tries = {},
        doneIds = {}, loadSent = 0,
        found = 0, resolved = 0, failed = 0,
        acc = 0, started = GetTime(),
        valid = slotUnion(),
        force = opts.force and true or false,
        onProgress = opts.onProgress, onDone = opts.onDone,
    }
    -- Both events carry (itemID, success) and the handler is idempotent, so watching
    -- both is belt and braces. RegisterEvent RAISES on an event a build does not know,
    -- and the TOC spans three interface versions, so each one is guarded.
    local rf = runnerFrame()
    pcall(rf.RegisterEvent, rf, "GET_ITEM_INFO_RECEIVED")
    pcall(rf.RegisterEvent, rf, "ITEM_DATA_LOAD_RESULT")
    rf:Show()
    report()
    return true
end

function Addon:StopItemScan()
    if not ST then return false end
    local st = ST
    ST = nil
    if runner then runner:Hide(); runner:UnregisterAllEvents() end
    if st.onDone then st.onDone(st.cache, st, true) end
    return true
end

-- The one and only place the scan asks the server for an item, so the ONE credit
-- is spent in one place too (see the THROTTLE note). -> true when the ask was
-- actually made, false when this tick's credit is already gone.
local function requestLoad(id)
    if not ST then return false end
    if (ST.loadSent or 0) >= Scan.REQUEST_PER_TICK then return false end
    ST.loadSent = (ST.loadSent or 0) + 1
    if _G.C_Item and _G.C_Item.RequestLoadItemDataByID then
        -- recordItem's own GetItemInfo(id) miss has ALREADY queued a server load
        -- for this id; the explicit request is the modern, documented form of the
        -- same ask (1.15 C_Item), so a build without it still resolves through the
        -- GetItemInfo path and fires the same event.
        pcall(_G.C_Item.RequestLoadItemDataByID, id)
    end
    return true
end

-- Try to read + record an item from what the client already holds. Returns true
-- when the item was recorded; false means "still needs loading".
--
-- THIS FUNCTION USED TO BE THE PROBLEM. It read a hidden tooltip, decided whether
-- to believe what it saw, kept two independent retry counters with two different
-- ceilings, re-queued to a later tick, and could still persist a row as "owed
-- another look" for a repair pass on a future session. All of that machinery
-- existed to derive one static fact. The fact is shipped now, so what is left is
-- the question GetItemInfo actually answers: does the client have this item's name
-- yet? Yes -> write it down. No -> ask, and come back when the event fires.
--
-- "WRITE IT DOWN" IS THE PART THAT WENT MISSING, and it is the whole function.
-- Tearing the restriction machinery out of here took the Scan.Put with it, along
-- with the done-marker and the resolved tally, because they sat in the middle of
-- the block that was deleted. What was left compiled, ran, reported progress and
-- announced a completed scan — while persisting nothing at all. A scan is not a
-- traversal, it is a WRITE, so the three lines below are the point of the file and
-- the harness now pins them by driving a whole forced rescan and demanding the
-- cache come out the far side with rows in it.
local function recordItem(id)
    if not ST then return false end
    local function clearInflight()
        if ST.inflight[id] then ST.inflight[id] = nil; ST.nInflight = ST.nInflight - 1 end
    end
    if ST.doneIds[id] then clearInflight(); return true end
    local name, _, quality = GetItemInfo(id)
    if not name then return false end
    -- A name came back, so the item is loaded and its quality came with it. The
    -- internal flag is NOT passed: Scan.Put derives it from the name, so a rescan
    -- and a normalise can never disagree about a row.
    Scan.Put(ST.cache, id, name, quality)
    ST.doneIds[id] = true
    ST.resolved    = ST.resolved + 1
    clearInflight()
    return true
end

function Addon:ScanItemLoaded(itemID, success)
    if not ST or not itemID then return end
    if not ST.inflight[itemID] then return end
    ST.inflight[itemID] = nil
    ST.nInflight = ST.nInflight - 1
    if success == false then
        ST.failed = ST.failed + 1
        return
    end
    -- Deferred to the tick so a burst of arrivals cannot spike a single frame
    -- with hundreds of record writes.
    ST.ready[#ST.ready + 1] = itemID
end

function Addon:ScanTick(elapsed)
    if not ST then return end
    ST.acc = ST.acc + (elapsed or 0)
    if ST.acc < Scan.TICK then return end
    ST.acc = 0

    -- ── phase 1: the free, local walk ────────────────────────────────────────
    if ST.phase == "instant" then
        local from, to, done = Scan.BatchPlan(ST.total, ST.cursor, Scan.INSTANT_PER_TICK)
        if from then
            for i = from, to do
                local id = Scan.IdAt(ST.ranges, i)
                if id then
                    local _, _, _, equipLoc, icon = GetItemInfoInstant(id)
                    if icon and equipLoc and ST.valid[equipLoc] then
                        ST.found = ST.found + 1
                        if ST.force or not ST.cache.names[id] then
                            ST.queue[#ST.queue + 1] = id
                        end
                    end
                end
            end
            ST.cursor = to
        end
        if done or not from then
            ST.phase = "resolve"
            ST.queueTotal = #ST.queue
            if ST.queueTotal == 0 then Addon:FinishItemScan(); return end
        end
        report()
        return
    end

    -- ── phase 2: resolve, under a credit window ──────────────────────────────
    local now = GetTime()

    -- ONE request credit per tick. The dispatch loop is now its only spender —
    -- the data gate's retry path, which used to share it, no longer exists.
    ST.loadSent = 0

    -- Expire silent requests, retrying once before writing them off. The ids are
    -- COLLECTED AND SORTED first (Scan.ExpiredIds) rather than re-queued straight
    -- out of a pairs() walk, so the retry order — and therefore which id spends
    -- the last request credit of a tick, and which ends the run in the failed set
    -- — is the same on every run over the same deadlines. ARM-8 / Class 8.
    local expired = Scan.ExpiredIds(ST.inflight, now)
    for i = 1, #expired do
        local id = expired[i]
        ST.inflight[id] = nil
        ST.nInflight = ST.nInflight - 1
        local t = ST.tries[id] or 1
        if t < Scan.MAX_TRIES then
            ST.tries[id] = t + 1
            ST.queue[#ST.queue + 1] = id
        else
            ST.failed = ST.failed + 1
        end
    end

    local budget = Scan.RECORD_BUDGET

    -- items whose data arrived since the last tick
    while budget > 0 and ST.rHead <= #ST.ready do
        local id = ST.ready[ST.rHead]; ST.rHead = ST.rHead + 1
        if not recordItem(id) then ST.failed = ST.failed + 1 end
        budget = budget - 1
    end

    -- dispatch new work
    while budget > 0 and ST.loadSent < Scan.REQUEST_PER_TICK
          and ST.nInflight < Scan.MAX_INFLIGHT and ST.qHead <= #ST.queue do
        local id = ST.queue[ST.qHead]; ST.qHead = ST.qHead + 1
        if not ST.inflight[id] and not ST.doneIds[id] then
            if recordItem(id) then
                budget = budget - 1
            else
                ST.inflight[id] = now + Scan.REQUEST_TIMEOUT
                ST.nInflight = ST.nInflight + 1
                ST.tries[id] = ST.tries[id] or 1
                requestLoad(id)
            end
        end
    end

    report()

    -- The queue is drained, nothing is waiting to be written down and nothing is
    -- still in flight: that is the whole finish test. (It used to have a fourth
    -- clause for the tooltip retry queue, which no longer exists.)
    if ST.qHead > #ST.queue and ST.rHead > #ST.ready and ST.nInflight <= 0 then
        Addon:FinishItemScan()
    end
end

function Addon:FinishItemScan()
    if not ST then return end
    local st = ST
    ST = nil
    if runner then runner:Hide(); runner:UnregisterAllEvents() end

    local cache = st.cache
    cache.version   = Scan.CACHE_VERSION
    cache.scannedAt = (type(time) == "function" and time()) or 0
    cache.ranges    = Scan.RangesLabel(st.ranges)
    cache.build     = select(2, GetBuildInfo())
    -- The auto-scan one-shot marker was CLEARED here, so that wiping the cache
    -- would re-arm the login scan. There is no auto path left to re-arm, and a
    -- stale marker left on disk by an older build is simply never read again.

    local n, internal = 0, 0
    for id in pairs(cache.names) do
        n = n + 1
        local _, i = Scan.UnpackMeta(cache.meta[id])
        if i then internal = internal + 1 end
    end
    cache.count         = n
    cache.internalCount = internal
    cache.internalStamp = Scan.INTERNAL_STAMP

    -- THE PICKER IS NOT TOLD, because it is not listening. Its index is built from
    -- catalog.lua and owes nothing to this cache, so a finished scan changes
    -- nothing a player can see — which is exactly right: this scan ran to produce
    -- a file for a DEVELOPER to feed to dev/gen-catalog.lua, and its output reaches
    -- users in the next release, not in the next frame. (This is where the old
    -- build invalidated Addon.GoalItemDB and pushed a refresh into an open picker.)

    local secs = Scan.FormatDuration(GetTime() - st.started) or "?"
    print(string.format("%s DEV scan complete — %d equippable items cached "
        .. "(%d internal/unobtainable) in %s.%s",
        Addon:Tag(), n - internal, internal, secs,
        st.failed > 0 and (" " .. st.failed .. " could not be loaded.") or ""))
    print(Addon:Wrap("muted", "  Log out to flush SavedVariables, then run "
        .. "dev/gen-catalog.lua and dev/gen-restrictions.lua against it."))

    if st.onDone then st.onDone(cache, st, false) end
end

----------------------------------------------------------------------
-- THERE IS NO LOGIN HOOK ANY MORE, AND THAT IS THE POINT OF THE RELEASE.
--
-- What used to be here: Addon:InitItemScan(), called from core.lua's login path.
-- It bound the SavedVariables cache, checked whether this account had ever
-- completed a scan, and if not armed a 15-second timer that announced "building
-- the item database for the first time — this runs once per account and takes
-- about a minute" and then walked 32 000 item ids. It carried a one-shot latch
-- (autoScanTried) whose placement had already been a release-verification defect
-- once, because a logout inside the 15-second window disarmed the auto path for
-- that account permanently and silently.
--
-- ALL OF IT IS GONE, because the thing it was building is now shipped in
-- catalog.lua. A frozen client's item list is a constant; asking every user to
-- measure it, once per account, behind a timer, with a latch to stop the measuring
-- from nagging them, was the old architecture leaking through. Nothing on the
-- login path touches the scan, nothing touches DaseekiArmoryScanDB, and a fresh
-- account gets a complete picker with no wait and no announcement.
--
-- WHAT THIS DELETES BESIDES THE TIMER: AUTO_SCAN_DELAY, the autoScanTried latch
-- and every question about its placement, the first-login chat line, and the
-- reason Addon:ItemScanCache() was ever called during normal play. The cache is
-- not created, not normalised and not written on any path a player can reach.
--
-- ═══════════════════════════════════════════════════════════════════════════
-- THE SCAN SURVIVES AS A DEVELOPER TOOL, and only as one.
--
-- The runner above is not dead code and must not be deleted: it is how catalog.lua
-- and restrictions.lua get REGENERATED. A developer runs it against a live client,
-- the result lands in their own SavedVariables, and dev/gen-catalog.lua and
-- dev/gen-restrictions.lua read that file to build the shipped tables. Deleting
-- the scan would mean the next client build could never be captured — the data
-- would be frozen at whatever the last release happened to know.
--
-- SO IT IS GATED, TWICE OVER, and neither gate can be tripped by accident:
--
--   1. the command that starts it (/darmory devscan) is undocumented — it is not
--      in the slash help, not in the options UI, and not in any tooltip;
--   2. it refuses to run unless the global named below is truthy, which a player
--      has no reason to set and no path to set by accident.
--
--      /run DASEEKI_ARMORY_DEV = true
--      /darmory devscan
--
-- A GLOBAL RATHER THAN A SAVED SETTING, deliberately: it evaporates on /reload, so
-- a developer cannot leave a machine armed, and it can never be persisted into a
-- user's SavedVariables by a stray click.
----------------------------------------------------------------------
Addon.DEV_SCAN_FLAG = "DASEEKI_ARMORY_DEV"

function Addon:IsDevScanEnabled()
    return _G[Addon.DEV_SCAN_FLAG] and true or false
end

-- -> started(boolean), reason(string|nil)
function Addon:StartDevScan()
    if not Addon:IsDevScanEnabled() then
        return false, "the item scan is a developer tool in this build. "
            .. "It is how catalog.lua gets regenerated for a new client, not "
            .. "something the picker needs — the item database is shipped."
    end
    if Addon:IsScanning() then return false, "a scan is already running." end
    return Addon:StartItemScan({ force = true })
end
