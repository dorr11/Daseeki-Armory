--[[
    Daseeki Armory — gear-set equip engine.

    Clean-room rebuild: 2026-07-31.

    Behavioral reference:
      * ITEMRACK_BEHAVIOR_SPEC.md (repo root) — the clean-room behavioral
        specification for the swap engine: two-tier item identity matching,
        source reservation, the move guards and their abort codes, multi-pass
        lock-driven convergence, partial-set handling, and the combat /
        really-dead queue contract.
      * TRINKETMENU_BEHAVIOR_SPEC.md (repo root) — the per-slot queue drain
        rules: drain only on PLAYER_REGEN_ENABLED / PLAYER_UNGHOST /
        PLAYER_ALIVE, never against a corpse, ascending slot order.

    Design: census -> plan -> execute -> converge.

      1. BuildCensus takes ONE sweep of bags and worn slots per pass and indexes
         everything by exact identity key and by base item id, collecting free
         bag slots and a global "is anything locked" flag as it goes.
      2. PlanSet turns (set, census) into an ordered operation list, claiming
         each source location so two slots of one set can never resolve to the
         same item, and accumulating the missing-item report.
      3. ExecuteOp applies one operation behind the shared move guards.
      4. EquipPass re-censuses and re-plans on every pass, driven by
         ITEM_LOCK_CHANGED with a debounce, until the plan is empty or the pass
         budget is spent.

    Planning is separated from execution so the whole engine can be driven
    headlessly by harness/run-selftests.lua against a virtual inventory.
--]]

local _, Addon = ...

-- ── Tunables ──────────────────────────────────────────────────────────────────
local MAX_PASSES    = 3      -- pass budget per equip request
local PASS_DEBOUNCE = 0.2    -- seconds; ITEM_LOCK_CHANGED coalescing window
local BAG_IDS       = { 0, 1, 2, 3, 4 }

-- Abort codes (ITEMRACK_BEHAVIOR_SPEC.md §2.6).
local ABORT_NO_ROOM   = 1
local ABORT_CURSOR    = 2
local ABORT_TARGETING = 3
local ABORT_LOCKED    = 4

local ABORT_TEXT = {
    [ABORT_NO_ROOM]   = "not enough bag space to finish the swap.",
    [ABORT_CURSOR]    = "something is already on the cursor.",
    [ABORT_TARGETING] = "a spell is waiting to be targeted.",
    [ABORT_LOCKED]    = "another swap is already under way.",
}

local UNEQUIP_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"

-- Which INVTYPE_* values may go into each inventory slot (for inventory flyouts).
-- Slot model per ITEMRACK_BEHAVIOR_SPEC.md §0, minus the ammo slot, which this
-- addon does not manage (see Addon.SLOTS in core.lua).
--
-- Keyed BY equip location so consumers can test membership directly:
-- goalPicker.lua takes this table verbatim and does validLoc[item.equipLoc].
local function invTypes(...)
    local t = {}
    for i = 1, select("#", ...) do t[(select(i, ...))] = true end
    return t
end

Addon.SLOT_INVTYPES = {
    [1]  = invTypes("INVTYPE_HEAD"),
    [2]  = invTypes("INVTYPE_NECK"),
    [3]  = invTypes("INVTYPE_SHOULDER"),
    [4]  = invTypes("INVTYPE_BODY"),
    [5]  = invTypes("INVTYPE_CHEST", "INVTYPE_ROBE"),
    [6]  = invTypes("INVTYPE_WAIST"),
    [7]  = invTypes("INVTYPE_LEGS"),
    [8]  = invTypes("INVTYPE_FEET"),
    [9]  = invTypes("INVTYPE_WRIST"),
    [10] = invTypes("INVTYPE_HAND"),
    [11] = invTypes("INVTYPE_FINGER"),
    [12] = invTypes("INVTYPE_FINGER"),
    [13] = invTypes("INVTYPE_TRINKET"),
    [14] = invTypes("INVTYPE_TRINKET"),
    [15] = invTypes("INVTYPE_CLOAK"),
    [16] = invTypes("INVTYPE_WEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_2HWEAPON"),
    [17] = invTypes("INVTYPE_WEAPON", "INVTYPE_WEAPONOFFHAND", "INVTYPE_SHIELD", "INVTYPE_HOLDABLE"),
    [18] = invTypes("INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN", "INVTYPE_RELIC"),
    [19] = invTypes("INVTYPE_TABARD"),
}

