--[[
    Daseeki Armory — icon database for the set icon picker.

    The full browsable grid is harvested at login from the client itself via
    GetMacroIcons / GetMacroItemIcons (every icon the client knows). Depending on
    the build these come back as texture-name strings (searchable by name) or as
    numeric fileIDs (renderable, searchable by id). To guarantee keyword search
    works regardless, we also seed a list of well-known icon names below.

    Armory.IconList  = { { tex = <path|fileID>, name = <lowercased name|nil>, id = <fileID|nil> }, ... }
    Armory:SearchIcons(query) -> filtered array (matches name substring, or fileID
        when the query is numeric). Empty query returns the whole list.
--]]

local _, Addon = ...

-- Seed of common Classic icon names (rendered via "Interface\\Icons\\<name>").
-- Not exhaustive — the client harvest below fills in the rest of the grid; this
-- list just guarantees these are findable by typing part of the name.
Addon.SeedIconNames = {
    -- weapons
    "INV_Sword_04","INV_Sword_27","INV_Sword_39","INV_Sword_48","INV_Axe_09","INV_Axe_17",
    "INV_Mace_01","INV_Mace_13","INV_Hammer_16","INV_Spear_05","INV_Staff_13","INV_Staff_30",
    "INV_Weapon_Bow_07","INV_Weapon_Rifle_06","INV_Weapon_Crossbow_04","INV_ThrowingAxe_03",
    "INV_Misc_Wand_05","Ability_DualWield","Ability_MeleeDamage","INV_Shield_06","INV_Shield_22",
    -- armor
    "INV_Helmet_03","INV_Helmet_24","INV_Chest_Plate06","INV_Chest_Cloth_17","INV_Shoulder_02",
    "INV_Pants_Plate_17","INV_Boots_Plate_03","INV_Bracer_07","INV_Gauntlets_25","INV_Belt_15",
    "INV_Misc_Cape_18","INV_Jewelry_Ring_03","INV_Jewelry_Necklace_07","INV_Misc_Cape_20",
    "INV_Shirt_01","INV_Shirt_GuildTabard_01","INV_Boots_Cloth_05","INV_Gauntlets_04",
    -- class / role
    "ClassIcon_Warrior","ClassIcon_Paladin","ClassIcon_Hunter","ClassIcon_Rogue","ClassIcon_Priest",
    "ClassIcon_Shaman","ClassIcon_Mage","ClassIcon_Warlock","ClassIcon_Druid",
    "Spell_Holy_PowerWordShield","Spell_Nature_Lightning","Spell_Fire_FireBolt02","Spell_Frost_FrostBolt02",
    "Spell_Shadow_ShadowBolt","Spell_Nature_HealingTouch","Ability_Rogue_Eviscerate","Ability_Warrior_Charge",
    "Ability_Hunter_RunningShot","Spell_Holy_GreaterHeal","Spell_Arcane_Blink","Ability_Stealth",
    "Ability_Defend","Ability_Warrior_OffensiveStance","Ability_Warrior_DefensiveStance",
    -- pvp / generic
    "Achievement_PVP_A_A","Achievement_PVP_H_H","INV_BannerPVP_02","INV_BannerPVP_03",
    "INV_Misc_Bag_08","INV_Misc_Bag_10_Blue","INV_Misc_Gear_01","INV_Misc_Gear_02",
    "INV_Misc_Note_01","INV_Misc_Book_09","INV_Misc_QuestionMark","Trade_Engineering",
    "Trade_Alchemy","Trade_BlackSmithing","Trade_LeatherWorking","Trade_Tailoring","Trade_Mining",
    "INV_Potion_54","INV_Potion_76","INV_Drink_07","INV_Food_34","INV_Misc_Food_15",
    "Spell_Holy_SealOfMight","Spell_Nature_Reincarnation","Spell_Shadow_DeathPact",
    "INV_Misc_Coin_01","INV_Misc_Rune_01","INV_Enchant_EssenceEternalLarge",
}

local function lower(s) return s and s:lower() or nil end

-- Generated name ranges so category searches (sword/axe/shield/helmet…) return
-- results even though the client's harvested icons come back as nameless fileIDs.
-- A few numbers in a range may not exist (they render as a default tile); that's
-- an accepted trade-off for keyword coverage.
local GENERATED = {
    INV_Sword_ = 50, INV_Axe_ = 30, INV_Mace_ = 30, INV_Hammer_ = 25,
    INV_Staff_ = 30, INV_Spear_ = 16, INV_Shield_ = 40,
    INV_Helmet_ = 70, INV_Gauntlets_ = 40, INV_Shoulder_ = 40, INV_Belt_ = 40,
    INV_Boots_Plate_ = 9, INV_Bracer_ = 20, INV_Misc_Cape_ = 20,
    INV_Jewelry_Ring_ = 60, INV_Jewelry_Necklace_ = 40,
    INV_Weapon_Bow_ = 16, INV_Weapon_Rifle_ = 10, INV_Weapon_Crossbow_ = 12,
    INV_Misc_Wand_ = 15, INV_ThrowingAxe_ = 6, INV_ThrowingKnife_ = 6,
}

