--[[
    Daseeki Armory — equip engine.

    Ported from ItemRack's ItemRackEquip.lua to Classic Era's C_Container API and
    simplified: locate each set item in bags (or another equipped slot), swap it in,
    and re-verify across a few lock-driven passes. In combat the swap is deferred to
    PLAYER_REGEN_ENABLED. Exposes a global EquipSet() so /run EquipSet("name") works.
--]]

local _, Addon = ...

-- Informational combat-queue chatter — only shown when Chat Messages is enabled.
function Addon:ChatMsg(text)
    if Addon.db and Addon.db.settings and Addon.db.settings.chatMessages then
        print(Addon:Tag() .. " " .. text)
    end
end

-- ── Classic C_Container shims ─────────────────────────────────────────────────
local GetContainerNumSlots = (C_Container and C_Container.GetContainerNumSlots) or _G.GetContainerNumSlots
local GetContainerItemLink = (C_Container and C_Container.GetContainerItemLink) or _G.GetContainerItemLink
local PickupContainerItem  = (C_Container and C_Container.PickupContainerItem)  or _G.PickupContainerItem

local function ContainerItemInfo(bag, slot)
    if C_Container then return C_Container.GetContainerItemInfo(bag, slot) end
    local icon, count, locked = _G.GetContainerItemInfo(bag, slot)
    if not icon then return nil end
    return { isLocked = locked, iconFileID = icon, stackCount = count }
end

local function baseIdOf(itemString)
    return tonumber(itemString:match("^(%d+)"))
end

-- Which INVTYPE_* values may go into each inventory slot (for inventory flyouts).
Addon.SLOT_INVTYPES = {
    [1]  = { INVTYPE_HEAD = true },
    [2]  = { INVTYPE_NECK = true },
    [3]  = { INVTYPE_SHOULDER = true },
    [15] = { INVTYPE_CLOAK = true },
    [5]  = { INVTYPE_CHEST = true, INVTYPE_ROBE = true },
    [4]  = { INVTYPE_BODY = true },
    [19] = { INVTYPE_TABARD = true },
    [9]  = { INVTYPE_WRIST = true },
    [10] = { INVTYPE_HAND = true },
    [6]  = { INVTYPE_WAIST = true },
    [7]  = { INVTYPE_LEGS = true },
    [8]  = { INVTYPE_FEET = true },
    [11] = { INVTYPE_FINGER = true },
    [12] = { INVTYPE_FINGER = true },
    [13] = { INVTYPE_TRINKET = true },
    [14] = { INVTYPE_TRINKET = true },
    [16] = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true },
    [17] = { INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true },
    [18] = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true, INVTYPE_RELIC = true },
}

function Addon:IsSlotActive(set, slotId)
    return set.equip[slotId] ~= nil and not (set.disabled and set.disabled[slotId])
end

-- Is the set's item for this slot equippable right now (worn or in bags)?
function Addon:IsEntryAvailable(entry)
    if not entry then return true end
    if Addon:FindInBags(entry) then return true end
    if Addon:FindInEquipped(entry, nil) then return true end
    return false
end

-- ── Matching ──────────────────────────────────────────────────────────────────
function Addon:SlotMatches(slotId, entry)
    local link = GetInventoryItemLink("player", slotId)
    if not link then return false end
    local str = Addon:ItemString(link)
    if not str then return false end
    if entry.exact then return Addon:ExactKey(str) == entry.exact end
    return baseIdOf(str) == entry.id
end

-- Base-item-id match only (ignores enchant/suffix). Used so a slot wearing the
-- right item isn't falsely reported "missing" when a stale exact key (e.g. an
-- ItemRack import without enchant data) doesn't match the live enchanted item.
function Addon:SlotMatchesBase(slotId, entry)
    local link = GetInventoryItemLink("player", slotId)
    if not link then return false end
    local str = Addon:ItemString(link)
    return str ~= nil and baseIdOf(str) == entry.id
end

-- exact match first, base-id match as fallback
function Addon:FindInBags(entry)
    local baseBag, baseSlot
    for bag = 0, 4 do
        local num = GetContainerNumSlots(bag) or 0
        for slot = 1, num do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local str = Addon:ItemString(link)
                if str then
                    if entry.exact and Addon:ExactKey(str) == entry.exact then
                        return bag, slot, true
                    end
                    if not baseBag and baseIdOf(str) == entry.id then
                        baseBag, baseSlot = bag, slot
                    end
                end
            end
        end
    end
    if baseBag then return baseBag, baseSlot, false end
    return nil