-- Informational combat-queue chatter — only shown when Chat Messages is enabled.
function Addon:ChatMsg(text)
    if Addon.db and Addon.db.settings and Addon.db.settings.chatMessages then
        print(Addon:Tag() .. " " .. text)
    end
end

-- ── Classic C_Container shims ─────────────────────────────────────────────────
-- GetContainerItemInfo returns a table on current Classic builds; normalise it
-- to (link, isLocked).
local function bagItem(bag, slot)
    local C = C_Container
    if not (C and C.GetContainerItemInfo) then return nil, false end
    local info = C.GetContainerItemInfo(bag, slot)
    if type(info) == "table" then
        return info.hyperlink, info.isLocked and true or false
    end
    return nil, false
end

local function bagSize(bag)
    local C = C_Container
    if not (C and C.GetContainerNumSlots) then return 0 end
    return C.GetContainerNumSlots(bag) or 0
end

-- Quivers, soul bags and the like cannot receive displaced gear (spec §0).
local function isGenericBag(bag)
    if bag == 0 then return true end
    local C = C_Container
    if not (C and C.GetContainerNumFreeSlots) then return true end
    local _, family = C.GetContainerNumFreeSlots(bag)
    return (family or 0) == 0
end

local function pickupBag(bag, slot)
    if C_Container and C_Container.PickupContainerItem then
        C_Container.PickupContainerItem(bag, slot)
    end
end

local function pickupWorn(slotId)
    if PickupInventoryItem then PickupInventoryItem(slotId) end
end

local function wornLink(slotId)
    return GetInventoryItemLink and GetInventoryItemLink("player", slotId) or nil
end

local function equipLocOf(link)
    if not link or not GetItemInfoInstant then return nil end
    return (select(4, GetItemInfoInstant(link)))
end

local function iconOf(link)
    if not link or not GetItemInfoInstant then return nil end
    return (select(5, GetItemInfoInstant(link)))
end

local function baseIdOf(itemString)
    if not itemString then return nil end
    return tonumber(itemString:match("^(%d+)"))
end

local function slotIds()
    return Addon.SLOT_IDS or {}
end

-- Identity of whatever is worn in a slot: exact key, base id, link.
local function wornIdentity(slotId)
    local link = wornLink(slotId)
    if not link then return nil, nil, nil end
    local str = Addon:ItemString(link)
    if not str then return nil, nil, link end
    return Addon:ExactKey(str), baseIdOf(str), link
end

-- ── Matching ──────────────────────────────────────────────────────────────────
function Addon:IsSlotActive(set, slotId)
    if not (set and set.equip) then return false end
    return set.equip[slotId] ~= nil and not (set.disabled and set.disabled[slotId])
end

-- Exact identity: base id + enchant + suffix must all agree.
function Addon:SlotMatches(slotId, entry)
    if not entry then return true end
    local exact = wornIdentity(slotId)
    if not exact then return false end
    return entry.exact ~= nil and exact == entry.exact
end

-- Base-item-id match only (ignores enchant/suffix). Used so a slot wearing the
-- right item isn't falsely reported "missing" when a stale exact key (e.g. an
-- ItemRack import without enchant data) doesn't match the live enchanted item.
function Addon:SlotMatchesBase(slotId, entry)
    if not entry then return true end
    local _, base = wornIdentity(slotId)
    if not base then return false end
    return entry.id ~= nil and base == entry.id
