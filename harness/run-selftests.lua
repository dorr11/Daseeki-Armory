-- =====================================================================
-- Daseeki-Armory headless self-test harness  (REAL Lua 5.1)
--
-- Loads statmath.lua (the pure formula layer) with no WoW API present and
-- runs fixture suites derived from CSC_BEHAVIOR_SPEC.md. Every fixture's
-- expected value is either quoted directly from the spec/gap-analysis worked
-- examples or derived from the spec's stated formula.
--
-- It also compiles every shipped .lua with loadfile() so a syntax error in any
-- touched file is caught here rather than at login.
--
-- Usage:  lua5.1 run-selftests.lua [ARMORY_DIR]
--   ARMORY_DIR defaults to the repo root one level up from this file.
--   Exit code 0 = ALL PASS.
-- =====================================================================

local HARNESS_DIR = (arg[0]:match("^(.*)[\\/][^\\/]+$")) or "."
local function slash(p) return (p:gsub("\\", "/")) end
HARNESS_DIR = slash(HARNESS_DIR)
local ARMORY_DIR = slash(arg[1] or (HARNESS_DIR .. "/.."))
local function P(rel) return ARMORY_DIR .. "/" .. rel end

----------------------------------------------------------------------
-- Load the pure formula layer. statmath.lua touches NO WoW API at load,
-- which is the property this harness depends on (and asserts).
----------------------------------------------------------------------
local Addon = {}
local fn, err = loadfile(P("statmath.lua"))
if not fn then
    print("HARNESS ERROR: cannot compile statmath.lua -> " .. tostring(err))
    os.exit(2)
end
local ok, rerr = pcall(fn, "Daseeki-Armory", Addon)
if not ok then
    print("HARNESS ERROR: statmath.lua raised at load -> " .. tostring(rerr))
    os.exit(2)
end
local M = Addon.StatMath
if type(M) ~= "table" then
    print("HARNESS ERROR: statmath.lua did not publish Addon.StatMath")
    os.exit(2)
end