end

function Addon:FindInEquipped(entry, exclude)
    local baseHit
    for _, slotId in ipairs(Addon.SLOT_IDS) do
        if slotId ~= exclude then
            local link = GetInventoryItemLink("player", slotId)
            if link then
                local str = Addon:ItemString(link)
                if str then
                    if entry.exact and Addon:ExactKey(str) == entry.exact then return slotId, true end
                    if not baseHit and baseIdOf(str) == entry.id then baseHit = slotId end
                end
            end
        end
    end
    if baseHit then return baseHit, false end
end

function Addon:FindFreeBagSlot()
    for bag = 0, 4 do
        local num = GetContainerNumSlots(bag) or 0
        for slot = 1, num do
            if not ContainerItemInfo(bag, slot) then return bag, slot end
        end
    end
end

-- ── Single-slot swap ──────────────────────────────────────────────────────────
function Addon:EquipSlot(slotId, entry)
    if Addon:SlotMatches(slotId, entry) then return true end
    if CursorHasItem() or SpellIsTargeting() then return false, "busy" end

    local bag, slot = Addon:FindInBags(entry)
    if bag then
        -- Equipping a 2H to the main hand: clear the off-hand to a free bag slot first.
        if slotId == 16 then
            local link = GetContainerItemLink(bag, slot)
            local equipLoc = link and select(9, GetItemInfo(link))
            if equipLoc == "INVTYPE_2HWEAPON" and GetInventoryItemLink("player", 17) then
                local fb, fs = Addon:FindFreeBagSlot()
                if fb then
                    ClearCursor()
                    PickupInventoryItem(17)
                    PickupContainerItem(fb, fs)
                    ClearCursor()
                end
            end
        end
        ClearCursor()
        PickupContainerItem(bag, slot)
        PickupInventoryItem(slotId)
        ClearCursor()
        return true
    end

    -- Item is worn in another slot (ring/trinket/weapon) — swap the two slots.
    local otherSlot = Addon:FindInEquipped(entry, slotId)
    if otherSlot then
        ClearCursor()
        PickupInventoryItem(otherSlot)
        PickupInventoryItem(slotId)
        ClearCursor()
        return true
    end

    return false, "missing"
end

-- ── Multi-pass orchestration ──────────────────────────────────────────────────
function Addon:EquipPass(name, attempt)
    local set = Addon.db.sets[name]
    if not set then Addon._equipping = nil; return end
    if InCombatLockdown() then Addon:DeferToCombatEnd(name); return end

    for _, slotId in ipairs(Addon.SLOT_IDS) do
        local entry = set.equip[slotId]
        if Addon:IsSlotActive(set, slotId) and not Addon:SlotMatches(slotId, entry) then
            Addon:EquipSlot(slotId, entry)
        end
    end

    local remaining = false
    for _, slotId in ipairs(Addon.SLOT_IDS) do
        local entry = set.equip[slotId]
        if Addon:IsSlotActive(set, slotId) and not Addon:SlotMatches(slotId, entry)
           and (Addon:FindInBags(entry) or Addon:FindInEquipped(entry, slotId)) then
            remaining = true
            break
        end
    end

    if remaining and attempt < 12 then
        C_Timer.After(0.15, function() Addon:EquipPass(name, attempt + 1) end)
    else
        Addon:FinishEquip(name)
    end
end

