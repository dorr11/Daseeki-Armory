--[[
    Daseeki Armory — goal item picker (search any item by name).

    A themed search list of items that fit a given slot. Three NAME sources are
    merged, highest-confidence first:

      1. the SCANNED cache (itemScan.lua / DaseekiArmoryScanDB) — real client names
         and real qualities;
      2. the bundled AtlasLoot-derived name table (itemDB.lua) as the seed/fallback
         ONLY WHILE NO SCAN HAS COMPLETED (see SEED RETIREMENT below);
      3. the vanilla PvP rank-set ids (pvpItems.lua), whose names only exist at runtime.

    Icons and equip locations always come from GetItemInfoInstant (synchronous,
    offline, never persisted so it cannot go stale). Shift-clicking an item link into
    the search box picks that item directly, which covers anything all three miss.

    Rows are tinted by item RARITY (Borders.QualityTextRGB). Quality is not available
    for an item the client has not loaded, so unresolved rows request a load and are
    re-tinted when it arrives.

    CLASS AND FACTION LOCKS ARE NOT A SOURCE HERE ANY MORE (1.3.1). They come from
    restrictions.lua — shipped data, identical on every account — and the row
    predicate looks them up by item id (Scan.RowVerdict). No entry in this index
    carries a copy of a lock, so no entry can hold a stale one, and there is nothing
    to repair, re-read or refresh when the picker opens.

    Rows the viewing character can NEVER equip — wrong class lock, wrong faction, wrong
    armor/weapon proficiency — are hidden by default; "Show unusable" in the footer
    turns the filter off for edge cases.

    Rows that are not ITEMS at all — Blizzard's placeholders, creature-equipment art,
    designer test gear, retired duplicates, enchantment-effect names — never enter the
    index (Scan.IsInternalName / the cached internal flag). Items that ARE real but
    that no player can obtain on a live realm (Addon.StaticUnobtainable) are dropped
    by the row predicate. "Show unusable" does NOT bring either kind back: they are
    not unusable, they are unobtainable by everyone, and no character anywhere can
    get one.

    SOURCE PRECEDENCE IS ABSOLUTE (1.3.1). Any id the SCAN covered is settled by the
    scan, whatever it decided — kept, dropped as internal, or rejected for its equip
    location. The bundled seed is an AtlasLoot snapshot whose ids do not all agree
    with this client, so it may only speak for ids the scan never saw.

    SEED RETIREMENT (1.3.1). Once a scan has COMPLETED, the seed is not consulted at
    all. The id walk is GetItemInfoInstant over the client's own item space, so it is
    ground truth for what this client knows: an id the completed scan never found is
    an id the client does not have, and no character on this realm can obtain it. The
    seed's leftovers are not "items the scan missed", they are ids that mean something
    else (or nothing) here. Census against the owner's real completed cache (10 504 ids,
    Era build 68940): 1 889 of the bundled 5 289 rows have no id in this client at all.
    95 of those sit ABOVE the scanned range entirely — Wrath and Cataclysm gear
    (Wrathful Gladiator's Tabard, Tabard of the Argent Crusade, Gilneas Tabard), the TBC
    city tabards (Exodar, Silvermoon City), TBC holiday gear (Hallowed Helm, Swift
    Brewfest Ram) and 24 AtlasLoot SECTION HEADINGS ("Warrior", "Rogue", "Mage") parked
    on 300000-325000 ids. The seed therefore exists for exactly one purpose: naming rows
    before the first scan finishes. Addon.GoalSeedAllowed(cache) is that rule, pure and
    harness-gated.

    NOTE what seed retirement does NOT do: ids 18582-18584 (The Twin Blades of
    Azzinoth, both Warglaives), 22736 (Andonisus) and 23054 (Gressil) ARE in this
    client's item space and the scan finds them. Those are unobtainable by HISTORY,
    not by client data, so seed retirement cannot see them — they are removed by
    Addon.StaticUnobtainable in restrictions.lua instead, which IS the hand-written
    list of what Blizzard retired, kept as data a person can edit in one line.

    SCROLL POSITION SURVIVES A REFRESH (1.3.1). A background refresh — item names
    streaming in, a scan finishing — re-filters the list under the reader. It must
    not throw them back to the top; Rows.NextOffset keeps the current offset,
    clamped to the new list. A refresh the READER asked for (a new query, toggling
    "Show unusable", opening the picker) does go back to the top, because row 400 of
    the previous list means nothing in the new one.

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

-- ── The row pool: geometry and tint, as a PURE module ─────────────────────────
-- Everything here is arithmetic over numbers, touches no WoW API, and is
-- harness-gated. It exists because 1.3.0 shipped a picker that rendered ONE row:
--
--     local cr, cg, cb = Addon.Borders and Addon.Borders.QualityTextRGB(q)
--
-- In Lua an `and` expression is adjusted to a SINGLE value, so cg and cb were
-- always nil, the very next line called SetTextColor(r, nil, nil), and that
-- raises. Row 1 had already been given its text, rows 2..12 had not been touched
-- yet, and the error left the loop — so the list showed exactly one line, no row
-- was ever tinted, and scrolling appeared to reveal items one at a time. Tint()
-- now returns the triple from a plain assignment; Rows.Tint's contract (all three
-- or none) is what the harness pins.
local Rows = {}
Addon.GoalPickerRows = Rows
Rows.ROW_HEIGHT  = ROWH
Rows.VISIBLE     = ROWS
Rows.LIST_TOP    = LIST_TOP
Rows.WIDTH       = W
Rows.FOOTER_Y    = FOOTER_Y
Rows.MAX_RESULTS = MAX_RESULTS

-- Downward offset of visible row i from the frame's TOPLEFT (1-based).
function Rows.RowY(i)
    i = math.floor(tonumber(i) or 0)
    if i < 1 or i > ROWS then return nil end
    return LIST_TOP + (i - 1) * ROWH
end

function Rows.FrameHeight() return FOOTER_Y + 32 end

-- The furthest the list can scroll: the last screenful, never negative.
function Rows.MaxOffset(n)
    n = math.floor(tonumber(n) or 0)
    return math.max(0, n - ROWS)
end

function Rows.ClampOffset(offset, n)
    offset = math.floor(tonumber(offset) or 0)
    if offset < 0 then return 0 end
    local mx = Rows.MaxOffset(n)
    if offset > mx then return mx end
    return offset
end

-- WHERE A REFRESH LANDS.
--
-- RefreshList used to be reached only through Requery, and Requery always wrote
-- `self._offset = 0`. Every background refresh therefore yanked the reader back
-- to row 1 — and those refreshes arrive in a stream (each visible row asks the
-- client to load its item so it can be tinted, every reply raises
-- GET_ITEM_INFO_RECEIVED, and the debounced handler re-queried), so the list was
-- unscrollable for as long as items were streaming in.
--
--   preserve = true   a refresh nobody asked for: keep the reader where they are,
--                     clamped, because the list may have got shorter under them
--   preserve = false  a refresh the reader asked for (new query, filter toggle,
--                     a fresh open): the old position has no meaning, go to the top
function Rows.NextOffset(prevOffset, newCount, preserve)
    if not preserve then return 0 end
    return Rows.ClampOffset(prevOffset, newCount)
end

-- Which result index each of the VISIBLE rows shows at this offset; false for a
-- row that must be hidden. Always exactly ROWS entries — the list is a fixed
-- pool, so every refresh has to say something about every row in it.
function Rows.Slice(n, offset)
    n = math.floor(tonumber(n) or 0)
    offset = Rows.ClampOffset(offset, n)
    local out = {}
    for i = 1, ROWS do
        local idx = offset + i
        out[i] = (idx >= 1 and idx <= n) and idx or false
    end
    return out
end

-- -> r, g, b, needsLoad
-- All three components or none: a caller can never be handed a partial color.
-- needsLoad is true exactly when the quality is not known yet, which is the
-- signal to ask the client for the item and re-tint on the reply.
function Rows.Tint(quality, borders)
    local B = borders or Addon.Borders
    if B and B.QualityTextRGB then
        local r, g, b = B.QualityTextRGB(quality)
        if r ~= nil and g ~= nil and b ~= nil then return r, g, b, false end
    end
    return nil, nil, nil, true
end

-- ── Class / faction usability ─────────────────────────────────────────────────
-- The predicate itself lives in itemScan.lua (pure, harness-gated); this is the
-- addon-facing wrapper kept for callers that only have an entry.
function Addon:ItemUsableByClass(e, ctx)
    return Scan.Usable(e, ctx or Addon:ScanContext(false))
end

-- ── SEED RETIREMENT ───────────────────────────────────────────────────────────
-- May the bundled AtlasLoot table speak at all? Only before a scan has completed.
--
-- The scan is a GetItemInfoInstant walk of ids 1..32000 — a purely local lookup
-- against the client's own item database — so a completed scan is an exhaustive
-- census of what this client knows. An id it never found is an id this client
-- does not have; a name the seed offers for such an id is a name from a different
-- game (the bundled table is an AtlasLoot snapshot that reaches into TBC and
-- beyond) or, more often, not an item name at all. Either way nothing a player
-- can obtain here is behind it, so it must not be offered as a goal.
--
-- Pure on purpose: this is the whole rule, and the harness drives it directly.
function Addon.GoalSeedAllowed(cache)
    return not Scan.IsComplete(cache)
end

-- ── The merged item index ─────────────────────────────────────────────────────
-- Entry: { id, name(lower), display, icon, equipLoc, classID, subclassID,
--          quality, internal, scanned }
--
-- NO CLASS MASK AND NO FACTION LIVE ON AN ENTRY (1.3.1). They are shipped facts
-- keyed by item id, and the row predicate looks them up. An index that copied them
-- would be a second place for a lock to live, which is a second place for it to be
-- wrong — the exact failure mode the repair pass existed to paper over.
--
-- Rebuilt whenever the scan cache changes (stamp = completion time + item count).
function Addon:BuildGoalItemDB()
    local cache = Addon:ItemScanCache()
    -- the denylist stamp is part of the key: growing INTERNAL_PATTERNS must rebuild
    -- the index, not wait for the next scan. The restriction table needs no stamp:
    -- it is shipped with the addon and cannot change while the client is running.
    local stamp = tostring(cache.scannedAt or 0) .. "/" .. tostring(cache.count or 0)
                  .. "/" .. tostring(cache.internalStamp or 0)
    if Addon.GoalItemDB and Addon._goalDBStamp == stamp then return Addon.GoalItemDB end

    local list, settled = {}, {}
    -- `settled` is every id a HIGHER-confidence source has already spoken for,
    -- whatever it decided — kept, dropped as internal, or rejected for its equip
    -- location. A lower source may never speak for a settled id again.
    --
    -- That is stricter than the "already in the list" test it replaces, and the
    -- difference is a real defect (owner screenshot, 1.3.1): the internal drop
    -- returns BEFORE the id is recorded, so dropping the client's placeholder at
    -- id 13794 handed that id straight back to the bundled seed — which names
    -- 13794 "Enchant Cloak - Resistance", an enchantment EFFECT, while the client
    -- calls it "[PH] Shining Dawn Coif". The picker then showed the seed's wrong
    -- name for a row the denylist had just removed. 37 ids in the owner's cache
    -- were resurrecting like that, 7 of them as "Enchant …" rows.
    --
    -- itemDB.lua is an AtlasLoot-derived SNAPSHOT; where it and the client
    -- disagree about what an id is, the client wins, always.
    local function add(id, name, quality, scanned, internal)
        if not id or settled[id] then return end
        settled[id] = true
        if type(name) ~= "string" or name == "" then return end
        if internal == nil then internal = Scan.IsInternalName(name) end
        if internal then return end
        local _, _, _, equipLoc, icon, classID, subclassID = GetItemInfoInstant(id)
        if not (icon and equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP") then return end
        list[#list + 1] = {
            id = id, name = name:lower(), display = name, icon = icon,
            equipLoc = equipLoc, classID = classID, subclassID = subclassID,
            quality = quality, internal = false, scanned = scanned or false,
        }
    end

    -- 1 — the scan (authoritative)
    for id in pairs(cache.names) do
        local nm, q, internal = Scan.Get(cache, id)
        add(id, nm, q, true, internal)
    end

    -- 2 — the bundled seed, ONLY while the scan has not yet spoken for this client.
    -- Once it has, the cache is the whole index: see SEED RETIREMENT at the top.
    -- It supplies NAMES only; its ItemClassMask has been folded into the shipped
    -- restrictions.lua by dev/gen-restrictions.lua, so it is not consulted for a
    -- lock at runtime any more.
    local seedAllowed = Addon.GoalSeedAllowed(cache)
    if seedAllowed and Addon.ItemNameDB then
        for id, nm in pairs(Addon.ItemNameDB) do
            add(id, nm, nil, false)
        end
    end

    -- 3 — PvP rank pieces: no bundled name, so ask the CLIENT for one. This pass
    -- survives seed retirement because its evidence is GetItemInfo, not the seed —
    -- a name only comes back for an id this client actually has. After a completed
    -- scan every one of these ids is already settled, so it is a no-op anyway.
    local missing = 0
    for _, id in ipairs(Addon.PvPItemIDs or {}) do
        if not settled[id] then
            local nm, _, q = GetItemInfo(id)
            if nm then add(id, nm, q, false)
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
    for i = 1, Rows.VISIBLE do
        local r = CreateFrame("Button", nil, f)
        r:SetSize(W - 28, ROWH)
        r:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -Rows.RowY(i))
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
        picker._offset = Rows.ClampOffset((picker._offset or 0) - delta, #(picker._list or {}))
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
                -- NOBODY ASKED FOR THIS ONE. It is the item-info stream catching up,
                -- and it arrives in bursts — so it keeps the reader's scroll position.
                self:Requery(true)
            end
        end)
    end)

    -- preserveScroll: see Rows.NextOffset. Absent/false = a refresh the reader
    -- asked for, which starts at the top.
    function f:Requery(preserveScroll)
        local prev   = self._offset or 0
        self._ctx    = Addon:ScanContext(pickerSettings().showUnusable)
        self._list   = filtered(self.search:GetText(), self._validLoc or {}, self._ctx)
        self._offset = Rows.NextOffset(prev, #self._list, preserveScroll)
        self:RefreshList()
    end

    -- The picker POLLS the scan rather than being called back by it, so a scan the
    -- picker did not start (the once-per-account auto scan at login) still shows its
    -- progress if the owner opens the picker while it is running.
    function f:SyncScanUI()
        local scanning = Addon:IsScanning()
        local label = scanning and "Scanning…" or "Rescan Items"
        if self.rescan.SetText then self.rescan:SetText(label) end
        if self.rescan._label then self.rescan._label:SetText(label) end
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
        if self:IsShown() then self:Requery(true) end
    end

    function f:RefreshList()
        local list  = self._list or {}
        -- Slice says something about EVERY row in the pool, and the loop walks the
        -- pool by index rather than with ipairs: a hole in the pool must not be
        -- able to cut the list short, which is half of how 1.3.0 rendered one row.
        local slice = Rows.Slice(#list, self._offset or 0)
        for i = 1, Rows.VISIBLE do
            local r = self.rows[i]
            local e = slice[i] and list[slice[i]] or nil
            if r and e then
                r.icon:SetTexture(e.icon)
                -- RARITY TINT: the suite's quality chain, text variant. Decide the
                -- color BEFORE touching the widget, and take all three components
                -- from one assignment (see Rows.Tint).
                local cr, cg, cb, needsLoad = Rows.Tint(qualityOf(e))
                if cr then r.label:SetTextColor(cr, cg, cb)
                else
                    r.label:SetTextColor(Addon:Col("text"))
                    -- uncached: ask the client, then re-tint on GET_ITEM_INFO_RECEIVED
                    if needsLoad and _G.C_Item and _G.C_Item.RequestLoadItemDataByID then
                        _G.C_Item.RequestLoadItemDataByID(e.id)
                    end
                end
                r.label:SetText(e.display)
                r._id = e.id
                r:Show()
            elseif r then
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

-- ── THE SCAN → RE-FILTER SEAM ────────────────────────────────────────────────
-- Called by itemScan.lua the moment a scan finishes.
--
-- Without it the ONLY thing that re-filters an open picker is the picker's own
-- 0.25s poll (f:SyncScanUI -> f:ScanFinished), and that poll is armed only when
-- SyncScanUI happens to be called while a scan is already running. So a scan could
-- finish and the open list would keep showing the rows it had at open time until
-- the picker was closed and reopened. The fix is a push, not a poll:
-- FinishItemScan invalidates the index and then calls this.
--
-- Scroll position is preserved: this refresh is not one the reader asked for.
function Addon:RefreshGoalPicker(preserveScroll)
    if not picker or not picker.Requery then return false end
    if not picker:IsShown() then return false end
    picker:Requery(preserveScroll ~= false)
    return true
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
    -- NOTHING HAPPENS HERE ANY MORE, and that is the release (1.3.1). Opening the
    -- picker used to kick off a lazy restriction-repair pass — throttled server
    -- traffic, a chat line, a session latch, a refusal reason to explain when the
    -- latch said no. The locks are shipped data now, so opening the picker opens
    -- the picker.
    f._onPick   = onPick
    f._slotId   = slotId
    f._validLoc = Addon.SLOT_INVTYPES[slotId] or {}
    f.search:SetText("")
    f:SyncScanUI()
    f:Requery()
    f:Show(); f:Raise()
    f.search:SetFocus()
end
