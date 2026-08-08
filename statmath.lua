--[[
    Daseeki Armory — stat mathematics.

    PURE Lua. Nothing in this file touches a WoW API, a frame, or a global at load
    time, so the whole formula layer is exercised headlessly by
    harness/run-selftests.lua. stats.lua is the thin adapter that reads the game
    APIs and feeds these functions.

    Every formula here is transcribed from CSC_BEHAVIOR_SPEC.md (section numbers
    are quoted per function). That document is a clean-room behavioural spec; no
    third-party source was read.

    Why a separate math layer at all: four of Armory's shipped stat rows were
    wrong because the arithmetic lived inline in a render closure where nothing
    could test it. Formulas now live here with fixtures.
--]]

local _, Addon = ...

local M = {}
Addon.StatMath = M

local floor, ceil, max = math.floor, math.ceil, math.max

-- ═════════════════════════════════════════════════════════════════════════════
-- §5.1 / §6 — Melee and ranged damage
-- ═════════════════════════════════════════════════════════════════════════════
-- UnitDamage / UnitRangedDamage return min/max that are ALREADY fully effective:
-- the physical bonus and the percent modifier are baked in by the client. The
-- displayed range is the raw return, floor/ceil'd and floored at 1. Re-adding the
-- bonus or re-multiplying by the percent modifier double-counts both (the shipped
-- bug: a true 100-150 with +5 phys and x1.1 rendered as 116-171).
function M.DamageDisplayRange(minD, maxD)
    return max(floor(minD or 0), 1), max(ceil(maxD or 0), 1)
end

-- Spacing rule (§5.1): both numbers < 100 -> " - "; otherwise "-".
function M.FormatDamageRange(lo, hi)
    local sep = (lo < 100 and hi < 100) and " - " or "-"
    return tostring(lo) .. sep .. tostring(hi)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- §3 — Classic-Era talent index remap
-- ═════════════════════════════════════════════════════════════════════════════
-- Classic Era reordered what GetTalentInfo(tab, index) returns, so an index that
-- meant "Arcane Instability" in the 1.12 layout points at a different talent on
-- 1.15.x. The remap rebuilds the 1.12 reading order from live (tier, column) data.
--
-- Input: tabs[tab] = { [liveIndex] = { tier = n, column = n }, ... } (dense array).
-- Output: map[tab][legacyIndex] = liveIndex, or nil if the build must abort.
--
-- Algorithm, exactly as specified:
--   * walk each tab's talents BACKWARDS (n..1) recording live index by (tier,column)
--     -- backwards so the lowest live index wins any duplicate cell;
--   * re-walk tier 1..maxTier, column 1..4, assigning sequential legacy indices
--     1,2,3,... to whichever live index occupies that cell;
--   * if ANY tab reports zero talents or zero tiers, abort the whole build (nil),
--     and every later lookup falls straight through to the raw index.
function M.BuildTalentRemap(tabs)
    if type(tabs) ~= "table" then return nil end
    local nTabs = #tabs
    if nTabs == 0 then return nil end

    local map = {}
    for tab = 1, nTabs do
        local list = tabs[tab]
        local n = (type(list) == "table") and #list or 0
        if n == 0 then return nil end                      -- abort the whole build

        local byCell, maxTier = {}, 0
        for i = n, 1, -1 do
            local t = list[i]
            if t and t.tier and t.column then
                byCell[t.tier] = byCell[t.tier] or {}
                byCell[t.tier][t.column] = i
                if t.tier > maxTier then maxTier = t.tier end
            end
        end
        if maxTier == 0 then return nil end                -- abort the whole build

        local legacy, seq = {}, 0
        for tier = 1, maxTier do
            local row = byCell[tier]
            if row then
                for col = 1, 4 do
                    if row[col] then
                        seq = seq + 1
                        legacy[seq] = row[col]
                    end
                end
            end
        end
        map[tab] = legacy
    end
    return map
end

-- Per-tab and per-index fall-through: a missing mapping returns the raw index.
function M.RemapTalentIndex(map, tab, legacyIndex)
    if not map then return legacyIndex end
    local t = map[tab]
    if not t then return legacyIndex end
    return t[legacyIndex] or legacyIndex
