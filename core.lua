--[[
    Daseeki Armory — core: addon table, SavedVariables, slot model, login flow.

    A per-character equipment-set manager modeled on ItemRack's "Sets" feature,
    built to plug into the shared Daseeki-Core hub (global DaseekiSuite). Sets are
    stored per character (## SavedVariablesPerCharacter: DaseekiArmoryDB).

    Global table: DaseekiArmory  (also _G['Daseeki-Armory'])
--]]

local ADDON, Addon = ...
DaseekiArmory      = Addon
_G['Daseeki-Armory'] = Addon

-- ── Equipment slot model ──────────────────────────────────────────────────────
-- id = inventory slot id (GetInventorySlotInfo order); laid out for the paper-doll
-- builder (left column, right column, then weapons across the bottom).
Addon.SLOTS = {
    { id = 1,  name = "Head",      col = "L", slotName = "HeadSlot" },
    { id = 2,  name = "Neck",      col = "L", slotName = "NeckSlot" },
    { id = 3,  name = "Shoulder",  col = "L", slotName = "ShoulderSlot" },
    { id = 15, name = "Back",      col = "L", slotName = "BackSlot" },
    { id = 5,  name = "Chest",     col = "L", slotName = "ChestSlot" },
    { id = 4,  name = "Shirt",     col = "L", slotName = "ShirtSlot" },
    { id = 19, name = "Tabard",    col = "L", slotName = "TabardSlot" },
    { id = 9,  name = "Wrist",     col = "L", slotName = "WristSlot" },

    { id = 10, name = "Hands",     col = "R", slotName = "HandsSlot" },
    { id = 6,  name = "Waist",     col = "R", slotName = "WaistSlot" },
    { id = 7,  name = "Legs",      col = "R", slotName = "LegsSlot" },
    { id = 8,  name = "Feet",      col = "R", slotName = "FeetSlot" },
    { id = 11, name = "Finger 1",  col = "R", slotName = "Finger0Slot" },
    { id = 12, name = "Finger 2",  col = "R", slotName = "Finger1Slot" },
    { id = 13, name = "Trinket 1", col = "R", slotName = "Trinket0Slot" },
    { id = 14, name = "Trinket 2", col = "R", slotName = "Trinket1Slot" },

    { id = 16, name = "Main Hand", col = "W", slotName = "MainHandSlot" },
    { id = 17, name = "Off Hand",  col = "W", slotName = "SecondaryHandSlot" },
    { id = 18, name = "Ranged",    col = "W", slotName = "RangedSlot" },
}

-- Per-slot empty-slot artwork (Blizzard paper-doll background), resolved lazily.
function Addon:GetSlotEmptyTexture(slotDef)
    if slotDef._emptyTex == nil and slotDef.slotName then
        local _, tex = GetInventorySlotInfo(slotDef.slotName)
        slotDef._emptyTex = tex or false
    end
    return slotDef._emptyTex or Addon.EMPTY_ICON
end

-- Ordered list of just the slot ids (used by the equip engine / SaveCurrentGear).
Addon.SLOT_IDS = {}
for _, s in ipairs(Addon.SLOTS) do Addon.SLOT_IDS[#Addon.SLOT_IDS + 1] = s.id end

Addon.DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
Addon.EMPTY_ICON   = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"

-- ── SavedVariables defaults ───────────────────────────────────────────────────
local DEFAULT_DB = {
    sets        = {},    -- name -> { name, icon, order, equip = { [slotId] = entry } }
    currentSet  = nil,   -- last equipped set name (for widget highlight)
    settings    = {
        flyoutPerRow = 5,         -- icons per row in the inventory flyout before wrapping
        flyoutTooltip = "ctrl",   -- "ctrl" (show item tooltip only while Ctrl held) | "always"
        chatMessages  = false,    -- print combat-queue messages to chat
        widget = {
            show     = false,
            locked   = false,
            point    = "CENTER",
            relPoint = "CENTER",
            x        = 250,
            y        = 0,
            scale    = 1,
            radius   = 92,
            openTrigger    = "click",   -- "click" | "hover"
            mode           = "radial",  -- "radial" | "dropdown"
            dropdownType   = "icon",    -- "icon" | "list" (dropdown mode only)
            dropdownDir    = "right",   -- icon type: "right"|"left"|"up"|"down"
            dropdownPerRow = 5,         -- icon type: icons per row before wrapping
            dropdownAlwaysOpen = false, -- icon type: stay open permanently, no hover/click needed
        },
        slotPopouts = {        -- detached gear-slot buttons (alt+click a char slot)
            locked  = false,
            scale   = 1,
            buttons = {},  -- [slotId] = { point, relPoint, x, y, dir, perRow, anchor }
        },
    },
}

local function ApplyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            ApplyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function Addon:DeepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = type(v) == "table" and Addon:DeepCopy(v) or v
    end
    return copy
end

function Addon:GetCharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

function Addon:Init()
    DaseekiArmoryDB = DaseekiArmoryDB or {}
    ApplyDefaults(DaseekiArmoryDB, DEFAULT_DB)
    Addon.db = DaseekiArmoryDB
end

-- ── Login ─────────────────────────────────────────────────────────────────────
function Addon:OnLogin()
    if Addon.InitWidget    then Addon:InitWidget()    end
    if Addon.RegisterOptions then Addon:RegisterOptions() end
    if Addon.BuildIconList then Addon:BuildIconList() end
    if Addon.IndexOwnedItems then Addon:IndexOwnedItems() end
    if Addon.InitTooltip     then Addon:InitTooltip()     end
    if Addon.InitPaperdoll   then Addon:InitPaperdoll()   end
    if Addon.InitSlotPopouts then Addon:InitSlotPopouts() end
    if Addon.ApplySetBindings then Addon:ApplySetBindings() end
    if Addon.InitGoals then Addon:InitGoals() end
    if Addon.WarmGoalItems then C_Timer.After(5, function() Addon:WarmGoalItems() end) end

    -- Macro entry points, unique to Armory so they never collide with ItemRack's
    -- global EquipSet(). Use: /run ArmEquip("1 - DPS")
    ArmEquip  = function(name) return Addon:EquipSet(name)  end
    ArmToggle = function(name) return Addon:ToggleSet(name) end

    local n = 0
    for _ in pairs(Addon.db.sets) do n = n + 1 end
    print(string.format(
        "|cff66ccffDaseeki Armory|r loaded — %d set%s. |cffffffff/darmory|r for options.",
        n, n == 1 and "" or "s"))
end

-- ── Event wiring ──────────────────────────────────────────────────────────────
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == ADDON then
            Addon:Init()
            ev:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        if not Addon.db then Addon:Init() end
        Addon:OnLogin()
        ev:UnregisterEvent("PLAYER_LOGIN")
    end
end)
