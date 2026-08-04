--[[
    Daseeki Armory — goal item picker (search any item by name).

    A themed search list of items that fit a given slot. Three sources are merged,
    highest-confidence first:

      1. the SCANNED cache (itemScan.lua / DaseekiArmoryScanDB) — real client names,
         real qualities, and the class/faction locks read off each item's tooltip;
      2. the bundled AtlasLoot-derived name table (itemDB.lua) as the seed/fallback
         while no scan has completed, with itemDB's ItemClassMask as its lock source;
      3. the vanilla PvP rank-set ids (pvpItems.lua), whose names only exist at runtime.

    Icons and equip locations always come from GetItemInfoInstant (synchronous,
    offline, never persisted so it cannot go stale). Shift-clicking an item link into
    the search box picks that item directly, which covers anything all three miss.

    Rows are tinted by item RARITY (Borders.QualityTextRGB). Quality is not available
    for an item the client has not loaded, so unresolved rows request a load and are
    re-tinted when it arrives.

    Rows the viewing character can NEVER equip — wrong class lock, wrong faction, wrong
    armor/weapon proficiency — are hidden by default; "Show unusable" in the footer
    turns the filter off for edge cases.

    Rows that are not ITEMS at all — Blizzard's placeholders, creature-equipment art,
    designer test gear, retired duplicates — never enter the index (Scan.IsInternalName /
    the cached internal flag). "Show unusable" does NOT bring them back: they are not
    unusable, they are not real, and no character anywhere can obtain one.

    An EMPTY search box lists the whole slot (browse mode), exactly as it has since
    1.0.0. There is no minimum query length and no row is ever the current goal echoed
    back; see Scan.Matches in itemScan.lua.

    Addon:ShowGoalPicker(slotId, onPick)   -- onPick(itemId)
--]]

local _, Addon = ...

local ROWH, ROWS, W = 28, 12, 360
local LIST_TOP  = 82
local FOOTER_Y  = LIST_TOP + ROWS * ROWH + 24
local MAX_RESULTS = 500
local picker

local Scan = Addon.ItemScan

-- ── Class / faction usability ─────────────────────────────────────────────────
-- The predicate itself lives in itemScan.lua (pure, harness-gated); this is the
-- addon-facing wrapper kept for callers that only have an entry.
function Addon:ItemUsableByClass(e, ctx)
    return Scan.Usable(e, ctx or Addon:ScanContext(false))
end

-- Bundled class mask for a seed entry (0 = no bundled restriction known).
local function seedClassMask(id)
    local m = Addon.ItemClassMask and Addon.ItemClassMask[id]
    return tonumber(m) or 0
end

