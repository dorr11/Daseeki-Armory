-- =====================================================================
-- Virtual WoW inventory world for the equip-engine self-tests.
--
-- Installs the handful of Blizzard APIs equip.lua touches over an in-memory
-- bags/worn/cursor model, then loads sets.lua + equip.lua against it. Cursor
-- semantics are modelled faithfully (picking up onto an occupied destination
-- hands the displaced item back on the cursor), so a swap only "works" here if
-- the engine puts the displaced item down again — the same requirement as in
-- the live client.
--
-- ── THE UNKIND CONTRACT (2026-08-07, audit brief A0) ─────────────────────────
-- Simulator doctrine (CLIENT_ASYNC_LESSONS.md, closing paragraph): any sim for
-- client interactions starts UNKIND; the spec-behaving profile is secondary.
-- This mock was KIND through 2026-08-03 — every pickup swapped cursor and slot
-- instantly and synchronously, and `isLocked` was only ever what a test poked
-- into `w.locks` by hand. That is the single reason every Class 1 finding in
-- Daseeki-Armory/equip.lua (SUITE_ASYNC_AUDIT.md, ARM-1…ARM-5) is invisible
-- headless.
--
-- The model below is ported from Daseeki-Bags/sort.lua:3200–3330 (the in-file
-- sort simulator, the suite's reference unkind sim), semantics for semantics:
--
--   1. TWO VIEWS. `truth` is server state, mutated the instant a drop is
--      issued. The VISIBLE view (`bags[b].items`, `worn[s]`) is what
--      GetContainerItemInfo / GetInventoryItemLink return, and it only catches
--      up when the round trip lands. Everything the ADDON can observe goes
--      through the visible view; every rule the SERVER applies is computed on
--      truth.
--   2. LOCK THEN SETTLE. A drop locks every slot it touches. `latency` later
--      the locks CLEAR and ITEM_LOCK_CHANGED fires. `settleLag` after THAT the
--      contents publish and BAG_UPDATE / PLAYER_EQUIPMENT_CHANGED /
--      BAG_UPDATE_DELAYED fire. The window between them is where a lock-only
--      "is it settled?" test reads the PRE-OPERATION world. The default
--      settleLag (0.35s) deliberately EXCEEDS equip.lua's PASS_DEBOUNCE (0.2s)
--      so the re-plan lands squarely inside that window — that is the live
--      shape ARM-2 describes.
--   3. REFUSAL IS COUNTED. A container/inventory op issued against a slot the
--      client itself reports LOCKED is refused and raises `lockedIssue`, which
--      fires a synthetic UI_ERROR_MESSAGE standing in for
--      ERR_INTERNAL_BAG_ERROR. Nothing in the engine reads that counter; the
--      SIM raises it and the fixtures assert it stayed at zero, so the engine
--      can never grade its own homework.
--   4. SERVER-SIDE VALIDATION. A drop says "move what I SEE in the source onto
--      what I SEE in the destination". The server checks its OWN truth; if
--      either end has moved on since the client's view was written the whole
--      operation is refused and nothing changes. That refusal is the live
--      Internal Bag Error, and it is what a settle window turns a RE-ISSUED
--      landed move into (Bags sort executor 2.0.2, verbatim).
--
-- The KIND profile (`mock.new(P, mock.KIND)`) restores the pre-A0 behaviour —
-- contents and locks move together, inline, with no round trip — for the tests
-- that legitimately need a settled world and are not testing the executor.
--
-- Returns a factory:
--   local mock = dofile("equip-mock.lua")
--   local w = mock.new(P)                 -- UNKIND (the default)
--   local w = mock.new(P, mock.KIND)      -- opt-in kind profile
--   local w = mock.new(P, { settleLag = 0.05 })
-- =====================================================================

local Mock = {}

-- Slot ids in the order core.lua's Addon.SLOTS declares them.
local SLOT_IDS = { 1, 2, 3, 15, 5, 4, 19, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }

-- id -> { name, equipLoc, icon }
local DEFAULT_ITEMS = {
    [1001] = { "Ring of Testing",   "INVTYPE_FINGER"  },
    [1002] = { "Band of Trial",     "INVTYPE_FINGER"  },
    [1003] = { "Loop of Proof",     "INVTYPE_FINGER"  },
    [2001] = { "Trinket Alpha",     "INVTYPE_TRINKET" },
    [2002] = { "Trinket Beta",      "INVTYPE_TRINKET" },
    [3001] = { "Test Helm",         "INVTYPE_HEAD"    },
    [3002] = { "Spare Helm",        "INVTYPE_HEAD"    },
    [4001] = { "Test Greatsword",   "INVTYPE_2HWEAPON"},
    [4002] = { "Test Sword",        "INVTYPE_WEAPON"  },
    [4003] = { "Test Shield",       "INVTYPE_SHIELD"  },
    [4004] = { "Test Bow",          "INVTYPE_RANGED"  },
}

-- Pass as a slot value to w:defineSet to store the explicit-empty sentinel
-- ("this slot must be EMPTY") rather than an item.
Mock.EMPTY = "<<EMPTY>>"

-- ── Profile tunables ──────────────────────────────────────────────────────────
-- latency   : server round-trip before the lock is released (ITEM_LOCK_CHANGED).
-- settleLag : gap between lock release and the contents publishing (BAG_UPDATE).
--             MUST exceed equip.lua's PASS_DEBOUNCE (0.2) for the default
--             profile, or the executor's stale re-census window closes by luck.
Mock.DEFAULT_LATENCY    = 0
Mock.DEFAULT_SETTLE_LAG = 0.35

-- Stands in for ERR_INTERNAL_BAG_ERROR. The live numeric id is build-specific,
-- so the text is carried alongside it exactly as Bags' sim does.
Mock.BAG_ERROR_ID   = 44
Mock.BAG_ERROR_TEXT = "Internal Bag Error"

-- The explicit opt-in kind profile: contents and locks move together, inline.
Mock.KIND   = { profile = "kind" }
Mock.UNKIND = { profile = "unkind" }

-- Build an item link. enchant/suffix default to 0.
function Mock.link(id, enchant, suffix)
    return string.format("item:%d:%d:0:0:0:0:%d:0:60:0", id, enchant or 0, suffix or 0)
end

local function idFromLink(link)
    if type(link) == "number" then return link end
    return tonumber(tostring(link):match("item:(%d+)"))
end

-- Slot keys. "b<bag>:<slot>" for containers, "w<slotId>" for worn — the same
-- spelling the existing fixtures poke into w.locks by hand.
local function bkey(bag, slot) return "b" .. bag .. ":" .. slot end
local function wkey(slot)      return "w" .. slot end

local function parseKey(k)
    local bag, slot = tostring(k):match("^b(%d+):(%d+)$")
    if bag then return "bag", tonumber(bag), tonumber(slot) end
    local inv = tostring(k):match("^w(%d+)$")
    if inv then return "worn", tonumber(inv) end
    return nil
end

local function logNameOf(k)
    local kind, a, b = parseKey(k)
    if kind == "bag" then return "bag:" .. a .. ":" .. b end
    if kind == "worn" then return "worn:" .. a end
    return tostring(k)
end

function Mock.new(P, opts)
    opts = opts or {}
    local profile = opts.profile or "unkind"
    local kind    = (profile == "kind")

    local w = {
        profile = profile,
        -- ── the two-phase settle ──────────────────────────────────────────
        latency   = opts.latency   or (kind and 0 or Mock.DEFAULT_LATENCY),
        settleLag = opts.settleLag or (kind and 0 or Mock.DEFAULT_SETTLE_LAG),
        -- `instant` collapses the round trip into the call itself. Kind only.
        instant   = (opts.instant ~= nil) and opts.instant or kind,

        bags    = {},   -- [bag] = { size = n, items = {visible}, truth = {server} }
        worn    = {},   -- [slotId] = link   (VISIBLE)
        wornTruth = {}, -- [slotId] = link   (SERVER TRUTH)
        cursor  = nil,  -- held link
        holdKey = nil,  -- slot key the held item came from
        heldDetached = false,  -- true once the held item has LEFT server truth
        heldTouched  = nil,    -- slot keys the gesture that detached it locked
        combat  = false,
        dead    = false,
        feign   = false,
        locks   = {},   -- ["b0:1"] / ["w11"] = true while a move is in flight
        frames  = {},
        clock   = 0,
        seq     = 0,
        timers  = {},   -- { at = <virtual time>, seq = n, fn = f }
        log     = {},   -- ordered record of every pickup
        events  = {},   -- ordered record of every event the SIM fired
        printed = {},
        items   = {},
        -- `refused`     — every refusal of any cause.
        -- `bagErrors`   — refusals the live client surfaces as "Internal Bag
        --                 Error": the addon asked the server to move something
        --                 the server no longer holds where the addon thought.
        -- `lockedIssue` — THE PERMANENT GATE: an op issued against a slot the
        --                 client itself reports LOCKED. Asserted by the SIM.
        stats   = { pickups = 0, drops = 0, refused = 0, applied = 0,
                    bagErrors = 0, lockedIssue = 0, lockEvents = 0, publishes = 0 },
    }
    for id, def in pairs(DEFAULT_ITEMS) do
        w.items[id] = { name = def[1], equipLoc = def[2], icon = "icon" .. id }
    end

    for _, bag in ipairs({ 0, 1, 2, 3, 4 }) do
        w.bags[bag] = { size = 16, items = {}, truth = {} }
    end

    ---------------------------------------------------------------- views
    local function getVis(k)
        local kind_, a, b = parseKey(k)
        if kind_ == "bag" then return w.bags[a] and w.bags[a].items[b] or nil end
        if kind_ == "worn" then return w.worn[a] end
        return nil
    end
    local function setVis(k, link)
        local kind_, a, b = parseKey(k)
        if kind_ == "bag" then if w.bags[a] then w.bags[a].items[b] = link end
        elseif kind_ == "worn" then w.worn[a] = link end
    end
    local function getTruth(k)
        local kind_, a, b = parseKey(k)
        if kind_ == "bag" then return w.bags[a] and w.bags[a].truth[b] or nil end
        if kind_ == "worn" then return w.wornTruth[a] end
        return nil
    end
    local function setTruth(k, link)
        local kind_, a, b = parseKey(k)
        if kind_ == "bag" then if w.bags[a] then w.bags[a].truth[b] = link end
        elseif kind_ == "worn" then w.wornTruth[a] = link end
    end

    ---------------------------------------------------------------- helpers
    -- Test setup writes BOTH views at once: in the client a fixture's starting
    -- state is not the result of a round trip, it simply IS the world.
    function w:setBag(bag, slot, link)
        if not self.bags[bag] then return end
        self.bags[bag].items[slot] = link
        self.bags[bag].truth[slot] = link
    end
    function w:setWorn(slot, link)
        self.worn[slot]      = link
        self.wornTruth[slot] = link
    end
    function w:bagOf(bag, slot)    return self.bags[bag] and self.bags[bag].items[slot] end
    function w:bagTruthOf(bag, slot) return self.bags[bag] and self.bags[bag].truth[slot] end
    function w:wornTruthOf(slot)   return self.wornTruth[slot] end
    function w:isLocked(key)       return self.locks[key] and true or false end

    -- Re-point the profile mid-test (e.g. to close the settle window and prove
    -- the window is what the failure depends on).
    function w:setProfile(o)
        o = o or {}
        if o.profile then
            self.profile = o.profile
            local k = (o.profile == "kind")
            self.latency   = o.latency   or (k and 0 or Mock.DEFAULT_LATENCY)
            self.settleLag = o.settleLag or (k and 0 or Mock.DEFAULT_SETTLE_LAG)
            self.instant   = (o.instant ~= nil) and o.instant or k
            return
        end
        if o.latency   ~= nil then self.latency   = o.latency   end
        if o.settleLag ~= nil then self.settleLag = o.settleLag end
        if o.instant   ~= nil then self.instant   = o.instant   end
    end

    -- Fill every bag slot except `keepFree` slots in bag 0, so "no room" is testable.
    function w:fillBags(keepFree)
        keepFree = keepFree or 0
        local free = keepFree
        for _, bag in ipairs({ 0, 1, 2, 3, 4 }) do
            for slot = 1, self.bags[bag].size do
                if self.bags[bag].items[slot] == nil then
                    if free > 0 then free = free - 1
                    else self:setBag(bag, slot, Mock.link(9999)) end
                end
            end
        end
    end

    function w:countFreeBagSlots()
        local n = 0
        for _, bag in ipairs({ 0, 1, 2, 3, 4 }) do
            for slot = 1, self.bags[bag].size do
                if self.bags[bag].items[slot] == nil then n = n + 1 end
            end
        end
        return n
    end

    function w:fireEvent(evt, a, b)
        self.events[#self.events + 1] = { evt = evt, a = a, b = b, at = self.clock }
        -- Snapshot: a handler may create a frame, and a frame created during
        -- dispatch has not registered for the event being dispatched.
        local snap = {}
        for i, f in ipairs(self.frames) do snap[i] = f end
        for _, f in ipairs(snap) do
            if f._events[evt] and f._script then f._script(f, evt, a, b) end
        end
    end

    -- How many times an event has been fired (sim-suite bookkeeping).
    function w:countEvents(evt)
        local n = 0
        for _, e in ipairs(self.events) do if e.evt == evt then n = n + 1 end end
        return n
    end

    -- Virtual clock. Ported from Daseeki-Bags/sort.lua's S.after / S:pump: the
    -- earliest-then-lowest-sequence timer wins, so ordering is deterministic and
    -- `settleLag` actually means something.
    function w:after(delay, fn)
        self.seq = self.seq + 1
        self.timers[#self.timers + 1] = { at = self.clock + (delay or 0), seq = self.seq, fn = fn }
    end

    -- Run the clock forward until the queue drains or `limit` virtual seconds
    -- pass. This is the client finishing every round trip it owes.
    function w:settle(limit)
        limit = limit or 30
        local guard = 0
        while true do
            guard = guard + 1
            if guard > 100000 then error("equip-mock: timer storm (possible infinite loop)") end
            local best
            for i, t in ipairs(self.timers) do
                if not best or t.at < self.timers[best].at
                   or (t.at == self.timers[best].at and t.seq < self.timers[best].seq) then best = i end
            end
            if not best then return end
            local t = self.timers[best]
            if t.at > limit then return end
            table.remove(self.timers, best)
            if t.at > self.clock then self.clock = t.at end
            t.fn()
        end
    end
    -- Historic name, kept so existing fixtures read unchanged.
    w.pumpTimers = w.settle

    function w:output() return table.concat(self.printed, "\n") end

    ---------------------------------------------------------------- settle machinery
    local function publish(touched)
        for _, k in ipairs(touched) do setVis(k, getTruth(k)) end
        w.stats.applied   = w.stats.applied + 1
        w.stats.publishes = w.stats.publishes + 1
    end

    -- The lock clears BEFORE the contents are rewritten. This is the whole
    -- point of the profile: anything that treats "unlocked" as "settled" reads
    -- the pre-operation world here.
    local function unlockAndAnnounce(touched)
        for _, k in ipairs(touched) do w.locks[k] = nil end
        for _, k in ipairs(touched) do
            local kind_, a, b = parseKey(k)
            w.stats.lockEvents = w.stats.lockEvents + 1
            if kind_ == "bag" then w:fireEvent("ITEM_LOCK_CHANGED", a, b)
            else w:fireEvent("ITEM_LOCK_CHANGED", a, nil) end
        end
    end

    local function announceContents(touched)
        local bagsSeen, wornSeen, anyWorn = {}, {}, false
        for _, k in ipairs(touched) do
            local kind_, a = parseKey(k)
            if kind_ == "bag" then
                if not bagsSeen[a] then bagsSeen[a] = true; w:fireEvent("BAG_UPDATE", a) end
            elseif kind_ == "worn" then
                if not wornSeen[a] then
                    wornSeen[a] = true; anyWorn = true
                    w:fireEvent("PLAYER_EQUIPMENT_CHANGED", a, w.worn[a] ~= nil)
                end
            end
        end
        if anyWorn then w:fireEvent("UNIT_INVENTORY_CHANGED", "player") end
        w:fireEvent("BAG_UPDATE_DELAYED")
    end

    -- The round-trip landing. With settleLag <= 0 this is the KIND model:
    -- contents and lock move together. With a settle lag it is the LIVE model —
    -- the lock clears first (ITEM_LOCK_CHANGED) and the contents catch up later
    -- (BAG_UPDATE), and the window between them is where a lock-only "is it
    -- settled?" test reads a stale world.
    local function commit(touched)
        local function land()
            if (w.settleLag or 0) <= 0 then
                publish(touched)
                unlockAndAnnounce(touched)
                announceContents(touched)
                return
            end
            unlockAndAnnounce(touched)
            w:after(w.settleLag, function()
                publish(touched)
                announceContents(touched)
            end)
        end
        if w.instant then land() else w:after(w.latency, land) end
    end

    ---------------------------------------------------------------- refusals
    local function bagError()
        w.stats.bagErrors = w.stats.bagErrors + 1
        w.stats.refused   = w.stats.refused + 1
        w:fireEvent("UI_ERROR_MESSAGE", Mock.BAG_ERROR_ID, Mock.BAG_ERROR_TEXT)
    end

    -- THE PERMANENT GATE. Nothing in equip.lua reads this; the SIM raises it and
    -- the fixtures assert it stayed at zero.
    local function lockedIssue()
        w.stats.lockedIssue = w.stats.lockedIssue + 1
        bagError()
    end

    local function isLockedKey(k)
        -- A slot whose item is sitting on the cursor is locked too — that is
        -- what the greyed-out icon means in the live client.
        return (w.locks[k] or (w.holdKey == k and not w.heldDetached)) and true or false
    end

    ---------------------------------------------------------------- the move
    -- One pickup/drop against a slot key. Empty cursor = pick up (client-side
    -- only, nothing leaves the server); loaded cursor = drop (the server applies
    -- it, both ends lock, and the round trip lands later).
    local function touchSlot(k)
        w.log[#w.log + 1] = logNameOf(k)

        if w.cursor == nil then
            ------------------------------------------------------------ pick up
            if isLockedKey(k) then lockedIssue(); return end
            -- The client picks up WHAT IT CAN SEE, not what the server holds.
            -- Inside the settle window those disagree, and the disagreement is
            -- only detected at the drop — by the server, as an Internal Bag Error.
            local link = getVis(k)
            if not link then return end
            w.cursor, w.holdKey = link, k
            w.heldDetached, w.heldTouched = false, nil
            w.stats.pickups = w.stats.pickups + 1
            return
        end

        ---------------------------------------------------------------- drop
        w.stats.drops = w.stats.drops + 1
        local srcKey = w.holdKey

        -- A drop that completes the SAME client gesture — putting the displaced
        -- item into the slot this very swap just vacated — is not a second
        -- operation. The live client accepts it; the sim must too, or the
        -- ordinary "equip over an occupied slot" flow could never work.
        local ownGesture = (k == srcKey) or (w.heldTouched and w.heldTouched[k]) or false

        if w.locks[k] and not ownGesture then lockedIssue(); return end

        -- Dropping an item back onto the slot it came from when nothing has
        -- actually left that slot is a no-op: the client simply puts it down.
        if k == srcKey and not w.heldDetached then
            w.cursor, w.holdKey, w.heldTouched = nil, nil, nil
            return
        end

        -- ── SERVER-SIDE VALIDATION ────────────────────────────────────────────
        -- The client sent "move what I SEE in the source onto what I SEE in the
        -- destination". The server checks its OWN truth; if either end has moved
        -- on since the client's view was written, the whole operation is refused
        -- and nothing changes. That refusal is the live Internal Bag Error, and
        -- it is what a settle window turns a re-issued landed move into.
        if not ownGesture then
            if not w.heldDetached and srcKey and getTruth(srcKey) ~= getVis(srcKey) then
                bagError(); return   -- item stays on the cursor
            end
            if getTruth(k) ~= getVis(k) then bagError(); return end
        end

        ---------------------------------------------------------------- apply
        local dst     = getTruth(k)
        local held    = w.cursor
        local touched = { k }
        w.locks[k] = true
        if not w.heldDetached and srcKey and srcKey ~= k then
            setTruth(srcKey, nil)
            w.locks[srcKey] = true
            touched[#touched + 1] = srcKey
        end
        setTruth(k, held)

        if dst ~= nil then
            -- Equipping/dropping onto an occupied slot hands the displaced item
            -- back on the cursor. It has LEFT server truth, so the caller must
            -- put it somewhere — into one of the slots this gesture just touched
            -- (which is where equip.lua puts it) or anywhere else that is free.
            local ht = {}
            for _, t in ipairs(touched) do ht[t] = true end
            w.cursor, w.holdKey = dst, k
            w.heldDetached, w.heldTouched = true, ht
        else
            w.cursor, w.holdKey = nil, nil
            w.heldDetached, w.heldTouched = false, nil
        end

        commit(touched)
    end

    ---------------------------------------------------------------- API install
    local G = _G

    -- Remember every global we are about to shadow so the harness's own output
    -- (and any later suite) is never affected by the mock.
    local INSTALLED = {
        "C_Container", "PickupInventoryItem", "GetInventoryItemLink",
        "GetInventoryItemTexture", "GetInventoryItemID", "IsInventoryItemLocked",
        "CursorHasItem", "ClearCursor", "SpellIsTargeting", "UnitAffectingCombat",
        "UnitIsDeadOrGhost", "UnitIsFeignDeath", "GetItemInfoInstant", "GetItemInfo",
        "CreateFrame", "C_Timer", "GetTime", "print", "DaseekiArmory",
        "ArmEquip", "ArmToggle", "ArmEquipSecure", "ArmoryEquipSet", "ArmoryToggleSet",
        "strtrim", "wipe",
    }
    local saved = {}
    for _, k in ipairs(INSTALLED) do saved[k] = G[k] end
    function w:teardown()
        for _, k in ipairs(INSTALLED) do G[k] = saved[k] end
    end

    G.C_Container = {
        GetContainerNumSlots = function(bag)
            return w.bags[bag] and w.bags[bag].size or 0
        end,
        GetContainerItemInfo = function(bag, slot)
            if not w.bags[bag] then return nil end
            local link = w.bags[bag].items[slot]
            if not link then
                -- An empty slot still reports its lock state — it is the source
                -- half of a move that is still in flight.
                if isLockedKey(bkey(bag, slot)) then return { hyperlink = nil, isLocked = true } end
                return nil
            end
            return { hyperlink = link, isLocked = isLockedKey(bkey(bag, slot)) }
        end,
        GetContainerItemLink = function(bag, slot)
            return w.bags[bag] and w.bags[bag].items[slot] or nil
        end,
        GetContainerNumFreeSlots = function(bag)
            local n = 0
            for slot = 1, (w.bags[bag] and w.bags[bag].size or 0) do
                if w.bags[bag].items[slot] == nil then n = n + 1 end
            end
            return n, 0   -- family 0 = generic container
        end,
        PickupContainerItem = function(bag, slot)
            if not w.bags[bag] or slot < 1 or slot > w.bags[bag].size then return end
            touchSlot(bkey(bag, slot))
        end,
    }

    G.PickupInventoryItem = function(slot) touchSlot(wkey(slot)) end

    G.GetInventoryItemLink    = function(_, slot) return w.worn[slot] end
    G.GetInventoryItemTexture = function(_, slot)
        local id = idFromLink(w.worn[slot])
        return id and w.items[id] and w.items[id].icon or nil
    end
    G.GetInventoryItemID      = function(_, slot) return idFromLink(w.worn[slot]) end
    G.IsInventoryItemLocked   = function(slot) return isLockedKey(wkey(slot)) end

    G.CursorHasItem    = function() return w.cursor ~= nil end
    -- Putting the cursor down returns the held item to where it came from, so
    -- nothing can ever be destroyed by a belt-and-suspenders ClearCursor().
    G.ClearCursor      = function()
        if not w.cursor then w.holdKey, w.heldTouched = nil, nil; return end
        local k, held, detached = w.holdKey, w.cursor, w.heldDetached
        w.cursor, w.holdKey, w.heldDetached, w.heldTouched = nil, nil, false, nil
        -- Picked up but never dropped (or the drop was refused): server truth
        -- never lost the item, so putting the cursor down changes nothing.
        if not detached or not k then return end
        if getTruth(k) == nil then
            setTruth(k, held)
            w.locks[k] = true
            commit({ k })
            return
        end
        -- Origin taken by something else: park it in the first free bag slot.
        for _, bag in ipairs({ 0, 1, 2, 3, 4 }) do
            for slot = 1, w.bags[bag].size do
                if w.bags[bag].truth[slot] == nil then
                    local fk = bkey(bag, slot)
                    setTruth(fk, held)
                    w.locks[fk] = true
                    commit({ fk })
                    return
                end
            end
        end
    end
    G.SpellIsTargeting = function() return w.targeting or false end

    G.UnitAffectingCombat = function() return w.combat end
    G.UnitIsDeadOrGhost   = function() return w.dead end
    G.UnitIsFeignDeath    = function() return w.feign end

    local function itemDef(link)
        local id = idFromLink(link)
        if not id then return nil end
        return id, w.items[id] or { name = "Item " .. id, equipLoc = "INVTYPE_FINGER", icon = "icon" }
    end

    G.GetItemInfoInstant = function(link)
        local id, def = itemDef(link)
        if not id then return nil end
        -- id, type, subType, equipLoc, icon
        return id, "Armor", "Misc", def.equipLoc, def.icon
    end

    G.GetItemInfo = function(link)
        local id, def = itemDef(link)
        if not id then return nil end
        -- name, link, quality, iLvl, reqLvl, class, subclass, maxStack, equipLoc, texture
        return def.name, (type(link) == "number" and Mock.link(link) or link), 2, 60, 1,
               "Armor", "Misc", 1, def.equipLoc, def.icon
    end

    G.CreateFrame = function()
        local f = { _events = {}, _script = nil }
        function f:RegisterEvent(e)   self._events[e] = true end
        function f:UnregisterEvent(e) self._events[e] = nil  end
        function f:UnregisterAllEvents() self._events = {} end
        function f:SetScript(k, fn)   if k == "OnEvent" then self._script = fn end end
        w.frames[#w.frames + 1] = f
        return f
    end

    G.C_Timer = { After = function(d, fn) w:after(d, fn) end }
    G.GetTime = function() return w.clock end

    -- Blizzard string/table helpers sets.lua uses (export/import, save-over).
    G.strtrim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
    G.wipe    = function(t) for k in pairs(t) do t[k] = nil end return t end

    G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        w.printed[#w.printed + 1] = table.concat(parts, " ")
    end

    ---------------------------------------------------------------- addon load
    local Addon = {}
    Addon.SLOT_IDS = SLOT_IDS
    Addon.db = { sets = {}, settings = { chatMessages = true }, currentSet = nil }
    function Addon:Tag() return "[Armory]" end

    G.DaseekiArmory = Addon

    for _, file in ipairs({ "sets.lua", "equip.lua" }) do
        local fn, err = loadfile(P(file))
        if not fn then error("mock: cannot compile " .. file .. " -> " .. tostring(err)) end
        local ok, rerr = pcall(fn, "Daseeki-Armory", Addon)
        if not ok then error("mock: " .. file .. " raised at load -> " .. tostring(rerr)) end
    end

    w.Addon = Addon

    -- Define a set from a { [slotId] = link } map. Mock.EMPTY stores the
    -- explicit-empty sentinel instead of an item.
    function w:defineSet(name, slots, disabled)
        local set = { name = name, equip = {}, disabled = disabled or {} }
        for slotId, link in pairs(slots) do
            if link == Mock.EMPTY then
                set.equip[slotId] = Addon:EmptyEntry()
            else
                set.equip[slotId] = Addon:IdentityFromLink(link)
            end
        end
        Addon.db.sets[name] = set
        return set
    end

    return w
end

Mock.SLOT_IDS = SLOT_IDS
return Mock
