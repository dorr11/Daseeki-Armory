--[[
    Daseeki Armory — item-database scan + usability model.

    WHY THIS FILE EXISTS
    --------------------
    The goal picker used to search one bundled, AtlasLoot-derived name table
    (itemDB.lua, Addon.ItemNameDB). That table is a snapshot: it misses items
    outright, its names can be stale, and it carries no quality and almost no
    class/faction restriction data. The consequences the owner reported were
    (a) items simply absent from the picker and (b) items shown that the viewing
    character can never equip (Atiesh on a warrior; Alliance PvP rank pieces on a
    Horde character).

    The fix is an in-game SCAN of the client's own item space, cached to
    SavedVariables. The client ships the item *record* locally, so
    GetItemInfoInstant(id) answers equip location / icon / class / subclass for
    ANY id with no server round-trip; only the NAME, the QUALITY and the tooltip
    (which is where class + faction locks live on Era) need the item to be loaded
    from the server. So the scan is two phases:

        phase 1  "instant"  — walk the id space with GetItemInfoInstant and keep
                              the ids whose equip location is one Armory manages.
                              Free, offline, no throttle risk.
        phase 2  "resolve"  — for each survivor, load the item (C_Item.
                              RequestLoadItemDataByID / GetItemInfo) under a
                              credit-limited window, then read name + quality and
                              scan a hidden tooltip once for the restriction lines.

    Only name / quality / classMask / faction / the internal flag are persisted;
    everything else is re-derived instantly from GetItemInfoInstant at load,
    which keeps the cache small and immune to client data changes.

    THE ID WALK SWEEPS UP BLIZZARD'S OWN SCAFFOLDING (1.3.1). The client's item
    space is not the game's item list: it also holds placeholders ("[PH] …"),
    creature-equipment art ("Monster - Sword, Katana"), designer test gear and
    retired duplicates. Roughly 12% of everything the walk finds is of that kind
    and none of it can be obtained by any player, so each record carries an
    `internal` flag (INTERNAL_PATTERNS, derived from a real 10 504-item cache)
    and the goal picker's index drops those rows outright. They stay IN the
    cache so a rescan does not have to re-fight them, and "Show unusable" does
    not reveal them — see the INTERNAL / UNOBTAINABLE section below.

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

-- Set when a "Classes:" line was present but at least one entry on it could not
-- be resolved to a class token (an unexpected locale string, a class the client
-- names differently). The predicate FAILS OPEN on this bit: showing an item the
-- character cannot use is a nuisance, hiding one he can is a defect.
Scan.CLASS_UNKNOWN = 2048

Scan.FACTION_NONE     = 0
Scan.FACTION_ALLIANCE = 1
Scan.FACTION_HORDE    = 2

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
-- THE FILTER PREDICATE
--
-- rec = { classID=, subclassID=, classMask=, faction= }  (a goal-picker entry)
-- ctx = { class="WARRIOR", classBit=1, faction=2, showUnusable=false }
--
-- Three independent axes, in cost order:
--   1. explicit class lock   (tooltip "Classes: …", or the bundled ItemClassMask)
--   2. faction lock          (tooltip "Alliance"/"Horde", or a single-faction "Races:")
--   3. armor/weapon proficiency for the class (numeric, locale-free)
----------------------------------------------------------------------
function Scan.Usable(rec, ctx)
    if not rec then return false end
    if not ctx then return true end
    if ctx.showUnusable then return true end

    -- 1 — explicit class restriction
    local cm = tonumber(rec.classMask) or 0
    if cm > 0 then
        local unknown = hasBit(cm, Scan.CLASS_UNKNOWN)
        local known   = cm % Scan.CLASS_UNKNOWN
        if not unknown and known > 0 and (ctx.classBit or 0) > 0
           and not hasBit(known, ctx.classBit) then
            return false
        end
    end

    -- 2 — faction restriction
    local fa = tonumber(rec.faction) or Scan.FACTION_NONE
    if fa ~= Scan.FACTION_NONE and (ctx.faction or 0) ~= 0 and fa ~= ctx.faction then
        return false
    end

    -- 3 — proficiency
    local prof = ctx.class and Scan.PROF[ctx.class]
    if prof and rec.classID then
        if rec.classID == Scan.ITEM_CLASS_WEAPON and not prof.weapon[rec.subclassID] then return false end
        if rec.classID == Scan.ITEM_CLASS_ARMOR  and not prof.armor[rec.subclassID]  then return false end
    end

    return true
end

-- True when the record carries ANY restriction (used for the completion tally).
function Scan.IsRestricted(rec)
    if not rec then return false end
    return (tonumber(rec.classMask) or 0) > 0 or (tonumber(rec.faction) or 0) ~= 0
end

----------------------------------------------------------------------
-- TOOLTIP RESTRICTION PARSER
--
-- Era does NOT return class or faction locks from GetItemInfo, so they are read
-- once per item off a hidden scanning tooltip and cached. This function is the
-- pure half: it takes the already-extracted left-text lines plus a locale
-- context and yields (classMask, faction).
--
-- loc = {
--   classPrefix   = "Classes: ",          -- ITEM_CLASSES_ALLOWED with the %s cut
--   racesPrefix   = "Races: ",            -- ITEM_RACES_ALLOWED   with the %s cut
--   classByName   = { ["Mage"] = "MAGE", … },
--   raceFaction   = { ["Orc"] = 2, ["Human"] = 1, … },
--   allianceLines = { ["Alliance"] = true, … },   -- whole-line matches
--   hordeLines    = { ["Horde"] = true, … },
-- }
--
-- COVERAGE LIMIT (documented, deliberate): only class locks and faction locks
-- are parsed. Reputation, profession, quest and level requirements are NOT
-- filtered — those are things a character can still go and earn, which is
-- exactly what a GOAL item is.
----------------------------------------------------------------------
local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end
Scan.Trim = trim

local function splitList(body)
    local out = {}
    for piece in tostring(body or ""):gmatch("[^,]+") do
        local t = trim(piece)
        if t ~= "" then out[#out + 1] = t end
    end
    return out
end
Scan.SplitList = splitList

function Scan.ParseRestrictions(lines, loc)
    local classMask, faction = 0, Scan.FACTION_NONE
    if type(lines) ~= "table" or type(loc) ~= "table" then return classMask, faction end

    local cp = loc.classPrefix
    local rp = loc.racesPrefix
    local seen = {}

    for _, raw in ipairs(lines) do
        local line = trim(raw)
        if line ~= "" then
            if loc.allianceLines and loc.allianceLines[line] then
                if faction == Scan.FACTION_NONE then faction = Scan.FACTION_ALLIANCE end
            elseif loc.hordeLines and loc.hordeLines[line] then
                if faction == Scan.FACTION_NONE then faction = Scan.FACTION_HORDE end
            elseif cp and cp ~= "" and line:sub(1, #cp) == cp then
                for _, nm in ipairs(splitList(line:sub(#cp + 1))) do
                    local tok = loc.classByName and loc.classByName[nm]
                    local b   = tok and Scan.CLASS_BIT[tok]
                    if b then
                        if not seen[b] then seen[b] = true; classMask = classMask + b end
                    elseif not seen[Scan.CLASS_UNKNOWN] then
                        seen[Scan.CLASS_UNKNOWN] = true
                        classMask = classMask + Scan.CLASS_UNKNOWN
                    end
                end
            elseif rp and rp ~= "" and line:sub(1, #rp) == rp then
                -- A full-faction race mask is how vanilla expresses "Horde only" on
                -- most gear. Only collapse it to a faction when EVERY listed race is
                -- on one side; a mixed or unrecognised list stays unrestricted.
                local f, ok = nil, true
                local names = splitList(line:sub(#rp + 1))
                if #names == 0 then ok = false end
                for _, nm in ipairs(names) do
                    local rf = loc.raceFaction and loc.raceFaction[nm]
                    if not rf or rf == Scan.FACTION_NONE then ok = false; break end
                    if f == nil then f = rf elseif f ~= rf then ok = false; break end
                end
                if ok and f and faction == Scan.FACTION_NONE then faction = f end
            end
        end
    end

    return classMask, faction
end

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
Scan.INTERNAL_STAMP = 1

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
-- meta packs quality (4 bits) + classMask (12 bits) + faction (2 bits) + the
-- internal/unobtainable flag (1 bit) into a single integer well inside Lua's
-- exact-double range. equipLoc / icon / classID / subclassID are deliberately
-- NOT stored: GetItemInfoInstant answers them offline and instantly for any id,
-- so persisting them would only let the cache go stale against a client data
-- change.
--
-- The internal bit is the TOP bit, so every meta value written by 1.3.0 (which
-- had no such bit) reads back as internal=false — an old cache is stale, not
-- corrupt, and Normalize re-derives it in place rather than forcing a rescan.
----------------------------------------------------------------------
Scan.CACHE_VERSION = 1

local Q_BITS, M_BITS = 16, 4096      -- quality < 16, classMask < 4096
local F_SHIFT = Q_BITS * M_BITS      -- 65536
local I_SHIFT = F_SHIFT * 4          -- 262144

function Scan.PackMeta(quality, classMask, faction, internal)
    local q = math.floor(tonumber(quality)   or 0)
    local m = math.floor(tonumber(classMask) or 0)
    local f = math.floor(tonumber(faction)   or 0)
    if q < 0 then q = 0 elseif q > Q_BITS - 1 then q = Q_BITS - 1 end
    if m < 0 then m = 0 elseif m > M_BITS - 1 then m = M_BITS - 1 end
    if f < 0 then f = 0 elseif f > 3 then f = 3 end
    return q + m * Q_BITS + f * F_SHIFT + (internal and I_SHIFT or 0)
end

-- -> quality, classMask, faction, internal(boolean)
function Scan.UnpackMeta(n)
    n = math.floor(tonumber(n) or 0)
    if n < 0 then n = 0 end
    local q = n % Q_BITS
    local m = math.floor(n / Q_BITS) % M_BITS
    local f = math.floor(n / F_SHIFT) % 4
    local i = math.floor(n / I_SHIFT) % 2 == 1
    return q, m, f, i
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
        local flag
        if restamp then
            local q, m, f = Scan.UnpackMeta(cache.meta[id])
            flag = Scan.IsInternalName(nm)
            cache.meta[id] = Scan.PackMeta(q, m, f, flag)
        else
            flag = select(4, Scan.UnpackMeta(cache.meta[id]))
        end
        if flag then internal = internal + 1 end
    end
    cache.count         = n
    cache.internalCount = internal
    cache.internalStamp = Scan.INTERNAL_STAMP
    return cache
end

function Scan.Put(cache, id, name, quality, classMask, faction)
    if type(cache) ~= "table" then return false end
    id = tonumber(id)
    if not id or type(name) ~= "string" or name == "" then return false end
    cache.names = cache.names or {}
    cache.meta  = cache.meta  or {}
    if cache.names[id] == nil then cache.count = (cache.count or 0) + 1 end
    cache.names[id] = name
    -- The internal flag is DERIVED, never passed in: the name is the only
    -- evidence there is, so a rescan cannot lose the flag and a caller cannot
    -- disagree with the denylist.
    cache.meta[id]  = Scan.PackMeta(quality, classMask, faction, Scan.IsInternalName(name))
    return true
end

-- -> name, quality, classMask, faction, internal   (nil when the id was never scanned)
function Scan.Get(cache, id)
    if type(cache) ~= "table" or type(cache.names) ~= "table" then return nil end
    id = tonumber(id)
    local nm = id and cache.names[id]
    if not nm then return nil end
    local q, m, f, i = Scan.UnpackMeta(cache.meta and cache.meta[id])
    return nm, q, m, f, i
end

-- True once a scan has run to completion at least once on this account.
function Scan.IsComplete(cache)
    return (type(cache) == "table" and cache.scannedAt and (cache.count or 0) > 0) and true or false
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
-- TOOLTIP_BUDGET caps the per-tick tooltip builds (the one genuinely expensive
-- step) so a warm client cache — where every item resolves locally and instantly
-- — cannot drain thousands of items in a single frame and hitch the client.
----------------------------------------------------------------------
Scan.TICK             = 0.05
Scan.INSTANT_PER_TICK = 1200   -- phase 1: local lookups only, no server traffic
Scan.REQUEST_PER_TICK = 15
Scan.MAX_INFLIGHT     = 200
Scan.TOOLTIP_BUDGET   = 25
Scan.REQUEST_TIMEOUT  = 6      -- seconds before a silent request is retried
Scan.MAX_TRIES        = 2

function Scan.PeakRequestsPerSecond() return Scan.REQUEST_PER_TICK / Scan.TICK end
function Scan.PeakRecordsPerSecond()  return Scan.TOOLTIP_BUDGET   / Scan.TICK end
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
-- Locale context for the tooltip parser, built once per session.
----------------------------------------------------------------------
local locCtx
local function localeContext()
    if locCtx then return locCtx end

    local function prefixOf(fmt, fallback)
        local s = (type(fmt) == "string" and fmt ~= "") and fmt or fallback
        return (s:gsub("%%s.*$", ""))
    end

    local classByName = {}
    for _, tbl in ipairs({ _G.LOCALIZED_CLASS_NAMES_MALE, _G.LOCALIZED_CLASS_NAMES_FEMALE }) do
        if type(tbl) == "table" then
            for token, loc in pairs(tbl) do
                if type(token) == "string" and type(loc) == "string" then classByName[loc] = token end
            end
        end
    end
    -- Guarantee at least the viewing character's own class resolves, whatever the
    -- state of the FrameXML tables.
    local myLoc, myTok = UnitClass("player")
    if myLoc and myTok then classByName[myLoc] = myTok end

    local raceFaction = {}
    local CI = _G.C_CreatureInfo
    if CI and CI.GetRaceInfo and CI.GetFactionInfo then
        for raceID = 1, 12 do
            local ri = CI.GetRaceInfo(raceID)
            local fi = CI.GetFactionInfo(raceID)
            local nm = ri and ri.raceName
            local tag = fi and fi.groupTag
            if nm and tag then
                raceFaction[nm] = (tag == "Alliance" and Scan.FACTION_ALLIANCE)
                               or (tag == "Horde"    and Scan.FACTION_HORDE)
                               or Scan.FACTION_NONE
            end
        end
    end

    local aLines, hLines = {}, {}
    local function addLine(t, s) if type(s) == "string" and s ~= "" then t[s] = true end end
    addLine(aLines, _G.ITEM_REQ_ALLIANCE); addLine(aLines, _G.FACTION_ALLIANCE)
    addLine(hLines, _G.ITEM_REQ_HORDE);    addLine(hLines, _G.FACTION_HORDE)

    locCtx = {
        classPrefix   = prefixOf(_G.ITEM_CLASSES_ALLOWED, "Classes: %s"),
        racesPrefix   = prefixOf(_G.ITEM_RACES_ALLOWED,   "Races: %s"),
        classByName   = classByName,
        raceFaction   = raceFaction,
        allianceLines = aLines,
        hordeLines    = hLines,
    }
    return locCtx
end
Addon.ItemScanLocale = localeContext

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
-- Hidden scanning tooltip. Returns the left-text lines BELOW the item name, or
-- nil when the tooltip did not build (item data not loaded yet).
----------------------------------------------------------------------
local scanTip
local function tooltipLines(id)
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "DaseekiArmoryItemScanTip", nil, "GameTooltipTemplate")
        scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    scanTip:ClearLines()
    scanTip:SetItemByID(id)
    local n = scanTip:NumLines() or 0
    if n < 2 then return nil end
    local out = {}
    for i = 2, n do
        local fs = _G["DaseekiArmoryItemScanTipTextLeft" .. i]
        out[#out + 1] = (fs and fs:GetText()) or ""
    end
    return out
end
Addon.ItemScanTooltipLines = tooltipLines

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

function Addon:StartItemScan(opts)
    if ST then return false end
    opts = opts or {}
    local cache = Addon:ItemScanCache()
    if opts.force then cache.names, cache.meta, cache.count = {}, {}, 0 end

    local ranges = Scan.ActiveRanges()
    ST = {
        cache = cache, ranges = ranges, total = Scan.RangeTotal(ranges),
        cursor = 0, phase = "instant",
        queue = {}, qHead = 1, queueTotal = 0,
        ready = {}, rHead = 1,
        inflight = {}, nInflight = 0, tries = {}, doneIds = {},
        found = 0, resolved = 0, failed = 0,
        acc = 0, started = GetTime(),
        valid = slotUnion(), loc = localeContext(),
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

-- Try to read + record an item from what the client already holds. Returns true
-- when the item was recorded (or is known-bad); false means "still needs loading".
local function recordItem(id)
    if not ST then return false end
    if ST.doneIds[id] then
        if ST.inflight[id] then ST.inflight[id] = nil; ST.nInflight = ST.nInflight - 1 end
        return true
    end
    local name, _, quality = GetItemInfo(id)
    if not name then return false end
    local classMask, faction = 0, Scan.FACTION_NONE
    local lines = tooltipLines(id)
    if lines then classMask, faction = Scan.ParseRestrictions(lines, ST.loc) end
    Scan.Put(ST.cache, id, name, quality or 1, classMask, faction)
    ST.doneIds[id] = true
    ST.resolved = ST.resolved + 1
    if ST.inflight[id] then ST.inflight[id] = nil; ST.nInflight = ST.nInflight - 1 end
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
    -- with hundreds of tooltip builds.
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

    local budget = Scan.TOOLTIP_BUDGET

    -- items whose data arrived since the last tick
    while budget > 0 and ST.rHead <= #ST.ready do
        local id = ST.ready[ST.rHead]; ST.rHead = ST.rHead + 1
        if not recordItem(id) then ST.failed = ST.failed + 1 end
        budget = budget - 1
    end

    -- dispatch new work
    local sent = 0
    while budget > 0 and sent < Scan.REQUEST_PER_TICK
          and ST.nInflight < Scan.MAX_INFLIGHT and ST.qHead <= #ST.queue do
        local id = ST.queue[ST.qHead]; ST.qHead = ST.qHead + 1
        if not ST.inflight[id] and not ST.doneIds[id] then
            if recordItem(id) then
                budget = budget - 1
            else
                ST.inflight[id] = now + Scan.REQUEST_TIMEOUT
                ST.nInflight = ST.nInflight + 1
                ST.tries[id] = ST.tries[id] or 1
                -- recordItem's own GetItemInfo(id) miss has ALREADY queued a server
                -- load for this id; the explicit request is the modern, documented
                -- form of the same ask (1.15 C_Item), so a build without it still
                -- resolves through the GetItemInfo path and fires the same event.
                if _G.C_Item and _G.C_Item.RequestLoadItemDataByID then
                    _G.C_Item.RequestLoadItemDataByID(id)
                end
                sent = sent + 1
            end
        end
    end

    report()

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
    cache.autoScanTried = nil        -- a completed scan re-arms the auto path for a future reset
    local n, restricted, internal = 0, 0, 0
    for id in pairs(cache.names) do
        n = n + 1
        local _, m, f, i = Scan.UnpackMeta(cache.meta[id])
        if i then internal = internal + 1
        elseif m > 0 or f ~= Scan.FACTION_NONE then restricted = restricted + 1 end
    end
    cache.count         = n
    cache.internalCount = internal
    cache.internalStamp = Scan.INTERNAL_STAMP

    -- the picker's index is derived from the cache; force a rebuild
    Addon.GoalItemDB, Addon._goalDBStamp = nil, nil

    local secs = Scan.FormatDuration(GetTime() - st.started) or "?"
    -- The internal count is reported, not hidden: the owner should be able to see
    -- that ~12% of what the client holds is Blizzard's own scaffolding, and that
    -- Armory kept it out of the picker on purpose.
    print(string.format("%s item scan complete — %d equippable items cached (%d restricted, "
        .. "%d internal/unobtainable hidden) in %s.%s",
        Addon:Tag(), n - internal, restricted, internal, secs,
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