-- ── The merged item index ─────────────────────────────────────────────────────
-- Entry: { id, name(lower), display, icon, equipLoc, classID, subclassID,
--          quality, classMask, faction, scanned }
-- Rebuilt whenever the scan cache changes (stamp = completion time + item count).
function Addon:BuildGoalItemDB()
    local cache = Addon:ItemScanCache()
    -- the denylist stamp is part of the key: growing INTERNAL_PATTERNS must rebuild
    -- the index, not wait for the next scan.
    local stamp = tostring(cache.scannedAt or 0) .. "/" .. tostring(cache.count or 0)
                  .. "/" .. tostring(cache.internalStamp or 0)
    if Addon.GoalItemDB and Addon._goalDBStamp == stamp then return Addon.GoalItemDB end

    local list, byId = {}, {}
    -- `internal` is the cached flag when the caller has one (the scan already
    -- derived it) and nil for the seed tables, where it is derived here. Internal
    -- rows never enter the index at ALL, which is why "Show unusable" cannot
    -- reveal them: that tick box is about items some OTHER character could equip,
    -- and these are not items — they are Blizzard's placeholders and test records.
    local function add(id, name, quality, classMask, faction, scanned, internal)
        if not id or byId[id] or type(name) ~= "string" or name == "" then return end
        if internal == nil then internal = Scan.IsInternalName(name) end
        if internal then return end
        local _, _, _, equipLoc, icon, classID, subclassID = GetItemInfoInstant(id)
        if not (icon and equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP") then return end
        local e = {
            id = id, name = name:lower(), display = name, icon = icon,
            equipLoc = equipLoc, classID = classID, subclassID = subclassID,
            quality = quality, classMask = classMask or 0,
            faction = faction or Scan.FACTION_NONE, scanned = scanned or false,
        }
        byId[id] = e
        list[#list + 1] = e
    end

    -- 1 — the scan (authoritative)
    for id in pairs(cache.names) do
        local nm, q, m, f, internal = Scan.Get(cache, id)
        add(id, nm, q, m, f, true, internal)
    end

    -- 2 — the bundled seed, for anything the scan has not covered yet
    if Addon.ItemNameDB then
        for id, nm in pairs(Addon.ItemNameDB) do
            add(id, nm, nil, seedClassMask(id), Scan.FACTION_NONE, false)
        end
    end

    -- 3 — PvP rank pieces: no bundled name, so ask the client for one
    local missing = 0
    for _, id in ipairs(Addon.PvPItemIDs or {}) do
        if not byId[id] then
            local nm, _, q = GetItemInfo(id)
            if nm then add(id, nm, q, seedClassMask(id), Scan.FACTION_NONE, false)
            else missing = missing + 1 end
        end
    end

    Addon.GoalItemDB      = list
    Addon._goalDBStamp    = stamp
    -- How many PvP ids still have no name. While this is > 0 an incoming
    -- GET_ITEM_INFO_RECEIVED is worth a full rebuild; once it hits 0 (always, after a
    -- completed scan) the streaming refresh is a re-filter only, never a rebuild.
    Addon._goalPvPMissing = missing
    return list
end

-- Back-compat shim: the old two-table model exposed this and the OnEvent refresh
-- called it. Unresolved PvP names now stream in through the same rebuild path.
function Addon:BuildGoalPvP()
    Addon.GoalItemDB, Addon._goalDBStamp = nil, nil
    return Addon:BuildGoalItemDB()
end

-- item level for sorting (cached once resolved; 0 while the client hasn't cached it)
local function ilvlOf(e)
    if e._ilvl then return e._ilvl end
    local _, _, _, lvl = GetItemInfo(e.id)
    if lvl then e._ilvl = lvl; return lvl end
    return 0
end

-- quality for the row tint (nil until the client has the item; requested lazily)
local function qualityOf(e)
    if e.quality ~= nil then return e.quality end
    local q = select(3, GetItemInfo(e.id))
    if q ~= nil then e.quality = q end
    return q
end

-- EMPTY SEARCH BOX = BROWSE THE WHOLE SLOT. Unchanged since 1.0.0 and kept
-- deliberately: the box filters a browsable list, it is not a required search
-- term, and there is no minimum length. The row predicate itself now lives in
-- itemScan.lua (Scan.Matches) so that promise is pinned by the harness.
local function filtered(query, validLoc, ctx)
    query = Scan.NormalizeQuery(query)
    local out = {}
    for _, e in ipairs(Addon:BuildGoalItemDB()) do
        if Scan.Matches(e, query, validLoc, ctx) then
            out[#out + 1] = e
        end
    end
    -- Sort FIRST, cap after: capping during the gather would hand back an arbitrary
    -- 500 (the index is walked in table order) and only then sort them, so the
    -- "highest item level first" promise held only when the result set was small.
    table.sort(out, function(a, b)
        local la, lb = ilvlOf(a), ilvlOf(b)
        if la ~= lb then return la > lb end   -- highest item level first
        return a.display < b.display
    end)
    for i = #out, MAX_RESULTS + 1, -1 do out[i] = nil end
    return out
end

-- ── Footer widgets (Core factories when present, Blizzard templates otherwise) ─
local function makeButton(parent, text, x, y, w, h, fn)
    local DS = _G.DaseekiSuite
    if DS and DS.MakeButton then return DS.MakeButton(parent, text, x, y, w, h, fn) end
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h); b:SetText(text)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    b:SetScript("OnClick", fn)
    return b
end

local function makeCheckbox(parent, text, x, y, getter, setter)
    local DS = _G.DaseekiSuite
    if DS and DS.MakeCheckbox then return DS.MakeCheckbox(parent, text, x, y, getter, setter) end
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y); cb:SetSize(24, 24)
    local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0); lbl:SetText(text)
    cb:SetScript("OnShow",  function(self) self:SetChecked(getter()) end)
    cb:SetScript("OnClick", function(self) setter(self:GetChecked()) end)
    return cb
end

local function pickerSettings()
    local s = Addon.db and Addon.db.settings
    return (s and s.goalPicker) or {}
end

local function ensure()
    if picker then return picker end
    local DS = _G.DaseekiSuite

    local H = FOOTER_Y + 32
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
    f.title:SetPoint("TOP", f, "TOP", 0, -12); f.title:SetText("Choose Goal Item")
    if not Addon:TrySetCeremonial(f.title, 16) then f.title:SetTextColor(1, 0.82, 0) end

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Hide() end)

    f.countText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Addon:TrySetFont(f.countText, "small")   -- before the SetTextColor below
    f.countText:SetPoint("TOP", f, "TOP", 0, -(LIST_TOP + ROWS * ROWH + 6))
    f.countText:SetWidth(W - 28); f.countText:SetJustifyH("CENTER")
    f.countText:SetTextColor(Addon:Col("muted"))

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
                print(Addon:Tag() .. " that item doesn't fit this slot.")
            end
            return
        end
        picker:Requery()
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus(); picker:Hide() end)
    f.search = search

    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    Addon:TrySetFont(f.hint, "small")
    f.hint:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -62)
    f.hint:SetText("Search by item name, or shift-click an item link here")

    f.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, f)
        r:SetSize(W - 28, ROWH)
        r:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -(LIST_TOP + (i - 1) * ROWH))
        r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
        r.bg:SetColorTexture(Addon:Col(i % 2 == 0 and "raised" or "panel", 0.5))
        r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(22, 22); r.icon:SetPoint("LEFT", 2, 0)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        r.label = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        Addon:TrySetFont(r.label, "body")   -- result rows are item names
        r.label:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.label:SetWidth(W - 60); r.label:SetJustifyH("LEFT")
        local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(Addon:Col("brand", 0.25))
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

    -- ── footer: rescan + the usability toggle ────────────────────────────────
    f.rescan = makeButton(f, "Rescan Items", 14, FOOTER_Y, 118, 22, function()
        if Addon:IsScanning() then return end
        Addon:StartItemScan({ force = true })
        f:SyncScanUI()
    end)
    f.rescan:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Rescan Items")
        GameTooltip:AddLine("Re-reads every equippable item from the client and caches its name,"
            .. " rarity and class/faction locks.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("Account-wide; takes about a minute. Safe to keep playing.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    f.rescan:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.showUnusable = makeCheckbox(f, "Show unusable", W - 148, FOOTER_Y + 1,
        function() return pickerSettings().showUnusable end,
        function(v)
            local s = Addon.db and Addon.db.settings
            if s then s.goalPicker = s.goalPicker or {}; s.goalPicker.showUnusable = v and true or false end
            if picker then picker:Requery() end
        end)

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        local maxOff = math.max(0, #(picker._list or {}) - ROWS)
        picker._offset = math.min(maxOff, math.max(0, (picker._offset or 0) - delta))
        picker:RefreshList()
    end)

    -- as item names / levels / qualities stream in, rebuild and re-tint
    f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    f:SetScript("OnEvent", function(self)
        if not self:IsShown() or self._refreshPending then return end
        self._refreshPending = true
        C_Timer.After(0.3, function()
            self._refreshPending = nil
            if self:IsShown() and not Addon:IsScanning() then
                if (Addon._goalPvPMissing or 0) > 0 then
                    Addon.GoalItemDB, Addon._goalDBStamp = nil, nil
                end
                self:Requery()
            end
        end)
    end)

    function f:Requery()
        self._ctx    = Addon:ScanContext(pickerSettings().showUnusable)
        self._list   = filtered(self.search:GetText(), self._validLoc or {}, self._ctx)
        self._offset = 0
        self:RefreshList()
    end

    -- The picker POLLS the scan rather than being called back by it, so a scan the
    -- picker did not start (the once-per-account auto scan at login) still shows its
    -- progress if the owner opens the picker while it is running.
    function f:SyncScanUI()
        local scanning = Addon:IsScanning()
        if self.rescan.SetText then self.rescan:SetText(scanning and "Scanning…" or "Rescan Items") end
        if self.rescan._label then self.rescan._label:SetText(scanning and "Scanning…" or "Rescan Items") end
        if scanning then self.rescan:Disable() else self.rescan:Enable() end
        if scanning and not self._scanPoll then
            self._scanPoll = true
            local function poll()
                if not picker or not picker._scanPoll then return end
                if Addon:IsScanning() then
                    picker:ShowScanProgress(Addon:ItemScanStatus())
                    C_Timer.After(0.25, poll)
                else
                    picker._scanPoll = nil
                    picker:ScanFinished()
                end
            end
            poll()
        end
    end

    function f:ShowScanProgress(st)
        if not st then return end
        self:SyncScanUI()
        if st.phase == "instant" then
            self.countText:SetText(string.format("Scanning item ids… %d%%  (%d equippable found)",
                st.percent or 0, st.found or 0))
        else
            self.countText:SetText(string.format("Loading items… %d / %d  (%d%%)",
                st.cursor or 0, st.total or 0, st.percent or 0))
        end
    end

    function f:ScanFinished()
        self:SyncScanUI()
        if self:IsShown() then self:Requery() end
    end

    function f:RefreshList()
        local list  = self._list or {}
        local start = (self._offset or 0)
        for i, r in ipairs(self.rows) do
            local e = list[start + i]
            if e then
                r.icon:SetTexture(e.icon)
                r.label:SetText(e.display)
                -- RARITY TINT: the suite's quality chain, text variant.
                local q = qualityOf(e)
                local cr, cg, cb = Addon.Borders and Addon.Borders.QualityTextRGB(q)
                if cr then r.label:SetTextColor(cr, cg, cb)
                else
                    r.label:SetTextColor(Addon:Col("text"))
                    -- uncached: ask the client, then re-tint on GET_ITEM_INFO_RECEIVED
                    if _G.C_Item and _G.C_Item.RequestLoadItemDataByID then
                        _G.C_Item.RequestLoadItemDataByID(e.id)
                    end
                end
                r._id = e.id
                r:Show()
            else
                r._id = nil; r:Hide()
            end
        end
        if not Addon:IsScanning() then
            local n = #list
            local cache = Addon:ItemScanCache()
            local suffix = Scan.IsComplete(cache) and "" or "  (unscanned — press Rescan Items)"
            self.countText:SetText((n >= MAX_RESULTS and (MAX_RESULTS .. "+ items") or (n .. " items")) .. suffix)
        end
    end

    picker = f
    return f
end

-- Warm the client cache for set-piece ids so their names resolve (called once,
-- a few seconds after login and again when the picker opens). Redundant once a
-- scan has completed — those ids are then already in the cache — so it is skipped.
function Addon:WarmGoalItems()
    if Addon._pvpWarmed then return end
    if Scan.IsComplete(Addon:ItemScanCache()) then Addon._pvpWarmed = true; return end
    Addon._pvpWarmed = true
    for _, id in ipairs(Addon.PvPItemIDs or {}) do GetItemInfo(id) end
end

function Addon:ShowGoalPicker(slotId, onPick)
    local f = ensure()
    Addon:WarmGoalItems()
    f._onPick   = onPick
    f._slotId   = slotId
    f._validLoc = Addon.SLOT_INVTYPES[slotId] or {}
    f.search:SetText("")
    f:SyncScanUI()
    f:Requery()
    f:Show(); f:Raise()
    f.search:SetFocus()
end