end

-- ═════════════════════════════════════════════════════════════════════════════
-- §9.3 — Spell crit from talents (the API does not report it in Classic Era)
-- ═════════════════════════════════════════════════════════════════════════════
M.SCHOOL = { HOLY = 2, FIRE = 3, NATURE = 4, FROST = 5, SHADOW = 6, ARCANE = 7 }

-- `values` is indexed by talent rank -> crit percentage granted at that rank.
-- Note Call of Thunder's rank-5 jump to 6 (not 5) -- that is the game's own table.
M.SPELL_CRIT_TALENTS = {
    MAGE = {
        { tree = "Arcane", talent = "Arcane Instability", values = { 1, 2, 3 },          schools = { "ALL" } },
        { tree = "Fire",   talent = "Critical Mass",      values = { 2, 4, 6 },          schools = { "FIRE" } },
    },
    PRIEST = {
        { tree = "Holy",       talent = "Holy Specialization", values = { 1, 2, 3, 4, 5 }, schools = { "HOLY" } },
        { tree = "Discipline", talent = "Force of Will",       values = { 1, 2, 3, 4, 5 }, schools = { "HOLY" } },
    },
    WARLOCK = {
        { tree = "Destruction", talent = "Devastation", values = { 1, 2, 3, 4, 5 }, schools = { "SHADOW", "FIRE" } },
    },
    SHAMAN = {
        { tree = "Elemental",   talent = "Call of Thunder", values = { 1, 2, 3, 4, 6 }, schools = { "LIGHTNING" } },
        { tree = "Restoration", talent = "Tidal Mastery",   values = { 1, 2, 3, 4, 5 }, schools = { "LIGHTNING", "NATURE" } },
    },
}

M.BENEDICTION_ITEM_ID = 18608   -- Priest staff: +2 Holy crit the API never reports

-- base: { [2..7] = GetSpellCritChance(school) }.  ranks: { [talentName] = rank }.
-- Returns a table keyed [2..7] plus a synthetic .LIGHTNING (starts as a copy of
-- Nature, per spec).
function M.SpellCritBySchool(class, base, ranks, hasBenediction)
    local out = {}
    for s = 2, 7 do out[s] = (base and base[s]) or 0 end
    out.LIGHTNING = out[M.SCHOOL.NATURE]

    local entries = M.SPELL_CRIT_TALENTS[class]
    if entries then
        for _, e in ipairs(entries) do
            local rank = (ranks and ranks[e.talent]) or 0
            local v = (rank > 0) and e.values[rank] or nil
            if v then
                for _, sc in ipairs(e.schools) do
                    if sc == "ALL" then
                        for s = 2, 7 do out[s] = out[s] + v end
                        out.LIGHTNING = out.LIGHTNING + v
                    elseif sc == "LIGHTNING" then
                        out.LIGHTNING = out.LIGHTNING + v
                    else
                        local idx = M.SCHOOL[sc]
                        out[idx] = out[idx] + v
                    end
                end
            end
        end
    end

    if class == "PRIEST" and hasBenediction then
        out[M.SCHOOL.HOLY] = out[M.SCHOOL.HOLY] + 2
    end
    return out
end

-- Armory shows ONE "Spell Crit" row (no per-school crit tooltip), so the headline
-- is the best school available to the player. Lightning is folded in for Shamans:
-- excluding it would leave Call of Thunder unrepresented anywhere in the UI, which
-- is the exact understatement this fix exists to remove.
function M.MaxSpellCrit(bySchool)
    local best = 0
    for s = 2, 7 do
        local v = bySchool[s] or 0
        if v > best then best = v end
    end
    local l = bySchool.LIGHTNING or 0
    if l > best then best = l end
    return best
end

-- ═════════════════════════════════════════════════════════════════════════════
-- §9.5 — Mana regen
-- ═════════════════════════════════════════════════════════════════════════════
-- GetManaRegen() is broken on Classic Era: both returns carry the same figure and
-- the "casting" return is unusable. Everything below reconstructs the two real
-- numbers from the base (spirit) regen plus gear, auras and casting-regen talents.

