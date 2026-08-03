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
-- Returns a factory: local mock = dofile("equip-mock.lua"); local w = mock.new(P)
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

-- Build an item link. enchant/suffix default to 0.
function Mock.link(id, enchant, suffix)
    return string.format("item:%d:%d:0:0:0:0:%d:0:60:0", id, enchant or 0, suffix or 0)
end

local function idFromLink(link)
    if type(link) == "number" then return link end
    return tonumber(tostring(link):match("item:(%d+)"))
end

function Mock.new(P)
    local w = {
        bags    = {},   -- [bag] = { size = n, items = { [slot] = link } }
        worn    = {},   -- [slotId] = link
        cursor  = nil,
        combat  = false,
        dead    = false,
        feign   = false,
        locks   = {},   -- ["b0:1"] / ["w11"] = true
        frames  = {},
        timers  = {},
        log     = {},   -- ordered record of every pickup
        printed = {},
        items   = {},
    }
    for id, def in pairs(DEFAULT_ITEMS) do
        w.items[id] = { name = def[1], equipLoc = def[2], icon = "icon" .. id }
    end

    for _, bag in ipairs({ 0, 1, 2, 3, 4 }) do
        w.bags[bag] = { size = 16, items = {} }
    end

    ---------------------------------------------------------------- helpers
    function w:setBag(bag, slot, link) self.bags[bag].items[slot] = link end
    function w:setWorn(slot, link)     self.worn[slot] = link end
    function w:bagOf(bag, slot)        return self.bags[bag].items[slot] end

    -- Fill every bag slot except `keepFree` slots in bag 0, so "no room" is testable.
    function w:fillBags(keepFree)
        keepFree = keepFree or 0
        local free = keepFree
        for _, bag in ipairs({ 0, 1, 2, 3, 4 }) do
            for slot = 1, self.bags[bag].size do
                if self.bags[bag].items[slot] == nil then
                    if free > 0 then free = free - 1
                    else self.bags[bag].items[slot] = Mock.link(9999) end
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

    function w:fireEvent(evt)
        for _, f in ipairs(self.frames) do
            if f._events[evt] and f._script then f._script(f, evt) end
        end
    end

    -- Run every pending C_Timer callback (repeatedly, since one may add more).
    function w:pumpTimers()
        for _ = 1, 10 do
            local due = self.timers
            if #due == 0 then return end
            self.timers = {}
            for _, t in ipairs(due) do t() end
        end
    end

    function w:output() return table.concat(self.printed, "\n") end

    ---------------------------------------------------------------- API install
    local G = _G

    -- Remember every global we are about to shadow so the harness's own output
    -- (and any later suite) is never affected by the mock.
    local INSTALLED = {
        "C_Container", "PickupInventoryItem", "GetInventoryItemLink",
        "GetInventoryItemTexture", "GetInventoryItemID", "IsInventoryItemLocked",
        "CursorHasItem", "ClearCursor", "SpellIsTargeting", "UnitAffectingCombat",
        "UnitIsDeadOrGhost", "UnitIsFeignDeath", "GetItemInfoInstant", "GetItemInfo",
        "CreateFrame", "C_Timer", "print", "DaseekiArmory",
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
            local link = w.bags[bag] and w.bags[bag].items[slot]
            if not link then return nil end
            return { hyperlink = link, isLocked = w.locks["b" .. bag .. ":" .. slot] or false }
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
        -- Cursor semantics: swap cursor with the bag slot's contents.
        PickupContainerItem = function(bag, slot)
            w.log[#w.log + 1] = "bag:" .. bag .. ":" .. slot
            local held = w.cursor
            w.cursor = w.bags[bag].items[slot]
            w.bags[bag].items[slot] = held
        end,
    }

    G.PickupInventoryItem = function(slot)
        w.log[#w.log + 1] = "worn:" .. slot
        local held = w.cursor
        w.cursor = w.worn[slot]
        w.worn[slot] = held
    end

    G.GetInventoryItemLink    = function(_, slot) return w.worn[slot] end
    G.GetInventoryItemTexture = function(_, slot)
        local id = idFromLink(w.worn[slot])
        return id and w.items[id] and w.items[id].icon or nil
    end
    G.GetInventoryItemID      = function(_, slot) return idFromLink(w.worn[slot]) end
    G.IsInventoryItemLocked   = function(slot) return w.locks["w" .. slot] or false end

    G.CursorHasItem    = function() return w.cursor ~= nil end
    G.ClearCursor      = function() w.cursor = nil end
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
        function f:SetScript(k, fn)   if k == "OnEvent" then self._script = fn end end
        w.frames[#w.frames + 1] = f
        return f
    end

    G.C_Timer = { After = function(_, fn) w.timers[#w.timers + 1] = fn end }

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
