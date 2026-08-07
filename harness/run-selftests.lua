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
--
-- BOTH SHIPPED DATA FILES ARE LOADED FIRST, into the SAME Addon table, exactly as
-- the TOC orders them. That is deliberate: the filter reads
-- Addon.StaticRestrictions and the index reads Addon.StaticCatalogRaw, so a
-- harness that stubbed either would be testing a different program. ScanAddon is
-- that Addon table, published so the suites can read the shipped data itself.
----------------------------------------------------------------------
local Scan, ScanAddon
do
    local A = {}
    ScanAddon = A
    local cf, cerr = loadfile(P("catalog.lua"))
    if cf then pcall(cf, "Daseeki-Armory", A) end
    ScanAddon._catalogLoadError = (not cf) and tostring(cerr) or nil
    local rf, rerr = loadfile(P("restrictions.lua"))
    if rf then pcall(rf, "Daseeki-Armory", A) end
    ScanAddon._restrictionsLoadError = (not rf) and tostring(rerr) or nil
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
    ck(Scan.RECORD_BUDGET > 0, "per-tick record writing is budgeted")
    ck(Scan.TOOLTIP_BUDGET == nil and Scan.TOOLTIP_TRIES == nil and Scan.DATA_TRIES == nil,
       "the tooltip / data-gate ceilings are gone with the machinery that needed them")
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
-- THE LOCK LOOKUP  (1.3.1)
--
-- Era does not return class or faction locks from GetItemInfo, which is why
-- 1.3.0 read them off a hidden tooltip and why four generations of machinery grew
-- around making that read trustworthy. They are shipped data now, and the whole
-- runtime mechanism is this: pack, unpack, one table lookup.
----------------------------------------------------------------------
suite("static-restrictions-codec", function(ck)
    if type(Scan) ~= "table" then ck(false, "itemScan.lua did not load"); return end
    local B = Scan.CLASS_BIT

    ck(ScanAddon._restrictionsLoadError == nil,
       "restrictions.lua compiles: " .. tostring(ScanAddon._restrictionsLoadError))
    ck(type(ScanAddon.StaticRestrictions) == "table", "…and publishes Addon.StaticRestrictions")
    ck(type(ScanAddon.StaticUnobtainable) == "table", "…and Addon.StaticUnobtainable")

    -- ── pack / unpack ───────────────────────────────────────────────────────
    local function trip(m, f)
        local a, b = Scan.UnpackStatic(Scan.PackStatic(m, f))
        return a == m and b == f
    end
    ck(trip(0, 0), "the empty lock round-trips")
    ck(trip(B.MAGE, Scan.FACTION_NONE), "a single-class lock round-trips")
    ck(trip(B.DRUID + B.MAGE + B.PRIEST + B.WARLOCK, 0), "a multi-class lock round-trips")
    ck(trip(0, Scan.FACTION_HORDE), "a bare faction lock round-trips")
    ck(trip(B.WARRIOR, Scan.FACTION_ALLIANCE), "both axes at once round-trip")
    ck(trip(4095, 3), "the top of every field round-trips")
    local allOK = true
    for _, m in ipairs({ 0, 1, 2, 4, 8, 16, 64, 128, 256, 1024, 1503, 4095 }) do
        for f = 0, 3 do if not trip(m, f) then allOK = false end end
    end
    ck(allOK, "every (mask x faction) combination in play round-trips exactly")
    ck(Scan.PackStatic(nil, nil) == 0, "nil fields pack as zero")
    ck(select(1, Scan.UnpackStatic(nil)) == 0, "unpacking nil yields zeros")
    ck(Scan.PackStatic(99999, 9) == Scan.PackStatic(4095, 3), "out-of-range fields clamp")
    ck(Scan.PackStatic(-1, -1) == 0, "negative fields clamp to zero")
    ck(Scan.STATIC_SHIFT == 4096, "the faction field starts above the 12-bit class mask")

    -- ── the lookup, including the fail-open gap ─────────────────────────────
    local m, f = Scan.StaticFor(22476)                    -- Bonescythe Breastplate
    ck(m == B.ROGUE and f == Scan.FACTION_NONE, "a shipped id answers with its lock")
    m, f = Scan.StaticFor(99999999)
    ck(m == 0 and f == Scan.FACTION_NONE,
       "AN ABSENT ID IS UNRESTRICTED — the fail-open rule, unchanged")
    m = Scan.StaticFor(nil)
    ck(m == 0, "a nil id is unrestricted rather than an error")
    m = Scan.StaticFor("22476")
    ck(m == B.ROGUE, "a numeric-string id is coerced (SavedVariables keys are strings)")
    ck(Scan.IsUnobtainable(nil) == false, "a nil id is not unobtainable")
    ck(Scan.IsUnobtainable(99999999) == false, "…nor is an id nobody listed")

    -- ── the gap is a DATA gap, and it is silent ─────────────────────────────
    -- The point of the release: a missing lock is now the same missing lock for
    -- everyone, fixable by regenerating one file. Nothing about it is per-account,
    -- and nothing anywhere reports a debt, because there is no debt to report.
    ck(Scan.UnreadIds == nil and Scan.UnreadCount == nil,
       "there is no 'rows still owed' surface left to consult")
    ck(Scan.RepairGate == nil and Scan.TrustRead == nil,
       "…and no gate deciding whether a re-read may run")
    ck(Scan.ParseRestrictions == nil and Scan.ReadRestrictions == nil,
       "…and no tooltip parser at all")
    ck(Scan.CLASS_UNKNOWN == nil,
       "…and no unknown-class bit: a table cannot fail to recognise its own tokens")

    -- ── PROFICIENCY IS STILL A MECHANISM, NOT DATA ──────────────────────────
    -- Librams / Idols / Totems are armour subclasses 7 / 8 / 9. They are not in
    -- the shipped table, and they must not be: exactly one class is proficient
    -- with each, numerically and locale-free.
    local relics = { [7] = "PALADIN", [8] = "DRUID", [9] = "SHAMAN" }
    for sub, owner in pairs(relics) do
        local n = 0
        for class, prof in pairs(Scan.PROF) do
            if prof.armor[sub] then
                n = n + 1
                ck(class == owner,
                   "armour subclass " .. sub .. " is " .. owner .. "'s alone (saw " .. class .. ")")
            end
        end
        ck(n == 1, "…and exactly one class has it")
    end
end)