----------------------------------------------------------------------
-- Tiny suite runner
----------------------------------------------------------------------
local SUITES, ORDER = {}, {}
local function suite(name, fnc) SUITES[name] = fnc; ORDER[#ORDER + 1] = name end

local function near(a, b, tol)
    return math.abs((a or 0) - (b or 0)) <= (tol or 1e-9)
end

----------------------------------------------------------------------
-- §5.1 / §6 damage: the display range IS the raw API return
----------------------------------------------------------------------
suite("damage-display-range", function(ck)
    -- Gap-analysis worked example: a true 100-150 with +5 physical and x1.1 was
    -- rendered as 116-171 by the pre-fix arithmetic ((min+pos+neg)*pct, rounded).
    local minD, maxD, posB, negB, pct = 100, 150, 5, 0, 1.1
    local oldLo = math.floor((minD + posB + negB) * pct + 0.5)
    local oldHi = math.floor((maxD + posB + negB) * pct + 0.5)
    ck(oldLo == 116 and oldHi == 171, "pre-fix arithmetic reproduces the reported 116-171")

    local lo, hi = M.DamageDisplayRange(minD, maxD)
    ck(lo == 100 and hi == 150, "post-fix range is the raw API return (100-150)")
    ck(M.FormatDamageRange(lo, hi) == "100-150", "3-digit range uses the tight separator")

    -- Flat-bonus case from the gap analysis: posB=5, pct=1.0 inflated by exactly 5.
    local lo2, hi2 = M.DamageDisplayRange(71.4, 99.2)
    ck(lo2 == 71 and hi2 == 100, "floor(min)=71, ceil(max)=100")
    ck(M.FormatDamageRange(71, 99) == "71 - 99", "sub-100 range uses the spaced separator")

    -- Floors at 1, never 0 or negative.
    local lo3, hi3 = M.DamageDisplayRange(0, 0)
    ck(lo3 == 1 and hi3 == 1, "range floors at 1")
    local lo4, hi4 = M.DamageDisplayRange(-8, -3)
    ck(lo4 == 1 and hi4 == 1, "negative returns floor at 1")

    -- nil-safety (the API can return nil before the first UNIT_DAMAGE).
    local lo5, hi5 = M.DamageDisplayRange(nil, nil)
    ck(lo5 == 1 and hi5 == 1, "nil returns floor at 1")
end)

----------------------------------------------------------------------
-- §3 talent tier/column remap
----------------------------------------------------------------------
suite("talent-remap", function(ck)
    -- One tab whose LIVE order is deliberately shuffled relative to the 1.12
    -- tier-then-column reading order.
    --   live 1 -> (2,1)   live 2 -> (1,3)   live 3 -> (1,1)
    --   live 4 -> (3,2)   live 5 -> (2,4)
    -- reading order: (1,1)=live3, (1,3)=live2, (2,1)=live1, (2,4)=live5, (3,2)=live4
    local tab1 = {
        { tier = 2, column = 1 },
        { tier = 1, column = 3 },
        { tier = 1, column = 1 },
        { tier = 3, column = 2 },
        { tier = 2, column = 4 },
    }
    local tab2 = { { tier = 1, column = 1 }, { tier = 1, column = 2 } }
    local tab3 = { { tier = 1, column = 4 } }

    local map = M.BuildTalentRemap({ tab1, tab2, tab3 })
    ck(map ~= nil, "remap builds for a well-formed 3-tab layout")
    ck(map[1][1] == 3, "legacy 1 -> live 3 (tier 1 col 1)")
    ck(map[1][2] == 2, "legacy 2 -> live 2 (tier 1 col 3)")
    ck(map[1][3] == 1, "legacy 3 -> live 1 (tier 2 col 1)")
    ck(map[1][4] == 5, "legacy 4 -> live 5 (tier 2 col 4)")
    ck(map[1][5] == 4, "legacy 5 -> live 4 (tier 3 col 2)")
    ck(map[2][1] == 1 and map[2][2] == 2, "an already-ordered tab is identity")
    ck(map[3][1] == 1, "single-talent tab maps")

    -- Backwards walk: on a duplicate (tier,column) the LOWEST live index wins.
    local dup = M.BuildTalentRemap({ { { tier = 1, column = 1 }, { tier = 1, column = 1 } },
                                     tab2, tab3 })
    ck(dup[1][1] == 1, "duplicate cell resolves to the lowest live index")

    -- Abort rules: any tab with zero talents, or zero tiers, kills the whole build.
    ck(M.BuildTalentRemap({ tab1, {}, tab3 }) == nil, "a zero-talent tab aborts the build")
    ck(M.BuildTalentRemap({ { { tier = nil, column = nil } }, tab2, tab3 }) == nil,
       "a zero-tier tab aborts the build")
    ck(M.BuildTalentRemap({}) == nil, "no tabs aborts the build")

    -- Fall-through: an absent map or an absent index returns the raw index.
    ck(M.RemapTalentIndex(nil, 1, 7) == 7, "nil map falls through to the raw index")
    ck(M.RemapTalentIndex(map, 9, 7) == 7, "missing tab falls through")
    ck(M.RemapTalentIndex(map, 1, 99) == 99, "missing legacy index falls through")
    ck(M.RemapTalentIndex(map, 1, 4) == 5, "present mapping is applied")
end)

----------------------------------------------------------------------
-- §9.3 spell crit from talents
----------------------------------------------------------------------
suite("spell-crit-talents", function(ck)
    local base = { [2] = 3, [3] = 3, [4] = 3, [5] = 3, [6] = 3, [7] = 3 }

    -- Mage, maxed: Arcane Instability 3/3 (+3 all schools) + Critical Mass 3/3
    -- (+6 Fire) => Fire is 9 above the API value. (Gap analysis: "up to 9%
    -- understated on Fire".)
    local mage = M.SpellCritBySchool("MAGE", base,
        { ["Arcane Instability"] = 3, ["Critical Mass"] = 3 }, false)
    ck(mage[3] == 3 + 3 + 6, "mage Fire crit = base + 3 + 6")
    ck(mage[5] == 3 + 3, "mage Frost crit = base + 3 (all-schools talent only)")
    ck(M.MaxSpellCrit(mage) == 12, "mage headline crit is Fire at 12")
    ck(M.MaxSpellCrit(mage) - 3 == 9, "mage understatement vs raw API is 9 points")

    -- Priest, maxed: Holy Specialization 5 + Force of Will 5 + Benediction +2
    -- => Holy is 12 above the API value.
    local priest = M.SpellCritBySchool("PRIEST", base,
        { ["Holy Specialization"] = 5, ["Force of Will"] = 5 }, true)
    ck(priest[2] == 3 + 5 + 5 + 2, "priest Holy crit = base + 5 + 5 + 2")
    ck(M.MaxSpellCrit(priest) - 3 == 12, "priest understatement vs raw API is 12 points")
    local noStaff = M.SpellCritBySchool("PRIEST", base,
        { ["Holy Specialization"] = 5, ["Force of Will"] = 5 }, false)
    ck(noStaff[2] == 3 + 10, "Benediction's +2 only applies when the staff is worn")

    -- Warlock: Devastation rank-as-value on BOTH Shadow and Fire, nothing else.
    local lock = M.SpellCritBySchool("WARLOCK", base, { ["Devastation"] = 5 }, false)
    ck(lock[6] == 8 and lock[3] == 8, "warlock Shadow and Fire both +5")
    ck(lock[2] == 3, "warlock Holy untouched")

    -- Shaman: Call of Thunder rank 5 grants 6 (not 5) — the game's own jump.
    -- Lightning starts as a copy of Nature, then takes CoT + Tidal Mastery;
    -- Nature takes Tidal Mastery only.
    local sham = M.SpellCritBySchool("SHAMAN", base,
        { ["Call of Thunder"] = 5, ["Tidal Mastery"] = 5 }, false)
    ck(sham.LIGHTNING == 3 + 6 + 5, "shaman Lightning = base + 6 + 5")
    ck(sham[4] == 3 + 5, "shaman Nature = base + 5 (Tidal Mastery only)")
    ck(M.MaxSpellCrit(sham) - 3 == 11, "shaman understatement vs raw API is 11 points")
    local cot4 = M.SpellCritBySchool("SHAMAN", base, { ["Call of Thunder"] = 4 }, false)
    ck(cot4.LIGHTNING == 3 + 4, "Call of Thunder rank 4 grants 4, rank 5 grants 6")

    -- A class with no crit talents is a pure pass-through.
    local war = M.SpellCritBySchool("WARRIOR", base, {}, false)
    ck(M.MaxSpellCrit(war) == 3, "a class with no spell-crit talents is unchanged")

    -- Unspent talents contribute nothing.
    local none = M.SpellCritBySchool("MAGE", base,
        { ["Arcane Instability"] = 0, ["Critical Mass"] = 0 }, false)
    ck(M.MaxSpellCrit(none) == 3, "rank 0 contributes nothing")
end)

----------------------------------------------------------------------
-- §9.5 mana regen
----------------------------------------------------------------------
suite("mana-regen", function(ck)
    -- The +1-per-item correction. Two MP5 pieces reporting 6 and 4 contribute 12,
    -- not 10.
    ck(M.GearMP5FromItemStats({ 6, 4 }) == 12, "item MP5 adds +1 per contributing item")
    ck(M.GearMP5FromItemStats({}) == 0, "no MP5 gear contributes 0")
    ck(M.GearMP5FromItemStats({ 0, nil, 5 }) == 6, "zero/absent entries are not contributors")

    -- Aura table, unmodified.
    local mp5, frac = M.AuraMP5({ 25290, 18194 }, 0)
    ck(mp5 == 33 + 8, "Blessing of Wisdom r6 (33) + Nightfin Soup (8)")
    ck(frac == 0, "no combat-regen aura present")

    -- Paladin Improved Blessing of Wisdom scales ONLY the Wisdom auras.
    local mp5b = M.AuraMP5({ 25290, 18194 }, 3)
    ck(near(mp5b, 33 * 1.3 + 8, 1e-9), "Improved BoW r3 scales 33 -> 42.9, soup untouched")
    local mp5c = M.AuraMP5({ 10497 }, 3)
    ck(mp5c == 25, "Mana Spring Totem is not scaled by Improved BoW")

    -- Mage Armor is a casting-regen fraction, not flat MP5.
    local mp5d, fracd = M.AuraMP5({ 22783 }, 0)
    ck(mp5d == 0 and near(fracd, 0.30), "Mage Armor contributes 0.30 casting fraction, 0 MP5")

    -- Casting modifier assembly.
    ck(near(M.CastingModifier("PRIEST", 3, 0, 0), 0.15), "Meditation 3/3 = 0.15")
    ck(near(M.CastingModifier("PRIEST", 3, 3, 0), 0.30), "priest 3-piece tier adds 0.15")
    ck(near(M.CastingModifier("MAGE", 3, 3, 0), 0.15), "the tier bonus is Druid/Priest only")
    ck(near(M.CastingModifier("MAGE", 3, 0, 0.30), 0.45), "Mage Armor stacks onto Arcane Meditation")

    -- Full worked example: base 3.0 mana/sec, gear 6+4 MP5 items + wrist enchant
    -- (+4), Blessing of Wisdom r6 under Improved BoW 3/3, Meditation 3/3.
    local base    = 3.0
    local gearMP5 = M.GearMP5FromItemStats({ 6, 4 }) + 4          -- 12 + 4 = 16
    local auraMP5 = select(1, M.AuraMP5({ 25290 }, 3))            -- 42.9
    local mod     = M.CastingModifier("PRIEST", 3, 0, 0)          -- 0.15
    local notCasting, casting = M.ManaRegenRows(base, gearMP5, auraMP5, mod)
    ck(near(notCasting, 3 * 5 + 16 + 42.9, 1e-9), "not-casting = base*5 + gear + auras = 73.9")
    ck(near(casting, 16 + 42.9 + 3 * 0.15 * 5, 1e-9), "casting = gear + auras + base*mod*5 = 61.15")
    ck(notCasting ~= casting, "the two rows are distinct (the shipped bug printed one number twice)")

    -- With no Meditation-style modifier the casting row is gear+auras only:
    -- spirit regen stops entirely for five seconds after a cast.
    local nc2, c2 = M.ManaRegenRows(3.0, 16, 0, 0)
    ck(near(nc2, 31) and near(c2, 16), "modifier 0 => casting row carries no spirit regen")

    -- Zero-flash guard.
    ck(M.ZeroFlashGuard(0, 4.2) == 4.2, "a transient 0 is replaced by the last good reading")
    ck(M.ZeroFlashGuard(0.5, 4.2) == 4.2, "anything under 1 is treated as the transient case")
    ck(M.ZeroFlashGuard(nil, 4.2) == 4.2, "nil is replaced by the last good reading")
    ck(M.ZeroFlashGuard(7.5, 4.2) == 7.5, "a real reading passes through")
    ck(M.ZeroFlashGuard(0, nil) == 0, "no cached reading yet degrades to 0, not nil")
end)

----------------------------------------------------------------------
-- §7.2 defense / §7.4 block value / §6 ranged hit
----------------------------------------------------------------------
suite("defense-block-ranged", function(ck)
    ck(M.DefenseValue(315, 10) == 325, "defense = rank + modifier")
    ck(M.DefenseValue(300, -20) == 280, "a negative modifier subtracts")
    ck(M.DefenseValue(5, -50) == 0, "defense never renders below 0")
    ck(M.DefenseValue(nil, nil) == 0, "nil-safe")

    -- Gap analysis: a 220-strength warrior is understated by ~11 without the
    -- Strength/20 term.
    ck(near(M.BlockValue(0, 220, 0, 0), 11), "Strength 220 contributes 11 block value")
    ck(near(M.BlockValue(46, 220, 0, 0), 57), "gear-scanned block value adds on top")
    ck(near(M.BlockValue(46, 220, 3, 0), 87), "Battlegear of Might 3-piece adds 30")
    ck(near(M.BlockValue(46, 220, 2, 0), 57), "2 pieces is below the set threshold")
    ck(near(M.BlockValue(46, 220, 3, 2), 117), "two warrior ZG enchants add 15 each")
    ck(near(M.BlockValue(nil, nil, nil, nil), 0), "nil-safe")

    ck(M.RangedHit(4, true) == 7, "the ranged scope enchant adds +3 hit")
    ck(M.RangedHit(4, false) == 4, "no scope, no bonus")
    ck(M.RangedHit(nil, false) == 0, "nil hit modifier reads as 0")

    ck(M.EnchantIdFromLink("|cff1eff00|Hitem:2825:2523:0:0:0:0:0:0:60|h[Bow]|h|r") == 2523,
       "permanent enchant id is parsed out of the item link")
    ck(M.EnchantIdFromLink("|cff1eff00|Hitem:2825:0:0:0:0:0:0:0:60|h[Bow]|h|r") == 0,
       "an unenchanted link reads enchant 0")
    ck(M.EnchantIdFromLink("item:2825") == nil, "a link with no enchant field reads nil")
    ck(M.EnchantIdFromLink(nil) == nil, "nil link is safe")
end)

----------------------------------------------------------------------
-- Table integrity (constants transcribed from the spec)
----------------------------------------------------------------------
suite("spec-tables", function(ck)
    ck(M.AURA_MP5[19742] == 10 and M.AURA_MP5[25290] == 33, "Blessing of Wisdom ranks")
    ck(M.AURA_MP5[25894] == 30 and M.AURA_MP5[25918] == 33, "Greater Blessing of Wisdom ranks")
    ck(M.AURA_MP5[5675] == 10 and M.AURA_MP5[10497] == 25, "Mana Spring Totem ranks")
    ck(M.AURA_MP5[24363] == 12, "Mageblood Potion")
    ck(M.AURA_MP5[18194] == 8, "Nightfin Soup")
    ck(M.AURA_IS_WISDOM[10497] == nil, "Mana Spring is not a Wisdom aura")

    local bomCount = 0
    for _ in pairs(M.BATTLEGEAR_OF_MIGHT_IDS) do bomCount = bomCount + 1 end
    ck(bomCount == 8, "Battlegear of Might covers ids 16861-16868")
    ck(M.BATTLEGEAR_OF_MIGHT_IDS[16861] and M.BATTLEGEAR_OF_MIGHT_IDS[16868], "endpoints present")

    local tierCount = 0
    for _ in pairs(M.CASTING_REGEN_SET_IDS) do tierCount = tierCount + 1 end
    ck(tierCount == 16, "Transcendence + Stormrage is a 16-id combined tally")

    ck(M.SCOPE_ENCHANT_ID == 2523 and M.SCOPE_ENCHANT_VALUE == 3, "scope enchant constants")
    ck(M.BENEDICTION_ITEM_ID == 18608, "Benediction item id")
    ck(M.WARRIOR_ZG_BLOCK_ENCHANT_ID == 2583, "warrior ZG block enchant id")
    ck(M.MP5_ENCHANTS.WRIST.id == 2565 and M.MP5_ENCHANTS.WRIST.mp5 == 4, "wrist MP5 enchant")
    ck(M.MP5_ENCHANTS.SHOULDER.id == 2715 and M.MP5_ENCHANTS.SHOULDER.mp5 == 5, "shoulder MP5 enchant")
    ck(M.MP5_ENCHANTS.PRIEST_HEAD.id == 2590 and M.MP5_ENCHANTS.PRIEST_HEAD.mp5 == 4, "priest ZG MP5 enchant")
    ck(M.MP5_ENCHANTS.MAINHAND_OIL.id == 2629 and M.MP5_ENCHANTS.MAINHAND_OIL.mp5 == 12, "Brilliant Mana Oil")
end)

----------------------------------------------------------------------
-- Equip engine (equip.lua) — driven headlessly against a virtual
-- bags/worn/cursor world. Behaviors are those specified in
-- ITEMRACK_BEHAVIOR_SPEC.md §1.3, §2.x, §4 and TRINKETMENU_BEHAVIOR_SPEC.md §2.3.
----------------------------------------------------------------------
local mock = dofile(HARNESS_DIR .. "/equip-mock.lua")
local L = mock.link

-- Each equip suite gets a fresh world, and the world is always torn down so a
-- failure can never leave the mocked globals installed.
local function world(fnc)
    return function(ck)
        local w = mock.new(P)
        local ok, err = pcall(fnc, ck, w, w.Addon)
        w:teardown()
        if not ok then error(err, 0) end
    end
end

-- §0 the engine's slot list must stay in step with core.lua's Addon.SLOTS
suite("equip-slot-model", world(function(ck, w, A)
    local core = io.open(P("core.lua"), "r")
    ck(core ~= nil, "core.lua is readable")
    if not core then return end
    local ids = {}
    for line in core:lines() do
        local id = line:match("^%s*{%s*id%s*=%s*(%d+)%s*,")
        if id then ids[#ids + 1] = tonumber(id) end
    end
    core:close()
    ck(#ids == #mock.SLOT_IDS, "core.lua declares " .. #mock.SLOT_IDS .. " slots, found " .. #ids)
    local same = true
    for i, v in ipairs(mock.SLOT_IDS) do if ids[i] ~= v then same = false end end
    ck(same, "mock slot order matches core.lua Addon.SLOTS order")
    -- every managed slot has an INVTYPE mapping, and ammo is not managed
    local missing = {}
    for _, id in ipairs(ids) do
        if not A.SLOT_INVTYPES[id] then missing[#missing + 1] = id end
    end
    ck(#missing == 0, "every managed slot has SLOT_INVTYPES (missing: " .. table.concat(missing, ",") .. ")")
    ck(A.SLOT_INVTYPES[0] == nil, "ammo slot 0 is not managed")
    -- goalPicker.lua takes this table verbatim and tests validLoc[item.equipLoc],
    -- so it must be keyed BY equip location, not an array of them.
    ck(A.SLOT_INVTYPES[16]["INVTYPE_2HWEAPON"] == true, "main hand accepts two-handers")
    ck(A.SLOT_INVTYPES[16][1] == nil, "SLOT_INVTYPES is keyed by equip location, not an array")
    ck(A.SLOT_INVTYPES[17]["INVTYPE_SHIELD"] == true, "off hand accepts shields")
    ck(A.SLOT_INVTYPES[17]["INVTYPE_2HWEAPON"] == nil, "off hand rejects two-handers")
    ck(A.SLOT_INVTYPES[5]["INVTYPE_ROBE"] == true, "chest accepts robes")
end))

-- §1.3 two-tier identity: exact first, base id as fallback; claims stop two
-- slots resolving to one item.
suite("equip-set-resolution", world(function(ck, w, A)
    -- exact identity beats a plain copy of the same base item
    w:setBag(1, 1, L(1001, 0))        -- plain
    w:setBag(2, 1, L(1001, 2504))     -- enchanted
    w:defineSet("exact", { [11] = L(1001, 2504) })
    A:EquipSet("exact")
    ck(w.worn[11] == L(1001, 2504), "exact identity wins over a plain copy of the same base id")
    ck(w:bagOf(1, 1) == L(1001, 0), "the plain copy is left alone")

    -- loose fallback when no exact match exists
    local w2 = mock.new(P)
    w2:setBag(0, 5, L(1002, 777))
    w2:defineSet("loose", { [12] = L(1002, 0) })
    w2.Addon:EquipSet("loose")
    ck(w2.worn[12] == L(1002, 777), "falls back to base-item-id match")
    w2:teardown()

    -- two ring slots, two distinct copies: the claim table stops a collision
    local w3 = mock.new(P)
    w3:setBag(0, 1, L(1001, 10))
    w3:setBag(0, 2, L(1001, 20))
    w3:defineSet("pair", { [11] = L(1001, 10), [12] = L(1001, 20) })
    w3.Addon:EquipSet("pair")
    ck(w3.worn[11] == L(1001, 10), "ring slot 11 got its own copy")
    ck(w3.worn[12] == L(1001, 20), "ring slot 12 got the other copy")
    ck(w3.worn[11] ~= w3.worn[12], "two slots never resolve to the same source item")
    w3:teardown()

    -- a worn item is a valid source: cross-slot ring exchange
    local w4 = mock.new(P)
    w4:setWorn(11, L(1002))
    w4:setWorn(12, L(1001))
    w4:defineSet("cross", { [11] = L(1001), [12] = L(1002) })
    w4.Addon:EquipSet("cross")
    ck(w4.worn[11] == L(1001), "cross-swap put the right ring in slot 11")
    ck(w4.worn[12] == L(1002), "cross-swap put the right ring in slot 12")
    ck(w4.cursor == nil, "cross-swap leaves nothing stranded on the cursor")
    w4:teardown()
end))

-- §2.5/§2.6 execution: displaced items are put down, guards refuse cleanly.
suite("equip-execution", world(function(ck, w, A)
    -- equipping over an occupied slot returns the old item to the source bag slot
    w:setWorn(1, L(3002))
    w:setBag(0, 3, L(3001))
    w:defineSet("helm", { [1] = L(3001) })
    A:EquipSet("helm")
    ck(w.worn[1] == L(3001), "new helm equipped")
    ck(w:bagOf(0, 3) == L(3002), "displaced helm went back into the vacated bag slot")
    ck(w.cursor == nil, "cursor is empty after the swap")

    -- a two-hander clears the off hand into a free bag slot
    local w2 = mock.new(P)
    w2:setWorn(16, L(4002))
    w2:setWorn(17, L(4003))
    w2:setBag(0, 1, L(4001))
    w2:defineSet("2h", { [16] = L(4001) })
    w2.Addon:EquipSet("2h")
    ck(w2.worn[16] == L(4001), "two-hander equipped to main hand")
    ck(w2.worn[17] == nil, "off hand was cleared for the two-hander")
    ck(w2.cursor == nil, "nothing stranded on the cursor after the 2H swap")
    w2:teardown()

    -- cursor already occupied: refuse, change nothing
    local w3 = mock.new(P)
    w3:setBag(0, 1, L(3001))
    w3:setWorn(1, L(3002))
    w3.cursor = L(9999)
    w3:defineSet("blocked", { [1] = L(3001) })
    w3.Addon:EquipSet("blocked")
    ck(w3.worn[1] == L(3002), "an occupied cursor blocks the swap")
    ck(w3:output():find("cursor") ~= nil, "the cursor abort is reported to the user")
    w3:teardown()

    -- no free bag slot for the displaced off hand: abort with the room message
    local w4 = mock.new(P)
    w4:setWorn(16, L(4002))
    w4:setWorn(17, L(4003))
    w4:setBag(0, 1, L(4001))
    w4:fillBags(0)
    w4:defineSet("2hfull", { [16] = L(4001) })
    w4.Addon:EquipSet("2hfull")
    ck(w4.worn[17] == L(4003), "off hand kept when there is nowhere to put it")
    ck(w4:output():find("bag space") ~= nil, "the not-enough-room abort is reported")
    w4:teardown()
end))

-- §4 partial sets: the rest of the set still equips, missing items reported once.
suite("equip-partial-sets", world(function(ck, w, A)
    w:setBag(0, 1, L(3001))
    w:setWorn(11, L(1003))
    w:defineSet("partial", { [1] = L(3001), [11] = L(1001), [13] = L(2001) })
    A:EquipSet("partial")
    ck(w.worn[1] == L(3001), "the findable item still equipped")
    ck(w.worn[11] == L(1003), "the unfindable slot kept what it had")
    ck(w.worn[13] == nil, "the unfindable trinket slot stayed empty")
    local out = w:output()
    ck(out:find("Ring of Testing") ~= nil, "missing ring named in the report")
    ck(out:find("Trinket Alpha") ~= nil, "missing trinket named in the report")
    local _, n = out:gsub("could not find", "")
    ck(n == 1, "the missing-item line is printed exactly once (got " .. n .. ")")

    -- a disabled slot is not governed at all
    local w2 = mock.new(P)
    w2:setBag(0, 1, L(3001))
    w2:setWorn(1, L(3002))
    w2:defineSet("dis", { [1] = L(3001) }, { [1] = true })
    ck(w2.Addon:IsSlotActive(w2.Addon:GetSet("dis"), 1) == false, "a disabled slot is inactive")
    w2.Addon:EquipSet("dis")
    ck(w2.worn[1] == L(3002), "a disabled slot is never touched")
    w2:teardown()

    -- a stale exact key over the right base item is not reported missing
    local w3 = mock.new(P)
    w3:setWorn(1, L(3001, 2504))                  -- worn: enchanted
    w3:defineSet("stale", { [1] = L(3001, 0) })   -- set: plain (e.g. an import)
    w3.Addon:EquipSet("stale")
    ck(w3:output():find("could not find") == nil, "same base item worn is not reported missing")
    w3:teardown()
end))

-- §2.7 multi-pass convergence, driven by ITEM_LOCK_CHANGED.
suite("equip-convergence", world(function(ck, w, A)
    w:setBag(0, 1, L(3001))
    w:setBag(0, 2, L(1001))
    w:defineSet("conv", { [1] = L(3001), [11] = L(1001) })
    A:EquipSet("conv")
    ck(w.worn[1] == L(3001) and w.worn[11] == L(1001), "pass 1 satisfied the whole set")

    -- re-planning a satisfied set yields an empty plan (the convergence property)
    local plan, missing = A:PlanSet(A:GetSet("conv"), A:BuildCensus())
    ck(#plan == 0, "a satisfied set re-plans to zero operations")
    ck(#missing == 0, "a satisfied set reports nothing missing")

    -- the lock watcher finalises once the inventory settles
    w:fireEvent("ITEM_LOCK_CHANGED")
    w:pumpTimers()
    ck(A._equipping == nil, "the engine finalised after the locks settled")
    ck(A.db.currentSet == "conv", "the equipped set became the current set")
    ck(A:IsSetEquipped("conv") == true, "IsSetEquipped agrees the set is worn")

    -- while something is still locked the next pass must not run
    local w2 = mock.new(P)
    w2:setBag(0, 1, L(3001))
    w2:defineSet("held", { [1] = L(3001) })
    w2.Addon:EquipSet("held")
    w2.locks["w11"] = true
    local before = #w2.log
    w2:fireEvent("ITEM_LOCK_CHANGED")
    w2:pumpTimers()
    ck(#w2.log == before, "no further moves are attempted while anything is locked")
    w2:teardown()

    -- an unsatisfiable set terminates instead of looping
    local w3 = mock.new(P)
    w3:defineSet("nope", { [1] = L(3001) })
    w3.Addon:EquipSet("nope")
    for _ = 1, 5 do w3:fireEvent("ITEM_LOCK_CHANGED"); w3:pumpTimers() end
    ck(w3.Addon._equipping == nil, "an unsatisfiable set does not stay in progress")
    w3:teardown()
end))

-- §2.8 / TRINKETMENU §2.3 the combat and really-dead queue contract.
suite("equip-combat-queue", world(function(ck, w, A)
    w:setBag(0, 1, L(3001))
    w:defineSet("cq", { [1] = L(3001) })

    w.combat = true
    ck(A:MustQueueSwap() == true, "in combat a swap must be queued")
    A:EquipSet("cq")
    ck(w.worn[1] == nil, "nothing swapped while in combat")
    ck(A._pendingSet == "cq", "the set is held as pending")

    w.combat = false
    w:fireEvent("PLAYER_REGEN_ENABLED")
    w:pumpTimers()
    ck(w.worn[1] == L(3001), "leaving combat drained the queue and equipped the set")
    ck(A._pendingSet == nil, "the pending set was consumed")

    -- feign death is treated as alive and swaps immediately
    local w2 = mock.new(P)
    w2:setBag(0, 1, L(3001))
    w2:defineSet("feign", { [1] = L(3001) })
    w2.dead, w2.feign = true, true
    ck(w2.Addon:IsReallyDead() == false, "a feigning hunter is not really dead")
    ck(w2.Addon:MustQueueSwap() == false, "feign death does not force queueing")
    w2.Addon:EquipSet("feign")
    ck(w2.worn[1] == L(3001), "feign death swaps immediately")
    w2:teardown()

    -- really dead: queue is held across the death-time regen event
    local w3 = mock.new(P)
    w3:setBag(0, 1, L(3001))
    w3:defineSet("dead", { [1] = L(3001) })
    w3.dead, w3.feign = true, false
    ck(w3.Addon:IsReallyDead() == true, "dead and not feigning is really dead")
    w3.Addon:EquipSet("dead")
    ck(w3.Addon._pendingSet == "dead", "the set queued while dead")
    -- dying drops combat, so PLAYER_REGEN_ENABLED fires against the corpse
    w3:fireEvent("PLAYER_REGEN_ENABLED")
    w3:pumpTimers()
    ck(w3.worn[1] == nil, "the queue is NOT consumed against a corpse")
    ck(w3.Addon._pendingSet == "dead", "the pending set survives the corpse-time regen event")
    -- resurrect
    w3.dead = false
    w3:fireEvent("PLAYER_UNGHOST")
    w3:pumpTimers()
    ck(w3.worn[1] == L(3001), "the queue drained on resurrection")
    w3:teardown()

    -- resurrecting mid-fight must NOT consume the queue
    local w5 = mock.new(P)
    w5:setBag(0, 1, L(3001))
    w5:defineSet("resu", { [1] = L(3001) })
    w5.dead = true
    w5.Addon:EquipSet("resu")
    w5.dead, w5.combat = false, true          -- resurrected, still fighting
    w5:fireEvent("PLAYER_UNGHOST")
    w5:pumpTimers()
    ck(w5.worn[1] == nil, "resurrecting while still in combat does not consume the queue")
    ck(w5.Addon._pendingSet == "resu", "the pending set survives a mid-fight resurrect")
    w5.combat = false
    w5:fireEvent("PLAYER_REGEN_ENABLED")
    w5:pumpTimers()
    ck(w5.worn[1] == L(3001), "it drains once combat actually ends")
    w5:teardown()

    -- PLAYER_ALIVE is also a drain trigger
    local w4 = mock.new(P)
    w4:setBag(0, 1, L(3001))
    w4:defineSet("alive", { [1] = L(3001) })
    w4.dead = true
    w4.Addon:EquipSet("alive")
    w4.dead = false
    w4:fireEvent("PLAYER_ALIVE")
    w4:pumpTimers()
    ck(w4.worn[1] == L(3001), "PLAYER_ALIVE drains the queue")
    w4:teardown()
end))

-- §2.8 per-slot queue: toggle-off, last-writer-wins, ascending drain order.
suite("equip-queue-ordering", world(function(ck, w, A)
    w.combat = true
    w:setBag(0, 1, L(2001))
    w:setBag(0, 2, L(2002))

    -- queue trinket 14 FIRST, then 13, to prove drain order is by slot not arrival
    ck(A:EquipContainerItemToSlot(0, 2, 14) == true, "queued an item for slot 14")
    ck(A:EquipContainerItemToSlot(0, 1, 13) == true, "queued an item for slot 13")

    w.combat = false
    w.log = {}
    w:fireEvent("PLAYER_REGEN_ENABLED")
    w:pumpTimers()
    ck(w.worn[13] == L(2001), "slot 13 received its queued trinket")
    ck(w.worn[14] == L(2002), "slot 14 received its queued trinket")
    local i13, i14
    for i, e in ipairs(w.log) do
        if e == "worn:13" and not i13 then i13 = i end
        if e == "worn:14" and not i14 then i14 = i end
    end
    ck(i13 and i14 and i13 < i14, "the queue drains in ascending slot order (13 before 14)")

    -- re-queueing the identical action toggles it back off
    local w2 = mock.new(P)
    w2.combat = true
    w2:setBag(0, 1, L(2001))
    ck(w2.Addon:EquipContainerItemToSlot(0, 1, 13) == true, "first request queues")
    ck(w2.Addon:EquipContainerItemToSlot(0, 1, 13) == false, "the identical request un-queues")
    ck(w2.Addon._combatQueue[13] == nil, "the slot has no pending action after the toggle")
    w2:teardown()

    -- a different item for the same slot replaces rather than stacking
    local w3 = mock.new(P)
    w3.combat = true
    w3:setBag(0, 1, L(2001))
    w3:setBag(0, 2, L(2002))
    w3.Addon:EquipContainerItemToSlot(0, 1, 13)
    w3.Addon:EquipContainerItemToSlot(0, 2, 13)
    w3.combat = false
    w3:fireEvent("PLAYER_REGEN_ENABLED")
    w3:pumpTimers()
    ck(w3.worn[13] == L(2002), "the later request for a slot wins (last-writer-wins)")
    ck(w3:bagOf(0, 1) == L(2001), "the superseded item was never equipped")
    w3:teardown()

    -- queued unequip drains too
    local w4 = mock.new(P)
    w4.combat = true
    w4:setWorn(13, L(2001))
    ck(w4.Addon:UnequipSlot(13) == true, "unequip queues in combat")
    w4.combat = false
    w4:fireEvent("PLAYER_REGEN_ENABLED")
    w4:pumpTimers()
    ck(w4.worn[13] == nil, "the queued unequip drained")
    w4:teardown()
end))

-- Interface compatibility: the surface the rest of Armory and user macros use.
suite("equip-public-surface", world(function(ck, w, A)
    for _, name in ipairs({
        "ChatMsg", "IsSlotActive", "IsEntryAvailable", "SlotMatches", "SlotMatchesBase",
        "FindInBags", "FindInEquipped", "FindFreeBagSlot", "EquipSlot", "EquipPass",
        "FinishEquip", "RunEquip", "IsReallyDead", "MustQueueSwap", "QueueReason",
        "QueueWhen", "StopQueueWatcher", "DrainCombatQueue", "EnsureRegenWatcher",
        "QueueCombatAction", "DeferToCombatEnd", "EquipContainerItemToSlot",
        "UnequipSlot", "GetInventoryItemsForSlot", "SwapEquippedSlots",
        "EquipSet", "IsSetEquipped", "ToggleSet", "GetEquipMacro",
    }) do
        ck(type(A[name]) == "function", "Addon:" .. name .. " is present")
    end
    ck(type(A.SLOT_INVTYPES) == "table", "Addon.SLOT_INVTYPES is present")

    ck(type(_G.ArmEquip) == "function", "global ArmEquip is exported for macros")
    ck(type(_G.ArmToggle) == "function", "global ArmToggle is exported for macros")
    ck(_G.ArmoryEquipSet == _G.ArmEquip, "ArmoryEquipSet aliases ArmEquip")
    ck(_G.ArmoryToggleSet == _G.ArmToggle, "ArmoryToggleSet aliases ArmToggle")

    ck(A:GetEquipMacro("My Set") == '/run ArmEquip("My Set")', "GetEquipMacro text is unchanged")

    -- the global macro path really equips through DaseekiArmory
    w:setBag(0, 1, L(3001))
    w:defineSet("macro", { [1] = L(3001) })
    _G.ArmEquip("macro")
    ck(w.worn[1] == L(3001), '/run ArmEquip("name") equips the set')

    -- GetInventoryItemsForSlot record shape consumed by flyout.lua / trinkets.lua
    local w2 = mock.new(P)
    w2:setBag(0, 4, L(2001))
    w2:setWorn(13, L(2002))
    local items = w2.Addon:GetInventoryItemsForSlot(13, false)
    ck(#items == 1, "bag-only listing excludes worn items")
    ck(items[1].link == L(2001) and items[1].bag == 0 and items[1].slot == 4,
       "bag records carry link/bag/slot")
    ck(items[1].equipped == false, "bag records are flagged not-equipped")
    local both = w2.Addon:GetInventoryItemsForSlot(13, true)
    ck(#both == 2, "includeEquipped adds worn items")
    ck(both[1].equipped == true and both[1].invSlot == 13, "worn records come first and carry invSlot")
    -- slot filtering really applies
    ck(#w2.Addon:GetInventoryItemsForSlot(1, false) == 0, "a trinket is not offered for the head slot")
    w2:teardown()

    -- the find helpers must reach the base-id fallback when no exact match exists
    local w4 = mock.new(P)
    w4:setBag(3, 7, L(1001, 999))          -- enchanted copy only
    w4:setWorn(12, L(1002, 888))
    local plainRing = w4.Addon:IdentityFromLink(L(1001, 0))
    local bag, slot = w4.Addon:FindInBags(plainRing)
    ck(bag == 3 and slot == 7, "FindInBags falls back to a base-id match")
    local plainWorn = w4.Addon:IdentityFromLink(L(1002, 0))
    ck(w4.Addon:FindInEquipped(plainWorn) == 12, "FindInEquipped falls back to a base-id match")
    ck(w4.Addon:FindInEquipped(plainWorn, 12) == nil, "FindInEquipped honours the exclude slot")
    ck(w4.Addon:FindFreeBagSlot() ~= nil, "FindFreeBagSlot reports a free slot")
    w4:teardown()

    -- IsSetEquipped / IsEntryAvailable
    local w3 = mock.new(P)
    w3:setBag(0, 1, L(3001))
    w3:defineSet("chk", { [1] = L(3001) })
    ck(w3.Addon:IsSetEquipped("chk") == false, "not equipped before the swap")
    ck(w3.Addon:IsEntryAvailable(w3.Addon:GetSet("chk").equip[1]) == true, "entry available from bags")
    w3.Addon:EquipSet("chk")
    ck(w3.Addon:IsSetEquipped("chk") == true, "equipped after the swap")
    ck(w3.Addon:IsSetEquipped("no-such-set") == false, "unknown set is not equipped")
    w3:teardown()
end))

----------------------------------------------------------------------
-- Every shipped file compiles (loadfile gate)
----------------------------------------------------------------------
suite("loadfile-all-files", function(ck)
    local toc = io.open(P("Daseeki-Armory.toc"), "r")
    ck(toc ~= nil, "TOC is readable")
    if not toc then return end
    local files, sawStatMath = {}, false
    for line in toc:lines() do
        local f = line:match("^%s*([%w_%-]+%.lua)%s*$")
        if f then
            files[#files + 1] = f
            if f == "statmath.lua" then sawStatMath = true end
        end
    end
    toc:close()
    ck(#files > 0, "TOC lists lua files")
    ck(sawStatMath, "statmath.lua is listed in the TOC")
    for _, f in ipairs(files) do
        local c, e = loadfile(P(f))
        ck(c ~= nil, "compiles: " .. f .. (c and "" or (" -> " .. tostring(e))))
    end
end)

----------------------------------------------------------------------
-- Run
----------------------------------------------------------------------
print("=== Daseeki-Armory stat-formula self-tests (real Lua 5.1) ===")
print("    repo: " .. ARMORY_DIR)
print("")

local totalFail, totalCheck = 0, 0
for _, name in ipairs(ORDER) do
    local fails, checks = {}, 0
    local function ck(cond, msg)
        checks = checks + 1
        if not cond then fails[#fails + 1] = msg end
    end
    local sok, serr = pcall(SUITES[name], ck)
    if not sok then fails[#fails + 1] = "SUITE RAISED: " .. tostring(serr) end
    totalCheck = totalCheck + checks
    totalFail  = totalFail + #fails
    print(string.format("  [%s] %-24s (%d checks)", #fails == 0 and "PASS" or "FAIL", name, checks))
    for _, f in ipairs(fails) do print("        FAIL :: " .. tostring(f)) end
end

print("")
print("############################################################")
print(string.format("# Daseeki-Armory self-tests : %s  (%d checks, %d failures)",
      totalFail == 0 and "ALL PASS" or "RED", totalCheck, totalFail))
print("############################################################")
os.exit(totalFail == 0 and 0 or 1)