function Addon:BuildIconList()
    if Addon.IconList then return Addon.IconList end
    local list, seen = {}, {}
    Addon._iconNameSeen = {}

    local function add(tex, name, id)
        local key = tostring(tex)
        if seen[key] then return end
        seen[key] = true
        if name then Addon._iconNameSeen[name:lower()] = true end
        list[#list + 1] = { tex = tex, name = lower(name), id = id }
    end

    -- seeded named icons first (guaranteed name search)
    for _, n in ipairs(Addon.SeedIconNames) do
        add("Interface\\Icons\\" .. n, n)
    end
    -- generated category ranges
    for prefix, count in pairs(GENERATED) do
        for i = 1, count do
            local n = prefix .. string.format("%02d", i)
            add("Interface\\Icons\\" .. n, n)
        end
    end

    -- full client icon set
    local function harvest(getter)
        if type(getter) ~= "function" then return end
        local t = {}
        local ok = pcall(getter, t)
        if not ok or #t == 0 then
            local ok2, ret = pcall(getter)
            if ok2 and type(ret) == "table" then t = ret end
        end
        for _, v in ipairs(t) do
            if type(v) == "number" then
                add(v, nil, v)
            elseif type(v) == "string" and v ~= "" then
                local nm = v:match("([^\\]+)$") or v
                add("Interface\\Icons\\" .. nm, nm)
            end
        end
    end
    harvest(_G.GetMacroIcons)
    harvest(_G.GetMacroItemIcons)

    Addon.IconList = list
    return list
end

-- ── Item-name → icon search index ─────────────────────────────────────────────
-- So typing an item's name (e.g. "Gressil") returns its icon. Built once from the
-- bundled ItemNameDB (AtlasLoot-derived ~4.7k items); icons come from
-- GetItemInfoInstant — synchronous and offline for any item the client knows.
function Addon:BuildItemSearch()
    if Addon._itemSearchBuilt then return Addon.ItemSearch end
    Addon._itemSearchBuilt = true
    Addon:BuildIconList()
    Addon._iconNameSeen = Addon._iconNameSeen or {}
    Addon.ItemSearch = Addon.ItemSearch or {}
    if Addon.ItemNameDB then
        for id, nm in pairs(Addon.ItemNameDB) do
            local key = nm:lower()
            if not Addon._iconNameSeen[key] then
                local _, _, _, _, icon = GetItemInfoInstant(id)
                if icon then
                    Addon._iconNameSeen[key] = true
                    Addon.ItemSearch[#Addon.ItemSearch + 1] = { tex = icon, name = key, id = icon, isItem = true }
                end
            end
        end
    end
    return Addon.ItemSearch
end

-- Add a single seen item (e.g. shift-clicked / dragged) that may not be in the DB.
function Addon:IndexItemIcon(itemLinkOrId)
    if not itemLinkOrId then return false end
    local name, _, _, _, _, _, _, _, _, tex = GetItemInfo(itemLinkOrId)
    if not name or not tex then return false end
    local key = name:lower()
    Addon._iconNameSeen = Addon._iconNameSeen or {}
    if Addon._iconNameSeen[key] then return true end
    Addon._iconNameSeen[key] = true
    Addon.ItemSearch = Addon.ItemSearch or {}
    Addon.ItemSearch[#Addon.ItemSearch + 1] = { tex = tex, name = key, id = (type(tex) == "number" and tex or nil), isItem = true }
    return true
end

-- Index the player's own spellbook by name. Class-ability icons that come back from
-- the client harvest as nameless fileIDs (see harvest() above) are otherwise only
-- searchable by numeric ID — typing e.g. "Recklessness" would never match its icon.
-- The player's known spells are guaranteed to be name-resolvable, so seed those.
function Addon:IndexSpellbook()
    if Addon._spellbookIndexed then return end
    Addon._spellbookIndexed = true
    if not (GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName and GetSpellBookItemTexture) then return end
    Addon._iconNameSeen = Addon._iconNameSeen or {}
    Addon.ItemSearch = Addon.ItemSearch or {}
    local book = BOOKTYPE_SPELL or "spell"
    for tab = 1, GetNumSpellTabs() do
        local _, _, offset, numSpells = GetSpellTabInfo(tab)
        for i = (offset or 0) + 1, (offset or 0) + (numSpells or 0) do
            local name = GetSpellBookItemName(i, book)
            local tex = GetSpellBookItemTexture(i, book)
            if name and tex then
                local key = name:lower()
                if not Addon._iconNameSeen[key] then
                    Addon._iconNameSeen[key] = true
                    Addon.ItemSearch[#Addon.ItemSearch + 1] = { tex = tex, name = key, isSpell = true }
                end
            end
        end
    end
end

function Addon:IndexOwnedItems()
    Addon:BuildIconList()
    Addon.ItemSearch = Addon.ItemSearch or {}
    local CN = C_Container and C_Container.GetContainerNumSlots or _G.GetContainerNumSlots
    local CL = C_Container and C_Container.GetContainerItemLink or _G.GetContainerItemLink
    for _, slotId in ipairs(Addon.SLOT_IDS) do
        local link = GetInventoryItemLink("player", slotId)
        if link then Addon:IndexItemIcon(link) end
    end
    for bag = 0, 4 do
        local num = CN(bag) or 0
        for slot = 1, num do
            local link = CL(bag, slot)
            if link then Addon:IndexItemIcon(link) end
        end
    end
    for _, set in pairs(Addon.db and Addon.db.sets or {}) do
        for _, e in pairs(set.equip or {}) do
            local l = Addon:EntryLink(e)
            if l then Addon:IndexItemIcon(l) end
        end
    end
end

function Addon:SearchIcons(query)
    local browse = Addon:BuildIconList()
    query = strtrim((query or "")):lower()
    if query == "" then return browse end

    local items   = Addon:BuildItemSearch()
    local num     = tonumber(query)
    local out, seen = {}, {}
    local function scan(listt)
        for _, e in ipairs(listt) do
            if (num and e.id == num) or (e.name and e.name:find(query, 1, true)) then
                local k = tostring(e.tex) .. "|" .. (e.name or "")
                if not seen[k] then
                    seen[k] = true
                    out[#out + 1] = e
                    if #out >= 600 then return true end
                end
            end
        end
    end
    if scan(browse) then return out end
    scan(items)
    return out
end
