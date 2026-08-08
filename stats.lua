--[[
    Daseeki Armory — character statistics.

    A full read-only stat breakdown, rendered two ways from ONE data layer:
      * a "Stats" section in the Armory hub (DaseekiUI flow), and
      * an optional compact panel attached to the right of the character window.

    This is the game-API adapter. The arithmetic lives in statmath.lua, which is
    pure Lua and covered by harness/run-selftests.lua. Formula behaviour follows
    CSC_BEHAVIOR_SPEC.md (a clean-room behavioural spec); section numbers are
    cited per stat. Several stats deliberately do NOT trust the raw API — see the
    damage, mana-regen, spell-crit and defense notes below.

    APIs used here are verified present in the local 1.15.9 API catalog.

    Live-updates on the stat/rating/damage-mod event family (coalesced to one refresh
    per frame-ish via a dirty flag). Layout is token-driven per DREW_UI_STYLE:
    two-column compact stat blocks, labeled, hugging their natural width.

    Daseeki-Core is an OptionalDep: every DaseekiUI touch is nil-guarded and the
    panel cleanly no-ops without it (see Addon:StatsUIReady).
--]]

local _, Addon = ...

local SM = Addon.StatMath          -- pure formula layer (statmath.lua, loaded first)

-- ── Formatting ────────────────────────────────────────────────────────────────
local function N(v)   v = v or 0; return tostring(math.floor(v + 0.5)) end
local function PCT(v) return string.format("%.2f%%", v or 0) end

local NA = "—"                     -- not applicable (no ranged weapon, no mana, …)

-- Debug channel for the "this contribution was skipped" cases below. Rides the
-- existing chatMessages setting — no new SavedVariable.
function Addon:StatDebug(msg)
    if Addon.db and Addon.db.settings and Addon.db.settings.chatMessages then
        print(Addon:Tag() .. " stats: " .. tostring(msg))
    end
end

-- ── Talent reads (CSC_BEHAVIOR_SPEC §3) ───────────────────────────────────────
-- Classic Era reordered GetTalentInfo's indices, so the 1.12-era (tab, index)
-- constants read the WRONG talent on 1.15.x. Every talent-derived number below
-- goes through the tier/column remap.
--
-- We do not have the 1.12 index constants (clean-room: the spec gives talent NAMES
-- and trees, not indices), so the legacy index for each spec talent is discovered
-- once at PLAYER_ENTERING_WORLD by walking legacy order 1..n through the remap and
-- matching the live talent name. That makes the remap load-bearing for every read
-- AND gives us the name guard the spec demands: the name is re-verified on every
-- read, and a mismatch skips the contribution (rather than silently misreading a
-- neighbouring talent) and logs through StatDebug.
--
-- Consequence on non-enUS clients: the spec's English talent names will not match,
-- the talent resolves to nil, and its contribution is skipped. That is the safe
-- direction — understated, never wrong-talent.

-- ARM-2 (SUITE_DATA_HONESTY_AUDIT, Class 5): "the tree answered and there is no
-- remap" and "the tree could not be read" used to write the same `false`, which is
-- a calibration learned once from a cold client and held for the session. They are
-- separated now: an unreadable tree leaves _talentRemap NIL (unknown) and raises
-- _talentRemapCold, which TalentRank retries against on every read until the tree
-- answers. Returns true when the tree answered, false when it could not be read.
function Addon:BuildTalentRemap()
    Addon._talentSlots = nil
    local nTabs = (GetNumTalentTabs and GetNumTalentTabs()) or 0
    if nTabs == 0 then
        -- 0 tabs is not "this character has no talents" — every character has three.
        Addon._talentRemap     = nil
        Addon._talentRemapCold = true
        return false
    end

    local tabs = {}
    for tab = 1, nTabs do
        local n = (GetNumTalents and GetNumTalents(tab)) or 0
        local list = {}
        for i = 1, n do
            -- Classic GetTalentInfo -> name, icon, tier, column, rank, maxRank, …
            local _, _, tier, column = GetTalentInfo(tab, i)
            list[i] = { tier = tier, column = column }
        end
        tabs[tab] = list
    end
    -- Every tab enumerated at least one talent, so a nil from SM.BuildTalentRemap
    -- here is a genuine "this layout needs no remap", not a cold read.
    Addon._talentRemap     = SM.BuildTalentRemap(tabs) or false
    Addon._talentRemapCold = nil
    return true
end

local function talentTabByName(treeName)
    if not treeName or not GetTalentTabInfo then return nil end
    for tab = 1, ((GetNumTalentTabs and GetNumTalentTabs()) or 0) do
        if GetTalentTabInfo(tab) == treeName then return tab end
    end
end

