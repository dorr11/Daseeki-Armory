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
