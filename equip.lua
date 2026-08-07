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

    Design: census -> plan -> issue one settle-disjoint wave -> re-derive.

      1. BuildCensus takes ONE sweep of bags and worn slots per step and indexes
         everything by exact identity key and by base item id, collecting free
         bag slots as it goes.
      2. PlanSet turns (set, census) into an ordered operation list, claiming
         each source location so two slots of one set can never resolve to the
         same item, and accumulating the missing-item report.
      3. ExecuteOp applies one operation behind the shared move guards and
         returns the PREDICTION it just made: the content every slot it touched
         is going to show once the server answers.
      4. EquipPass issues only the ops whose involved slots are disjoint from
         everything already in flight, then WAITS. A step retires when those
         slots SHOW their predicted content — never when they merely unlock —
         and the plan is then re-derived from the settled world.

    See the SETTLE DISCIPLINE banner over the executor for why, and for the
    ceilings that make the wait terminate no matter what the client does.

    Planning is separated from execution so the whole engine can be driven
    headlessly by harness/run-selftests.lua against a virtual inventory.

    Two behaviors that ride on top of that core:

      * EXPLICIT-EMPTY SLOTS (ITEMRACK spec §1.2 / §2.5A). A set entry of
        { id = 0 } means "this slot must be EMPTY". The planner emits an unequip
        operation for it; execution needs one free bag slot and aborts the whole
        pass with the not-enough-room message when there is none.

      * IN-COMBAT WEAPON SWAPS (ITEMRACK spec §2.8 / §6.1). Nothing in this file
        can change gear during combat: every move here is a cursor pickup, which
        the client refuses in combat. The spec's mechanism is a SECURE one — a
        macro attribute written OUT of combat onto a SecureActionButton, carrying
        one `/equipslot [combat]<slot> <item name>` line per governed weapon slot
        (16/17/18 only). Pressing the set's key binding in combat therefore swaps
        main hand / off hand / ranged immediately through the client's own secure
        command, while every other slot queues for the end of combat. This file
        owns the macro TEXT (BuildSetMacroText) and the queue split; keybind.lua
        owns the button and the binding.
--]]

local _, Addon = ...

-- ── Tunables ──────────────────────────────────────────────────────────────────
local BAG_IDS       = { 0, 1, 2, 3, 4 }

-- ── THE SETTLE DISCIPLINE (CLIENT_ASYNC_LESSONS.md Class 1) ──────────────────
-- MAX_STEPS       runaway ceiling on re-plan steps in one equip run. A healthy
--                 whole-set swap takes 1-3; the stall guard stops a wedged one
--                 long before this.
-- MAX_IN_FLIGHT   concurrent un-acked operations. Every op takes its involved
--                 slots out of the planner's reach, so this is also how many
--                 slots the next re-plan cannot use. Six covers a full weapon
--                 set in one wave without freezing a third of the character.
-- SETTLE_POLL     backstop cadence while waiting. The bag/lock events drive the
--                 check; this exists so the wait can never be event-only.
-- SETTLE_TTL      per-op ceiling. A prediction whose content never arrives (the
--                 move was genuinely refused, or the server dropped it) is let
--                 go here and the op is re-planned from OBSERVED state. This is
--                 the ONLY path that may re-issue a move we already sent.
-- RUN_CEILING     the latch is released this long after the run last made
--                 PROGRESS (ARM-4). Re-based on every improvement, because a
--                 slow server is a nuisance and a half-equipped set is a defect;
--                 what must never happen is waiting on a residual that is not
--                 shrinking, and the stall guard below covers that.
-- MAX_NO_PROGRESS steps in a row whose residual plan did not shrink while
--                 nothing of ours was in flight — i.e. a foreign lock is
--                 sitting on a slot we need. Progress-based, not clock-based.
local MAX_STEPS       = 64
local MAX_IN_FLIGHT   = 6
local SETTLE_POLL     = 0.10
local SETTLE_TTL      = 1.50
local RUN_CEILING     = 12.0
local MAX_NO_PROGRESS = 20
local MAX_DRAIN_ROUNDS = 24

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
Addon.UNEQUIP_ICON = UNEQUIP_ICON

-- The only slots a secure `/equipslot [combat]` line may change during combat
-- (ITEMRACK_BEHAVIOR_SPEC.md §2.8 "the one exception that does swap in combat").
-- Ordered, because the macro lines are emitted in this order.
Addon.SECURE_COMBAT_SLOTS = { 16, 17, 18 }
local IS_SECURE_COMBAT_SLOT = { [16] = true, [17] = true, [18] = true }
function Addon:IsSecureCombatSlot(slotId) return IS_SECURE_COMBAT_SLOT[slotId] == true end

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