----------------------------------------------------------------------
-- THE FILTER RULE TABLE, one case PER RULE, plus a mutation-adequacy gate.
--
-- The predicate is now an ordered rule table (Scan.RULES / Scan.RowVerdict) and
-- the ORDER is the contract: the two "not a real item" rules sit ABOVE "Show
-- unusable", the three restriction rules sit below it. RowVerdict returns the
-- name of the rule that decided, so every rule is asserted by name and by verdict
-- rather than by a verdict that could have come from anywhere.
--
-- EVERY LOCK HERE COMES OUT OF THE SHIPPED TABLE. The rows carry ids, not masks —
-- that is the architecture — so these are real ids with their real, shipped locks:
--
--   22476  Bonescythe Breastplate   rogue-locked leather (the headline symptom)
--   22589  Atiesh                   a caster-locked staff
--   22416  Dreadnaught Breastplate  warrior-locked plate
--    4964  Goblin Smasher           the one FACTION lock in the owner's evidence
--   19019  Thunderfury              a real, obtainable, unrestricted legendary
--   18583  Warglaive of Azzinoth    real, and unobtainable by history
----------------------------------------------------------------------
suite("item-scan-filter-matrix", function(ck)
    if type(Scan) ~= "table" then ck(false, "itemScan.lua did not load"); return end
    local B = Scan.CLASS_BIT
    local WEAPON, ARMOR = Scan.ITEM_CLASS_WEAPON, Scan.ITEM_CLASS_ARMOR

    local function viewer(class, faction, showUnusable)
        return { class = class, classBit = B[class] or 0, faction = faction or 0,
                 showUnusable = showUnusable and true or false }
    end
    local hordeWarrior = viewer("WARRIOR", Scan.FACTION_HORDE)
    local allyWarrior  = viewer("WARRIOR", Scan.FACTION_ALLIANCE)
    local hordeMage    = viewer("MAGE",    Scan.FACTION_HORDE)
    local hordeRogue   = viewer("ROGUE",   Scan.FACTION_HORDE)
    local shown        = viewer("WARRIOR", Scan.FACTION_HORDE, true)

    -- ── rows: an id, an item class and a subclass. No masks. ────────────────
    local function row(id, classID, subclassID, internal)
        return { id = id, classID = classID, subclassID = subclassID, internal = internal }
    end
    local plainCloak  = row(19019, ARMOR,  0)      -- unrestricted, universal subclass
    local plateChest  = row(12640, ARMOR,  4)      -- Lionheart Helm: plate, unrestricted
    local clothRobe   = row(18486, ARMOR,  1)      -- Mooncloth Robe: cloth, unrestricted
    local wand        = row(11287, WEAPON, 19)     -- Lesser Magic Wand: unrestricted
    local bonescythe  = row(22476, ARMOR,  2)      -- ROGUE, leather
    local dreadnaught = row(22416, ARMOR,  4)      -- WARRIOR, plate
    local atieshRow   = row(22589, WEAPON, 10)     -- a caster class, staff
    local factionRow  = row(4964,  WEAPON, 5)      -- Goblin Smasher: HORDE
    local glaive      = row(18583, WEAPON, 7)      -- unobtainable by history
    local placeholder = row(13794, ARMOR,  1, true)  -- "[PH] Shining Dawn Coif"

    -- the fixtures must actually carry the locks this suite is about, or every
    -- verdict below would be vacuously true
    ck(select(1, Scan.StaticFor(22476)) == B.ROGUE, "fixture check: 22476 is rogue-locked")
    ck(select(1, Scan.StaticFor(22416)) == B.WARRIOR, "fixture check: 22416 is warrior-locked")
    ck(select(2, Scan.StaticFor(4964)) == Scan.FACTION_HORDE, "fixture check: 4964 is Horde-locked")
    ck(select(1, Scan.StaticFor(19019)) == 0, "fixture check: Thunderfury carries no lock")
    ck(Scan.IsUnobtainable(18583) == true, "fixture check: 18583 is unobtainable by history")

    local U, V = Scan.Usable, Scan.RowVerdict

    -- ── ONE CASE PER RULE, asserted by the rule that fired ──────────────────
    local known = {}
    for _, r in ipairs(Scan.RULES or {}) do known[r] = true end
    ck(#Scan.RULES == 9, "the rule table is published and has nine rules")

    local ok1, r1 = V("not a row", hordeWarrior)
    ck(ok1 == false and r1 == "no-row", "RULE no-row: a non-table is hidden")
    ck(known[r1], "…and names a rule that is in the published table")

    local ok2, r2 = V(placeholder, hordeMage)
    ck(ok2 == false and r2 == "not-an-item",
       "RULE not-an-item: Blizzard's own placeholder is hidden")
    local ok2b, r2b = V(placeholder, shown)
    ck(ok2b == false and r2b == "not-an-item",
       "ADVERSARIAL: …and 'Show unusable' cannot reveal it — the rule sits ABOVE that one")

    local ok3, r3 = V(glaive, hordeWarrior)
    ck(ok3 == false and r3 == "unobtainable",
       "RULE unobtainable: a Warglaive is a real item nobody can get, so it is hidden")
    local ok3b, r3b = V(glaive, shown)
    ck(ok3b == false and r3b == "unobtainable",
       "ADVERSARIAL: …and 'Show unusable' cannot reveal it either")

    local ok4, r4 = V(plainCloak, nil)
    ck(ok4 == true and r4 == "no-context", "RULE no-context: with no viewer, nothing is filtered")

    local ok5, r5 = V(bonescythe, shown)
    ck(ok5 == true and r5 == "show-unusable",
       "ADVERSARIAL: id IS in the table + 'Show unusable' -> shown, and that is the rule that decided")

    local ok6, r6 = V(bonescythe, hordeWarrior)
    ck(ok6 == false and r6 == "class",
       "RULE class: THE HEADLINE SYMPTOM — rogue-only Bonescythe is hidden from a warrior")

    local ok7, r7 = V(factionRow, allyWarrior)
    ck(ok7 == false and r7 == "faction",
       "RULE faction: a Horde-locked weapon is hidden from an Alliance character")

    local ok8, r8 = V(wand, hordeWarrior)
    ck(ok8 == false and r8 == "proficiency",
       "RULE proficiency: a warrior cannot use a wand, and no table entry says so")

    local ok9, r9 = V(plainCloak, hordeWarrior)
    ck(ok9 == true and r9 == "usable", "RULE usable: nothing objected")

    local okA, rA = V(row(999999999, ARMOR, 0), hordeWarrior)
    ck(okA == true and rA == "usable",
       "ADVERSARIAL: an id the table has never heard of is SHOWN (fail-open, unchanged)")

    -- ── the verdicts themselves, as a matrix ────────────────────────────────
    ck(U(plainCloak, hordeWarrior) == true, "an unrestricted cloak shows for everyone")
    ck(U(plainCloak, hordeMage)    == true, "...including a cloth wearer")
    ck(U(plainCloak, hordeRogue)   == true, "armor subclass 0 (cloaks/rings/necks/trinkets) is universal")

    ck(U(atieshRow, hordeWarrior) == false, "Atiesh is HIDDEN from a warrior")
    ck(U(bonescythe, hordeRogue)  == true,  "a rogue set piece shows for a rogue")
    ck(U(bonescythe, hordeWarrior) == false, "...and is hidden from a warrior")
    ck(U(dreadnaught, hordeWarrior) == true, "a warrior set piece shows for a warrior")
    ck(U(dreadnaught, hordeMage)    == false, "...and is hidden from a mage")

    ck(U(factionRow, hordeWarrior) == true,  "a Horde-locked item shows for Horde")
    ck(U(factionRow, allyWarrior)  == false, "...and is hidden from Alliance")

    ck(U(plateChest, hordeWarrior) == true,  "a warrior can wear plate")
    ck(U(plateChest, hordeMage)    == false, "a mage cannot")
    ck(U(clothRobe,  hordeMage)    == true,  "a mage can wear cloth")
    ck(U(clothRobe,  hordeWarrior) == true,  "a warrior can also wear cloth (no downgrade lock)")
    ck(U(wand, hordeMage)    == true,  "a mage can use a wand")
    ck(U(wand, hordeRogue)   == false, "nor can a rogue")

    ck(U(atieshRow, shown)  == true, "'show unusable' reveals class-locked items")
    ck(U(factionRow, viewer("WARRIOR", Scan.FACTION_ALLIANCE, true)) == true,
       "...and opposite-faction items")
    ck(U(wand, shown) == true, "...and items the class has no proficiency for")

    ck(U(nil, hordeWarrior) == false, "a nil record is never usable")
    ck(U(plainCloak, nil)   == true,  "with no viewer context nothing is filtered")
    ck(U(bonescythe, viewer("NOTACLASS", 0)) == true,
       "an unknown viewer class filters nothing rather than hiding everything")
    ck(U(row(19019, ARMOR, 99), hordeWarrior) == false,
       "an armor subclass no class knows is treated as unusable")
    ck(U(row(19019, 15, 99), hordeWarrior) == true,
       "a non-armor / non-weapon item class is not proficiency-gated")

    -- ── MUTATION ADEQUACY ───────────────────────────────────────────────────
    -- Each mutant is a plausible WRONG implementation of the rule table — a rule
    -- dropped, a rule inverted, or two rules swapped in precedence. The fixture
    -- set above must distinguish every one of them, or a regression of that exact
    -- shape would ship green.
    local fixtures = {
        { plainCloak, hordeWarrior }, { plainCloak, hordeMage },
        { atieshRow, hordeMage },     { atieshRow, hordeWarrior },
        { bonescythe, hordeRogue },   { bonescythe, hordeWarrior },
        { dreadnaught, hordeWarrior },{ dreadnaught, hordeMage },
        { factionRow, hordeWarrior }, { factionRow, allyWarrior },
        { plateChest, hordeWarrior }, { plateChest, hordeMage },
        { wand, hordeMage },          { wand, hordeWarrior },
        { glaive, hordeWarrior },     { glaive, shown },
        { placeholder, hordeMage },   { placeholder, shown },
        { atieshRow, shown },         { bonescythe, shown },   { wand, shown },
        { row(999999999, ARMOR, 0), hordeWarrior },
    }
    local hasBit = Scan.HasBit
    local function profOK(rec, ctx)
        local prof = ctx.class and Scan.PROF[ctx.class]
        if not (prof and rec.classID) then return true end
        if rec.classID == ARMOR  and not prof.armor[rec.subclassID]  then return false end
        if rec.classID == WEAPON and not prof.weapon[rec.subclassID] then return false end
        return true
    end
    local MUTANTS = {
        ["R1 class lock ignored"] = function(rec, ctx)
            if rec.internal or Scan.IsUnobtainable(rec.id) then return false end
            if ctx.showUnusable then return true end
            local _, f = Scan.StaticFor(rec.id)
            if f ~= 0 and (ctx.faction or 0) ~= 0 and f ~= ctx.faction then return false end
            return profOK(rec, ctx)
        end,
        ["R2 class test inverted"] = function(rec, ctx)
            if rec.internal or Scan.IsUnobtainable(rec.id) then return false end
            if ctx.showUnusable then return true end
            local m = Scan.StaticFor(rec.id)
            if m > 0 and hasBit(m, ctx.classBit) then return false end
            return true
        end,
        ["R3 faction lock ignored"] = function(rec, ctx)
            if rec.internal or Scan.IsUnobtainable(rec.id) then return false end
            if ctx.showUnusable then return true end
            local m = Scan.StaticFor(rec.id)
            if m > 0 and (ctx.classBit or 0) > 0 and not hasBit(m, ctx.classBit) then return false end
            return profOK(rec, ctx)
        end,
        ["R4 faction test inverted"] = function(rec, ctx)
            if rec.internal or Scan.IsUnobtainable(rec.id) then return false end
            if ctx.showUnusable then return true end
            local _, f = Scan.StaticFor(rec.id)
            if f ~= 0 and f == (ctx.faction or 0) then return false end
            return true
        end,
        ["R5 an absent id is treated as LOCKED (fail-closed)"] = function(rec, ctx)
            if rec.internal or Scan.IsUnobtainable(rec.id) then return false end
            if ctx.showUnusable then return true end
            local m = Scan.StaticFor(rec.id)
            if not hasBit(m, ctx.classBit) then return false end
            return profOK(rec, ctx)
        end,
        ["R6 show-unusable inverted"] = function(rec, ctx)
            local c2 = {}
            for k, v in pairs(ctx) do c2[k] = v end
            c2.showUnusable = not ctx.showUnusable
            return Scan.Usable(rec, c2)
        end,
        ["R7 proficiency ignored"] = function(rec, ctx)
            if rec.internal or Scan.IsUnobtainable(rec.id) then return false end
            if ctx.showUnusable then return true end
            local m, f = Scan.StaticFor(rec.id)
            if m > 0 and (ctx.classBit or 0) > 0 and not hasBit(m, ctx.classBit) then return false end
            if f ~= 0 and (ctx.faction or 0) ~= 0 and f ~= ctx.faction then return false end
            return true
        end,
        ["R8 unobtainable rule dropped"] = function(rec, ctx)
            if rec.internal then return false end
            if ctx.showUnusable then return true end
            local m, f = Scan.StaticFor(rec.id)
            if m > 0 and (ctx.classBit or 0) > 0 and not hasBit(m, ctx.classBit) then return false end
            if f ~= 0 and (ctx.faction or 0) ~= 0 and f ~= ctx.faction then return false end
            return profOK(rec, ctx)
        end,
        ["R9 internal rule dropped"] = function(rec, ctx)
            if Scan.IsUnobtainable(rec.id) then return false end
            if ctx.showUnusable then return true end
            local m, f = Scan.StaticFor(rec.id)
            if m > 0 and (ctx.classBit or 0) > 0 and not hasBit(m, ctx.classBit) then return false end
            if f ~= 0 and (ctx.faction or 0) ~= 0 and f ~= ctx.faction then return false end
            return profOK(rec, ctx)
        end,
        ["R10 PRECEDENCE: show-unusable placed above the not-real rules"] = function(rec, ctx)
            if ctx.showUnusable then return true end
            if rec.internal or Scan.IsUnobtainable(rec.id) then return false end
            local m, f = Scan.StaticFor(rec.id)
            if m > 0 and (ctx.classBit or 0) > 0 and not hasBit(m, ctx.classBit) then return false end
            if f ~= 0 and (ctx.faction or 0) ~= 0 and f ~= ctx.faction then return false end
            return profOK(rec, ctx)
        end,
    }
    local names = {}
    for k in pairs(MUTANTS) do names[#names + 1] = k end
    table.sort(names)
    for _, name in ipairs(names) do
        local mut, killed = MUTANTS[name], false
        for _, fx in ipairs(fixtures) do
            local real = Scan.Usable(fx[1], fx[2])
            local okm, got = pcall(mut, fx[1], fx[2])
            if not okm or (got and true or false) ~= real then killed = true; break end
        end
        ck(killed, "mutation killed: " .. name)
    end
end)

----------------------------------------------------------------------
-- CACHE ROUND-TRIP: pack/unpack, Put/Get, and a real SavedVariables
-- serialize -> reload cycle (the cache's whole job is to survive a logout).
--
-- THE CACHE GOT SMALLER (1.3.1). It used to carry a classMask, a faction and a
-- restrictions-UNREAD flag per row, plus a capture stamp and a repair tally on the
-- cache itself. The locks are shipped now, so a row is a name, a quality and the
-- denylist verdict — and the layout change is handled by LEAVING THE HOLE where
-- the restriction bits were, so a cache written by any earlier 1.3.x build reads
-- back with its quality and its internal flag intact and needs no migration.
----------------------------------------------------------------------
suite("item-scan-cache-roundtrip", function(ck)
    if type(Scan) ~= "table" then ck(false, "itemScan.lua did not load"); return end

    -- ── the packed meta field ───────────────────────────────────────────────
    local function trip(q, i)
        local a, b = Scan.UnpackMeta(Scan.PackMeta(q, i))
        return a == q and b == i
    end
    ck(trip(0, false), "the all-zero record round-trips")
    ck(trip(4, false), "an epic round-trips")
    ck(trip(5, true),  "a legendary flagged internal round-trips")
    ck(trip(15, true), "the top of the quality field round-trips")
    local allOK = true
    for q = 0, 15 do
        for _, i in ipairs({ true, false }) do if not trip(q, i) then allOK = false end end
    end
    ck(allOK, "every (quality x internal) combination round-trips exactly")
    ck(Scan.PackMeta(nil, nil) == 0, "nil fields pack as zero")
    ck(select(1, Scan.UnpackMeta(nil)) == 0, "unpacking nil yields zeros")
    ck(Scan.PackMeta(99, false) == Scan.PackMeta(15, false), "an out-of-range quality clamps")
    ck(Scan.PackMeta(-4, false) == 0, "a negative quality clamps to zero")
    ck(Scan.PackMeta(4, false) < 2^24, "a packed record stays a small integer")

    -- ── LAYOUT COMPATIBILITY: a legacy word still decodes ───────────────────
    -- This is a real 1.3.1 meta word: quality 4, classMask ROGUE(8), faction 0,
    -- internal set. The restriction bits in the middle must be SKIPPED, not
    -- misread as part of the quality or the flag.
    local legacy = 4 + 8 * 16 + 1 * 65536 + 262144        -- q4 | mask 8 | faction 1 | internal
    local lq, li = Scan.UnpackMeta(legacy)
    ck(lq == 4, "a legacy meta word still yields its quality")
    ck(li == true, "…and its internal flag, from the same bit it always used")
    local legacyNoFlag = 4 + 8 * 16 + 1 * 65536
    ck(select(2, Scan.UnpackMeta(legacyNoFlag)) == false,
       "…and a legacy word without the flag does not acquire one from the dead bits")
    ck(select(1, Scan.UnpackMeta(524288 + 4)) == 4,
       "…nor does the retired UNREAD bit disturb the quality")

    -- ── Put / Get ───────────────────────────────────────────────────────────
    local c = Scan.NewCache()
    ck(c.version == Scan.CACHE_VERSION and c.count == 0, "a fresh cache is empty and versioned")
    ck(c.unreadCount == nil and c.restrictStamp == nil,
       "a fresh cache carries no restriction bookkeeping at all")
    ck(Scan.IsComplete(c) == false, "a fresh cache is not a completed scan")
    ck(Scan.Put(c, 23709, "Corehound Belt", 3) == true, "Put accepts a record")
    ck(c.count == 1, "count tracks the insert")
    ck(Scan.Put(c, 22589, "Atiesh, Greatstaff of the Guardian", 5) == true, "second record")
    ck(c.count == 2, "count tracks the second insert")
    ck(Scan.Put(c, 23709, "Corehound Belt", 3) == true, "re-Put of a known id succeeds")
    ck(c.count == 2, "...without double counting")
    ck(Scan.Put(c, nil, "x") == false, "Put rejects a nil id")
    ck(Scan.Put(c, 5, nil) == false, "Put rejects a nil name")
    ck(Scan.Put(c, 5, "") == false, "Put rejects an empty name")
    ck(Scan.Put(nil, 5, "x") == false, "Put rejects a nil cache")
    ck(c.count == 2, "rejected Puts do not move the count")

    local nm, q, internal = Scan.Get(c, 22589)
    ck(nm == "Atiesh, Greatstaff of the Guardian", "Get returns the name")
    ck(q == 5, "...the quality")
    ck(internal == false, "...and the denylist verdict, which is all a row holds now")
    ck(Scan.Get(c, 999999) == nil, "an unscanned id reads back nil")
    ck(Scan.Get(nil, 1) == nil, "a nil cache reads back nil")
    ck(Scan.Get(c, "22589") ~= nil, "a numeric-string id is coerced (SavedVariables keys)")
    -- the flag is DERIVED, so a caller cannot disagree with the denylist
    Scan.Put(c, 13789, "[PH] Brilliant Dawn Cap", 1)
    ck(select(3, Scan.Get(c, 13789)) == true, "an internal name is flagged by Put itself")

    -- ── SavedVariables serialize -> reload ──────────────────────────────────
    Scan.Put(c, 16542, "Warlord's Iron-Breastplate", 4)
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
        ck(reloaded.count == 4, "the reloaded cache recounts its entries")
        ck(Scan.IsComplete(reloaded) == true, "a reloaded completed scan reads as complete")
        local n2, q2, i2 = Scan.Get(reloaded, 16542)
        ck(n2 == "Warlord's Iron-Breastplate", "the apostrophe survives the round trip")
        ck(q2 == 4 and i2 == false, "quality and the denylist verdict survive a logout")
        ck(reloaded.scannedAt == 1754200000 and reloaded.build == "1.15.9.68808",
           "the scan stamp survives")
        ck(reloaded.internalCount == 1, "…and the internal tally is rebuilt from the rows")
        -- and the predicate still answers correctly off the reloaded record, taking
        -- the lock from the SHIPPED table rather than from the row
        local rec = { id = 22589, classID = Scan.ITEM_CLASS_WEAPON, subclassID = 10 }
        ck(Scan.Usable(rec, { class = "WARRIOR", classBit = Scan.CLASS_BIT.WARRIOR }) == false,
           "a reloaded Atiesh row is still hidden from a warrior — the lock never lived in the cache")
    end

    -- ── A REAL PRE-1.3.1 CACHE MIGRATES WITHOUT CEREMONY ────────────────────
    -- Shaped exactly as the owner's SavedVariables were left: restriction bits in
    -- the meta words, a capture stamp, an unread tally, a repair timestamp.
    local old = {
        version = Scan.CACHE_VERSION,
        names = { [22476] = "Bonescythe Breastplate", [13789] = "[PH] Brilliant Dawn Cap" },
        meta  = { [22476] = 4 + 8 * 16, [13789] = 1 + 262144 },
        count = 2, internalCount = 1, internalStamp = Scan.INTERNAL_STAMP,
        unreadCount = 9240, restrictStamp = 3,
        restrictRepairedAt = 1785872625, restrictLocked = 834, restrictUnreadable = 0,
        repairBlocked = "this session's repair pass already ran",
        scannedAt = 1785862751,
    }
    local mig = Scan.Normalize(old)
    ck(mig.count == 2, "an old cache is kept, not discarded — its names are still good")
    ck(select(2, Scan.Get(mig, 22476)) == 4, "…its qualities read back")
    ck(select(3, Scan.Get(mig, 13789)) == true, "…and its internal flags read back")
    ck(mig.unreadCount == nil and mig.restrictStamp == nil,
       "…while the restriction bookkeeping is dropped from the cache")
    ck(mig.restrictRepairedAt == nil and mig.restrictLocked == nil
       and mig.restrictUnreadable == nil and mig.repairBlocked == nil,
       "…all of it, so nothing on disk can claim a pass is owed")
    ck(mig.meta[22476] == 4 + 8 * 16,
       "…and the dead restriction bits are left INERT rather than rewritten: "
       .. "nothing reads them, so erasing them would be a pointless full-table write")
    -- the row is still filtered correctly, because the lock comes from elsewhere
    ck(Scan.Usable({ id = 22476, classID = Scan.ITEM_CLASS_ARMOR, subclassID = 2 },
                   { class = "WARRIOR", classBit = Scan.CLASS_BIT.WARRIOR }) == false,
       "THE MIGRATION IS A NO-OP THAT FIXES THE BUG: Bonescythe is hidden from a warrior "
       .. "on the owner's existing cache, with no rescan and no repair")

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
    local q, i = Scan.UnpackMeta(Scan.PackMeta(4, true))
    ck(q == 4 and i == true, "the internal bit round-trips alongside the quality")
    ck(select(2, Scan.UnpackMeta(Scan.PackMeta(15, false))) == false,
       "…and a full record with the bit clear reads back clear")
    ck(Scan.PackMeta(15, true) < 2 ^ 24, "a packed record is still a small integer")
    ck(select(2, Scan.UnpackMeta(Scan.PackMeta(4))) == false,
       "an omitted flag means 'not internal'")
    -- and a LEGACY word, restriction bits and all, still lands on the same answer
    ck(select(2, Scan.UnpackMeta(1 + Scan.CLASS_BIT.MAGE * 16 + 1 * 65536 + 262144)) == true,
       "a pre-1.3.1 meta word keeps its flag: the dead restriction bits are skipped, not shifted")

    local c = Scan.NewCache()
    ck(c.internalStamp == Scan.INTERNAL_STAMP, "a fresh cache carries the current denylist stamp")
    Scan.Put(c, 19162, "Corehound Belt", 3)
    Scan.Put(c, 13789, "[PH] Brilliant Dawn Cap", 1)
    ck(select(3, Scan.Get(c, 13789)) == true, "Put DERIVES the internal flag from the name")
    ck(select(3, Scan.Get(c, 19162)) == false, "…and leaves a real item unflagged")
    ck(c.count == 2, "internal rows stay IN the cache (a rescan must not re-fight them)")

    -- ── a 1.3.0 cache is UPGRADED IN PLACE, never discarded ─────────────────
    -- The bit did not exist in 1.3.0, so every meta value read back with it clear.
    -- Normalize must re-derive rather than demand a minute-long rescan.
    local old = {
        version = Scan.CACHE_VERSION,
        names = { [13789] = "[PH] Brilliant Dawn Cap", [19162] = "Corehound Belt",
                  [9425] = "Pendulum of Doom", [11342] = "Monster - Axe, 2H Pendulum of Doom" },
        meta  = { [13789] = 1, [19162] = 3, [9425] = 4, [11342] = 1 },
        count = 4, scannedAt = 1754200000,
    }
    ck(old.internalStamp == nil, "…the 1.3.0 cache has no denylist stamp")
    local up = Scan.Normalize(old)
    ck(up.count == 4, "the upgrade keeps every row (no rescan is demanded)")
    ck(up.internalStamp == Scan.INTERNAL_STAMP, "…and stamps the denylist it was derived with")
    ck(up.internalCount == 2, "…having flagged exactly the two internal rows")
    ck(select(3, Scan.Get(up, 13789)) == true and select(3, Scan.Get(up, 11342)) == true,
       "the placeholder and the creature record are flagged on the way in")
    ck(select(3, Scan.Get(up, 19162)) == false and select(3, Scan.Get(up, 9425)) == false,
       "…and the real items are not")
    ck(select(2, Scan.Get(up, 9425)) == 4, "the re-derive preserves quality")

    -- an already-stamped cache is left alone (the pass is idempotent and one-shot)
    up.meta[19162] = Scan.PackMeta(3, true)     -- a lie, deliberately planted
    local again = Scan.Normalize(up)
    ck(select(3, Scan.Get(again, 19162)) == true,
       "a cache already on the current stamp is NOT re-derived (the pass runs once)")
    again.internalStamp = "some-older-stamp"
    again = Scan.Normalize(again)
    ck(select(3, Scan.Get(again, 19162)) == false,
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
    -- Real ids, so the usability half of the predicate reads the SHIPPED locks
    -- rather than a mask this fixture made up. 999999 is deliberately an id the
    -- shipped table has never heard of.
    local function row(id, name, loc, subclass)
        return { id = id, name = name:lower(), display = name, equipLoc = loc or "INVTYPE_HEAD",
                 classID = Scan.ITEM_CLASS_ARMOR, subclassID = subclass or 4 }
    end
    local helm  = row(12640, "Lionheart Helm")               -- unrestricted plate
    local coif  = row(16963, "Helm of Wrath")                -- warrior-locked plate
    local robe  = row(19145, "Robe of Volatile Power", "INVTYPE_ROBE", 1)
    local mageOnly = row(16795, "Arcanist Crown", "INVTYPE_HEAD", 1)   -- MAGE in the table
    ck(select(1, Scan.StaticFor(16795)) == Scan.CLASS_BIT.MAGE,
       "fixture check: the Arcanist Crown really is mage-locked in the shipped table")

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
    local plus = row(999999, "Test Defense Ring +120")
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
        -- THE INDEX BUILDER NO LONGER FILTERS INTERNAL ROWS, and that is correct:
        -- dev/gen-catalog.lua applied the denylist at generation time, so there is
        -- not one internal row in catalog.lua for the builder to drop. A filter
        -- here would be a second mechanism for a decision already made.
        ck(s:find("if internal then return end") == nil,
           "the index builder has no internal filter — the catalog ships without them")
        ck(s:find("Scan%.CatalogEach") ~= nil, "…because it builds from the shipped catalog")
        ck(s:find("Scan%.Matches") ~= nil, "the row filter runs the shared predicate")
        ck(s:find("Scan%.NormalizeQuery") ~= nil, "…over a normalised query")
        ck(s:find("internalStamp") == nil,
           "no denylist stamp in the index key: shipped data cannot change mid-session")
        ck(s:find("Addon:ItemScanCache") == nil,
           "…and the picker never touches the retired scan cache")
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
    -- THE PICKER HAS NO SCAN CONTROL AT ALL (1.3.1). "Rescan Items", its
    -- "Scanning…" label, the progress poll and the "(unscanned)" suffix are gone
    -- with the scan they described. The footer is one checkbox.
    --
    -- These look for CODE, not for the words. The comments above each removal say
    -- what used to be there and why it went, deliberately — a deletion nobody can
    -- read the reason for gets reinstated by the next person. So the assertions
    -- name the constructs: the button field, its factory call, the sync function,
    -- the suffix variable, and any call into the runner.
    ck(src:find("StartItemScan") == nil, "the picker cannot start a scan")
    ck(src:find("f%.rescan") == nil, "…there is no rescan button on the frame")
    ck(src:find('makeButton%(f, "Rescan') == nil, "…and nothing builds one")
    ck(src:find("function f:SyncScanUI") == nil, "…no scan-UI sync function survives")
    ck(src:find("function f:ShowScanProgress") == nil, "…nor a progress readout")
    ck(src:find("function f:ScanFinished") == nil, "…nor a scan-finished handler")
    ck(src:find("local suffix") == nil, "…and the count line has no suffix to append")
    ck(src:find("Addon:IsScanning") == nil, "…the picker never asks whether a scan is running")
    ck(src:find("showUnusable") ~= nil, "…and exposes the show-unusable escape hatch")
    -- The cap must come after the sort, or "highest ilvl first" is a lie on big
    -- result sets. Both now live inside Rows.SortAndCap, which is what makes the
    -- order testable rather than merely readable — so the ordering is asserted
    -- there (see the legendary-sweep suite) and what is pinned here is that
    -- `filtered` has no order of its own left to get wrong.
    local fs, ss = src:find("table%.sort%(list"), src:find("for i = #list, MAX_RESULTS")
    ck(fs ~= nil and ss ~= nil and ss > fs, "results are capped AFTER the sort, not before")
    ck(src:find("function Rows%.SortAndCap") ~= nil,
       "…and the order is a published, pure function rather than a local in the filter")
    ck(src:find("return Rows%.SortAndCap%(out, ilvlOf, qualityOf%)") ~= nil,
       "…which `filtered` hands the item level AND the quality, so a cold client still ranks")
    local sortCount = 0
    for _ in src:gmatch("table%.sort%(") do sortCount = sortCount + 1 end
    ck(sortCount == 1, "there is exactly ONE ordering in the picker (found " .. sortCount .. ")")

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
    -- The external door (Addon:RefreshGoalPicker) preserves too. It used to be
    -- called by FinishItemScan; no scan reaches a player now, so what it pins is
    -- the general "something changed" path, not a scan seam.
    ck(src:find("picker:Requery%(preserveScroll ~= false%)") ~= nil,
       "…and so does an externally requested re-filter")
    ck(src:find("picker:Requery%(%)\n%s*end%)\n%s*search:SetScript%(\"OnEscapePressed") ~= nil,
       "…while typing in the search box goes back to the top")
    ck(src:find("if picker then picker:Requery%(%) end") ~= nil,
       "…as does toggling Show unusable")
    ck(src:find("f\\.search:SetText%(\"\"%)\n%s*f:Requery%(%)") ~= nil
       or src:find('f%.search:SetText%(""%)\r?\n%s*f:Requery%(%)') ~= nil,
       "…and as does opening the picker, which now goes straight from clearing "
       .. "the search box to the query with no scan-UI sync in between")
end)

----------------------------------------------------------------------
-- THE CATALOG IS THE PICKER'S ONLY SOURCE  (1.3.1)
--
-- WHAT THIS SUITE REPLACED, and why the replacement is smaller. It used to be
-- "THE SEED MAY NOT OVERRIDE THE CLIENT": a precedence suite guarding a rule that
-- three name sources had to obey, written after a real defect (owner screenshot)
-- in which the picker offered "Enchant Cloak - Resistance" — the name of an
-- enchantment EFFECT. That row reached the list because goalPicker's `add`
-- returned on an internal row BEFORE recording that the id had been dealt with,
-- so the bundled AtlasLoot seed got to name it on the next pass: id 13794 is
-- "[PH] Shining Dawn Coif" in the client and "Enchant Cloak - Resistance" in the
-- seed, and 37 ids in the owner's cache were resurrecting like that.
--
-- There is one source now, so that whole class of defect is unreachable: a seed
-- cannot contradict the client when there is no seed, and an internal row cannot
-- be handed back when the catalog was generated without one. The suite that
-- remains proves the new shape rather than policing the old rule — including,
-- directly against the shipped file, that the defect's own fixture ids are simply
-- not in it.
----------------------------------------------------------------------
suite("goal-picker-catalog-source", function(ck)
    if type(Scan) ~= "table" then ck(false, "itemScan.lua did not load"); return end

    -- ── THE PARSER, on fixtures ─────────────────────────────────────────────
    ck(type(Scan.CatalogEach) == "function", "the catalog reader is published as Scan.CatalogEach")
    ck(type(Scan.CatalogCount) == "function", "…with a count that needs no parse")

    local function collect(raw)
        local out, order = {}, {}
        local n = Scan.CatalogEach(function(id, name, q)
            out[id] = { name = name, q = q }; order[#order + 1] = id
        end, raw)
        return out, n, order
    end

    local got, n, order = collect("25 1 Worn Shortsword\n19019 5 Thunderfury, Blessed Blade of the Windseeker\n12640 4 Lionheart Helm")
    ck(n == 3, "three records parse from three lines (got " .. tostring(n) .. ")")
    ck(got[25] and got[25].name == "Worn Shortsword" and got[25].q == 1, "id, quality and name all arrive")
    ck(got[19019] and got[19019].name == "Thunderfury, Blessed Blade of the Windseeker",
       "a name with commas and spaces survives — the name runs to end of line")
    ck(order[1] == 25 and order[2] == 19019 and order[3] == 12640,
       "…in file order, which the generator writes ascending")

    -- CRLF: catalog.lua is written into a CRLF working tree, so this is not a
    -- hypothetical. A reader that split on "\n" alone would hand every name back
    -- with a trailing carriage return — invisible in a diff, wrong in the picker,
    -- and wrong only on Windows.
    local crlf = collect("25 1 Worn Shortsword\r\n19019 5 Thunderfury\r\n")
    ck(crlf[25] and crlf[25].name == "Worn Shortsword",
       "CRLF: no carriage return leaks into the name")
    ck(crlf[19019] and crlf[19019].name == "Thunderfury", "…on any line")

    -- a name that begins with digits must not be re-split
    local digits = collect("12345 2 30 Pound Fish Trophy")
    ck(digits[12345] and digits[12345].name == "30 Pound Fish Trophy" and digits[12345].q == 2,
       "a name that STARTS with a number is not mistaken for the id/quality fields")

    ck(Scan.CatalogEach(function() end, "") == 0, "an empty payload yields nothing")
    ck(Scan.CatalogEach(function() end, nil, nil) >= 0, "a nil payload does not raise")
    ck(Scan.CatalogEach(nil, "25 1 Worn Shortsword") == 0, "a nil callback yields nothing")

    -- HEADLESS DISCIPLINE: the walk is ceilinged, so a corrupted string cannot
    -- spin the login frame.
    ck(type(Scan.CATALOG_CEILING) == "number" and Scan.CATALOG_CEILING > 9240,
       "the walk carries an iteration ceiling above the shipped row count")
    local big = {}
    for i = 1, 50 do big[i] = i .. " 1 Item " .. i end
    local savedCeil = Scan.CATALOG_CEILING
    Scan.CATALOG_CEILING = 10
    local capped = Scan.CatalogEach(function() end, table.concat(big, "\n"))
    Scan.CATALOG_CEILING = savedCeil
    ck(capped == 10, "…and it really stops there (got " .. tostring(capped) .. ")")

    -- ── THE SHIPPED FILE ────────────────────────────────────────────────────
    local A = {}
    local cfn, cerr = loadfile(P("catalog.lua"))
    ck(cfn ~= nil, "catalog.lua compiles" .. (cfn and "" or (" -> " .. tostring(cerr))))
    if not cfn then return end
    ck(pcall(cfn, "Daseeki-Armory", A), "…and loads with no WoW API present")
    ck(type(A.StaticCatalogRaw) == "string", "it publishes Addon.StaticCatalogRaw")
    ck(type(A.StaticCatalogCount) == "number", "…and a literal Addon.StaticCatalogCount")

    local shipped, shippedN = {}, 0
    local dupes, badQ = 0, 0
    Scan.CatalogEach(function(id, name, q)
        shippedN = shippedN + 1
        if shipped[id] then dupes = dupes + 1 end
        if type(q) ~= "number" or q < 0 or q > 7 then badQ = badQ + 1 end
        shipped[id] = name
    end, A.StaticCatalogRaw)

    ck(shippedN == A.StaticCatalogCount,
       "the declared count matches the payload (" .. shippedN .. " vs "
       .. tostring(A.StaticCatalogCount) .. ")")
    ck(shippedN == 9240, "the shipped catalog is 9 240 items (got " .. shippedN .. ")")
    ck(dupes == 0, "no id appears twice")
    ck(badQ == 0, "every quality is a real 0..7")

    -- THE DENYLIST IS BAKED IN. Not one internal name survived generation, which
    -- is why the index builder has no internal filter left.
    local leaked, leakName = 0, nil
    for id, name in pairs(shipped) do
        if Scan.IsInternalName(name) then
            leaked = leaked + 1
            if not leakName then leakName = id .. " " .. name end
        end
    end
    ck(leaked == 0, "NOT ONE internal record is in the shipped catalog (leak: "
       .. tostring(leakName) .. ")")

    -- the old defect's own ids, checked directly against the shipped file
    ck(shipped[13794] == nil,
       "the 1.3.1 defect id 13794 ([PH] Shining Dawn Coif) is not shipped at all")
    for _, nm in pairs(shipped) do
        if nm == "Enchant Cloak - Resistance" then leaked = leaked + 1 end
    end
    ck(leaked == 0, "…and no row anywhere is named 'Enchant Cloak - Resistance'")

    -- and the items that MUST be there
    ck(shipped[19019] == "Thunderfury, Blessed Blade of the Windseeker",
       "Thunderfury ships, under the client's own name")
    ck(shipped[17182] == "Sulfuras, Hand of Ragnaros", "…and Sulfuras")
    ck(shipped[22691] == "Corrupted Ashbringer", "…and the Ashbringer you can actually chase")
    ck(shipped[12640] == "Lionheart Helm", "…and ordinary gear")

    -- EVERY RESTRICTED ID IS IN THE CATALOG. A lock on an id the picker can never
    -- offer is a lock that does nothing; this is what proves the two shipped files
    -- were generated from the same evidence.
    local R = {}
    local rfn = loadfile(P("restrictions.lua"))
    if rfn then pcall(rfn, "Daseeki-Armory", R) end
    local orphanLock, orphanHide = 0, 0
    for id in pairs(R.StaticRestrictions or {}) do
        if not shipped[id] then orphanLock = orphanLock + 1 end
    end
    for id in pairs(R.StaticUnobtainable or {}) do
        if not shipped[id] then orphanHide = orphanHide + 1 end
    end
    ck(orphanLock == 0, "every class/faction lock names an id the catalog ships (" .. orphanLock .. " orphans)")
    ck(orphanHide == 0, "…and so does every hidden-by-history id (" .. orphanHide .. " orphans)")

    -- THE HIDDEN LIST IS *NOT* BAKED OUT, deliberately. Those ids ship and are
    -- dropped by the row predicate, so deleting a line from restrictions.lua puts
    -- the item straight back with no regeneration — which is the promise that list
    -- has always carried.
    ck(shipped[13262] == "Ashbringer",
       "an unobtainable item is still IN the catalog — the hidden list stays policy")
    ck(shipped[6698] == "Stone of Pierce", "…including the GM records")

    -- ── THE INDEX BUILDER, driven for real ──────────────────────────────────
    -- goalPicker.lua touches the WoW API only from inside functions, so the
    -- builder runs headlessly against stubs.
    local function buildFixture(raw, pvp, clientHas)
        local G = { ItemScan = Scan, StaticCatalogRaw = raw, PvPItemIDs = pvp or {} }
        local fn = loadfile(P("goalPicker.lua"))
        if not fn then return nil, "goalPicker.lua does not compile" end
        if not pcall(fn, "Daseeki-Armory", G) then return nil, "goalPicker.lua raised at load" end
        -- Scan.CatalogEach falls back to the catalog on ITS OWN addon table (the
        -- one itemScan.lua was loaded with), so point that at the fixture for the
        -- duration rather than the picker's.
        local savedRaw = ScanAddon.StaticCatalogRaw
        ScanAddon.StaticCatalogRaw = raw
        local savedI, savedG = _G.GetItemInfoInstant, _G.GetItemInfo
        _G.GetItemInfoInstant = function(id)
            if clientHas and not clientHas[id] then return id end   -- no icon: client lacks it
            return id, nil, nil, "INVTYPE_HEAD", "icon" .. tostring(id), 4, 1
        end
        _G.GetItemInfo = function(id)
            if pvp and pvp.names and pvp.names[id] then return pvp.names[id], nil, 3 end
            return nil
        end
        local okb, list = pcall(G.BuildGoalItemDB, G)
        _G.GetItemInfoInstant, _G.GetItemInfo = savedI, savedG
        Addon.StaticCatalogRaw = savedRaw
        if not okb then return nil, "BuildGoalItemDB raised: " .. tostring(list) end
        local byId = {}
        for _, e in ipairs(list) do byId[e.id] = e end
        return { G = G, list = list, byId = byId }
    end

    local FIX = "25 1 Worn Shortsword\n12640 4 Lionheart Helm\n19019 5 Thunderfury, Blessed Blade of the Windseeker"
    local b, berr = buildFixture(FIX)
    ck(b ~= nil, "the index builds straight from the catalog (" .. tostring(berr) .. ")")
    if b then
        ck(#b.list == 3, "every catalog row becomes an entry (got " .. #b.list .. ")")
        ck(b.byId[19019] and b.byId[19019].display == "Thunderfury, Blessed Blade of the Windseeker",
           "…under the catalog's name")
        ck(b.byId[19019] and b.byId[19019].name == "thunderfury, blessed blade of the windseeker",
           "…with a folded search key beside it")
        -- QUALITY COMES FROM THE CATALOG, which is the whole cold-sort fix: it is
        -- present before the client has sent anything, so the order never collapses
        -- onto the alphabet and no legendary can be sorted off the end of the cap.
        ck(b.byId[19019] and b.byId[19019].quality == 5,
           "QUALITY IS NEVER COLD: it arrives with the catalog row, not from the server")
        ck(b.byId[12640] and b.byId[12640].quality == 4, "…for every row")
        ck(b.byId[25] and b.byId[25].equipLoc == "INVTYPE_HEAD",
           "equipLoc is re-derived from GetItemInfoInstant, not shipped")
        ck(b.byId[25] and b.byId[25].icon ~= nil, "…as are the icon and the item class")
    end

    -- AN ID THIS CLIENT DOES NOT HAVE IS DROPPED. That is the safety net that lets
    -- one developer's capture ship to everyone: a catalog built against a different
    -- build offers less, never phantoms.
    local nb = buildFixture(FIX, nil, { [25] = true, [12640] = true })
    ck(nb and #nb.list == 2 and nb.byId[19019] == nil,
       "an id the running client cannot answer for is silently dropped")

    -- THE PvP SAFETY NET still fires for an id the catalog somehow missed…
    local pb = buildFixture("25 1 Worn Shortsword",
                            setmetatable({ 16472 }, nil))
    ck(pb ~= nil, "the index builds with PvP ids present")
    local pv = { 16472, names = { [16472] = "Field Marshal's Coronet" } }
    local pb2 = buildFixture("25 1 Worn Shortsword", pv)
    ck(pb2 and pb2.byId[16472] ~= nil,
       "PvP SAFETY NET: an id the catalog missed is still named by the client")
    ck(pb2 and (pb2.G._goalPvPMissing or 0) == 0, "…and nothing is left outstanding")
    -- …and is a no-op when the catalog already covers it
    local pb3 = buildFixture("16472 4 Field Marshal's Coronet", pv)
    ck(pb3 and pb3.byId[16472] and pb3.byId[16472].display == "Field Marshal's Coronet",
       "…while a covered id keeps the CATALOG's name, not a second lookup's")
    ck(pb3 and #pb3.list == 1, "…and is not added twice")

    -- every real PvP id IS covered by the shipped catalog today
    local V = {}
    local vfn = loadfile(P("pvpItems.lua"))
    if vfn then pcall(vfn, "Daseeki-Armory", V) end
    local pvpMissing = 0
    for _, id in ipairs(V.PvPItemIDs or {}) do
        if not shipped[id] then pvpMissing = pvpMissing + 1 end
    end
    ck(#(V.PvPItemIDs or {}) > 0, "pvpItems.lua publishes its ids")
    ck(pvpMissing == 0,
       "all " .. #(V.PvPItemIDs or {}) .. " PvP rank ids are in the shipped catalog "
       .. "(" .. pvpMissing .. " missing) — the net is slack on purpose")

    -- ── SOURCE SHAPE, in the source ─────────────────────────────────────────
    local h = io.open(P("goalPicker.lua"), "r")
    ck(h ~= nil, "goalPicker.lua is readable")
    if h then
        local src = h:read("*a"); h:close()
        ck(src:find("Scan%.CatalogEach%(add%)") ~= nil,
           "the index is built by streaming the catalog")
        ck(src:find("Addon%.ItemNameDB") == nil, "the bundled seed is not consulted at all")
        ck(src:find("GoalSeedAllowed") == nil, "…so the seed-retirement rule is gone with it")
        ck(src:find("cache%.names") == nil, "…and so is the scan cache")
        ck(src:find("local list, settled = {}, {}") ~= nil,
           "the duplicate guard survives (one source can still repeat an id)")
        local catLoop = src:find("Scan%.CatalogEach%(add%)")
        local pvpLoop = src:find("for _, id in ipairs%(Addon%.PvPItemIDs")
        ck(catLoop and pvpLoop and catLoop < pvpLoop,
           "the catalog is read before the PvP net, so the net only fills gaps")
    end

    -- ── THE SEED IS NOT SHIPPED ─────────────────────────────────────────────
    local stray = io.open(P("itemDB.lua"), "r")
    ck(stray == nil, "itemDB.lua is no longer in the addon root")
    if stray then stray:close() end
    local kept = io.open(P("dev/itemDB-seed.lua"), "r")
    ck(kept ~= nil, "…it survives as dev/itemDB-seed.lua, a generator input")
    if kept then
        local ks = kept:read("*a"); kept:close()
        ck(ks:find("Addon%.ItemClassMask") ~= nil,
           "…carrying the Tier-3 class masks no other source has, for the next regeneration")
    end
    local toc = io.open(P("Daseeki-Armory.toc"), "r")
    if toc then
        local ts = toc:read("*a"); toc:close()
        ck(ts:find("itemDB%.lua") == nil, "…and the TOC does not load it")
        ck(ts:find("catalog%.lua") ~= nil, "…while catalog.lua takes its place")
    end
end)

----------------------------------------------------------------------
-- THE SHIPPED LOCKS REACH THE PICKER  (1.3.1, the architectural replacement)
--
-- THE DEFECT, four times over: four copies of Atiesh — the Naxxramas legendary
-- staff, locked to mage/priest/warlock/druid — and all nine Tier-3 sets were in a
-- warrior's list. Their class locks are the ones the runtime capture never read
-- (classMask 0 across the whole 22314-22821 band, 0 of 224 rows restricted,
-- verified in the owner's real cache), and four generations of retry/repair
-- machinery failed to get them.
--
-- THE REPLACEMENT: they are shipped in restrictions.lua and looked up by id.
-- This suite drives the real filter over the real shipped table — no fixture
-- masks, no invented ids — so what it pins is the state the owner actually opens
-- his picker into.
----------------------------------------------------------------------
suite("static-restrictions-shipped", function(ck)
    if type(Scan) ~= "table" then ck(false, "itemScan.lua did not load"); return end
    if type(ScanAddon.StaticRestrictions) ~= "table" then
        ck(false, "restrictions.lua did not publish Addon.StaticRestrictions"); return
    end
    local B = Scan.CLASS_BIT
    local SR = ScanAddon.StaticRestrictions

    -- ── 1. THE TABLE ITSELF ─────────────────────────────────────────────────
    local n = 0
    for _ in pairs(SR) do n = n + 1 end
    ck(n >= 850, "the shipped table carries the whole census, not a sample (" .. n .. " ids)")
    ck(Scan.StaticCount() == n, "Scan.StaticCount agrees with the table it counts")

    local badKey, badVal, tooWide, allNine = 0, 0, 0, 0
    local NINE = B.WARRIOR + B.PALADIN + B.HUNTER + B.ROGUE + B.PRIEST
               + B.SHAMAN + B.MAGE + B.WARLOCK + B.DRUID
    for id, packed in pairs(SR) do
        if type(id) ~= "number" or id <= 0 or id ~= math.floor(id) then badKey = badKey + 1 end
        if type(packed) ~= "number" or packed <= 0 then badVal = badVal + 1 end
        local m, f = Scan.UnpackStatic(packed)
        if m >= Scan.STATIC_SHIFT or f > 2 then tooWide = tooWide + 1 end
        if m > 0 and (m % (NINE + 1)) == NINE then allNine = allNine + 1 end
        if m == 0 and f == Scan.FACTION_NONE then badVal = badVal + 1 end
    end
    ck(badKey == 0, "every key is a positive integer item id")
    ck(badVal == 0, "every value is a positive packed lock — an unrestricted id is ABSENT, not 0")
    ck(tooWide == 0, "no mask or faction overflows its field")
    ck(allNine == 0,
       "no entry names all nine classes: a mask that hides nothing is a row that lies")

    -- pack/unpack is exact over the whole shipped table
    local tripped = true
    for id, packed in pairs(SR) do
        local m, f = Scan.UnpackStatic(packed)
        if Scan.PackStatic(m, f) ~= packed then tripped = false; break end
    end
    ck(tripped, "every shipped value survives UnpackStatic -> PackStatic unchanged")

    -- ── 2. ATIESH: the owner's row, through the real predicate ──────────────
    -- Every Atiesh variant is a staff (weapon subclass 10) and a warrior IS
    -- proficient with staves, so nothing but the class lock can hide it. That is
    -- exactly why it was the visible symptom.
    ck(Scan.PROF.WARRIOR.weapon[10] == true,
       "a warrior can wield a staff, so proficiency alone would never hide Atiesh")
    local ATIESH = { 22589, 22630, 22631, 22632 }
    local CASTERS = { MAGE = true, WARLOCK = true, PRIEST = true, DRUID = true }
    local seen, single, casterOnly = {}, 0, 0
    for _, id in ipairs(ATIESH) do
        local m, f = Scan.StaticFor(id)
        ck(m > 0, "Atiesh " .. id .. " carries a class lock in the shipped table")
        ck(f == Scan.FACTION_NONE, "…and no faction lock (both sides could hold one)")
        local named, tok = 0, nil
        for class, bit in pairs(B) do
            if Scan.HasBit(m, bit) then named = named + 1; tok = class end
        end
        if named == 1 then single = single + 1 end
        if tok and CASTERS[tok] then casterOnly = casterOnly + 1; seen[tok] = (seen[tok] or 0) + 1 end
    end
    ck(single == 4, "each of the four Atiesh ids names exactly one class")
    ck(casterOnly == 4, "…and every one of them is a caster class")
    local perm = 0
    for c in pairs(CASTERS) do if seen[c] == 1 then perm = perm + 1 end end
    ck(perm == 4,
       "the four ids are a PERMUTATION of mage/warlock/priest/druid — one copy each, "
       .. "which is the part that is checkable without the client")

    -- and the load-bearing property, which holds however that permutation falls
    local function row(id, subclass)
        return { id = id, equipLoc = "INVTYPE_2HWEAPON", name = "",
                 classID = Scan.ITEM_CLASS_WEAPON, subclassID = subclass or 10 }
    end
    local function viewer(class, faction, showUnusable)
        return { class = class, classBit = B[class] or 0,
                 faction = faction or Scan.FACTION_NONE,
                 showUnusable = showUnusable and true or false }
    end
    local twoHand = { INVTYPE_2HWEAPON = true }
    local hiddenFromAll = 0
    for _, id in ipairs(ATIESH) do
        local ok = true
        for _, c in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "SHAMAN" }) do
            if Scan.Matches(row(id), "", twoHand, viewer(c)) then ok = false end
        end
        if ok then hiddenFromAll = hiddenFromAll + 1 end
    end
    ck(hiddenFromAll == 4,
       "THE OWNER'S ROW: no Atiesh is offered to a warrior, paladin, hunter, rogue or shaman")
    local shownToSomeCaster = 0
    for _, id in ipairs(ATIESH) do
        for _, c in ipairs({ "MAGE", "WARLOCK", "PRIEST", "DRUID" }) do
            if Scan.Matches(row(id), "", twoHand, viewer(c)) then
                shownToSomeCaster = shownToSomeCaster + 1; break
            end
        end
    end
    ck(shownToSomeCaster == 4, "…and each copy is still offered to the caster who can hold it")
    ck(Scan.Matches(row(22589), "atiesh", twoHand, viewer("WARRIOR")) == false,
       "searching for it by name does not bring it back for a warrior either")
    ck(Scan.Matches(row(22589), "", twoHand, viewer("WARRIOR", nil, true)) == true,
       "…while 'Show unusable' still reveals it, because it IS a real item")

    -- ── 3. TIER 3: nine sets, eight pieces each, all in the shipped table ───
    -- The band the runtime capture lost in its entirety.
    local T3 = {
        { 22416, 22423, "WARRIOR", "Dreadnaught"  },
        { 22424, 22431, "PALADIN", "Redemption"   },
        { 22436, 22443, "HUNTER",  "Cryptstalker" },
        { 22464, 22471, "SHAMAN",  "Earthshatter" },
        { 22476, 22483, "ROGUE",   "Bonescythe"   },
        { 22488, 22495, "DRUID",   "Dreamwalker"  },
        { 22496, 22503, "MAGE",    "Frostfire"    },
        { 22504, 22511, "WARLOCK", "Plagueheart"  },
        { 22512, 22519, "PRIEST",  "Vestments of Faith" },
    }
    local pieces, wrong = 0, 0
    for _, set in ipairs(T3) do
        local want = B[set[3]]
        for id = set[1], set[2] do
            pieces = pieces + 1
            local m, f = Scan.StaticFor(id)
            if m ~= want or f ~= Scan.FACTION_NONE then wrong = wrong + 1 end
        end
    end
    ck(pieces == 72, "the fixture covers all nine Tier-3 sets, eight pieces each")
    ck(wrong == 0, "every Tier-3 piece carries its own set's class and nothing else")

    -- Bonescythe on a warrior — the headline symptom — through the real predicate
    local plate = { INVTYPE_CHEST = true }
    local bone = { id = 22476, equipLoc = "INVTYPE_CHEST", name = "",
                   classID = Scan.ITEM_CLASS_ARMOR, subclassID = 2 }
    ck(Scan.Matches(bone, "", plate, viewer("ROGUE")) == true,
       "Bonescythe Breastplate is offered to a rogue")
    ck(Scan.Matches(bone, "", plate, viewer("WARRIOR")) == false,
       "…and is NOT offered to a warrior (leather proficiency would not have saved him)")
    ck(Scan.PROF.WARRIOR.armor[2] == true,
       "…confirmed: a warrior IS proficient with leather, so the class lock is the only thing hiding it")

    -- ── 4. UNOBTAINABLE BY HISTORY ──────────────────────────────────────────
    ck(type(ScanAddon.StaticUnobtainable) == "table",
       "restrictions.lua publishes the unobtainable-by-history list")
    local un = ScanAddon.StaticUnobtainable
    -- THE WHOLE LIST, BY ENUMERATION AND BY COUNT. Twelve ids, every one signed
    -- off by the owner: five reviewed one by one on 2026-08-04, and the seven
    -- GM/developer records added on 2026-08-05 ("yes hide the gm items"). The
    -- count is pinned alongside the names so that an id ADDED without a decision
    -- fails here too — enumeration alone only catches deletions, and this list
    -- hides things from the player, so it earns both.
    local KEPT_HIDDEN = { 13262, 18582, 18583, 18584, 22736,
                          6698, 6707, 6708, 6711, 6724, 6728, 12947 }
    for _, id in ipairs(KEPT_HIDDEN) do
        ck(un[id] == true, "the owner's named unobtainable id " .. id .. " is on the list")
    end
    local nUn = 0
    for _ in pairs(un) do nUn = nUn + 1 end
    ck(nUn == #KEPT_HIDDEN,
       "…and the list is EXACTLY those " .. #KEPT_HIDDEN .. " ids, nothing else (saw " .. nUn .. ")")
    local oneHand = { INVTYPE_WEAPON = true }
    local glaive = { id = 18583, equipLoc = "INVTYPE_WEAPON", name = "",
                     classID = Scan.ITEM_CLASS_WEAPON, subclassID = 7 }
    ck(Scan.Matches(glaive, "", oneHand, viewer("WARRIOR")) == false,
       "a Warglaive is not offered as a goal")
    ck(Scan.Matches(glaive, "", oneHand, viewer("WARRIOR", nil, true)) == false,
       "…and 'Show unusable' does NOT reveal it: no character anywhere can obtain one")
    ck(Scan.IsUnobtainable(18583) == true and Scan.IsUnobtainable(19019) == false,
       "Thunderfury, which IS obtainable, is not on the list")
    ck(Scan.Matches({ id = 19019, equipLoc = "INVTYPE_WEAPON", name = "",
                      classID = Scan.ITEM_CLASS_WEAPON, subclassID = 7 },
                    "", oneHand, viewer("WARRIOR")) == true,
       "…so it is still offered")

    -- ── 4b. THE TWO ASHBRINGERS — one policy line apart ─────────────────────
    -- OWNER DECISION 2026-08-04: "only corrupted ashbringer stays". 13262 never
    -- reached a live Era loot table; 22691 is a genuine Naxxramas drop and a
    -- legitimate goal item. Both are two-handed swords (weapon subclass 8) and
    -- a warrior is proficient with those, so proficiency separates neither of
    -- them — the unobtainable list is the ONLY thing that can tell them apart.
    -- The real names, so the by-name search checks below are not passing on an
    -- empty string: a name search that never had the word to find proves nothing.
    -- Lower-cased because that is what an index entry carries (goalPicker builds
    -- rows with name = name:lower(), against a NormalizeQuery'd query).
    local ASH_NAME = { [13262] = "ashbringer", [22691] = "corrupted ashbringer" }
    local function ashRow(id)
        return { id = id, equipLoc = "INVTYPE_2HWEAPON", name = ASH_NAME[id],
                 classID = Scan.ITEM_CLASS_WEAPON, subclassID = 8 }
    end
    ck(Scan.PROF.WARRIOR.weapon[8] == true and Scan.PROF.PALADIN.weapon[8] == true,
       "a warrior and a paladin both wield two-handed swords, so proficiency hides neither Ashbringer")
    ck(un[13262] == true and Scan.IsUnobtainable(13262) == true,
       "Ashbringer (13262) is on the unobtainable-by-history list")
    ck(Scan.Matches(ashRow(13262), "", twoHand, viewer("WARRIOR")) == false,
       "…so it is not offered as a goal to a warrior")
    ck(Scan.Matches(ashRow(13262), "", twoHand, viewer("PALADIN")) == false,
       "…nor to a paladin, the class the story attaches it to")
    ck(Scan.Matches(ashRow(13262), "", twoHand, viewer("WARRIOR", nil, true)) == false,
       "…and 'Show unusable' does NOT reveal it: no character anywhere can obtain one")
    ck(Scan.Matches(ashRow(13262), "ashbringer", twoHand, viewer("PALADIN", nil, true)) == false,
       "…searching for it by name does not bring it back either")
    ck(un[22691] == nil and Scan.IsUnobtainable(22691) == false,
       "CORRUPTED ASHBRINGER (22691) IS NOT ON THE LIST — a real Naxxramas drop stays a goal")
    ck(SR[22691] == nil,
       "…and it carries no class lock in the shipped table, so nothing else hides it")
    ck(Scan.Matches(ashRow(22691), "", twoHand, viewer("WARRIOR")) == true,
       "…it is offered to a warrior")
    ck(Scan.Matches(ashRow(22691), "ashbringer", twoHand, viewer("PALADIN")) == true,
       "…and a paladin searching 'ashbringer' is shown the one he can actually chase")

    -- ── 4c. THE KRUUL BLADES — obtainable on Anniversary, so back in ────────
    -- OWNER CORRECTION 2026-08-04, verbatim: "Gressil Iblis and Neretzek are all
    -- obtainable unless there is another version in the code that reads as
    -- legendary." The first pass hid them on ORIGINAL-VANILLA history; the realm
    -- this addon is used on is Classic Era ANNIVERSARY, where the Scourge Invasion
    -- re-ran and the blades are genuine drops. They were removed from the list.
    --
    -- THE CAVEAT WAS CHECKED, NOT ASSUMED. A census of the owner's account-1 scan
    -- cache and the bundled seed for every id naming Gressil / Iblis / Neretzek /
    -- Untamed found exactly four ids and NO TWINS — one record each, in both
    -- sources, quality 4 (Epic). There is no legendary display variant to keep
    -- hiding, which is the condition the owner attached to the correction, so the
    -- assertion that stands in for the census is that no OTHER id answers to these
    -- names in the shipped data — see the by-name sweep at the end of this block.
    local KRUUL = {
        [23054] = "gressil, dawn of ruin",
        [23014] = "iblis, blade of the fallen seraph",
        [21856] = "neretzek, the blood drinker",
        [19334] = "the untamed blade",          -- never listed; pinned as the control
    }
    local kruulOrder = { 19334, 21856, 23014, 23054 }
    for _, id in ipairs(kruulOrder) do
        ck(un[id] == nil and Scan.IsUnobtainable(id) == false,
           "Kruul blade " .. id .. " (" .. KRUUL[id] .. ") is NOT hidden as unobtainable")
        ck(SR[id] == nil,
           "…and carries no class lock in the shipped table either")
    end

    -- PROFICIENCY IS THE ONLY GATE LEFT, and that is the whole claim. The shipped
    -- data now says nothing at all about these four ids, so whatever weapon they
    -- turn out to be, the picker must offer each one to exactly the classes that
    -- can wield that weapon — no more (the addon inventing a lock) and no fewer
    -- (the addon still hiding them). Sweeping EVERY weapon subclass proves it
    -- without this harness having to assert what subclass each blade really is:
    -- that is a client fact, and the client is not in the room.
    local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
                      "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
    local mismatched, offeredSomewhere = 0, 0
    for _, id in ipairs(kruulOrder) do
        local everOffered = false
        for sub = 0, 20 do
            local wrow = { id = id, equipLoc = "INVTYPE_WEAPON", name = KRUUL[id],
                           classID = Scan.ITEM_CLASS_WEAPON, subclassID = sub }
            for _, c in ipairs(CLASSES) do
                local shown = Scan.Matches(wrow, "", oneHand, viewer(c))
                local canWield = Scan.PROF[c].weapon[sub] == true
                if shown ~= canWield then mismatched = mismatched + 1 end
                if shown then everOffered = true end
            end
        end
        if everOffered then offeredSomewhere = offeredSomewhere + 1 end
    end
    ck(mismatched == 0,
       "each restored blade is offered to EXACTLY the classes proficient with its weapon "
       .. "subclass — proficiency is the only gate the shipped data leaves (" .. mismatched
       .. " disagreements over 4 ids x 21 subclasses x 9 classes)")
    ck(offeredSomewhere == 4,
       "…and all four are genuinely reachable: every one is offered to somebody")

    -- A NAME SEARCH FINDS THEM AGAIN. Hiding was the bug; being un-findable by
    -- name is how the owner would notice it had come back.
    for _, id in ipairs(kruulOrder) do
        local swordRow = { id = id, equipLoc = "INVTYPE_WEAPON", name = KRUUL[id],
                           classID = Scan.ITEM_CLASS_WEAPON, subclassID = 7 }
        ck(Scan.Matches(swordRow, "blade", oneHand, viewer("ROGUE")) == true
           or Scan.Matches(swordRow, KRUUL[id]:sub(1, 6), oneHand, viewer("ROGUE")) == true,
           "…and a rogue searching for " .. id .. " by name is shown it")
    end

    -- THE ONE LEGENDARY IN THE NEIGHBOURHOOD STAYS HIDDEN, for its own reason:
    -- Andonisus IS obtainable on an Anniversary realm, but it decays and destroys
    -- itself, so it is not a goal a character can still own. It is the row the
    -- Anniversary reasoning does NOT reach, which is exactly why it is worth
    -- pinning next to the three it did.
    ck(un[22736] == true and Scan.IsUnobtainable(22736) == true,
       "ANDONISUS (22736) STAYS HIDDEN — obtainable, but a decaying weapon is not a goal")
    ck(Scan.Matches({ id = 22736, equipLoc = "INVTYPE_WEAPON", name = "andonisus, reaper of souls",
                      classID = Scan.ITEM_CLASS_WEAPON, subclassID = 7 },
                    "andonisus", oneHand, viewer("WARRIOR", nil, true)) == false,
       "…not by name, not under 'Show unusable' — the same treatment as before the correction")

    -- ── 5. THE SCAN → PICKER SEAM IS CUT (1.3.1) ───────────────────────────
    -- This used to assert the opposite: that FinishItemScan invalidated the
    -- picker's index and then PUSHED a refresh into an open picker, in that order.
    -- The index is built from catalog.lua now and owes the scan nothing, so a
    -- finished scan must NOT reach into the picker at all — the developer capture
    -- exists to produce a file for the next release, and rewriting the list under
    -- the person looking at it would be both pointless and startling.
    local sh = io.open(P("itemScan.lua"), "r")
    ck(sh ~= nil, "itemScan.lua is readable")
    if sh then
        local s = sh:read("*a"); sh:close()
        ck(s:find("Addon%.RefreshGoalPicker") == nil,
           "a finished scan does NOT push a refresh into the picker any more")
        ck(s:find("Addon%.GoalItemDB, Addon%._goalDBStamp = nil, nil") == nil,
           "…and does not invalidate an index it no longer feeds")
        ck(s:find("_goalDBStamp") == nil, "…the index stamp is gone with the cache that moved it")

        -- ── THE DELETION INVENTORY, asserted so it cannot creep back ────────
        for _, gone in ipairs({
            "ParseRestrictions", "ReadRestrictions", "TrustRead", "RepairGate",
            "UnreadIds", "UnreadCount", "MaybeRepairRestrictions", "BlockRepair",
            "IsRepairing", "RESTRICT_STAMP", "TOOLTIP_TRIES", "DATA_TRIES",
            "SetItemByID", "IsItemDataCachedByID", "ITEM_CLASSES_ALLOWED",
        }) do
            ck(s:find(gone, 1, true) == nil,
               "the runtime restriction machinery is GONE from itemScan.lua: " .. gone)
        end
        ck(s:find("Scan%.StaticFor") ~= nil, "…and the shipped-table lookup is what replaced it")
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
        ck(g:find("MaybeRepairRestrictions") == nil,
           "OPENING THE PICKER NO LONGER STARTS ANYTHING")
        ck(g:find("seedClassMask") == nil,
           "…and the seed is no longer a runtime lock source")
        ck(g:find("classMask = ") == nil and g:find("faction = faction") == nil,
           "…nor does an index entry carry a copy of a lock it does not own")
    end

    -- ── 6. /darmory data: A REPORT ON SHIPPED DATA, NOT ON A PROCESS ───────
    --
    -- Every earlier version of this report answered questions about a PROCESS —
    -- is the scan running, how far has it got, when did it last finish, how many
    -- rows are still unread, why was the last repair refused, which capture stamp
    -- is current — because the item database was something each user produced for
    -- themselves and the production could fail. It is shipped now, so the report
    -- takes no arguments at all: there is no cache to walk and no live status to
    -- interrogate, and three counts say everything there is to say.
    ck(type(Scan.StatusReport) == "function", "Scan.StatusReport is published")
    local function joined(lines) return table.concat(lines or {}, "\n") end
    local function findLine(lines, prefix)
        for _, l in ipairs(lines or {}) do
            if l:sub(1, #prefix) == prefix then return l end
        end
    end

    -- IT TAKES NO ARGUMENTS. Passing the old ones must not change the answer, or
    -- some caller is still feeding it state it should not have.
    local rep  = Scan.StatusReport()
    local rep2 = Scan.StatusReport(Scan.NewCache(), { phase = "instant", percent = 25 })
    ck(joined(rep) == joined(rep2),
       "the report is a pure function of the BUILD: old arguments change nothing")

    ck(#rep == 4, "the report is FOUR lines (got " .. #rep .. ")")
    local catLine = findLine(rep, "catalog:")
    ck(catLine ~= nil, "…led by the catalog line")
    ck(catLine and catLine:find("9240 items") ~= nil,
       "…which says how many items this build ships: " .. tostring(catLine))
    local restrictLine = findLine(rep, "restrictions:")
    ck(restrictLine ~= nil, "…then the locks")
    ck(restrictLine and restrictLine:find(tostring(n) .. " class/faction locks") ~= nil,
       "…counted from the shipped table (" .. n .. ")")
    local hiddenLine = findLine(rep, "hidden:")
    ck(hiddenLine ~= nil, "…then what is hidden by history")
    ck(hiddenLine and hiddenLine:find("12 unobtainable") ~= nil,
       "…all 12 of them: " .. tostring(hiddenLine))
    ck(joined(rep):find("Nothing to scan") ~= nil,
       "…and the report says outright that there is nothing to scan")

    -- THE PROCESS VOCABULARY IS GONE, every word of it.
    for _, word in ipairs({ "owed", "unread", "repair", "capture", "RUNNING",
                            "last full scan", "idle", "cache:", "stamps:" }) do
        ck(joined(rep):find(word, 1, true) == nil,
           "no line can still say '" .. word .. "' — there is no process to describe")
    end

    -- A ZERO IS THE ONE FAULT LEFT, and it must be legible rather than inferred
    -- from an empty picker.
    local savedCat, savedRes = ScanAddon.StaticCatalogCount, ScanAddon.StaticRestrictions
    ScanAddon.StaticCatalogCount = nil
    local broken = Scan.StatusReport()
    ScanAddon.StaticCatalogCount = savedCat
    ck(findLine(broken, "catalog:") and findLine(broken, "catalog:"):find("did not load") ~= nil,
       "a catalog that failed to load says so on its own line")
    ck(savedRes ~= nil, "fixture check: the restriction table was there to begin with")

    for _, l in ipairs(rep) do
        ck(type(l) == "string" and l:find("|c") == nil and l:find("nil") == nil,
           "every status line is plain, complete text: " .. tostring(l))
    end

    local sl = io.open(P("slash.lua"), "r")
    ck(sl ~= nil, "slash.lua is readable")
    if sl then
        local t = sl:read("*a"); sl:close()
        ck(t:find('cmd == "data"') ~= nil, "/darmory data is the command")
        ck(t:find('cmd == "scanstatus"') ~= nil,
           "…and scanstatus still answers, because it is in muscle memory and a release note")
        ck(t:find("Scan%.StatusReport%(%)") ~= nil,
           "…printing exactly the report, with nothing handed to it")
        ck(t:find("Addon:ItemScanCache") == nil,
           "…and the slash surface never binds the retired cache")
        ck(t:find("/darmory data") ~= nil, "…documented in the file's own header")

        -- THE DEV DOOR: gated, and never advertised.
        ck(t:find('cmd == "devscan"') ~= nil, "the developer scan has an entry point")
        ck(t:find("Addon:StartDevScan%(%)") ~= nil, "…which goes through the gated starter")
        ck(t:find("StartItemScan") == nil,
           "…and the slash file cannot reach the runner directly")
        local hdrEnd = t:find("%-%-%]%]")
        ck(hdrEnd and t:find("devscan", 1, true) > hdrEnd
           or (t:find("UNDOCUMENTED") ~= nil),
           "…and the header lists it as undocumented rather than as a command")
    end

    -- THE GATE ITSELF: a global nobody sets by accident, checked at call time.
    local sh2 = io.open(P("itemScan.lua"), "r")
    if sh2 then
        local s2 = sh2:read("*a"); sh2:close()
        ck(s2:find('Addon%.DEV_SCAN_FLAG = "DASEEKI_ARMORY_DEV"') ~= nil,
           "the dev flag is a named global, not a saved setting")
        ck(s2:find("function Addon:IsDevScanEnabled") ~= nil, "…with a published predicate")
        ck(s2:find("if not Addon:IsDevScanEnabled%(%) then") ~= nil,
           "…and StartDevScan refuses before it does anything else")
        ck(s2:find("function Addon:InitItemScan") == nil,
           "THE AUTO PATH IS GONE: there is no login hook left to arm it")
        -- The rest of the auto path — the delay, the one-shot latch, the notice —
        -- is asserted away construct by construct in item-scan-no-auto-path.
    end
    local ch = io.open(P("core.lua"), "r")
    if ch then
        local c2 = ch:read("*a"); ch:close()
        ck(c2:find("if Addon%.InitItemScan then Addon:InitItemScan%(%) end") == nil,
           "…and the login path does not call it")
    end

    -- ── 7. THE TOC LOADS THE DATA BEFORE THE CODE THAT READS IT ─────────────
    local th = io.open(P("Daseeki-Armory.toc"), "r")
    ck(th ~= nil, "the TOC is readable")
    if th then
        local toc = th:read("*a"); th:close()
        local r = toc:find("restrictions%.lua")
        local i = toc:find("itemScan%.lua")
        local c = toc:find("catalog%.lua")
        ck(r ~= nil, "restrictions.lua is shipped")
        ck(r and i and r < i, "…and is loaded BEFORE itemScan.lua, which reads it")
        ck(c ~= nil, "catalog.lua is shipped")
        ck(c and i and c < i, "…and is likewise loaded before its reader")
        -- CONTINUITY: the retired SavedVariable stays DECLARED for a couple of
        -- releases after its last writer, so a downgrade cannot meet an undeclared
        -- global and old data on disk stays readable.
        ck(toc:find("## SavedVariables: DaseekiArmoryScanDB") ~= nil,
           "the retired scan SavedVariable is still declared (continuity)")
        ck(toc:find("RETIRED") ~= nil,
           "…with the reason and the removal release written beside it")
    end
end)

----------------------------------------------------------------------
-- THE LEGENDARY SWEEP  (owner report, 1.3.1)
--
-- OWNER, verbatim: "the classic wow era legendaries should still display, just
-- only for the classes that can get it. for example, thunderfury is missing now."
--
-- THE DIAGNOSIS, TRACED RATHER THAN GUESSED. Driving the real chain over the
-- owner's own account-1 cache, id 19019 survives EVERY rule:
--
--     names[19019]           = "Thunderfury, Blessed Blade of the Windseeker"
--     meta[19019]            = 5      -> quality 5, internal false
--     Scan.InternalPattern   -> nil            (no denylist pattern touches it)
--     StaticRestrictions     -> absent         (classMask 0, faction 0)
--     StaticUnobtainable     -> absent
--     Scan.RowVerdict(WARRIOR) -> shown = true, rule = "usable"
--     BuildGoalItemDB over the real cache -> 9 240 entries, 19019 among them
--
-- No rule hid it. It was SORTED OFF THE END. The list is ordered by item level,
-- which the client does not hold offline — GetItemInfo answers nil for anything
-- the server has not sent this session and ilvlOf turns that into 0 — so on a
-- freshly opened picker every key is 0, the order collapses onto the alphabetical
-- tie-break, and MAX_RESULTS keeps the first 500 names. Measured on the owner's
-- 9 240 offerable rows: Atiesh sorts at 3.5% and Corrupted Ashbringer at 18.9%
-- (both visible, which is why he said legendaries "should STILL display"), while
-- Sulfuras sorts at 86.5% and Thunderfury at 90.1% and each needs its slot list to
-- be shorter than ~554 rows to survive the cap at all.
--
-- So this suite pins BOTH halves, per item: the right classes see it (filter), and
-- it is never truncated out of the list (order). "Legendaries display correctly"
-- becomes an invariant instead of a per-report fix.
--
-- THE INVENTORY IS A CENSUS, NOT A HAND LIST. Every quality>=5 row in the owner's
-- account-1 cache (10 504 ids, Era build 68940) is 28 rows, and every one of them
-- is now accounted for:
--
--     7   caught by the internal denylist (Blizzard's own legendary-stamped test
--         gear) and therefore never written into catalog.lua at all;
--    12   on the owner-reviewed hidden list — the Ashbringer, the three Azzinoth
--         records, Andonisus, and the seven GM/developer records the owner ruled
--         on 2026-08-05 ("yes hide the gm items");
--     9   genuinely offerable, below.
--
-- Corrupted Ashbringer is carried alongside those nine because the owner counts it
-- a legendary even though this client stamps it Epic (quality 4), which is why the
-- offerable list is 10 rows and not 9.
--
-- THE SEVEN GM RECORDS USED TO BE IN THE OFFERABLE LIST HERE, flagged in their own
-- verdict text as "CANDIDATE for the unobtainable list, owner decision". That is
-- how they reached him: the sweep did not hide them, it did not guess, it stated
-- what it had found and named the decision as his. This is the census working as
-- intended, and the note is left standing as the reason to keep writing verdicts
-- rather than booleans.
----------------------------------------------------------------------
suite("legendary-sweep", function(ck)
    if type(Scan) ~= "table" then ck(false, "itemScan.lua did not load"); return end
    if type(ScanAddon.StaticRestrictions) ~= "table" then
        ck(false, "restrictions.lua did not load"); return
    end
    local SR, UN = ScanAddon.StaticRestrictions, ScanAddon.StaticUnobtainable
    local B, CLASSES = Scan.CLASS_BIT,
        { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
    local function viewer(c, showUnusable)
        return { class = c, classBit = B[c] or 0, faction = Scan.FACTION_NONE,
                 showUnusable = showUnusable and true or false }
    end

    -- ── 1. THE INVENTORY ────────────────────────────────────────────────────
    -- name       the CLIENT's name, lower-cased the way an index entry carries it
    -- verdict    the obtainability reading, stated per item and owner-facing
    local OFFERABLE = {
        { 17142, "shard of the defiler",    5, "legendary-quality quest item the client ships and the scan found; left offerable (fail-open)" },
        { 17182, "sulfuras, hand of ragnaros", 5, "OBTAINABLE — Molten Core; two-handed mace, proficiency is the only gate" },
        { 17782, "talisman of binding shard",    5, "legendary-quality Molten Core quest item; left offerable" },
        { 17783, "talisman of binding fragment", 5, "as 17782" },
        { 19019, "thunderfury, blessed blade of the windseeker", 5, "OBTAINABLE — the owner's reported item; one-handed sword, proficiency is the only gate" },
        { 22589, "atiesh, greatstaff of the guardian", 5, "OBTAINABLE — Naxxramas; class-locked MAGE by shipped static knowledge" },
        { 22630, "atiesh, greatstaff of the guardian", 5, "OBTAINABLE — class-locked WARLOCK" },
        { 22631, "atiesh, greatstaff of the guardian", 5, "OBTAINABLE — class-locked PRIEST" },
        { 22632, "atiesh, greatstaff of the guardian", 5, "OBTAINABLE — class-locked DRUID" },
        { 22691, "corrupted ashbringer", 4, "OBTAINABLE — Naxxramas drop; kept off the unobtainable list on the owner's 2026-08-04 decision" },
    }
    -- The quality>=5 rows the DENYLIST removes: Blizzard's own legendary-stamped
    -- scaffolding. Each must still be condemned by a pattern, because a denylist
    -- that stopped catching these would put "TEST Legendary" at the top of every
    -- list the moment quality started carrying the order.
    local INTERNAL = {
        { 2189,  "Tigole's Boomstick (TEST)" },
        { 3687,  "Deprecated Unholy Avenger" },
        { 3895,  "TEST Legendary" },
        { 5828,  "Ring of Uber Resists (TEST)" },
        { 17802, "Thunderfury, Blessed Blade of the Windseeker DEPRECATED" },
        { 18881, "TEST Ragnaros Hammer" },
        { 19158, "TEST Sulfuras, Hand of Ragnaros" },
    }
    -- The quality>=5 rows the owner-reviewed policy list removes, and WHY each is
    -- on it. The seven GM records joined on the owner's 2026-08-05 decision
    -- ("yes hide the gm items"); before that they were carried in OFFERABLE above
    -- as flagged candidates, which is how they came to his attention.
    local HIDDEN = {
        { 13262, "ashbringer",                    "never itemised on a live Era realm" },
        { 18582, "the twin blades of azzinoth",   "a Burning Crusade record this client happens to carry" },
        { 18583, "warglaive of azzinoth (right)", "as 18582" },
        { 18584, "warglaive of azzinoth (left)",  "as 18582" },
        { 22736, "andonisus, reaper of souls",    "obtainable, but a temporary decaying weapon — not a goal you can keep" },
        { 6698,  "stone of pierce",               "GM/developer record" },
        { 6707,  "stone of lapidis",              "GM/developer record" },
        { 6708,  "stone of goodman",              "GM/developer record" },
        { 6711,  "stone of kurtz",                "GM/developer record" },
        { 6724,  "stone of backus",               "GM/developer record" },
        { 6728,  "stone of brownell",             "GM/developer record" },
        { 12947, "alex's ring of audacity",       "GM/developer record" },
    }

    ck(#OFFERABLE == 10, "the census carries all 10 offerable rows (9 legendary + Corrupted Ashbringer)")
    ck(#HIDDEN == 12, "…and all 12 hidden-by-policy rows")
    ck(Scan.UnobtainableCount() == 12,
       "…which is exactly what the shipped list holds (got " .. Scan.UnobtainableCount() .. ")")

    -- ── 2. NOTHING MAY HIDE THEM BY ACCIDENT ────────────────────────────────
    for _, row in ipairs(OFFERABLE) do
        local id, nm = row[1], row[2]
        ck(Scan.IsUnobtainable(id) == false,
           ("%d (%s) is not on the unobtainable list"):format(id, nm))
        ck(Scan.InternalPattern(nm) == nil,
           ("…and no denylist pattern condemns its live name (%s)"):format(
               tostring(Scan.InternalPattern(nm))))
    end
    -- The twin pair, which is the whole reason the denylist has to be exact: one
    -- real Thunderfury and one Blizzard leftover, one word apart.
    ck(Scan.InternalPattern("thunderfury, blessed blade of the windseeker") == nil
       and Scan.InternalPattern("thunderfury, blessed blade of the windseeker deprecated") ~= nil,
       "THE TWIN PAIR: the real Thunderfury survives the denylist and the DEPRECATED twin does not")
    for _, row in ipairs(INTERNAL) do
        ck(Scan.InternalPattern(row[2]:lower()) ~= nil,
           ("Blizzard's own %q is still condemned by a pattern"):format(row[2]))
    end
    for _, row in ipairs(HIDDEN) do
        local id, nm, why = row[1], row[2], row[3]
        ck(UN[id] == true,
           ("the owner-reviewed hidden id %d (%s) is still hidden — %s"):format(id, nm, why))
        -- HIDDEN MEANS HIDDEN, INCLUDING UNDER "SHOW UNUSABLE". That tick box is
        -- about gear a DIFFERENT character could wear; there is no character
        -- anywhere that can obtain one of these, so revealing them would be a lie
        -- about what the box means. Rule 3 sits ABOVE rule 5 for exactly this.
        local e = { id = id, equipLoc = "INVTYPE_WEAPON", name = nm,
                    classID = Scan.ITEM_CLASS_WEAPON, subclassID = 7 }
        local everShown = false
        for _, c in ipairs(CLASSES) do
            if Scan.Matches(e, "", { INVTYPE_WEAPON = true }, viewer(c, true)) then everShown = true end
        end
        ck(everShown == false,
           ("…and 'Show unusable' does not reveal %d to any of the nine classes"):format(id))
        local shown, rule = Scan.RowVerdict(e, viewer("WARRIOR", true))
        ck(shown == false and rule == "unobtainable",
           ("…the rule that decided %d is 'unobtainable', not something further down"):format(id))
    end

    -- ── 2b. THE ARTIFACT BAND IS FULLY ACCOUNTED FOR ────────────────────────
    -- Classic Era ships no obtainable artifact, so after the 2026-08-05 decision
    -- NO quality-6 row may be offerable. The client holds exactly 13 of them: three
    -- the denylist condemns as test gear, three Warglaives, and the seven GM
    -- records. This asserts the whole band against the SHIPPED catalog rather than
    -- against a list somebody remembered to update.
    local CFG = {}
    local cfn2 = loadfile(P("catalog.lua"))
    if cfn2 and pcall(cfn2, "Daseeki-Armory", CFG) then
        local artifacts, offerableArtifacts, names = 0, 0, {}
        Scan.CatalogEach(function(id, name, q)
            if q >= 6 then
                artifacts = artifacts + 1
                if not Scan.IsUnobtainable(id) then
                    offerableArtifacts = offerableArtifacts + 1
                    names[#names + 1] = id .. " " .. name
                end
            end
        end, CFG.StaticCatalogRaw)
        ck(artifacts == 10,
           "the shipped catalog carries 10 artifact-quality rows (3 of the client's 13 "
           .. "were denylisted at generation time) — got " .. artifacts)
        ck(offerableArtifacts == 0,
           "NO artifact-quality row is offerable: Era ships none (leaked: "
           .. table.concat(names, ", ") .. ")")
    end

    -- ── 3. THE RIGHT CLASSES, PER ITEM ──────────────────────────────────────
    -- The general invariant first: for every offerable id, sweep all 21 weapon
    -- subclasses and all 10 armour subclasses against all 9 classes and require the
    -- picker's answer to be EXACTLY (the shipped lock admits this class) and (the
    -- class is proficient with this subclass). Whatever the item turns out to be,
    -- nothing else is allowed to have an opinion about it.
    local anyLoc = { INVTYPE_WEAPON = true }
    for _, row in ipairs(OFFERABLE) do
        local id, nm = row[1], row[2]
        local mask = select(1, Scan.StaticFor(id))
        local wrong = 0
        for _, classID in ipairs({ Scan.ITEM_CLASS_WEAPON, Scan.ITEM_CLASS_ARMOR }) do
            local top = (classID == Scan.ITEM_CLASS_WEAPON) and 20 or 9
            for sub = 0, top do
                local e = { id = id, equipLoc = "INVTYPE_WEAPON", name = nm,
                            classID = classID, subclassID = sub }
                for _, c in ipairs(CLASSES) do
                    -- if/else, NOT `cond and a or b`: `a` is nil for a subclass the
                    -- class cannot use, which is exactly when the `or` branch fires
                    -- and answers with the wrong proficiency table.
                    local prof
                    if classID == Scan.ITEM_CLASS_WEAPON then prof = Scan.PROF[c].weapon[sub]
                    else                                      prof = Scan.PROF[c].armor[sub] end
                    local lockOK = (mask == 0) or Scan.HasBit(mask, B[c])
                    local want = (prof == true) and lockOK
                    if Scan.Matches(e, "", anyLoc, viewer(c)) ~= want then wrong = wrong + 1 end
                end
            end
        end
        ck(wrong == 0,
           ("%d (%s): lock+proficiency is the WHOLE gate over 279 shapes (%d disagreements)")
           :format(id, nm, wrong))
    end

    -- The named facts the owner gave, against the real item shapes.
    local function offeredTo(id, nm, classID, sub)
        local e = { id = id, equipLoc = "INVTYPE_WEAPON", name = nm,
                    classID = classID, subclassID = sub }
        local out = {}
        for _, c in ipairs(CLASSES) do
            if Scan.Matches(e, "", anyLoc, viewer(c)) then out[#out + 1] = c end
        end
        return table.concat(out, "+")
    end
    ck(offeredTo(19019, "thunderfury, blessed blade of the windseeker", Scan.ITEM_CLASS_WEAPON, 7)
       == "WARRIOR+PALADIN+HUNTER+ROGUE+MAGE+WARLOCK",
       "THUNDERFURY (one-handed sword) is offered to exactly the sword-wielders — got "
       .. offeredTo(19019, "thunderfury", Scan.ITEM_CLASS_WEAPON, 7))
    ck(offeredTo(17182, "sulfuras, hand of ragnaros", Scan.ITEM_CLASS_WEAPON, 5)
       == "WARRIOR+PALADIN+SHAMAN+DRUID",
       "SULFURAS (two-handed mace) is offered to exactly the mace-wielders — got "
       .. offeredTo(17182, "sulfuras", Scan.ITEM_CLASS_WEAPON, 5))
    ck(offeredTo(22691, "corrupted ashbringer", Scan.ITEM_CLASS_WEAPON, 8)
       == "WARRIOR+PALADIN+HUNTER",
       "CORRUPTED ASHBRINGER (two-handed sword) is offered to exactly its wielders — got "
       .. offeredTo(22691, "corrupted ashbringer", Scan.ITEM_CLASS_WEAPON, 8))
    local ATIESH = { [22589] = "MAGE", [22630] = "WARLOCK", [22631] = "PRIEST", [22632] = "DRUID" }
    for _, id in ipairs({ 22589, 22630, 22631, 22632 }) do
        ck(offeredTo(id, "atiesh, greatstaff of the guardian", Scan.ITEM_CLASS_WEAPON, 10)
           == ATIESH[id],
           ("ATIESH %d is offered to %s and to nobody else"):format(id, ATIESH[id]))
    end

    -- ── 4. AND IT MUST SURVIVE THE LIST'S OWN ORDER  (the reported defect) ──
    local A = { ItemScan = Scan }
    local gfn = loadfile(P("goalPicker.lua"))
    ck(gfn ~= nil, "goalPicker.lua compiles")
    local okl = gfn and pcall(gfn, "Daseeki-Armory", A)
    ck(okl == true, "…and loads with no WoW API present")
    local Rows = A.GoalPickerRows
    ck(type(Rows) == "table" and type(Rows.SortAndCap) == "function",
       "the picker publishes its order as a pure function")
    if type(Rows) == "table" and type(Rows.SortAndCap) == "function" then
        local CAP = Rows.MAX_RESULTS
        -- The owner's shape, made deterministic: one legendary whose name sorts
        -- LAST, buried under CAP+200 ordinary rows, on a client that has sent no
        -- item level for anything.
        local function corpus()
            local t = {}
            for i = 1, CAP + 200 do
                t[#t + 1] = { id = 1000 + i, display = ("Common Item %04d"):format(i), quality = 2 }
            end
            t[#t + 1] = { id = 19019,
                          display = "Zzz Thunderfury, Blessed Blade of the Windseeker",
                          quality = 5 }
            return t
        end
        local cold = function() return 0 end
        local qual = function(e) return e.quality end
        local function holds(list, id)
            for _, e in ipairs(list) do if e.id == id then return true end end
            return false
        end

        local sorted = Rows.SortAndCap(corpus(), cold, qual)
        ck(#sorted == CAP, "the cap still holds the list to " .. CAP .. " rows")
        ck(holds(sorted, 19019),
           "THE DEFECT: a legendary the client has sent no item level for is NOT sorted off the end")
        ck(sorted[1] and sorted[1].id == 19019,
           "…it leads the list, because rarity carries the order while levels are unknown")

        -- TEETH. The rule as it was — item level, then the alphabet — must FAIL this
        -- same fixture, or the assertion above is proving nothing.
        local old = corpus()
        table.sort(old, function(a, b) return a.display < b.display end)
        for i = #old, CAP + 1, -1 do old[i] = nil end
        ck(holds(old, 19019) == false,
           "…and the OLD order really did cut it, so this is not a vacuous test")

        -- ITEM LEVEL STILL LEADS once the client has answered: a warm epic with a
        -- higher level outranks a legendary, exactly as before.
        local warm = { { id = 1, display = "Warm Epic",    quality = 4 },
                       { id = 2, display = "Cold Legend",  quality = 5 } }
        local lvl = { [1] = 92, [2] = 80 }
        Rows.SortAndCap(warm, function(e) return lvl[e.id] end, qual)
        ck(warm[1].id == 1, "with real item levels, item level still leads the order")

        -- A TOTAL ORDER, NOT A COMPARATOR THAT CAN CHANGE ITS MIND. table.sort in
        -- Lua 5.1 raises "invalid order function for sorting" on an inconsistent
        -- comparator, and in a picker refresh that is an empty list; the keys are
        -- snapshotted before the sort precisely so it cannot happen. Duplicate
        -- names (the four Atiesh) and duplicate keys are the stress case.
        local dup = {}
        for i = 1, 400 do
            dup[#dup + 1] = { id = i, display = "Atiesh, Greatstaff of the Guardian", quality = 5 }
        end
        local okSort = pcall(Rows.SortAndCap, dup, cold, qual)
        ck(okSort == true, "400 rows sharing one name and one key sort without raising")
        local nilQ = { { id = 1, display = "Seed Row", quality = nil },
                       { id = 2, display = "Scanned Row", quality = 0 } }
        local okNil = pcall(Rows.SortAndCap, nilQ, cold, qual)
        ck(okNil == true, "an entry with no quality at all (a pre-scan seed row) sorts too")
        ck(nilQ[1].id == 2, "…and ranks below a row whose quality is known to be Poor")
    end

    -- ── 5. AND THE CACHE MUST STILL HOLD THEM AFTER A RESCAN ───────────────
    -- The picker can only offer what the scan wrote down. Deleting the restriction
    -- machinery out of recordItem took the Scan.Put with it, so a forced rescan
    -- WIPED the cache (StartItemScan clears it first) and refilled it with nothing
    -- — 10 504 rows to 0 against the owner's own cache — while still announcing a
    -- completed scan. Every legendary above, and every other item, went with it.
    -- This drives the REAL runner over a small id space on the warmest possible
    -- client: if it does not persist here it can never persist.
    local S = {}
    local sfn = loadfile(P("itemScan.lua"))
    ck(sfn ~= nil, "itemScan.lua compiles")
    if sfn and pcall(sfn, "Daseeki-Armory", S) then
        local ITEMS = { [19019] = { "Thunderfury, Blessed Blade of the Windseeker", 5 },
                        [17182] = { "Sulfuras, Hand of Ragnaros", 5 },
                        [22691] = { "Corrupted Ashbringer", 4 },
                        [13789] = { "[PH] Brilliant Dawn Cap", 1 } }
        S.SLOT_INVTYPES = { [16] = { INVTYPE_WEAPON = true } }
        S.Tag  = function() return "[Armory]" end
        S.Wrap = function(_, _, s) return s end
        local Sc = S.ItemScan
        Sc.RANGES = { { 13789, 13789 }, { 17182, 17182 }, { 19019, 19019 }, { 22691, 22691 } }

        local saved = { _G.GetItemInfo, _G.GetItemInfoInstant, _G.GetTime, _G.time,
                        _G.GetBuildInfo, _G.C_Timer, _G.C_Item, _G.CreateFrame,
                        _G.print, _G.DaseekiArmoryScanDB }
        local T = 0
        _G.GetItemInfo = function(id)
            local it = ITEMS[id]; if not it then return nil end
            return it[1], "link", it[2], 80
        end
        _G.GetItemInfoInstant = function(id)
            if not ITEMS[id] then return nil end
            return id, nil, nil, "INVTYPE_WEAPON", "icon", 2, 7
        end
        _G.GetTime       = function() return T end
        _G.time          = function() return 1785900000 end
        _G.GetBuildInfo  = function() return "1.15.9", "68940" end
        _G.C_Timer       = { After = function() end }
        _G.C_Item        = { RequestLoadItemDataByID = function() end }
        _G.print         = function() end
        local stub = { Show = function() end, Hide = function() end, SetScript = function() end,
                       RegisterEvent = function() end, UnregisterAllEvents = function() end }
        _G.CreateFrame   = function() return stub end
        _G.DaseekiArmoryScanDB = Sc.NewCache()

        local cache = S:ItemScanCache()
        Sc.Put(cache, 19019, "Thunderfury, Blessed Blade of the Windseeker", 5)
        local pre = cache.count

        local started = S:StartItemScan({ force = true })
        local ticks = 0
        while S:IsScanning() and ticks < 5000 do
            T = T + Sc.TICK; S:ScanTick(Sc.TICK); ticks = ticks + 1
        end
        local names, q5 = 0, 0
        for id in pairs(cache.names) do
            names = names + 1
            local q = Sc.UnpackMeta(cache.meta[id])
            if q >= 5 then q5 = q5 + 1 end
        end

        _G.GetItemInfo, _G.GetItemInfoInstant, _G.GetTime, _G.time,
        _G.GetBuildInfo, _G.C_Timer, _G.C_Item, _G.CreateFrame,
        _G.print, _G.DaseekiArmoryScanDB =
            saved[1], saved[2], saved[3], saved[4], saved[5],
            saved[6], saved[7], saved[8], saved[9], saved[10]

        ck(started == true, "a forced rescan starts")
        ck(pre == 1, "…over a cache that held a row before it (which force wipes)")
        ck(S:IsScanning() == false, "…and it finishes (" .. ticks .. " ticks)")
        ck(names == 4,
           "A RESCAN WRITES WHAT IT READ: all 4 ids are back in the cache (got " .. names .. ")")
        ck(cache.count == names, "…and the count field agrees with the rows")
        ck(cache.names[19019] == "Thunderfury, Blessed Blade of the Windseeker",
           "…Thunderfury among them, under the client's own name")
        ck(q5 == 2, "…carrying the qualities the client gave (2 legendary rows)")
        ck(Sc.IsComplete(cache) == true,
           "…so the scan reads as COMPLETE and the bundled seed stays retired")
        ck(cache.internalCount == 1,
           "…and the one placeholder among them is still flagged internal")
    else
        ck(false, "itemScan.lua loads for the rescan drive")
    end
end)

----------------------------------------------------------------------
-- THERE IS NO AUTO PATH  (1.3.1)
--
-- WHAT THIS SUITE USED TO BE: "AUTO-SCAN ARMING (release verification N5)". It
-- drove Addon:InitItemScan — the login hook that one-shot the first-run item scan
-- behind a 15-second delay (so the scan never competed with the login burst) and
-- behind a marker (cache.autoScanTried, so it did not nag) — with a recording
-- C_Timer, so the 15-second window could be opened and abandoned the way a logout
-- abandons it.
--
-- IT EXISTED BECAUSE OF A REAL DEFECT worth remembering: the marker was stamped at
-- LOGIN, before the timer was even armed. cache is DaseekiArmoryScanDB —
-- SavedVariables — so a logout, /reload or disconnect inside that window persisted
-- "already tried" for a scan that never ran, and the auto path was then disarmed on
-- that account for ever (IsComplete false + marker true => early return on every
-- subsequent login, silently). The owner's only way out was to find "Rescan Items"
-- in the goal picker by himself.
--
-- THE FIX IS NOW STRUCTURAL RATHER THAN CAREFUL. That whole defect class — a
-- one-shot latch, a window it can be lost in, a delay to tune, a first-run notice
-- to word, and a suite to prove the latch closes in the right place — existed to
-- make a per-account measurement of a CONSTANT reliable. The constant ships in
-- catalog.lua. So the correct assertion is no longer "the latch closes at the right
-- moment"; it is that there is no latch, no timer, no notice and no login hook at
-- all, and that nothing a player can reach starts a scan or touches the retired
-- SavedVariable.
--
-- The runner itself is deliberately NOT asserted away — it is how the shipped files
-- get regenerated for a new client build. What is asserted is that the only door to
-- it is bolted.
----------------------------------------------------------------------
suite("item-scan-no-auto-path", function(ck)
    local A = {}
    local fnc, e = loadfile(P("itemScan.lua"))
    ck(fnc ~= nil, "itemScan.lua compiles: " .. tostring(e))
    if not fnc then return end
    ck(pcall(fnc, "Daseeki-Armory", A), "…and loads with no WoW API present")

    -- ── 1. THE LOGIN HOOK AND ITS MACHINERY ARE GONE ────────────────────────
    ck(A.InitItemScan == nil, "Addon:InitItemScan no longer exists")
    ck(A.AUTO_SCAN_DELAY == nil, "…nor the delay it waited behind")

    local sh = io.open(P("itemScan.lua"), "r")
    ck(sh ~= nil, "itemScan.lua is readable")
    local s = sh and sh:read("*a") or ""
    if sh then sh:close() end
    -- CODE, NOT WORDS. The long comment where the hook used to be names
    -- autoScanTried and AUTO_SCAN_DELAY on purpose — a deletion whose reason
    -- nobody can read gets reinstated by the next person — so these assertions
    -- look for the constructs, not the vocabulary.
    for _, gone in ipairs({ "function Addon:InitItemScan",
                            "Addon%.AUTO_SCAN_DELAY = ",
                            "c%.autoScanTried = true",
                            "cache%.autoScanTried = nil",
                            "print%(Addon:Tag%(%) %.%. \" building the item database" }) do
        ck(s:find(gone) == nil, "the auto path is GONE from itemScan.lua: " .. gone)
    end
    -- C_Timer is what armed it. Nothing in this file should need a timer any more.
    ck(s:find("C_Timer%.After") == nil, "…and nothing here arms a timer at all")

    local ch = io.open(P("core.lua"), "r")
    ck(ch ~= nil, "core.lua is readable")
    if ch then
        local c = ch:read("*a"); ch:close()
        -- the surviving mention is the comment explaining the removal; what must
        -- be gone is the guarded CALL that used to sit in the login sequence.
        ck(c:find("if Addon%.InitItemScan then Addon:InitItemScan%(%) end") == nil,
           "the login path does not call the hook")
        ck(c:find("InitItemScan") ~= nil,
           "…and says in a comment what used to be there and why it went")
    end

    -- ── 2. THE DEV GATE ─────────────────────────────────────────────────────
    ck(type(A.IsDevScanEnabled) == "function", "the dev gate is published")
    ck(type(A.StartDevScan) == "function", "…with a gated starter beside it")
    ck(A.DEV_SCAN_FLAG == "DASEEKI_ARMORY_DEV", "…keyed on a named global")

    -- A GLOBAL, NOT A SAVED SETTING: it evaporates on /reload, so a developer
    -- cannot leave a machine armed and a stray click cannot persist it.
    ck(s:find("_G%[Addon%.DEV_SCAN_FLAG%]") ~= nil, "…read from _G at call time")
    ck(s:find("Addon%.db.-DEV_SCAN") == nil, "…never out of a saved setting")

    local savedFlag = _G.DASEEKI_ARMORY_DEV
    _G.DASEEKI_ARMORY_DEV = nil
    ck(A:IsDevScanEnabled() == false, "with the flag unset the gate is shut")
    -- The refusal must not reach the runner: StartItemScan needs CreateFrame and
    -- GetTime, neither of which exists here, so a leak would raise rather than
    -- return — which is exactly the shape of proof wanted.
    local ok, started, why = pcall(A.StartDevScan, A)
    ck(ok == true, "…and refusing does not raise (" .. tostring(started) .. ")")
    ck(started == false, "…it returns false")
    ck(type(why) == "string" and why:find("developer tool") ~= nil,
       "…with an explanation a player can act on: " .. tostring(why))
    ck(type(why) == "string" and why:find("shipped") ~= nil,
       "…that says the item database is shipped, so nothing is owed")

    -- ARMED, the gate opens — and the call reaches the real runner, which is what
    -- the missing WoW API proves by raising. That failure IS the pass: it can only
    -- happen if the gate let the call through.
    _G.DASEEKI_ARMORY_DEV = true
    ck(A:IsDevScanEnabled() == true, "with the flag armed the gate opens")
    local okArmed, res = pcall(A.StartDevScan, A)
    ck(okArmed == false or res ~= false,
       "…and the call reaches the runner rather than being refused again")
    _G.DASEEKI_ARMORY_DEV = savedFlag

    -- ── 3. NOTHING A PLAYER REACHES TOUCHES THE RETIRED SAVEDVARIABLE ───────
    -- The picker is the surface a player actually uses; the cache binder is what
    -- would CREATE DaseekiArmoryScanDB on an account that never had one.
    local gh = io.open(P("goalPicker.lua"), "r")
    ck(gh ~= nil, "goalPicker.lua is readable")
    if gh then
        local g = gh:read("*a"); gh:close()
        ck(g:find("ItemScanCache") == nil, "the picker never binds the scan cache")
        ck(g:find("DaseekiArmoryScanDB") == nil, "…and never names the SavedVariable")
    end
    local il = io.open(P("iconData.lua"), "r")
    if il then
        local i = il:read("*a"); il:close()
        ck(i:find("ItemScanCache") == nil, "…nor does the icon search index")
        ck(i:find("Scan%.CatalogEach") ~= nil, "…which reads the shipped catalog instead")
        ck(i:find("Addon%.ItemNameDB") == nil, "…and not the retired seed")
    end
    -- ItemScanCache still EXISTS — the developer scan needs it — but it is the only
    -- caller left.
    ck(s:find("function Addon:ItemScanCache") ~= nil,
       "the cache binder survives for the developer path")
    -- Exactly one real call site survives, in StartItemScan. (The other mentions
    -- are the published-surface list and the note explaining the retirement.)
    local binderCalls = 0
    for _ in s:gmatch("local cache = Addon:ItemScanCache%(%)") do binderCalls = binderCalls + 1 end
    ck(binderCalls == 1,
       "…with exactly one caller left, the scan starter (" .. binderCalls .. " call sites)")
end)
----------------------------------------------------------------------
-- SET-LIST REORDER DRAG: the drop bar must sit under the pointer at ANY scale.
--
-- GetCursorPosition() returns RAW screen units; child:GetTop() returns in the
-- scroll child's OWN effective-scale space. The shipped ticker divided the
-- cursor by UIParent's scale and compared the result against child:GetTop(),
-- which agrees only while the list's effective scale equals UIParent's.
--
-- Nothing scales the Armory options pane today, so this was LATENT here — but it
-- is byte-for-byte the shape that broke live in Daseeki-Raid-Prep the week a
-- "List Scale" slider gave the row chain a SetScale (fixed in Raid Prep 1.3.1).
-- The error is PROPORTIONAL to height above the screen's bottom edge, not a
-- constant offset, so the bar drifts further the higher up the list you drag.
--
-- The arithmetic now lives as a pure seam, Addon.SetListDrag.DropLine in
-- options.lua, following the goalPicker.lua precedent (Addon.GoalPickerRows: a
-- UI file's row geometry published as a pure module and driven headlessly). The
-- REAL function is driven below, against the SHIPPED 1.3.1 arithmetic kept here
-- as a RED CONTROL, so these checks demonstrate the bug rather than merely
-- assert the fix.
----------------------------------------------------------------------
suite("setlist-drag-drop-index", function(ck)
    -- options.lua touches exactly one WoW global at load (StaticPopupDialogs).
    -- Stub it, load into a FRESH namespace so nothing here can perturb the
    -- statmath suites, and restore the global afterwards.
    local savedSPD = _G.StaticPopupDialogs
    _G.StaticPopupDialogs = {}
    local A = { SLOTS = {}, ItemScan = {} }
    local fn, err = loadfile(P("options.lua"))
    ck(fn ~= nil, "options.lua compiles" .. (fn and "" or (" -> " .. tostring(err))))
    if not fn then _G.StaticPopupDialogs = savedSPD; return end
    local lok, lerr = pcall(fn, "Daseeki-Armory", A)
    _G.StaticPopupDialogs = savedSPD
    ck(lok, "options.lua loads with no WoW API but StaticPopupDialogs"
            .. (lok and "" or (" -> " .. tostring(lerr))))
    if not lok then return end

    local D = A.SetListDrag
    ck(type(D) == "table", "the pure layer is published as Addon.SetListDrag")
    ck(type(D) == "table" and type(D.DropLine) == "function",
       "…carrying DropLine as the seam the ticker decides through")
    if type(D) ~= "table" or type(D.DropLine) ~= "function" then return end
    local DropLine = D.DropLine

    local ROW_H = 28            -- SET_ROW_H
    local TOP   = 500           -- child:GetTop() in the LIST's own space

    -- The SHIPPED 1.3.1 arithmetic, verbatim in spirit: cursor converted with
    -- UIParent's scale, compared against a list-space top edge.
    local function oldDropLine(childTop, rowH, count, cursorY, uiScale)
        local my   = cursorY / uiScale
        local relY = childTop - my
        local hRow = math.floor(relY / rowH)
        local frac = relY - hRow * rowH
        local line = (frac < rowH / 2) and (hRow + 1) or (hRow + 2)
        return math.max(1, math.min(count + 1, line))
    end

    -- What the player is pointing at, derived from the GEOMETRY rather than from
    -- the implementation: rows run downward from childTop at rowH pitch, and the
    -- half of a row the cursor is in decides before/after.
    local function expected(childTop, rowH, count, listSpaceY)
        local relY = childTop - listSpaceY
        local line = (relY - math.floor(relY / rowH) * rowH < rowH / 2)
                     and (math.floor(relY / rowH) + 1) or (math.floor(relY / rowH) + 2)
        return math.max(1, math.min(count + 1, line))
    end

    -- The client's raw cursor Y for a point the player SEES at `listSpaceY`.
    local function rawFor(listSpaceY, uiScale, paneScale)
        return listSpaceY * uiScale * paneScale
    end

    -- THE IEEE754 SAMPLING TRAP (documented in Raid Prep's GATE DRAG): the sweeps
    -- below step in list space from a HALF-INTEGER offset. Row midpoints sit at
    -- integer list-space heights (TOP - 14 - 28k), so a half-integer sample can
    -- never land on one. Sitting exactly on a boundary would make a
    -- multiply-then-divide round trip decide the strict `<` on the last bit of a
    -- float — that tests IEEE754, not the hit-test. The boundary itself is pinned
    -- separately in (g), at scale 1, where the round trip is exact.
    local function sweep(uiScale, paneScale, count, childTop, fnc)
        local bad = 0
        for k = 0, 79 do
            local y = (childTop or TOP) - (0.5 + 3 * k)
            local got = fnc(rawFor(y, uiScale, paneScale), uiScale * paneScale, uiScale)
            if got ~= expected(childTop or TOP, ROW_H, count, y) then bad = bad + 1 end
        end
        return bad
    end
    local function newAt(count, childTop)
        return function(raw, listScale) return DropLine(childTop, ROW_H, count, raw, listScale) end
    end
    local function oldAt(count, childTop)
        return function(raw, _, uiScale) return oldDropLine(childTop, ROW_H, count, raw, uiScale) end
    end

    -- (a) BASELINE — everything at parity, which is every Armory install TODAY.
    --     Old and new must AGREE here, or the fix would be a regression for the
    --     untouched majority. This is the "nothing changed at scale 1" pin.
    ck(sweep(1.0, 1.0, 6, TOP, newAt(6, TOP)) == 0,
       "(a) scale 1 everywhere: every sampled cursor lands on the slot it is over")
    ck(sweep(1.0, 1.0, 6, TOP, oldAt(6, TOP)) == 0,
       "(a) at parity the OLD math was right too — this fix changes NOTHING today")
    do
        local same = true
        for k = 0, 79 do
            local y = TOP - (0.5 + 3 * k)
            if DropLine(TOP, ROW_H, 6, y, 1.0) ~= oldDropLine(TOP, ROW_H, 6, y, 1.0) then same = false end
        end
        ck(same, "(a) old and new are the SAME function at scale 1 — a latent fix, not a behaviour change")
    end

    -- (b) THE LATENT DEFECT — the list chain takes a 0.8 SetScale (a list-scale
    --     slider, a themed pane scale, a Core window scale). The old math must be
    --     visibly WRONG here; that is the whole point of keeping it.
    do
        local raw = rawFor(TOP - 74.5, 1.0, 0.8)   -- 74.5 below the top -> row 3's lower half
        local want = expected(TOP, ROW_H, 6, TOP - 74.5)
        ck(want == 4, "(b) fixture sanity: 74.5px down a 28px pitch is row 3's lower half -> line 4")
        ck(DropLine(TOP, ROW_H, 6, raw, 1.0 * 0.8) == want,
           "(b) list scaled to 80%: the seam still returns the slot under the pointer")
        ck(oldDropLine(TOP, ROW_H, 6, raw, 1.0) ~= want,
           "(b) RED CONTROL: the shipped math does NOT return that slot")
        ck(oldDropLine(TOP, ROW_H, 6, raw, 1.0) > want,
           "(b) RED CONTROL: and it errs DOWNWARD — the bar would draw below the mouse")
        ck(sweep(1.0, 0.8, 6, TOP, newAt(6, TOP)) == 0,
           "(b) list scaled to 80%: correct across the whole list, top to bottom")
        ck(sweep(1.0, 0.8, 6, TOP, oldAt(6, TOP)) > 0,
           "(b) RED CONTROL: the shipped math is wrong somewhere in that same sweep")
    end

    -- (c) DRIFT, NOT OFFSET — the old error GROWS with height above the screen's
    --     bottom edge. That signature is why Raid Prep's reporter saw the bar
    --     "well below" the mouse near the top of the list and close to it low down.
    do
        local nearTop    = math.abs(oldDropLine(TOP, ROW_H, 40, rawFor(TOP - 5.5, 1.0, 0.8), 1.0)
                                    - expected(TOP, ROW_H, 40, TOP - 5.5))
        local nearBottom = math.abs(oldDropLine(TOP, ROW_H, 40, rawFor(TOP - 200.5, 1.0, 0.8), 1.0)
                                    - expected(TOP, ROW_H, 40, TOP - 200.5))
        ck(nearTop > nearBottom, "(c) RED CONTROL: the old error grows with height (drift, not a constant offset)")
    end

    -- (d) UI SCALE ALONE was NEVER the broken case: with the list at 100% the two
    --     spaces coincide at any UI Scale. Pin that the new math keeps it so —
    --     this is the half a careless "fix" would break.
    do
        for _, ui in ipairs({ 0.53, 0.71, 1.0, 1.25 }) do
            ck(sweep(ui, 1.0, 6, TOP, newAt(6, TOP)) == 0,
               ("(d) UI Scale %.2f, list 100%%: still exact"):format(ui))
            ck(sweep(ui, 1.0, 6, TOP, oldAt(6, TOP)) == 0,
               ("(d) UI Scale %.2f, list 100%%: never broken — pinned"):format(ui))
        end
    end

    -- (e) BOTH off parity: the effective scale COMPOUNDS. Above 100% the old math
    --     drifts the other way, so the bar would draw ABOVE the mouse.
    do
        ck(sweep(0.71, 1.25, 6, TOP, newAt(6, TOP)) == 0,
           "(e) UI Scale 0.71 x list 125%: compounded scale handled")
        ck(sweep(1.35, 0.6, 6, TOP, newAt(6, TOP)) == 0,
           "(e) UI Scale 1.35 x list 60%: compounded the other way too")
        local raw  = rawFor(TOP - 74.5, 0.71, 1.25)
        local want = expected(TOP, ROW_H, 6, TOP - 74.5)
        ck(oldDropLine(TOP, ROW_H, 6, raw, 0.71) < want,
           "(e) RED CONTROL: above 100% the old math errs UPWARD (bar above the mouse)")
        ck(DropLine(TOP, ROW_H, 6, raw, 0.71 * 1.25) == want, "(e) the seam is right in both directions")
    end

    -- (f) SCROLLED LIST — SetVerticalScroll moves the scroll child, so childTop is
    --     simply somewhere else. The index must follow the ROWS, not the viewport.
    do
        local scrolledTop = TOP + 3 * ROW_H
        ck(sweep(1.0, 0.8, 12, scrolledTop, newAt(12, scrolledTop)) == 0,
           "(f) list scrolled down three rows at 80%: index follows the rows, not the viewport")
        ck(sweep(1.0, 1.0, 12, scrolledTop, newAt(12, scrolledTop)) == 0,
           "(f) …and at scale 1 as well")
    end

    -- (g) BOUNDARIES — pinned at scale 1, where the round trip is exact, so the
    --     assertion is about the comparison and not about float representation.
    do
        ck(DropLine(TOP, ROW_H, 5, TOP - 14, 1) == 2,
           "(g) exactly on row 1's midpoint resolves DOWN, once, with no tie")
        ck(DropLine(TOP, ROW_H, 5, TOP - 13.999, 1) == 1,
           "(g) a hair above that midpoint is the slot above — the boundary is where it says")
        ck(DropLine(TOP, ROW_H, 5, TOP, 1) == 1, "(g) exactly on the list's top edge -> the head")
        ck(DropLine(TOP, ROW_H, 5, TOP - 5 * ROW_H, 1) == 6,
           "(g) exactly on the bottom edge of the last row -> past the tail")
    end

    -- (h) CURSOR OUTSIDE THE LIST at five scales: above every row -> the head;
    --     below every row -> one past the tail. Never out of range either way.
    do
        for _, sc in ipairs({ 0.5, 0.8, 1.0, 1.25, 1.5 }) do
            ck(DropLine(TOP, ROW_H, 5, rawFor(9000, 1.0, sc), sc) == 1,
               ("(h) cursor far above the list at scale %d%% -> insert at the head"):format(sc * 100))
            ck(DropLine(TOP, ROW_H, 5, rawFor(-9000, 1.0, sc), sc) == 6,
               ("(h) cursor far below the list at scale %d%% -> insert past the tail"):format(sc * 100))
        end
    end

    -- (i) EMPTY LIST: the only insertion point is 1, at any scale or cursor height.
    do
        ck(DropLine(TOP, ROW_H, 0, 400, 0.8) == 1, "(i) empty list -> insert at 1")
        ck(DropLine(TOP, ROW_H, 0, -9999, 1.0) == 1, "(i) empty list, cursor off-screen low -> 1")
        ck(DropLine(TOP, ROW_H, 0, 99999, 1.35) == 1, "(i) empty list, cursor off-screen high -> 1")
    end

    -- (j) DEGENERATE INPUT never raises and never returns a nil or fractional index.
    do
        local cases = {
            { TOP, ROW_H, 4, 400, nil }, { TOP, ROW_H, 4, 400, 0 },   { TOP, ROW_H, 4, 400, -1 },
            { TOP, ROW_H, 4, nil, 0.8 }, { nil, ROW_H, 4, 400, 0.8 }, { TOP, nil,  4, 400, 0.8 },
            { TOP, 0,     4, 400, 0.8 }, { TOP, ROW_H, nil, 400, 0.8 }, { TOP, ROW_H, -3, 400, 0.8 },
            { TOP, ROW_H, 4, 1 / 0, 0.8 },
        }
        local raised, oor = 0, 0
        for _, c in ipairs(cases) do
            local sok, line = pcall(DropLine, c[1], c[2], c[3], c[4], c[5])
            if not sok then raised = raised + 1
            elseif type(line) ~= "number" or line ~= line or line < 1 or line ~= math.floor(line) then
                oor = oor + 1
            end
        end
        ck(raised == 0, "(j) no degenerate input raises")
        ck(oor == 0,    "(j) every answer is a whole index >= 1")
        ck(DropLine(TOP, ROW_H, 4, 400, nil) == DropLine(TOP, ROW_H, 4, 400, 1),
           "(j) a missing scale falls back to 1, never to a division by zero")
    end

    -- (k) STRUCTURAL — the ticker must decide through the seam, read the SCROLL
    --     CHILD's scale for the hit-test, and keep UIParent's scale for the
    --     movement threshold (which is a screen gesture and was always correct).
    --     The anchor captured in OnMouseDown must stay in that same UIParent
    --     space, or the 5px threshold would compare two different spaces.
    do
        local fh = io.open(P("options.lua"), "r")
        ck(fh ~= nil, "options.lua is readable for the structural pins")
        if fh then
            local src = fh:read("*a"); fh:close()
            ck(src:find("Drag.DropLine(childTop, SET_ROW_H, n, cy, listScale)", 1, true) ~= nil,
               "(k) the drag ticker decides through the pure seam")
            ck(src:find("child:GetEffectiveScale()", 1, true) ~= nil,
               "(k) the hit-test reads the SCROLL CHILD's effective scale")

            local block = src:match("dragTick:SetScript%(\"OnUpdate\", function%(%)(.-)\n    end%)") or ""
            ck(block ~= "", "(k) the drag ticker is locatable")
            ck(block:find("UIParent:GetEffectiveScale()", 1, true) ~= nil,
               "(k) UIParent's scale is still read — for the movement threshold")
            ck(block:find("uiMX", 1, true) ~= nil and block:find("uiMY", 1, true) ~= nil,
               "(k) the UIParent-space cursor is named for what it is")
            ck(block:match("Drag%.DropLine%([^)]*uiM") == nil,
               "(k) REGRESSION PIN: the UIParent-space cursor never reaches the hit-test")
            ck(block:find("childTop %- my") == nil and block:find("relY", 1, true) == nil,
               "(k) REGRESSION PIN: the old inline midpoint arithmetic is gone from the ticker")

            local anchor = src:match("panel%._dragSourceName = self%._name(.-)end%)") or ""
            ck(anchor ~= "", "(k) the OnMouseDown anchor capture is locatable")
            ck(anchor:find("UIParent:GetEffectiveScale()", 1, true) ~= nil,
               "(k) the click anchor is captured in UIParent space — the SAME space the threshold reads")
            ck(anchor:find("GetEffectiveScale", 1, true) ~= nil
               and anchor:find("child:GetEffectiveScale()", 1, true) == nil,
               "(k) …and NOT in the list's space, which would split the threshold across two spaces")
        end
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

    -- catalog.lua is the largest shipped file by an order of magnitude and it is
    -- generated, so the loadfile gate matters more for it than for anything else:
    -- one stray ']' in an item name would close the long-bracket string early and
    -- the addon would fail at login with a syntax error.
    local cl, cle = loadfile(P("catalog.lua"))
    ck(cl ~= nil, "compiles: catalog.lua" .. (cl and "" or (" -> " .. tostring(cle))))

    -- THE GENERATORS are not shipped (they are not in the TOC and never load in
    -- game), but a generator that does not compile is a shipped table nobody can
    -- regenerate, which is the one repair path this design leaves. dev/ also holds
    -- the retired AtlasLoot seed, which is an INPUT to gen-restrictions.lua and
    -- must therefore still load.
    for _, rel in ipairs({ "dev/gen-shared.lua", "dev/gen-restrictions.lua",
                           "dev/gen-catalog.lua", "dev/itemDB-seed.lua" }) do
        local g, ge = loadfile(P(rel))
        ck(g ~= nil, "compiles: " .. rel .. (g and "" or (" -> " .. tostring(ge))))
    end

    -- HEADLESS DISCIPLINE lives in the shared module now, so that is where the
    -- ceilings are asserted — and each generator must actually route through it,
    -- or it would have quietly reintroduced an unbounded loop of its own.
    local sh = io.open(P("dev/gen-shared.lua"), "r")
    ck(sh ~= nil, "the shared generator core is committed")
    if sh then
        local ss = sh:read("*a"); sh:close()
        ck(ss:find("MEM_CEILING_KB") ~= nil and ss:find("ITER_CEILING") ~= nil,
           "…carrying a memory ceiling and an iteration ceiling")
        ck(ss:find("function Shared%.each") ~= nil and ss:find("function Shared%.eachi") ~= nil,
           "…as bounded pairs() and ipairs() both generators use")
        ck(ss:find("minRows") ~= nil,
           "…and it REFUSES a partial cache, so a wiped source cannot generate shipped data")
    end
    for _, rel in ipairs({ "dev/gen-restrictions.lua", "dev/gen-catalog.lua" }) do
        local gh = io.open(P(rel), "r")
        ck(gh ~= nil, rel .. " is committed alongside the file it writes")
        if gh then
            local gs = gh:read("*a"); gh:close()
            ck(gs:find('loadfile%(HERE') ~= nil or gs:find("gen%-shared%.lua") ~= nil,
               rel .. " routes through the shared, ceilinged core")
            ck(gs:find("Shared%.each") ~= nil, "…and walks its inputs through the bounded each()")
        end
    end
    local gc = io.open(P("dev/gen-catalog.lua"), "r")
    if gc then
        local cs = gc:read("*a"); gc:close()
        ck(cs:find('P%("catalog%.lua"%)') ~= nil, "gen-catalog.lua writes catalog.lua itself")
        ck(cs:find("Scan%.IsInternalName") ~= nil,
           "…applying the SHIPPED denylist at generation time, so the two cannot drift")
        ck(cs:find("%[%^\\r\\n%]%+") ~= nil,
           "…and reads its own output back CRLF-safely, the way the addon will")
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