end

-- ── Census ────────────────────────────────────────────────────────────────────
-- One sweep of bags + worn slots, indexed for direct resolution. Rebuilt at the
-- start of every pass so it can never go stale mid-swap.
--
-- A location is:
--   { where = "bag",  bag = <id>, slot = <index>, link = <link> }
--   { where = "worn", invSlot = <id>,             link = <link> }
function Addon:BuildCensus()
    local census = { byExact = {}, byBase = {}, free = {}, locked = false }

    local function record(loc, str)
        if not str then return end
        local exact = Addon:ExactKey(str)
        local base  = baseIdOf(str)
        if exact then
            census.byExact[exact] = census.byExact[exact] or {}
            table.insert(census.byExact[exact], loc)
        end
        if base then
            census.byBase[base] = census.byBase[base] or {}
            table.insert(census.byBase[base], loc)
        end
    end

    -- Bags. Search order is descending 4 -> 0 per spec §2.3; only generic
    -- containers can be offered as somewhere to put a displaced item.
    for i = #BAG_IDS, 1, -1 do
        local bag     = BAG_IDS[i]
        local generic = isGenericBag(bag)
        for slot = 1, bagSize(bag) do
            local link, locked = bagItem(bag, slot)
            if locked then census.locked = true end
            if link then
                record({ where = "bag", bag = bag, slot = slot, link = link },
                       Addon:ItemString(link))
            elseif generic then
                table.insert(census.free, { bag = bag, slot = slot })
            end
        end
    end

    for _, slotId in ipairs(slotIds()) do
        if IsInventoryItemLocked and IsInventoryItemLocked(slotId) then census.locked = true end
        local link = wornLink(slotId)
        if link then
            record({ where = "worn", invSlot = slotId, link = link },
                   Addon:ItemString(link))
        end
    end

    return census
end

-- Claim keys keep two slots of one set from resolving to the same source item.
local function claimKey(loc)
    if loc.where == "bag" then return "b" .. loc.bag .. ":" .. loc.slot end
    return "w" .. loc.invSlot
end

local function candidates(census, entry)
    if not entry then return nil, nil end
    return entry.exact and census.byExact[entry.exact] or nil,
           entry.id    and census.byBase[entry.id]     or nil
end

-- Two-tier resolve: exact identity first, base item id as fallback (spec §1.3).
local function resolve(census, entry, claims, exclude)
    local exactList, baseList = candidates(census, entry)
    local function pick(list)
        for _, loc in ipairs(list or {}) do
            local blocked = claims and claims[claimKey(loc)]
            if not blocked and exclude and loc.where == "worn" and loc.invSlot == exclude then
                blocked = true
            end
            if not blocked then return loc end
        end
        return nil
    end
    return pick(exactList) or pick(baseList)
end

-- ── Public find helpers ───────────────────────────────────────────────────────
-- Walk the exact-match list then the base-id list. These are held in two named
-- locals rather than a { exactList, baseList } array because the exact list is
-- nil exactly when the base-id fallback matters, and ipairs would stop at the
-- nil first element and never reach it.
local function eachCandidate(census, entry, fn)
    local exactList, baseList = candidates(census, entry)
    for _, loc in ipairs(exactList or {}) do
        local r1, r2 = fn(loc)
        if r1 ~= nil then return r1, r2 end
    end
    for _, loc in ipairs(baseList or {}) do
        local r1, r2 = fn(loc)
        if r1 ~= nil then return r1, r2 end
    end
    return nil
end

function Addon:FindInBags(entry)
    return eachCandidate(Addon:BuildCensus(), entry, function(loc)
        if loc.where == "bag" then return loc.bag, loc.slot end
        return nil
    end)
end

function Addon:FindInEquipped(entry, exclude)
    return eachCandidate(Addon:BuildCensus(), entry, function(loc)
        if loc.where == "worn" and loc.invSlot ~= exclude then return loc.invSlot end
        return nil
    end)
