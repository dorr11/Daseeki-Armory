--[[
    Daseeki Armory — set storage: item identity, CRUD, save-current-gear, and the
    export/import string used to clone all sets to another character.

    A stored slot "entry" is:  { id = <base itemID>, str = <itemString>, exact = <exact key> }
      - id    : base item id (loose matching, e.g. two copies of the same base item)
      - str   : the itemString after "item:" (e.g. "12345:0:0:0:0:0:1234:...")
      - exact : "<id>:<enchant>:<suffix>" — ItemRack-style exact identity, so an
                enchanted/suffixed item is distinguished from a plain one.
--]]

local _, Addon = ...

local EXPORT_VERSION = "v3"

-- ── Item identity ─────────────────────────────────────────────────────────────
function Addon:ItemString(link)
    if type(link) == "number" then link = "item:" .. link end
    return link and link:match("item:([%-%d:]+)") or nil
end

-- nth colon-separated field of an itemString ("" when missing)
local function field(str, n)
    local i = 0
    for v in (str .. ":"):gmatch("([%-%d]*):") do
        i = i + 1
        if i == n then return v end
    end
    return ""
end

-- Exact identity ignoring volatile fields (player level / uniqueId): id + enchant + suffix.
function Addon:ExactKey(itemString)
    if not itemString then return nil end
    local id      = field(itemString, 1); if id      == "" then id      = "0" end
    local enchant = field(itemString, 2); if enchant == "" then enchant = "0" end
    local suffix  = field(itemString, 7); if suffix  == "" then suffix  = "0" end
    return id .. ":" .. enchant .. ":" .. suffix
end

function Addon:IdentityFromLink(link)
    local str = Addon:ItemString(link)
    if not str then return nil end
    return { id = tonumber(field(str, 1)) or 0, str = str, exact = Addon:ExactKey(str) }
end

-- Rebuild a usable item string/link for tooltips, textures, GetItemInfo.
function Addon:EntryLink(entry)
    if not entry then return nil end
    if entry.str then return "item:" .. entry.str end
    if entry.id and entry.id > 0 then return "item:" .. entry.id end
    return nil
end

function Addon:EntryTexture(entry)
    local link = Addon:EntryLink(entry)
    if link then
        local tex = select(10, GetItemInfo(link))
        if tex then return tex end
    end
    if entry and entry.id and entry.id > 0 then
        local tex = select(10, GetItemInfo(entry.id))
        if tex then return tex end
        local _, _, _, _, icon = GetItemInfoInstant(entry.id)  -- synchronous fallback
        if icon then return icon end
    end
    return nil
end

-- ── Set lookup / ordering ─────────────────────────────────────────────────────
function Addon:GetSet(name)
    return name and Addon.db.sets[name] or nil
end

function Addon:NextOrder()
    local m = 0
    for _, s in pairs(Addon.db.sets) do
        if (s.order or 0) > m then m = s.order end
    end
    return m + 1
end