local function resolveTalent(tree, talentName)
    Addon._talentSlots = Addon._talentSlots or {}
    local key = tostring(tree) .. "|" .. talentName
    local cached = Addon._talentSlots[key]
    if cached ~= nil then return cached or nil end

    local map   = Addon._talentRemap or nil
    local nTabs = (GetNumTalentTabs and GetNumTalentTabs()) or 0
    -- Prefer the spec's tree; fall back to every other tab so a renamed/moved tree
    -- still resolves.
    local order, preferred = {}, talentTabByName(tree)
    if preferred then order[#order + 1] = preferred end
    for tab = 1, nTabs do if tab ~= preferred then order[#order + 1] = tab end end

    -- ARM-2: the tree has only "answered" if it named tabs AND every tab it named
    -- enumerated talents. A tab reporting zero talents is a cold read, not an empty
    -- tree — and a negative learned from one latches for the session.
    local answered = (nTabs > 0)
    for _, tab in ipairs(order) do
        local n = (GetNumTalents and GetNumTalents(tab)) or 0
        if n == 0 then answered = false end
        for legacy = 1, n do
            local live = SM.RemapTalentIndex(map, tab, legacy)
            if GetTalentInfo(tab, live) == talentName then
                Addon._talentSlots[key] = { tab = tab, legacy = legacy }
                return Addon._talentSlots[key]
            end
        end
    end

    if not answered then
        -- NO CACHE WRITE. The same function already re-resolves on a name mismatch
        -- (TalentRank below); this is the other half of that discipline — a miss we
        -- cannot prove is a miss leaves the key unresolved so the next read retries.
        Addon:StatDebug("talent tree not readable yet — '" .. talentName .. "' left unresolved")
        return nil
    end

    Addon._talentSlots[key] = false
    Addon:StatDebug("talent '" .. talentName .. "' not found (non-English client?) — contribution skipped")
    return nil
end

-- Rank of a spec talent, read through the remap with a name re-verification.
-- Returns 0 when unresolvable or when the name check fails.
function Addon:TalentRank(tree, talentName)
    if not (GetTalentInfo and GetNumTalents) then return 0 end
    -- ARM-2: a remap that could not be built because the tree was unreadable is
    -- UNKNOWN, not "there is no remap". Retry before every read until it answers —
    -- one GetNumTalentTabs() call, and only while the flag is up. PLAYER_ENTERING_WORLD
    -- rebuilds too, but a character who logs in and reads their sheet without zoning
    -- never gets that event, which is the whole finding.
    if Addon._talentRemapCold then Addon:BuildTalentRemap() end
    local slot = resolveTalent(tree, talentName)
    if not slot then return 0 end
    local live = SM.RemapTalentIndex(Addon._talentRemap or nil, slot.tab, slot.legacy)
    local name, _, _, _, rank = GetTalentInfo(slot.tab, live)
    if name ~= talentName then
        Addon:StatDebug(string.format(
            "talent tab %d legacy %d remapped to '%s', expected '%s' — contribution skipped",
            slot.tab, slot.legacy, tostring(name), talentName))
        Addon._talentSlots[tostring(tree) .. "|" .. talentName] = nil   -- re-resolve next read
        return 0
    end
    return rank or 0
end

-- ── Equipped-gear scan (MP5, block value, tier-set tallies) ───────────────────
-- Cached and only rebuilt when equipment changes; the tooltip scrape is far too
-- expensive to run on every UNIT_AURA-driven refresh.
--
-- ARM-1 (SUITE_DATA_HONESTY_AUDIT, Class 4). THE CACHE IS ONLY WRITTEN FROM A
-- PROVEN SCAN. Equipped item data lands a beat after the first stat-panel paint;
-- a scanning tooltip pointed at a cold slot renders its TITLE and nothing else, so
-- the block-value walk sums to 0 — indistinguishable from "this gear grants no
-- block value" — and memoizing that made the wrong number stand until the player
-- changed gear or took a loading screen. Now: an unproven slot is UNKNOWN, the
-- whole scan is marked unproven, nothing is memoized, a warm load is requested for
-- every cold id, and GET_ITEM_INFO_RECEIVED repaints (see EVENTS at the bottom).
local gearCache

function Addon:InvalidateStatGearCache() gearCache = nil end

-- Count of equipped slots the last scan could not prove warm. > 0 means the
-- streaming item-info events are worth a repaint; 0 is the settled state.
Addon._statGearUnproven = 0

-- The wait is event-driven WITH A CEILING (Class 4 fix shape). GET_ITEM_INFO_RECEIVED
-- arrives in bursts for every item any addon touches, and an id that never resolves
-- would otherwise re-scan eighteen tooltips on each one for the rest of the session.
-- Spending the budget does not make the panel lie: the rows stay "—", which is still
-- the honest answer. Any equipment change or loading screen re-arms it.
local WARM_REPAINT_CEILING = 40
Addon._statWarmBudget = WARM_REPAINT_CEILING
function Addon:RearmStatWarmBudget() Addon._statWarmBudget = WARM_REPAINT_CEILING end

local scanTip
local function ensureScanTip()
    if scanTip then return scanTip end
    scanTip = CreateFrame("GameTooltip", "DaseekiArmoryStatScanTooltip", UIParent, "GameTooltipTemplate")
    scanTip:SetOwner(_G.WorldFrame or UIParent, "ANCHOR_NONE")
    return scanTip
end

local function escapePattern(s) return (s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")) end

-- CSC §7.4: match the three block-value stat strings in BOTH word orders
-- ("<number> <stat>" and "<stat> <number>"). Longest stat string first so
-- "Block Rating" wins over "Block" and one line is never counted twice.
local BLOCK_STAT_GLOBALS = { "ITEM_MOD_BLOCK_RATING_SHORT", "ITEM_MOD_BLOCK_RATING", "ITEM_MOD_BLOCK_VALUE" }
local blockPatterns
local function blockValuePatterns()
    if blockPatterns then return blockPatterns end
    local bodies = {}
    for _, g in ipairs(BLOCK_STAT_GLOBALS) do
        local s = _G[g]
        if type(s) == "string" then
            -- strip the format specifier and trailing punctuation the strings carry
            local body = s:gsub("%%%d?%$?[dsf]", ""):gsub("[%.:%s]+$", ""):gsub("^[%.:%s]+", "")
            if #body >= 4 then bodies[#bodies + 1] = body end
        end
    end
    table.sort(bodies, function(a, b) return #a > #b end)
    local out = {}
    for _, body in ipairs(bodies) do
        local e = escapePattern(body)
        out[#out + 1] = "%+?(%d+)%s+" .. e
        out[#out + 1] = e .. "%s*:?%s*%+?(%d+)"
    end
    -- Class 5: an EMPTY result is not memoized. These globals are static, but a
    -- pattern table learned once from a client that had not published them yet
    -- would be an empty answer held for the rest of the session.
    if #out > 0 then blockPatterns = out end
    return out
end

-- ARM-1. Returns the block-value sum for one equipped slot, or NIL when the slot
-- could not be proven warm — because a cold slot's sum is 0 and a shield with no
-- block value on it also sums to 0, and those are different facts.
--
-- Two independent proofs, per the audit's fix shape. Either is sufficient:
--   * C_Item.IsItemDataCachedByID(id) — the client's own answer, where the build
--     has it (the TOC spans three interface versions, so it is not assumed);
--   * tip:NumLines() > 1 — a tooltip that rendered its title and nothing else is
--     exactly the proven Class 4 shape, and it is the ONLY proof available on a
--     build with no C_Item. It also catches an item the client thinks it has
--     cached but whose tooltip has not been built yet.
local function scanBlockValueOnSlot(slotId, itemId)
    local pats = blockValuePatterns()
    -- No stat strings to match means no answer, not a zero.
    if #pats == 0 then return nil end

    if itemId and _G.C_Item and _G.C_Item.IsItemDataCachedByID then
        local okC, cached = pcall(_G.C_Item.IsItemDataCachedByID, itemId)
        if okC and not cached then return nil end
    end

    local tip = ensureScanTip()
    tip:ClearLines()
    tip:SetOwner(_G.WorldFrame or UIParent, "ANCHOR_NONE")
    local ok = pcall(tip.SetInventoryItem, tip, "player", slotId)
    if not ok then return nil end                       -- a raise is not a zero
    local lines = tip:NumLines() or 0
    if lines <= 1 then return nil end                   -- title-only: the body is not here yet

    local sum = 0
    for i = 1, lines do
        local fs = _G["DaseekiArmoryStatScanTooltipTextLeft" .. i]
        local text = fs and fs:GetText()
        if text then
            for _, pat in ipairs(pats) do
                local n = text:match(pat)
                if n then sum = sum + tonumber(n); break end   -- one number per line
            end
        end
    end
    return sum
end

-- Ask the client for an item whose data we could not read. Same ask goalPicker.lua
-- makes, and the reason GET_ITEM_INFO_RECEIVED will fire for gear the server has
-- never sent this session.
local function requestWarm(itemId)
    if not itemId then return end
    if _G.C_Item and _G.C_Item.RequestLoadItemDataByID then
        pcall(_G.C_Item.RequestLoadItemDataByID, itemId)
    end
end

local function scanGear()
    if gearCache then return gearCache end
    local _, class = UnitClass("player")
    local mp5Values, blockSum, battlegear, zgBlock, tierPieces = {}, 0, 0, 0, 0
    local unproven = 0

    for slotId = 1, 18 do
        local link = GetInventoryItemLink("player", slotId)
        if link then
            local id = tonumber(link:match("item:(%d+)"))

            -- The block walk is the warmth oracle for the whole slot: nil means the
            -- tooltip body was not there, and GetItemStats is cold in the same breath.
            local slotBlock = scanBlockValueOnSlot(slotId, id)
            if slotBlock == nil then
                unproven = unproven + 1
                requestWarm(id)
            else
                blockSum = blockSum + slotBlock

                local okStats, stats = pcall(GetItemStats, link)
                if okStats and type(stats) == "table" then
                    local v = stats["ITEM_MOD_POWER_REGEN0_SHORT"]
                    if v and v ~= 0 then mp5Values[#mp5Values + 1] = v end
                end
            end

            -- Link-derived facts (set ids, enchant ids) need no item data at all —
            -- they are in the link the client already handed us, so they stay exact
            -- even while the body is cold.
            if id then
                if SM.BATTLEGEAR_OF_MIGHT_IDS[id] then battlegear = battlegear + 1 end
                if SM.CASTING_REGEN_SET_IDS[id]   then tierPieces = tierPieces + 1 end
            end

            local ench = SM.EnchantIdFromLink(link)
            if class == "WARRIOR" and (slotId == 1 or slotId == 7)
               and ench == SM.WARRIOR_ZG_BLOCK_ENCHANT_ID then
                zgBlock = zgBlock + 1
            end
        end
    end

    -- Flat MP5 enchant sources (§9.5 step 4).
    local mp5 = SM.GearMP5FromItemStats(mp5Values)
    local function slotEnchant(slotId)
        return SM.EnchantIdFromLink(GetInventoryItemLink("player", slotId))
    end
    if slotEnchant(9) == SM.MP5_ENCHANTS.WRIST.id    then mp5 = mp5 + SM.MP5_ENCHANTS.WRIST.mp5 end
    if slotEnchant(3) == SM.MP5_ENCHANTS.SHOULDER.id then mp5 = mp5 + SM.MP5_ENCHANTS.SHOULDER.mp5 end
    if class == "PRIEST" then
        if slotEnchant(1) == SM.MP5_ENCHANTS.PRIEST_HEAD.id then mp5 = mp5 + SM.MP5_ENCHANTS.PRIEST_HEAD.mp5 end
        if slotEnchant(7) == SM.MP5_ENCHANTS.PRIEST_LEGS.id then mp5 = mp5 + SM.MP5_ENCHANTS.PRIEST_LEGS.mp5 end
    end

    Addon._statGearUnproven = unproven

    local scan = {
        -- nil, not 0: the two tooltip-derived sums have no answer while any slot is
        -- cold, and their consumers render "—" rather than a number that is short.
        mp5 = (unproven == 0) and mp5 or nil,
        blockValue = (unproven == 0) and blockSum or nil,
        battlegear = battlegear, zgBlockEnchants = zgBlock,
        tierPieces = tierPieces, class = class, unproven = unproven,
    }
    if unproven > 0 then
        Addon:StatDebug(unproven .. " equipped slot(s) not warm yet — gear scan not cached")
        return scan                        -- DELIBERATELY NOT MEMOIZED
    end
    gearCache = scan
    return gearCache
end

-- Temporary main-hand weapon enchant (Brilliant Mana Oil) is not gear-cached: it
-- expires on a timer, so it is read live.
local function temporaryMainHandMP5()
    if not GetWeaponEnchantInfo then return 0 end
    local hasMain, _, _, mainEnchantId = GetWeaponEnchantInfo()
    if hasMain and mainEnchantId == SM.MP5_ENCHANTS.MAINHAND_OIL.id then
        return SM.MP5_ENCHANTS.MAINHAND_OIL.mp5
    end
    return 0
end

-- ── Compute helpers (game APIs only) ──────────────────────────────────────────
local function stat(i)  return N(select(2, UnitStat("player", i))) end          -- effectiveStat
local function armor()  return N(select(2, UnitArmor("player"))) end            -- effectiveArmor

local function meleeAP()
    local base, pos, neg = UnitAttackPower("player")
    return N((base or 0) + (pos or 0) + (neg or 0))
end
local function rangedAP()
    local base, pos, neg = UnitRangedAttackPower("player")
    return N((base or 0) + (pos or 0) + (neg or 0))
end

-- CSC §5.1: UnitDamage's min/max are ALREADY fully effective. The display range is
-- the raw return; re-adding the physical bonus or re-applying the percent modifier
-- double-counts both (the pre-fix behaviour).
local function meleeDamage()
    local minD, maxD = UnitDamage("player")
    return SM.FormatDamageRange(SM.DamageDisplayRange(minD, maxD))
end
local function meleeSpeed()
    local m, o = UnitAttackSpeed("player")
    if o and o > 0 then return string.format("%.2f / %.2f", m or 0, o) end
    return string.format("%.2f", m or 0)
end

-- ── Ranged (CSC §6): every row is N/A without a ranged weapon ─────────────────
local function hasRangedWeapon() return (IsRangedWeapon and IsRangedWeapon()) and true or false end
local function hasWandEquipped() return (HasWandEquipped and HasWandEquipped()) and true or false end

local function rangedRow(fn)
    return function()
        if not hasRangedWeapon() then return NA end
        return fn()
    end
end

local function rangedDamage()
    -- UnitRangedDamage -> (speed, min, max, posBuff, negBuff, percent); same rule.
    local _, minD, maxD = UnitRangedDamage("player")
    return SM.FormatDamageRange(SM.DamageDisplayRange(minD, maxD))
end
local function rangedSpeed()
    local speed = UnitRangedDamage("player")
    return string.format("%.2f", speed or 0)
end
-- §6: ranged AP is additionally N/A with a wand — wands have no meaningful
-- ranged attack power in this era.
local function rangedAPRow()
    if not hasRangedWeapon() or hasWandEquipped() then return NA end
    return rangedAP()
end
-- §6: ranged hit is GetHitModifier() plus +3 for the ranged-slot scope enchant.
local function rangedHit()
    local link = GetInventoryItemLink("player", 18)
    local hasScope = (link and SM.EnchantIdFromLink(link) == SM.SCOPE_ENCHANT_ID) or false
    return PCT(SM.RangedHit(GetHitModifier and GetHitModifier() or 0, hasScope))
end

-- Spell schools are 1-based: 1 Physical, 2 Holy, 3 Fire, 4 Nature, 5 Frost, 6 Shadow,
-- 7 Arcane (mirrors the game's SPELL_SCHOOL enum). GetSpellBonusDamage / GetSpellCritChance
-- take that index; the Spell block lists schools 2..7 (physical isn't a spell school).
local function bonusDmg(school) return function() return N(GetSpellBonusDamage(school)) end end

-- CSC §9.3: the client does not report talent-granted spell crit in Classic Era.
local function maxSpellCrit()
    local _, class = UnitClass("player")
    local base = {}
    for s = 2, 7 do base[s] = GetSpellCritChance(s) or 0 end

    local ranks = {}
    local entries = SM.SPELL_CRIT_TALENTS[class]
    if entries then
        for _, e in ipairs(entries) do ranks[e.talent] = Addon:TalentRank(e.tree, e.talent) end
    end

    local benediction = (class == "PRIEST")
        and GetInventoryItemID and (GetInventoryItemID("player", 16) == SM.BENEDICTION_ITEM_ID)
        or false

    return SM.MaxSpellCrit(SM.SpellCritBySchool(class, base, ranks, benediction))
end

-- ── Mana regen (CSC §9.5) ─────────────────────────────────────────────────────
-- GetManaRegen() is broken on Era: both returns carry the same figure. Rebuild the
-- two real numbers from base spirit regen + gear MP5 + aura MP5 + casting fraction.
local lastSeenBase = 0            -- zero-flash guard cache (§9.5 step 3)
local regenMemo, regenMemoSerial

local function playerAuraSpellIds()
    local ids = {}
    if not UnitAura then return ids end
    for i = 1, 40 do
        -- HELPFUL only (not HELPFUL|PLAYER): Blessing of Wisdom and Mana Spring
        -- Totem are cast BY OTHERS, and restricting to player-cast auras would
        -- drop the two biggest MP5 sources in the table.
        local name, _, _, _, _, _, _, _, _, spellId = UnitAura("player", i, "HELPFUL")
        if not name then break end
        if spellId then ids[#ids + 1] = spellId end
    end
    return ids
end

local function computeManaRegen()
    if regenMemo and regenMemoSerial == Addon._statsSerial then return regenMemo end
    if not (UnitHasMana and UnitHasMana("player")) then
        regenMemo, regenMemoSerial = false, Addon._statsSerial
        return false
    end

    local _, class = UnitClass("player")
    local base = SM.ZeroFlashGuard(GetManaRegen and GetManaRegen() or 0, lastSeenBase)
    if base and base >= 1 then lastSeenBase = base end

    local g = scanGear()
    -- ARM-1: a cold gear scan has no MP5 answer. Both rows read "—" until the item
    -- data lands, rather than quoting a sum that is missing whole pieces.
    if g.mp5 == nil then
        regenMemo, regenMemoSerial = false, Addon._statsSerial
        return false
    end
    local gearMP5 = g.mp5 + temporaryMainHandMP5()

    local impWisdom = (class == "PALADIN")
        and Addon:TalentRank("Holy", "Improved Blessing of Wisdom") or 0
    local auraMP5, auraCombatFrac = SM.AuraMP5(playerAuraSpellIds(), impWisdom)

    local medRanks = 0
    local medList = SM.MEDITATION_TALENTS[class]
    if medList then
        for _, t in ipairs(medList) do medRanks = medRanks + Addon:TalentRank(t.tree, t.talent) end
    end

    local modifier = SM.CastingModifier(class, medRanks, g.tierPieces, auraCombatFrac)
    local notCasting, casting = SM.ManaRegenRows(base, gearMP5, auraMP5, modifier)

    regenMemo = { notCasting = notCasting, casting = casting }
    regenMemoSerial = Addon._statsSerial
    return regenMemo
end

local function manaRegenNotCasting()
    local r = computeManaRegen()
    if not r then return NA end
    return N(r.notCasting)
end
local function manaRegenCasting()
    local r = computeManaRegen()
    if not r then return NA end
    return N(r.casting)
end

-- ── Defense (CSC §7.2): skill-line walk primary, UnitDefense fallback ─────────
local function defenseFromSkillLines()
    if not (GetNumSkillLines and GetSkillLineInfo) then return nil end
    local n = GetNumSkillLines() or 0
    if n == 0 then return nil end
    local wantHeader = _G.WEAPON_SKILLS
    local wantName   = _G.DEFENSE or "Defense"
    local header, anyRank, anyMod
    for i = 1, n do
        -- GetSkillLineInfo -> name, isHeader, isExpanded, rank, numTempPoints, modifier, …
        local name, isHeader, _, rank, _, modifier = GetSkillLineInfo(i)
        if isHeader then
            header = name
        elseif name == wantName then
            if (not wantHeader) or header == wantHeader then return rank, modifier end
            if not anyRank then anyRank, anyMod = rank, modifier end
        end
    end
    if anyRank then return anyRank, anyMod end
    return nil
end

local function defenseVal()
    local rank, mod = defenseFromSkillLines()
    if not rank then
        -- Fallback only. The skill line is unavailable when its header is collapsed.
        rank, mod = UnitDefense("player")
    end
    return N(SM.DefenseValue(rank, mod))
end

-- ── Block value (CSC §7.4) ────────────────────────────────────────────────────
-- Default source is the spec's own calculation: tooltip-scraped block value across
-- slots 1..18, plus Strength/20, plus the Battlegear of Might 3-piece +30, plus the
-- warrior Zul'Gurub head/legs enchant +15 each. GetShieldBlock() is the opt-in
-- alternative and carries none of those terms.
local function blockValue()
    local s = Addon.db and Addon.db.settings and Addon.db.settings.stats
    if s and s.blizzardBlockValue then
        return N(GetShieldBlock and GetShieldBlock() or 0)
    end
    local g = scanGear()
    local strength = select(2, UnitStat("player", 1))
    -- ARM-1: SM.BlockValue refuses a nil gear sum. Strength/20 alone is not a block
    -- value — it is the one term that survived a cold read, and rendering it was
    -- how a protection warrior's 57 showed as 11.
    local v = SM.BlockValue(g.blockValue, strength, g.battlegear, g.zgBlockEnchants)
    if v == nil then return NA end
    return N(v)
end
-- Resistance indices: 0 Armor, 1 Holy (never itemized), 2 Fire, 3 Nature, 4 Frost,
-- 5 Shadow, 6 Arcane. select(2) is the effective value shown on the sheet.
local function resist(i) return function() return N(select(2, UnitResistance("player", i))) end end

-- ── Stat block specification (the shared data layer) ──────────────────────────
-- { title, cells = { { label, computeFn }, ... } }. Labels are static; each
-- computeFn returns the live display string. Both renderers register every cell's
-- value fontstring against a refresh registry so a single loop updates all of them.
local SPECS = {
    { title = "Attributes", cells = {
        { "Strength",  function() return stat(1) end },
        { "Agility",   function() return stat(2) end },
        { "Stamina",   function() return stat(3) end },
        { "Intellect", function() return stat(4) end },
        { "Spirit",    function() return stat(5) end },
        { "Armor",     armor },
        { "Health",    function() return N(UnitHealthMax("player")) end },
        { "Mana",      function() return N(UnitPowerMax("player", 0)) end },
    }},
    { title = "Melee", cells = {
        { "Attack Power", meleeAP },
        { "Damage",       meleeDamage },
        { "Speed",        meleeSpeed },
        { "Hit",          function() return PCT(GetHitModifier and GetHitModifier() or 0) end },
        { "Crit",         function() return PCT(GetCritChance()) end },
    }},
    { title = "Ranged", cells = {
        { "Attack Power", rangedAPRow },
        { "Damage",       rangedRow(rangedDamage) },
        { "Speed",        rangedRow(rangedSpeed) },
        { "Crit",         rangedRow(function() return PCT(GetRangedCritChance()) end) },
        { "Hit",          rangedRow(rangedHit) },
    }},
    { title = "Spell", cells = {
        { "Holy",        bonusDmg(2) },
        { "Fire",        bonusDmg(3) },
        { "Nature",      bonusDmg(4) },
        { "Frost",       bonusDmg(5) },
        { "Shadow",      bonusDmg(6) },
        { "Arcane",      bonusDmg(7) },
        { "Healing",     function() return N(GetSpellBonusHealing()) end },
        { "Spell Hit",   function() return PCT(GetSpellHitModifier and GetSpellHitModifier() or 0) end },
        { "Spell Crit",  function() return PCT(maxSpellCrit()) end },
        { "MP5 Casting",     manaRegenCasting },
        { "MP5 Not Casting", manaRegenNotCasting },
        { "Spell Pen",   function() return N(GetSpellPenetration and GetSpellPenetration() or 0) end },
    }},
    { title = "Defense", cells = {
        { "Armor",       armor },
        { "Defense",     defenseVal },
        { "Dodge",       function() return PCT(GetDodgeChance()) end },
        { "Parry",       function() return PCT(GetParryChance()) end },
        { "Block",       function() return PCT(GetBlockChance()) end },
        { "Block Value", blockValue },
    }},
    { title = "Resistances", cells = {
        { "Fire",   resist(2) },
        { "Nature", resist(3) },
        { "Frost",  resist(4) },
        { "Shadow", resist(5) },
        { "Arcane", resist(6) },
    }},
}

function Addon:StatBlockSpecs() return SPECS end

-- ── Refresh registries ────────────────────────────────────────────────────────
local function refreshRegistry(reg)
    if not reg then return end
    for _, e in ipairs(reg) do
        local ok, s = pcall(e.fn)
        e.fs:SetText((ok and s) or "—")
    end
end

-- Bumped once per refresh tick so multi-row computations (mana regen feeds two
-- rows) are done once and memoised for the rest of the tick.
Addon._statsSerial = 0

function Addon:RefreshStatsTab()
    refreshRegistry(Addon._statCellsHub)
end
function Addon:RefreshStatsPanel()
    if Addon._statsPanel and Addon._statsPanel:IsShown() then
        refreshRegistry(Addon._statCellsPanel)
    end
end

-- Coalesce a burst of stat events into one refresh next frame-ish.
function Addon:MarkStatsDirty()
    if Addon._statsDirty then return end
    Addon._statsDirty = true
    C_Timer.After(0.1, function()
        Addon._statsDirty = false
        Addon._statsSerial = (Addon._statsSerial or 0) + 1
        Addon:RefreshStatsTab()
        Addon:RefreshStatsPanel()
    end)
end

-- ── Renderer: one stat block host (title + hairline + two-column cell grid) ────
-- Registers each value fontstring into `registry`. Returns a frame carrying an
-- arrange(width) -> height for both the flow pane and the standalone panel.
local TITLE_H = 24    -- serif title (18) + gap to the hairline/first row
local CELL_H  = 16
local CELL_PAD = 6

-- Daseeki-Core is an OptionalDep: every DaseekiUI dereference on the attach path
-- must be nil-guarded or the panel hard-errors at login with Core disabled.
function Addon:StatsUIReady()
    local UI = _G.DaseekiUI
    return (UI and UI.fonts and UI.Hairline and UI.FlatFrame) and UI or nil
end

function Addon:_MakeStatHost(parent, blk, registry)
    local UI = Addon:StatsUIReady()
    if not UI then return nil end
    local host = CreateFrame("Frame", nil, parent)

    -- True section title → ceremonial (MORPHEUS >=16), per BRAND_SPEC §3. These are
    -- Armory's own block titles (not Core's shared MakeSectionHeader), so they take the
    -- ceremonial face in both renderers (hub Stats section + attached panel).
    local title = host:CreateFontString(nil, "OVERLAY")
    title:SetFontObject(UI.fonts.ceremonial)
    title:SetJustifyH("LEFT")
    title:SetText(blk.title)

    -- ONE pixel-snapped hairline per block (BRAND_SPEC §9 hairline budget).
    local rule = UI.Hairline(host, { token = "borderLite" })

    host._cells = {}
    for _, c in ipairs(blk.cells) do
        local lbl = host:CreateFontString(nil, "OVERLAY")
        lbl:SetFontObject(UI.fonts.muted); lbl:SetJustifyH("LEFT"); lbl:SetText(c[1])
        -- Live stat readouts are telemetry columns → numeral face (ARIALN+OUTLINE).
        local val = host:CreateFontString(nil, "OVERLAY")
        val:SetFontObject(UI.fonts.numeral); val:SetJustifyH("RIGHT")
        host._cells[#host._cells + 1] = { lbl = lbl, val = val }
        registry[#registry + 1] = { fs = val, fn = c[2] }
    end

    host.arrange = function(width)
        width = math.max(width or 1, 1)
        host:SetWidth(width)
        title:ClearAllPoints(); title:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        rule:ClearAllPoints()
        rule:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -19)
        rule:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -19)

        local cols = (width < 240) and 1 or 2
        local colW = width / cols
        local labelW = colW * 0.58
        for i, cell in ipairs(host._cells) do
            local col  = (i - 1) % cols
            local rowN = math.floor((i - 1) / cols)
            local x = col * colW
            local y = TITLE_H + rowN * CELL_H
            cell.lbl:ClearAllPoints()
            cell.lbl:SetPoint("TOPLEFT", host, "TOPLEFT", x, -y)
            cell.lbl:SetWidth(labelW)
            cell.val:ClearAllPoints()
            cell.val:SetPoint("TOPLEFT", host, "TOPLEFT", x + labelW, -y)
            cell.val:SetWidth(math.max(1, colW - labelW - CELL_PAD))
        end
        local rows = math.ceil(#host._cells / cols)
        local h = TITLE_H + rows * CELL_H
        host:SetHeight(math.max(h, 1))
        return h
    end

    return host
end

-- ── Hub "Stats" section ───────────────────────────────────────────────────────
function Addon:BuildStatsSection(flow)
    Addon.frames = Addon.frames or {}
    Addon.frames.stats = flow
    Addon:BuildStatsTab(flow)
end

function Addon:BuildStatsTab(flow)
    Addon._statsFlow    = flow
    Addon._statCellsHub = {}

    flow:Hint("Live character statistics — values update as your gear, buffs, and skills change.")
    flow:Checkbox({
        label   = "Attach a compact stats panel to the character window",
        get     = function() return Addon.db.settings.stats.attach end,
        set     = function(v)
            Addon.db.settings.stats.attach = v and true or false
            Addon:UpdateStatsPanelShown()
        end,
        tooltip = "Shows the same stat blocks docked to the right of the character sheet.",
    })
    flow:Checkbox({
        label   = "Use the client's block value instead of Armory's calculation",
        get     = function() return Addon.db.settings.stats.blizzardBlockValue end,
        set     = function(v)
            Addon.db.settings.stats.blizzardBlockValue = v and true or false
            Addon:InvalidateStatGearCache()
            Addon:MarkStatsDirty()
        end,
        tooltip = "Off (default): block value is summed from your gear plus Strength/20, "
               .. "the Battlegear of Might 3-piece bonus and warrior Zul'Gurub enchants.\n"
               .. "On: GetShieldBlock() verbatim, with none of those terms.",
    })

    local UI = Addon:StatsUIReady()
    local gap = (UI and UI.Token and UI.Token("rowGap")) or 10
    for _, blk in ipairs(SPECS) do
        local host = Addon:_MakeStatHost(flow.pane.child, blk, Addon._statCellsHub)
        if host then flow.pane:AddBlock(host, host.arrange, gap, 0) end
    end

    Addon:RefreshStatsTab()
end

-- ── Optional attach-to-character-window panel ─────────────────────────────────
-- Returns nil (a clean no-op) when Daseeki-Core is absent.
function Addon:BuildStatsPanel()
    if Addon._statsPanel then return Addon._statsPanel end
    local UI = Addon:StatsUIReady()
    if not UI then return nil end
    local W, PAD, BLKGAP = 236, 12, 8

    local p = UI.FlatFrame(UIParent, "panel", "border")
    p:SetWidth(W)
    p:SetFrameStrata("MEDIUM")
    p:EnableMouse(true)   -- swallow clicks so they don't fall through to the world
    p:Hide()

    Addon._statCellsPanel = {}
    local y = PAD
    for _, blk in ipairs(SPECS) do
        local host = Addon:_MakeStatHost(p, blk, Addon._statCellsPanel)
        if host then
            host:ClearAllPoints()
            host:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -y)
            local h = host.arrange(W - PAD * 2)
            y = y + h + BLKGAP
        end
    end
    p:SetHeight(math.max(y - BLKGAP + PAD, 1))

    Addon._statsPanel = p
    return p
end

function Addon:UpdateStatsPanelShown()
    local want = Addon.db and Addon.db.settings and Addon.db.settings.stats
                 and Addon.db.settings.stats.attach
    if not want then
        if Addon._statsPanel then Addon._statsPanel:Hide() end
        return
    end
    local p = Addon:BuildStatsPanel()
    if not p then return end        -- no Daseeki-Core: attach is a clean no-op
    if _G.CharacterFrame and _G.CharacterFrame:IsShown() then
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", _G.CharacterFrame, "TOPRIGHT", 4, 0)
        p:Show()
        Addon:RefreshStatsPanel()
    else
        p:Hide()
    end
end

-- ── Init: live-update events + character-frame attach hooks ────────────────────
function Addon:InitStats()
    if Addon._statsInit then return end
    Addon._statsInit = true

    local ev = CreateFrame("Frame")
    local EVENTS = {
        "UNIT_STATS", "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER", "UNIT_ATTACK_SPEED",
        "UNIT_DAMAGE", "UNIT_RANGEDDAMAGE", "UNIT_ATTACK", "UNIT_RESISTANCES",
        "UNIT_MAXHEALTH", "PLAYER_DAMAGE_DONE_MODS", "COMBAT_RATING_UPDATE",
        "SPELL_POWER_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED",
        "SKILL_LINES_CHANGED", "UNIT_AURA", "PLAYER_ENTERING_WORLD",
        "CHARACTER_POINTS_CHANGED",
        -- ARM-1: the one event that announces "the data you could not read has
        -- arrived". Without it a cold login's gear scan stood until the player
        -- changed gear or took a loading screen. Both spellings are watched (the
        -- register call is pcall-guarded above, so a build lacking one is fine).
        "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT",
    }
    for _, e in ipairs(EVENTS) do
        -- guard: a patch level that lacks a given event should not abort the rest
        pcall(function() ev:RegisterEvent(e) end)
    end
    ev:SetScript("OnEvent", function(_, event, arg1)
        if event == "PLAYER_ENTERING_WORLD" then
            -- The talent remap must exist before any talent-derived number is read.
            Addon:BuildTalentRemap()
            Addon:InvalidateStatGearCache()
            Addon:RearmStatWarmBudget()
            Addon:MarkStatsDirty()
            return
        end
        if event == "CHARACTER_POINTS_CHANGED" then
            Addon._talentSlots = nil          -- re-resolve names against the live tree
            Addon:MarkStatsDirty()
            return
        end
        -- ARM-1: item info streaming in. arg1 is an ITEM ID here, not a unit, so it
        -- has to be handled before the "player"-only filter below. Gated on the
        -- unresolved counter (goalPicker.lua's _goalPvPMissing discipline): these
        -- arrive in bursts, and at 0 there is nothing cold left to repaint for.
        if event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
            if (Addon._statGearUnproven or 0) > 0 and (Addon._statWarmBudget or 0) > 0 then
                Addon._statWarmBudget = Addon._statWarmBudget - 1
                Addon:InvalidateStatGearCache()
                Addon:MarkStatsDirty()
            end
            return
        end
        -- Equipment changes invalidate the cached gear scan (MP5 / block value /
        -- tier tallies). PLAYER_EQUIPMENT_CHANGED's first arg is a SLOT NUMBER, so
        -- it must be handled before the "player"-only filter below.
        if event == "PLAYER_EQUIPMENT_CHANGED"
           or (event == "UNIT_INVENTORY_CHANGED" and arg1 == "player") then
            Addon:InvalidateStatGearCache()
            Addon:RearmStatWarmBudget()     -- new gear is a new warmth question
            Addon:MarkStatsDirty()
            return
        end
        -- unit-scoped events: only care about the player
        if arg1 ~= nil and arg1 ~= "player" then return end
        Addon:MarkStatsDirty()
    end)
    Addon._statsEv = ev

    -- PLAYER_ENTERING_WORLD may already have fired before InitStats runs.
    Addon:BuildTalentRemap()

    if _G.CharacterFrame then
        _G.CharacterFrame:HookScript("OnShow", function() Addon:UpdateStatsPanelShown() end)
        _G.CharacterFrame:HookScript("OnHide", function()
            if Addon._statsPanel then Addon._statsPanel:Hide() end
        end)
    end

    Addon:UpdateStatsPanelShown()
end