-- Exact identity: base id + enchant + suffix must all agree. An explicit-empty
-- entry is satisfied only by a genuinely bare slot (spec §1.2).
function Addon:SlotMatches(slotId, entry)
    if not entry then return true end
    if Addon:IsEmptyEntry(entry) then return wornLink(slotId) == nil end
    local exact = wornIdentity(slotId)
    if not exact then return false end
    return entry.exact ~= nil and exact == entry.exact
end

-- Base-item-id match only (ignores enchant/suffix). Used so a slot wearing the
-- right item isn't falsely reported "missing" when a stale exact key (e.g. an
-- ItemRack import without enchant data) doesn't match the live enchanted item.
function Addon:SlotMatchesBase(slotId, entry)
    if not entry then return true end
    if Addon:IsEmptyEntry(entry) then return wornLink(slotId) == nil end
    local _, base = wornIdentity(slotId)
    if not base then return false end
    return entry.id ~= nil and base == entry.id
end

-- ── Census ────────────────────────────────────────────────────────────────────
-- One sweep of bags + worn slots, indexed for direct resolution. Rebuilt at the
-- start of every step so it can never go stale mid-swap.
--
-- A location is:
--   { where = "bag",  bag = <id>, slot = <index>, link = <link> }
--   { where = "worn", invSlot = <id>,             link = <link> }
--
-- DELIBERATELY ABSENT: a global "is anything locked" flag. It used to be here,
-- and retiring the pass wait on it was ARM-2 — the client clears a lock BEFORE
-- it rewrites the slot, so `locked == false` means "the answer is on its way",
-- not "the answer has arrived". Settlement is per-slot and per-operation
-- (Addon:OpSettled); nothing may ask this census whether the world is ready.
function Addon:BuildCensus()
    local census = { byExact = {}, byBase = {}, free = {} }

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
            if link then
                record({ where = "bag", bag = bag, slot = slot, link = link },
                       Addon:ItemString(link))
            elseif generic and not locked then
                -- A bare-but-LOCKED slot is the source half of a move still in
                -- the air; offering it as free space would race that move.
                table.insert(census.free, { bag = bag, slot = slot })
            end
        end
    end

    for _, slotId in ipairs(slotIds()) do
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

-- Is the set's item for this slot equippable right now (worn or in bags)? An
-- explicit-empty entry needs no item — only somewhere to put what comes off.
function Addon:IsEntryAvailable(entry)
    if not entry then return false end
    local census = Addon:BuildCensus()
    if Addon:IsEmptyEntry(entry) then return census.free[1] ~= nil end
    return resolve(census, entry) ~= nil
end

-- ── Planner ───────────────────────────────────────────────────────────────────
-- Pure over (set, census): produces the operation list and the missing-item
-- report without touching the cursor.
--   op = { slot = <target>, from = <location>, twoHand = <bool> }
--   op = { slot = <target>, unequip = true }            -- explicit-empty slot
function Addon:PlanSet(set, census)
    local plan, missing, claims = {}, {}, {}

    for _, slotId in ipairs(slotIds()) do
        local entry = Addon:IsSlotActive(set, slotId) and set.equip[slotId] or nil
        if entry and Addon:SlotMatches(slotId, entry) then
            entry = nil                     -- already satisfied, nothing to plan
        end
        if entry and Addon:IsEmptyEntry(entry) then
            -- Explicit-empty (spec §1.2): nothing to find, nothing to claim, and
            -- never reported missing — the slot simply has to come off.
            table.insert(plan, { slot = slotId, entry = entry, unequip = true })
        elseif entry then
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

-- Every path that can leave one of OUR items dangling ends here. ClearCursor()
-- returns the held item to where it came from — nothing is ever destroyed by
-- calling it — so a refused op can no longer strand gear on the cursor with no
-- way back (ARM-2a: there was no ClearCursor anywhere in this file).
local function clearCursorBackstop()
    if cursorLoaded() and ClearCursor then ClearCursor() end
end
Addon.ClearCursorBackstop = function() clearCursorBackstop() end

-- ── Slot keys ─────────────────────────────────────────────────────────────────
-- "b<bag>:<slot>" / "w<invSlot>" — the same spelling claimKey() uses, so a
-- planner claim and an executor prediction name a location identically.
local function wkey(slotId)     return "w" .. slotId end
local function bkeyOf(bag, slot) return "b" .. bag .. ":" .. slot end

local function parseSlotKey(key)
    local bag, slot = tostring(key):match("^b(%d+):(%d+)$")
    if bag then return "bag", tonumber(bag), tonumber(slot) end
    local inv = tostring(key):match("^w(%d+)$")
    if inv then return "worn", tonumber(inv) end
    return nil
end

-- Published so the harness can pin AND mutate the settle rule without a client.
function Addon:SlotKeyLocked(key)
    local kind, a, b = parseSlotKey(key)
    if kind == "bag"  then return bagLocked(a, b) end
    if kind == "worn" then return slotLocked(a) end
    return false