function Addon:GetSetsSorted()
    local list = {}
    for _, s in pairs(Addon.db.sets) do list[#list + 1] = s end
    table.sort(list, function(a, b)
        if (a.order or 0) == (b.order or 0) then return (a.name or "") < (b.name or "") end
        return (a.order or 0) < (b.order or 0)
    end)
    return list
end

-- Move `name` to the position currently held by `targetName`, renumbering order.
function Addon:ReorderSet(name, targetName)
    if not name or name == targetName then return end
    if not Addon.db.sets[name] then return end
    local names = {}
    for _, s in ipairs(Addon:GetSetsSorted()) do
        if s.name ~= name then names[#names + 1] = s.name end
    end
    local at = #names + 1
    for i, n in ipairs(names) do if n == targetName then at = i; break end end
    table.insert(names, at, name)
    for i, n in ipairs(names) do Addon.db.sets[n].order = i end
end

-- ── CRUD ──────────────────────────────────────────────────────────────────────
function Addon:CreateSet(name)
    name = strtrim(name or "")
    if name == "" then return false, "Name cannot be empty" end
    if Addon.db.sets[name] then return false, "A set with that name already exists" end
    Addon.db.sets[name] = {
        name     = name,
        icon     = Addon.DEFAULT_ICON,
        order    = Addon:NextOrder(),
        equip    = {},
        disabled = { [4] = true, [19] = true },  -- shirt + tabard ignored by default
    }
    return true, name
end

-- ── Disabled (ignored) slots ──────────────────────────────────────────────────
function Addon:IsSlotDisabled(name, slotId)
    local set = Addon.db.sets[name]
    return set and set.disabled and set.disabled[slotId] or false
end

function Addon:ToggleSlotDisabled(name, slotId)
    local set = Addon.db.sets[name]
    if not set then return false end
    set.disabled = set.disabled or {}
    if set.disabled[slotId] then
        set.disabled[slotId] = nil
    else
        set.disabled[slotId] = true
    end
    return true, set.disabled[slotId] and true or false
end

function Addon:DeleteSet(name)
    if not Addon.db.sets[name] then return false, "Set not found" end
    Addon.db.sets[name] = nil
    if Addon.db.currentSet == name then Addon.db.currentSet = nil end
    if Addon.ApplySetBindings then Addon:ApplySetBindings() end
    return true
end

function Addon:RenameSet(oldName, newName)
    newName = strtrim(newName or "")
    if not Addon.db.sets[oldName] then return false, "Set not found" end
    if newName == "" then return false, "Name cannot be empty" end
    if newName == oldName then return true, oldName end
    if Addon.db.sets[newName] then return false, "A set with that name already exists" end
    local set = Addon.db.sets[oldName]
    set.name = newName
    Addon.db.sets[newName] = set
    Addon.db.sets[oldName] = nil
    if Addon.db.currentSet == oldName then Addon.db.currentSet = newName end
    if Addon.ApplySetBindings then Addon:ApplySetBindings() end
    return true, newName
end

function Addon:DuplicateSet(name, newName)
    local src = Addon.db.sets[name]
    if not src then return false, "Set not found" end
    if not newName or strtrim(newName) == "" then
        newName = name .. " Copy"
        local n = 2
        while Addon.db.sets[newName] do newName = name .. " Copy " .. n; n = n + 1 end
    end
    newName = strtrim(newName)
    if Addon.db.sets[newName] then return false, "A set with that name already exists" end
    local copy = Addon:DeepCopy(src)
    copy.name  = newName
    copy.order = Addon:NextOrder()
    Addon.db.sets[newName] = copy
    return true, newName
end

function Addon:SetIcon(name, icon)
    local set = Addon.db.sets[name]
    if not set then return false end
    set.icon = icon
    return true
end

-- ── Slot editing ──────────────────────────────────────────────────────────────
function Addon:SaveCurrentGear(name)
    local set = Addon.db.sets[name]
    if not set then return false, "Set not found" end
    wipe(set.equip)
    for _, slotId in ipairs(Addon.SLOT_IDS) do
        if not (set.disabled and set.disabled[slotId]) then
            local link = GetInventoryItemLink("player", slotId)
            if link then
                local e = Addon:IdentityFromLink(link)
                if e then set.equip[slotId] = e end
            end
        end
    end
    return true
end

function Addon:SetSlotFromLink(name, slotId, link)
    local set = Addon.db.sets[name]
    if not set then return false end
    local e = Addon:IdentityFromLink(link)
    if not e then return false end
    set.equip[slotId] = e
    return true
end

function Addon:CaptureSlot(name, slotId)
    local link = GetInventoryItemLink("player", slotId)
    if not link then return false, "Nothing equipped in that slot" end
    return Addon:SetSlotFromLink(name, slotId, link)
end

function Addon:ClearSlot(name, slotId)
    local set = Addon.db.sets[name]
    if not set then return false end
    set.equip[slotId] = nil
    return true
end

-- ── Export / Import (clone all sets to another character) ─────────────────────
-- Single-line, "~~"-separated records / ";"-separated fields. Deliberately avoids
-- BOTH whitespace (newlines/tabs can get collapsed going through the OS clipboard
-- between two separate game client windows) AND "|" (WoW's inline text-formatting
-- escape prefix — "|c", "|H", "|T", "|r" etc. — a bare "|" followed by ordinary
-- text like "|HEAL" gets misread by the client's escape parser as the start of a
-- hyperlink and silently swallows everything up to the next "|h", destroying real
-- delimiters and data well past the first field). ";" and "~" have no special
-- meaning to WoW's text engine, so they survive the EditBox round-trip intact.
function Addon:ExportSets()
    local recs = { "DaseekiArmory:" .. EXPORT_VERSION }
    for _, set in ipairs(Addon:GetSetsSorted()) do
        recs[#recs + 1] = table.concat({ "SET", set.name, tostring(set.icon or "") }, ";")
        for _, slotId in ipairs(Addon.SLOT_IDS) do
            local e = set.equip[slotId]
            if e then
                recs[#recs + 1] = table.concat(
                    { "S", slotId, e.id or 0, e.exact or "", e.str or "" }, ";")
            end
        end
        if set.disabled then
            local off = {}
            for slotId in pairs(set.disabled) do off[#off + 1] = slotId end
            if #off > 0 then
                table.sort(off)
                recs[#recs + 1] = "D;" .. table.concat(off, ",")
            end
        end
    end
    return table.concat(recs, "~~")
end

function Addon:ImportSets(str)
    if not str or strtrim(str) == "" then return false, "Nothing to import" end
    -- tolerate a stray real newline surviving the paste by treating it as a record break too
    str = str:gsub("[\r\n]+", "~~")
    local lines = {}
    for rec in (str .. "~~"):gmatch("(.-)~~") do
        if rec ~= "" then lines[#lines + 1] = rec end
    end
    if not lines[1] or not lines[1]:match("^DaseekiArmory:") then
        return false, "Invalid format (expected a DaseekiArmory export string)"
    end

    local count, cur = 0, nil
    for i = 2, #lines do
        local parts = {}
        for p in (lines[i] .. ";"):gmatch("([^;]*);") do parts[#parts + 1] = p end
        if parts[1] == "SET" then
            local name = strtrim(parts[2] or "")
            if name == "" then name = "Imported Set" end
            local final, n = name, 2
            while Addon.db.sets[final] do final = name .. " (" .. n .. ")"; n = n + 1 end
            local icon = parts[3]
            if icon == "" then icon = nil elseif tonumber(icon) then icon = tonumber(icon) end
            cur = { name = final, icon = icon or Addon.DEFAULT_ICON, order = Addon:NextOrder(), equip = {}, disabled = {} }
            Addon.db.sets[final] = cur
            count = count + 1
        elseif parts[1] == "S" and cur then
            local slotId = tonumber(parts[2])
            if slotId then
                cur.equip[slotId] = {
                    id    = tonumber(parts[3]) or 0,
                    exact = (parts[4] ~= "" and parts[4]) or nil,
                    str   = (parts[5] ~= "" and parts[5]) or nil,
                }
            end
        elseif parts[1] == "D" and cur then
            for s in (parts[2] or ""):gmatch("(%d+)") do
                cur.disabled[tonumber(s)] = true
            end
        end
    end
    return true, count
end

-- ── Import directly from ItemRack (live, via its global ItemRackUser table) ────
-- ItemRack stores per-character sets in ItemRackUser.Sets[name] = { equip = { [slot]=itemString },
-- icon = fileID }. Slots are standard inventory ids (1..19, 0=ammo) — a 1:1 match to Armory.
-- Same-named Armory sets are overwritten. Returns true,count or false,error.
function Addon:ItemRackAvailable()
    local ir = _G.ItemRackUser
    return ir and type(ir.Sets) == "table" and ir or nil
end

function Addon:CountItemRackSets()
    local ir = Addon:ItemRackAvailable()
    if not ir then return 0 end
    local n = 0
    for name in pairs(ir.Sets) do
        if type(name) == "string" and name:sub(1, 1) ~= "~" then n = n + 1 end
    end
    return n
end

function Addon:ImportFromItemRack()
    local ir = Addon:ItemRackAvailable()
    if not ir then return false, "ItemRack data not found — make sure ItemRack is enabled." end

    local count = 0
    for name, irset in pairs(ir.Sets) do
        if type(name) == "string" and name:sub(1, 1) ~= "~"
           and type(irset) == "table" and type(irset.equip) == "table" then
            local set = {
                name     = name,
                icon     = irset.icon or Addon.DEFAULT_ICON,
                order    = tonumber(name:match("^(%d+)")) or Addon:NextOrder(),
                equip    = {},
                disabled = {},
            }
            for slot = 1, 19 do
                local s = irset.equip[slot]
                if type(s) == "string" and s ~= "" and s ~= "0" then
                    local id = tonumber(s:match("^(%-?%d+)"))
                    if id and id > 0 then
                        set.equip[slot] = { id = id, str = s, exact = Addon:ExactKey(s) }
                    end
                end
            end
            if not set.equip[4]  then set.disabled[4]  = true end  -- shirt
            if not set.equip[19] then set.disabled[19] = true end  -- tabard
            Addon.db.sets[name] = set
            count = count + 1
        end
    end

    if ir.CurrentSet and Addon.db.sets[ir.CurrentSet] then
        Addon.db.currentSet = ir.CurrentSet
    end
    return true, count
end

-- ── Chase-list goals ──────────────────────────────────────────────────────────
-- set.goals[slotId]   = { id, str, exact }  — target item the player is chasing
-- set.goalMet[slotId] = true                — sticky "obtained" flag

function Addon:GetGoal(set, slotId)
    return set and set.goals and set.goals[slotId] or nil
end

-- Met when explicitly obtained, or the set's current item already IS the goal item.
function Addon:IsGoalMet(set, slotId)
    if not (set and set.goals and set.goals[slotId]) then return false end
    if set.goalMet and set.goalMet[slotId] then return true end
    local cur = set.equip and set.equip[slotId]
    return cur ~= nil and cur.id == set.goals[slotId].id
end

function Addon:SetGoal(name, slotId, itemId)
    local set = Addon.db.sets[name]
    if not set or not itemId then return false end
    set.goals = set.goals or {}
    set.goalMet = set.goalMet or {}
    set.goals[slotId] = Addon:IdentityFromLink("item:" .. itemId)
    set.goalMet[slotId] = nil  -- new goal → not yet obtained
    return true
end

function Addon:ClearGoal(name, slotId)
    local set = Addon.db.sets[name]
    if not set then return false end
    if set.goals then set.goals[slotId] = nil end
    if set.goalMet then set.goalMet[slotId] = nil end
    return true
end

-- Scan bags for any unmet goal's base item; on a hit, fill the set slot with the
-- real bag item (carrying its enchant) and mark the goal obtained. Returns true if
-- anything changed. Idempotent — safe to call on every BAG_UPDATE_DELAYED.
function Addon:CheckGoals()
    local CN = (C_Container and C_Container.GetContainerNumSlots) or _G.GetContainerNumSlots
    local CL = (C_Container and C_Container.GetContainerItemLink)  or _G.GetContainerItemLink
    local changed = false
    for _, set in pairs(Addon.db.sets or {}) do
        if set.goals then
            for slotId, goal in pairs(set.goals) do
                if goal and not (set.goalMet and set.goalMet[slotId])
                   and not (set.equip[slotId] and set.equip[slotId].id == goal.id) then
                    -- look for the goal's base item in the player's bags
                    local found
                    for bag = 0, 4 do
                        local num = CN(bag) or 0
                        for slot = 1, num do
                            local link = CL(bag, slot)
                            if link and tonumber(link:match("item:(%d+)")) == goal.id then
                                found = link; break
                            end
                        end
                        if found then break end
                    end
                    if found then
                        set.equip[slotId] = Addon:IdentityFromLink(found)
                        if set.disabled then set.disabled[slotId] = nil end
                        set.goalMet = set.goalMet or {}
                        set.goalMet[slotId] = true
                        changed = true
                    end
                end
            end
        end
    end
    if changed then
        if Addon.RefreshOptions then Addon:RefreshOptions() end
        if Addon.RefreshWidget  then Addon:RefreshWidget()  end
    end
    return changed
end

-- BAG_UPDATE_DELAYED watcher (also run once at login from core.lua).
function Addon:InitGoals()
    if Addon._goalEv then return end
    Addon._goalEv = CreateFrame("Frame")
    Addon._goalEv:RegisterEvent("BAG_UPDATE_DELAYED")
    Addon._goalEv:SetScript("OnEvent", function() Addon:CheckGoals() end)
    Addon:CheckGoals()
end