end

function Addon:FindFreeBagSlot()
    local f = Addon:BuildCensus().free[1]
    if f then return f.bag, f.slot end
    return nil
end

-- Is the set's item for this slot equippable right now (worn or in bags)?
function Addon:IsEntryAvailable(entry)
    if not entry then return false end
    return resolve(Addon:BuildCensus(), entry) ~= nil
end

-- ── Planner ───────────────────────────────────────────────────────────────────
-- Pure over (set, census): produces the operation list and the missing-item
-- report without touching the cursor.
--   op = { slot = <target>, from = <location>, twoHand = <bool> }
function Addon:PlanSet(set, census)
    local plan, missing, claims = {}, {}, {}

    for _, slotId in ipairs(slotIds()) do
        local entry = Addon:IsSlotActive(set, slotId) and set.equip[slotId] or nil
        if entry and not Addon:SlotMatches(slotId, entry) then
            -- Exclude the target slot as its own source: it only ever matches
            -- when the slot is already satisfied, which is handled above.
            local loc = resolve(census, entry, claims, slotId)
            if loc then
                claims[claimKey(loc)] = true
                table.insert(plan, {
                    slot    = slotId,
                    entry   = entry,
                    from    = loc,
                    twoHand = (slotId == 16) and (equipLocOf(loc.link) == "INVTYPE_2HWEAPON") or false,
                })
            elseif not Addon:SlotMatchesBase(slotId, entry) then
                -- Nowhere on the player, and the slot is not already wearing the
                -- right base item: genuinely missing (spec §4).
                local link = Addon:EntryLink(entry)
                local name = link and GetItemInfo and GetItemInfo(link) or nil
                table.insert(missing, name or ("item:" .. tostring(entry.id)))
            end
        end
    end

    return plan, missing
end

-- ── Executor ──────────────────────────────────────────────────────────────────
local function cursorLoaded()
    return (CursorHasItem and CursorHasItem()) and true or false
end

local function moveGuard()
    if cursorLoaded() then return ABORT_CURSOR end
    if SpellIsTargeting and SpellIsTargeting() then return ABORT_TARGETING end
    return nil
end

local function slotLocked(slotId)
    return (IsInventoryItemLocked and IsInventoryItemLocked(slotId)) and true or false
end

local function bagLocked(bag, slot)
    return (select(2, bagItem(bag, slot))) and true or false
end

-- Move whatever is worn in `invSlot` into a free bag slot, consuming one entry
-- from the census free list. Returns true, or false plus an abort code.
local function stow(invSlot, census)
    if not wornLink(invSlot) then return true end
    -- Guards first: only consume the free slot once the move will actually run,
    -- so an aborted stow doesn't shrink the pass's free-slot budget.
    local g = moveGuard()
    if g then return false, g end
    local free = census.free[1]
    if not free then return false, ABORT_NO_ROOM end
    if slotLocked(invSlot) or bagLocked(free.bag, free.slot) then return false, ABORT_LOCKED end
    table.remove(census.free, 1)
    pickupWorn(invSlot)
    pickupBag(free.bag, free.slot)
    return true
end

-- Does this location still hold the item the plan expects? An earlier move in
-- the same pass may have shifted it.
local function locHolds(link, entry)
    if not (link and entry) then return false end
    local str = Addon:ItemString(link)
    if not str then return false end
    if entry.exact and Addon:ExactKey(str) == entry.exact then return true end
    return entry.id ~= nil and baseIdOf(str) == entry.id
end