end

function Addon:SlotKeyLink(key)
    local kind, a, b = parseSlotKey(key)
    if kind == "bag"  then return (bagItem(a, b)) end
    if kind == "worn" then return wornLink(a) end
    return nil
end

-- Two links are "the same item" for settle purposes when their exact identity
-- agrees. Raw string equality first, because in the common case it is.
local function sameItem(a, b)
    if a == nil or b == nil then return a == b end
    if a == b then return true end
    local sa, sb = Addon:ItemString(a), Addon:ItemString(b)
    if not (sa and sb) then return false end
    return Addon:ExactKey(sa) == Addon:ExactKey(sb)
end

-- ── THE SETTLE RULE ───────────────────────────────────────────────────────────
-- Factored out as ONE named decision (the shape Daseeki-Bags/sort.lua's
-- Sort.PredSettled ships) so the harness can pin it and mutate it. The defect
-- this replaces is exactly the mutant "every involved slot is unlocked":
-- the client releases a slot's lock BEFORE it rewrites the slot's contents, so
-- retiring there reads the pre-operation world, re-plans the move that already
-- landed, and re-issues it — ERR_INTERNAL_BAG_ERROR (ARM-2, Bags 2.0.2).
--
-- An operation is settled when the slots it touched SHOW WHAT IT PROMISED.
-- Never inferred from an event about some other slot: only slot X's own
-- contents can answer for X.
function Addon:OpSettled(pred)
    if not (pred and pred.expect) then return true end
    for _, e in ipairs(pred.expect) do
        if Addon:SlotKeyLocked(e.key) then return false end
        if not sameItem(Addon:SlotKeyLink(e.key), e.link) then return false end
    end
    return true
end

-- Move whatever is worn in `invSlot` into a free bag slot, consuming one entry
-- from the census free list.
-- Returns ok, abortCode, freeKey, movedLink.
local function stow(invSlot, census)
    local held = wornLink(invSlot)
    if not held then return true end
    -- Guards first: only consume the free slot once the move will actually run,
    -- so an aborted stow doesn't shrink the step's free-slot budget.
    local g = moveGuard()
    if g then return false, g end
    local free = census.free[1]
    if not free then return false, ABORT_NO_ROOM end
    if slotLocked(invSlot) or bagLocked(free.bag, free.slot) then return false, ABORT_LOCKED end
    table.remove(census.free, 1)
    pickupWorn(invSlot)
    pickupBag(free.bag, free.slot)
    return true, nil, bkeyOf(free.bag, free.slot), held
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
    -- An unequip has no source to re-validate: SlotMatches above already said the
    -- slot is still occupied, which is the whole condition.
    if op.unequip then return true end
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

