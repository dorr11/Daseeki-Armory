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

-- §1.2 / §2.5A explicit-empty slots: the sentinel entry, its planning, and the
-- bag-space rule that governs it.
suite("equip-explicit-empty", world(function(ck, w, A)
    ck(A:IsEmptyEntry({ id = 0 }) == true, "id 0 is the explicit-empty sentinel")
    ck(A:IsEmptyEntry(A:EmptyEntry()) == true, "EmptyEntry() builds a sentinel")
    ck(A:IsEmptyEntry(A:IdentityFromLink(L(1001))) == false, "a real item is not a sentinel")
    ck(A:IsEmptyEntry(nil) == false, "nil is not a sentinel")
    ck(A:EntryLink(A:EmptyEntry()) == nil, "the sentinel resolves to no item link")

    -- a governed empty slot with something in it is stripped into a bag
    w:setWorn(13, L(2001))
    w:defineSet("strip", { [13] = mock.EMPTY })
    local freeBefore = w:countFreeBagSlots()
    ck(A:SlotMatches(13, A:GetSet("strip").equip[13]) == false, "an occupied slot does not satisfy the sentinel")
    A:EquipSet("strip")
    ck(w.worn[13] == nil, "the explicitly-empty slot was stripped")
    ck(w:countFreeBagSlots() == freeBefore - 1, "the item went into exactly one free bag slot")
    ck(w.cursor == nil, "nothing is stranded on the cursor")
    ck(A:IsSetEquipped("strip") == true, "an emptied slot counts as the set being worn")
    ck(w:output():find("could not find") == nil, "a sentinel is never reported as a missing item")

    -- the planner emits exactly one unequip op, and nothing at all once satisfied
    local w2 = mock.new(P)
    w2:setWorn(13, L(2001))
    w2:defineSet("planned", { [13] = mock.EMPTY })
    local p = w2.Addon:PlanSet(w2.Addon:GetSet("planned"), w2.Addon:BuildCensus())
    ck(#p == 1, "one operation is planned for the sentinel")
    ck(p[1].slot == 13 and p[1].unequip == true, "…and it is an unequip of that slot")
    ck(p[1].from == nil, "an unequip op has no source location")
    ck(w2.Addon:OpStillNeeded(p[1]) == true, "the unequip is still needed while the slot is occupied")
    w2.worn[13] = nil
    ck(w2.Addon:OpStillNeeded(p[1]) == false, "…and drops out once the slot is bare")
    local p2 = w2.Addon:PlanSet(w2.Addon:GetSet("planned"), w2.Addon:BuildCensus())
    ck(#p2 == 0, "an already-empty slot plans no operations")
    w2:teardown()

    -- no bag space: the spec's not-enough-room abort, slot untouched
    local w3 = mock.new(P)
    w3:setWorn(13, L(2001))
    w3:fillBags(0)
    w3:defineSet("noroom", { [13] = mock.EMPTY })
    w3.Addon:EquipSet("noroom")
    ck(w3.worn[13] == L(2001), "with no bag space the slot keeps its item")
    ck(w3:output():find("bag space") ~= nil, "the not-enough-room abort is reported")
    w3:teardown()

    -- mixed set: the sentinel slot empties while the rest still equips
    local w4 = mock.new(P)
    w4:setWorn(13, L(2001))
    w4:setWorn(1,  L(3002))
    w4:setBag(0, 1, L(3001))
    w4:defineSet("mixed", { [1] = L(3001), [13] = mock.EMPTY })
    w4.Addon:EquipSet("mixed")
    ck(w4.worn[1] == L(3001), "the ordinary slot equipped")
    ck(w4.worn[13] == nil, "the sentinel slot emptied in the same pass")
    w4:teardown()

    -- a disabled slot is not governed even when it carries a sentinel
    local w5 = mock.new(P)
    w5:setWorn(13, L(2001))
    w5:defineSet("off", { [13] = mock.EMPTY }, { [13] = true })
    w5.Addon:EquipSet("off")
    ck(w5.worn[13] == L(2001), "an ignored slot is never stripped")
    w5:teardown()

    -- in combat the strip queues like any other change, and drains on regen
    local w6 = mock.new(P)
    w6:setWorn(13, L(2001))
    w6:defineSet("cqEmpty", { [13] = mock.EMPTY })
    w6.combat = true
    w6.Addon:EquipSet("cqEmpty")
    ck(w6.worn[13] == L(2001), "nothing is stripped while in combat")
    w6.combat = false
    w6:fireEvent("PLAYER_REGEN_ENABLED")
    w6:pumpTimers()
    ck(w6.worn[13] == nil, "the strip happened when combat ended")
    w6:teardown()

    -- single-slot public equip honours the sentinel too
    local w7 = mock.new(P)
    w7:setWorn(13, L(2001))
    w7.Addon:EquipSlot(13, w7.Addon:EmptyEntry())
    ck(w7.worn[13] == nil, "EquipSlot with a sentinel takes the item off")
    w7:teardown()
end))

-- §2.8 / §6.1 in-combat weapon swaps: the secure macro text and the queue split.
suite("equip-combat-weapon-split", world(function(ck, w, A)
    ck(A:IsSecureCombatSlot(16) and A:IsSecureCombatSlot(17) and A:IsSecureCombatSlot(18),
       "slots 16/17/18 are the secure in-combat slots")
    ck(A:IsSecureCombatSlot(13) == false, "trinkets are NOT secure in-combat slots")

    w:setBag(0, 1, L(4002))   -- Test Sword
    w:setBag(0, 2, L(4003))   -- Test Shield
    w:setBag(0, 3, L(4004))   -- Test Bow
    w:setBag(0, 4, L(3001))   -- Test Helm
    w:defineSet("war", { [16] = L(4002), [17] = L(4003), [18] = L(4004), [1] = L(3001) })

    local lines = A:WeaponMacroLines("war")
    ck(#lines == 3, "one /equipslot line per governed weapon slot (got " .. #lines .. ")")
    ck(lines[1] == "/equipslot [combat]16 Test Sword",  "main hand line")
    ck(lines[2] == "/equipslot [combat]17 Test Shield", "off hand line")
    ck(lines[3] == "/equipslot [combat]18 Test Bow",    "ranged line")
    ck(A:SetHasCombatWeapons("war") == true, "the set is flagged as swappable in combat")

    local macro = A:BuildSetMacroText("war")
    ck(macro:find('\n/run ArmEquipSecure%("war"%)$') ~= nil,
       "the macro ends with the flagged equip call")
    ck(macro:find("/equipslot %[combat%]16") == 1, "the weapon lines come first")

    -- a set governing no weapon slot is just the equip call
    w:defineSet("cloth", { [1] = L(3001) })
    ck(#A:WeaponMacroLines("cloth") == 0, "no weapon slots, no /equipslot lines")
    ck(A:BuildSetMacroText("cloth") == '/run ArmEquipSecure("cloth")', "…just the equip call")
    ck(A:SetHasCombatWeapons("cloth") == false, "…and it is not flagged")

    -- an explicitly-empty weapon slot gets no line: there is no secure unequip
    w:defineSet("noOff", { [16] = L(4002), [17] = mock.EMPTY })
    local l2 = A:WeaponMacroLines("noOff")
    ck(#l2 == 1 and l2[1]:find("%[combat%]16") ~= nil, "an explicit-empty weapon slot is skipped")

    -- an ignored weapon slot gets no line either
    w:defineSet("noMain", { [16] = L(4002) }, { [16] = true })
    ck(#A:WeaponMacroLines("noMain") == 0, "an ignored weapon slot emits no line")

    -- quotes in a set name cannot break out of the /run line
    w:defineSet('say "hi"', { [1] = L(3001) })
    ck(A:BuildSetMacroText('say "hi"') == '/run ArmEquipSecure("say \\"hi\\"")',
       "quotes in a set name are escaped")

    -- THE SPLIT: with the secure path in play the weapon slots are not pending
    w.combat = true
    A:EquipSet("war", { secureWeapons = true })
    ck(A._pendingSet == "war", "the rest of the set is still queued for the end of combat")
    ck(A._pendingSkip ~= nil, "a skip list was recorded")
    ck(A._pendingSkip and A._pendingSkip[16] and A._pendingSkip[17] and A._pendingSkip[18],
       "all three weapon slots are excluded from the pending overlay")
    ck(A._pendingSkip and A._pendingSkip[1] == nil, "ordinary slots are still pending")
    ck(w.worn[16] == nil, "the engine itself never moves a weapon during combat")

    -- the ordinary (unbound) path claims nothing
    A:EquipSet("war")
    ck(A._pendingSkip == nil, "an ordinary in-combat equip claims no secure weapon handling")

    w.combat = false
    w:fireEvent("PLAYER_REGEN_ENABLED")
    w:pumpTimers()
    ck(w.worn[16] == L(4002) and w.worn[17] == L(4003) and w.worn[18] == L(4004),
       "the drain completes every weapon slot out of combat")
    ck(w.worn[1] == L(3001), "…and the ordinary slots too")
    ck(A._pendingSkip == nil, "the skip list is consumed with the queue")

    -- the global the secure macro calls really goes through the flagged path
    local w2 = mock.new(P)
    w2:setBag(0, 1, L(4002))
    w2:defineSet("secure", { [16] = L(4002) })
    w2.combat = true
    _G.ArmEquipSecure("secure")
    ck(w2.Addon._pendingSkip ~= nil and w2.Addon._pendingSkip[16] == true,
       "ArmEquipSecure() marks the weapon slots as secure-handled")
    w2:teardown()
end))

-- SavedVariables additivity: a set written by the released build must load, plan
-- and equip exactly as it did before the sentinel existed.
suite("sv-additive-legacy-sets", world(function(ck, w, A)
    A.db.sets["legacy"] = {
        name = "legacy", icon = "Interface\\Icons\\INV_Misc_Bag_08", order = 1,
        equip = {
            [1]  = { id = 3001, str = "3001:0:0:0:0:0:0:0:60:0", exact = "3001:0:0" },
            [11] = { id = 1001, str = "1001:0:0:0:0:0:0:0:60:0", exact = "1001:0:0" },
        },
        disabled = { [4] = true, [19] = true },
    }
    for slotId, e in pairs(A.db.sets.legacy.equip) do
        ck(A:IsEmptyEntry(e) == false, "legacy entry in slot " .. slotId .. " is not read as a sentinel")
    end

    w:setBag(0, 1, L(3001))
    w:setBag(0, 2, L(1001))
    A:EquipSet("legacy")
    ck(w.worn[1] == L(3001) and w.worn[11] == L(1001), "a legacy set equips exactly as before")
    ck(A:IsSetEquipped("legacy") == true, "…and reads as equipped afterwards")

    local n = 0
    for _ in pairs(A.db.sets.legacy) do n = n + 1 end
    ck(n == 5, "equipping a legacy set adds no keys to it (name/icon/order/equip/disabled)")
    for _, e in pairs(A.db.sets.legacy.equip) do
        local fields = 0
        for _ in pairs(e) do fields = fields + 1 end
        ck(fields == 3, "a legacy entry still carries exactly id/str/exact")
    end

    -- export/import round trip: the legacy record survives byte-identically, and a
    -- sentinel rides in the existing id field with no format change
    local w2 = mock.new(P)
    local B = w2.Addon
    B.db.sets["round"] = {
        name = "round", icon = "icon", order = 1,
        equip = { [1] = { id = 3001, str = "3001:0:0:0:0:0:0:0:60:0", exact = "3001:0:0" },
                  [13] = B:EmptyEntry() },
        disabled = { [4] = true },
    }
    local str = B:ExportSets()
    ck(str:find("^DaseekiArmory:v3") ~= nil, "the export version is unchanged")
    ck(str:find("S;13;0;;") ~= nil, "the sentinel exports as id 0 in the existing field")
    B.db.sets = {}
    local ok, count = B:ImportSets(str)
    ck(ok and count == 1, "the string imports")
    local back = B.db.sets["round"]
    ck(back ~= nil, "the set came back under its own name")
    ck(back and back.equip[1].id == 3001 and back.equip[1].exact == "3001:0:0",
       "the ordinary entry round-trips unchanged")
    ck(back and B:IsEmptyEntry(back.equip[13]) == true, "the sentinel round-trips as explicit-empty")
    ck(back and back.disabled[4] == true, "ignored slots round-trip")
    w2:teardown()

    -- save-over keeps a deliberate empty marker but never invents one
    local w3 = mock.new(P)
    local C = w3.Addon
    w3:setWorn(1, L(3001))
    C.db.sets["keep"] = { name = "keep", equip = { [13] = C:EmptyEntry() }, disabled = {} }
    C:SaveCurrentGear("keep")
    ck(C:IsEmptyEntry(C.db.sets.keep.equip[13]) == true, "an explicit-empty marker survives save-over")
    ck(C.db.sets.keep.equip[1] ~= nil, "worn gear was captured")
    ck(C.db.sets.keep.equip[14] == nil, "a merely-bare slot is NOT turned into a marker")
    w3:teardown()
end))

-- TRINKETMENU §4.2 cooldown readout text. Pure formatter: trinkets.lua is loaded
-- with no WoW API at all, which is the property this suite asserts first.
suite("trinket-cooldown-text", function(ck)
    local T = { db = { settings = { trinkets = { showCooldowns = true, largeNumbers = true } } } }
    function T:TrySetNumeral() end
    function T:Col() return 1, 1, 1, 1 end

    local fn, err = loadfile(P("trinkets.lua"))
    ck(fn ~= nil, "trinkets.lua compiles" .. (fn and "" or (" -> " .. tostring(err))))
    if not fn then return end
    local ok, rerr = pcall(fn, "Daseeki-Armory", T)
    ck(ok, "trinkets.lua loads with no WoW API present" .. (ok and "" or (" -> " .. tostring(rerr))))
    ck(type(T.CooldownText) == "function", "the formatter is published as Addon:CooldownText")
    if type(T.CooldownText) ~= "function" then return end

    local function F(start, dur, now, prev) return T:CooldownText(start, dur, now, prev) end

    ck(F(0, 60, 100, "") == "", "start = 0 (not on cooldown) is blank")
    ck(F(nil, nil, 100, "") == "", "nil start/duration is blank")
    ck(F(100, 0, 100, "") == "", "a zero duration is blank")
    ck(F(100, 30, 140, "") == "", "an elapsed cooldown is blank")

    ck(F(100, 45, 100, "") == "45 s", "under a minute reads in seconds")
    ck(F(100, 45, 102, "") == "43 s", "…counted down from GetTime()")
    ck(F(100, 10.4, 100, "") == "10 s", "seconds round to nearest: 10.4 -> 10")
    ck(F(100, 10.6, 100, "") == "11 s", "seconds round to nearest: 10.6 -> 11")
    ck(F(100, 59.9, 100, "") == "60 s", "59.9 s still reads in seconds, rounded to 60")

    -- the order-dependent global-cooldown rule (spec §4.2 / §7.9)
    ck(F(100, 2, 100, "") == "", "a countdown that would START under 3 s is suppressed")
    ck(F(100, 2, 100, nil) == "", "…a nil field counts as blank")
    ck(F(100, 2, 100, "5 s") == "2 s", "…but one already ticking keeps rendering through 3, 2, 1")
    ck(F(100, 3, 100, "") == "3 s", "exactly 3 s is not suppressed")

    ck(F(100, 60, 100, "") == "1 m", "60 s reads as 1 m")
    ck(F(100, 61, 100, "") == "2 m", "minutes round UP: 61 s -> 2 m")
    ck(F(100, 120, 100, "") == "2 m", "120 s -> 2 m")
    ck(F(100, 3599, 100, "") == "60 m", "just under an hour still reads in minutes")
    ck(F(100, 3600, 100, "") == "1 h", "an hour reads in hours")
    ck(F(100, 3601, 100, "") == "2 h", "hours round UP")
    ck(F(100, 7200, 100, "") == "2 h", "two hours")
end)

-- Quality GLOW geometry (borders.lua), pinned to 1.x SOURCE via Daseeki-Bags 2.0's
-- transcription, NOT to CII_BEHAVIOR_SPEC §2. These constants ARE the look, and they are
-- a SIBLING CONTRACT: Daseeki-Bags2-beta's borders.lua "SUITE GLOW GEOMETRY" block
-- (branch v2) is the AUTHORITY — it transcribed Daseeki-Bags 1.x (main) line by line, and
-- its own harness (borders.lua testGlowGeometry + parity.lua rows 6-9) gates the identical
-- numbers. Every citation below is that block's citation. Any edit here must be mirrored
-- there. Like trinkets.lua, borders.lua's pure layer is loaded with no WoW API at all,
-- which is the property this suite asserts first.
suite("border-glow-geometry", function(ck)
    local B = { SLOTS = {} }

    local fn, err = loadfile(P("borders.lua"))
    ck(fn ~= nil, "borders.lua compiles" .. (fn and "" or (" -> " .. tostring(err))))
    if not fn then return end
    local ok, rerr = pcall(fn, "Daseeki-Armory", B)
    ck(ok, "borders.lua loads with no WoW API present" .. (ok and "" or (" -> " .. tostring(rerr))))
    local M = B.Borders
    ck(type(M) == "table", "the pure layer is published as Addon.Borders")
    if type(M) ~= "table" then return end

    -- 1.x anatomy, constant by constant. Identical to Bags 2.0 Borders.GLOW_*; each
    -- citation is the one carried by the Bags "SUITE GLOW GEOMETRY" constant block, whose
    -- alpha row is now the OWNER'S PROFILE value rather than 1.x's shipped default.
    ck(M.GLOW_TEXTURE == "Interface\\Buttons\\UI-ActionButton-Border",
       "1.x item.lua:55 glow texture")
    ck(M.GLOW_REF_BUTTON == 37, "1.x reference button is the template's own 37px")
    ck(near(M.GLOW_SCALE, 67 / 37), "1.x item.lua:58 SetSize(67,67) on a 37px button")
    ck(near(M.GLOW_SCALE_AMMO, 58 / 37), "CII §2 Ammo exception retained: a 58px halo")
    ck(M.GLOW_ALPHA == 0.77,
       "owner profile glowAlpha 0.77 (WTF account #1), uniform on every tint")
    ck(M.GLOW_OFFSET_Y_SCALE == 0, "1.x item.lua:57 SetPoint('CENTER') — no offset")
    ck(M.GLOW_LAYER == "OVERLAY", "1.x item.lua:54 OVERLAY layer")
    ck(M.GLOW_SUBLEVEL == -1, "1.x item.lua:54 sublevel -1 (below the button's own overlay art)")
    ck(M.GLOW_SCALE > 1, "the halo overhangs the button — a wash, not a rim")
    ck(M.GLOW_SCALE_AMMO > 1, "even the Ammo halo overhangs")
    ck(M.GLOW_SCALE_AMMO < M.GLOW_SCALE, "the Ammo halo is the smaller exception")

    -- REGRESSION LOCK on the previous round: these are the four spec §2 values 1.x
    -- overrides. If any of them comes back, the character window has drifted off the
    -- suite standard again — the exact drift the Bags parity pass was run to end.
    ck(not near(M.GLOW_SCALE, 68 / 37), "NOT the spec's 68/37")
    ck(M.GLOW_ALPHA ~= 0.49, "NOT the spec's 0.49")
    -- ...and the release-blocking lock the Bags round added: 1.x's UNTOUCHED slider default
    -- is not the owner's look. glowAlpha is the one glow parameter 1.x exposes as a slider
    -- and his live value is 0.77 (WTF account #1, his main; #2/#3 read 0.87). At 0.5 the
    -- additive wash is too faint to be the primary cue and the cell reads as a hard edge.
    ck(M.GLOW_ALPHA ~= 0.5, "NOT 1.x's untouched default 0.5 (superseded by the profile)")
    ck(M.GLOW_ALPHA > 0.5, "the wash is the PRIMARY cue, stronger than the 1.x default")
    ck(M.GLOW_ALPHA < 1, "...and still a wash, not an opaque fill")
    ck(not near(M.GLOW_OFFSET_Y_SCALE, 1 / 37), "NOT the spec's (0,1) nudge")
    ck(M.GLOW_SUBLEVEL ~= nil, "NOT the spec's plain-OVERLAY (no sublevel)")

    -- At 1.x's own button size the ratios reproduce its literal pixel values.
    ck(near(M.GlowSize(37), 67), "a 37px paper-doll slot gets 1.x's literal 67px halo")
    ck(near(M.GlowSize(37, true), 58), "…and an Ammo slot gets literally 58")
    ck(near(M.GlowOffsetY(37), 0), "…and the offset is literally 0")

    -- Sizing is read off the host button, so both button sizes in play get the same
    -- proportional wash: the paper-doll slot (37) and the flyout lead (32).
    ck(near(M.GlowSize(32), 32 * 67 / 37), "a 32px flyout lead gets a proportional halo")
    ck(M.GlowOffsetY(32) == 0, "…and the zero offset stays zero at the flyout size too")
    ck(M.GlowSize(48) > M.GlowSize(37), "a bigger button gets a bigger halo")
    ck(near(M.GlowSize(74), 134), "a doubled button doubles the halo (proportion held)")
    ck(M.GlowSize(0) == 0, "degenerate button -> no halo")
    ck(M.GlowSize(-5) == 0, "negative button -> no halo")
    ck(M.GlowSize(nil) == 0, "nil button -> no halo")
    ck(M.GlowOffsetY(0) == 0 and M.GlowOffsetY(nil) == 0, "degenerate button -> no offset")

    -- ── LAYERING: the halo must stay UNDER Armory's own per-slot overlay art ─────
    -- The container now sits at the HOST BUTTON'S OWN frame level (not +1), so the halo
    -- is ordered against the button's other art by DRAW LAYER alone — which is the whole
    -- point of the sublevel. Armory draws two things on the same paper-doll button:
    --   trinkets.lua   host:CreateFontString(nil, "OVERLAY", …)      -> sublevel 0
    --   paperdoll.lua  btn:CreateTexture(nil, "OVERLAY", nil, 6/7)   -> sublevels 6, 7
    -- All three outrank OVERLAY(-1), so the cooldown readout and the combat-pending
    -- overlay pair render ABOVE the halo. Scanned from source so the assertion cannot
    -- rot if those literals are edited (the io.open precedent is equip-slot-model).
    local function grepAll(rel, pat)
        local fh = io.open(P(rel), "r")
        if not fh then return nil end
        local out = {}
        for line in fh:lines() do
            local s = line:match(pat)
            if s then out[#out + 1] = s end
        end
        fh:close()
        return out
    end

    -- paperdoll.lua: the combat-pending overlay pair, created ON the character slot button.
    local pd = grepAll("paperdoll.lua", 'btn:CreateTexture%(nil, "OVERLAY", nil, (%d+)%)')
    ck(pd ~= nil, "paperdoll.lua is readable")
    ck(pd and #pd == 2, "paperdoll.lua draws exactly the 2 combat-pending overlay textures")
    local pdAbove = (pd ~= nil and #pd > 0)
    for _, s in ipairs(pd or {}) do
        if tonumber(s) <= M.GLOW_SUBLEVEL then pdAbove = false end
    end
    ck(pdAbove, "every combat-pending overlay sublevel outranks the halo's -1")

    -- trinkets.lua: the cooldown readouts, created ON the host button at plain OVERLAY.
    -- A plain OVERLAY FontString is sublevel 0, so a negative halo sublevel sorts under it.
    local tr = grepAll("trinkets.lua", '(CreateFontString%(nil, "OVERLAY")')
    ck(tr ~= nil and #tr >= 2, "trinkets.lua creates the cooldown readouts on plain OVERLAY")
    ck(grepAll("trinkets.lua", 'CreateFontString%(nil, "OVERLAY", nil, (%-?%d+)') ~= nil
       and #grepAll("trinkets.lua", 'CreateFontString%(nil, "OVERLAY", nil, (%-?%d+)') == 0,
       "…none of them carries an explicit sublevel, so all sit at 0")
    ck(M.GLOW_SUBLEVEL < 0, "…and the halo's sublevel is negative, so OVERLAY(0) text wins")

    -- The container level itself: borders.lua must NOT re-introduce the +1 offset.
    local bsrc = io.open(P("borders.lua"), "r")
    ck(bsrc ~= nil, "borders.lua is readable")
    local body = bsrc and bsrc:read("*a") or ""
    if bsrc then bsrc:close() end
    ck(body:find("f:SetFrameLevel(parent:GetFrameLevel() or 1)", 1, true) ~= nil,
       "the glow container sits at the host button's OWN frame level")
    ck(body:find("GetFrameLevel() or 1) + 1", 1, true) == nil,
       "…and the level+1 container (which put the halo over everything) is gone")
    ck(body:find("Borders.GLOW_LAYER, nil, Borders.GLOW_SUBLEVEL", 1, true) ~= nil,
       "the halo texture is created with the layer+sublevel constants, not a plain OVERLAY")

    -- ── Spec §3: two floors, chosen by how the quality was resolved ──────────────
    -- This is the asymmetry the character window was getting wrong. EQUIPPED slots read
    -- GetInventoryItemQuality and border at EVERY quality (poor and common included);
    -- the flyout reads an item link through GetItemInfo and borders above Common only.
    ck(M.EQUIPPED_MIN_QUALITY == 0, "the equipped floor admits every quality (spec §3)")
    ck(M.BAG_MIN_QUALITY == 2, "the item-link floor is above Common (spec §3)")
    ck(M.MIN_QUALITY == 2, "the back-compat alias still names the link-path floor")

    local EQ = M.EQUIPPED_MIN_QUALITY
    ck(M.ShouldShow(nil, true, EQ) == false, "equipped: an EMPTY slot (nil) -> no glow")
    ck(M.ShouldShow(0, true, EQ) == true, "equipped: POOR glows (spec §3)")
    ck(M.ShouldShow(1, true, EQ) == true, "equipped: COMMON glows (spec §3)")
    ck(M.ShouldShow(2, true, EQ) == true, "equipped: uncommon glows")
    ck(M.ShouldShow(5, true, EQ) == true, "equipped: legendary glows")
    ck(M.ShouldShow(0, false, EQ) == false, "equipped: our toggle still silences poor")
    ck(M.ShouldShow(4, false, EQ) == false, "equipped: our toggle still silences epic")

    ck(M.ShouldShow(nil, true) == false, "flyout: nil quality -> no glow")
    ck(M.ShouldShow(0, true) == false, "flyout: poor -> no glow")
    ck(M.ShouldShow(1, true) == false, "flyout: common -> no glow")
    ck(M.ShouldShow(2, true) == true, "flyout: uncommon -> glow")
    ck(M.ShouldShow(3, true) == true, "flyout: rare -> glow")
    ck(M.ShouldShow(5, true) == true, "flyout: legendary -> glow")
    ck(M.ShouldShow(4, false) == false, "flyout: toggle off -> no glow even for epic")

    -- Spec §3 colors: Poor is the reference's near-black table mutation, NOT Blizzard's
    -- 0.62 grey, and it wins over the live game APIs the way that mutation does.
    -- Common stays white. Both are only ever SEEN on the equipped surface.
    ck(M.POOR_RGB[1] == 0.1 and M.POOR_RGB[2] == 0.1 and M.POOR_RGB[3] == 0.1,
       "spec §3 Poor is near-black 0.1/0.1/0.1")
    local pr, pg, pb = M.QualityRGB(0)
    ck(pr == 0.1 and pg == 0.1 and pb == 0.1, "…and QualityRGB(0) returns it")
    ck(M._fallback[0][1] == 0.1, "the static table agrees with the override")
    local cr, cg, cb = M.QualityRGB(1)
    ck(cr == 1 and cg == 1 and cb == 1, "spec §3 Common is white")

    -- Full-saturation colors: headless the static table is the last resort in the
    -- C_Item -> ITEM_QUALITY_COLORS -> static chain, and it stays rarity-distinct.
    ck(M.QualityRGB(nil) == nil, "nil quality -> no color")
    local r3, g3, b3 = M.QualityRGB(3)
    ck(b3 > r3 and b3 > g3, "rare reads blue-dominant")
    local r5, g5, b5 = M.QualityRGB(5)
    ck(r5 > g5 and g5 > b5, "legendary reads orange (R>G>B)")
    local r4, g4, b4 = M.QualityRGB(4)
    ck(b4 > g4 and r4 > g4, "epic reads purple (B>G, R>G)")
    ck(r4 > r3 + 0.15, "epic is separable from rare by the red channel")

    -- The live chain is preferred over the static table when the game APIs exist.
    _G.C_Item = { GetItemQualityColor = function() return 0.10, 0.20, 0.30 end }
    local lr, lg, lb = M.QualityRGB(3)
    ck(lr == 0.10 and lg == 0.20 and lb == 0.30, "C_Item.GetItemQualityColor wins when present")
    -- …except for Poor, where the spec's table mutation outranks the game's own value.
    ck(select(1, M.QualityRGB(0)) == 0.1, "Poor's spec override beats even C_Item")
    _G.C_Item = nil
    _G.ITEM_QUALITY_COLORS = { [3] = { r = 0.4, g = 0.5, b = 0.6 } }
    local fr, fg, fb = M.QualityRGB(3)
    ck(fr == 0.4 and fg == 0.5 and fb == 0.6, "ITEM_QUALITY_COLORS is the second link in the chain")
    _G.ITEM_QUALITY_COLORS = nil
    ck(near(select(1, M.QualityRGB(3)), r3), "…and the static table is the last resort")
end)

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
        -- explicit-empty slots + the secure in-combat weapon path
        "IsEmptyEntry", "EmptyEntry", "SetSlotEmpty", "ToggleSlotEmpty",
        "IsSlotEmptySentinel", "IsSecureCombatSlot", "WeaponMacroLines",
        "BuildSetMacroText", "SetHasCombatWeapons",
    }) do
        ck(type(A[name]) == "function", "Addon:" .. name .. " is present")
    end
    ck(type(A.SLOT_INVTYPES) == "table", "Addon.SLOT_INVTYPES is present")
    ck(type(A.SECURE_COMBAT_SLOTS) == "table", "Addon.SECURE_COMBAT_SLOTS is present")
    ck(#A.SECURE_COMBAT_SLOTS == 3, "exactly three slots may swap in combat")
    ck(type(A.UNEQUIP_ICON) == "string", "Addon.UNEQUIP_ICON is published for the overlays")

    ck(type(_G.ArmEquip) == "function", "global ArmEquip is exported for macros")
    ck(type(_G.ArmToggle) == "function", "global ArmToggle is exported for macros")
    ck(type(_G.ArmEquipSecure) == "function", "global ArmEquipSecure is exported for the secure macro")
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
-- Set-builder goal "obtained" check (the green tick on a slot)
--
-- The predicate behind options.lua's b.check:SetShown() is
-- (GetGoal ~= nil) and IsGoalMet. Owner report: the tick never appeared once a
-- goal was achieved, because "achieved" only ever meant "the item is loose in a
-- bag right now" — gear that went straight onto the character was invisible.
----------------------------------------------------------------------
local function goalShown(A, set, slotId)
    -- the exact composition options.lua's RefreshBuilder feeds to b.check
    local goal = A:GetGoal(set, slotId)
    local met  = A:IsGoalMet(set, slotId)
    return (goal ~= nil and met) and true or false
end

suite("goal-obtained-check", world(function(ck, w, A)
    local HEAD, HANDS = 1, 10

    -- ── not achieved: item is nowhere ────────────────────────────────────────
    local set = w:defineSet("chase", { [HEAD] = L(3002) })
    A:SetGoal("chase", HEAD, 3001)
    ck(A:GetGoal(set, HEAD) ~= nil, "goal is recorded on the slot")
    ck(A:IsGoalMet(set, HEAD) == false, "goal not met while the item is nowhere")
    ck(goalShown(A, set, HEAD) == false, "check HIDDEN when the goal is unmet")

    -- ── achieved via the character: the regression case ──────────────────────
    w:setWorn(HEAD, L(3001))
    ck(A:IsGoalWorn(HEAD, A:GetGoal(set, HEAD)) == true, "goal item detected as worn")
    ck(A:IsGoalMet(set, HEAD) == true, "goal met from WORN gear, with empty bags")
    ck(goalShown(A, set, HEAD) == true, "check SHOWN when the goal item is worn")

    -- CheckGoals adopts the worn item into the set and makes the flag sticky
    ck(A:CheckGoals() == true, "CheckGoals reports a change for the worn hit")
    ck(set.equip[HEAD].id == 3001, "worn goal item is adopted into the set slot")
    ck(set.goalMet[HEAD] == true, "worn hit sets the sticky obtained flag")
    w:setWorn(HEAD, nil)
    ck(A:IsGoalMet(set, HEAD) == true, "stays met after the item comes back off")
    ck(A:CheckGoals() == false, "CheckGoals is idempotent once the goal is met")

    -- ── worn in a DIFFERENT slot is not this slot's goal ─────────────────────
    local set2 = w:defineSet("chase2", { [HANDS] = L(1001) })
    A:SetGoal("chase2", HANDS, 3001)
    w:setWorn(HEAD, L(3001))          -- right item, wrong slot
    ck(A:IsGoalMet(set2, HANDS) == false, "worn in another slot does not meet the goal")
    ck(goalShown(A, set2, HANDS) == false, "check HIDDEN for a wrong-slot match")
    w:setWorn(HEAD, nil)

    -- ── achieved via bags still works (the original path) ────────────────────
    w:setBag(0, 1, L(3001))
    ck(A:CheckGoals() == true, "bag hit still marks the goal obtained")
    ck(set2.equip[HANDS] ~= nil and set2.equip[HANDS].id == 3001, "bag item adopted into the slot")
    ck(goalShown(A, set2, HANDS) == true, "check SHOWN after a bag hit")
    w:setBag(0, 1, nil)

    -- ── no goal on the slot: never a check, whatever is worn ─────────────────
    local set3 = w:defineSet("plain", { [HEAD] = L(3001) })
    w:setWorn(HEAD, L(3001))
    ck(A:GetGoal(set3, HEAD) == nil, "slot has no goal")
    ck(A:IsGoalMet(set3, HEAD) == false, "no goal means never met")
    ck(goalShown(A, set3, HEAD) == false, "check HIDDEN on a slot with no goal")
    w:setWorn(HEAD, nil)

    -- ── CheckGoals survives a goal-bearing set with no equip table ───────────
    -- Previously this indexed nil and aborted the scan for EVERY set.
    A.db.sets["broken"] = { name = "broken", goals = { [HEAD] = { id = 3001 } } }
    local set4 = w:defineSet("after", { [HEAD] = L(3002) })
    A:SetGoal("after", HEAD, 3001)
    w:setWorn(HEAD, L(3001))
    local okScan, scanErr = pcall(function() return A:CheckGoals() end)
    ck(okScan == true, "CheckGoals does not raise on a set with goals but no equip: "
                       .. tostring(scanErr))
    ck(set4.goalMet ~= nil and set4.goalMet[HEAD] == true,
       "later sets are still scanned after the malformed one")
    A.db.sets["broken"] = nil
    w:setWorn(HEAD, nil)

    -- ── a zero/absent goal id can never be "worn" ────────────────────────────
    ck(A:IsGoalWorn(HEAD, { id = 0 }) == false, "id 0 is never a worn match")
    ck(A:IsGoalWorn(HEAD, nil) == false, "nil goal is never a worn match")

    -- the equipment event must be watched, or the worn path never fires live
    local watched = {}
    for _, e in ipairs(A.GOAL_EVENTS or {}) do watched[e] = true end
    ck(watched["BAG_UPDATE_DELAYED"] == true, "goals watch BAG_UPDATE_DELAYED")
    ck(watched["PLAYER_EQUIPMENT_CHANGED"] == true, "goals watch PLAYER_EQUIPMENT_CHANGED")
end))

----------------------------------------------------------------------
-- Set-builder preview model: the dressing plan
--
-- Owner report: the preview showed live gear, and only one weapon (the
-- off-hand) rendered, in the main hand. BuildDressPlan is the ordered TryOn
-- list; the ordering and the handSlotName hints are the contract.
----------------------------------------------------------------------
suite("set-preview-dressing", function(ck)
    local w = mock.new(P)
    local A = w.Addon
    local MH, OH, RANGED = 16, 17, 18

    local function ids(plan)
        local t = {}
        for i, s in ipairs(plan) do t[i] = s.slotId end
        return t
    end
    local function join(t) return table.concat(t, ",") end

    ck(join(ids(A:BuildDressPlan(nil))) == "", "no set yields an empty plan")
    ck(join(ids(A:BuildDressPlan({}))) == "", "set with no equip yields an empty plan")

    -- ── 1H + shield: weapons last, main hand first, both hinted ──────────────
    local s1 = w:defineSet("mh-oh", { [1] = L(3001), [MH] = L(4002), [OH] = L(4003) })
    local p1 = A:BuildDressPlan(s1)
    ck(join(ids(p1)) == "1,16,17", "1H+shield: head, then main hand, then off hand")
    ck(p1[2].hand == "MAINHANDSLOT", "main hand carries MAINHANDSLOT")
    ck(p1[3].hand == "SECONDARYHANDSLOT", "off hand carries SECONDARYHANDSLOT")
    ck(p1[1].hand == nil, "non-weapon steps carry no hand hint")

    -- ordering must hold no matter which order the set table happens to iterate
    for _ = 1, 5 do
        local p = A:BuildDressPlan(s1)
        ck(join(ids(p)) == "1,16,17", "plan order is deterministic across rebuilds")
    end

    -- ── dual wield: still MH then OH, never both into the main hand ──────────
    local s2 = w:defineSet("dw", { [MH] = L(4002), [OH] = L(4002) })
    local p2 = A:BuildDressPlan(s2)
    ck(join(ids(p2)) == "16,17", "dual wield: main hand precedes off hand")
    ck(p2[1].hand == "MAINHANDSLOT" and p2[2].hand == "SECONDARYHANDSLOT",
       "dual wield hints both hands explicitly")

    -- ── 2H alone: one weapon step, main hand ─────────────────────────────────
    local s3 = w:defineSet("2h", { [MH] = L(4001) })
    local p3 = A:BuildDressPlan(s3)
    ck(join(ids(p3)) == "16", "2H alone: a single main-hand step")
    ck(p3[1].hand == "MAINHANDSLOT", "2H is hinted to the main hand")

    -- ── ranged is never previewed ────────────────────────────────────────────
    local s4 = w:defineSet("bow", { [MH] = L(4002), [RANGED] = L(4004) })
    local p4 = A:BuildDressPlan(s4)
    ck(join(ids(p4)) == "16", "ranged slot 18 is excluded from the preview")

    -- ── explicit-empty and disabled slots dress nothing ──────────────────────
    local s5 = w:defineSet("holes", { [1] = mock.EMPTY, [3] = L(3001), [5] = L(3002) },
                           { [5] = true })
    local p5 = A:BuildDressPlan(s5)
    ck(join(ids(p5)) == "3", "explicit-empty and disabled slots are not dressed")

    -- ── non-weapon steps follow core.lua's Addon.SLOTS order ─────────────────
    local s6 = w:defineSet("many", { [9] = L(3001), [1] = L(3001), [5] = L(3001) })
    ck(join(ids(A:BuildDressPlan(s6))) == "1,5,9", "non-weapon steps follow SLOT_IDS order")

    -- every step must carry a usable link
    local allLinks = true
    for _, s in ipairs(p1) do if type(s.link) ~= "string" then allLinks = false end end
    ck(allLinks, "every plan step carries an item link string")

    w:teardown()
end)

----------------------------------------------------------------------
-- Source contract for the two surfaces above (the io.open scan gate)
----------------------------------------------------------------------
suite("set-builder-source-contract", function(ck)
    local function slurp(f)
        local h = io.open(P(f), "r")
        if not h then return nil end
        local s = h:read("*a"); h:close(); return s
    end

    local opt = slurp("options.lua")
    ck(opt ~= nil, "options.lua is readable")
    if not opt then return end

    -- the goal check itself: texture, corner, layer, and the shown predicate
    ck(opt:find('b%.check:SetTexture%("Interface\\\\RaidFrame\\\\ReadyCheck%-Ready"%)') ~= nil,
       "goal check uses the green ReadyCheck-Ready texture")
    ck(opt:find('b%.check = b:CreateTexture%(nil, "OVERLAY", nil, BADGE_SUBLEVEL%)') ~= nil,
       "goal check is created at the named badge sublevel")
    ck(opt:find("local BADGE_SUBLEVEL = 7") ~= nil, "badge sublevel is OVERLAY 7")
    ck(opt:find('b%.check:SetPoint%("BOTTOMRIGHT"') ~= nil, "goal check sits bottom-right")
    ck(opt:find("b%.check:SetShown%(%(goal ~= nil and met%)") ~= nil,
       "goal check is shown by (goal ~= nil and met)")

    -- the badge must outrank the suite quality glow
    local bord = slurp("borders.lua")
    ck(bord ~= nil, "borders.lua is readable")
    local glowSub = bord and tonumber(bord:match("GLOW_SUBLEVEL%s*=%s*(%-?%d+)"))
    ck(glowSub ~= nil, "borders.lua declares GLOW_SUBLEVEL")
    ck(glowSub ~= nil and glowSub < 7, "quality glow (" .. tostring(glowSub)
       .. ") sorts below the slot badges (7)")

    -- the preview model: SetUnit binds once at build, never on refresh
    local dress = opt:match("function Addon:DressSetModel%(%).-\nend\n")
    ck(dress ~= nil, "DressSetModel exists")
    ck(dress ~= nil and dress:find(":SetUnit%(") == nil,
       "DressSetModel never calls SetUnit (it would re-dress in live gear)")
    ck(dress ~= nil and dress:find("BuildDressPlan") ~= nil,
       "DressSetModel dresses from BuildDressPlan")
    local refresh = opt:match("function Addon:RefreshSetModel%(%).-\nend\n")
    ck(refresh ~= nil, "RefreshSetModel exists")
    ck(refresh ~= nil and refresh:find(":SetUnit%(") == nil,
       "RefreshSetModel never calls SetUnit")
    ck(opt:find('model:SetUnit%("player"%)') ~= nil,
       "the model is still bound to the player once, at build time")
    ck(opt:find("step%.hand") ~= nil, "the dress pass passes the handSlotName hint")
end)

----------------------------------------------------------------------
-- ITEM SCAN (itemScan.lua) — the pure layer behind the goal picker's
-- rescan, its class/faction filter and its SavedVariables cache.
--
-- Like trinkets.lua and borders.lua, itemScan.lua is loaded with NO WoW API
-- present at all, which is the property the first suite asserts.
----------------------------------------------------------------------
local Scan
do
    local A = {}
    local fn = loadfile(P("itemScan.lua"))
    if fn then
        local ok = pcall(fn, "Daseeki-Armory", A)
        if ok then Scan = A.ItemScan end
    end
end

suite("item-scan-batching", function(ck)
    ck(type(Scan) == "table", "itemScan.lua loads with no WoW API and publishes Addon.ItemScan")
    if type(Scan) ~= "table" then return end

    -- ── the id space ────────────────────────────────────────────────────────
    local R = { { 1, 10 }, { 100, 104 } }
    ck(Scan.RangeTotal(R) == 15, "RangeTotal sums the (inclusive) ranges")
    ck(Scan.RangeTotal({}) == 0, "no ranges -> nothing to walk")
    ck(Scan.RangeTotal(nil) == 0, "nil ranges -> nothing to walk")
    ck(Scan.RangeTotal({ { 5, 4 } }) == 0, "an inverted range contributes nothing")

    ck(Scan.IdAt(R, 1)  == 1,   "index 1 is the first id of the first range")
    ck(Scan.IdAt(R, 10) == 10,  "index 10 is the last id of the first range")
    ck(Scan.IdAt(R, 11) == 100, "index 11 rolls into the second range")
    ck(Scan.IdAt(R, 15) == 104, "index 15 is the final id")
    ck(Scan.IdAt(R, 16) == nil, "past the end is nil")
    ck(Scan.IdAt(R, 0)  == nil, "index 0 is nil (the space is 1-based)")
    ck(Scan.IdAt(R, -3) == nil, "a negative index is nil")
    -- the walk visits every id exactly once, in order
    local seen, ordered, dupes, prev = {}, true, 0, nil
    for i = 1, Scan.RangeTotal(R) do
        local id = Scan.IdAt(R, i)
        if seen[id] then dupes = dupes + 1 end
        seen[id] = true
        if prev and id <= prev and id ~= 100 then ordered = false end
        prev = id
    end
    ck(dupes == 0, "the virtual index visits each id exactly once")
    ck(ordered, "…ascending within a range, stepping cleanly across the range boundary")

    -- ── batch math ──────────────────────────────────────────────────────────
    local from, to, done = Scan.BatchPlan(15, 0, 6)
    ck(from == 1 and to == 6 and done == false, "first batch is [1,6], not finished")
    from, to, done = Scan.BatchPlan(15, 6, 6)
    ck(from == 7 and to == 12 and done == false, "second batch is [7,12]")
    from, to, done = Scan.BatchPlan(15, 12, 6)
    ck(from == 13 and to == 15 and done == true, "last batch clamps to the total and reports done")
    from, to, done = Scan.BatchPlan(15, 15, 6)
    ck(from == nil and to == nil and done == true, "an exhausted cursor yields no slice")
    from, to, done = Scan.BatchPlan(15, 99, 6)
    ck(from == nil and done == true, "a cursor past the end is still 'done', never negative")
    from, to = Scan.BatchPlan(15, 0, 0)
    ck(from == 1 and to == 1, "a zero batch size is floored to 1 (the walk cannot stall)")
    from, to = Scan.BatchPlan(15, -5, 4)
    ck(from == 1 and to == 4, "a negative cursor is clamped to the start")
    from, to = Scan.BatchPlan(3, 0, 1000)
    ck(from == 1 and to == 3, "an oversized batch clamps to the total")
    ck(select(3, Scan.BatchPlan(0, 0, 10)) == true, "an empty space is immediately done")
    -- exhaustive: batching covers the space with no gap and no overlap, any size
    for size = 1, 7 do
        local cursor, covered, guard = 0, 0, 0
        repeat
            local a, b, fin = Scan.BatchPlan(15, cursor, size)
            if a then
                if a ~= cursor + 1 then covered = -1 end
                covered = covered + (b - a + 1)
                cursor = b
            end
            guard = guard + 1
        until fin or guard > 100
        ck(covered == 15, "batch size " .. size .. " covers all 15 indices exactly once")
        ck(guard <= 100, "batch size " .. size .. " terminates")
    end

    -- ── progress / estimate ─────────────────────────────────────────────────
    ck(Scan.Percent(0, 200)   == 0,   "0 of 200 is 0%")
    ck(Scan.Percent(100, 200) == 50,  "100 of 200 is 50%")
    ck(Scan.Percent(200, 200) == 100, "200 of 200 is 100%")
    ck(Scan.Percent(300, 200) == 100, "over-count clamps to 100%")
    ck(Scan.Percent(-5, 200)  == 0,   "under-count clamps to 0%")
    ck(Scan.Percent(5, 0)     == 100, "an empty total reads as complete, never a divide by zero")

    ck(Scan.EstimateSeconds(600, 300) == 2, "600 left at 300/s is 2 s")
    ck(Scan.EstimateSeconds(0, 300)   == 0, "nothing left is 0 s")
    ck(Scan.EstimateSeconds(600, 0)  == nil, "a zero rate has no estimate (not infinity)")
    ck(Scan.EstimateSeconds(600, nil) == nil, "a nil rate has no estimate")

    ck(Scan.FormatDuration(0)    == "0s",     "0 s")
    ck(Scan.FormatDuration(41.4) == "41s",    "seconds round to nearest")
    ck(Scan.FormatDuration(59)   == "59s",    "just under a minute stays in seconds")
    ck(Scan.FormatDuration(60)   == "1m 00s", "a minute switches format")
    ck(Scan.FormatDuration(125)  == "2m 05s", "the seconds field is zero padded")
    ck(Scan.FormatDuration(-1)   == nil,      "a negative duration has no text")
    ck(Scan.FormatDuration(nil)  == nil,      "nil has no text")

    -- ── throttle envelope ───────────────────────────────────────────────────
    -- The server rate-limits item queries; these are the numbers that keep the
    -- scan inside "a few hundred requests/sec" AND keep any single frame cheap.
    ck(Scan.TICK > 0 and Scan.TICK <= 0.1, "the tick is a sub-tenth-second cadence")
    ck(Scan.PeakRequestsPerSecond() == 300, "peak request rate is 300/s")
    ck(Scan.PeakRequestsPerSecond() >= 100, "...fast enough to finish in about a minute")
    ck(Scan.PeakRequestsPerSecond() <= 500, "...and well under a flood")
    ck(Scan.MAX_INFLIGHT > 0, "there is a ceiling on outstanding requests")
    ck(Scan.MAX_INFLIGHT >= Scan.REQUEST_PER_TICK,
       "the in-flight window is wider than one tick's dispatch, or the scan self-stalls")
    ck(Scan.TOOLTIP_BUDGET > 0, "per-tick tooltip work is budgeted")
    ck(Scan.PeakRecordsPerSecond() >= Scan.PeakRequestsPerSecond(),
       "the record budget keeps up with the request rate (the queue cannot back up)")
    ck(Scan.REQUEST_TIMEOUT > 0 and Scan.MAX_TRIES >= 1,
       "a silent request times out and is retried, so the scan can always terminate")
    ck(Scan.InstantIdsPerSecond() >= 10000,
       "the free local walk is fast (no server traffic to pace against)")

    -- ── the id ceiling ──────────────────────────────────────────────────────
    local total = Scan.RangeTotal(Scan.ActiveRanges())
    ck(total >= 24500, "the default ceiling clears vanilla's ~24.3k top item id")
    ck(total <= 60000, "...without walking a pointlessly large space")
    ck(Scan.IdAt(Scan.ActiveRanges(), 1) == 1, "the walk starts at item id 1")
    ck(Scan.RangesLabel({ { 1, 10 }, { 20, 30 } }) == "1-10,20-30", "ranges stringify for the cache stamp")
    ck(#Scan.EXTRA_RANGES == 0, "the high (SoD / non-Era) id blocks are off by default")
    local act = Scan.ActiveRanges()
    act[1][1] = 999
    ck(Scan.RANGES[1][1] == 1, "ActiveRanges hands back a copy, not the live constant")
end)

----------------------------------------------------------------------
-- Tooltip restriction parsing: the ONLY place Era exposes class and faction
-- locks. Pure over already-extracted tooltip lines.
----------------------------------------------------------------------
suite("item-scan-restrictions", function(ck)
    if type(Scan) ~= "table" then ck(false, "itemScan.lua did not load"); return end

    local LOC = {
        classPrefix = "Classes: ",
        racesPrefix = "Races: ",
        classByName = { Warrior = "WARRIOR", Paladin = "PALADIN", Hunter = "HUNTER",
                        Rogue = "ROGUE", Priest = "PRIEST", Shaman = "SHAMAN",
                        Mage = "MAGE", Warlock = "WARLOCK", Druid = "DRUID" },
        raceFaction = { Human = 1, Dwarf = 1, ["Night Elf"] = 1, Gnome = 1,
                        Orc = 2, Undead = 2, Tauren = 2, Troll = 2 },
        allianceLines = { Alliance = true, ["Alliance Only"] = true },
        hordeLines    = { Horde = true, ["Horde Only"] = true },
    }
    local B = Scan.CLASS_BIT

    local function parse(...) return Scan.ParseRestrictions({ ... }, LOC) end

    -- ── no restriction ──────────────────────────────────────────────────────
    local m, f = parse("Binds when picked up", "Cloth", "Head", "+10 Stamina")
    ck(m == 0, "an ordinary item has no class mask")
    ck(f == Scan.FACTION_NONE, "...and no faction lock")
    ck(select(1, Scan.ParseRestrictions({}, LOC)) == 0, "no lines -> unrestricted")
    ck(select(1, Scan.ParseRestrictions(nil, LOC)) == 0, "nil lines -> unrestricted")
    ck(select(1, Scan.ParseRestrictions({ "Classes: Mage" }, nil)) == 0,
       "no locale context -> unrestricted (fails open, never hides)")

    -- ── class locks (the Atiesh case) ───────────────────────────────────────
    m, f = parse("Binds when picked up", "Two-Hand", "Staff", "Classes: Mage")
    ck(m == B.MAGE, "a single-class lock yields exactly that class bit")
    ck(f == Scan.FACTION_NONE, "a class lock is not a faction lock")
    m = parse("Classes: Druid, Mage, Priest, Warlock")
    ck(m == B.DRUID + B.MAGE + B.PRIEST + B.WARLOCK, "a multi-class lock ORs the bits")
    ck(Scan.HasBit(m, B.MAGE) and not Scan.HasBit(m, B.WARRIOR),
       "...and reads back per class")
    m = parse("Classes:Rogue")           -- no space after the colon
    ck(m == 0, "a line that does not carry the localized prefix is ignored, not guessed")
    m = parse("Classes: Mage, Mage")
    ck(m == B.MAGE, "a duplicated class is counted once")
    m = parse("Classes:  Mage ,  Priest ")
    ck(m == B.MAGE + B.PRIEST, "surrounding whitespace on each entry is trimmed")
    ck(m < Scan.CLASS_UNKNOWN, "a fully parsed list never sets the unknown bit")

    -- ── unparseable class names fail OPEN ───────────────────────────────────
    m = parse("Classes: Necromancer")
    ck(Scan.HasBit(m, Scan.CLASS_UNKNOWN), "an unresolvable class name raises the unknown bit")
    m = parse("Classes: Mage, Necromancer")
    ck(Scan.HasBit(m, B.MAGE), "...the resolvable part is still recorded")
    ck(Scan.HasBit(m, Scan.CLASS_UNKNOWN), "...alongside the unknown bit")

    -- ── faction locks ───────────────────────────────────────────────────────
    m, f = parse("Binds when picked up", "Alliance Only")
    ck(f == Scan.FACTION_ALLIANCE, "an 'Alliance Only' line is an Alliance lock")
    m, f = parse("Horde Only")
    ck(f == Scan.FACTION_HORDE, "a 'Horde Only' line is a Horde lock")
    m, f = parse("Horde")
    ck(f == Scan.FACTION_HORDE, "the bare faction name also counts (FACTION_HORDE)")

    -- vanilla mostly expresses faction as a full-faction RACE mask
    m, f = parse("Races: Orc, Undead, Tauren, Troll")
    ck(f == Scan.FACTION_HORDE, "a whole-Horde race list collapses to a Horde lock")
    m, f = parse("Races: Human, Dwarf, Night Elf, Gnome")
    ck(f == Scan.FACTION_ALLIANCE, "a whole-Alliance race list collapses to an Alliance lock")
    m, f = parse("Races: Human, Orc")
    ck(f == Scan.FACTION_NONE, "a CROSS-faction race list is not a faction lock")
    m, f = parse("Races: Gnome")
    ck(f == Scan.FACTION_ALLIANCE, "a single-race list still identifies its faction")
    m, f = parse("Races: Dryad")
    ck(f == Scan.FACTION_NONE, "an unrecognised race leaves the item unrestricted (fails open)")
    m, f = parse("Races: ")
    ck(f == Scan.FACTION_NONE, "an empty race list is not a lock")

    -- ── both axes on one tooltip ────────────────────────────────────────────
    m, f = parse("Binds when picked up", "Classes: Warrior", "Horde Only", "Requires level 60")
    ck(m == B.WARRIOR and f == Scan.FACTION_HORDE, "class and faction locks coexist")

    -- ── deliberately NOT filtered (coverage limit, asserted so it stays a choice) ─
    m, f = parse("Requires Blacksmithing (300)", "Requires Argent Dawn - Exalted", "Requires Level 60")
    ck(m == 0 and f == Scan.FACTION_NONE,
       "profession / reputation / level requirements are NOT restrictions — a goal can be earned")

    ck(Scan.IsRestricted({ classMask = B.MAGE }) == true, "IsRestricted sees a class lock")
    ck(Scan.IsRestricted({ faction = Scan.FACTION_HORDE }) == true, "IsRestricted sees a faction lock")
    ck(Scan.IsRestricted({ classMask = 0, faction = 0 }) == false, "an open item is not restricted")
    ck(Scan.IsRestricted(nil) == false, "nil is not restricted")
end)

----------------------------------------------------------------------
-- THE FILTER PREDICATE MATRIX, plus a mutation-adequacy gate.
--
-- The whole point of the round: "hide items the CURRENT character can never
-- equip". Every row below is a (item, viewer) pair with a stated verdict.
----------------------------------------------------------------------
suite("item-scan-filter-matrix", function(ck)
    if type(Scan) ~= "table" then ck(false, "itemScan.lua did not load"); return end
    local B = Scan.CLASS_BIT
    local WEAPON, ARMOR = Scan.ITEM_CLASS_WEAPON, Scan.ITEM_CLASS_ARMOR

    local function viewer(class, faction, showUnusable)
        return { class = class, classBit = B[class] or 0, faction = faction or 0,
                 showUnusable = showUnusable and true or false }
    end
    local hordeWarrior  = viewer("WARRIOR", Scan.FACTION_HORDE)
    local allyWarrior   = viewer("WARRIOR", Scan.FACTION_ALLIANCE)
    local hordeMage     = viewer("MAGE",    Scan.FACTION_HORDE)
    local hordeRogue    = viewer("ROGUE",   Scan.FACTION_HORDE)

    -- ── items ───────────────────────────────────────────────────────────────
    local plainCloak  = { classID = ARMOR,  subclassID = 0, classMask = 0, faction = 0 }
    local plateChest  = { classID = ARMOR,  subclassID = 4, classMask = 0, faction = 0 }
    local clothRobe   = { classID = ARMOR,  subclassID = 1, classMask = 0, faction = 0 }
    local atiesh      = { classID = WEAPON, subclassID = 10, classMask = B.MAGE, faction = 0 }
    local warrSet     = { classID = ARMOR,  subclassID = 4, classMask = B.WARRIOR, faction = 0 }
    local allyRank    = { classID = ARMOR,  subclassID = 4, classMask = 0, faction = Scan.FACTION_ALLIANCE }
    local hordeRank   = { classID = ARMOR,  subclassID = 4, classMask = 0, faction = Scan.FACTION_HORDE }
    local allyWarrSet = { classID = ARMOR,  subclassID = 4, classMask = B.WARRIOR, faction = Scan.FACTION_ALLIANCE }
    local wand        = { classID = WEAPON, subclassID = 19, classMask = 0, faction = 0 }
    local fuzzyClass  = { classID = ARMOR,  subclassID = 1, classMask = B.MAGE + Scan.CLASS_UNKNOWN, faction = 0 }
    local onlyUnknown = { classID = ARMOR,  subclassID = 1, classMask = Scan.CLASS_UNKNOWN, faction = 0 }

    local U = Scan.Usable

    -- unrestricted
    ck(U(plainCloak, hordeWarrior) == true, "an unrestricted cloak shows for everyone")
    ck(U(plainCloak, hordeMage)    == true, "...including a cloth wearer")

    -- class lock, right vs wrong class  (THE reported defect: Atiesh on a warrior)
    ck(U(atiesh, hordeMage)    == true,  "Atiesh (Classes: Mage) SHOWS for a mage")
    ck(U(atiesh, hordeWarrior) == false, "Atiesh is HIDDEN from a warrior")
    ck(U(warrSet, hordeWarrior) == true, "a warrior set piece shows for a warrior")
    ck(U(warrSet, hordeMage)    == false, "...and is hidden from a mage")

    -- faction lock, right vs wrong faction (Alliance rank gear on Horde)
    ck(U(allyRank, allyWarrior)  == true,  "an Alliance rank piece shows for Alliance")
    ck(U(allyRank, hordeWarrior) == false, "...and is HIDDEN from Horde")
    ck(U(hordeRank, hordeWarrior) == true,  "a Horde rank piece shows for Horde")
    ck(U(hordeRank, allyWarrior)  == false, "...and is hidden from Alliance")

    -- the two axes are independent
    ck(U(allyWarrSet, allyWarrior)  == true,  "right class + right faction shows")
    ck(U(allyWarrSet, hordeWarrior) == false, "right class + WRONG faction hides")
    ck(U(allyWarrSet, viewer("MAGE", Scan.FACTION_ALLIANCE)) == false,
       "wrong class + right faction hides")

    -- proficiency
    ck(U(plateChest, hordeWarrior) == true,  "a warrior can wear plate")
    ck(U(plateChest, hordeMage)    == false, "a mage cannot")
    ck(U(clothRobe,  hordeMage)    == true,  "a mage can wear cloth")
    ck(U(clothRobe,  hordeWarrior) == true,  "a warrior can also wear cloth (no downgrade lock)")
    ck(U(wand, hordeMage)     == true,  "a mage can use a wand")
    ck(U(wand, hordeWarrior)  == false, "a warrior cannot")
    ck(U(wand, hordeRogue)    == false, "nor can a rogue")
    ck(U(plainCloak, hordeRogue) == true, "armor subclass 0 (cloaks/rings/necks/trinkets) is universal")

    -- the unknown-class bit fails OPEN
    ck(U(fuzzyClass, hordeWarrior) == true,
       "a partly-unparseable class list is SHOWN to a non-listed class (fails open)")
    ck(U(fuzzyClass, hordeMage) == true, "...and of course to the listed class")
    ck(U(onlyUnknown, hordeWarrior) == true, "a wholly unparseable class list is shown")

    -- the escape hatch
    local shown = viewer("WARRIOR", Scan.FACTION_HORDE, true)
    ck(U(atiesh,   shown) == true, "'show unusable' reveals class-locked items")
    ck(U(allyRank, shown) == true, "...and opposite-faction items")
    ck(U(wand,     shown) == true, "...and items the class has no proficiency for")

    -- degenerate inputs
    ck(U(nil, hordeWarrior) == false, "a nil record is never usable")
    ck(U(plainCloak, nil)   == true,  "with no viewer context nothing is filtered")
    ck(U(atiesh, viewer("NOTACLASS", 0)) == true,
       "an unknown viewer class filters nothing rather than hiding everything")
    ck(U({ classID = ARMOR, subclassID = 99, classMask = 0, faction = 0 }, hordeWarrior) == false,
       "an armor subclass no class knows is treated as unusable")
    ck(U({ classID = 15, subclassID = 99, classMask = 0, faction = 0 }, hordeWarrior) == true,
       "a non-armor / non-weapon item class is not proficiency-gated")

    -- ── MUTATION ADEQUACY ───────────────────────────────────────────────────
    -- Each mutant is a plausible WRONG implementation of the predicate. The
    -- fixture set above must distinguish every one of them, or a regression of
    -- that exact shape would ship green.
    local fixtures = {
        { plainCloak, hordeWarrior }, { plainCloak, hordeMage },
        { atiesh, hordeMage },        { atiesh, hordeWarrior },
        { warrSet, hordeWarrior },    { warrSet, hordeMage },
        { allyRank, allyWarrior },    { allyRank, hordeWarrior },
        { hordeRank, hordeWarrior },  { hordeRank, allyWarrior },
        { allyWarrSet, allyWarrior }, { allyWarrSet, hordeWarrior },
        { plateChest, hordeWarrior }, { plateChest, hordeMage },
        { wand, hordeMage },          { wand, hordeWarrior },
        { fuzzyClass, hordeWarrior }, { onlyUnknown, hordeWarrior },
        { atiesh, shown },            { allyRank, shown }, { wand, shown },
    }
    local hasBit = Scan.HasBit
    local MUTANTS = {
        ["M1 class lock ignored"] = function(rec, ctx)
            if ctx.showUnusable then return true end
            local fa = rec.faction or 0
            if fa ~= 0 and (ctx.faction or 0) ~= 0 and fa ~= ctx.faction then return false end
            local prof = Scan.PROF[ctx.class]
            if prof and rec.classID == 4 and not prof.armor[rec.subclassID] then return false end
            if prof and rec.classID == 2 and not prof.weapon[rec.subclassID] then return false end
            return true
        end,
        ["M2 class test inverted"] = function(rec, ctx)
            if ctx.showUnusable then return true end
            local cm = rec.classMask or 0
            if cm > 0 and not hasBit(cm, Scan.CLASS_UNKNOWN) then
                if hasBit(cm % Scan.CLASS_UNKNOWN, ctx.classBit) then return false end
            end
            return true
        end,
        ["M3 faction lock ignored"] = function(rec, ctx)
            if ctx.showUnusable then return true end
            local cm = rec.classMask or 0
            if cm > 0 and not hasBit(cm, Scan.CLASS_UNKNOWN)
               and (cm % Scan.CLASS_UNKNOWN) > 0 and not hasBit(cm, ctx.classBit) then return false end
            local prof = Scan.PROF[ctx.class]
            if prof and rec.classID == 4 and not prof.armor[rec.subclassID] then return false end
            if prof and rec.classID == 2 and not prof.weapon[rec.subclassID] then return false end
            return true
        end,
        ["M4 faction test inverted"] = function(rec, ctx)
            if ctx.showUnusable then return true end
            local fa = rec.faction or 0
            if fa ~= 0 and fa == (ctx.faction or 0) then return false end
            return true
        end,
        ["M5 unrestricted treated as locked"] = function(rec, ctx)
            if ctx.showUnusable then return true end
            if not hasBit(rec.classMask or 0, ctx.classBit) then return false end
            return true
        end,
        ["M6 show-unusable inverted"] = function(rec, ctx)
            local c2 = {}
            for k, v in pairs(ctx) do c2[k] = v end
            c2.showUnusable = not ctx.showUnusable
            return Scan.Usable(rec, c2)
        end,
        ["M7 proficiency ignored"] = function(rec, ctx)
            if ctx.showUnusable then return true end
            local cm = rec.classMask or 0
            if cm > 0 and not hasBit(cm, Scan.CLASS_UNKNOWN)
               and (cm % Scan.CLASS_UNKNOWN) > 0 and not hasBit(cm, ctx.classBit) then return false end
            local fa = rec.faction or 0
            if fa ~= 0 and (ctx.faction or 0) ~= 0 and fa ~= ctx.faction then return false end
            return true
        end,
        ["M8 unknown class bit fails CLOSED"] = function(rec, ctx)
            if ctx.showUnusable then return true end
            local cm = rec.classMask or 0
            if cm > 0 and not hasBit(cm, ctx.classBit) then return false end
            local fa = rec.faction or 0
            if fa ~= 0 and (ctx.faction or 0) ~= 0 and fa ~= ctx.faction then return false end
            local prof = Scan.PROF[ctx.class]
            if prof and rec.classID == 4 and not prof.armor[rec.subclassID] then return false end
            if prof and rec.classID == 2 and not prof.weapon[rec.subclassID] then return false end
            return true
        end,
    }
    local names = {}
    for k in pairs(MUTANTS) do names[#names + 1] = k end
    table.sort(names)
    for _, name in ipairs(names) do
        local mut, killed = MUTANTS[name], false
        for _, fx in ipairs(fixtures) do
            local real = Scan.Usable(fx[1], fx[2])
            local ok, got = pcall(mut, fx[1], fx[2])
            if not ok or (got and true or false) ~= real then killed = true; break end
        end
        ck(killed, "mutation killed: " .. name)
    end
end)

----------------------------------------------------------------------
-- CACHE ROUND-TRIP: pack/unpack, Put/Get, and a real SavedVariables
-- serialize -> reload cycle (the cache's whole job is to survive a logout).
----------------------------------------------------------------------
suite("item-scan-cache-roundtrip", function(ck)
    if type(Scan) ~= "table" then ck(false, "itemScan.lua did not load"); return end
    local B = Scan.CLASS_BIT

    -- ── the packed meta field ───────────────────────────────────────────────
    local function trip(q, m, f)
        local a, b, c = Scan.UnpackMeta(Scan.PackMeta(q, m, f))
        return a == q and b == m and c == f
    end
    ck(trip(0, 0, 0), "the all-zero record round-trips")
    ck(trip(4, B.MAGE, Scan.FACTION_HORDE), "epic / mage-locked / Horde round-trips")
    ck(trip(5, B.DRUID + B.MAGE + B.PRIEST + B.WARLOCK, 0), "a multi-class legendary round-trips")
    ck(trip(1, Scan.CLASS_UNKNOWN, Scan.FACTION_ALLIANCE), "the unknown bit survives the round trip")
    ck(trip(7, 4095, 3), "the top of every field round-trips")
    local allOK = true
    for q = 0, 7 do
        for _, m in ipairs({ 0, 1, 2, 4, 8, 16, 64, 128, 256, 1024, 2048, 1503, 4095 }) do
            for f = 0, 2 do if not trip(q, m, f) then allOK = false end end
        end
    end
    ck(allOK, "every (quality x mask x faction) combination in play round-trips exactly")
    ck(Scan.PackMeta(nil, nil, nil) == 0, "nil fields pack as zero")
    ck(select(1, Scan.UnpackMeta(nil)) == 0, "unpacking nil yields zeros")
    ck(Scan.PackMeta(99, 99999, 9) == Scan.PackMeta(15, 4095, 3), "out-of-range fields clamp")
    ck(Scan.PackMeta(-4, -1, -1) == 0, "negative fields clamp to zero")
    ck(Scan.PackMeta(4, 0, 0) < 2^24, "a packed record stays a small integer")

    -- ── Put / Get ───────────────────────────────────────────────────────────
    local c = Scan.NewCache()
    ck(c.version == Scan.CACHE_VERSION and c.count == 0, "a fresh cache is empty and versioned")
    ck(Scan.IsComplete(c) == false, "a fresh cache is not a completed scan")
    ck(Scan.Put(c, 23709, "Corehound Belt", 3, 0, 0) == true, "Put accepts a record")
    ck(c.count == 1, "count tracks the insert")
    ck(Scan.Put(c, 22589, "Atiesh, Greatstaff of the Guardian", 5, B.MAGE, 0) == true, "second record")
    ck(c.count == 2, "count tracks the second insert")
    ck(Scan.Put(c, 23709, "Corehound Belt", 3, 0, 0) == true, "re-Put of a known id succeeds")
    ck(c.count == 2, "...without double counting")
    ck(Scan.Put(c, nil, "x") == false, "Put rejects a nil id")
    ck(Scan.Put(c, 5, nil) == false, "Put rejects a nil name")
    ck(Scan.Put(c, 5, "") == false, "Put rejects an empty name")
    ck(Scan.Put(nil, 5, "x") == false, "Put rejects a nil cache")
    ck(c.count == 2, "rejected Puts do not move the count")

    local nm, q, m, f = Scan.Get(c, 22589)
    ck(nm == "Atiesh, Greatstaff of the Guardian", "Get returns the name")
    ck(q == 5, "...the quality")
    ck(m == B.MAGE, "...the class mask")
    ck(f == 0, "...and the faction")
    ck(Scan.Get(c, 999999) == nil, "an unscanned id reads back nil")
    ck(Scan.Get(nil, 1) == nil, "a nil cache reads back nil")
    ck(Scan.Get(c, "22589") ~= nil, "a numeric-string id is coerced (SavedVariables keys)")

    -- ── SavedVariables serialize -> reload ──────────────────────────────────
    Scan.Put(c, 16542, "Warlord's Iron-Breastplate", 4, B.WARRIOR, Scan.FACTION_HORDE)
    c.scannedAt, c.build, c.ranges = 1754200000, "1.15.9.68808", "1-32000"
    local function ser(v, out)
        local t = type(v)
        if t == "string" then out[#out + 1] = string.format("%q", v)
        elseif t == "number" or t == "boolean" then out[#out + 1] = tostring(v)
        elseif t == "table" then
            out[#out + 1] = "{"
            local keys = {}
            for k in pairs(v) do keys[#keys + 1] = k end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            for _, k in ipairs(keys) do
                out[#out + 1] = "[" .. (type(k) == "string" and string.format("%q", k) or tostring(k)) .. "]="
                ser(v[k], out)
                out[#out + 1] = ","
            end
            out[#out + 1] = "}"
        else out[#out + 1] = "nil" end
    end
    local buf = {}
    ser(c, buf)
    local chunk = loadstring("return " .. table.concat(buf))
    ck(chunk ~= nil, "the cache serializes to a loadable SavedVariables chunk")
    local reloaded = chunk and Scan.Normalize(chunk())
    ck(reloaded ~= nil, "…and normalizes on the way back in")
    if reloaded then
        ck(reloaded.count == 3, "the reloaded cache recounts its entries")
        ck(Scan.IsComplete(reloaded) == true, "a reloaded completed scan reads as complete")
        local n2, q2, m2, f2 = Scan.Get(reloaded, 16542)
        ck(n2 == "Warlord's Iron-Breastplate", "the apostrophe survives the round trip")
        ck(q2 == 4 and m2 == B.WARRIOR and f2 == Scan.FACTION_HORDE,
           "quality, class lock and faction lock all survive a logout")
        ck(reloaded.scannedAt == 1754200000 and reloaded.build == "1.15.9.68808",
           "the scan stamp survives")
        -- and the predicate still answers correctly off the reloaded record
        local rec = { classID = 4, subclassID = 4, classMask = m2, faction = f2 }
        ck(Scan.Usable(rec, { class = "WARRIOR", classBit = B.WARRIOR, faction = Scan.FACTION_HORDE }) == true,
           "reloaded Horde warrior piece is usable by a Horde warrior")
        ck(Scan.Usable(rec, { class = "WARRIOR", classBit = B.WARRIOR, faction = Scan.FACTION_ALLIANCE }) == false,
           "…and hidden from an Alliance warrior")
    end

    -- ── Normalize guards ────────────────────────────────────────────────────
    local n = Scan.Normalize(nil)
    ck(type(n) == "table" and n.count == 0, "Normalize(nil) yields a fresh cache")
    n = Scan.Normalize("not a table")
    ck(type(n) == "table" and n.count == 0, "Normalize of a non-table yields a fresh cache")
    n = Scan.Normalize({ version = Scan.CACHE_VERSION - 1, names = { [1] = "old" }, count = 1 })
    ck(n.count == 0 and next(n.names) == nil,
       "a stale cache version is DISCARDED, not migrated (it is a derived artefact)")
    n = Scan.Normalize({ version = Scan.CACHE_VERSION, names = { [1] = "a", [2] = "b" } })
    ck(n.count == 2 and type(n.meta) == "table", "a torn cache is repaired and recounted")
    ck(Scan.IsComplete(nil) == false, "nil is not a completed scan")
    ck(Scan.IsComplete({ scannedAt = 1, count = 0 }) == false, "an empty completed scan is not complete")
end)

----------------------------------------------------------------------
-- INTERNAL / UNOBTAINABLE ITEM FILTER  (1.3.1)
--
-- The 1..32000 id walk is a walk of the CLIENT's item space, so it sweeps up
-- Blizzard's own working records: "[PH] Brilliant Dawn Cap" (the item the owner
-- screenshotted in an otherwise-empty picker), "Monster - Sword, Katana",
-- "Test Glaive A", "90 Epic Warrior Helm", "Deprecated Dented Skullcap". None of
-- them can be obtained by any player.
--
-- EVIDENCE BASE: every fixture below is a VERBATIM name from a real completed
-- cache (10 504 equippable ids, Era build 68940) — the junk ones and the
-- genuine ones alike. 1 263 of the 10 504 are internal; the surviving 9 241 were
-- swept for collisions and there are none, so the survivor fixtures here are the
-- near-misses that actually forced each pattern's anchoring.
----------------------------------------------------------------------
suite("item-scan-internal-filter", function(ck)
    if type(Scan) ~= "table" then ck(false, "itemScan.lua did not load"); return end
    ck(type(Scan.INTERNAL_PATTERNS) == "table" and #Scan.INTERNAL_PATTERNS > 0,
       "the denylist is published as Scan.INTERNAL_PATTERNS")
    ck(type(Scan.IsInternalName) == "function", "Scan.IsInternalName is published")

    -- ── one fixture per pattern; the pattern must be the one that kills it ───
    -- (InternalPattern returns the FIRST match, so this also proves no fixture is
    -- being killed by some earlier, broader pattern instead.)
    local KILLS = {
        ["%[ph%]"]              = "[PH] Brilliant Dawn Cap",
        ["monster %- "]         = "Monster - Sword, Katana",
        ["%f[%a]test%f[%A]"]    = "Test Glaive A",
        ["%f[%a]testing%f[%A]"] = "Ring of Critical Testing 2",
        ["^testboots"]          = "TestBoots - Puffed Mail Green",
        ["qatest"]              = "QATest +1000 Spell Dmg Ring",
        ["jefftest"]            = "Fishing Pole (JEFFTEST)",
        ["%(delete me%)"]       = "Shane (DELETE ME)",
        ["^deprecated "]        = "Deprecated Dented Skullcap",
        [" deprecated$"]        = "Thunderfury, Blessed Blade of the Windseeker DEPRECATED",
        [" dep$"]               = "Lok'delar, Stave of the Ancient Keepers DEP",
        ["^old%a"]              = "OLDThug Belt",
        ["%(old%)"]             = "(OLD)Medium Throwing Knife",
        ["%f[%a]unused%f[%A]"]  = "Unused Feathered Leggings",
        ["%(dnd%)"]             = "Charm Pouch (DND)",
        ["%f[%a]foo%f[%A]"]     = "Twain Random Sword FOO",
        ["^pvp %a+ %a+ %a"]     = "PVP Plate Helm Alliance",
        ["^%d+ epic %a"]        = "90 Epic Warrior Helm",
        ["^%d+ green %a"]       = "63 Green Rogue Cap",
        ["^%d+ blue %a"]        = "70 Blue Warrior Axe",
        ["^%d+ purple %a"]      = "80 Purple Rogue Dagger",
        ["^%d+ white %a"]       = "40 White Mage Robe",
        ["^%d+ grey %a"]        = "40 Grey Mage Robe",
        ["^%d+ gray %a"]        = "40 Gray Mage Robe",
        ["%f[%a]%a%d%d "]       = "Black Leather D02 Boots",
        ["%f[%a]%a%d%d$"]       = "Monster Shield Engineer A01",
        -- 1.3.1, from the owner's second screenshot
        ["^enchant %w.* %- %a"] = "Enchant Cloak - Resistance",
        ["%f[%a]nax ph%f[%A]"]  = "Nax PH Crit Plate Shoulders",
    }
    local uncovered = {}
    for _, p in ipairs(Scan.INTERNAL_PATTERNS) do
        local fx = KILLS[p]
        if not fx then uncovered[#uncovered + 1] = p
        else
            ck(Scan.InternalPattern(fx) == p,
               "pattern " .. p .. " kills its fixture: " .. fx)
        end
    end
    ck(#uncovered == 0, "every denylist pattern has a fixture (uncovered: "
       .. table.concat(uncovered, " ") .. ")")

    -- ── genuine Era names SURVIVE. Every one of these is in the real cache, and
    -- the awkward ones are why the patterns are anchored the way they are. ────
    local SURVIVORS = {
        "Testament of Hope",          -- 'Test' + a letter, not the word "test"
        "Contest Winner's Tabard",    -- "test" inside another word
        "Old Blanchy's Blanket", "Old Blunderbuss", "Old Greatsword", "Old Leather Belt",
        "Adept's Cloak", "Adept Short Staff", "Band of Icy Depths",   -- 'dep'
        "10 Pound Mud Snapper", "103 Pound Mightfish", "15 Pound Salmon",
        "Doomcaller's Footwraps", "Footpads of the Fang",             -- 'foo'
        "Templar Crown", "Tempered Bracers",
        "Boots of Prophecy", "Circlet of Prophecy",                   -- 'ph'
        "Pendulum of Doom", "Corehound Belt", "Krol Blade", "Arcanite Reaper",
        "Bloodfang Hood", "Onyxia Tooth Pendant",
        "Thunderfury, Blessed Blade of the Windseeker",
        "Lok'delar, Stave of the Ancient Keepers",
        "Rhok'delar, Longbow of the Ancient Keepers",
        "Sulfuras, Hand of Ragnaros", "Atiesh, Greatstaff of the Guardian",
        "Zin'rokh, Destroyer of Worlds",
        "The 1 Ring", "Engineer's Shield 1", "Digmaster 5000",
        "Frostwolf Insignia Rank 4", "Techbot CPU Shell",
        "Nat Pagle's Extreme Angler FC-5000", "Warglaive of Azzinoth (Left)",
        "Seal of the Dawn", "Tabard of the Argent Dawn",
        "BKP 42 \"Ultra\"", "Warlock Orb 35",
        -- the enchant family's real neighbours (1.3.1). The recipes are genuine
        -- tradeable items and the "Enchanted …" gear is genuine worn gear; only
        -- the bare "Enchant <slot> - <effect>" spell-effect name is not real.
        "Formula: Enchant Cloak - Resistance",
        "Formula: Enchant Cloak - Greater Resistance",
        "Formula: Enchant 2H Weapon - Major Intellect",
        "Formula: Enchant Gloves - Superior Agility",
        "Enchanted Thorium Helm", "Enchanted Thorium Breastplate",
        "Enchanted Battlehammer", "Enchanted Kodo Bracers",
        "Enchanted Moonstalker Cloak", "Enchanted South Seas Kelp",
        "Enchanter's Cowl", "Boots of the Enchanter",
        "Pristine Enchanted South Seas Kelp",
    }
    for _, nm in ipairs(SURVIVORS) do
        ck(Scan.IsInternalName(nm) == false,
           "genuine item survives: " .. nm .. " (killed by "
           .. tostring(Scan.InternalPattern(nm)) .. ")")
    end

    -- the four twin pairs: the live item and the client's dead copy of it
    local TWINS = {
        { "Thunderfury, Blessed Blade of the Windseeker",
          "Thunderfury, Blessed Blade of the Windseeker DEPRECATED" },
        { "Lok'delar, Stave of the Ancient Keepers",
          "Lok'delar, Stave of the Ancient Keepers DEP" },
        { "Pendulum of Doom", "Monster - Axe, 2H Pendulum of Doom" },
        { "Mandokir's Sting", "Mandokir's Sting DEPRECATED" },
    }
    for _, t in ipairs(TWINS) do
        ck(Scan.IsInternalName(t[1]) == false and Scan.IsInternalName(t[2]) == true,
           "the live item outlives its dead twin: " .. t[1])
    end

    -- ── THE ENCHANT FAMILY (1.3.1) ──────────────────────────────────────────
    -- "Enchant <slot> - <effect>" is the name of an enchantment EFFECT. The
    -- bundled AtlasLoot seed carries 123 of them; the owner's picker offered
    -- "Enchant Cloak - Resistance". Fixtures are verbatim seed names, one per
    -- slot the family covers, so a future narrowing of the pattern goes red.
    local ENCHANTS = {
        "Enchant Cloak - Resistance", "Enchant Cloak - Greater Resistance",
        "Enchant Cloak - Superior Defense", "Enchant Cloak - Stealth",
        "Enchant Chest - Greater Stats", "Enchant Chest - Minor Absorption",
        "Enchant Bracer - Superior Strength", "Enchant Bracer - Mana Regeneration",
        "Enchant Gloves - Advanced Herbalism", "Enchant Gloves - Riding Skill",
        "Enchant Boots - Minor Speed", "Enchant Shield - Lesser Block",
        "Enchant Weapon - Crusader", "Enchant Weapon - Mighty Intellect",
        "Enchant 2H Weapon - Agility",        -- the slot token starts with a DIGIT
        "Enchant 2H Weapon - Superior Impact",
    }
    for _, nm in ipairs(ENCHANTS) do
        ck(Scan.InternalPattern(nm) == "^enchant %w.* %- %a",
           "the enchant-effect pattern removes: " .. nm)
    end
    -- …and the pattern's anchor is load-bearing in BOTH directions.
    ck(Scan.IsInternalName("Formula: Enchant Cloak - Resistance") == false,
       "the RECIPE for the very same enchant survives (it is a real, tradeable item)")
    ck(Scan.IsInternalName("Enchanted Thorium Helm") == false,
       "'Enchanted …' survives: the pattern needs a SPACE after the word enchant")
    ck(Scan.IsInternalName("Enchanter's Cowl") == false, "…and so does 'Enchanter's …'")
    ck(Scan.IsInternalName("Enchant Cloak") == false,
       "a bare 'Enchant <word>' with no ' - <effect>' is not the family and is left alone")

    -- degenerate inputs
    ck(Scan.IsInternalName(nil) == false, "nil is not an internal name")
    ck(Scan.IsInternalName("")  == false, "an empty name is not an internal name")
    ck(Scan.IsInternalName(42)  == false, "a non-string is not an internal name")
    ck(Scan.IsInternalName("test") == true, "the bare lowercase name 'test' is internal")
    ck(Scan.IsInternalName("TEST SWORD") == true, "…and its uppercase sibling (matching is case-insensitive)")

    -- ── the flag is CACHED, packed, and survives a logout ───────────────────
    local q, m, f, i = Scan.UnpackMeta(Scan.PackMeta(4, Scan.CLASS_BIT.MAGE, 1, true))
    ck(q == 4 and m == Scan.CLASS_BIT.MAGE and f == 1 and i == true,
       "the internal bit round-trips alongside quality / mask / faction")
    ck(select(4, Scan.UnpackMeta(Scan.PackMeta(4, 4095, 3, false))) == false,
       "…and a full record with the bit clear reads back clear")
    ck(Scan.PackMeta(15, 4095, 3, true) < 2 ^ 24, "a packed record is still a small integer")
    ck(select(4, Scan.UnpackMeta(Scan.PackMeta(4, 0, 0))) == false,
       "1.3.0's three-argument PackMeta still means 'not internal'")

    local c = Scan.NewCache()
    ck(c.internalStamp == Scan.INTERNAL_STAMP, "a fresh cache carries the current denylist stamp")
    Scan.Put(c, 19162, "Corehound Belt", 3, 0, 0)
    Scan.Put(c, 13789, "[PH] Brilliant Dawn Cap", 1, 0, 0)
    ck(select(5, Scan.Get(c, 13789)) == true, "Put DERIVES the internal flag from the name")
    ck(select(5, Scan.Get(c, 19162)) == false, "…and leaves a real item unflagged")
    ck(c.count == 2, "internal rows stay IN the cache (a rescan must not re-fight them)")

    -- ── a 1.3.0 cache is UPGRADED IN PLACE, never discarded ─────────────────
    -- The bit did not exist in 1.3.0, so every meta value read back with it clear.
    -- Normalize must re-derive rather than demand a minute-long rescan.
    local old = {
        version = Scan.CACHE_VERSION,
        names = { [13789] = "[PH] Brilliant Dawn Cap", [19162] = "Corehound Belt",
                  [9425] = "Pendulum of Doom", [11342] = "Monster - Axe, 2H Pendulum of Doom" },
        meta  = { [13789] = Scan.PackMeta(1, 0, 0), [19162] = Scan.PackMeta(3, 0, 0),
                  [9425] = Scan.PackMeta(4, 0, 0), [11342] = Scan.PackMeta(1, 0, 0) },
        count = 4, scannedAt = 1754200000,
    }
    ck(old.internalStamp == nil, "…the 1.3.0 cache has no denylist stamp")
    local up = Scan.Normalize(old)
    ck(up.count == 4, "the upgrade keeps every row (no rescan is demanded)")
    ck(up.internalStamp == Scan.INTERNAL_STAMP, "…and stamps the denylist it was derived with")
    ck(up.internalCount == 2, "…having flagged exactly the two internal rows")
    ck(select(5, Scan.Get(up, 13789)) == true and select(5, Scan.Get(up, 11342)) == true,
       "the placeholder and the creature record are flagged on the way in")
    ck(select(5, Scan.Get(up, 19162)) == false and select(5, Scan.Get(up, 9425)) == false,
       "…and the real items are not")
    ck(select(2, Scan.Get(up, 9425)) == 4, "the re-derive preserves quality")

    -- an already-stamped cache is left alone (the pass is idempotent and one-shot)
    up.meta[19162] = Scan.PackMeta(3, 0, 0, true)     -- a lie, deliberately planted
    local again = Scan.Normalize(up)
    ck(select(5, Scan.Get(again, 19162)) == true,
       "a cache already on the current stamp is NOT re-derived (the pass runs once)")
    again.internalStamp = "some-older-stamp"
    again = Scan.Normalize(again)
    ck(select(5, Scan.Get(again, 19162)) == false,
       "…and a stamp change re-derives every flag, so a denylist fix reaches an old cache")

    -- ── MUTATION ADEQUACY: each mutant is a plausible WRONG denylist. The
    -- fixtures above must distinguish every one, or that regression ships green.
    local FIX = {}
    for _, nm in pairs(KILLS) do FIX[#FIX + 1] = nm end
    for _, nm in ipairs(SURVIVORS) do FIX[#FIX + 1] = nm end
    for _, nm in ipairs(ENCHANTS) do FIX[#FIX + 1] = nm end
    FIX[#FIX + 1] = "test Eric Shirt"
    FIX[#FIX + 1] = "Mandokir's Sting DEPRECATED"
    FIX[#FIX + 1] = "Monster - Axe, 2H Pendulum of Doom"

    local function anyOf(pats)
        return function(name)
            local s = tostring(name or ""):lower()
            for _, p in ipairs(pats) do if s:find(p) then return true end end
            return false
        end
    end
    local MUTANTS = {
        ["N1 'test' as a loose substring"] = anyOf({ "test" }),
        ["N2 'ph' as a loose substring"]   = anyOf({ "ph" }),
        ["N3 'old' without the glue rule"] = anyOf({ "^old" }),
        ["N4 'dep' as a loose substring"]  = anyOf({ "dep" }),
        ["N5 'foo' as a loose substring"]  = anyOf({ "foo" }),
        ["N6 level template without the quality word"] = anyOf({ "^%d%d " }),
        ["N7 case-sensitive matching"] = function(name)
            local s = tostring(name or "")
            for _, p in ipairs(Scan.INTERNAL_PATTERNS) do if s:find(p) then return true end end
            return false
        end,
        ["N8 only the first pattern is consulted"] = function(name)
            return tostring(name or ""):lower():find(Scan.INTERNAL_PATTERNS[1]) ~= nil
        end,
        -- 1.3.1: the enchant pattern is exactly as loose as it must be, no looser.
        ["N12 'enchant' as a loose substring"] = anyOf({ "enchant" }),
        ["N13 '^enchant' without the trailing space"] = anyOf({ "^enchant" }),
        ["N14 the enchant pattern without its ' - <effect>' tail"] = anyOf({ "^enchant %w" }),
        ["N15 'ph' anywhere, not just the Nax placeholder"] = anyOf({ "ph" }),
        ["N9 the verdict is inverted"] = function(name) return not Scan.IsInternalName(name) end,
        ["N10 nothing is ever internal"] = function() return false end,
        ["N11 everything is internal"] = function() return true end,
    }
    local mnames = {}
    for k in pairs(MUTANTS) do mnames[#mnames + 1] = k end
    table.sort(mnames)
    for _, name in ipairs(mnames) do
        local mut, killed = MUTANTS[name], false
        for _, fx in ipairs(FIX) do
            local ok, got = pcall(mut, fx)
            if not ok or (got and true or false) ~= Scan.IsInternalName(fx) then killed = true; break end
        end
        ck(killed, "mutation killed: " .. name)
    end
end)

----------------------------------------------------------------------
-- THE EMPTY-SEARCH STATE  (owner question, 1.3.1)
--
-- VERDICT: an empty search box lists the WHOLE slot — every item that fits it
-- and that this character could equip. There is no minimum query length, no
-- current-goal echo, and nothing about it changed in 1.3.0: the pre-scan picker
-- (commit c602fb9) filtered on `query == "" or e.name:find(query)` and
-- ShowGoalPicker opened with `filtered("", …)`, which is browse-the-slot. The
-- box is a FILTER over a browsable list, not a required search term, so it
-- stays that way.
--
-- What actually went wrong in 1.3.0 is that the client scan poured Blizzard's
-- internal records into that browsable list, so a placeholder was what the owner
-- saw sitting in an "empty" picker. The suite above removes those; this one pins
-- the browse semantics so nobody "fixes" the empty state by mistake.
----------------------------------------------------------------------
suite("goal-picker-empty-query", function(ck)
    if type(Scan) ~= "table" then ck(false, "itemScan.lua did not load"); return end
    ck(type(Scan.Matches) == "function", "the row predicate is published as Scan.Matches")
    ck(type(Scan.NormalizeQuery) == "function", "…and query normalisation with it")

    local HEAD = { INVTYPE_HEAD = true }
    local warrior = { class = "WARRIOR", classBit = Scan.CLASS_BIT.WARRIOR,
                      faction = Scan.FACTION_HORDE, showUnusable = false }
    local function row(name, loc, subclass, mask)
        return { id = 1, name = name:lower(), display = name, equipLoc = loc or "INVTYPE_HEAD",
                 classID = Scan.ITEM_CLASS_ARMOR, subclassID = subclass or 4,
                 classMask = mask or 0, faction = Scan.FACTION_NONE }
    end
    local helm  = row("Lionheart Helm")
    local coif  = row("Helm of Wrath")
    local robe  = row("Robe of Volatile Power", "INVTYPE_ROBE", 1)
    local mageOnly = row("Arcanist Crown", "INVTYPE_HEAD", 1, Scan.CLASS_BIT.MAGE)

    -- ── the empty box ───────────────────────────────────────────────────────
    ck(Scan.NormalizeQuery("") == "", "an empty box normalises to the empty query")
    ck(Scan.NormalizeQuery("   ") == "", "…and so does a box holding only spaces")
    ck(Scan.NormalizeQuery(nil) == "", "…and a nil text")
    ck(Scan.NormalizeQuery("  LioNheart ") == "lionheart", "a real query is trimmed and folded")

    ck(Scan.Matches(helm, "", HEAD, warrior) == true,
       "EMPTY QUERY LISTS THE SLOT: a head item matches with no search term")
    ck(Scan.Matches(coif, "", HEAD, warrior) == true, "…and so does every other head item")
    ck(Scan.Matches(helm, Scan.NormalizeQuery("   "), HEAD, warrior) == true,
       "…a whitespace-only box is the same empty query, not a failed search")
    ck(Scan.Matches(robe, "", HEAD, warrior) == false,
       "…but the slot filter still bites: a robe is not a head item")
    ck(Scan.Matches(mageOnly, "", HEAD, warrior) == false,
       "…and so does the usability filter: a mage-only crown stays hidden from a warrior")

    -- there is no minimum length: one character filters, it does not reset to all
    ck(Scan.Matches(helm, "n", HEAD, warrior) == true, "a one-character query filters")
    ck(Scan.Matches(coif, "n", HEAD, warrior) == false, "…and it really does exclude")
    ck(Scan.Matches(helm, "lionheart", HEAD, warrior) == true, "a full name matches")
    ck(Scan.Matches(helm, "zzzz", HEAD, warrior) == false, "a query that matches nothing yields nothing")
    ck(Scan.Matches(helm, "helm of", HEAD, warrior) == false,
       "the query is a plain substring of THIS row's name, not a fuzzy match")

    -- the search is a literal substring, so a Lua pattern character is not magic
    local plus = row("Test Defense Ring +120")
    ck(Scan.Matches(plus, "+120", HEAD, warrior) == true,
       "'+' in the query is literal text, not a Lua pattern quantifier")

    -- degenerate inputs
    ck(Scan.Matches(nil, "", HEAD, warrior) == false, "a nil row never matches")
    ck(Scan.Matches(helm, "", nil, warrior) == false,
       "no slot map means no rows (the picker is always opened FOR a slot)")
    ck(Scan.Matches(helm, "", {}, warrior) == false, "an empty slot map matches nothing")
    ck(Scan.Matches(helm, "", HEAD, nil) == true, "with no viewer context nothing is usability-filtered")

    -- 'show unusable' still works through the same predicate…
    local shown = { class = "WARRIOR", classBit = Scan.CLASS_BIT.WARRIOR,
                    faction = Scan.FACTION_HORDE, showUnusable = true }
    ck(Scan.Matches(mageOnly, "", HEAD, shown) == true,
       "'show unusable' reveals the mage-only crown")
    -- …but it CANNOT reveal an internal record, because those never reach the index.
    ck(Scan.IsInternalName("[PH] Brilliant Dawn Cap") == true,
       "the screenshotted row is an internal record")
    local src = io.open(P("goalPicker.lua"), "r")
    ck(src ~= nil, "goalPicker.lua is readable")
    if src then
        local s = src:read("*a"); src:close()
        ck(s:find("if internal then return end") ~= nil,
           "the index builder drops internal rows before they become entries")
        ck(s:find("Scan%.IsInternalName") ~= nil,
           "…deriving the flag for the seed tables, which were never scanned")
        ck(s:find("Scan%.Matches") ~= nil, "the row filter runs the shared predicate")
        ck(s:find("Scan%.NormalizeQuery") ~= nil, "…over a normalised query")
        ck(s:find("internalStamp") ~= nil,
           "the index cache key includes the denylist stamp, so a pattern fix rebuilds it")
    end
end)

----------------------------------------------------------------------
-- ROW MODEL: the picker tints each result row by item RARITY, using the
-- suite's quality-color chain rather than a private copy.
----------------------------------------------------------------------
suite("goal-picker-row-model", function(ck)
    local Bd = {}
    local fn = loadfile(P("borders.lua"))
    ck(fn ~= nil, "borders.lua compiles")
    if not fn then return end
    Bd.SLOTS = {}
    local ok = pcall(fn, "Daseeki-Armory", Bd)
    ck(ok, "borders.lua loads with no WoW API present")
    local M = Bd.Borders
    ck(type(M) == "table" and type(M.QualityTextRGB) == "function",
       "the text variant is published as Borders.QualityTextRGB")
    if type(M) ~= "table" or type(M.QualityTextRGB) ~= "function" then return end

    -- the row tint IS the suite chain for every quality above Poor
    for q = 1, 7 do
        local a1, a2, a3 = M.QualityTextRGB(q)
        local b1, b2, b3 = M.QualityRGB(q)
        ck(a1 == b1 and a2 == b2 and a3 == b3,
           "quality " .. q .. " tints identically to the glow chain (no private palette)")
    end
    local r, g, b = M.QualityTextRGB(4)
    ck(near(r, 0.64) and near(g, 0.21) and near(b, 0.93), "epic rows are the Blizzard purple")
    r = M.QualityTextRGB(5)
    ck(near(r, 1.00) and near(select(2, M.QualityTextRGB(5)), 0.50), "legendary rows are orange")

    -- Poor is the ONE deliberate divergence: the glow value is near-black by design
    -- (spec §3, an ADD-blended wash), which as TEXT would be invisible.
    local pr = M.QualityTextRGB(0)
    ck(pr ~= nil, "Poor has a text color")
    ck(pr > 0.4, "Poor TEXT is legible grey, not the near-black glow tint (" .. tostring(pr) .. ")")
    ck(near(pr, 0.62), "...specifically Blizzard's own ITEM_QUALITY_COLORS[0] grey")
    ck(near(M.QualityRGB(0), 0.1), "...while the GLOW path keeps its near-black override")
    ck(M.QualityTextRGB(nil) == nil,
       "an unresolved quality has NO color, so the caller can fall back and re-tint later")

    -- source contract: the picker actually uses all of this
    local h = io.open(P("goalPicker.lua"), "r")
    ck(h ~= nil, "goalPicker.lua is readable")
    if not h then return end
    local src = h:read("*a"); h:close()
    ck(src:find("QualityTextRGB") ~= nil, "the picker tints rows through Borders.QualityTextRGB")
    ck(src:find("RequestLoadItemDataByID") ~= nil,
       "…and requests a load for rows whose quality has not arrived yet")
    ck(src:find("GET_ITEM_INFO_RECEIVED") ~= nil, "…and re-tints when it does")
    ck(src:find("Scan%.Usable") ~= nil, "the result filter runs the shared usability predicate")
    ck(src:find("Addon:ScanContext") ~= nil, "…against the VIEWING character's context")
    ck(src:find("StartItemScan") ~= nil, "the picker can start a rescan")
    ck(src:find("showUnusable") ~= nil, "…and exposes the show-unusable escape hatch")
    -- the cap must come after the sort, or "highest ilvl first" is a lie on big result sets
    local fs, ss = src:find("table%.sort%(out"), src:find("for i = #out, MAX_RESULTS")
    ck(fs ~= nil and ss ~= nil and ss > fs, "results are capped AFTER the ilvl sort, not before")

    -- the scan cache is a NEW account-wide SavedVariables; the per-character one is untouched
    local t = io.open(P("Daseeki-Armory.toc"), "r")
    ck(t ~= nil, "TOC is readable")
    if not t then return end
    local toc = t:read("*a"); t:close()
    ck(toc:find("## SavedVariablesPerCharacter: DaseekiArmoryDB") ~= nil,
       "the per-character SavedVariables is unchanged")
    ck(toc:find("## SavedVariables: DaseekiArmoryScanDB") ~= nil,
       "the scan cache is a NEW account-wide SavedVariables (additive)")
    ck(toc:find("\nitemScan%.lua") ~= nil, "itemScan.lua is in the load order")
    ck(toc:find("itemScan%.lua") < toc:find("goalPicker%.lua"),
       "…before goalPicker.lua, which binds Addon.ItemScan at file scope")
end)

----------------------------------------------------------------------
-- THE ROW POOL: geometry and tint  (1.3.1)
--
-- THE DEFECT (owner screenshot, shipped in 1.3.0 with the rarity-colour work):
-- the picker rendered exactly ONE row. Items were there — scrolling moved that
-- one row through them — and nothing was tinted by rarity.
--
-- THE CAUSE was a single line of Lua:
--     local cr, cg, cb = Addon.Borders and Addon.Borders.QualityTextRGB(q)
-- An `and` expression is adjusted to ONE value, so cg and cb were always nil and
-- the next line ran SetTextColor(r, nil, nil), which raises. Row 1 had already
-- been given its text; rows 2..12 had not been reached; the error left
-- RefreshList, so the count line never updated either. Every symptom follows.
--
-- goalPicker.lua now publishes the pure half of the pool (Addon.GoalPickerRows)
-- so the geometry and the tint contract are arithmetic a harness can hold.
----------------------------------------------------------------------
local PickerRows
do
    local A = { ItemScan = Scan }
    local fn = loadfile(P("goalPicker.lua"))
    if fn then
        local ok = pcall(fn, "Daseeki-Armory", A)
        if ok then PickerRows = A.GoalPickerRows end
    end
end

suite("goal-picker-row-pool", function(ck)
    ck(type(PickerRows) == "table",
       "goalPicker.lua loads with no WoW API and publishes Addon.GoalPickerRows")
    if type(PickerRows) ~= "table" then return end
    local R = PickerRows

    -- ── geometry ────────────────────────────────────────────────────────────
    ck(R.VISIBLE == 12, "the pool holds 12 visible rows")
    ck(R.ROW_HEIGHT == 28, "each row is 28px tall")
    ck(R.LIST_TOP == 82, "the list starts 82px below the frame top")
    ck(R.RowY(1) == R.LIST_TOP, "row 1 sits at the top of the list")
    for i = 2, R.VISIBLE do
        ck(R.RowY(i) - R.RowY(i - 1) == R.ROW_HEIGHT,
           "row " .. i .. " is exactly one row-height below row " .. (i - 1))
    end
    ck(R.RowY(R.VISIBLE) == R.LIST_TOP + (R.VISIBLE - 1) * R.ROW_HEIGHT,
       "the last row's offset is LIST_TOP + 11 row heights (no drift)")
    ck(R.RowY(0) == nil and R.RowY(R.VISIBLE + 1) == nil,
       "a row outside the pool has no position")
    ck(R.FrameHeight() > R.RowY(R.VISIBLE) + R.ROW_HEIGHT,
       "the frame is tall enough to show every row in the pool")
    ck(R.FOOTER_Y >= R.RowY(R.VISIBLE) + R.ROW_HEIGHT,
       "…and the footer sits below the last row, not on top of it")

    -- ── N VISIBLE ROWS FOR M ITEMS: the property the defect broke ────────────
    local function shown(n, off)
        local s, c = R.Slice(n, off), 0
        for i = 1, R.VISIBLE do if s[i] then c = c + 1 end end
        return c, s
    end
    ck(#R.Slice(0, 0) == R.VISIBLE, "Slice always speaks for every row in the pool")
    for _, case in ipairs({ { 0, 0 }, { 1, 1 }, { 5, 5 }, { 11, 11 }, { 12, 12 },
                            { 13, 12 }, { 500, 12 }, { 9241, 12 } }) do
        local n, expect = case[1], case[2]
        local got = shown(n, 0)
        ck(got == expect,
           n .. " results fill " .. expect .. " rows at offset 0 (got " .. got .. ")")
    end
    local _, s0 = shown(40, 0)
    ck(s0[1] == 1 and s0[12] == 12, "at offset 0 the pool shows results 1..12")
    local _, s7 = shown(40, 7)
    ck(s7[1] == 8 and s7[12] == 19, "at offset 7 it shows results 8..19")
    local _, sEnd = shown(40, 28)
    ck(sEnd[1] == 29 and sEnd[12] == 40, "at the last screenful it shows 29..40, all full")
    local _, sShort = shown(3, 0)
    ck(sShort[3] == 3 and sShort[4] == false,
       "with 3 results, rows 4..12 are told to hide (they are not left stale)")

    -- ── scrolling cannot run off either end ─────────────────────────────────
    ck(R.MaxOffset(0) == 0 and R.MaxOffset(12) == 0, "a list that fits does not scroll")
    ck(R.MaxOffset(13) == 1, "one row over the pool scrolls by exactly one")
    ck(R.MaxOffset(500) == 488, "a full result set stops with the last row at the bottom")
    ck(R.ClampOffset(-5, 500) == 0, "scrolling up past the top clamps to the top")
    ck(R.ClampOffset(9999, 500) == 488, "…and down past the end clamps to the last screenful")
    ck(R.ClampOffset(4, 3) == 0, "an offset larger than a short list collapses to 0")
    local _, sOver = shown(500, 9999)
    ck(sOver[12] == 500, "the clamped bottom really shows the last result")

    -- ── SCROLL SURVIVES A REFRESH NOBODY ASKED FOR (1.3.1) ──────────────────
    -- THE DEFECT (owner, round two): scrolling the list jumped back to the top
    -- over and over. Requery unconditionally wrote _offset = 0, and Requery is
    -- what the GET_ITEM_INFO_RECEIVED handler calls — which during the
    -- restriction-repair pass fires in a continuous stream, because every visible
    -- row that is not yet tinted asks the client to load its item and every reply
    -- schedules another refresh. The list was effectively unscrollable.
    ck(type(R.NextOffset) == "function", "the pool decides where a refresh lands")
    ck(R.NextOffset(0, 500, false) == 0, "a reader-initiated refresh starts at the top")
    ck(R.NextOffset(240, 500, false) == 0, "…however far down the reader was")
    ck(R.NextOffset(240, 500, true) == 240,
       "THE FIX: a background refresh leaves the reader exactly where they were")
    ck(R.NextOffset(0, 500, true) == 0, "…including at the top")
    ck(R.NextOffset(488, 500, true) == 488, "…and at the very bottom")
    -- the list can SHRINK under the reader (a repair lands class locks and rows
    -- disappear); the kept offset is clamped, never left past the end
    ck(R.NextOffset(488, 500, true) == R.MaxOffset(500),
       "the bottom of a 500-row list is the last screenful")
    ck(R.NextOffset(488, 20, true) == R.MaxOffset(20),
       "a list that shrank under the reader clamps to ITS last screenful, not the old one")
    ck(R.NextOffset(488, 5, true) == 0, "…and a list shorter than the pool collapses to the top")
    ck(R.NextOffset(488, 0, true) == 0, "…as does an empty one")
    ck(R.NextOffset(-3, 500, true) == 0, "a negative carried offset is still clamped")
    ck(R.NextOffset(nil, 500, true) == 0, "…and a missing one reads as the top")
    -- the kept offset always produces a full slice where one is available
    local _, keep = shown(500, R.NextOffset(240, 500, true))
    ck(keep[1] == 241 and keep[12] == 252,
       "the preserved offset really shows the same twelve rows again")
    local _, kept2 = shown(20, R.NextOffset(488, 20, true))
    ck(kept2[1] == 9 and kept2[12] == 20,
       "…and after a shrink it shows the new last screenful, fully populated")

    local OFFSET_MUTANTS = {
        ["O1 every refresh goes to the top (THE ROUND-TWO DEFECT)"] = function()
            return R.NextOffset(240, 500, true) == 0
        end,
        ["O2 every refresh keeps the offset, even a new query"] = function()
            return R.NextOffset(240, 500, false) ~= 0
        end,
        ["O3 the kept offset is not clamped to the new list"] = function()
            return R.NextOffset(488, 20, true) == 488
        end,
        ["O4 the preserve flag is ignored entirely"] = function()
            return R.NextOffset(240, 500, true) == R.NextOffset(240, 500, false)
        end,
    }
    local onames = {}
    for k in pairs(OFFSET_MUTANTS) do onames[#onames + 1] = k end
    table.sort(onames)
    for _, name in ipairs(onames) do
        local okm, holds = pcall(OFFSET_MUTANTS[name])
        ck(okm and holds == false, "mutation killed: " .. name)
    end

    -- ── THE TINT CONTRACT: all three components, or none ────────────────────
    local Bd = {}
    local bfn = loadfile(P("borders.lua"))
    ck(bfn ~= nil, "borders.lua compiles")
    if not bfn then return end
    Bd.SLOTS = {}
    pcall(bfn, "Daseeki-Armory", Bd)
    local B = Bd.Borders
    ck(type(B) == "table", "borders.lua published Addon.Borders")
    if type(B) ~= "table" then return end

    for q = 0, 7 do
        local r, g, b, needs = R.Tint(q, B)
        ck(r ~= nil and g ~= nil and b ~= nil,
           "quality " .. q .. " tints with a COMPLETE r,g,b triple (this is the 1.3.0 defect)")
        ck(needs == false, "…and needs no further item load")
        local br, bg, bb = B.QualityTextRGB(q)
        ck(r == br and g == bg and b == bb,
           "…and it is the suite's own colour for quality " .. q .. ", not a private one")
    end
    local nr, ng, nb, needs = R.Tint(nil, B)
    ck(nr == nil and ng == nil and nb == nil,
       "an unresolved quality yields NO colour rather than a partial one")
    ck(needs == true, "…and asks for the item to be loaded")
    local mr, mg, mb, mneeds = R.Tint(4, nil)
    ck(mr == nil and mg == nil and mb == nil and mneeds == true,
       "with no Borders module at all the row falls back cleanly instead of raising")

    -- the epic row is purple in all three channels — a truncated return would
    -- have passed the r check alone
    local er, eg, eb = R.Tint(4, B)
    ck(near(er, 0.64) and near(eg, 0.21) and near(eb, 0.93),
       "an epic row is the Blizzard purple in every channel")

    -- ── MUTATION ADEQUACY over the layout and the tint ──────────────────────
    local LAYOUT_MUTANTS = {
        ["L1 RowY forgets the 1-based offset (i, not i-1)"] = function()
            return R.LIST_TOP + 1 * R.ROW_HEIGHT == R.RowY(1)
        end,
        ["L2 every row is anchored at the same y"] = function()
            return R.RowY(1) == R.RowY(2)
        end,
        ["L3 Slice fills only the first row (the 1.3.0 symptom)"] = function()
            return shown(40, 0) == 1
        end,
        ["L4 Slice ignores the offset"] = function()
            local _, s = shown(40, 7); return s[1] == 1
        end,
        ["L5 MaxOffset forgets to subtract the pool"] = function()
            return R.MaxOffset(500) == 500
        end,
        ["L6 the offset is never clamped"] = function()
            return R.ClampOffset(9999, 500) == 9999 or R.ClampOffset(-5, 500) == -5
        end,
        ["L7 Slice leaves the tail rows stale instead of hiding them"] = function()
            local _, s = shown(3, 0); return s[4] ~= false
        end,
    }
    local lnames = {}
    for k in pairs(LAYOUT_MUTANTS) do lnames[#lnames + 1] = k end
    table.sort(lnames)
    for _, name in ipairs(lnames) do
        local okm, holds = pcall(LAYOUT_MUTANTS[name])
        ck(okm and holds == false, "mutation killed: " .. name)
    end

    -- The tint mutants are written as REPLACEMENT implementations and must all
    -- disagree with the real one on the fixture qualities. M1 is the shipped bug.
    local TINT_MUTANTS = {
        ["M1 the `and` truncation (THE 1.3.0 DEFECT)"] = function(q)
            local r, g, b = B and B.QualityTextRGB(q)
            return r, g, b
        end,
        ["M2 nothing ever gets a colour"] = function() return nil, nil, nil end,
        ["M3 every row gets the same colour"] = function() return 1, 1, 1 end,
        ["M4 an unknown quality is tinted anyway"] = function(q)
            if q == nil then return 1, 1, 1 end
            local r, g, b = B.QualityTextRGB(q); return r, g, b
        end,
        ["M5 Poor uses the near-black GLOW value as text"] = function(q)
            local r, g, b = B.QualityRGB(q); return r, g, b
        end,
    }
    local QFIX = { 0, 1, 2, 3, 4, 5, 6, 7, nil }
    local tnames = {}
    for k in pairs(TINT_MUTANTS) do tnames[#tnames + 1] = k end
    table.sort(tnames)
    for _, name in ipairs(tnames) do
        local mut, killed = TINT_MUTANTS[name], false
        for i = 1, 9 do
            local q = QFIX[i]
            local a1, a2, a3 = R.Tint(q, B)
            local okm, b1, b2, b3 = pcall(mut, q)
            if not okm or a1 ~= b1 or a2 ~= b2 or a3 ~= b3 then killed = true; break end
        end
        ck(killed, "mutation killed: " .. name)
    end

    -- ── source contract: the picker really uses the pool ────────────────────
    local h = io.open(P("goalPicker.lua"), "r")
    ck(h ~= nil, "goalPicker.lua is readable")
    if not h then return end
    local src = h:read("*a"); h:close()
    ck(src:find("Rows%.Tint%(qualityOf") ~= nil,
       "RefreshList tints through Rows.Tint, not through an `and` expression")
    -- The defect line is QUOTED in the file's own comment (that is the record of
    -- why the pool exists), so the check has to look at code, not at prose.
    local offending
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
        local body = line:gsub("^%s+", "")
        if body:sub(1, 2) ~= "--"
           and line:find("=[^=]*and%s+[%w_.]*QualityTextRGB%s*%(") then
            offending = line
        end
    end
    ck(offending == nil,
       "THE DEFECT LINE IS GONE: no multi-return is taken out of an `and` ("
       .. tostring(offending) .. ")")
    ck(src:find("for i = 1, Rows%.VISIBLE do") ~= nil,
       "the refresh walks the pool BY INDEX, so a hole cannot cut the list short")
    ck(src:find("Rows%.Slice") ~= nil, "…over the slice, which speaks for every row")
    ck(src:find("Rows%.ClampOffset") ~= nil, "the mouse wheel clamps through the same module")
    ck(src:find("%-Rows%.RowY%(i%)") ~= nil, "…and the rows are anchored by Rows.RowY")

    -- Requery must route its offset through the pool, and must NOT hard-zero it.
    ck(src:find("self%._offset = Rows%.NextOffset%(prev, #self%._list, preserveScroll%)") ~= nil,
       "Requery lands its offset through Rows.NextOffset")
    -- The defect line is QUOTED in the file's own comment (that is the record of
    -- why NextOffset exists), so the check has to look at code, not at prose.
    local zeroing
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
        local body = line:gsub("^%s+", "")
        if body:sub(1, 2) ~= "--" and body:find("^self%._offset%s*=%s*0") then
            zeroing = line
        end
    end
    ck(zeroing == nil,
       "THE DEFECT LINE IS GONE: nothing writes the offset straight to zero ("
       .. tostring(zeroing) .. ")")
    ck(src:find("function f:Requery%(preserveScroll%)") ~= nil,
       "…and the caller says whether the reader asked for this refresh")
    -- the two background refresh paths both preserve, and the reader-driven ones
    -- do not: search box, "Show unusable" and a fresh open all call Requery()
    local evt = src:find("GET_ITEM_INFO_RECEIVED\"%)")
    local evtRequery = evt and src:find("self:Requery%(true%)", evt)
    ck(evtRequery ~= nil,
       "the item-info stream refresh preserves the scroll position")
    ck(src:find("if self:IsShown%(%) then self:Requery%(true%) end") ~= nil,
       "…and so does the one that runs when a scan or repair finishes")
    ck(src:find("picker:Requery%(%)\n%s*end%)\n%s*search:SetScript%(\"OnEscapePressed") ~= nil,
       "…while typing in the search box goes back to the top")
    ck(src:find("if picker then picker:Requery%(%) end") ~= nil,
       "…as does toggling Show unusable")
    ck(src:find("f:SyncScanUI%(%)\n%s*f:Requery%(%)") ~= nil,
       "…and as does opening the picker")
end)

----------------------------------------------------------------------
-- RESTRICTION CAPTURE: "read nothing" is not "nothing to read"  (1.3.1)
--
-- THE DEFECT (owner screenshot): Bonescythe — rogue-only Tier-3 leather — was
-- offered to a WARRIOR. Not a fail-open on an unknown class token: the owner's
-- cache carries classMask = 0 for it, i.e. "no restriction at all", which the
-- filter is right to honour.
--
-- THE CAUSE: the scan read locks off a hidden tooltip and, when that tooltip did
-- not build, fell through to classMask = 0 — the same value it writes for an item
-- it read successfully and found unrestricted. Evidence from the owner's real
-- 10 504-item cache: all eight Tier-3 armour sets (ids 22416-22511, nine classes)
-- have classMask 0, inside one contiguous 224-row band of ids 22314-22821 that
-- contains no restricted row at all, while Tier 1 and Tier 2 either side of it
-- are captured 8-for-8 (Bloodfang, Nightslayer, Judgement, Lawbringer …). The
-- CLASS_UNKNOWN bit is set on 0 of 10 504 rows, so the fail-open path was never
-- the one in play — the reads simply never happened and were written down as
-- facts.
----------------------------------------------------------------------
suite("item-scan-restriction-capture", function(ck)
    if type(Scan) ~= "table" then ck(false, "itemScan.lua did not load"); return end
    ck(type(Scan.ReadRestrictions) == "function", "Scan.ReadRestrictions is published")

    local loc = {
        classPrefix = "Classes: ", racesPrefix = "Races: ",
        classByName = { Rogue = "ROGUE", Warrior = "WARRIOR", Mage = "MAGE" },
        raceFaction = { Orc = Scan.FACTION_HORDE, Human = Scan.FACTION_ALLIANCE },
        allianceLines = { Alliance = true }, hordeLines = { Horde = true },
    }

    -- ── the three outcomes are now THREE, not two ───────────────────────────
    local m, f, read = Scan.ReadRestrictions(
        { "Binds when picked up", "Chest", "Leather", "Classes: Rogue" }, loc)
    ck(read == true and m == Scan.CLASS_BIT.ROGUE and f == Scan.FACTION_NONE,
       "a tooltip that built and named a class yields that class, read=true")
    m, f, read = Scan.ReadRestrictions({ "Binds when equipped", "Chest", "Plate" }, loc)
    ck(read == true and m == 0,
       "a tooltip that built and named NO class is evidence of an unrestricted item")
    m, f, read = Scan.ReadRestrictions(nil, loc)
    ck(read == false and m == 0,
       "THE FIX: a tooltip that did not build is evidence of NOTHING (read=false)")
    m, f, read = Scan.ReadRestrictions({}, loc)
    ck(read == false, "…and so is an empty line list")
    ck(select(3, Scan.ReadRestrictions("not a table", loc)) == false,
       "…and a non-table")

    -- the Bonescythe line itself, as the client writes it
    ck(select(1, Scan.ReadRestrictions({ "Classes: Rogue" }, loc)) == Scan.CLASS_BIT.ROGUE,
       "'Classes: Rogue' is the lock that hides Bonescythe from a warrior")
    local warrior = { class = "WARRIOR", classBit = Scan.CLASS_BIT.WARRIOR,
                      faction = Scan.FACTION_NONE, showUnusable = false }
    local bone = { classID = Scan.ITEM_CLASS_ARMOR, subclassID = 2,
                   classMask = Scan.CLASS_BIT.ROGUE, faction = Scan.FACTION_NONE }
    ck(Scan.Usable(bone, warrior) == false, "with the lock captured, a warrior does not see it")
    local boneBare = { classID = Scan.ITEM_CLASS_ARMOR, subclassID = 2,
                       classMask = 0, faction = Scan.FACTION_NONE }
    ck(Scan.Usable(boneBare, warrior) == true,
       "…and with classMask 0 he does — the filter is right, the capture was wrong")
    -- fail-open on a genuinely unknown token is UNCHANGED policy
    local unk = { classID = Scan.ITEM_CLASS_ARMOR, subclassID = 2,
                  classMask = Scan.CLASS_UNKNOWN + Scan.CLASS_BIT.ROGUE,
                  faction = Scan.FACTION_NONE }
    ck(Scan.Usable(unk, warrior) == true,
       "a TRUE unknown still fails open: hiding an item he can use is the worse defect")

    -- ── the unread flag round-trips and is persisted ────────────────────────
    local q, cm, fa, i, u = Scan.UnpackMeta(Scan.PackMeta(4, Scan.CLASS_BIT.ROGUE, 0, false, true))
    ck(q == 4 and cm == Scan.CLASS_BIT.ROGUE and i == false and u == true,
       "the unread bit round-trips alongside quality / mask / faction / internal")
    ck(select(5, Scan.UnpackMeta(Scan.PackMeta(4, 0, 0, false, false))) == false,
       "…and reads back clear when it was not set")
    ck(select(5, Scan.UnpackMeta(Scan.PackMeta(4, 0, 0, true))) == false,
       "1.3.0's argument list still means 'read' (an old meta value is stale, not corrupt)")
    ck(Scan.PackMeta(15, 4095, 3, true, true) < 2 ^ 24,
       "a fully-flagged record is still a small integer")

    local c = Scan.NewCache()
    ck(c.restrictStamp == Scan.RESTRICT_STAMP, "a fresh cache carries the capture stamp")
    ck(Scan.UnreadCount(c) == 0, "…and nothing to re-read")
    Scan.Put(c, 22476, "Bonescythe Breastplate", 4, 0, 0, true)   -- tooltip refused
    Scan.Put(c, 16905, "Bloodfang Chestpiece",   4, Scan.CLASS_BIT.ROGUE, 0, false)
    ck(select(6, Scan.Get(c, 22476)) == true, "a row whose tooltip refused is flagged unread")
    ck(select(6, Scan.Get(c, 16905)) == false, "…and a row that was read is not")
    ck(select(3, Scan.Get(c, 16905)) == Scan.CLASS_BIT.ROGUE, "…keeping the lock it read")
    Scan.Put(c, 13789, "[PH] Brilliant Dawn Cap", 1, 0, 0, true)
    ck(select(6, Scan.Get(c, 13789)) == false,
       "an INTERNAL row is never 'unread': nothing ever asks it for a class lock")

    local ids = Scan.UnreadIds(c)
    ck(#ids == 1 and ids[1] == 22476, "UnreadIds lists exactly the rows to re-read")

    -- ── a pre-1.3.1 cache is migrated, not discarded ────────────────────────
    -- It cannot say which rows had a tooltip, so every real row is re-queued.
    local old = {
        version = Scan.CACHE_VERSION, scannedAt = 1785862751, count = 4,
        internalStamp = Scan.INTERNAL_STAMP,
        names = { [22476] = "Bonescythe Breastplate", [16905] = "Bloodfang Chestpiece",
                  [9425]  = "Pendulum of Doom",       [13789] = "[PH] Brilliant Dawn Cap" },
        meta  = { [22476] = Scan.PackMeta(4, 0, 0),
                  [16905] = Scan.PackMeta(4, Scan.CLASS_BIT.ROGUE, 0),
                  [9425]  = Scan.PackMeta(4, 0, 0),
                  [13789] = Scan.PackMeta(1, 0, 0, true) },
    }
    ck(old.restrictStamp == nil, "the pre-1.3.1 cache has no capture stamp")
    local up = Scan.Normalize(old)
    ck(up.count == 4, "the migration keeps every row (no rescan is demanded)")
    ck(up.restrictStamp == Scan.RESTRICT_STAMP, "…and stamps the capture it now trusts")
    ck(up.unreadCount == 3, "…having queued every REAL row for a re-read")
    ck(select(6, Scan.Get(up, 13789)) == false, "…and left the internal row out of it")
    ck(select(2, Scan.Get(up, 16905)) == 4, "the migration preserves quality")
    ck(select(3, Scan.Get(up, 16905)) == Scan.CLASS_BIT.ROGUE,
       "…and the locks it DID capture (a re-read can only improve on them)")
    local queue = Scan.UnreadIds(up)
    ck(#queue == 3 and queue[1] == 9425 and queue[3] == 22476,
       "the repair queue is in id order, exactly as the scan walked them")

    -- idempotent: a stamped cache is not re-flagged on the next login
    up.meta[9425] = Scan.PackMeta(4, 0, 0, false, false)   -- pretend it was repaired
    local again = Scan.Normalize(up)
    ck(select(6, Scan.Get(again, 9425)) == false,
       "a cache already on the current capture stamp is NOT re-flagged (the pass runs once)")
    ck(again.unreadCount == 2, "…and the remaining count falls as rows are repaired")
    again.restrictStamp = 0
    again = Scan.Normalize(again)
    ck(again.unreadCount == 3,
       "…while a capture-stamp bump re-queues everything, so a future capture fix lands too")

    -- a cache with NOTHING left to re-read asks for no repair at all
    for id in pairs(again.names) do
        local nm, qq, mm, ff = Scan.Get(again, id)
        Scan.Put(again, id, nm, qq, mm, ff, false)
    end
    again.unreadCount = nil                     -- force the recount path
    ck(Scan.UnreadCount(again) == 0, "a fully-read cache has no repair queue")

    -- ── source contract ─────────────────────────────────────────────────────
    local fh = io.open(P("itemScan.lua"), "r")
    ck(fh ~= nil, "itemScan.lua is readable")
    if fh then
        local s = fh:read("*a"); fh:close()
        ck(s:find("Scan%.ReadRestrictions%(tooltipLines%(id%), ST%.loc%)") ~= nil,
           "the recorder asks whether the tooltip was READ, not just what it said")
        ck(s:find("if lines then classMask, faction") == nil,
           "THE DEFECT IS GONE: an unbuilt tooltip is no longer silently 'unrestricted'")
        ck(s:find("Scan%.TOOLTIP_TRIES") ~= nil,
           "an unreadable tooltip is retried inside the scan before it is written off")
        ck(s:find("scanTip:SetOwner%(UIParent, \"ANCHOR_NONE\"%)") ~= nil,
           "the scanning tooltip re-owns itself on every use (an unowned tooltip builds nothing)")
        local created = s:find("CreateFrame%(\"GameTooltip\", \"DaseekiArmoryItemScanTip\"")
        local owned   = s:find("scanTip:SetOwner")
        ck(created ~= nil and owned ~= nil and owned > created,
           "…and does so AFTER creation, on the call path, not once at construction")
        ck(s:find("function Addon:MaybeRepairRestrictions") ~= nil,
           "the lazy repair pass is published")
        ck(s:find("opts%.repair") ~= nil, "…and rides the existing throttled scan runner")
        ck(s:find("Scan%.TOOLTIP_TRIES") < s:find("function Addon:MaybeRepairRestrictions"),
           "…with the in-scan retry as the first line of defence")
    end
    local gp = io.open(P("goalPicker.lua"), "r")
    if gp then
        local g = gp:read("*a"); gp:close()
        ck(g:find("Addon:MaybeRepairRestrictions") ~= nil,
           "the picker triggers the repair when it opens (lazily, once per session)")
        ck(g:find("Re%-reading class restrictions") ~= nil,
           "…and says so in the count line while it runs")
    end
end)

----------------------------------------------------------------------
-- THE SEED MAY NOT OVERRIDE THE CLIENT  (1.3.1)
--
-- THE DEFECT (owner screenshot): the picker offered "Enchant Cloak -
-- Resistance", the name of an enchantment EFFECT. It reached the list through a
-- fall-through introduced with the denylist: goalPicker's `add` returned on an
-- internal row BEFORE recording that the id had been dealt with, so the bundled
-- AtlasLoot seed — whose ids do not all agree with this client — got to name it
-- on the next pass. Id 13794 is "[PH] Shining Dawn Coif" in the owner's client
-- and "Enchant Cloak - Resistance" in the seed; the denylist removed the former
-- and the seed put the latter back. 37 ids in the owner's cache were resurrecting
-- like that, 7 of them as "Enchant …" rows, the rest under equally wrong names
-- ("Instant Poison V" for "Monster - Axe, 2H Pendulum of Doom").
----------------------------------------------------------------------
suite("goal-picker-source-precedence", function(ck)
    -- ── BEHAVIOURAL: drive the real BuildGoalItemDB over the real defect ─────
    -- goalPicker.lua touches the WoW API only from inside functions, so the index
    -- builder can be run headlessly against stubs. The fixture is the owner's own
    -- id 13794: "[PH] Shining Dawn Coif" in the client, "Enchant Cloak -
    -- Resistance" in the bundled seed.
    --
    -- `scanned` switches the fixture between the two regimes the 1.3.1 SEED
    -- RETIREMENT rule distinguishes: before the first completed scan the seed is
    -- the only name source there is, after it the cache is the whole index.
    local function buildFixture(scanned)
        local A = { ItemScan = Scan }
        local fn = loadfile(P("goalPicker.lua"))
        if not fn then return nil, "goalPicker.lua does not compile" end
        local okl = pcall(fn, "Daseeki-Armory", A)
        if not okl then return nil, "goalPicker.lua raised at load" end

        local cache = Scan.NewCache()
        Scan.Put(cache, 13794, "[PH] Shining Dawn Coif", 3, 0, 0)      -- internal
        Scan.Put(cache, 18419, "Monster - Axe, 2H Horde Red War Axe", 2, 0, 0)
        Scan.Put(cache, 19019, "Thunderfury, Blessed Blade of the Windseeker", 5, 0, 0)
        if scanned then cache.scannedAt = 1785862751 end
        A.ItemScanCache = function() return cache end
        -- the seed's disagreeing names for the SAME ids, verbatim from itemDB.lua
        A.ItemNameDB = {
            [13794] = "Enchant Cloak - Resistance",
            [18419] = "Felcloth Pants",
            [21134] = "Zandalar Freethinker's Breastplate",   -- seed-only, genuine
            [22737] = "Atiesh, Greatstaff of the Guardian",   -- seed-only, NOT in this client
        }
        A.ItemClassMask = {}
        A.PvPItemIDs = {}

        local savedI, savedG = _G.GetItemInfoInstant, _G.GetItemInfo
        _G.GetItemInfoInstant = function(id)
            return id, nil, nil, "INVTYPE_HEAD", "icon" .. tostring(id), 4, 1
        end
        _G.GetItemInfo = function() return nil end
        local okb, list = pcall(A.BuildGoalItemDB, A)
        _G.GetItemInfoInstant, _G.GetItemInfo = savedI, savedG
        if not okb then return nil, "BuildGoalItemDB raised: " .. tostring(list) end

        local byId, byName = {}, {}
        for _, e in ipairs(list) do byId[e.id] = e; byName[e.display] = true end
        return { A = A, cache = cache, list = list, byId = byId, byName = byName }
    end

    if type(Scan) == "table" then
        -- ── AFTER a completed scan: the cache is the WHOLE index ─────────────
        local post, perr = buildFixture(true)
        ck(post ~= nil, "the index builds against a completed-scan cache (" .. tostring(perr) .. ")")
        if post then
            ck(post.byName["Enchant Cloak - Resistance"] == nil,
               "THE 1.3.1 DEFECT: the seed cannot re-name an id the scan dropped as internal")
            ck(post.byId[13794] == nil, "…id 13794 is out of the index entirely")
            ck(post.byName["Felcloth Pants"] == nil,
               "…and neither can it re-name a dropped creature-art record")
            ck(post.byId[19019] ~= nil and post.byId[19019].display
               == "Thunderfury, Blessed Blade of the Windseeker",
               "a real scanned item is still in the index, under the CLIENT's name")
            -- ── SEED RETIREMENT (round two) ──────────────────────────────────
            ck(post.byId[21134] == nil,
               "SEED RETIREMENT: a seed-only id the completed scan never found is gone")
            ck(post.byId[22737] == nil,
               "…including the fifth Atiesh the bundled snapshot carries and this client does not")
            ck(post.byName["Zandalar Freethinker's Breastplate"] == nil,
               "…by name as well as by id")
            ck(#post.list == 1,
               "exactly the one scanned survivor, no seed rows at all (got " .. #post.list .. ")")
            ck(post.A.GoalSeedAllowed(post.cache) == false,
               "the rule itself says so: a completed scan retires the seed")
        end

        -- ── BEFORE any scan: the seed is all there is, and it still speaks ───
        local pre, prerr = buildFixture(false)
        ck(pre ~= nil, "the index builds against a never-scanned cache (" .. tostring(prerr) .. ")")
        if pre then
            ck(pre.A.GoalSeedAllowed(pre.cache) == true,
               "…and an incomplete scan does NOT retire it")
            ck(pre.byId[21134] ~= nil,
               "PRE-SCAN: the same seed-only row IS offered, because nothing better exists yet")
            ck(pre.byId[22737] ~= nil, "…as is the seed's fifth Atiesh")
            ck(pre.byId[19019] ~= nil,
               "…while the partial cache still outranks the seed on ids it does cover")
            ck(pre.byId[13794] == nil and pre.byName["Enchant Cloak - Resistance"] == nil,
               "…and precedence is unchanged: a dropped internal row is still not the seed's to name")
            ck(#pre.list > #post.list,
               "the pre-scan list is the longer one — retirement is what shortens it")
        end

        -- ── MUTATION ADEQUACY over the precedence rule itself ────────────────
        -- Each mutant is the rule written wrong; every one must disagree with the
        -- real Addon.GoalSeedAllowed on at least one of the four cache shapes.
        local none   = Scan.NewCache()
        local part   = Scan.NewCache(); Scan.Put(part, 19019, "Thunderfury", 5, 0, 0)
        local done   = Scan.NewCache(); Scan.Put(done, 19019, "Thunderfury", 5, 0, 0)
        done.scannedAt = 1785862751
        local hollow = Scan.NewCache(); hollow.scannedAt = 1785862751   -- stamped, zero rows
        local SHAPES = { none, part, done, hollow }
        local real = (post and post.A.GoalSeedAllowed) or nil
        ck(type(real) == "function", "the seed rule is published as a pure function")
        if type(real) == "function" then
            ck(real(none) == true,   "an empty cache keeps the seed")
            ck(real(part) == true,   "a cache with rows but no completion stamp keeps it")
            ck(real(done) == false,  "a completed scan retires it")
            ck(real(hollow) == true,
               "a completion stamp over ZERO rows is not a completed scan — the seed stays")
            local RULE_MUTANTS = {
                ["P1 the seed is always consulted (the shipped 1.3.0 behaviour)"] =
                    function() return true end,
                ["P2 the seed is never consulted, even before the first scan"] =
                    function() return false end,
                ["P3 'complete' means only that the stamp is present"] =
                    function(c) return not c.scannedAt end,
                ["P4 'complete' means only that the cache has rows"] =
                    function(c) return (c.count or 0) == 0 end,
                ["P5 the rule is inverted"] =
                    function(c) return Scan.IsComplete(c) end,
            }
            local rnames = {}
            for k in pairs(RULE_MUTANTS) do rnames[#rnames + 1] = k end
            table.sort(rnames)
            for _, name in ipairs(rnames) do
                local mut, killed = RULE_MUTANTS[name], false
                for _, c in ipairs(SHAPES) do
                    local okm, got = pcall(mut, c)
                    if not okm or got ~= real(c) then killed = true; break end
                end
                ck(killed, "mutation killed: " .. name)
            end
        end
    end

    local h = io.open(P("goalPicker.lua"), "r")
    ck(h ~= nil, "goalPicker.lua is readable")
    if not h then return end
    local src = h:read("*a"); h:close()

    ck(src:find("local list, settled = {}, {}") ~= nil,
       "the index builder tracks every id a source has SETTLED, not just the ones it kept")
    local mark = src:find("settled%[id%] = true")
    local drop = src:find("if internal then return end")
    ck(mark ~= nil and drop ~= nil and mark < drop,
       "an id is settled BEFORE the internal drop, so the drop cannot hand it to the seed")
    local guard = src:find("if not id or settled%[id%] then return end")
    ck(guard ~= nil and guard < mark, "…and a settled id is refused at the door")
    ck(src:find("if not byId%[id%] then") == nil and src:find("byId%[id%] = e") == nil,
       "the old keep-only bookkeeping is gone")
    ck(src:find("if not settled%[id%] then") ~= nil,
       "the PvP source honours the same ledger")

    -- source order: the scan speaks first, then the seed, then the PvP ids
    local scanLoop = src:find("for id in pairs%(cache%.names%) do")
    local seedLoop = src:find("for id, nm in pairs%(Addon%.ItemNameDB%) do")
    local pvpLoop  = src:find("for _, id in ipairs%(Addon%.PvPItemIDs")
    ck(scanLoop and seedLoop and pvpLoop and scanLoop < seedLoop and seedLoop < pvpLoop,
       "the CLIENT scan is consulted before the bundled snapshot, always")

    -- seed retirement is a GATE on that loop, not a filter inside it
    ck(src:find("function Addon%.GoalSeedAllowed%(cache%)") ~= nil,
       "the seed-retirement rule is published, pure, and named")
    ck(src:find("local seedAllowed = Addon%.GoalSeedAllowed%(cache%)") ~= nil,
       "…and the index builder asks it before opening the seed at all")
    ck(src:find("if seedAllowed and Addon%.ItemNameDB then") ~= nil,
       "…gating the whole seed loop rather than each row")
    ck(src:find("if Addon%.ItemNameDB then\n") == nil,
       "THE OLD UNGATED SEED LOOP IS GONE")

    -- and the family that exposed it can no longer be named at all
    if type(Scan) == "table" then
        ck(Scan.IsInternalName("Enchant Cloak - Resistance") == true,
           "belt and braces: the seed's own name for 13794 is on the denylist too")
        ck(Scan.IsInternalName("[PH] Shining Dawn Coif") == true,
           "…as is what the client actually calls that id")
    end
end)

----------------------------------------------------------------------
-- THE REPAIR REACHES THE OPEN PICKER  (1.3.1, round two)
--
-- THE DEFECT (owner, on a warrior): four copies of Atiesh — the Naxxramas
-- legendary staff, locked to mage/priest/warlock/druid — and all eight Tier-3
-- sets were still in the list. Their class locks are the ones the pre-1.3.1
-- capture never read (classMask 0 across the whole 22314-22821 band, 0 of 224
-- rows restricted, verified in the owner's real cache), so the repair pass is
-- what fixes them.
--
-- THE WIRING GAP: the repair wrote the masks and cleared the index, and then
-- nothing told the picker. The ONLY re-filter was f:ScanFinished, reached from a
-- 0.25s poll that f:SyncScanUI arms — and only when SyncScanUI happens to run
-- while a scan is already going. A repair that finished with the picker open but
-- the poll unarmed, or with the picker hidden and then re-shown from a cached
-- frame, left the pre-repair rows on screen. FinishItemScan now PUSHES the
-- refresh (Addon:RefreshGoalPicker) instead of waiting to be polled.
--
-- The second gap was the one-shot: MaybeRepairRestrictions stamped
-- Addon._restrictRepairTried and printed its notice BEFORE asking whether the
-- pass had actually started, so a session could burn its only attempt (and say so
-- in chat) on a repair that never ran.
----------------------------------------------------------------------
suite("goal-picker-repair-refilter", function(ck)
    if type(Scan) ~= "table" then ck(false, "itemScan.lua did not load"); return end

    -- ── 1. ATIESH, end to end, from tooltip text to picker row ──────────────
    -- The fixture is the client's own tooltip for id 22589, in the order the
    -- lines come off it. Nothing here is hand-waved: the same ParseRestrictions
    -- the scan uses turns it into a mask, the same Scan.Put persists it, the same
    -- Scan.Matches decides the row.
    local loc = {
        classPrefix = "Classes: ", racesPrefix = "Races: ",
        classByName = { Warrior = "WARRIOR", Paladin = "PALADIN", Hunter = "HUNTER",
                        Rogue = "ROGUE", Priest = "PRIEST", Shaman = "SHAMAN",
                        Mage = "MAGE", Warlock = "WARLOCK", Druid = "DRUID" },
        raceFaction = { Orc = Scan.FACTION_HORDE, Human = Scan.FACTION_ALLIANCE },
        allianceLines = { Alliance = true }, hordeLines = { Horde = true },
    }
    local ATIESH_TIP = {
        "Binds when picked up",
        "Unique",
        "Two-Hand", "Staff",
        "146 - 271 Damage", "Speed 3.00",
        "(69.5 damage per second)",
        "+30 Stamina",
        "+30 Intellect",
        "Classes: Mage, Priest, Warlock, Druid",
        "Requires Level 60",
        "Equip: Increases damage and healing done by magical spells and effects by up to 95.",
        "Equip: Restores 8 mana per 5 sec.",
        "Increases the spell damage of all party members within 30 yards by up to 33.",
    }
    local mask, fac, read = Scan.ReadRestrictions(ATIESH_TIP, loc)
    ck(read == true, "Atiesh's tooltip is a tooltip that BUILT (read = true)")
    local expect = Scan.CLASS_BIT.MAGE + Scan.CLASS_BIT.PRIEST
                 + Scan.CLASS_BIT.WARLOCK + Scan.CLASS_BIT.DRUID
    ck(mask == expect,
       "…and its 'Classes:' line is read as mage+priest+warlock+druid (got " .. mask .. ")")
    ck(fac == Scan.FACTION_NONE, "…with no faction lock (both sides can hold it)")
    ck(Scan.HasBit(mask, Scan.CLASS_BIT.WARRIOR) == false, "…and no warrior bit in it")
    ck(Scan.HasBit(mask, Scan.CLASS_UNKNOWN) == false,
       "…and no CLASS_UNKNOWN, so the filter does NOT fail open on it")

    local warrior = { class = "WARRIOR", classBit = Scan.CLASS_BIT.WARRIOR,
                      faction = Scan.FACTION_ALLIANCE, showUnusable = false }
    local mage    = { class = "MAGE", classBit = Scan.CLASS_BIT.MAGE,
                      faction = Scan.FACTION_ALLIANCE, showUnusable = false }
    -- a staff is weapon subclass 10; a warrior IS proficient with staves, so the
    -- class lock is the only thing that can hide it — exactly the owner's case
    ck(Scan.PROF.WARRIOR.weapon[10] == true,
       "a warrior can wield a staff, so proficiency alone would never hide Atiesh")
    local atiesh = { id = 22589, name = "atiesh, greatstaff of the guardian",
                     display = "Atiesh, Greatstaff of the Guardian",
                     equipLoc = "INVTYPE_2HWEAPON",
                     classID = Scan.ITEM_CLASS_WEAPON, subclassID = 10,
                     classMask = mask, faction = fac }
    local twoHand = { INVTYPE_2HWEAPON = true }
    ck(Scan.Matches(atiesh, "", twoHand, warrior) == false,
       "THE OWNER'S ROW: with the lock captured, a warrior's empty-query list drops Atiesh")
    ck(Scan.Matches(atiesh, "atiesh", twoHand, warrior) == false,
       "…and searching for it by name does not bring it back either")
    ck(Scan.Matches(atiesh, "", twoHand, mage) == true, "…while a mage still sees it")
    ck(Scan.Matches(atiesh, "", twoHand,
       { class = "WARRIOR", classBit = Scan.CLASS_BIT.WARRIOR, showUnusable = true }) == true,
       "…and 'Show unusable' still reveals it, because it IS a real item")
    -- the pre-repair state is the bug, and it must still reproduce
    local unrepaired = { id = 22589, name = "atiesh", display = "Atiesh",
                         equipLoc = "INVTYPE_2HWEAPON",
                         classID = Scan.ITEM_CLASS_WEAPON, subclassID = 10,
                         classMask = 0, faction = Scan.FACTION_NONE }
    ck(Scan.Matches(unrepaired, "", twoHand, warrior) == true,
       "…and with classMask 0 the warrior DOES see it — the repair is the fix, not the filter")

    -- the mask survives the cache round trip the repair writes it through
    local c = Scan.NewCache()
    Scan.Put(c, 22589, "Atiesh, Greatstaff of the Guardian", 5, 0, 0, true)   -- as 1.3.0 left it
    ck(select(6, Scan.Get(c, 22589)) == true, "before the repair, Atiesh is flagged unread")
    ck(Scan.UnreadIds(c)[1] == 22589, "…so the repair queue picks it up")
    Scan.Put(c, 22589, "Atiesh, Greatstaff of the Guardian", 5, mask, fac, false)
    local _, q2, m2, f2, i2, u2 = Scan.Get(c, 22589)
    ck(m2 == expect and q2 == 5 and f2 == Scan.FACTION_NONE,
       "after it, the cache holds the class lock the tooltip named")
    ck(u2 == false and i2 == false, "…flagged read, and never internal")
    ck(Scan.UnreadCount(c) == 0, "…and the repair queue is empty")
    -- and all four copies repair independently
    for _, id in ipairs({ 22589, 22630, 22631, 22632 }) do
        Scan.Put(c, id, "Atiesh, Greatstaff of the Guardian", 5, mask, fac, false)
    end
    local locked = 0
    for _, id in ipairs({ 22589, 22630, 22631, 22632 }) do
        if select(3, Scan.Get(c, id)) == expect then locked = locked + 1 end
    end
    ck(locked == 4, "all FOUR Atiesh ids in the owner's cache carry the lock (got " .. locked .. ")")

    -- ── 2. THE WIRING: a finished repair pushes the refresh ─────────────────
    local sh = io.open(P("itemScan.lua"), "r")
    ck(sh ~= nil, "itemScan.lua is readable")
    if sh then
        local s = sh:read("*a"); sh:close()
        local finish = s:find("function Addon:FinishItemScan")
        local push   = s:find("Addon%.RefreshGoalPicker")
        local invalid= s:find("Addon%.GoalItemDB, Addon%._goalDBStamp = nil, nil")
        ck(finish and invalid and invalid > finish,
           "FinishItemScan invalidates the picker index")
        ck(push and finish and push > finish,
           "THE FIX: …and then PUSHES the refresh into an open picker")
        ck(invalid and push and invalid < push,
           "…in that order, so the refresh rebuilds rather than re-reading the stale index")
        ck(s:find("cache%.restrictLocked%s*=%s*restricted") ~= nil,
           "the repair result is PERSISTED, not only printed")
        ck(s:find("cache%.restrictUnreadable%s*=%s*unread") ~= nil,
           "…both halves of it")
        -- the one-shot closes on a pass that started
        local start = s:find("local started = Addon:StartItemScan%({ repair = true }%)")
        local latch = s:find("Addon%._restrictRepairTried = true")
        ck(start ~= nil, "MaybeRepairRestrictions asks whether the pass actually started")
        ck(start and latch and latch > start,
           "THE FIX: …before burning the session's one attempt on it")
        local notice = s:find("re%-reading class restrictions for %%d cached items")
        ck(start and notice and notice > start,
           "…and before announcing a repair in chat")
        -- the tooltip retry is deferred, not spun
        ck(s:find("ST%.retry%[#ST%.retry %+ 1%] = id") ~= nil,
           "an unreadable tooltip is deferred to a later tick, not re-queued into this one")
        ck(s:find("ST%.queue%[#ST%.queue %+ 1%] = id\n%s*return true") == nil,
           "THE SPIN IS GONE: three tries no longer burn inside one frame")
        ck(s:find("and #ST%.retry == 0 then") ~= nil,
           "…and a deferred row keeps the pass from declaring itself finished")
    end
    local gh = io.open(P("goalPicker.lua"), "r")
    ck(gh ~= nil, "goalPicker.lua is readable")
    if gh then
        local g = gh:read("*a"); gh:close()
        ck(g:find("function Addon:RefreshGoalPicker%(preserveScroll%)") ~= nil,
           "the picker publishes the seam the scan pushes through")
        ck(g:find("if not picker:IsShown%(%) then return false end") ~= nil,
           "…which is a no-op when nothing is on screen")
        ck(g:find("picker:Requery%(preserveScroll ~= false%)") ~= nil,
           "…and re-filters, keeping the reader's scroll position by default")
        ck(g:find("Addon:MaybeRepairRestrictions") ~= nil,
           "the picker still triggers the repair when it opens")
    end

    -- ── 3. /darmory scanstatus: the state is QUERYABLE ──────────────────────
    ck(type(Scan.StatusReport) == "function", "Scan.StatusReport is published")
    local function joined(lines) return table.concat(lines or {}, "\n") end
    local function findLine(lines, prefix)
        for _, l in ipairs(lines or {}) do
            if l:sub(1, #prefix) == prefix then return l end
        end
    end

    local empty = Scan.StatusReport(nil, nil)
    ck(#empty == 1 and empty[1]:find("never run") ~= nil,
       "with no cache at all it says so in one line")
    ck(#Scan.StatusReport({}, nil) == 1, "…as it does for a table that is not a cache")

    -- a cache shaped like the owner's, mid-repair
    local rc = Scan.NewCache()
    Scan.Put(rc, 22589, "Atiesh, Greatstaff of the Guardian", 5, expect, 0, false)
    Scan.Put(rc, 22476, "Bonescythe Breastplate", 4, 0, 0, true)          -- still unread
    Scan.Put(rc, 22477, "Bonescythe Gauntlets",   4, 0, 0, true)          -- still unread
    Scan.Put(rc, 16963, "Nightslayer Chestpiece", 4, Scan.CLASS_BIT.ROGUE, 0, false)
    Scan.Put(rc, 13789, "[PH] Brilliant Dawn Cap", 1, 0, 0, false)        -- internal
    Scan.Put(rc, 12592, "Blackblade of Shahram",  4, 0, Scan.FACTION_HORDE, false)
    rc.scannedAt = 1785862751
    rc.build, rc.ranges = "68940", "1-32000"

    local idle = Scan.StatusReport(rc, nil)
    -- cache / restrictions / scan state / last scan / last repair / stamps
    ck(#idle == 6, "an idle report is six lines (got " .. #idle .. ")")
    local cacheLine = findLine(idle, "cache:")
    ck(cacheLine ~= nil, "…led by the cache line")
    ck(cacheLine and cacheLine:find("6 ids") ~= nil, "…which counts every row")
    ck(cacheLine and cacheLine:find("5 offerable") ~= nil, "…separating what the picker may offer")
    ck(cacheLine and cacheLine:find("1 internal") ~= nil, "…from what it hides")
    local restrictLine = findLine(idle, "restrictions:")
    ck(restrictLine and restrictLine:find("2 class%-locked") ~= nil,
       "the restriction line counts the class locks that ARE captured")
    ck(restrictLine and restrictLine:find("1 faction%-locked") ~= nil, "…and the faction locks")
    ck(restrictLine and restrictLine:find("2 still unread") ~= nil,
       "…and, crucially, how many rows the repair still owes")
    ck(findLine(idle, "scan: idle") ~= nil, "an idle scan says idle")
    ck(findLine(idle, "scan: idle"):find("repair pass is still owed") ~= nil,
       "…and says outright that a repair is outstanding, since 2 rows are unread")
    ck(findLine(idle, "last full scan:") ~= nil, "the last completed scan is stamped")
    ck(joined(idle):find("68940") ~= nil and joined(idle):find("1%-32000") ~= nil,
       "…with the build and the id range it covered")
    ck(findLine(idle, "last repair: never") ~= nil, "a cache never repaired says never")
    ck(findLine(idle, "stamps:") ~= nil, "and the three stamps are readable")
    ck(joined(idle):find("denylist " .. Scan.INTERNAL_STAMP) ~= nil, "…the denylist stamp")
    ck(joined(idle):find("capture " .. Scan.RESTRICT_STAMP) ~= nil, "…and the capture stamp")

    -- the same cache with a repair RUNNING over it
    local live = Scan.StatusReport(rc, { phase = "repair", cursor = 4120, total = 9241,
                                         percent = 44, found = 9241 })
    ck(findLine(live, "repair: RUNNING") ~= nil, "a running repair says RUNNING")
    ck(findLine(live, "repair: RUNNING"):find("4120 / 9241") ~= nil,
       "…with x / y, which is the question the chat line could not answer later")
    ck(findLine(live, "repair: RUNNING"):find("44%%") ~= nil, "…and a percentage")
    ck(findLine(live, "scan: idle") == nil, "…and does not also claim to be idle")
    local walking = Scan.StatusReport(rc, { phase = "instant", cursor = 8000, total = 32000,
                                            percent = 25, found = 3100 })
    ck(findLine(walking, "scan: RUNNING") ~= nil, "the id walk reports as a scan, not a repair")
    ck(findLine(walking, "scan: RUNNING"):find("3100 equippable") ~= nil,
       "…counting what it has found so far")
    local loading = Scan.StatusReport(rc, { phase = "resolve", cursor = 900, total = 9241,
                                            percent = 9 })
    ck(findLine(loading, "scan: RUNNING") ~= nil, "so does the item-loading phase")
    ck(findLine(loading, "scan: RUNNING"):find("900 / 9241") ~= nil, "…with its own x / y")

    -- a repaired cache reports the result the chat line used to carry away
    local done = Scan.NewCache()
    Scan.Put(done, 22589, "Atiesh, Greatstaff of the Guardian", 5, expect, 0, false)
    done.scannedAt = 1785862751
    done.restrictRepairedAt = 1785949151
    done.restrictLocked, done.restrictUnreadable = 1102, 37
    local drep = Scan.StatusReport(done, nil)
    local lastRepair = findLine(drep, "last repair:")
    ck(lastRepair ~= nil and lastRepair:find("never") == nil, "a repaired cache reports its repair")
    ck(lastRepair and lastRepair:find("1102 locked") ~= nil, "…how many rows it locked")
    ck(lastRepair and lastRepair:find("37 unreadable") ~= nil, "…and how many it could not read")
    ck(findLine(drep, "scan: idle") ~= nil and
       findLine(drep, "scan: idle"):find("still owed") == nil,
       "…and a fully-read cache does not claim a repair is outstanding")

    -- purity: no line carries a colour code or a nil
    for _, l in ipairs(idle) do
        ck(type(l) == "string" and l:find("|c") == nil and l:find("nil") == nil,
           "every status line is plain, complete text: " .. tostring(l))
    end

    -- the slash command really routes to it
    local sl = io.open(P("slash.lua"), "r")
    ck(sl ~= nil, "slash.lua is readable")
    if sl then
        local t = sl:read("*a"); sl:close()
        ck(t:find('cmd == "scanstatus"') ~= nil, "/darmory scanstatus is a command")
        ck(t:find("Scan%.StatusReport%(Addon:ItemScanCache%(%), Addon:ItemScanStatus%(%)%)") ~= nil,
           "…and prints exactly the report, over the live cache and the live scan state")
        ck(t:find("/darmory scanstatus") ~= nil, "…and is documented in the file's own header")
    end
end)

----------------------------------------------------------------------
-- AUTO-SCAN ARMING  (release verification N5)
--
-- Addon:InitItemScan is the login hook. It one-shots the first-run item scan behind a
-- 15s delay so the scan never competes with the login burst, and behind a marker
-- (cache.autoScanTried) so it does not nag.
--
-- The defect: the marker was stamped at LOGIN, before the timer was even armed. cache is
-- DaseekiArmoryScanDB — SavedVariables — so a logout, /reload or disconnect inside that
-- 15s window persisted "already tried" for a scan that never ran, and the auto path was
-- disarmed on that account for ever (IsComplete false + marker true => early return on
-- every subsequent login, silently).
--
-- These suites drive the real InitItemScan with a recording C_Timer, so the window can be
-- opened and abandoned the way a logout abandons it.
----------------------------------------------------------------------
local function newScanEnv()
    local A = {}
    local fnc, e = loadfile(P("itemScan.lua"))
    if not fnc then return nil, "compile: " .. tostring(e) end
    local okl, el = pcall(fnc, "Daseeki-Armory", A)
    if not okl then return nil, "load: " .. tostring(el) end

    local env = { addon = A, timers = {}, starts = 0, printed = {}, scanning = false }
    -- The chat/format helpers the notice uses, and the one call we must NOT let through:
    -- the real StartItemScan wants CreateFrame and GetTime. Its INVOCATION is what this
    -- suite is about, so a recorder is the faithful stand-in.
    A.Tag           = function() return "[Armory]" end
    A.Wrap          = function(_, _, s) return s end
    A.IsScanning    = function() return env.scanning end
    A.StartItemScan = function() env.starts = env.starts + 1; return true end
    return env
end

-- One login: bind the SavedVariables table, run the hook, collect whatever timer it armed.
-- Returns the number of timers armed by THIS login.
local function scanLogin(env, savedVars)
    local savedTimer, savedPrint, savedDB = _G.C_Timer, _G.print, _G.DaseekiArmoryScanDB
    local armed = 0
    _G.DaseekiArmoryScanDB = savedVars
    _G.C_Timer = { After = function(delay, cb)
        armed = armed + 1
        env.timers[#env.timers + 1] = { delay = delay, cb = cb }
    end }
    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        env.printed[#env.printed + 1] = table.concat(parts, " ")
    end
    local okc, errc = pcall(env.addon.InitItemScan, env.addon)
    _G.C_Timer, _G.print, _G.DaseekiArmoryScanDB = savedTimer, savedPrint, savedDB
    env.lastError = (not okc) and errc or nil
    return armed
end

-- Fire every armed timer (i.e. the player stayed logged in past the delay).
local function scanFireTimers(env, savedVars)
    local savedTimer, savedPrint, savedDB = _G.C_Timer, _G.print, _G.DaseekiArmoryScanDB
    _G.DaseekiArmoryScanDB = savedVars
    _G.C_Timer = { After = function() end }
    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        env.printed[#env.printed + 1] = table.concat(parts, " ")
    end
    local pending = env.timers
    env.timers = {}
    for _, t in ipairs(pending) do pcall(t.cb) end
    _G.C_Timer, _G.print, _G.DaseekiArmoryScanDB = savedTimer, savedPrint, savedDB
end

suite("item-scan-auto-arm", function(ck)
    if type(Scan) ~= "table" then ck(false, "itemScan.lua did not load"); return end

    -- ── 1. THE DEFECT: an early logout must not disarm the auto path ────────────
    -- Cache is the SavedVariables table, so the SAME table is carried across the
    -- simulated logouts below — that is exactly what persists to disk.
    local sv = Scan.NewCache()
    local e1 = newScanEnv()
    ck(e1 ~= nil, "a fresh itemScan environment loads with no WoW API")
    if not e1 then return end

    local armed1 = scanLogin(e1, sv)
    ck(e1.lastError == nil, "InitItemScan runs on an empty cache (" .. tostring(e1.lastError) .. ")")
    ck(armed1 == 1, "an empty cache arms exactly one delayed auto-scan (got " .. armed1 .. ")")
    ck(e1.timers[1] and e1.timers[1].delay == e1.addon.AUTO_SCAN_DELAY,
       "…at AUTO_SCAN_DELAY (" .. tostring(e1.addon.AUTO_SCAN_DELAY) .. "s), off the login burst")
    ck(sv.autoScanTried == nil,
       "THE FIX: nothing is written to SavedVariables merely by ARMING the timer")
    ck(e1.starts == 0, "…and no scan has started yet")
    ck(#e1.printed == 0, "…and the owner has not been told anything yet")

    -- LOGOUT inside the 15s window: the timer dies with the session, unfired.
    -- Next login gets a whole new addon environment, but the same saved cache.
    local e2 = newScanEnv()
    local armed2 = scanLogin(e2, sv)
    ck(armed2 == 1,
       "THE REGRESSION: after an early logout the NEXT login re-arms the auto-scan " ..
       "(got " .. armed2 .. " — 0 means the one-time scan is disarmed for ever)")
    ck(sv.autoScanTried == nil, "…and still nothing has been persisted")

    -- Three abandoned windows in a row still leave it armed: nothing latches until a
    -- scan actually runs.
    local armedN = 0
    for _ = 1, 3 do armedN = armedN + scanLogin(newScanEnv(), sv) end
    ck(armedN == 3, "…and it survives repeated early logouts (got " .. armedN .. " of 3)")
    ck(sv.autoScanTried == nil, "…with the marker still unset")

    -- ── 2. THE LATCH CLOSES WHEN THE SCAN ACTUALLY STARTS ──────────────────────
    scanFireTimers(e2, sv)
    ck(e2.starts == 1, "staying logged in past the delay starts the scan (got " .. e2.starts .. ")")
    ck(sv.autoScanTried == true, "…and THAT is what sets the marker")
    ck(#e2.printed == 1, "…with one first-run notice printed (got " .. #e2.printed .. ")")
    ck((e2.printed[1] or ""):find("first time") ~= nil and
       (e2.printed[1] or ""):find("Rescan Items") ~= nil,
       "…that says it runs once and names the manual way to redo it")

    -- ── 3. INTERRUPTED SCAN: started, never finished -> does NOT re-arm ─────────
    -- The marker is on disk and scannedAt is not, so the auto path stays quiet. This is
    -- deliberate: a scan that wedges the client must not restart itself every login.
    ck(Scan.IsComplete(sv) == false, "an interrupted scan is NOT a completed scan")
    local e3 = newScanEnv()
    local armed3 = scanLogin(e3, sv)
    ck(armed3 == 0, "a login after an interrupted scan does not auto-retry (got " .. armed3 .. ")")
    ck(e3.starts == 0, "…and starts nothing")

    -- ── 4. COMPLETION IS THE TERMINAL STATE ────────────────────────────────────
    -- FinishItemScan is the only writer of scannedAt/count, and it clears the marker so a
    -- later cache wipe re-arms the auto path. Source-asserted because reaching the real
    -- FinishItemScan needs a live scan (CreateFrame + GetTime).
    local fh = io.open(P("itemScan.lua"), "r")
    ck(fh ~= nil, "itemScan.lua is readable")
    if fh then
        local src = fh:read("*a"); fh:close()
        local finishAt = src:find("function Addon:FinishItemScan")
        local initAt   = src:find("function Addon:InitItemScan")
        local clearAt  = src:find("cache%.autoScanTried%s*=%s*nil")
        ck(finishAt ~= nil and clearAt ~= nil and clearAt > finishAt and clearAt < initAt,
           "FinishItemScan clears autoScanTried (a completed scan re-arms a future reset)")
        -- The regression this suite exists for, stated structurally: the marker must not
        -- be written in InitItemScan's own body before the timer is armed.
        local timerAt = src:find("C_Timer%.After%(Addon%.AUTO_SCAN_DELAY", initAt or 1)
        local setAt   = src:find("autoScanTried%s*=%s*true", initAt or 1)
        ck(timerAt ~= nil and setAt ~= nil and setAt > timerAt,
           "the marker is set INSIDE the delayed callback, not at login time")
        local startAt = src:find("Addon:StartItemScan%(%)", setAt or 1)
        ck(startAt ~= nil, "…immediately before the scan it is recording")
    end

    -- A completed cache never arms, marker or no marker.
    local done = Scan.NewCache()
    Scan.Put(done, 23709, "Corehound Belt", 3, 0, 0)
    done.scannedAt, done.autoScanTried = 1700000000, nil
    ck(Scan.IsComplete(done) == true, "a scanned, non-empty cache reads as complete")
    ck(scanLogin(newScanEnv(), done) == 0, "…and never arms the auto-scan again")

    -- …and a wipe of that completed cache re-arms it (the "future reset" path).
    local wiped = Scan.NewCache()
    ck(scanLogin(newScanEnv(), wiped) == 1, "a wiped cache arms the auto-scan afresh")

    -- ── 5. THE TIMER'S OWN GUARDS DO NOT BURN THE ONE-SHOT ─────────────────────
    -- Firing into a manual scan that is already running must leave the latch open, or a
    -- rescan the owner kicked off at login would eat the automatic first run.
    local sv5 = Scan.NewCache()
    local e5 = newScanEnv()
    ck(scanLogin(e5, sv5) == 1, "empty cache arms")
    e5.scanning = true
    scanFireTimers(e5, sv5)
    ck(e5.starts == 0, "the callback declines to start a second, overlapping scan")
    ck(sv5.autoScanTried == nil, "…and does NOT spend the one-shot marker doing so")
    e5.scanning = false
    ck(scanLogin(newScanEnv(), sv5) == 1, "…so the next login still arms it")
end)

----------------------------------------------------------------------
-- THE CAPTURE-STAMP RE-ARM  (1.3.1, the forcing bump)
--
-- THE SITUATION (owner's live /darmory scanstatus, capture stamp 1):
--     restrictions: 833 class-locked, 0 still unread
--     last repair:  11:06 — 0 locked, 0 unreadable
-- The first cut of the repair pass latched its one-shot before the pass had
-- started and burned all three tooltip tries inside a single frame. It therefore
-- SPENT the unread flags — the only record that a re-read was owed — without
-- writing back the locks they stood for. A cache in that state is indistinguishable,
-- to the fixed pipeline, from a cache that has nothing left to do: UnreadCount is
-- 0, so MaybeRepairRestrictions declines, silently, on every future login.
--
-- The flags cannot re-arm themselves. Scan.RESTRICT_STAMP is the one thing left
-- that can: Normalize re-flags every real row on a stamp mismatch, which is the
-- exact mechanism the 1.3.0 -> 1.3.1 migration used, so bumping the constant runs
-- round one again on machinery that now works.
--
-- This suite pins the re-arm on the three cache states an upgrader can be in.
----------------------------------------------------------------------
suite("item-scan-capture-restamp", function(ck)
    if type(Scan) ~= "table" then ck(false, "itemScan.lua did not load"); return end

    ck(Scan.RESTRICT_STAMP == 2,
       "the capture stamp has MOVED (got " .. tostring(Scan.RESTRICT_STAMP)
       .. ") — nothing below can re-arm a consumed cache without it")

    local ROGUE = Scan.CLASS_BIT.ROGUE
    local MAGE  = Scan.CLASS_BIT.MAGE + Scan.CLASS_BIT.PRIEST
                + Scan.CLASS_BIT.WARLOCK + Scan.CLASS_BIT.DRUID

    -- The owner's cache in miniature, written through the real codec: one row
    -- whose lock WAS read, one Atiesh whose lock was lost, one unrestricted row,
    -- one internal row. `stamp` is what the cache carries off disk; `atieshMask`
    -- is 0 for the consumed state and the true lock for the healthy one. Every
    -- row is flagged READ — that is the poisoning.
    local function ownerCache(stamp, atieshMask)
        local c = Scan.NewCache()
        Scan.Put(c, 16905, "Bloodfang Chestpiece",              4, ROGUE, 0, false)
        Scan.Put(c, 22589, "Atiesh, Greatstaff of the Guardian", 5, atieshMask or 0, 0, false)
        Scan.Put(c, 9425,  "Pendulum of Doom",                   4, 0, 0, false)
        Scan.Put(c, 13789, "[PH] Brilliant Dawn Cap",            1, 0, 0, false)   -- internal
        c.scannedAt          = 1785862751
        c.restrictStamp      = stamp
        c.restrictRepairedAt = 1785899160          -- the 11:06 line on his report
        c.restrictLocked, c.restrictUnreadable = 0, 0
        return c
    end

    -- ── THE POISONED STATE, stated exactly ──────────────────────────────────
    -- On the CURRENT stamp a consumed cache is dead to the repair. This is not a
    -- defect in Normalize or in MaybeRepairRestrictions — both are behaving —
    -- it is why the constant had to move.
    local dead = ownerCache(Scan.RESTRICT_STAMP, 0)
    ck(Scan.UnreadCount(dead) == 0, "a consumed cache believes nothing is owed")
    local deadN = Scan.Normalize(dead)
    ck(deadN.unreadCount == 0,
       "…and a login on the SAME stamp re-flags nothing — the debt is unrecoverable from the flags")
    ck(#Scan.UnreadIds(deadN) == 0, "…so the repair queue is empty and no pass can start")
    ck(select(3, Scan.Get(deadN, 22589)) == 0,
       "…while Atiesh still carries no class lock: the picker keeps offering it to a warrior")

    -- ── (a) THE POISONED CACHE, re-armed by the bump ────────────────────────
    local poisoned = ownerCache(1, 0)                      -- off disk on the OLD stamp
    ck(poisoned.restrictStamp ~= Scan.RESTRICT_STAMP, "(a) the poisoned cache is on the old capture stamp")
    local a = Scan.Normalize(poisoned)
    ck(a.restrictStamp == Scan.RESTRICT_STAMP, "(a) the login migration re-stamps it to the current capture")
    ck(a.unreadCount == 3,
       "…having re-flagged every REAL row unread (got " .. tostring(a.unreadCount) .. " of 3)")
    ck(select(6, Scan.Get(a, 13789)) == false,
       "…and left the internal row out of it: nothing ever asks it for a class lock")
    ck(a.count == 4, "…keeping every row (no rescan is demanded of him)")
    ck(select(3, Scan.Get(a, 16905)) == ROGUE,
       "…and preserving the locks it DID hold — the migration rewrites the flag bit, not the mask")
    local q = Scan.UnreadIds(a)
    ck(#q == 3 and q[1] == 9425 and q[2] == 16905 and q[3] == 22589,
       "…so the repair queue is the three real rows, in id order")

    -- ── (b) A HEALTHY e145ecb REPAIR: one redundant re-read, no loss ────────
    local healthy = ownerCache(1, MAGE)                    -- its repair DID land the locks
    local b = Scan.Normalize(healthy)
    ck(b.unreadCount == 3,
       "(b) a cache whose repair was HEALTHY is re-queued too — one redundant re-read is the price")
    ck(select(3, Scan.Get(b, 22589)) == MAGE,
       "…but it carries its correct locks through the migration untouched")
    ck(select(3, Scan.Get(b, 16905)) == ROGUE, "…every one of them")
    -- and that is what makes the redundant pass harmless: the picker is right the
    -- whole time it runs, so the owner sees no regression while it re-reads
    local warrior = { class = "WARRIOR", classBit = Scan.CLASS_BIT.WARRIOR,
                      faction = Scan.FACTION_NONE, showUnusable = false }
    local row = { id = 22589, name = "atiesh", display = "Atiesh",
                  equipLoc = "INVTYPE_2HWEAPON",
                  classID = Scan.ITEM_CLASS_WEAPON, subclassID = 10,
                  classMask = select(3, Scan.Get(b, 22589)), faction = Scan.FACTION_NONE }
    ck(Scan.Matches(row, "", { INVTYPE_2HWEAPON = true }, warrior) == false,
       "…so a warrior's list still drops Atiesh WHILE the redundant pass is running")

    -- ── (c) A CACHE WRITTEN BY THIS BUILD IS NEVER RE-FLAGGED ───────────────
    local fresh = Scan.NewCache()
    Scan.Put(fresh, 16905, "Bloodfang Chestpiece", 4, ROGUE, 0, false)
    Scan.Put(fresh, 22589, "Atiesh, Greatstaff of the Guardian", 5, MAGE, 0, false)
    fresh.scannedAt = 1785999999
    ck(fresh.restrictStamp == Scan.RESTRICT_STAMP, "(c) a cache built by THIS build carries the current stamp")
    local cN = Scan.Normalize(fresh)
    ck(cN.unreadCount == 0, "…so the next login re-flags nothing")
    ck(Scan.UnreadCount(cN) == 0, "…and owes no repair pass at all")
    ck(select(3, Scan.Get(cN, 22589)) == MAGE, "…with the locks its own tooltips read left alone")
    -- a genuine failure inside that scan is still owed, and only it
    Scan.Put(cN, 9425, "Pendulum of Doom", 4, 0, 0, true)
    local cN2 = Scan.Normalize(cN)
    ck(cN2.unreadCount == 1 and Scan.UnreadIds(cN2)[1] == 9425,
       "…while a row whose tooltip genuinely refused is queued, and it alone")

    ----------------------------------------------------------------------
    -- BEHAVIOURAL: drive the real login -> picker-open path, all three states.
    -- itemScan.lua touches the WoW API only from inside functions, so the whole
    -- pipeline runs headlessly against stubs. The scan RUNNER is never ticked —
    -- what is under test is which passes start, and what gets stamped.
    ----------------------------------------------------------------------
    local function scanEnv()
        local A = {}
        local fnc, e = loadfile(P("itemScan.lua"))
        if not fnc then return nil, "compile: " .. tostring(e) end
        local okl, el = pcall(fnc, "Daseeki-Armory", A)
        if not okl then return nil, "load: " .. tostring(el) end
        A.Tag  = function() return "[Armory]" end
        A.Wrap = function(_, _, s) return s end
        return A
    end

    local NIL  = {}
    local KEYS = { "CreateFrame", "GetTime", "GetBuildInfo", "time", "UnitClass",
                   "print", "UIParent", "C_Item", "DaseekiArmoryScanDB" }
    local function withStubs(fn)
        local saved = {}
        for _, k in ipairs(KEYS) do
            local v = _G[k]
            saved[k] = (v == nil) and NIL or v
        end
        local frame = {}
        function frame:Hide() end
        function frame:Show() end
        function frame:SetScript() end
        function frame:RegisterEvent() end
        function frame:UnregisterAllEvents() end
        _G.CreateFrame   = function() return frame end
        _G.GetTime       = function() return 1000 end
        _G.GetBuildInfo  = function() return "1.15.7", "60111" end
        _G.time          = function() return 1786000000 end
        _G.UnitClass     = function() return "Warrior", "WARRIOR" end
        _G.UIParent      = frame
        _G.C_Item        = nil
        _G.print         = function() end
        local packed = { pcall(fn) }
        for _, k in ipairs(KEYS) do
            local v = saved[k]
            _G[k] = (v ~= NIL) and v or nil
        end
        return unpack(packed)
    end

    -- (a) poisoned cache: login normalises it, the picker's call starts a pass
    local A1 = scanEnv()
    ck(A1 ~= nil, "a headless itemScan environment loads with no WoW API present")
    if A1 then
        local sv = ownerCache(1, 0)
        local ok, started, queued, owed = withStubs(function()
            _G.DaseekiArmoryScanDB = sv
            A1:ItemScanCache()                       -- LOGIN: the migration runs here
            local n = Scan.UnreadCount(sv)
            local s = A1:MaybeRepairRestrictions()   -- PICKER OPEN
            local st = A1:ItemScanStatus()
            A1:StopItemScan()
            return s, st and st.total or -1, n
        end)
        ck(ok == true, "(a) the poisoned cache drives the real login->picker path (" .. tostring(started) .. ")")
        ck(owed == 3, "(a) login leaves three rows owed again (got " .. tostring(owed) .. ")")
        ck(started == true, "(a) THE FORCING FIX: a repair pass starts on the owner's own cache state")
        ck(queued == 3, "…queued with exactly the re-flagged rows (got " .. tostring(queued) .. ")")
        ck(sv.restrictStamp == Scan.RESTRICT_STAMP, "…and the cache is on the new stamp on disk")
    end

    -- the counterfactual: the SAME cache already on the current stamp starts nothing
    local A0 = scanEnv()
    if A0 then
        local sv0 = ownerCache(Scan.RESTRICT_STAMP, 0)
        local ok0, started0 = withStubs(function()
            _G.DaseekiArmoryScanDB = sv0
            A0:ItemScanCache()
            local s = A0:MaybeRepairRestrictions()
            A0:StopItemScan()
            return s
        end)
        ck(ok0 == true, "the counterfactual runs")
        ck(started0 == false,
           "WITHOUT the bump the same consumed cache starts nothing — that is the bug being forced open")
    end

    -- (b) healthy cache: one pass, and its locks are intact going into it
    local A2 = scanEnv()
    if A2 then
        local sv2 = ownerCache(1, MAGE)
        local ok2, started2, mask = withStubs(function()
            _G.DaseekiArmoryScanDB = sv2
            A2:ItemScanCache()
            local s = A2:MaybeRepairRestrictions()
            A2:StopItemScan()
            return s, select(3, Scan.Get(sv2, 22589))
        end)
        ck(ok2 == true, "(b) the healthy cache drives the same path")
        ck(started2 == true, "(b) …and pays one redundant re-read (accepted, not a defect)")
        ck(mask == MAGE, "…with every lock it already held still in the cache")
    end

    -- (c) a FULL rescan finishing under this build stamps itself, and is not
    --     followed by a repair — the owner's manual rescan must be the end of it
    local A3 = scanEnv()
    if A3 then
        local sv3 = Scan.NewCache()
        sv3.restrictStamp = 1                        -- it began life poisoned
        local ok3, stamp, scanned, unread, after = withStubs(function()
            _G.DaseekiArmoryScanDB = sv3
            local cache = A3:ItemScanCache()         -- login: re-flagged (nothing in it yet)
            A3:StartItemScan()                       -- the owner's Rescan Items
            Scan.Put(cache, 16905, "Bloodfang Chestpiece", 4, ROGUE, 0, false)
            Scan.Put(cache, 22589, "Atiesh, Greatstaff of the Guardian", 5, MAGE, 0, false)
            A3:FinishItemScan()                      -- …runs to completion
            local s = A3:MaybeRepairRestrictions()   -- picker opens afterwards
            A3:StopItemScan()
            return cache.restrictStamp, cache.scannedAt, cache.unreadCount, s
        end)
        ck(ok3 == true, "(c) a full scan runs to completion headlessly (" .. tostring(stamp) .. ")")
        ck(stamp == Scan.RESTRICT_STAMP,
           "(c) FinishItemScan stamps a COMPLETED FULL SCAN with the current capture (got "
           .. tostring(stamp) .. ")")
        ck(scanned == 1786000000, "…and marks it complete")
        ck(unread == 0, "…with nothing left unread — its own tooltips were read")
        ck(after == false,
           "(c) …so his manual rescan is NOT followed by a pointless repair pass")
        ck(Scan.Normalize(sv3).unreadCount == 0, "…and the NEXT login re-flags nothing either")
    end

    -- and the repair path stamps too, so a completed repair is terminal
    local A4 = scanEnv()
    if A4 then
        local sv4 = ownerCache(1, 0)
        local ok4, stamp4, repaired, unread4 = withStubs(function()
            _G.DaseekiArmoryScanDB = sv4
            local cache = A4:ItemScanCache()
            A4:MaybeRepairRestrictions()
            for _, id in ipairs({ 9425, 16905, 22589 }) do          -- the pass reads them
                local nm, qq = Scan.Get(cache, id)
                Scan.Put(cache, id, nm, qq, id == 22589 and MAGE or 0, 0, false)
            end
            A4:FinishItemScan()
            return cache.restrictStamp, cache.restrictRepairedAt, cache.unreadCount
        end)
        ck(ok4 == true, "a finished repair pass runs headlessly")
        ck(stamp4 == Scan.RESTRICT_STAMP, "…and carries the current capture stamp")
        ck(repaired == 1786000000, "…records when it ran")
        ck(unread4 == 0, "…and leaves nothing owed")
        ck(sv4.restrictLocked == 1 and sv4.restrictUnreadable == 0,
           "…with the result persisted for /darmory scanstatus to read back")
        ck(Scan.Normalize(sv4).unreadCount == 0, "…so the next login does not repeat it")
    end

    -- ── source contract: the comparison is against the CONSTANT ─────────────
    local fh = io.open(P("itemScan.lua"), "r")
    ck(fh ~= nil, "itemScan.lua is readable")
    if fh then
        local s = fh:read("*a"); fh:close()
        ck(s:find("Scan%.RESTRICT_STAMP%s*=%s*2") ~= nil,
           "the capture constant is at 2 in the source")
        ck(s:find("cache%.restrictStamp%s*~=%s*Scan%.RESTRICT_STAMP") ~= nil,
           "Normalize compares against the CONSTANT, so the next bump needs one edit and no other")
        ck(s:find("restrictStamp%s*~=%s*1") == nil and s:find("restrictStamp%s*==%s*1") == nil,
           "…and nothing anywhere tests the stamp against a literal")
        ck(s:find("if reread%s+then unflag = not flag end") ~= nil,
           "a stamp mismatch re-flags every non-internal row unread")
        ck(s:find("cache%.unreadCount%s*=%s*unread%s*\n%s*cache%.restrictStamp%s*=%s*Scan%.RESTRICT_STAMP") ~= nil,
           "FinishItemScan stamps in the UNCONDITIONAL recount block, so a full scan records it too")
    end
end)

----------------------------------------------------------------------
-- A FAILED RE-READ MAY NOT ERASE A LOCK IT DID NOT READ  (1.3.1)
--
-- THE DEFECT (pre-existing, found while reviewing the capture-stamp bump):
-- recordItem wrote Scan.Put(…, classMask, faction, not read) unconditionally, and
-- Scan.ReadRestrictions answers a tooltip that did not build with
-- 0, FACTION_NONE, false. So a row whose RE-READ failed had its previously-good
-- mask overwritten with 0 — correctly flagged unread, but with the evidence gone.
--
-- That matters because the pass most likely to hit it is the redundant one: a
-- capture-stamp bump re-queues EVERY real row (state (b) of
-- item-scan-capture-restamp), so a single transient tooltip failure over a
-- healthy row downgrades good data, and Atiesh is back in a warrior's list until
-- some later session happens to read it again.
--
-- Failing OPEN on an unreadable tooltip is policy and is unchanged. Destroying
-- what an earlier read already established is not.
----------------------------------------------------------------------
suite("item-scan-mask-preserve", function(ck)
    if type(Scan) ~= "table" then ck(false, "itemScan.lua did not load"); return end

    local ROGUE   = Scan.CLASS_BIT.ROGUE
    local WARRIOR = Scan.CLASS_BIT.WARRIOR
    local MAGE    = Scan.CLASS_BIT.MAGE

    -- ── 1. THE PRIMITIVE: Scan.Put's precedence, case by case ───────────────
    local c = Scan.NewCache()
    Scan.Put(c, 16905, "Bloodfang Chestpiece", 4, ROGUE, 0, false)   -- a tooltip that BUILT
    ck(select(3, Scan.Get(c, 16905)) == ROGUE, "the row starts with the lock its tooltip named")

    -- good mask + FAILED re-read: the mask survives, the row goes unread
    Scan.Put(c, 16905, "Bloodfang Chestpiece", 4, 0, 0, true)
    local nm, q, m, _, _, u = Scan.Get(c, 16905)
    ck(m == ROGUE, "THE FIX: a failed re-read does NOT overwrite the stored class lock")
    ck(u == true, "…while the row IS flagged unread, so the repair pass still owes it a look")
    ck(q == 4 and nm == "Bloodfang Chestpiece", "…and name / quality are written as before")
    ck(Scan.UnreadIds(c)[1] == 16905, "…so it is queued for the next pass, not written off")

    -- good mask + a re-read that SUCCEEDS with a different answer: updated
    Scan.Put(c, 16905, "Bloodfang Chestpiece", 4, MAGE, 0, false)
    ck(select(3, Scan.Get(c, 16905)) == MAGE, "a successful re-read replaces the stored lock")
    ck(select(6, Scan.Get(c, 16905)) == false, "…and clears the unread flag")

    -- a READ write of 0 is EVIDENCE, and may still clear a lock
    Scan.Put(c, 16905, "Bloodfang Chestpiece", 4, 0, 0, false)
    ck(select(3, Scan.Get(c, 16905)) == 0,
       "a tooltip that built and named no class clears the lock — a finding, not a gap")

    -- no prior data + failed read: zeros and unread, exactly as 1.3.1 already did
    Scan.Put(c, 22476, "Bonescythe Breastplate", 4, 0, 0, true)
    local _, _, m2, f2, _, u2 = Scan.Get(c, 22476)
    ck(m2 == 0 and f2 == Scan.FACTION_NONE and u2 == true,
       "a row with nothing stored still lands 0 / FACTION_NONE / unread (fail-open, unchanged)")

    -- the faction lock is preserved on the same rule, independently of the mask
    Scan.Put(c, 12592, "Blackblade of Shahram", 4, 0, Scan.FACTION_HORDE, false)
    Scan.Put(c, 12592, "Blackblade of Shahram", 4, 0, 0, true)
    ck(select(4, Scan.Get(c, 12592)) == Scan.FACTION_HORDE,
       "…and a failed re-read does not erase a stored FACTION lock either")
    ck(select(6, Scan.Get(c, 12592)) == true, "…which is still flagged for the repair pass")

    -- an UNREAD write that nonetheless carries a value still wins
    Scan.Put(c, 9425, "Pendulum of Doom", 4, 0, 0, false)
    Scan.Put(c, 9425, "Pendulum of Doom", 4, ROGUE, 0, true)
    ck(select(3, Scan.Get(c, 9425)) == ROGUE,
       "evidence is evidence: an unread write that DOES carry a mask is not thrown away")

    -- the bookkeeping still adds up after all of that
    local n = Scan.Normalize(c)
    ck(n.count == 4, "the cache still holds its four rows")
    ck(n.unreadCount == 3, "…with three of them owed a re-read (got " .. tostring(n.unreadCount) .. ")")

    ----------------------------------------------------------------------
    -- 2. BEHAVIOURAL: drive the REAL repair pass over a REAL refusing tooltip.
    -- itemScan.lua touches the WoW API only from inside functions, so the whole
    -- recorder — StartItemScan, ScanTick, recordItem, tooltipLines,
    -- ReadRestrictions, Scan.Put, FinishItemScan — runs headlessly against stubs.
    ----------------------------------------------------------------------
    local function scanEnv()
        local A = {}
        local fnc = loadfile(P("itemScan.lua"))
        if not fnc then return nil end
        local okl = pcall(fnc, "Daseeki-Armory", A)
        if not okl then return nil end
        A.Tag  = function() return "[Armory]" end
        A.Wrap = function(_, _, s) return s end
        A.SLOT_INVTYPES = { chest = { INVTYPE_ROBE = true } }
        return A
    end

    local NAMES = { [16905] = "Bloodfang Chestpiece", [9425] = "Pendulum of Doom" }
    local NIL   = {}
    local KEYS  = { "CreateFrame", "GetTime", "GetBuildInfo", "time", "UnitClass",
                    "print", "UIParent", "C_Item", "C_CreatureInfo", "GetItemInfo",
                    "GetItemInfoInstant", "LOCALIZED_CLASS_NAMES_MALE",
                    "LOCALIZED_CLASS_NAMES_FEMALE", "ITEM_CLASSES_ALLOWED",
                    "DaseekiArmoryScanDB" }
    for i = 1, 8 do KEYS[#KEYS + 1] = "DaseekiArmoryItemScanTipTextLeft" .. i end

    -- The hidden scanning tooltip, driven exactly as itemScan.lua drives it:
    -- SetItemByID publishes the line font-strings under the tooltip's global name
    -- and NumLines reports what is there. tipLines = nil IS the defect's own
    -- condition — a tooltip that does not build at all.
    local tipLines
    local function withStubs(fn)
        local saved = {}
        for _, k in ipairs(KEYS) do
            local v = _G[k]; saved[k] = (v == nil) and NIL or v
        end
        local frame = {}
        function frame:Hide() end
        function frame:Show() end
        function frame:SetScript() end
        function frame:RegisterEvent() end
        function frame:UnregisterAllEvents() end
        function frame:SetOwner() end
        function frame:ClearLines() end
        function frame:SetItemByID()
            for i = 1, 8 do _G["DaseekiArmoryItemScanTipTextLeft" .. i] = nil end
            for i, txt in ipairs(tipLines or {}) do
                local t = txt
                _G["DaseekiArmoryItemScanTipTextLeft" .. i] = { GetText = function() return t end }
            end
        end
        function frame:NumLines() return tipLines and #tipLines or 0 end
        _G.CreateFrame        = function() return frame end
        _G.GetTime            = function() return 1000 end
        _G.GetBuildInfo       = function() return "1.15.7", "60111" end
        _G.time               = function() return 1786000000 end
        _G.UnitClass          = function() return "Warrior", "WARRIOR" end
        _G.UIParent           = frame
        _G.C_Item             = nil
        _G.C_CreatureInfo     = nil
        _G.print              = function() end
        _G.LOCALIZED_CLASS_NAMES_MALE   = { ROGUE = "Rogue", WARRIOR = "Warrior", MAGE = "Mage" }
        _G.LOCALIZED_CLASS_NAMES_FEMALE = nil
        _G.ITEM_CLASSES_ALLOWED = "Classes: %s"
        _G.GetItemInfo        = function(id) return NAMES[id] or "Corehound Belt", nil, 4 end
        _G.GetItemInfoInstant = function(id) return id, nil, nil, "INVTYPE_ROBE", 12345 end
        local packed = { pcall(fn) }
        for _, k in ipairs(KEYS) do
            local v = saved[k]; _G[k] = (v ~= NIL) and v or nil
        end
        return unpack(packed)
    end

    local function runToIdle(A)
        local t = 0
        while A:IsScanning() and t < 40 do A:ScanTick(1); t = t + 1 end
        A:StopItemScan()
        return t
    end

    -- ── (a) the redundant pass over a HEALTHY row whose tooltip refuses ──────
    local A1 = scanEnv()
    ck(A1 ~= nil, "a headless itemScan environment loads with no WoW API present")
    if A1 then
        local sv = Scan.NewCache()
        Scan.Put(sv, 16905, "Bloodfang Chestpiece", 4, ROGUE, 0, false)
        sv.scannedAt     = 1785862751
        sv.restrictStamp = 1              -- off disk on the old stamp: re-queued
        tipLines = nil                    -- …and no tooltip builds this session
        local ok, owed, ticks = withStubs(function()
            _G.DaseekiArmoryScanDB = sv
            A1:ItemScanCache()                       -- LOGIN: re-flags, keeps the mask
            local n = Scan.UnreadCount(sv)
            A1:StartItemScan({ repair = true })      -- PICKER OPEN: the redundant pass
            return n, runToIdle(A1)
        end)
        ck(ok == true, "(a) the repair pass runs headlessly over a refusing tooltip")
        ck(owed == 1, "(a) login leaves the healthy row owed a re-read (got " .. tostring(owed) .. ")")
        ck(ticks == Scan.TOOLTIP_TRIES,
           "…and it costs one tick per try, never all three inside one frame (got "
           .. tostring(ticks) .. ")")
        ck(select(3, Scan.Get(sv, 16905)) == ROGUE,
           "(a) THE FIX, END TO END: three failed tooltip builds leave the class lock standing")
        ck(select(6, Scan.Get(sv, 16905)) == true,
           "…with the row still flagged unread, so a later session tries again")
        ck(sv.restrictLocked == 1,
           "…and the pass reports the lock as still held (got " .. tostring(sv.restrictLocked) .. ")")
        ck(sv.restrictUnreadable == 1, "…alongside the read it could not make")
        ck(sv.unreadCount == 1, "…so exactly one row remains owed on disk")
    end

    -- ── (b) the same pass with a tooltip that DOES build, saying something new ─
    local A2 = scanEnv()
    if A2 then
        local sv2 = Scan.NewCache()
        Scan.Put(sv2, 16905, "Bloodfang Chestpiece", 4, ROGUE, 0, false)
        sv2.scannedAt     = 1785862751
        sv2.restrictStamp = 1
        tipLines = { "Bloodfang Chestpiece", "Binds when picked up", "Chest", "Leather",
                     "Classes: Warrior" }
        local ok2 = withStubs(function()
            _G.DaseekiArmoryScanDB = sv2
            A2:ItemScanCache()
            A2:StartItemScan({ repair = true })
            return runToIdle(A2)
        end)
        ck(ok2 == true, "(b) the same pass runs against a tooltip that builds")
        ck(select(3, Scan.Get(sv2, 16905)) == WARRIOR,
           "(b) a successful re-read OVERWRITES the stored lock with what it read (got "
           .. tostring(select(3, Scan.Get(sv2, 16905))) .. ")")
        ck(select(6, Scan.Get(sv2, 16905)) == false, "…and the row is no longer owed")
        ck(sv2.unreadCount == 0, "…so the cache owes nothing at all")
    end

    -- ── (c) PHASE 2's FIRST read of an id: no prior data, behaviour unchanged ─
    local A3 = scanEnv()
    if A3 then
        A3.ItemScan.RANGES = { { 9425, 9426 } }   -- a two-id id space: phase 1 is instant
        local sv3 = Scan.NewCache()
        tipLines = nil                            -- every tooltip refuses
        local ok3 = withStubs(function()
            _G.DaseekiArmoryScanDB = sv3
            A3:ItemScanCache()
            A3:StartItemScan()                    -- a FULL scan, not a repair
            return runToIdle(A3)
        end)
        ck(ok3 == true, "(c) a full scan runs over a two-id space")
        ck(sv3.count == 2, "…recording both ids the walk found (got " .. tostring(sv3.count) .. ")")
        local _, _, m3, f3, _, u3 = Scan.Get(sv3, 9425)
        ck(m3 == 0 and f3 == Scan.FACTION_NONE and u3 == true,
           "(c) a first read has nothing to preserve, so it still lands 0 / FACTION_NONE / unread")
        ck(sv3.unreadCount == 2, "…and both rows are owed the repair pass")
    end

    -- ── the rule lives in the primitive, so every writer inherits it ─────────
    local fh = io.open(P("itemScan.lua"), "r")
    ck(fh ~= nil, "itemScan.lua is readable")
    if fh then
        local s = fh:read("*a"); fh:close()
        ck(s:find("A WRITE THAT CARRIES NO EVIDENCE MAY NOT ERASE EVIDENCE") ~= nil,
           "the precedence is stated where the code enforces it")
        local put = s:find("function Scan%.Put")
        local rec = s:find("Scan%.Put%(ST%.cache")
        ck(put ~= nil and rec ~= nil and rec > put,
           "…and the scan's one and only writer goes through it")
    end
end)

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