-- A planned operation is still worth running only if its target is not already
-- satisfied AND its source still holds the wanted item. A three-step exchange
-- can satisfy a later slot as a side effect, so this is re-checked per op rather
-- than trusted from plan time — otherwise the later op would undo the earlier one.
function Addon:OpStillNeeded(op)
    if Addon:SlotMatches(op.slot, op.entry) then return false end
    -- Explicit branch, not `a and b or c`: an emptied bag slot yields nil, which
    -- would fall through to the worn lookup with a nil slot id.
    local link
    if op.from.where == "bag" then
        link = (bagItem(op.from.bag, op.from.slot))
    else
        link = wornLink(op.from.invSlot)
    end
    return locHolds(link, op.entry)
end

-- Apply one planned operation. Returns true, or false plus an abort code.
function Addon:ExecuteOp(op, census)
    local g = moveGuard()
    if g then return false, g end

    if op.from.where == "bag" then
        if bagLocked(op.from.bag, op.from.slot) or slotLocked(op.slot) then
            return false, ABORT_LOCKED
        end
        -- A two-hander needs the off hand cleared first (spec §2.5).
        if op.twoHand and wornLink(17) then
            local ok, code = stow(17, census)
            if not ok then return false, code end
        end
        pickupBag(op.from.bag, op.from.slot)
        pickupWorn(op.slot)
        -- Equipping into an occupied slot hands the displaced item back on the
        -- cursor; drop it into the bag slot the new item vacated.
        if cursorLoaded() then pickupBag(op.from.bag, op.from.slot) end
        return true
    end

    -- Worn -> worn: the exchange leaves the displaced item on the cursor, which
    -- goes back into the source slot the item was taken from.
    if slotLocked(op.from.invSlot) or slotLocked(op.slot) then return false, ABORT_LOCKED end
    pickupWorn(op.from.invSlot)
    pickupWorn(op.slot)
    if cursorLoaded() then pickupWorn(op.from.invSlot) end
    return true
end

-- Public single-slot equip.
function Addon:EquipSlot(slotId, entry)
    if not entry or Addon:SlotMatches(slotId, entry) then return true end
    local census = Addon:BuildCensus()
    local loc = resolve(census, entry, nil, slotId)
    if not loc then return false end
    return (Addon:ExecuteOp({
        slot    = slotId,
        from    = loc,
        twoHand = (slotId == 16) and (equipLocOf(loc.link) == "INVTYPE_2HWEAPON") or false,
    }, census))
end

-- ── Multi-pass orchestration ──────────────────────────────────────────────────
-- Pass 1 runs synchronously; later passes are driven by ITEM_LOCK_CHANGED with a
-- debounce, and only once nothing anywhere is still locked (spec §2.7).
function Addon:EquipPass(name, attempt)
    local set = Addon:GetSet(name)
    if not set then Addon._equipping = nil; return end

    attempt = attempt or 1
    local census = Addon:BuildCensus()
    local plan, missing = Addon:PlanSet(set, census)

    if attempt == 1 and #missing > 0 then
        Addon:ChatMsg("could not find: [" .. table.concat(missing, "] [") .. "]")
    end

    if #plan == 0 then
        Addon:FinishEquip(name)
        return
    end

    local abort
    for _, op in ipairs(plan) do
        if Addon:OpStillNeeded(op) then
            local ok, code = Addon:ExecuteOp(op, census)
            if not ok and code then abort = code; break end
        end
    end

    if abort then
        Addon:ChatMsg(ABORT_TEXT[abort] or "the swap was interrupted.")
        Addon:FinishEquip(name)
        return
    end

    if attempt >= MAX_PASSES then
        Addon:FinishEquip(name)
        return
    end

    Addon._equipping = name
    Addon:WatchLocks(name, attempt + 1)
end