-- Permanent/temporary enchant MP5 sources, keyed by enchant id.
M.MP5_ENCHANTS = {
    WRIST        = { id = 2565, mp5 = 4,  slot = 9  },  -- Mana Regeneration
    SHOULDER     = { id = 2715, mp5 = 5,  slot = 3  },  -- Resilience of the Scourge
    PRIEST_HEAD  = { id = 2590, mp5 = 4,  slot = 1  },  -- Zul'Gurub (Priest only)
    PRIEST_LEGS  = { id = 2590, mp5 = 4,  slot = 7  },  -- Zul'Gurub (Priest only)
    MAINHAND_OIL = { id = 2629, mp5 = 12 },             -- Brilliant Mana Oil (temporary)
}

-- The client under-reports item MP5 by exactly 1 per contributing item, so every
-- item that carries the stat contributes (value + 1). Without this every MP5 piece
-- reads one low.
function M.GearMP5FromItemStats(perItemValues)
    local total = 0
    for i = 1, #perItemValues do
        local v = perItemValues[i]
        if v and v ~= 0 then total = total + v + 1 end
    end
    return total
end

M.AURA_MP5 = {
    -- Blessing of Wisdom
    [19742] = 10, [19850] = 15, [19852] = 20, [19853] = 25, [19854] = 30, [25290] = 33,
    -- Greater Blessing of Wisdom
    [25894] = 30, [25918] = 33,
    -- Mana Spring Totem
    [5675]  = 10, [10495] = 15, [10496] = 20, [10497] = 25,
    -- Consumables
    [24363] = 12,   -- Mageblood Potion
    [18194] = 8,    -- Nightfin Soup
}

-- Only these are scaled by a Paladin's Improved Blessing of Wisdom.
M.AURA_IS_WISDOM = {
    [19742] = true, [19850] = true, [19852] = true, [19853] = true,
    [19854] = true, [25290] = true, [25894] = true, [25918] = true,
}

-- Auras that let a fraction of base spirit regen persist while casting.
M.COMBAT_REGEN_AURA = { [6117] = 0.30, [22782] = 0.30, [22783] = 0.30 }  -- Mage Armor

-- spellIds: flat array of the player's own helpful aura spell ids.
-- Returns (flat MP5 from auras, casting-regen fraction contributed by auras).
function M.AuraMP5(spellIds, improvedWisdomRank)
    local mp5, combatFrac = 0, 0
    local mult = 1 + (improvedWisdomRank or 0) * 0.1
    for i = 1, #spellIds do
        local id = spellIds[i]
        local v = M.AURA_MP5[id]
        if v then
            if M.AURA_IS_WISDOM[id] then v = v * mult end
            mp5 = mp5 + v
        end
        local f = M.COMBAT_REGEN_AURA[id]
        if f then combatFrac = combatFrac + f end
    end
    return mp5, combatFrac
end

-- Meditation-style talents: 0.05 per rank (Priest Meditation, Mage Arcane
-- Meditation, Druid Reflection).  Druid/Priest 3+ pieces across Vestments of
-- Transcendence + Stormrage Raiment (one combined tally): +0.15.
M.MEDITATION_TALENTS = {
    PRIEST = { { tree = "Discipline", talent = "Meditation" } },
    MAGE   = { { tree = "Arcane",     talent = "Arcane Meditation" } },
    DRUID  = { { tree = "Balance",    talent = "Reflection" } },
}
M.MEDITATION_PER_RANK = 0.05

M.CASTING_REGEN_SET_IDS = {}   -- Vestments of Transcendence + Stormrage Raiment
for id = 16919, 16926 do M.CASTING_REGEN_SET_IDS[id] = true end
for id = 16897, 16904 do M.CASTING_REGEN_SET_IDS[id] = true end

function M.CastingModifier(class, talentRankSum, tierSetPieces, auraCombatFraction)
    local mod = (talentRankSum or 0) * M.MEDITATION_PER_RANK + (auraCombatFraction or 0)
    if (class == "DRUID" or class == "PRIEST") and (tierSetPieces or 0) >= 3 then
        mod = mod + 0.15
    end
    return mod
