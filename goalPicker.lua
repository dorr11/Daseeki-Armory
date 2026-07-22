--[[
    Daseeki Armory — goal item picker (search any item by name).

    A themed search list of items that fit a given slot, drawn from the bundled
    AtlasLoot-derived item DB (Addon.ItemNameDB). Icons/equip-locations come from
    GetItemInfoInstant (synchronous, offline). Shift-clicking an item link into the
    search box picks that item directly (covers items not in the DB).

    Addon:ShowGoalPicker(slotId, onPick)   -- onPick(itemId)
--]]

local _, Addon = ...

local ROWH, ROWS, W = 28, 12, 360
local LIST_TOP = 82
local picker

-- ── Class usability ───────────────────────────────────────────────────────────
-- Per-class weapon/armor proficiency by numeric subclass id (locale-safe). classID
-- 2 = Weapon, 4 = Armor. Weapon subclasses: 0 axe1h,1 axe2h,2 bow,3 gun,4 mace1h,
-- 5 mace2h,6 polearm,7 sword1h,8 sword2h,10 staff,13 fist,15 dagger,16 thrown,
-- 18 crossbow,19 wand. Armor subclasses: 0 misc,1 cloth,2 leather,3 mail,4 plate,
-- 6 shield,7 libram,8 idol,9 totem.
local function S(...) local t = {}; for _, v in ipairs({...}) do t[v] = true end; return t end
local PROF = {
    WARRIOR = { weapon = S(0,1,2,3,4,5,6,7,8,10,13,15,16,18), armor = S(0,1,2,3,4,6) },
    PALADIN = { weapon = S(0,1,4,5,6,7,8),                     armor = S(0,1,2,3,4,6,7) },
    HUNTER  = { weapon = S(0,1,2,3,6,7,8,10,13,15,18),         armor = S(0,1,2,3) },
    ROGUE   = { weapon = S(0,2,3,4,7,13,15,16,18),             armor = S(0,1,2) },
    PRIEST  = { weapon = S(4,10,15,19),                        armor = S(0,1) },
    SHAMAN  = { weapon = S(0,1,4,5,10,13,15),                  armor = S(0,1,2,3,6,9) },
    MAGE    = { weapon = S(7,10,15,19),                        armor = S(0,1) },
    WARLOCK = { weapon = S(7,10,15,19),                        armor = S(0,1) },
    DRUID   = { weapon = S(4,5,6,10,13,15),                    armor = S(0,1,2,8) },
}

local scanTip
local CLASS_PREFIX = ((ITEM_CLASSES_ALLOWED or "Classes: %s"):gsub("%%s.*$", ""))
local playerClass, playerClassLoc

-- Class token -> allowable-class bit (matches Addon.ItemClassMask in itemDB.lua).
local CLASS_BIT = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
                    SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024 }

-- True if the logged-in class can use this item (proficiency + explicit "Classes:"
-- restriction). Class-set pieces are filtered offline via the bundled mask; the
-- tooltip-scan fallback only bites once the item is cached.
function Addon:ItemUsableByClass(e)
    playerClass    = playerClass    or select(2, UnitClass("player"))
    playerClassLoc = playerClassLoc or UnitClass("player")
    local mask = Addon.ItemClassMask and Addon.ItemClassMask[e.id]
    if mask and CLASS_BIT[playerClass] and bit.band(mask, CLASS_BIT[playerClass]) == 0 then
        return false
    end
    local prof = PROF[playerClass]
    if prof and e.classID then
        if e.classID == 2 and not prof.weapon[e.subclassID] then return false end
        if e.classID == 4 and not prof.armor[e.subclassID]  then return false end
    end
    if e._classOK ~= nil then return e._classOK end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "DaseekiArmoryGoalScan", nil, "GameTooltipTemplate")
        scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    scanTip:ClearLines(); scanTip:SetItemByID(e.id)
    local n = scanTip:NumLines() or 0
    if n > 1 then
        for i = 2, n do
            local fs = _G["DaseekiArmoryGoalScanTextLeft" .. i]
            local txt = fs and fs:GetText()
            if txt and txt:find(CLASS_PREFIX, 1, true) == 1 then
                e._classOK = txt:find(playerClassLoc, 1, true) ~= nil
                return e._classOK
            end
        end
        e._classOK = true   -- tooltip loaded, no class restriction
    end
    return true             -- uncached: assume usable for now (re-checked on refresh)