-- Re-drives the next pass once the inventory settles after a swap.
function Addon:WatchLocks(name, nextAttempt)
    if not Addon._lockWatcher then
        if not CreateFrame then return end
        Addon._lockWatcher = CreateFrame("Frame")
        Addon._lockWatcher:SetScript("OnEvent", function()
            local w = Addon._lockWatcher
            if not (w and w._name) then return end
            w._token = (w._token or 0) + 1
            local token = w._token
            local function fire()
                local ww = Addon._lockWatcher
                if not (ww and ww._name and ww._token == token) then return end
                if Addon._equipping ~= ww._name then return end
                if Addon:BuildCensus().locked then return end  -- still settling
                local n, a = ww._name, ww._attempt
                Addon:StopLockWatcher()
                Addon:EquipPass(n, a)
            end
            if C_Timer and C_Timer.After then C_Timer.After(PASS_DEBOUNCE, fire) else fire() end
        end)
    end
    Addon._lockWatcher._name    = name
    Addon._lockWatcher._attempt = nextAttempt
    pcall(function() Addon._lockWatcher:RegisterEvent("ITEM_LOCK_CHANGED") end)
end

function Addon:StopLockWatcher()
    local w = Addon._lockWatcher
    if not w then return end
    w._name, w._attempt = nil, nil
    pcall(function() w:UnregisterEvent("ITEM_LOCK_CHANGED") end)
end

function Addon:FinishEquip(name)
    Addon._equipping = nil
    Addon:StopLockWatcher()

    if Addon:GetSet(name) then
        Addon.db.currentSet = name
    end
    if Addon.ClearPendingSlots  then Addon:ClearPendingSlots()  end
    if Addon.UpdateSlotBorders  then Addon:UpdateSlotBorders()  end
    if Addon.RefreshWidget      then Addon:RefreshWidget()      end
    if Addon.RefreshSetList     then Addon:RefreshSetList()     end
end

function Addon:RunEquip(name)
    if not Addon:GetSet(name) then return end
    Addon._equipping = name
    Addon:EquipPass(name, 1)
end

-- ── Combat queue (whole sets + individual sidebar equips) ─────────────────────
-- Keyed by the TARGET equipment slot so only one pending action exists per slot,
-- and re-selecting the same item toggles it back off.

-- "Really dead" per both queue specs: dead or ghost, EXCEPT a feigning hunter,
-- who is treated as alive and swaps normally.
function Addon:IsReallyDead()
    if not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then return false end
    if UnitIsFeignDeath and UnitIsFeignDeath("player") then return false end
    return true
end

-- A swap must be queued rather than attempted while in combat OR while dead.
-- Attempting one as a corpse silently fails and the request is lost.
function Addon:MustQueueSwap()
    if UnitAffectingCombat and UnitAffectingCombat("player") then return true end
    return Addon:IsReallyDead()
end

-- Chat wording so a queued-while-dead swap doesn't claim to be waiting on combat.
function Addon:QueueReason()
    if UnitAffectingCombat and UnitAffectingCombat("player") then return "in combat" end
    return "while dead"
end

function Addon:QueueWhen()
    if UnitAffectingCombat and UnitAffectingCombat("player") then return "when combat ends" end
    return "on resurrection"
end

-- Dying drops combat, so PLAYER_REGEN_ENABLED fires while the player is a corpse.
-- Draining there would consume the queue against a corpse and lose it. The queue is
-- therefore HELD while really dead and drains on resurrection instead.
local DRAIN_EVENTS = { "PLAYER_REGEN_ENABLED", "PLAYER_UNGHOST", "PLAYER_ALIVE" }

function Addon:StopQueueWatcher()
    if not Addon._regen then return end
    for _, e in ipairs(DRAIN_EVENTS) do
        pcall(function() Addon._regen:UnregisterEvent(e) end)
    end
end

function Addon:EnsureRegenWatcher()
    if not Addon._regen then
        if not CreateFrame then return end
        Addon._regen = CreateFrame("Frame")
        Addon._regen:SetScript("OnEvent", function() Addon:DrainCombatQueue() end)
    end
    for _, e in ipairs(DRAIN_EVENTS) do
        pcall(function() Addon._regen:RegisterEvent(e) end)
    end
end

