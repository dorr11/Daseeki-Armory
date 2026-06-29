--[[
    Daseeki Armory — optional OPie ring integration.

    If OPie is installed, registers a "Daseeki Armory" ring listing every set for this
    character; clicking a slice equips it. This mirrors OPie's own built-in Equipment
    Sets ring (OPie/Meta/EQSet2.lua), which is disabled on Classic Era because Blizzard's
    Equipment Manager doesn't exist here — this fills that gap using Armory's own sets.
    No OPie files are modified; this addon never loads if OPie isn't present.
--]]

local _, Addon = ...

local OPie = _G.OPie
if not (OPie and OPie.ActionBook and OPie.UI) then return end
local AB = OPie.ActionBook:compatible(2, 14)
if not AB then return end

-- exists, state(0/1 = currently equipped), icon, label, r,g,b
local function hint(name)
    local set = Addon.db.sets[name]
    if not set then return false end
    local active = Addon.IsSetEquipped and Addon:IsSetEquipped(name)
    return true, active and 1 or 0, set.icon or Addon.DEFAULT_ICON, set.name, 0, 0, 0
end

local function equipSet(name)
    Addon:EquipSet(name)
end

-- lazy per-set action id cache, keyed by set name (stale entries for renamed/deleted
-- sets are harmless and just go unused, same as OPie's own Tracking.lua does)
local actionsByName = setmetatable({}, { __index = function(t, name)
    local id = AB:CreateActionSlot(hint, name, "func", equipSet, name)
    t[name] = id
    return id
end })

local collectionData = {}
local col = AB:CreateActionSlot(nil, nil, "collection", collectionData)

local function syncRing(selfId, _, updatedId)
    if selfId ~= updatedId then return end
    wipe(collectionData)
    local sets = Addon:GetSetsSorted()
    for i, set in ipairs(sets) do
        local token = "DAo" .. i
        collectionData[i], collectionData[token] = token, actionsByName[set.name]
        -- per-slice short label (shown on the icon itself, like OPie's own Tracking ring)
        OPie.UI:SetDisplayOptions(token, nil, set.name)
    end
    AB:UpdateActionSlot(col, collectionData)
end

OPie:SetRing("DaseekiArmory", col, { name = "Daseeki Armory" })
AB:AddObserver("internal.collection.preopen", syncRing, col)
