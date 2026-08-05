--[[
    Daseeki Armory — goal item picker (search any item by name).

    A themed search list of items that fit a given slot.

    THE PICKER SHIPS ITS ENTIRE ITEM DATABASE (1.3.1). There is one name source and
    it is catalog.lua: all 9 240 equippable items the Era client holds, with the
    client's own names and qualities, generated once by dev/gen-catalog.lua and
    delivered with the addon. A brand-new account, first login, no wait: open a
    slot and the whole list is there.

    WHAT THAT REPLACED. Three merged sources under a strict precedence order — a
    per-account SavedVariables scan that each user had to run (a minute-long walk of
    32 000 ids, auto-started by a login timer, repeatable through a "Rescan Items"
    button), the bundled AtlasLoot snapshot as a stand-in until that scan finished,
    and a runtime GetItemInfo pass for the PvP rank sets. Precedence, the `settled`
    bookkeeping that enforced it, seed retirement, the scan-progress readout, the
    "(unscanned)" warning on the count line and the scan -> re-filter push all
    existed to manage sources that disagreed and a database that might not be built
    yet. Neither problem exists when the database is shipped.

    The PvP pass survives as a safety net (every one of its ids is already in the
    catalog, so it adds nothing today) and shift-clicking an item link into the
    search box still picks that item directly, which covers anything at all.

    Icons and equip locations still come from GetItemInfoInstant — synchronous,
    offline, never persisted, so they cannot go stale, and an id the catalog names
    that this client does not have is dropped rather than offered.

    Rows are tinted by item RARITY (Borders.QualityTextRGB), and the quality comes
    from the catalog, so it is known for every row before the frame is drawn. Rows
    still ask the client to load, but only so the item LEVEL can join the sort.

    CLASS AND FACTION LOCKS ARE NOT A SOURCE HERE ANY MORE (1.3.1). They come from
    restrictions.lua — shipped data, identical on every account — and the row
    predicate looks them up by item id (Scan.RowVerdict). No entry in this index
    carries a copy of a lock, so no entry can hold a stale one, and there is nothing
    to repair, re-read or refresh when the picker opens.

    Rows the viewing character can NEVER equip — wrong class lock, wrong faction, wrong
    armor/weapon proficiency — are hidden by default; "Show unusable" in the footer
    turns the filter off for edge cases.

    Rows that are not ITEMS at all — Blizzard's placeholders, creature-equipment art,
    designer test gear, retired duplicates, enchantment-effect names — are NOT IN THE
    CATALOG. The denylist (Scan.IsInternalName) is applied by dev/gen-catalog.lua at
    generation time, so those 1 264 rows were never shipped and this index has
    nothing to filter out. Items that ARE real but that no player can obtain on a
    live realm (Addon.StaticUnobtainable — the Ashbringer, the Warglaives, the seven
    GM stones) ARE shipped, and are dropped by the row predicate instead, because
    that list is policy a person must be able to reverse in one line. "Show unusable"
    does NOT bring either kind back: they are not unusable, they are unobtainable by
    everyone, and no character anywhere can get one.

    THE SEED IS GONE, AND SO IS EVERYTHING THAT MANAGED IT. The AtlasLoot snapshot
    (itemDB.lua) is no longer shipped at all; it survives as dev/itemDB-seed.lua,
    a generator input for the Tier-3 class masks that no other source carries. The
    census that justified retiring it stands as the reason the catalog is trusted
    instead: against the owner's completed cache (10 504 ids, Era build 68940),
    1 889 of the snapshot's 5 289 rows had no id in this client at all — Wrath and
    Cataclysm gear, TBC city tabards, and 24 AtlasLoot SECTION HEADINGS ("Warrior",
    "Rogue", "Mage") parked on 300000-325000 ids. Those were never "items the scan
    missed"; they were ids that mean something else here. The catalog is the client's
    own item table, so it cannot contain that class of error.

    SCROLL POSITION SURVIVES A REFRESH (1.3.1). A background refresh — item levels
    streaming in — re-filters the list under the reader. It must not throw them back
    to the top; Rows.NextOffset keeps the current offset, clamped to the new list. A
    refresh the READER asked for (a new query, toggling "Show unusable", opening the
    picker) does go back to the top, because row 400 of the previous list means
    nothing in the new one.

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

-- THE ORDER OF THE LIST, AND THE CAP AT THE END OF IT.
--
-- THE DEFECT (owner report, 1.3.1): "the classic wow era legendaries should still
-- display … thunderfury is missing now." It was missing, and no filter rule had
-- removed it — Scan.RowVerdict answers "usable" for id 19019 on a warrior against
-- the owner's own cache, and the index carries it. It was sorted off the end.
--
-- The list is ordered by ITEM LEVEL, which is not a fact the client holds offline:
-- GetItemInfo answers nil for an item the server has not sent this session, and
-- ilvlOf turns that nil into 0. On a freshly opened picker that is EVERY row, so
-- the item-level key is uniformly 0, the whole order collapses onto the
-- alphabetical tie-break, and MAX_RESULTS then keeps the first 500 names — which
-- is to say the letters A through roughly C.
--
-- Measured on the owner's account-1 cache (9 240 offerable rows): Atiesh sorts at
-- 3.5% and Corrupted Ashbringer at 18.9%, so both survive the cap and he could see
-- them — while Sulfuras sorts at 86.5% and Thunderfury at 90.1%, and each needs
-- its slot's list to be shorter than ~554 rows to survive at all. The weapon slots
-- are not remotely that short. That is the whole bug, and it is exactly the shape
-- of the report: some legendaries displayed, the two late in the alphabet did not.
--
-- THE FIX IS TO STOP LETTING AN ABSENT VALUE DECIDE THE ORDER. Quality is the one
-- ranking fact the scan PERSISTS (Scan.PackMeta writes it into the cache), so it
-- is never cold, and it is what the row is already tinted by. It becomes the key
-- BELOW item level: while levels are unknown the order is by rarity, and the 21
-- legendary/artifact rows in a 9 240-row index cannot be reached by a 500-row cap.
-- Once the levels stream in, item level leads again exactly as before and quality
-- is only a tie-break among equal levels — which used to fall straight to the
-- alphabet.
--
-- THE KEYS ARE SNAPSHOTTED BEFORE THE SORT, NOT READ INSIDE THE COMPARATOR. Both
-- lookups reach for the client, and a comparator whose answers can change while
-- table.sort is running is not an order at all: Lua 5.1 detects the inconsistency
-- and raises "invalid order function for sorting", which in a picker refresh is an
-- empty list. One pass to snapshot, then a comparator that is pure arithmetic over
-- two tables, is what makes the order a total order.
--
--   list      the filtered entries, sorted and capped IN PLACE (also returned)
--   levelOf   entry -> item level, 0 when the client has not sent it
--   qualityOf entry -> item quality, nil when unknown (ranked below Poor)
function Rows.SortAndCap(list, levelOf, qualityOf)
    local lvl, qual = {}, {}
    for i = 1, #list do
        local e = list[i]
        lvl[e]  = tonumber(levelOf   and levelOf(e))   or 0
        qual[e] = tonumber(qualityOf and qualityOf(e)) or -1
    end
    table.sort(list, function(a, b)
        local la, lb = lvl[a], lvl[b]
        if la ~= lb then return la > lb end       -- highest item level first
        local qa, qb = qual[a], qual[b]
        if qa ~= qb then return qa > qb end       -- then rarest first
        return a.display < b.display              -- then by name
    end)
    for i = #list, MAX_RESULTS + 1, -1 do list[i] = nil end
    return list
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

-- ── The item index ────────────────────────────────────────────────────────────
-- Entry: { id, name(lower), display, icon, equipLoc, classID, subclassID,
--          quality, internal, scanned }
--
-- ONE SOURCE NOW (1.3.1). This used to merge three, in a strict precedence order,
-- because none of them was trustworthy on its own: a per-account scan cache that
-- might be empty or half-built, a bundled AtlasLoot snapshot whose ids did not all
-- mean the same thing on this client, and a runtime GetItemInfo pass for the PvP
-- rank sets. The precedence rule, the `settled` bookkeeping that enforced it, and
-- the seed-retirement predicate that decided when the snapshot was allowed to
-- speak at all — every bit of that existed to manage disagreement between sources.
--
-- catalog.lua removed the disagreement by removing the sources. It is the client's
-- own item table, captured once, filtered once, shipped — so it is complete on
-- first login and identical on every account, and there is nothing for a second
-- source to fill in. `settled` survives only as a duplicate guard.
--
-- NO CLASS MASK AND NO FACTION LIVE ON AN ENTRY. They are shipped facts keyed by
-- item id, and the row predicate looks them up. An index that copied them would be
-- a second place for a lock to live, which is a second place for it to be wrong.
--
-- NEITHER DOES equipLoc, icon, classID OR subclassID LIVE IN THE CATALOG.
-- GetItemInfoInstant answers all four offline and synchronously for any id the
-- client holds, so they are re-derived here. That is not a compromise, it is the
-- safety net: an id the catalog names but THIS client does not have answers nil
-- and the row is dropped, so a catalog built against a different build quietly
-- offers less rather than offering phantoms.
--
-- NO STAMP, BECAUSE NOTHING CAN INVALIDATE IT. The catalog is shipped data and
-- cannot change while the client is running; the restriction table likewise. The
-- one thing that can still arrive late is a PvP name (see below), and that is what
-- _goalPvPMissing tracks.
function Addon:BuildGoalItemDB()
    if Addon.GoalItemDB then return Addon.GoalItemDB end

    local list, settled = {}, {}

    local function add(id, name, quality)
        if not id or settled[id] then return end
        settled[id] = true
        if type(name) ~= "string" or name == "" then return end
        local _, _, _, equipLoc, icon, classID, subclassID = GetItemInfoInstant(id)
        if not (icon and equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP") then return end
        list[#list + 1] = {
            id = id, name = name:lower(), display = name, icon = icon,
            equipLoc = equipLoc, classID = classID, subclassID = subclassID,
            quality = quality, internal = false, scanned = true,
        }
    end

    -- 1 — THE SHIPPED CATALOG. Blizzard's scaffolding is already absent (the
    -- denylist was applied when the file was generated), so there is no internal
    -- check to run here and no placeholder for a lower source to inherit.
    Scan.CatalogEach(add)

    -- 2 — PvP rank pieces, kept as a SAFETY NET rather than as a source. Every one
    -- of the 186 ids is in the catalog today, so this loop adds nothing; it stays
    -- because its evidence is the client itself, which means a future catalog that
    -- somehow missed a rank piece still names it. A name that has not arrived yet
    -- is counted, not guessed at.
    local missing = 0
    for _, id in ipairs(Addon.PvPItemIDs or {}) do
        if not settled[id] then
            local nm, _, q = GetItemInfo(id)
            if nm then add(id, nm, q)
            else missing = missing + 1 end
        end
    end

    Addon.GoalItemDB = list
    -- While this is > 0 an incoming GET_ITEM_INFO_RECEIVED is worth a full rebuild;
    -- at 0 (which is the shipped state) the streaming refresh is a re-filter only.
    Addon._goalPvPMissing = missing
    return list
end

-- Back-compat shim: the old two-table model exposed this and the OnEvent refresh
-- called it. Unresolved PvP names now stream in through the same rebuild path.
function Addon:BuildGoalPvP()
    Addon.GoalItemDB = nil
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
    -- The order itself is Rows.SortAndCap — pure, harness-gated, and the place the
    -- owner's missing-legendary defect was fixed; see the note beside it.
    return Rows.SortAndCap(out, ilvlOf, qualityOf)
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

    -- ── footer: the usability toggle, and nothing else ───────────────────────
    -- "RESCAN ITEMS" USED TO SIT HERE, at x=14, with a tooltip promising "about a
    -- minute" and "safe to keep playing". It is gone, along with the "Scanning…"
    -- label it swapped to, the 0.25s progress poll behind it, and the
    -- "(unscanned — press Rescan Items)" suffix on the count line. There is
    -- nothing left for it to rebuild: the item database ships with the addon.
    --
    -- Removing a button is a user-visible change and this is the whole point of
    -- it — the picker no longer has a maintenance control, because the picker no
    -- longer has state that a user could be responsible for maintaining.
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
            if self:IsShown() then
                if (Addon._goalPvPMissing or 0) > 0 then
                    Addon.GoalItemDB = nil
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

    -- SyncScanUI / ShowScanProgress / ScanFinished USED TO LIVE HERE — the button
    -- label swap, the 0.25s progress poll, and the "Scanning item ids… 43%" and
    -- "Loading items… 2140 / 9240" lines it wrote over the count text. The picker
    -- polled rather than being called back, so that a scan it did not start (the
    -- login auto-scan) would still show progress if the owner opened the picker
    -- while it was running.
    --
    -- None of it has anything to describe now. There is no scan on any path a
    -- player can reach, so the picker has no process to report on — only a list.

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
        -- The count line is a count, full stop. It used to carry
        -- "(unscanned — press Rescan Items)" whenever this account had never
        -- completed a scan, which was the picker admitting the list in front of
        -- you might be missing most of the game. There is no such state to warn
        -- about: the list is complete the first time it is ever drawn.
        local n = #list
        self.countText:SetText(n >= MAX_RESULTS and (MAX_RESULTS .. "+ items") or (n .. " items"))
    end

    picker = f
    return f
end

-- ── An external re-filter ────────────────────────────────────────────────────
-- This existed as THE SCAN -> RE-FILTER SEAM: itemScan.lua called it the moment a
-- scan finished, because otherwise an open picker would keep showing the rows it
-- had at open time until it was closed and reopened. No scan reaches a player any
-- more, and the developer scan deliberately does NOT call it (a capture made for
-- the next release must not rewrite the list under the person looking at it).
--
-- The entry point stays because it is the general "something changed, re-filter
-- what is on screen" door, and it is what the harness drives.
--
-- Scroll position is preserved: this refresh is not one the reader asked for.
function Addon:RefreshGoalPicker(preserveScroll)
    if not picker or not picker.Requery then return false end
    if not picker:IsShown() then return false end
    picker:Requery(preserveScroll ~= false)
    return true
end

-- Warm the client cache for the PvP rank-set ids so their names resolve.
--
-- REDUNDANT AND KEPT DELIBERATELY SMALL. All 186 ids are in the shipped catalog,
-- so the index never needs these names; what warming still buys is the item LEVEL
-- for the sort, which only GetItemInfo can answer and only for a loaded item. It
-- runs once, costs nothing on a warm client, and is the sole remaining reason the
-- picker asks the client for anything ahead of time.
function Addon:WarmGoalItems()
    if Addon._pvpWarmed then return end
    Addon._pvpWarmed = true
    for _, id in ipairs(Addon.PvPItemIDs or {}) do GetItemInfo(id) end
end

function Addon:ShowGoalPicker(slotId, onPick)
    local f = ensure()
    Addon:WarmGoalItems()
    -- NOTHING HAPPENS HERE ANY MORE, and that is the release. Opening the picker
    -- used to kick off a lazy restriction-repair pass (1.3.0: throttled server
    -- traffic, a chat line, a session latch, a refusal reason to explain when the
    -- latch said no), and then to sync a rescan button against a running scan.
    -- Both the locks and the items are shipped data, so opening the picker opens
    -- the picker.
    f._onPick   = onPick
    f._slotId   = slotId
    f._validLoc = Addon.SLOT_INVTYPES[slotId] or {}
    f.search:SetText("")
    f:Requery()
    f:Show(); f:Raise()
    f.search:SetFocus()
end