function Addon:DrainCombatQueue()
    -- Never consume the queue against a corpse — hold it for the resurrect.
    -- Also hold if still in combat: resurrecting mid-fight fires PLAYER_UNGHOST
    -- while swaps are still refused, and a whole-set equip consumed there would
    -- be lost silently.
    if Addon:MustQueueSwap() then return end

    local q    = Addon._combatQueue
    local pend = Addon._pendingSet
    if not q and not pend then Addon:StopQueueWatcher(); return end

    Addon._combatQueue = nil
    Addon._pendingSet  = nil
    Addon:StopQueueWatcher()

    -- Deterministic order: ascending target slot, so trinket 13 drains before 14.
    if q then
        local slots = {}
        for slot in pairs(q) do slots[#slots + 1] = slot end
        table.sort(slots)
        for _, slot in ipairs(slots) do
            local a = q[slot]
            if a.kind == "bag" then
                Addon:EquipContainerItemToSlot(a.bag, a.slot, slot)
            elseif a.kind == "worn" then
                Addon:SwapEquippedSlots(a.from, slot)
            elseif a.kind == "unequip" then
                Addon:UnequipSlot(slot)
            end
        end
    end

    if pend then Addon:RunEquip(pend) end
    if Addon.ClearPendingSlots then Addon:ClearPendingSlots() end
end

local function sameAction(a, b)
    if not a or not b or a.kind ~= b.kind then return false end
    if a.kind == "bag"  then return a.bag == b.bag and a.slot == b.slot end
    if a.kind == "worn" then return a.from == b.from end
    return true
end

-- Queue (or, if the identical action is already queued for that slot, un-queue) a
-- per-slot combat action. Returns true if now queued, false if it was toggled off.
function Addon:QueueCombatAction(slot, action)
    Addon._combatQueue = Addon._combatQueue or {}
    if sameAction(Addon._combatQueue[slot], action) then
        Addon._combatQueue[slot] = nil
        if Addon.SetPendingSlot then Addon:SetPendingSlot(slot, nil) end  -- clear overlay
        Addon:ChatMsg("cancelled the queued swap for that slot.")
        return false
    end
    Addon._combatQueue[slot] = action
    Addon:EnsureRegenWatcher()
    Addon:ChatMsg("queued " .. Addon:QueueReason() .. " — it will swap " .. Addon:QueueWhen() .. ".")
    return true
end

function Addon:DeferToCombatEnd(name)
    Addon._pendingSet = name
    Addon:EnsureRegenWatcher()
    if Addon.MarkSetPending then Addon:MarkSetPending(name) end
    Addon:ChatMsg("\"" .. tostring(name) .. "\" queued " .. Addon:QueueReason()
        .. " — it will equip " .. Addon:QueueWhen() .. ".")
end

-- ── Equip a specific inventory item into a slot (used by flyout / sidebar) ─────
function Addon:EquipContainerItemToSlot(bag, slot, invSlot)
    if Addon:MustQueueSwap() then
        local queued = Addon:QueueCombatAction(invSlot, { kind = "bag", bag = bag, slot = slot })
        if queued and Addon.SetPendingSlot then
            Addon:SetPendingSlot(invSlot, iconOf((bagItem(bag, slot))))
        end
        return queued
    end

    local g = moveGuard()
    if g then Addon:ChatMsg(ABORT_TEXT[g]); return false end
    if bagLocked(bag, slot) or slotLocked(invSlot) then
        Addon:ChatMsg(ABORT_TEXT[ABORT_LOCKED]); return false
    end

    local census = Addon:BuildCensus()
    if invSlot == 16 and equipLocOf((bagItem(bag, slot))) == "INVTYPE_2HWEAPON" and wornLink(17) then
        local ok, code = stow(17, census)
        if not ok then Addon:ChatMsg(ABORT_TEXT[code]); return false end
    end

    pickupBag(bag, slot)
    pickupWorn(invSlot)
    if cursorLoaded() then pickupBag(bag, slot) end
    return true
end

-- Take off the item currently in an equipment slot (into a free bag slot).
function Addon:UnequipSlot(invSlot)
    if Addon:MustQueueSwap() then
        local queued = Addon:QueueCombatAction(invSlot, { kind = "unequip" })
        if queued and Addon.SetPendingSlot then Addon:SetPendingSlot(invSlot, UNEQUIP_ICON) end
        return queued
    end

    local census = Addon:BuildCensus()
    local ok, code = stow(invSlot, census)
    if not ok then Addon:ChatMsg(ABORT_TEXT[code]); return false end
    return true
end

-- Move an already-equipped item from one slot to another (e.g. swap rings).
function Addon:SwapEquippedSlots(fromSlot, toSlot)
    if Addon:MustQueueSwap() then
        local queued = Addon:QueueCombatAction(toSlot, { kind = "worn", from = fromSlot })
        if queued and Addon.SetPendingSlot then
            local tex = GetInventoryItemTexture and GetInventoryItemTexture("player", fromSlot)
            Addon:SetPendingSlot(toSlot, tex)
        end
        return queued
    end

    local g = moveGuard()
    if g then Addon:ChatMsg(ABORT_TEXT[g]); return false end
    if slotLocked(fromSlot) or slotLocked(toSlot) then
        Addon:ChatMsg(ABORT_TEXT[ABORT_LOCKED]); return false
    end

    pickupWorn(fromSlot)
    pickupWorn(toSlot)
    if cursorLoaded() then pickupWorn(fromSlot) end
    return true
end

-- Items in bags that can go into a given inventory slot. When includeEquipped is
-- true (the set builder), currently-worn gear is listed first too; the character
-- pane and slot popouts pass false so already-equipped items aren't offered.
function Addon:GetInventoryItemsForSlot(slotId, includeEquipped)
    local valid = Addon.SLOT_INVTYPES[slotId] or {}
    local out = {}

    if includeEquipped then
        for _, s in ipairs(slotIds()) do
            local link = wornLink(s)
            if link and valid[equipLocOf(link)] then
                out[#out + 1] = { link = link, equipped = true, invSlot = s }
            end
        end
    end

    -- Menus read backpack-first, unlike the swap engine's descending search order.
    for _, bag in ipairs(BAG_IDS) do
        for slot = 1, bagSize(bag) do
            local link = bagItem(bag, slot)
            if link and valid[equipLocOf(link)] then
                out[#out + 1] = { link = link, equipped = false, bag = bag, slot = slot }
            end
        end
    end

    return out
end

-- ── Public API ────────────────────────────────────────────────────────────────
function Addon:EquipSet(name)
    if not Addon:GetSet(name) then return false end

    if Addon:MustQueueSwap() then
        Addon:DeferToCombatEnd(name)
        return false
    end

    Addon:RunEquip(name)
    return true
end

function Addon:IsSetEquipped(name)
    local set = Addon:GetSet(name)
    if not set then return false end
    local any = false
    for _, slotId in ipairs(slotIds()) do
        if Addon:IsSlotActive(set, slotId) then
            any = true
            if not Addon:SlotMatches(slotId, set.equip[slotId]) then return false end
        end
    end
    return any
end

-- Without snapshotting prior gear we don't restore on toggle; this re-equips.
function Addon:ToggleSet(name)
    return Addon:EquipSet(name)
end

function Addon:GetEquipMacro(name)
    return '/run ArmEquip("' .. tostring(name) .. '")'
end

-- ── Globals for macros — unique to Armory (no clash with ItemRack's EquipSet) ──
function ArmEquip(name)  return DaseekiArmory:EquipSet(name)  end
function ArmToggle(name) return DaseekiArmory:ToggleSet(name) end
ArmoryEquipSet  = ArmEquip
ArmoryToggleSet = ArmToggle