end

-- Lazy item index: { id, name(lower), display, icon, equipLoc, classID, subclassID }
function Addon:BuildGoalItemDB()
    if Addon.GoalItemDB then return Addon.GoalItemDB end
    local list = {}
    if Addon.ItemNameDB then
        for id, nm in pairs(Addon.ItemNameDB) do
            local _, _, _, equipLoc, icon, classID, subclassID = GetItemInfoInstant(id)
            if icon and equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP" then
                list[#list + 1] = { id = id, name = nm:lower(), display = nm, icon = icon,
                                    equipLoc = equipLoc, classID = classID, subclassID = subclassID }
            end
        end
    end
    Addon.GoalItemDB = list
    return list
end

-- PvP rank items have no bundled name; resolve from the client at runtime.
function Addon:BuildGoalPvP()
    local out = {}
    for _, id in ipairs(Addon.PvPItemIDs or {}) do
        if not (Addon.ItemNameDB and Addon.ItemNameDB[id]) then
            local name = GetItemInfo(id)
            if name then
                local _, _, _, equipLoc, icon, classID, subclassID = GetItemInfoInstant(id)
                if icon and equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP" then
                    out[#out + 1] = { id = id, name = name:lower(), display = name, icon = icon,
                                      equipLoc = equipLoc, classID = classID, subclassID = subclassID }
                end
            end
        end
    end
    Addon.GoalPvP = out
    return out
end