function Addon:FinishEquip(name)
    Addon._equipping = nil
    local set = Addon.db.sets[name]
    if not set then return end

    local missing = {}
    for _, slotId in ipairs(Addon.SLOT_IDS) do
        local entry = set.equip[slotId]
        -- only truly missing if the right base item isn't worn here, not in bags,
        -- and not worn in another slot (tolerates enchant/suffix differences).
        if Addon:IsSlotActive(set, slotId) and not Addon:SlotMatchesBase(slotId, entry)
           and not Addon:FindInBags(entry) and not Addon:FindInEquipped(entry, slotId) then
            local itemName = GetItemInfo(Addon:EntryLink(entry) or entry.id or 0)
            missing[#missing + 1] = itemName or ("item:" .. (entry.id or "?"))
        end
    end

    Addon.db.currentSet = name
    if Addon.RefreshWidget  then Addon:RefreshWidget()  end
    if Addon.RefreshOptions then Addon:RefreshOptions() end

    if #missing > 0 then
        print(Addon:Tag() .. " equipped '" .. name .. "' — could not find: " ..
            table.concat(missing, ", "))
    end
end

function Addon:RunEquip(name)
    if not Addon.db.sets[name] then return end
    Addon._equipping = name
    Addon:EquipPass(name, 0)
end

-- ── Combat queue (whole sets + individual sidebar equips) ─────────────────────
-- Keyed by the TARGET equipment slot so only one pending action exists per slot,
-- and re-selecting the same item toggles it back off.
function Addon:EnsureRegenWatcher()
    if not Addon._regen then
        Addon._regen = CreateFrame("Frame")
        Addon._regen:SetScript("OnEvent", function()
            Addon._regen:UnregisterEvent("PLAYER_REGEN_ENABLED")
            -- queued single-item actions first (slot -> action)
            local q = Addon._combatQueue
            Addon._combatQueue = nil
            if q then
                for slot, act in pairs(q) do
                    if act.type == "unequip" then
                        Addon:UnequipSlot(slot)
                    elseif act.type == "swap" then
                        Addon:SwapEquippedSlots(act.from, slot)
                    elseif act.type == "equip" then
                        local e = Addon:IdentityFromLink(act.link)
                        local bag, bslot
                        if e then bag, bslot = Addon:FindInBags(e) end
                        if bag and bslot then Addon:EquipContainerItemToSlot(bag, bslot, slot) end
                    end
                end
            end
            -- then a queued whole set
            local pend = Addon._pendingSet
            Addon._pendingSet = nil
            if pend then Addon:RunEquip(pend) end
            if Addon.ClearPendingSlots then Addon:ClearPendingSlots() end
        end)
    end
    Addon._regen:RegisterEvent("PLAYER_REGEN_ENABLED")
end

local function sameAction(a, b)
    if not a or a.type ~= b.type then return false end
    if a.type == "equip" then return a.id == b.id end
    if a.type == "swap"  then return a.from == b.from end
    return true  -- unequip
end

-- Queue (or, if the identical action is already queued for that slot, un-queue) a
-- per-slot combat action. Returns true if now queued, false if it was toggled off.
function Addon:QueueCombatAction(slot, action)
    Addon._combatQueue = Addon._combatQueue or {}
    if sameAction(Addon._combatQueue[slot], action) then
        Addon._combatQueue[slot] = nil
        if Addon.SetPendingSlot then Addon:SetPendingSlot(slot, nil) end  -- clear overlay
        return false
    end
    Addon._combatQueue[slot] = action
    Addon:EnsureRegenWatcher()
    return true
end

function Addon:DeferToCombatEnd(name)
    Addon._pendingSet = name
    if Addon.MarkSetPending then Addon:MarkSetPending(name) end
    Addon:EnsureRegenWatcher()
end

-- ── Equip a specific inventory item into a slot (used by flyout / sidebar) ─────
function Addon:EquipContainerItemToSlot(bag, slot, invSlot)
    if not (bag and slot) then return end
    local link = GetContainerItemLink(bag, slot)
    if InCombatLockdown() then
        if link and invSlot then
            local id = tonumber(link:match("item:(%d+)"))
            local queued = Addon:QueueCombatAction(invSlot, { type = "equip", link = link, id = id })
            if queued then
                Addon:ChatMsg("in combat — will equip " .. link .. " when combat ends.")
                if Addon.SetPendingSlot then Addon:SetPendingSlot(invSlot, select(5, GetItemInfoInstant(link))) end
            else
                Addon:ChatMsg("un-queued " .. link .. ".")
            end
        end
        return
    end
    ClearCursor()
    PickupContainerItem(bag, slot)
    if invSlot then
        PickupInventoryItem(invSlot)
    else
        AutoEquipCursorItem()
    end
    ClearCursor()
    if Addon.RefreshOptions then Addon:RefreshOptions() end
end

-- Take off the item currently in an equipment slot (into a free bag slot).
function Addon:UnequipSlot(invSlot)
    local link = GetInventoryItemLink("player", invSlot)
    if not link then return end
    if InCombatLockdown() then
        local queued = Addon:QueueCombatAction(invSlot, { type = "unequip" })
        if queued then
            Addon:ChatMsg("in combat — will unequip " .. link .. " when combat ends.")
            if Addon.SetPendingSlot then Addon:SetPendingSlot(invSlot, "Interface\\Buttons\\UI-GroupLoot-Pass-Up") end
        else
            Addon:ChatMsg("un-queued unequip.")
        end
        return
    end
    local bag, slot = Addon:FindFreeBagSlot()
    if not bag then
        print(Addon:Tag() .. " no free bag space to unequip.")
        return
    end
    ClearCursor()
    PickupInventoryItem(invSlot)
    PickupContainerItem(bag, slot)
    ClearCursor()
    if Addon.RefreshOptions then Addon:RefreshOptions() end
end

-- Items in bags that can go into a given inventory slot. When includeEquipped is
-- true (the set builder), currently-worn gear is listed first too; the character
-- pane and slot popouts pass false so already-equipped items aren't offered.
function Addon:GetInventoryItemsForSlot(slotId, includeEquipped)
    local valid = Addon.SLOT_INVTYPES[slotId]
    if not valid then return {} end
    local out = {}
    if includeEquipped then
        for _, eqSlot in ipairs(Addon.SLOT_IDS) do
            local link = GetInventoryItemLink("player", eqSlot)
            if link then
                local equipLoc = select(4, GetItemInfoInstant(link))
                if equipLoc and valid[equipLoc] then
                    out[#out + 1] = {
                        equipped = true, invSlot = eqSlot, link = link,
                        id = tonumber(link:match("item:(%d+)")),
                    }
                end
            end
        end
    end
    -- bag items
    for bag = 0, 4 do
        local num = GetContainerNumSlots(bag) or 0
        for slot = 1, num do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local equipLoc = select(4, GetItemInfoInstant(link))
                if equipLoc and valid[equipLoc] then
                    out[#out + 1] = {
                        bag = bag, slot = slot, link = link,
                        id = tonumber(link:match("item:(%d+)")),
                    }
                end
            end
        end
    end
    return out
end

-- Move an already-equipped item from one slot to another (e.g. swap rings).
function Addon:SwapEquippedSlots(fromSlot, toSlot)
    if not fromSlot or fromSlot == toSlot then return end
    if not GetInventoryItemLink("player", fromSlot) then return end
    if InCombatLockdown() then
        local queued = Addon:QueueCombatAction(toSlot, { type = "swap", from = fromSlot })
        if queued then
            Addon:ChatMsg("in combat — will move that item when combat ends.")
            if Addon.SetPendingSlot then Addon:SetPendingSlot(toSlot, GetInventoryItemTexture("player", fromSlot)) end
        else
            Addon:ChatMsg("un-queued.")
        end
        return
    end
    ClearCursor()
    PickupInventoryItem(fromSlot)
    PickupInventoryItem(toSlot)
    ClearCursor()
    if Addon.RefreshOptions then Addon:RefreshOptions() end
end

-- ── Public API ────────────────────────────────────────────────────────────────
function Addon:EquipSet(name)
    local set = Addon.db.sets[name]
    if not set then
        print(Addon:Tag() .. " set '" .. tostring(name) .. "' doesn't exist.")
        return
    end
    if InCombatLockdown() then
        Addon:DeferToCombatEnd(name)
        Addon:ChatMsg("in combat — '" .. name .. "' will equip when combat ends.")
        return
    end
    Addon:RunEquip(name)
end

function Addon:IsSetEquipped(name)
    local set = Addon.db.sets[name]
    if not set then return false end
    local any = false
    for _, slotId in ipairs(Addon.SLOT_IDS) do
        if Addon:IsSlotActive(set, slotId) then
            any = true
            if not Addon:SlotMatches(slotId, set.equip[slotId]) then return false end
        end
    end
    return any
end

-- Without snapshotting prior gear we don't restore on toggle; this re-equips.
function Addon:ToggleSet(name)
    Addon:EquipSet(name)
end

function Addon:GetEquipMacro(name)
    return '/run ArmEquip("' .. (name or "") .. '")'
end

-- ── Globals for macros — unique to Armory (no clash with ItemRack's EquipSet) ──
function ArmEquip(name)  return DaseekiArmory:EquipSet(name)  end
function ArmToggle(name) return DaseekiArmory:ToggleSet(name) end
ArmoryEquipSet  = ArmEquip
ArmoryToggleSet = ArmToggle
