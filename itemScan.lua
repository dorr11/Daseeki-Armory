--[[
    Daseeki Armory — item-database scan + usability model.

    WHY THIS FILE EXISTS
    --------------------
    The goal picker used to search one bundled, AtlasLoot-derived name table
    (itemDB.lua, Addon.ItemNameDB). That table is a snapshot: it misses items
    outright and its names can be stale. The consequence the owner reported was
    items simply absent from the picker.

    The fix is an in-game SCAN of the client's own item space, cached to
    SavedVariables. The client ships the item *record* locally, so
    GetItemInfoInstant(id) answers equip location / icon / class / subclass for
    ANY id with no server round-trip; only the NAME and the QUALITY need the item
    loaded from the server. So the scan is two phases:

        phase 1  "instant"  — walk the id space with GetItemInfoInstant and keep
                              the ids whose equip location is one Armory manages.
                              Free, offline, no throttle risk.
        phase 2  "resolve"  — for each survivor, load the item (C_Item.
                              RequestLoadItemDataByID / GetItemInfo) under a
                              credit-limited window and record name + quality.

    Only name / quality / the internal flag are persisted; everything else is
    re-derived instantly from GetItemInfoInstant at load, which keeps the cache
    small and immune to client data changes.

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
    obtained by any player, so each record carries an `internal` flag
    (INTERNAL_PATTERNS, derived from a real 10 504-item cache) and the goal picker's
    index drops those rows outright. They stay IN the cache so a rescan does not
    have to re-fight them, and "Show unusable" does not reveal them — see the
    INTERNAL / UNOBTAINABLE section below.

    Published surface:
        Addon.ItemScan            -- the PURE layer (no WoW API at load; harness-gated)
        Addon:ItemScanCache()     -- the SavedVariables cache, normalised
        Addon:StartItemScan(opts) -- opts = { force=, onProgress=, onDone= }
        Addon:StopItemScan()
        Addon:IsScanning()
        Addon:ItemScanStatus()    -- progress record, or nil when idle
        Addon:ScanContext(showUnusable)  -- the viewing character's filter context
        Addon:InitItemScan()      -- login hook (binds the SV, auto-runs once)

    SavedVariables: DaseekiArmoryScanDB (## SavedVariables — ACCOUNT-wide, not
    per-character). The scan result is a property of the CLIENT, not of a
    character, so scanning once per account rather than once per alt is the
    correct scope. This is a NEW global; the per-character DaseekiArmoryDB is
    untouched (additive only).
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
-- Class model. CLASS_BIT matches Addon.ItemClassMask in itemDB.lua verbatim
-- (that bundled table is a valid seed source for the same field).
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
-- THE QUERYABLE STATE  (/darmory scanstatus)
--
-- The scan announces itself in chat once and then scrolls away, which is no use
-- to anyone trying to answer "is it still running?" three minutes later.
-- StatusReport turns the cache (plus the live scan status, when there is one)
-- into the lines the slash command prints.
--
-- IT GOT SHORTER, and that is the report (1.3.1). It used to carry a line for
-- rows still unread, a line for the last repair pass, a line for why a repair had
-- been refused, and a capture stamp — four surfaces that existed only to explain
-- a restriction capture that could fail. The capture is gone, so the questions are
-- gone; what replaces all of it is one line saying how many locks the addon ships.
-- If that number is 0 the shipped table did not load, which is the only
-- restriction fault that can still exist and is now visible at a glance.
--
-- PURE. It walks the cache it is handed and touches no WoW API, so the harness
-- pins the shape of the report rather than the fact that a print happened.
--
--   cache : the SavedVariables scan cache (Addon:ItemScanCache())
--   live  : Addon:ItemScanStatus() when a scan is running, else nil
--   -> array of plain strings, one per line, no colour codes
----------------------------------------------------------------------
local function stampText(t)
    t = tonumber(t)
    if not t or t <= 0 then return "never" end
    if type(date) == "function" then
        local ok, s = pcall(date, "%Y-%m-%d %H:%M", t)
        if ok and s then return s end
    end
    return tostring(t)
end

function Scan.StatusReport(cache, live)
    local out = {}
    local function line(s) out[#out + 1] = s end

    local locks = Scan.StaticCount()
    local hidden = Scan.UnobtainableCount()

    if type(cache) ~= "table" or type(cache.names) ~= "table" then
        line("no item cache yet — the scan has never run.")
        line(("restrictions: static table, %d entries (%d unobtainable-by-history)")
             :format(locks, hidden))
        return out
    end

    -- one walk answers every count, so the report can never disagree with itself
    local total, internal = 0, 0
    for id in pairs(cache.names) do
        total = total + 1
        local _, isInternal = Scan.UnpackMeta(cache.meta and cache.meta[id])
        if isInternal then internal = internal + 1 end
    end

    line(("cache: %d ids — %d offerable, %d internal/unobtainable hidden")
         :format(total, total - internal, internal))
    line(("restrictions: static table, %d entries (%d unobtainable-by-history)")
         :format(locks, hidden))

    if live then
        if live.phase == "instant" then
            line(("scan: RUNNING — walking item ids %d / %d (%d%%), %d equippable found")
                 :format(live.cursor or 0, live.total or 0, live.percent or 0, live.found or 0))
        else
            line(("scan: RUNNING — loading items %d / %d (%d%%)")
                 :format(live.cursor or 0, live.total or 0, live.percent or 0))
        end
    else
        line("scan: idle")
    end

    line(("last full scan: %s%s"):format(stampText(cache.scannedAt),
         cache.build and (" (build " .. tostring(cache.build)
                          .. ", ids " .. tostring(cache.ranges or "?") .. ")") or ""))
    line(("stamps: cache v%s, denylist %s")
         :format(tostring(cache.version), tostring(cache.internalStamp)))
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
local function recordItem(id)
    if not ST then return false end
    local function clearInflight()
        if ST.inflight[id] then ST.inflight[id] = nil; ST.nInflight = ST.nInflight - 1 end
    end
    if ST.doneIds[id] then clearInflight(); return true end
    local name, _, quality = GetItemInfo(id)
    if not name then return false end
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

    -- expire silent requests, retrying once before writing them off
    for id, deadline in pairs(ST.inflight) do
        if now > deadline then
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
    cache.autoScanTried = nil    -- a completed scan re-arms the auto path for a future reset

    local n, internal = 0, 0
    for id in pairs(cache.names) do
        n = n + 1
        local _, i = Scan.UnpackMeta(cache.meta[id])
        if i then internal = internal + 1 end
    end
    cache.count         = n
    cache.internalCount = internal
    cache.internalStamp = Scan.INTERNAL_STAMP

    -- the picker's index is derived from the cache; force a rebuild
    Addon.GoalItemDB, Addon._goalDBStamp = nil, nil
    -- …and PUSH that rebuild into an open picker rather than waiting for its own
    -- poll to notice, so a scan that finishes while the picker is open fills the
    -- list the owner is looking at instead of the next one he opens.
    if Addon.RefreshGoalPicker then pcall(Addon.RefreshGoalPicker, Addon, true) end

    local secs = Scan.FormatDuration(GetTime() - st.started) or "?"
    -- The internal count is reported, not hidden: the owner should be able to see
    -- that ~12% of what the client holds is Blizzard's own scaffolding, and that
    -- Armory kept it out of the picker on purpose. There is no "restricted" tally
    -- any more — the locks are shipped data, the same on every account, and
    -- /darmory scanstatus reports how many of them there are.
    print(string.format("%s item scan complete — %d equippable items cached "
        .. "(%d internal/unobtainable hidden) in %s.%s",
        Addon:Tag(), n - internal, internal, secs,
        st.failed > 0 and (" " .. st.failed .. " could not be loaded.") or ""))

    if st.onDone then st.onDone(cache, st, false) end
end

----------------------------------------------------------------------
-- Login hook. Auto-runs ONCE on an empty cache (the owner directive's "auto-run
-- if the cache is empty" marker), delayed so it never competes with the login
-- burst.
--
-- WHERE THE MARKER IS SET IS THE WHOLE POINT (release verification N5).
-- It used to be stamped HERE, at login, before the 15s timer was even armed.
-- cache is DaseekiArmoryScanDB — SavedVariables — so any logout, /reload or
-- disconnect inside that 15s window wrote autoScanTried = true to disk for a scan
-- that never ran. The auto path was then permanently disarmed on that account:
-- IsComplete() is false (no scan ever finished) and the marker is true, so this
-- function returns early on every login for ever after, in silence. The owner's
-- only way out was to find "Rescan Items" in the goal picker by themselves.
--
-- The marker is therefore set inside the callback, immediately before the scan
-- actually starts, and AFTER the callback's own guards — so a 15s window that is
-- cut short by a logout costs nothing, and a timer that fires into an already
-- running scan does not burn the one-shot either.
--
-- FINAL SEMANTICS (autoScanTried is a latch on the AUTO path only):
--   armed        cache not complete and no marker -> one attempt per login
--   latched      set only when this callback reaches StartItemScan
--   interrupted  a scan that STARTED but never finished keeps the marker: the
--                auto path does not retry it (that is the "does not nag forever"
--                property — a scan that hangs the client must not restart itself
--                every login), and Rescan Items is the manual door
--   terminal     completion is the real terminal state: FinishItemScan sets
--                scannedAt/count, so IsComplete() gates every future login, and
--                clears the marker so a later cache wipe re-arms the auto path
----------------------------------------------------------------------
Addon.AUTO_SCAN_DELAY = 15

function Addon:InitItemScan()
    local cache = Addon:ItemScanCache()
    if Scan.IsComplete(cache) or cache.autoScanTried then return end
    C_Timer.After(Addon.AUTO_SCAN_DELAY, function()
        if Addon:IsScanning() then return end
        local c = Addon:ItemScanCache()
        if Scan.IsComplete(c) then return end
        print(Addon:Tag() .. " building the item database for the first time — "
              .. "this runs once per account and takes about a minute. "
              .. Addon:Wrap("muted", "(Goal picker -> Rescan Items to redo it.)"))
        -- N5: the latch closes HERE, on a scan that is actually starting — never at
        -- login, where an early logout would disarm the auto path for good.
        c.autoScanTried = true
        Addon:StartItemScan()
    end)
end