-- Every slot an operation will WRITE, computed from the observed world just
-- before it is issued. This doubles as the disjointness test: two ops may go
-- out together only if these sets do not intersect, so an op is never issued
-- against a slot one of our own in-flight ops is about to rewrite.
--
-- The free-slot entries name census.free[1] because that is what stow() takes;
-- executing the wave op-by-op keeps the two in step. A missing free slot is NOT
-- reported here — ExecuteOp raises ABORT_NO_ROOM so the user gets the message.
function Addon:OpSlotKeys(op, census)
    if not op then return nil end
    local keys = {}
    local function add(k) if k then keys[#keys + 1] = k end end

    if op.unequip then
        add(wkey(op.slot))
        local f = census and census.free[1]
        if f then add(bkeyOf(f.bag, f.slot)) end
        return keys
    end

    if not op.from then return nil end
    add(wkey(op.slot))
    if op.from.where == "bag" then
        add(bkeyOf(op.from.bag, op.from.slot))
        if op.twoHand and wornLink(17) then
            add(wkey(17))
            local f = census and census.free[1]
            if f then add(bkeyOf(f.bag, f.slot)) end
        end
    else
        add(wkey(op.from.invSlot))
    end
    return keys
end

-- Apply one planned operation.
-- Returns true plus the PREDICTION (what each touched slot will show once the
-- server answers), or false plus an abort code. The prediction is what the step
-- waits on; nothing here re-reads the world it just wrote.
function Addon:ExecuteOp(op, census)
    local g = moveGuard()
    if g then return false, g end

    -- Explicit-empty: move the worn item into a free bag slot. stow() raises
    -- ABORT_NO_ROOM when there is nowhere to put it (spec §2.5A).
    if op.unequip then
        local ok, code, freeKey, moved = stow(op.slot, census)
        if not ok then return false, code end
        if not moved then return true, nil, nil end     -- already bare: nothing in flight
        return true, nil, { expect = {
            { key = wkey(op.slot), link = nil },
            { key = freeKey,       link = moved },
        } }
    end

    if op.from.where == "bag" then
        if bagLocked(op.from.bag, op.from.slot) or slotLocked(op.slot) then
            return false, ABORT_LOCKED
        end
        local srcKey  = bkeyOf(op.from.bag, op.from.slot)
        local srcLink = (bagItem(op.from.bag, op.from.slot))
        local expect  = {}
        -- A two-hander needs the off hand cleared first (spec §2.5).
        if op.twoHand and wornLink(17) then
            local ok, code, freeKey, moved = stow(17, census)
            if not ok then return false, code end
            expect[#expect + 1] = { key = wkey(17), link = nil }
            expect[#expect + 1] = { key = freeKey,  link = moved }
        end
        local displaced = wornLink(op.slot)
        pickupBag(op.from.bag, op.from.slot)
        pickupWorn(op.slot)
        -- Equipping into an occupied slot hands the displaced item back on the
        -- cursor; drop it into the bag slot the new item vacated.
        if cursorLoaded() then pickupBag(op.from.bag, op.from.slot) end
        clearCursorBackstop()
        expect[#expect + 1] = { key = wkey(op.slot), link = srcLink }
        expect[#expect + 1] = { key = srcKey,        link = displaced }
        return true, nil, { expect = expect }
    end

    -- Worn -> worn: the exchange leaves the displaced item on the cursor, which
    -- goes back into the source slot the item was taken from.
    if slotLocked(op.from.invSlot) or slotLocked(op.slot) then return false, ABORT_LOCKED end
    local srcLink   = wornLink(op.from.invSlot)
    local displaced = wornLink(op.slot)
    pickupWorn(op.from.invSlot)
    pickupWorn(op.slot)
    if cursorLoaded() then pickupWorn(op.from.invSlot) end
    clearCursorBackstop()
    return true, nil, { expect = {
        { key = wkey(op.slot),         link = srcLink },
        { key = wkey(op.from.invSlot), link = displaced },
    } }
end

-- Public single-slot equip.
function Addon:EquipSlot(slotId, entry)
    if not entry or Addon:SlotMatches(slotId, entry) then return true end
    if Addon:IsEmptyEntry(entry) then return Addon:UnequipSlot(slotId) end
    local census = Addon:BuildCensus()
    local loc = resolve(census, entry, nil, slotId)
    if not loc then return false end
    local ok, code = Addon:ExecuteOp({
        slot    = slotId,
        from    = loc,
        twoHand = (slotId == 16) and (equipLocOf(loc.link) == "INVTYPE_2HWEAPON") or false,
    }, census)
    if not ok then
        if code ~= ABORT_CURSOR then clearCursorBackstop() end
        return false
    end
    return true
end

-- ── Settle-aware run orchestration ────────────────────────────────────────────
-- ONE STEP = census -> plan -> issue the slot-disjoint wave -> wait for those
-- slots to SHOW their result -> re-derive the plan from the settled world.
--
-- The plan is never materialised and replayed: it is re-derived per step from
-- the current world (the Gargul idempotence pattern; Conduit's ledger runner is
-- the suite precedent). That is what makes a step safe to repeat and makes a
-- half-finished run self-correcting rather than destructive.
--
-- Termination is guaranteed three ways and never depends on an event arriving:
--   * per-op SETTLE_TTL      — a prediction that never lands is let go,
--   * per-step MAX_NO_PROGRESS — a residual that stops shrinking is a stall,
--   * per-run RUN_CEILING / MAX_STEPS — the latch is released regardless.

local function now() return (GetTime and GetTime()) or 0 end
local function canDefer() return (C_Timer and C_Timer.After) and true or false end

-- Everything the client publishes when a move lands. ITEM_LOCK_CHANGED alone is
-- the ARM-2 trap: it is the EARLY signal, and the contents follow it.
local SETTLE_EVENTS = {
    "ITEM_LOCK_CHANGED", "BAG_UPDATE", "BAG_UPDATE_DELAYED",
    "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED",
}

function Addon:EquipPass(name, attempt)
    local set = Addon:GetSet(name)
    if not set then Addon:FinishEquip(name, false); return end

    attempt = attempt or 1

    -- EquipPass is public, so it can be called cold. A run record is what the
    -- settle machinery needs; make one rather than half-running without it.
    local run = Addon._run
    if not (run and run.name == name) then
        Addon._runGen = (Addon._runGen or 0) + 1
        run = { name = name, gen = Addon._runGen, progressed = now(),
                inflight = {}, best = nil, stall = 0, issuedAny = false }
        Addon._run = run
    end
    run.step = attempt
    Addon._equipping = name

    local census = Addon:BuildCensus()
    local plan, missing = Addon:PlanSet(set, census)

    if attempt == 1 and #missing > 0 then
        Addon:ChatMsg("could not find: [" .. table.concat(missing, "] [") .. "]")
    end

    -- THE CENSUS CONFIRMS IT. An empty plan derived from settled state is the
    -- only thing that may mark the set current — never dispatch (ARM-1).
    if #plan == 0 then
        Addon:FinishEquip(name, true)
        return
    end

    if attempt >= MAX_STEPS or (now() - run.progressed) >= RUN_CEILING then
        Addon:AbortRun(name, nil)
        return
    end

    -- Progress is measured on the residual, not the clock: a run that is still
    -- shrinking its plan is still working, however slow the server is.
    if run.best == nil or #plan < run.best then
        run.best, run.stall, run.progressed = #plan, 0, now()
    else
        run.stall = run.stall + 1
    end

    -- ── Issue the wave ────────────────────────────────────────────────────────
    -- Only ops whose involved slots are disjoint from everything already going
    -- out this step. An op that overlaps is not skipped forever — it is simply
    -- left for a later step, by which time its dependency has SETTLED and it is
    -- planned against a world that really contains the earlier op's result.
    local claimed, issued, abort = {}, 0, nil
    for _, op in ipairs(plan) do
        if issued >= MAX_IN_FLIGHT then break end
        if Addon:OpStillNeeded(op) then
            local keys, free = Addon:OpSlotKeys(op, census), true
            if not keys then free = false end
            for _, k in ipairs(keys or {}) do if claimed[k] then free = false end end
            if free then
                local ok, code, pred = Addon:ExecuteOp(op, census)
                if ok then
                    run.issuedAny = true
                    for _, k in ipairs(keys) do claimed[k] = true end
                    if pred then
                        pred.at = now()
                        run.inflight[#run.inflight + 1] = pred
                        issued = issued + 1
                    end
                elseif code == ABORT_LOCKED then
                    -- Someone else is holding a slot we need. That is a reason to
                    -- WAIT, not to abandon the set; the stall guard ends it if the
                    -- lock never clears (ARM-4's audited shape).
                else
                    abort = code
                    break
                end
            end
        end
    end

    if abort then Addon:AbortRun(name, abort); return end

    -- Nothing issued, nothing in flight, and the residual is not shrinking: the
    -- world is not going to answer us. End it rather than watch forever.
    if issued == 0 and #run.inflight == 0 and run.stall >= MAX_NO_PROGRESS then
        Addon:AbortRun(name, ABORT_LOCKED)
        return
    end

    Addon:WatchSettle()
end

-- Arm the wait: the client's own publish events, plus a bounded backstop poll so
-- the wait is NEVER event-only (ARM-4's live shape — a pass whose ops were all
-- refused fires nothing at all and the old watcher never re-armed).
function Addon:WatchSettle()
    local run = Addon._run
    if not run then return end

    if CreateFrame and not Addon._lockWatcher then
        Addon._lockWatcher = CreateFrame("Frame")
        Addon._lockWatcher:SetScript("OnEvent", function()
            local w = Addon._lockWatcher
            if not (w and w._name) then return end
            local r = Addon._run
            if not (r and r.gen == w._gen) then return end
            Addon:ScheduleSettleCheck(r.gen, 0)
        end)
    end
    if Addon._lockWatcher then
        Addon._lockWatcher._name = run.name
        Addon._lockWatcher._gen  = run.gen
        for _, e in ipairs(SETTLE_EVENTS) do
            pcall(function() Addon._lockWatcher:RegisterEvent(e) end)
        end
    end

    -- No way to defer at all (a bare environment): we cannot wait for a settle,
    -- so finish honestly instead of leaving the latch set.
    if not canDefer() then Addon:FinishEquip(run.name, false); return end
    Addon:ScheduleSettleCheck(run.gen, SETTLE_POLL)
end

-- Exactly ONE check is ever live: each schedule takes the next tick and any
-- earlier one that fires afterwards recognises itself as stale and returns. A
-- publish burst is a dozen events about one landing, and it must cost one check,
-- not a dozen re-plans.
function Addon:ScheduleSettleCheck(gen, delay)
    local run = Addon._run
    if not (run and run.gen == gen) then return end
    if not canDefer() then return end
    local immediate = (delay or 0) <= 0
    if immediate and run.burst then return end   -- the burst already has a check coming

    run.tick  = (run.tick or 0) + 1
    run.burst = immediate or nil
    local tick = run.tick

    C_Timer.After(delay or 0, function()
        local r = Addon._run
        if not (r and r.gen == gen and r.tick == tick) then return end   -- superseded
        r.burst = nil
        Addon:SettleCheck(gen)
    end)
end

-- Retire what has landed, let go of what never will, then take the next step.
function Addon:SettleCheck(gen)
    local run = Addon._run
    if not (run and run.gen == gen) then return end

    local t, still = now(), {}
    for _, p in ipairs(run.inflight) do
        if Addon:OpSettled(p) then
            -- Retired on CONTENT. This is the whole fix.
        elseif (t - (p.at or t)) >= SETTLE_TTL then
            -- Reality wins at the ceiling: the op is re-planned from OBSERVED
            -- state, which is the only legitimate way to re-issue a move.
            run.ttlDrops = (run.ttlDrops or 0) + 1
        else
            still[#still + 1] = p
        end
    end
    run.inflight = still

    if (t - run.progressed) >= RUN_CEILING then Addon:AbortRun(run.name, nil); return end

    if #run.inflight > 0 then
        Addon:ScheduleSettleCheck(gen, SETTLE_POLL)
        return
    end

    Addon:EquipPass(run.name, (run.step or 1) + 1)
end

function Addon:StopLockWatcher()
    local w = Addon._lockWatcher
    if not w then return end
    w._name, w._attempt, w._gen = nil, nil, nil
    for _, e in ipairs(SETTLE_EVENTS) do
        pcall(function() w:UnregisterEvent(e) end)
    end
end

-- The one exit that is not convergence. Nothing of ours may be left hanging.
function Addon:AbortRun(name, code)
    local run = Addon._run
    -- A cursor the guard tripped over BEFORE we touched anything is the user's,
    -- not ours; clearing it would drop the item they were carrying.
    if not (code == ABORT_CURSOR and not (run and run.issuedAny)) then
        clearCursorBackstop()
    end
    Addon:ChatMsg(ABORT_TEXT[code] or "the swap was interrupted.")
    Addon:FinishEquip(name, false)
end

-- `converged` is the census verdict, not the fact that we stopped.
function Addon:FinishEquip(name, converged)
    Addon._equipping = nil
    Addon._run       = nil
    Addon:StopLockWatcher()

    if converged and Addon:GetSet(name) then
        Addon.db.currentSet = name
    end
    if Addon.ClearPendingSlots  then Addon:ClearPendingSlots()  end
    if Addon.UpdateSlotBorders  then Addon:UpdateSlotBorders()  end
    if Addon.RefreshWidget      then Addon:RefreshWidget()      end
    if Addon.RefreshSetList     then Addon:RefreshSetList()     end
end

function Addon:RunEquip(name)
    if not Addon:GetSet(name) then return end
    Addon._runGen = (Addon._runGen or 0) + 1
    Addon._run = { name = name, gen = Addon._runGen, progressed = now(),
                   inflight = {}, best = nil, stall = 0, issuedAny = false }
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

-- A queued action, resolved against the world AT DRAIN TIME.
function Addon:ActionToOp(slot, a)
    if not a then return nil end
    if a.kind == "unequip" then return { slot = slot, unequip = true } end
    if a.kind == "bag" then
        local link = (bagItem(a.bag, a.slot))
        if not link then return nil end                 -- the item moved; drop it
        return {
            slot    = slot,
            from    = { where = "bag", bag = a.bag, slot = a.slot, link = link },
            twoHand = (slot == 16) and (equipLocOf(link) == "INVTYPE_2HWEAPON") or false,
        }
    end
    if a.kind == "worn" then
        local link = wornLink(a.from)
        if not link then return nil end
        return { slot = slot, from = { where = "worn", invSlot = a.from, link = link } }
    end
    return nil
end

-- ── The drain ─────────────────────────────────────────────────────────────────
-- ARM-3: the queue used to be emptied BEFORE the loop, so action 2 — refused on
-- action 1's still-set locks — was gone forever. Now an action leaves the queue
-- only when it has been ISSUED, a refusal leaves it queued for the next round,
-- and the rounds are settle-paced and bounded.
function Addon:DrainCombatQueue()
    -- Never consume the queue against a corpse — hold it for the resurrect.
    -- Also hold if still in combat: resurrecting mid-fight fires PLAYER_UNGHOST
    -- while swaps are still refused, and a whole-set equip consumed there would
    -- be lost silently.
    if Addon:MustQueueSwap() then return end
    if not (Addon._combatQueue or Addon._pendingSet) then Addon:StopQueueWatcher(); return end
    if Addon._drain then return end                     -- a drain is already walking it

    Addon._drainGen = (Addon._drainGen or 0) + 1
    Addon._drain = { gen = Addon._drainGen, round = 0, inflight = {}, progressed = now() }
    Addon:DrainStep(Addon._drainGen)
end

function Addon:ScheduleDrainStep(gen, delay)
    if not canDefer() then return end
    C_Timer.After(delay or 0, function() Addon:DrainStep(gen) end)
end

function Addon:DrainStep(gen)
    local d = Addon._drain
    if not (d and d.gen == gen) then return end

    -- Retire on CONTENT, exactly as the equip run does.
    local t, still = now(), {}
    for _, p in ipairs(d.inflight) do
        if Addon:OpSettled(p) then                       -- landed
        elseif (t - (p.at or t)) >= SETTLE_TTL then      -- never will; let it go
        else still[#still + 1] = p end
    end
    d.inflight = still

    -- Combat came back (or the player died) mid-drain: HOLD whatever is left.
    if Addon:MustQueueSwap() then
        Addon._drain = nil
        Addon:EnsureRegenWatcher()
        return
    end

    if #d.inflight > 0 then
        if (t - d.progressed) < RUN_CEILING then Addon:ScheduleDrainStep(gen, SETTLE_POLL); return end
        d.inflight = {}                                  -- ceiling: stop waiting on them
    end

    local q = Addon._combatQueue
    if q and next(q) then
        d.round = d.round + 1
        if d.round > MAX_DRAIN_ROUNDS then
            clearCursorBackstop()
            Addon:ChatMsg("could not finish every queued swap.")
            Addon._combatQueue = nil
        else
            local issued = Addon:DrainWave(d)
            if issued > 0 then d.progressed = now() end   -- re-base: this round worked
            if issued > 0 or (Addon._combatQueue and next(Addon._combatQueue)) then
                if canDefer() then Addon:ScheduleDrainStep(gen, SETTLE_POLL); return end
            end
        end
    end

    -- The per-slot queue is done. Only now does the whole-set request run, so it
    -- plans against the world the queued actions actually produced.
    Addon._combatQueue = nil
    Addon._drain       = nil
    Addon:StopQueueWatcher()

    local pend = Addon._pendingSet
    Addon._pendingSet, Addon._pendingSkip = nil, nil
    if pend then Addon:RunEquip(pend) end
    if Addon.ClearPendingSlots then Addon:ClearPendingSlots() end
end

-- One round of the drain: the slot-disjoint, dependency-ordered wave.
--
-- Deterministic order is ascending target slot (trinket 13 before 14), with one
-- precedence rule on top: an action that SOURCES a slot another queued action
-- TARGETS has to go first, or the second action would move the item the first
-- one displaced rather than the item the user pointed at.
function Addon:DrainWave(d)
    local q = Addon._combatQueue
    if not q then return 0 end

    local slots = {}
    for slot in pairs(q) do slots[#slots + 1] = slot end
    table.sort(slots)

    local sourcedBy = {}
    for _, slot in ipairs(slots) do
        local a = q[slot]
        if a and a.kind == "worn" and a.from ~= slot then sourcedBy[a.from] = slot end
    end
    -- A cycle would block every action; fall back to plain ascending order.
    local anyFree = false
    for _, slot in ipairs(slots) do if not sourcedBy[slot] then anyFree = true end end

    local census, claimed, issued = Addon:BuildCensus(), {}, 0
    for _, slot in ipairs(slots) do
        if issued >= MAX_IN_FLIGHT then break end
        local a = q[slot]
        if a and not (anyFree and sourcedBy[slot]) then
            local op = Addon:ActionToOp(slot, a)
            if not op then
                q[slot] = nil                            -- the item is not there any more
            else
                local keys, free = Addon:OpSlotKeys(op, census), true
                if not keys then free = false end
                for _, k in ipairs(keys or {}) do if claimed[k] then free = false end end
                if free then
                    local ok, code, pred = Addon:ExecuteOp(op, census)
                    if ok then
                        for _, k in ipairs(keys) do claimed[k] = true end
                        q[slot] = nil                    -- issued: it may leave the queue
                        if pred then
                            pred.at = now()
                            d.inflight[#d.inflight + 1] = pred
                            issued = issued + 1
                        end
                    elseif code == ABORT_LOCKED then
                        -- Refused on a lock: KEEP it queued and retry next round.
                    else
                        clearCursorBackstop()
                        Addon:ChatMsg(ABORT_TEXT[code] or "the swap was interrupted.")
                        q[slot] = nil                    -- a hard refusal is not retried
                    end
                end
            end
        end
    end

    if not next(q) then Addon._combatQueue = nil end
    return issued
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

function Addon:DeferToCombatEnd(name, secureWeapons)
    Addon._pendingSet  = name
    Addon._pendingSkip = nil
    if secureWeapons then
        -- Weapon slots are being swapped right now by the secure macro, so they
        -- are not part of what is waiting for combat to end.
        local skip = {}
        for _, slotId in ipairs(Addon.SECURE_COMBAT_SLOTS) do skip[slotId] = true end
        Addon._pendingSkip = skip
    end
    Addon:EnsureRegenWatcher()
    if Addon.MarkSetPending then Addon:MarkSetPending(name, Addon._pendingSkip) end

    local tail = ""
    if secureWeapons then
        tail = " Weapons swap now."
    elseif Addon:SetHasCombatWeapons(name) then
        tail = " Give the set a key binding to swap its weapons during combat."
    end
    Addon:ChatMsg("\"" .. tostring(name) .. "\" queued " .. Addon:QueueReason()
        .. " — it will equip " .. Addon:QueueWhen() .. "." .. tail)
end

-- ── One immediate action, out of combat ───────────────────────────────────────
-- The single shared issue path for the flyout / sidebar / slot popouts, so the
-- guards, the abort wording and the ClearCursor backstop are written once.
function Addon:IssueAction(invSlot, a)
    local op = Addon:ActionToOp(invSlot, a)
    if not op then return false end
    local ok, code = Addon:ExecuteOp(op, Addon:BuildCensus())
    if ok then return true end
    if code ~= ABORT_CURSOR then clearCursorBackstop() end
    Addon:ChatMsg(ABORT_TEXT[code] or "the swap was interrupted.")
    return false
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
    return Addon:IssueAction(invSlot, { kind = "bag", bag = bag, slot = slot })
end

-- Take off the item currently in an equipment slot (into a free bag slot).
function Addon:UnequipSlot(invSlot)
    if Addon:MustQueueSwap() then
        local queued = Addon:QueueCombatAction(invSlot, { kind = "unequip" })
        if queued and Addon.SetPendingSlot then Addon:SetPendingSlot(invSlot, UNEQUIP_ICON) end
        return queued
    end
    return Addon:IssueAction(invSlot, { kind = "unequip" })
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
    return Addon:IssueAction(toSlot, { kind = "worn", from = fromSlot })
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

-- ── Secure in-combat weapon swaps (spec §2.8 / §6.1) ──────────────────────────
-- The client will not let this addon move an item during combat — every path in
-- this file ends in a cursor pickup, which is refused. The one mechanism the
-- spec describes that DOES work is the client's own secure macro command: a
-- SecureActionButton carrying `/equipslot [combat]<slot> <item name>` lines,
-- written while OUT of combat, fired by a real key press. The `[combat]`
-- condition means the line is inert out of combat, where the normal engine below
-- already does the work.

-- Macro text is a quoted Lua string inside a macro line; a set name containing a
-- quote or backslash would otherwise truncate the whole line.
local function escapeMacroArg(s)
    return (tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"'))
end

-- One `/equipslot` line per governed weapon slot whose item name resolves right
-- now. Skipped: slots the set does not govern, slots the set marks explicitly
-- empty (there is no secure "take this off" command), and items whose name the
-- client has not cached yet.
function Addon:WeaponMacroLines(name)
    local set, lines = Addon:GetSet(name), {}
    if not set then return lines end
    for _, slotId in ipairs(Addon.SECURE_COMBAT_SLOTS) do
        local entry = Addon:IsSlotActive(set, slotId) and set.equip[slotId] or nil
        if entry and not Addon:IsEmptyEntry(entry) then
            local link = Addon:EntryLink(entry)
            local itemName = link and GetItemInfo and GetItemInfo(link) or nil
            if itemName then
                lines[#lines + 1] = "/equipslot [combat]" .. slotId .. " " .. itemName
            end
        end
    end
    return lines
end

-- Full macro body for a set's secure button: the weapon lines (which only fire in
-- combat) followed by the ordinary equip call, flagged so the queue knows the
-- weapon slots are already being handled.
function Addon:BuildSetMacroText(name)
    local lines = Addon:WeaponMacroLines(name)
    lines[#lines + 1] = '/run ArmEquipSecure("' .. escapeMacroArg(name) .. '")'
    return table.concat(lines, "\n")
end

-- Does this set govern any slot the secure path can swap mid-combat?
function Addon:SetHasCombatWeapons(name)
    return #Addon:WeaponMacroLines(name) > 0
end

-- ── Public API ────────────────────────────────────────────────────────────────
-- opts.secureWeapons — set by the secure macro path only. It means the client is
-- equipping slots 16/17/18 itself via `/equipslot [combat]`, so those slots are
-- excluded from the pending-swap overlay: they are not waiting for combat to end,
-- they are changing right now. The end-of-combat drain still re-plans the whole
-- set, which is a no-op for any slot the secure lines already satisfied and a
-- repair for any that failed.
function Addon:EquipSet(name, opts)
    if not Addon:GetSet(name) then return false end

    if Addon:MustQueueSwap() then
        Addon:DeferToCombatEnd(name, opts and opts.secureWeapons)
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
-- Called only from the secure set-binding macro, after its /equipslot lines.
function ArmEquipSecure(name)
    return DaseekiArmory:EquipSet(name, { secureWeapons = true })
end
ArmoryEquipSet  = ArmEquip
ArmoryToggleSet = ArmToggle