end

-- The API transiently reports < 1 right after a stat change; substitute the last
-- good reading rather than flashing a 0 on every gear swap.
function M.ZeroFlashGuard(value, lastSeen)
    if not value or value < 1 then return lastSeen or 0 end
    return value
end

-- basePerSec is GetManaRegen()'s FIRST return (mana per second, not casting).
-- Both outputs are mana per 5 seconds.
function M.ManaRegenRows(basePerSec, gearMP5, auraMP5, castingModifier)
    basePerSec = basePerSec or 0
    gearMP5, auraMP5 = gearMP5 or 0, auraMP5 or 0
    local notCasting = basePerSec * 5.0 + gearMP5 + auraMP5
    local casting    = gearMP5 + auraMP5
    if (castingModifier or 0) > 0 then
        casting = casting + basePerSec * castingModifier * 5.0
    end
    return notCasting, casting
end

-- ═════════════════════════════════════════════════════════════════════════════
-- §7.2 — Defense
-- ═════════════════════════════════════════════════════════════════════════════
-- Value comes from the Defense skill line (rank + modifier), never below 0.
-- UnitDefense is a fallback only; it does not report the full picture in Era.
function M.DefenseValue(rank, modifier)
    return max(0, (rank or 0) + (modifier or 0))
end

-- ═════════════════════════════════════════════════════════════════════════════
-- §7.4 — Block value
-- ═════════════════════════════════════════════════════════════════════════════
M.BATTLEGEAR_OF_MIGHT_IDS = {}
for id = 16861, 16868 do M.BATTLEGEAR_OF_MIGHT_IDS[id] = true end
M.BATTLEGEAR_SET_BONUS_PIECES = 3
M.BATTLEGEAR_SET_BONUS_VALUE  = 30
M.WARRIOR_ZG_BLOCK_ENCHANT_ID = 2583   -- head/legs, +15 each
M.WARRIOR_ZG_BLOCK_ENCHANT_VALUE = 15

-- tooltipSum: every block-value number scraped off equipped slots 1..18.
-- The Strength/20 term is part of the default (own-calculation) source; the
-- Blizzard alternative (GetShieldBlock) carries no strength, set or enchant terms.
--
-- ARM-1 / Class 5 (SUITE_DATA_HONESTY_AUDIT 2026-08-07): tooltipSum NIL means the
-- gear scan could not prove a single slot warm, and there is no block value to
-- report — this returns nil and the row renders "—". A tooltipSum of 0 is the
-- opposite: a scan that ran, proved every slot, and found no block value on any of
-- them. 0 is an answer; nil is absence, and they used to render the same number.
function M.BlockValue(tooltipSum, strength, battlegearPieces, warriorZGEnchantCount)
    if tooltipSum == nil then return nil end
    local v = tooltipSum + (strength or 0) / 20
    if (battlegearPieces or 0) >= M.BATTLEGEAR_SET_BONUS_PIECES then
        v = v + M.BATTLEGEAR_SET_BONUS_VALUE
    end
    v = v + (warriorZGEnchantCount or 0) * M.WARRIOR_ZG_BLOCK_ENCHANT_VALUE
    return v
end

-- ═════════════════════════════════════════════════════════════════════════════
-- §6 — Ranged hit
-- ═════════════════════════════════════════════════════════════════════════════
M.SCOPE_ENCHANT_ID    = 2523   -- +3% hit, ranged slot (18)
M.SCOPE_ENCHANT_VALUE = 3

function M.RangedHit(hitModifier, hasScopeEnchant)
    return (hitModifier or 0) + (hasScopeEnchant and M.SCOPE_ENCHANT_VALUE or 0)
end

-- Permanent enchant id out of an item link's `item:<id>:<enchant>:` fields.
function M.EnchantIdFromLink(link)
    if type(link) ~= "string" then return nil end
    local enchant = link:match("item:%d+:(%d*)")
    if not enchant or enchant == "" then return nil end
    return tonumber(enchant)
end

return M