-- item level for sorting (cached once resolved; 0 while the client hasn't cached it)
local function ilvlOf(e)
    if e._ilvl then return e._ilvl end
    local _, _, _, lvl = GetItemInfo(e.id)
    if lvl then e._ilvl = lvl; return lvl end
    return 0
end

local function filtered(query, validLoc)
    query = strtrim((query or "")):lower()
    local out, seen = {}, {}
    local function scan(listt)
        for _, e in ipairs(listt) do
            if not seen[e.id] and validLoc[e.equipLoc]
               and (query == "" or e.name:find(query, 1, true))
               and Addon:ItemUsableByClass(e) then
                seen[e.id] = true
                out[#out + 1] = e
                if #out >= 500 then return true end
            end
        end
    end
    if not scan(Addon:BuildGoalItemDB()) then scan(Addon:BuildGoalPvP()) end
    table.sort(out, function(a, b)
        local la, lb = ilvlOf(a), ilvlOf(b)
        if la ~= lb then return la > lb end   -- highest item level first
        return a.display < b.display
    end)
    return out
end

local function ensure()
    if picker then return picker end
    local DS = _G.DaseekiSuite

    local H = LIST_TOP + ROWS * ROWH + 16
    local f = CreateFrame("Frame", "DaseekiArmoryGoalPicker", UIParent, "BackdropTemplate")
    f:SetSize(W, H)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetPoint("CENTER")
    f:SetMovable(true); f:EnableMouse(true)
    f:SetScript("OnMouseDown", function(s, b) if b == "LeftButton" then s:StartMoving() end end)
    f:SetScript("OnMouseUp",   function(s) s:StopMovingOrSizing() end)
    f:SetScript("OnShow", function(s) if DS and DS.ApplySkin then DS.ApplySkin(s) end end)
    if DS and DS.ApplySkin then
        DS.ApplySkin(f)
    else
        f:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0, 0, 0, 0.92); f:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    end

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", f, "TOP", 0, -12); f.title:SetText("Choose Goal Item"); f.title:SetTextColor(1, 0.82, 0)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Hide() end)

    f.countText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.countText:SetPoint("BOTTOM", f, "BOTTOM", 0, 8); f.countText:SetTextColor(0.7, 0.7, 0.7)

    local search
    if DS and DS.MakeEditBox then search = DS.MakeEditBox(f, 14, 40, W - 28)
    else
        search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        search:SetSize(W - 28, 20); search:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -40)
        search:SetAutoFocus(false); search:SetFontObject(ChatFontNormal)
    end
    search:SetScript("OnTextChanged", function(self)
        -- shift-clicking an item link → pick it directly if it fits the slot
        local linkId = self:GetText():match("|Hitem:(%d+)")
        if linkId then
            local id = tonumber(linkId)
            local _, _, _, equipLoc = GetItemInfoInstant(id)
            self:SetText("")
            if picker._validLoc and equipLoc and picker._validLoc[equipLoc] then
                if picker._onPick then picker._onPick(id) end
                picker:Hide()
            else
                print("|cff66ccffArmory|r that item doesn't fit this slot.")
            end
            return
        end
        picker._list = filtered(self:GetText(), picker._validLoc or {})
        picker._offset = 0
        picker:RefreshList()
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus(); picker:Hide() end)
    f.search = search

    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -62)
    f.hint:SetText("Search by item name, or shift-click an item link here")

    f.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, f)
        r:SetSize(W - 28, ROWH)
        r:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -(LIST_TOP + (i - 1) * ROWH))
        r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
        r.bg:SetColorTexture(i % 2 == 0 and 0.12 or 0.08, 0.1, 0.12, 0.5)
        r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(22, 22); r.icon:SetPoint("LEFT", 2, 0)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        r.label = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        r.label:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.label:SetWidth(W - 60); r.label:SetJustifyH("LEFT")
        local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.25)
        r:SetScript("OnClick", function(self)
            if self._id and picker._onPick then picker._onPick(self._id) end
            picker:Hide()
        end)
        r:SetScript("OnEnter", function(self)
            if self._id then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(self._id); GameTooltip:Show() end
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.rows[i] = r
    end

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        local maxOff = math.max(0, #(picker._list or {}) - ROWS)
        picker._offset = math.min(maxOff, math.max(0, (picker._offset or 0) - delta))
        picker:RefreshList()
    end)

    -- as item names / levels stream in, rebuild PvP entries and re-sort the list
    f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    f:SetScript("OnEvent", function(self)
        if not self:IsShown() or self._refreshPending then return end
        self._refreshPending = true
        C_Timer.After(0.3, function()
            self._refreshPending = nil
            if self:IsShown() then
                Addon:BuildGoalPvP()
                self._list = filtered(self.search:GetText(), self._validLoc or {})
                self:RefreshList()
            end
        end)
    end)

    function f:RefreshList()
        local list  = self._list or {}
        local start = (self._offset or 0)
        for i, r in ipairs(self.rows) do
            local e = list[start + i]
            if e then
                r.icon:SetTexture(e.icon)
                r.label:SetText(e.display)
                r._id = e.id
                r:Show()
            else
                r._id = nil; r:Hide()
            end
        end
        self.countText:SetText(#list .. " items")
    end

    picker = f
    return f
end

-- Warm the client cache for set-piece ids so their names resolve (called once,
-- a few seconds after login and again when the picker opens).
function Addon:WarmGoalItems()
    if Addon._pvpWarmed then return end
    Addon._pvpWarmed = true
    for _, id in ipairs(Addon.PvPItemIDs or {}) do GetItemInfo(id) end
end

function Addon:ShowGoalPicker(slotId, onPick)
    local f = ensure()
    Addon:WarmGoalItems()
    Addon:BuildGoalPvP()
    f._onPick   = onPick
    f._slotId   = slotId
    f._validLoc = Addon.SLOT_INVTYPES[slotId] or {}
    f._offset   = 0
    f.search:SetText("")
    f._list = filtered("", f._validLoc)
    f:RefreshList()
    f:Show(); f:Raise()
    f.search:SetFocus()
end
