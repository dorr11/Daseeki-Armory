--[[
    Daseeki Armory — options sections for the Daseeki-Core hub (id "armory").

    Migrated to the DaseekiUI flow API (Core commit 1d7d942). Each section's
    build(flow) receives the flow object; every control is appended through the
    flow (AddSection / AddRow / widget constructors) so vertical position is a
    computed running cursor — there are NO caller-supplied y-offsets and the pane
    scroll+clips, so nothing can render outside the window.

    The two spatially-rich pieces (the set list and the paper-doll set builder)
    are custom token-skinned frames added as flow blocks so they participate in
    layout, reflow on resize, and scroll with the pane. They read theme tokens at
    render and re-skin live on ThemeChanged (DaseekiUI.Skin / DaseekiUI.Color).

    Three sections (Core sub-tabs); round-5 folded the Set Swapper config into the
    Sets tab's left column, so it is no longer a top-level sidebar entry:
      • Sets            — set list + CRUD + management + Set Swapper + paper-doll builder
      • Character Window — per-slot flyout config (Blizzard character pane)
      • Item Slot Widgets — live list of detached gear-slot popouts
--]]

local _, Addon = ...

local function cap(d) return (d:sub(1, 1):upper() .. d:sub(2)) end

local function slotName(slotId)
    for _, s in ipairs(Addon.SLOTS) do if s.id == slotId then return s.name end end
    return "Slot"
end
local function slotEmptyTex(slotId)
    for _, s in ipairs(Addon.SLOTS) do if s.id == slotId then return Addon:GetSlotEmptyTexture(s) end end
    return Addon.EMPTY_ICON
end

local PERROW = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12" }

-- ── Named layout metrics (single source; no magic literals in the code below) ──
local IB          = 2    -- art inset within an icon button
local LIST_INSET  = 4    -- scroll viewport inset in the set list
local CHECK_INSET = 3    -- goal-obtained check inset within a slot
-- Slot badge layer. OVERLAY sublevel 7 is the top of a button's OVERLAY range,
-- so the goal check and the explicit-empty X sort above every other slot
-- decoration: the red "missing gear" ring (OVERLAY sublevel 0 on the button) and
-- the suite quality glow (borders.lua, OVERLAY sublevel -1 in its own container
-- frame at the host button's level). Only HIGHLIGHT — the translucent hover
-- tint — draws over it, which is intended.
local BADGE_SUBLEVEL = 7
local SET_ROW_H   = 28   -- set-list row height
local SETLIST_H   = 200  -- set-list viewport height
local SLOT_SZ     = 36   -- equip-slot button size
local SLOT_STEP   = 40   -- vertical pitch between equip slots
local COL_ROWS    = 8    -- equip slots per column
local MODEL_W     = 200  -- paper-doll model width
local MODEL_H     = 300  -- paper-doll model height
local WPN_GAP     = 12   -- vertical gap above the weapons row
local WPN_XGAP    = 8    -- horizontal gap between weapon slots
local GOAL_SZ     = 22   -- goal "chase list" button size
local W_ROW_H     = 30   -- item-slot-widget list row height
local PD_W        = 512  -- fixed paper-doll builder band width (centered in content)
local SPLIT_MIN   = 828  -- content width to switch Sets to two-pane (SPLIT_LEFT+GAP+PD_W)
local SPLIT_LEFT  = 300  -- set-list column width in two-pane mode
local SPLIT_GAP   = 16   -- gap between the two Sets columns
local ITEM_GAP    = 8    -- mirrors DaseekiUI's inter-item gap inside a flow row
local MGMT_BTN    = 142  -- management/CRUD button width (two per row in the ~300px column)
local MGMT_GRID   = MGMT_BTN * 2 + ITEM_GAP  -- full management-grid width (two buttons + one gap) = 292
local SWAP_DD     = (MGMT_GRID - 2 * ITEM_GAP) / 3  -- three Set-Swapper dropdowns sharing the management-grid edges = 92
local DD_CAP_H    = 18   -- Set-Swapper column-caption height (UI.MakeLabel's fixed height)
local DD_CAP_GAP  = 2    -- caption -> dropdown gap (the 20px pitch MakeDropdown's own label uses)
local DD_BTN_H    = 24   -- MakeDropdown button height

-- ── Set-list reorder drag: which slot is the cursor pointing at? (PURE) ───────
--
-- Arithmetic over numbers only, no WoW API, so the harness drives the REAL
-- function — the same treatment goalPicker.lua's row geometry gets (Rows /
-- Addon.GoalPickerRows), and for the same reason: a hit-test that lives inline
-- in an OnUpdate closure is a hit-test nothing can test.
--
-- TWO COORDINATE SPACES MEET IN A REORDER DRAG, and mixing them is the defect
-- this seam exists to end:
--
--   GetCursorPosition()          -> RAW screen units, no scale applied.
--   Frame:GetTop()/GetBottom()   -> the FRAME'S OWN effective-scale space.
--
-- A cursor Y may therefore only be compared against a frame's edges after
-- dividing it by THAT frame's effective scale. The set list used to divide by
-- UIParent's instead, which agrees only while the list's effective scale happens
-- to equal UIParent's. Nothing scales the options pane today, so the two spaces
-- coincide and the bug is invisible — but the moment anything in the chain from
-- UIParent down to the scroll child takes a SetScale (a list-scale slider, a
-- themed pane scale, a Core window scale), the comparison reads the cursor as
-- (listScale x) its true height above the screen's bottom edge. That error is
-- PROPORTIONAL to height, not a constant offset, so the drop bar would drift
-- further from the pointer the higher up the list you dragged. Daseeki-Raid-Prep
-- shipped exactly this shape and a player hit it the week a List Scale slider
-- landed (Raid Prep 1.3.1); this is the same defect, fixed before it can bite.
--
-- Every row shares one parent — the scroll child — so ONE conversion covers the
-- whole list, which is why the seam takes a single `listScale`.
--
-- Pure inputs: `childTop` is the scroll child's GetTop() in the LIST's own
-- space; `rowH` the row pitch (also list space); `count` how many rows are in
-- play; `cursorY` the RAW GetCursorPosition() Y; `listScale` the scroll child's
-- effective scale. Returns the insertion line, 1..count+1 (count+1 = "after the
-- last row"), always a whole number, never nil.
local Drag = {}
Addon.SetListDrag = Drag

function Drag.DropLine(childTop, rowH, count, cursorY, listScale)
    count = tonumber(count)
    count = count and math.floor(count) or 0
    if count < 1 then return 1 end

    childTop, cursorY, rowH = tonumber(childTop), tonumber(cursorY), tonumber(rowH)
    -- An unlaid-out list, a cursor the client has not reported yet, or a zero
    -- row pitch: answer "the head" rather than divide by zero or return nil into
    -- an arithmetic caller.
    if not childTop or not cursorY or not rowH or rowH <= 0 then return 1 end

    -- A scale is never 0 or negative in a live client; refuse to divide by one
    -- anyway rather than propagate an inf/NaN into the comparison.
    listScale = tonumber(listScale)
    if not listScale or listScale <= 0 then listScale = 1 end

    local y    = cursorY / listScale     -- the cursor, in the LIST's space
    local relY = childTop - y            -- how far below the list's top edge
    local hRow = math.floor(relY / rowH) -- rows fully above the cursor
    local frac = relY - hRow * rowH      -- how far into the row under the cursor

    -- Upper half of a row inserts BEFORE it, lower half AFTER it. The comparison
    -- is strict, so a cursor exactly on a row's midpoint resolves one way only
    -- and the drop bar cannot flicker between two slots.
    local line = (frac < rowH / 2) and (hRow + 1) or (hRow + 2)

    if line ~= line then return 1 end    -- NaN in (inf - inf), never out
    if line < 1 then return 1 end
    if line > count + 1 then return count + 1 end
    return line
end

-- Shared re-tinting FontObjects created by DaseekiUI (theme.lua). Referencing the
-- global names keeps custom FontStrings themed — they re-color on ThemeChanged.
local F_BODY, F_SMALL = "DaseekiUIFontBody", "DaseekiUIFontSmall"

local function rowGap() return (DaseekiUI.Token and DaseekiUI.Token("rowGap")) or 10 end

-- Add a caller-built custom frame to a flow's pane as one block. `arrange(avail)`
-- sizes/positions the frame's children and returns its height; the flow places it
-- at the running cursor (top-level indent 0 — these blocks span the full pane).
local function addBlock(flow, frame, arrange, topGap)
    flow.pane:AddBlock(frame, arrange, topGap or rowGap(), 0)
end

-- A flow row that can collapse to zero height (and swallow its top gap) when not
-- applicable, so the Set Swapper's mode-dependent controls leave no gap once
-- hidden. Reflow by setting applicability then calling flow.pane:Layout().
local function condRow(flow)
    local row = flow:AddRow()
    local blk = flow.pane.blocks[#flow.pane.blocks]
    row._blk, row._baseGap = blk, blk.topGap
    local origArrange = blk.arrange
    -- `row._arrange`, if the caller installs one, replaces the default left-to-right
    -- row layout while KEEPING the collapse behaviour above (a custom arrange assigned
    -- straight onto blk.arrange would clobber this wrapper).
    blk.arrange = function(width)
        if row._applicable == false then row:Hide(); return 0 end
        row:Show(); return (row._arrange or origArrange)(width)
    end
    function row:SetApplicable(on)
        self._applicable = on and true or false
        self._blk.topGap = self._applicable and self._baseGap or 0
    end
    return row
end

-- One Set-Swapper column caption: a muted SMALL label sized to the exact grid column
-- so its text centers over its own dropdown and can neither truncate nor spill into
-- the neighbouring column. Shared by both dropdown trios in the Set Swapper block.
local function swapCaption(row, text)
    local lb = row:Label(text, { muted = true })
    lb._label:SetFontObject(F_SMALL)
    lb._label:SetWidth(SWAP_DD)          -- fill the 92px column so the text can center in it
    lb._label:SetJustifyH("CENTER")      -- center each caption over its own dropdown
    lb.uiWidth = SWAP_DD; lb:SetWidth(SWAP_DD)
    return lb
end

-- ── Confirmation dialogs ──────────────────────────────────────────────────────
StaticPopupDialogs["DASEEKI_ARMORY_DELETE"] = {
    text = "Delete armory set \"%s\"?",
    button1 = YES, button2 = NO,
    OnAccept = function(_, data)
        Addon:DeleteSet(data)
        if Addon.panel then Addon.panel.selectedSet = nil end
        Addon:RefreshOptions(); Addon:RefreshWidget()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
}
StaticPopupDialogs["DASEEKI_ARMORY_KEYBIND"] = {
    text = "Bind %s to set \"%s\"?",
    button1 = YES, button2 = NO,
    OnAccept = function(_, data) Addon:SetSetKeybind(data.name, data.key) end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
StaticPopupDialogs["DASEEKI_ARMORY_IRIMPORT"] = {
    text = "Import %d set(s) from ItemRack?\nArmory sets with the same name will be overwritten.",
    button1 = YES, button2 = NO,
    OnAccept = function()
        local ok, res = Addon:ImportFromItemRack()
        if ok then
            print(Addon:Tag() .. " imported " ..res .. " set(s) from ItemRack.")
            if Addon.panel then Addon.panel.selectedSet = nil end
            Addon:RefreshOptions(); Addon:RefreshWidget()
        else
            print(Addon:Tag() .. " " ..tostring(res))
        end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
}

-- ── Section builders (registered with Core as the Armory sub-tabs) ────────────
-- Each Core section's build(flow) receives the DaseekiUI flow. The Sets section
-- owns the shared builder state on Addon.panel (== its flow; extra fields hung on
-- it) that the Refresh* helpers read.
Addon.frames = Addon.frames or {}

function Addon:BuildSetsSection(flow)
    Addon.frames.sets = flow
    Addon.panel = flow
    flow.rows = {}
    flow.slotButtons = {}
    -- async item-info refresh (textures/model fill in once the client caches items)
    flow.evt = CreateFrame("Frame")
    flow.evt:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    flow.evt:SetScript("OnEvent", function()
        if flow.pane:IsVisible() then Addon:RefreshBuilder() end
    end)
    Addon:BuildSetsTab(flow)
end

function Addon:BuildCharWindowSection(flow)
    Addon.frames.charwin = flow
    Addon:BuildCharWindowTab(flow)
end

function Addon:BuildWidgetsSection(flow)
    Addon.frames.widgets = flow
    Addon:BuildWidgetsTab(flow)
end

-- ══ Set Swapper (on-screen radial/dropdown switcher + global options) ═════════
-- Round-5: folded into the Sets tab's left column. build(flow) lays the whole
-- swapper config under ONE in-pane "Set Swapper" section header (the pre-migration
-- "Display"/"General" sub-headers are dropped so it stays compact in the ~300px
-- column). Every control + conditional collapse is preserved.
function Addon:BuildSetSwapperTab(flow)
    Addon.frames.swapper = flow
    local w = Addon.db.settings.widget

    flow:AddSection("Set Swapper")
    flow:Hint("One-click set-swap widget.")

    -- Row 1 — Enable / Lock / Chat Messages distributed space-between across the
    -- MGMT_GRID (292): first flush left, last flush right, the middle evenly gapped, so
    -- the three checkbox columns line up with the three SWAP_DD dropdown columns below.
    -- "Chat Messages" (too wide for a 92px grid column) is the right-flush item, so it
    -- never overflows. The old "Print a message…" hint that stood under Chat Messages no
    -- longer has a row of its own in the compact layout, so it becomes its hover tooltip.
    local cbRow = flow:AddRow()
    local cbItems = {
        cbRow:Checkbox({
            label = "Enable",
            get = function() return Addon.db.settings.widget.show end,
            set = function(v) Addon:SetWidgetShown(v) end,
        }),
        cbRow:Checkbox({
            label = "Lock",
            get = function() return Addon.db.settings.widget.locked end,
            set = function(v) Addon.db.settings.widget.locked = v and true or false end,
        }),
        cbRow:Checkbox({
            label = "Chat Messages",
            get = function() return Addon.db.settings.chatMessages end,
            set = function(v) Addon.db.settings.chatMessages = v and true or false end,
            tooltip = "Print a message when a set or item swap is queued for after combat.",
        }),
    }
    -- The flow row API has only a left run / centered run / right-pin — no space-between —
    -- so distribute this row ourselves by overriding its block arrange (the same
    -- reach-into-the-last-block pattern used for the header→dropdown gap just below).
    -- Both frame dimensions are set; no negative-y offsets.
    flow.pane.blocks[#flow.pane.blocks].arrange = function(width)
        cbRow:SetWidth(math.max(width, 1))
        local span = math.min(MGMT_GRID, width)   -- distribute within the 292 grid, not the wider column
        local totalW, h = 0, 0
        for _, cb in ipairs(cbItems) do
            totalW = totalW + (cb.uiWidth or cb:GetWidth())
            h = math.max(h, cb.uiHeight or cb:GetHeight())
        end
        local n = #cbItems
        local gap = (n > 1) and math.max(0, (span - totalW) / (n - 1)) or 0
        local x = 0
        for _, cb in ipairs(cbItems) do
            local ww = cb.uiWidth or cb:GetWidth()
            cb:ClearAllPoints()
            cb:SetPoint("LEFT", cbRow, "LEFT", x, 0)
            cb:SetWidth(ww)
            x = x + ww + gap
        end
        cbRow:SetHeight(math.max(h, 1))
        return math.max(h, 1)
    end

    -- Row 2 — Open On / Display Mode / Tooltips as three equal ~92px columns sharing
    -- the management grid's edges: a muted-small header row over a row of unlabeled
    -- dropdowns. Each header label fills its 92px column and center-justifies, so it sits
    -- centered over its own dropdown (same pattern as the char-window flyout headers).
    local ddHdr = flow:AddRow()
    swapCaption(ddHdr, "Open On"); swapCaption(ddHdr, "Display Mode"); swapCaption(ddHdr, "Tooltips")

    local ddRow = flow:AddRow()
    -- Tighten the header→dropdown gap so each label reads as attached to its column.
    flow.pane.blocks[#flow.pane.blocks].topGap = 2
    ddRow:Dropdown({
        width = SWAP_DD, choices = { "Click", "Hover" },
        get = function() return w.openTrigger == "hover" and "Hover" or "Click" end,
        set = function(v) w.openTrigger = v:lower() end,
    })
    ddRow:Dropdown({
        width = SWAP_DD, choices = { "Radial", "Dropdown" },
        get = function() return w.mode == "dropdown" and "Dropdown" or "Radial" end,
        set = function(v)
            w.mode = (v == "Dropdown") and "dropdown" or "radial"
            Addon:RefreshSwapperTab(); Addon:RefreshWidget()
        end,
    })
    ddRow:Dropdown({
        width = SWAP_DD, choices = { "On Ctrl", "Always" },
        get = function() return Addon.db.settings.flyoutTooltip == "always" and "Always" or "On Ctrl" end,
        set = function(v) Addon.db.settings.flyoutTooltip = (v == "Always") and "always" or "ctrl" end,
    })

    -- Row 3 — Type / Direction / Sets Per Row on ONE row (owner directive): three
    -- columns on the same 92px grid as the trio above, each a caption over its own
    -- dropdown, replacing the three stacked label-left rows this used to be.
    --
    -- Built as ONE block with its own arrange (the flow row API lays items
    -- left-to-right on a single baseline and has no "stack a caption above a control"
    -- primitive) — the same construction Nexus's Setup identity row uses. One block
    -- means a caption can never drift out of sync with its dropdown, and the columns
    -- are divided once from the real width.
    local optRow  = condRow(flow)
    local optCols = {}
    local function optCol(caption, ddOpts)
        ddOpts.width = SWAP_DD
        local col = { cap = swapCaption(optRow, caption), dd = optRow:Dropdown(ddOpts) }
        optCols[#optCols + 1] = col
        return col
    end
    optCol("Type", {
        choices = { "Icon", "List" },
        get = function() return w.dropdownType == "list" and "List" or "Icon" end,
        set = function(v)
            w.dropdownType = v:lower()
            Addon:RefreshSwapperTab(); Addon:RefreshWidget()
        end,
    })
    optCol("Direction", {
        choices = { "Right", "Left", "Down", "Up" },
        get = function() return cap(w.dropdownDir or "right") end,
        set = function(v) w.dropdownDir = v:lower(); Addon:RefreshWidget() end,
    })
    optCol("Sets Per Row", {
        choices = PERROW,
        get = function() return tostring(w.dropdownPerRow or 5) end,
        set = function(v) w.dropdownPerRow = tonumber(v); Addon:RefreshWidget() end,
    })
    optRow._cols = optCols

    -- Even three-column division of the same management grid the rows above share, so
    -- this trio lines up with the Open On / Display Mode / Tooltips trio exactly. Both
    -- frame dimensions are set and no offset is negative-x. MakeDropdown sizes its
    -- button at construction (SWAP_DD), so the columns are authored at that width and
    -- this arrange divides/places them; the caption gets the column width so its
    -- centered text always stays inside its own column.
    optRow._arrange = function(width)
        optRow:SetWidth(math.max(width, 1))
        local avail = math.max(1, width - optRow._indent)
        local span  = math.min(MGMT_GRID, avail)   -- distribute within the 292 grid
        local colW  = math.max(1, (span - 2 * ITEM_GAP) / 3)
        for i, c in ipairs(optCols) do
            local x = optRow._indent + (i - 1) * (colW + ITEM_GAP)
            c.cap:ClearAllPoints()
            c.cap:SetPoint("TOPLEFT", optRow, "TOPLEFT", x, 0)
            c.cap:SetWidth(colW); c.cap._label:SetWidth(colW)
            c.dd:ClearAllPoints()
            c.dd:SetPoint("TOPLEFT", optRow, "TOPLEFT", x, -(DD_CAP_H + DD_CAP_GAP))
            c.dd:SetWidth(colW)
        end
        local h = DD_CAP_H + DD_CAP_GAP + DD_BTN_H
        optRow:SetHeight(h)
        return h
    end

    local alwaysRow = condRow(flow)
    alwaysRow:Checkbox({
        label = "Always Open",
        get = function() return w.dropdownAlwaysOpen end,
        set = function(v)
            w.dropdownAlwaysOpen = v and true or false
            Addon:RefreshWidget()
        end,
    })
    flow._condRows = { opts = optRow, always = alwaysRow }

    Addon:RefreshSwapperTab()
end

-- Show only the rows relevant to the current Mode/Type (Type+Direction+PerRow are
-- meaningless in Radial mode; Direction/PerRow/AlwaysOpen only apply to Icon type),
-- then reflow so hidden rows leave no gap.
function Addon:RefreshSwapperTab()
    local flow = Addon.frames and Addon.frames.swapper
    if not (flow and flow._condRows) then return end
    local w = Addon.db.settings.widget
    local isDropdown = w.mode == "dropdown"
    local isIcon     = isDropdown and w.dropdownType ~= "list"
    -- The Type/Direction/Sets-Per-Row row applies whenever the widget is a dropdown;
    -- within it, Direction and Sets Per Row are Icon-only, so those two COLUMNS hide
    -- individually. The column geometry is fixed, so Type never moves when they do.
    local optRow = flow._condRows.opts
    optRow:SetApplicable(isDropdown)
    for i = 2, 3 do
        local c = optRow._cols and optRow._cols[i]
        if c then c.cap:SetShown(isIcon); c.dd:SetShown(isIcon) end
    end
    flow._condRows.always:SetApplicable(isIcon)
    -- The swapper now lives in the Sets tab's left column, so reflow the OUTER Sets
    -- scroll pane (re-runs the split arrange → re-lays both columns + scroll range)
    -- rather than the column, which has no width to lay itself standalone.
    if Addon.panel and Addon.panel.pane then Addon.panel.pane:Layout() end
end

-- ══ Sets — set list + paper-doll set builder ══════════════════════════════════

-- Custom leading widget: slot/item icon + name label, sized to a fixed column
-- width so the flyout table's columns line up under their headers.
local function slotLead(parent, sid, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, 24)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(20, 20)
    f.icon:SetPoint("LEFT", f, "LEFT", 0, 0)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.icon:SetTexture(GetInventoryItemTexture("player", sid) or slotEmptyTex(sid))
    f.label = f:CreateFontString(nil, "OVERLAY")
    f.label:SetFontObject(F_BODY)
    f.label:SetPoint("LEFT", f.icon, "RIGHT", 6, 0)
    f.label:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    f.label:SetJustifyH("LEFT"); f.label:SetWordWrap(false)
    f.label:SetText(slotName(sid))
    f.uiWidth, f.uiHeight = width, 24
    return f
end

-- The scrolling set list (icons + name + keybind, selection highlight, and the
-- cursor-poll drag-to-reorder). Token-skinned; added as one flow block.
local function buildSetList(flow, panel)
    local UI = DaseekiUI
    local host = UI.FlatFrame(flow.pane.child, "inset", "border")
    host.uiHeight, host._fillWidth = SETLIST_H, true

    local scroll = CreateFrame("ScrollFrame", "DaseekiArmorySetScroll", host)
    scroll:SetPoint("TOPLEFT", host, "TOPLEFT", LIST_INSET, -LIST_INSET)
    scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -LIST_INSET, LIST_INSET)
    scroll:SetClipsChildren(true)
    scroll:EnableMouseWheel(true)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxs = math.max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxs, cur - delta * 24)))
    end)
    panel.listChild, panel.listScroll = child, scroll

    -- Empty-state line (shown by RefreshSetList when there are no sets).
    host.empty = host:CreateFontString(nil, "OVERLAY")
    host.empty:SetFontObject(F_SMALL)
    host.empty:SetPoint("TOPLEFT", host, "TOPLEFT", LIST_INSET + 4, -(LIST_INSET + 6))
    host.empty:SetText("No sets yet — click New")
    host.empty:Hide()
    panel.listEmpty = host.empty

    -- Drag-to-reorder: a plain drag/release between two Buttons never fires
    -- OnReceiveDrag (that only fires for cursor-item drops) and GetMouseFocus is
    -- unreliable here, so poll cursor position instead — same pattern as
    -- Daseeki-Buff-Tracker's working item-list reorder.
    local dropBar = child:CreateTexture(nil, "OVERLAY")
    dropBar:SetHeight(2); dropBar:Hide()
    UI.Skin(dropBar, function(self) self:SetColorTexture(UI.Color("accent")) end)
    panel.dropBar = dropBar

    local dragTick = CreateFrame("Frame"); dragTick:Hide()
    dragTick:SetScript("OnUpdate", function()
        local srcName = panel._dragSourceName
        if not srcName then dragTick:Hide(); return end
        local cx, cy = GetCursorPosition()

        -- UIParent's space is the right one HERE and only here: the movement
        -- threshold below is a SCREEN gesture ("has the mouse moved far enough
        -- to mean a drag?"), and the anchor it is measured against was captured
        -- in this same space in the row's OnMouseDown. Both sides must agree;
        -- neither may reach the hit-test, which lives in the LIST's space.
        local uiScale = UIParent:GetEffectiveScale()
        if not uiScale or uiScale <= 0 then uiScale = 1 end
        local uiMX, uiMY = cx / uiScale, cy / uiScale

        if not IsMouseButtonDown("LeftButton") then
            dragTick:Hide(); dropBar:Hide()
            if panel._dragging and panel._dragDropLine then
                local sets = Addon:GetSetsSorted()
                local target = sets[panel._dragDropLine]
                Addon:ReorderSet(srcName, target and target.name or nil)
                Addon:RefreshOptions(); Addon:RefreshWidget()
            end
            panel._dragSourceName, panel._dragging, panel._dragDropLine = nil, false, nil
            return
        end

        if not panel._dragging then
            local dx, dy = uiMX - (panel._dragClickX or uiMX), uiMY - (panel._dragClickY or uiMY)
            if dx * dx + dy * dy < 25 then return end
            panel._dragging = true
        end

        local childTop = child:GetTop()
        if not childTop then return end
        local n = #Addon:GetSetsSorted()
        if n == 0 then return end

        -- A DIFFERENT SPACE: child:GetTop() and SET_ROW_H are both expressed in
        -- the scroll child's own effective scale, so the RAW cursor is converted
        -- with the CHILD's scale — never with uiMY above. See Drag.DropLine.
        local listScale = child:GetEffectiveScale()
        local line = Drag.DropLine(childTop, SET_ROW_H, n, cy, listScale)
        panel._dragDropLine = line

        dropBar:ClearAllPoints()
        dropBar:SetPoint("TOPLEFT",  child, "TOPLEFT",  0, -(line - 1) * SET_ROW_H)
        dropBar:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -(line - 1) * SET_ROW_H)
        dropBar:Show()
    end)
    panel._dragTick = dragTick

    host.arrange = function(width)
        host:SetWidth(width)
        host:SetHeight(SETLIST_H)   -- ROUND-3 BUG FIX: without an explicit height the
        -- FlatFrame defaults to 0px tall, so its backdrop, the /daseekiui debug outline
        -- (SetAllPoints host), the scroll viewport (anchored to host) and every set row
        -- inside it are culled — the ~250px blank band the owner saw. The cursor still
        -- advances by the returned SETLIST_H, which is why the space was reserved.
        child:SetWidth(math.max(1, width - 2 * LIST_INSET))
        return SETLIST_H
    end
    return host
end

-- The paper-doll set builder: two columns of equip slots flanking a 3D model,
-- weapons across the bottom. Custom token-skinned frame; width-relative layout
-- (centered model, right column pinned to the right edge) so it reflows.
local function buildPaperdoll(flow, panel)
    local UI = DaseekiUI
    local pd = CreateFrame("Frame", nil, flow.pane.child)
    pd._fillWidth = true

    local model = CreateFrame("DressUpModel", nil, pd)
    model:SetSize(MODEL_W, MODEL_H)
    model:SetUnit("player"); model:EnableMouse(true)
    model:SetScript("OnMouseDown", function(self) self._rot = true; self._mx = GetCursorPosition() end)
    model:SetScript("OnMouseUp",   function(self) self._rot = false end)
    model:SetScript("OnUpdate", function(self)
        if self._rot then
            local x = GetCursorPosition()
            self._facing = (self._facing or 0) + (x - (self._mx or x)) * 0.02
            self._mx = x; self:SetFacing(self._facing)
        end
    end)
    panel.model = model

    -- Hover a slot → open the item flyout to choose what goes in it. If the slot
    -- already has an item, also show its tooltip to the right (may overlap the
    -- flyout — deliberate; reads better next to the slot).
    local function slotEnter(self)
        local name = panel.selectedSet
        if not name then return end
        local slotId = self._slotId
        local set = Addon.db.sets[name]
        local uneq
        local entry   = set and set.equip[slotId]
        local isEmpty = entry ~= nil and Addon:IsEmptyEntry(entry)
        if entry then
            uneq = { fn = function() Addon:ClearSlot(name, slotId); Addon:RefreshBuilder() end,
                     label = "Remove from set" }
        end
        -- An explicit-empty slot has no item to describe, so the tooltip explains
        -- the state and the gesture instead; a slot that is not in the set at all
        -- advertises the gesture. Only ever Show() a tooltip we actually own.
        local shown = false
        if isEmpty then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self._slotName or "Slot", 1, 1, 1)
            GameTooltip:AddLine("Must be EMPTY: this set takes off whatever is worn here.", 1, 0.5, 0)
            GameTooltip:AddLine("Shift-click: stop governing this slot", 0.5, 0.5, 0.5)
            shown = true
        elseif entry then
            local link = Addon:EntryLink(entry)
            if link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(link)
                shown = true
            end
        else
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self._slotName or "Slot", 1, 1, 1)
            GameTooltip:AddLine("Shift-click: require this slot to be empty", 0.5, 0.5, 0.5)
            shown = true
        end
        if shown then GameTooltip:Show() end
        Addon:ShowItemFlyout(self, slotId, function(item)
            Addon:SetSlotFromLink(name, slotId, item.link)
            if set and set.disabled then set.disabled[slotId] = nil end
            Addon:RefreshBuilder()
        end, uneq, nil, true)  -- include currently-equipped items in the builder
    end
    -- Shift+Left-click toggles the explicit-empty marker (spec §1.2: a slot the
    -- set deliberately strips, distinct from a slot it simply ignores).
    -- Right-click disables the slot; Shift+Right-click clears it.
    local function slotClick(self, button)
        local name = panel.selectedSet
        if not name then return end
        if button == "LeftButton" then
            if not IsShiftKeyDown() then return end
            Addon:ToggleSlotEmpty(name, self._slotId)
            Addon:HideItemFlyout()
            Addon:RefreshBuilder()
            return
        end
        if button ~= "RightButton" then return end
        if IsShiftKeyDown() then Addon:ClearSlot(name, self._slotId)
        else Addon:ToggleSlotDisabled(name, self._slotId) end
        Addon:RefreshBuilder()
    end
    local function slotReceiveDrag(self)
        local name = panel.selectedSet
        if not name then return end
        local ctype, _, link = GetCursorInfo()
        if ctype == "item" and link then
            Addon:SetSlotFromLink(name, self._slotId, link)
            local set = Addon.db.sets[name]
            if set and set.disabled then set.disabled[self._slotId] = nil end
            ClearCursor(); Addon:RefreshBuilder()
        end
    end
    local function makeSlot(slotDef)
        local slotId = slotDef.id
        local b = CreateFrame("Button", nil, pd)
        b:SetSize(SLOT_SZ, SLOT_SZ)
        b:SetFrameLevel(model:GetFrameLevel() + 4)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b._emptyTex = Addon:GetSlotEmptyTexture(slotDef)
        b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
        UI.Skin(b.bg, function(self) self:SetColorTexture(UI.Color("inset", 0.85)) end)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints(); b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.glow = b:CreateTexture(nil, "OVERLAY")
        b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        b.glow:SetBlendMode("ADD")
        b.glow:SetPoint("CENTER"); b.glow:SetSize(54, 54); b.glow:Hide()
        UI.Skin(b.glow, function(self) self:SetVertexColor(UI.Color("danger")) end)
        b.off = b:CreateTexture(nil, "OVERLAY"); b.off:SetAllPoints(); b.off:Hide()
        UI.Skin(b.off, function(self) self:SetColorTexture(UI.Color("ground", 0.65)) end)
        -- explicit-empty marker: the same red X the flyout uses for "take off",
        -- badged bottom-left so an emptied slot reads differently from an ignored
        -- one and from a slot that is simply not in the set (spec §5.2)
        b.emptyMark = b:CreateTexture(nil, "OVERLAY", nil, BADGE_SUBLEVEL)
        b.emptyMark:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        b.emptyMark:SetSize(16, 16)
        b.emptyMark:SetPoint("BOTTOMLEFT", -CHECK_INSET, -CHECK_INSET)
        b.emptyMark:Hide()
        -- goal obtained check (bottom-right)
        b.check = b:CreateTexture(nil, "OVERLAY", nil, BADGE_SUBLEVEL)
        b.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        b.check:SetSize(16, 16); b.check:SetPoint("BOTTOMRIGHT", CHECK_INSET, -CHECK_INSET); b.check:Hide()
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints()
        UI.Skin(hl, function(self) self:SetColorTexture(UI.Color("accent", 0.25)) end)
        b._slotId, b._slotName = slotDef.id, slotDef.name
        b:SetScript("OnClick", slotClick)
        b:SetScript("OnReceiveDrag", slotReceiveDrag)
        b:SetScript("OnEnter", slotEnter)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        panel.slotButtons[slotDef.id] = b

        -- goal "chase list" button on the inside edge (toward the model)
        local g = CreateFrame("Button", nil, b)
        g:SetSize(GOAL_SZ, GOAL_SZ)
        g:SetFrameLevel(b:GetFrameLevel() + 3)
        if slotDef.col == "L" then     g:SetPoint("LEFT",   b, "RIGHT", 3, 0)
        elseif slotDef.col == "R" then g:SetPoint("RIGHT",  b, "LEFT", -3, 0)
        else                            g:SetPoint("BOTTOM", b, "TOP",   0, 3) end
        g:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        g.bg = g:CreateTexture(nil, "BACKGROUND"); g.bg:SetAllPoints()
        UI.Skin(g.bg, function(self) self:SetColorTexture(UI.Color("inset", 0.9)) end)
        g.icon = g:CreateTexture(nil, "ARTWORK"); g.icon:SetAllPoints(); g.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        g.plus = g:CreateFontString(nil, "OVERLAY")
        g.plus:SetFontObject(F_BODY)
        g.plus:SetPoint("CENTER"); g.plus:SetText("+")
        UI.Skin(g.plus, function(self) self:SetTextColor(UI.Color("ok")) end)
        local ghl = g:CreateTexture(nil, "HIGHLIGHT"); ghl:SetAllPoints()
        UI.Skin(ghl, function(self) self:SetColorTexture(UI.Color("ok", 0.3)) end)
        g:SetScript("OnClick", function(self, button)
            local name = panel.selectedSet
            if not name then return end
            if button == "RightButton" then Addon:ClearGoal(name, slotId); Addon:RefreshBuilder(); return end
            Addon:ShowGoalPicker(slotId, function(itemId)
                Addon:SetGoal(name, slotId, itemId)
                Addon:CheckGoals()
                Addon:RefreshBuilder()
            end)
        end)
        g:SetScript("OnEnter", function(self)
            local set = panel.selectedSet and Addon.db.sets[panel.selectedSet]
            local goal = set and Addon:GetGoal(set, slotId)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if goal then
                local link = Addon:EntryLink(goal)
                if link then GameTooltip:SetHyperlink(link) end
                GameTooltip:AddLine("Goal item", 0.6, 0.9, 0.6)
            else
                GameTooltip:AddLine(slotDef.name .. " goal", 1, 1, 1)
                GameTooltip:AddLine("Click to set a goal item", 0.7, 0.7, 0.7)
            end
            GameTooltip:AddLine("Right-click: clear goal", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        g:SetScript("OnLeave", function() GameTooltip:Hide() end)
        g:Hide()
        b.goalBtn = g
    end

    for _, slotDef in ipairs(Addon.SLOTS) do
        if slotDef.col == "L" or slotDef.col == "R" or slotDef.col == "W" then makeSlot(slotDef) end
    end

    -- Composed arrange: a fixed-width builder band (PD_W) centered within the content
    -- width. Columns anchor to the band edges (never the pane edges); model centered
    -- in the band; weapons centered across the bottom. Reflows with the content width.
    pd.arrange = function(width)
        pd:SetWidth(width)
        local inner = math.min(PD_W, width)          -- fixed band, clamped to available
        local ox    = math.max(0, (width - inner) / 2)   -- left offset that centers it
        local colH  = COL_ROWS * SLOT_STEP
        local bodyH = math.max(colH, MODEL_H)

        model:ClearAllPoints()
        model:SetPoint("TOP", pd, "TOPLEFT", ox + inner / 2, 0)   -- centered in the band

        local li, ri = 0, 0
        for _, slotDef in ipairs(Addon.SLOTS) do
            local b = panel.slotButtons[slotDef.id]
            if b then
                b:ClearAllPoints()
                if slotDef.col == "L" then
                    b:SetPoint("TOPLEFT", pd, "TOPLEFT", ox, -(li * SLOT_STEP)); li = li + 1
                elseif slotDef.col == "R" then
                    b:SetPoint("TOPLEFT", pd, "TOPLEFT", ox + inner - SLOT_SZ, -(ri * SLOT_STEP)); ri = ri + 1
                end
            end
        end

        local weapons = { 16, 17, 18 }
        local totalW = #weapons * SLOT_SZ + (#weapons - 1) * WPN_XGAP
        local startX = ox + math.max(0, (inner - totalW) / 2)
        local wy = bodyH + WPN_GAP
        for idx, sid in ipairs(weapons) do
            local b = panel.slotButtons[sid]
            if b then
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", pd, "TOPLEFT", startX + (idx - 1) * (SLOT_SZ + WPN_XGAP), -wy)
            end
        end

        local total = wy + SLOT_SZ
        pd:SetHeight(total)
        return total
    end
    return pd
end

function Addon:BuildSetsTab(flow)
    local UI = DaseekiUI
    local panel = Addon.panel

    -- Two-pane composition: one split block hosts a left column (the set list +
    -- management) and a right column (the set builder). They render side-by-side when
    -- the effective content width >= SPLIT_MIN, and stack vertically below that. The
    -- split re-arranges automatically on pane resize (the outer pane re-runs its
    -- arrange), and each column sizes itself to its content (the outer pane scrolls).
    local split = CreateFrame("Frame", nil, flow.pane.child)
    local leftCol  = UI.CreateColumn(split)
    local rightCol = UI.CreateColumn(split)
    panel.leftCol, panel.rightCol = leftCol, rightCol
    local L, R = leftCol.flow, rightCol.flow

    -- ── Left column: set list (own scroll + empty state) + management ─────────
    L:AddSection("Armory Sets")
    local listHost = buildSetList(L, panel)
    addBlock(L, listHost, listHost.arrange, rowGap())

    -- New / Duplicate / Rename / Delete — two rows of two so they fit the ~300px column.
    local crud1 = L:AddRow()
    crud1:Button({ text = "New", width = MGMT_BTN, onClick = function()
        _G.DaseekiSuite.ShowNameInputDialog("New Set", "", function(v)
            local ok, err = Addon:CreateSet(v)
            if ok then panel.selectedSet = v; Addon:RefreshOptions(); Addon:RefreshWidget()
            else print(Addon:Tag() .. " " ..tostring(err)) end
        end)
    end })
    crud1:Button({ text = "Duplicate", width = MGMT_BTN, onClick = function()
        if not panel.selectedSet then return end
        local ok, res = Addon:DuplicateSet(panel.selectedSet)
        if ok then panel.selectedSet = res; Addon:RefreshOptions(); Addon:RefreshWidget()
        else print(Addon:Tag() .. " " ..tostring(res)) end
    end })
    local crud2 = L:AddRow()
    crud2:Button({ text = "Rename", width = MGMT_BTN, onClick = function()
        if not panel.selectedSet then return end
        _G.DaseekiSuite.ShowNameInputDialog("Rename Set", panel.selectedSet, function(v)
            local ok, err = Addon:RenameSet(panel.selectedSet, v)
            if ok then panel.selectedSet = v; Addon:RefreshOptions(); Addon:RefreshWidget()
            else print(Addon:Tag() .. " " ..tostring(err)) end
        end)
    end })
    crud2:Button({ text = "Delete", width = MGMT_BTN, onClick = function()
        if panel.selectedSet then StaticPopup_Show("DASEEKI_ARMORY_DELETE", panel.selectedSet, nil, panel.selectedSet) end
    end })

    L:AddSeparator()
    L:Hint("Clone to another character")
    -- Export / Import as a matching 2-up row (same button width + edges as the CRUD
    -- grid above), and "Import from ItemRack" spanning the full grid width below it.
    local io1 = L:AddRow()
    io1:Button({ text = "Export Sets", width = MGMT_BTN, onClick = function()
        _G.DaseekiSuite.ShowTextDialog("Export Armory Sets", Addon:ExportSets(), true)
    end })
    io1:Button({ text = "Import Sets", width = MGMT_BTN, onClick = function()
        _G.DaseekiSuite.ShowTextDialog("Import Armory Sets", "", false, function(text)
            local ok, res = Addon:ImportSets(text)
            if ok then print(Addon:Tag() .. " imported " ..res .. " set(s).")
                Addon:RefreshOptions(); Addon:RefreshWidget()
            else print(Addon:Tag() .. " " ..tostring(res)) end
        end)
    end })
    L:AddRow():Button({ text = "Import from ItemRack", width = MGMT_GRID, onClick = function()
        local n = Addon:CountItemRackSets()
        if n == 0 then print(Addon:Tag() .. " no ItemRack sets found — make sure ItemRack is enabled."); return end
        StaticPopup_Show("DASEEKI_ARMORY_IRIMPORT", n)
    end })

    -- Set Swapper config folded into this left column (round-5) — below the
    -- management buttons, under its own "Set Swapper" section header. The whole
    -- pane scrolls, so the added height stays reachable.
    Addon:BuildSetSwapperTab(L)

    -- ── Right column: set builder ─────────────────────────────────────────────
    -- Round-5 item B: the "Set name" caption row was removed — it was the blank band
    -- under the "Set Builder" header. The icon/name row now sits one rowGap below it.
    R:AddSection("Set Builder")

    -- icon button + name edit box on one row (centered in the builder column, and
    -- vertically centered against each other so the 24px EditBox sits mid-height of
    -- the 46px icon button instead of tops-aligned).
    local headRow = R:AddRow({ align = "center", vAlign = "center" })
    local iconBtn = CreateFrame("Button", nil, headRow, "BackdropTemplate")
    iconBtn:SetSize(46, 46)
    UI.Skin(iconBtn, function(self)
        self:SetBackdrop(UI.FLAT_BACKDROP)
        self:SetBackdropColor(UI.Color("inset"))
        self:SetBackdropBorderColor(UI.Color("controlBorder"))
    end)
    iconBtn.icon = iconBtn:CreateTexture(nil, "ARTWORK")
    iconBtn.icon:SetPoint("TOPLEFT", IB, -IB)
    iconBtn.icon:SetPoint("BOTTOMRIGHT", -IB, IB)
    iconBtn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local ihl = iconBtn:CreateTexture(nil, "HIGHLIGHT"); ihl:SetAllPoints()
    UI.Skin(ihl, function(self) self:SetColorTexture(UI.Color("accent", 0.25)) end)
    iconBtn.uiWidth, iconBtn.uiHeight = 46, 46
    iconBtn:SetScript("OnClick", function()
        local set = panel.selectedSet and Addon.db.sets[panel.selectedSet]
        if not set then return end
        Addon:ShowIconPicker(set.icon, function(tex)
            Addon:SetIcon(panel.selectedSet, tex)
            Addon:RefreshOptions(); Addon:RefreshWidget()
        end)
    end)
    iconBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Set icon", 1, 1, 1)
        GameTooltip:AddLine("Click to choose an icon", 0.7, 0.7, 0.7); GameTooltip:Show()
    end)
    iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    headRow._items[#headRow._items + 1] = { w = iconBtn }
    panel.iconBtn = iconBtn

    panel.nameEB = headRow:EditBox({
        width = 240,   -- fixed so the icon+name pair has an intrinsic width to center
        get = function() return panel.selectedSet or "" end,
        set = function(v)
            v = strtrim(v or "")
            if panel.selectedSet and v ~= "" and v ~= panel.selectedSet then
                local ok, err = Addon:RenameSet(panel.selectedSet, v)
                if ok then panel.selectedSet = v; Addon:RefreshOptions(); Addon:RefreshWidget()
                else print(Addon:Tag() .. " " ..tostring(err)) end
            end
        end,
    })

    -- keybind + goals row (centered in the builder column)
    local kbRow = R:AddRow({ align = "center" })
    local kbBtn = kbRow:Button({ text = "Keybind: \194\183", width = 170 })
    kbBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    kbBtn:SetScript("OnClick", function(self, button)
        local name = panel.selectedSet
        if not name then return end
        if button == "RightButton" then
            Addon:SetSetKeybind(name, nil)
        else
            Addon:CaptureKeybind(function(combo)
                local warn, otherSet = "", nil
                for n, s in pairs(Addon.db.sets) do
                    if n ~= name and s.key == combo then otherSet = n; break end
                end
                if otherSet then
                    warn = "\n" .. Addon:Wrap("warn", "Already bound to Armory set \"" .. otherSet .. "\" — it will be reassigned.")
                else
                    local action = GetBindingAction and GetBindingAction(combo)
                    if action and action ~= "" then
                        warn = "\n" .. Addon:Wrap("warn", "Already bound to: " .. (_G["BINDING_NAME_" .. action] or action))
                    end
                end
                local txt = ("Bind %s to set \"%s\"?"):format(combo, name) .. warn
                StaticPopupDialogs["DASEEKI_ARMORY_KEYBIND"].text = txt:gsub("%%", "%%%%")
                StaticPopup_Show("DASEEKI_ARMORY_KEYBIND", nil, nil, { name = name, key = combo })
            end)
        end
    end)
    kbBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Set keybind", 1, 1, 1)
        GameTooltip:AddLine("Left-click: assign a key", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Right-click: clear", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    kbBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.kbBtn = kbBtn

    panel.goalsBtn = kbRow:Button({ text = "Set Goals", width = 140, onClick = function()
        panel.goalMode = not panel.goalMode
        Addon:RefreshBuilder()
    end })
    panel.goalsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Set Goals (chase list)", 1, 1, 1)
        GameTooltip:AddLine("Toggle goal editing. Set per-slot target items; when one lands", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("in your bags the set updates to it automatically.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    panel.goalsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- paper-doll slot grid + model
    local pd = buildPaperdoll(R, panel)
    addBlock(R, pd, pd.arrange, rowGap())

    -- action buttons (centered in the builder column)
    local actRow = R:AddRow({ align = "center" })
    panel.saveBtn = actRow:Button({ text = "Populate Current Gear", width = 150, onClick = function()
        if panel.selectedSet then Addon:SaveCurrentGear(panel.selectedSet); Addon:RefreshBuilder() end
    end })
    panel.equipBtn = actRow:Button({ text = "Equip Set", width = 90, onClick = function()
        if panel.selectedSet then Addon:EquipSet(panel.selectedSet) end
    end })
    panel.macroBtn = actRow:Button({ text = "Show Macro", width = 90, onClick = function()
        if panel.selectedSet then
            _G.DaseekiSuite.ShowTextDialog("Equip Macro — " .. panel.selectedSet, Addon:GetEquipMacro(panel.selectedSet), true)
        end
    end })

    -- Centered under the centered action-button row above (default hints left-align).
    local builderHint = R:Hint("Hover a slot to choose  \194\183  Right-click: disable  \194\183  Shift+Right: clear")
    builderHint._label:SetJustifyH("CENTER")

    -- ── Split arrange: side-by-side at >= SPLIT_MIN ───────────────────────────
    -- The hub minimum window width (Core MIN_W=1140) guarantees the composed content
    -- width (avail) is always >= SPLIT_MIN, so the two-pane branch is the only reachable
    -- one; the stacked branch below is kept as a defensive fallback (unreachable in
    -- practice) in case token/geometry changes ever shrink avail below SPLIT_MIN.
    split.arrange = function(width)
        split:SetWidth(width)
        if width >= SPLIT_MIN then
            local lw = SPLIT_LEFT
            local rw = math.max(1, width - lw - SPLIT_GAP)
            local lh = leftCol:Layout(lw)
            local rh = rightCol:Layout(rw)
            leftCol.frame:ClearAllPoints()
            leftCol.frame:SetPoint("TOPLEFT", split, "TOPLEFT", 0, 0)
            rightCol.frame:ClearAllPoints()
            rightCol.frame:SetPoint("TOPLEFT", split, "TOPLEFT", lw + SPLIT_GAP, 0)
            local total = math.max(lh, rh)
            split:SetHeight(math.max(total, 1))
            return total
        else
            local lh = leftCol:Layout(width)
            local rh = rightCol:Layout(width)
            leftCol.frame:ClearAllPoints()
            leftCol.frame:SetPoint("TOPLEFT", split, "TOPLEFT", 0, 0)
            rightCol.frame:ClearAllPoints()
            rightCol.frame:SetPoint("TOPLEFT", split, "TOPLEFT", 0, -(lh + SPLIT_GAP))
            local total = lh + SPLIT_GAP + rh
            split:SetHeight(math.max(total, 1))
            return total
        end
    end
    addBlock(flow, split, split.arrange, rowGap())
end

-- ══ Character Window flyouts (per slot) ═══════════════════════════════════════
-- Two columns mirroring the in-game character pane (Head..Wrist left, Hands..Trinket 2
-- right, per Addon.SLOTS col "L"/"R"), with the weapons (col "W") as a centered group
-- beneath. Built from UI.CreateColumn (the round-3 two-column primitive); the pane
-- still scrolls if the rows are taller than the window.
local CW_SLOT_W, CW_DIR_W, CW_PER_W = 150, 110, 70
local CW_COL_W = CW_SLOT_W + CW_DIR_W + CW_PER_W + 30   -- row content + inter-item gaps
local CW_COL_GAP = 24                                    -- gap between the two columns

-- Header row (Slot / Direction / Per row) for a column flow. Muted SMALL font; each
-- label is given its column's exact width so it sits directly over that dropdown
-- column (round-5 item A — the third label previously had no width and could cull).
local function charWinHeader(cflow)
    local hdr = cflow:AddRow()
    local function hcell(text, w)
        local lb = hdr:Label(text, { muted = true })
        lb._label:SetFontObject(F_SMALL)
        lb.uiWidth = w; lb:SetWidth(w)
        return lb
    end
    hcell("Slot", CW_SLOT_W)
    hcell("Direction", CW_DIR_W)
    hcell("Per row", CW_PER_W)
    cflow:AddSeparator()
end

-- One flyout config row (icon+name lead, Direction dropdown, Per-row dropdown).
local function charWinRow(cflow, sid)
    local row = cflow:AddRow()
    local lead = slotLead(row, sid, CW_SLOT_W)
    row._items[#row._items + 1] = { w = lead }
    row:Dropdown({
        width = CW_DIR_W, choices = { "Right", "Left", "Down", "Up" },
        get = function() return cap(Addon:GetFlyoutConfig(sid).dir) end,
        set = function(v) Addon:GetFlyoutConfig(sid).dir = v:lower() end,
    })
    row:Dropdown({
        width = CW_PER_W, choices = PERROW,
        get = function() return tostring(Addon:GetFlyoutConfig(sid).perRow) end,
        set = function(v) Addon:GetFlyoutConfig(sid).perRow = tonumber(v) end,
    })
end

function Addon:BuildCharWindowTab(flow)
    local UI = DaseekiUI
    flow:AddSection("Character Window Flyouts")
    flow:Hint("Item flyout shown when you hover an equipped slot on the character pane.")

    flow:Checkbox({
        label   = "Quality glow on equipped slots",
        get     = function() return Addon.db.settings.charWindow.qualityBorders end,
        set     = function(v)
            Addon.db.settings.charWindow.qualityBorders = v and true or false
            if Addon.UpdateSlotBorders then Addon:UpdateSlotBorders() end
        end,
        tooltip = "Soft quality-colored glow on the character-sheet items (and flyout entries), matching Daseeki Bags. Uncommon and above only.",
    })

    flow:Checkbox({
        label   = "Trinket cooldown readouts",
        get     = function() return Addon.db.settings.trinkets.showCooldowns end,
        set     = function(v)
            Addon.db.settings.trinkets.showCooldowns = v and true or false
            if Addon.UpdateTrinketCooldowns then Addon:UpdateTrinketCooldowns() end
        end,
        tooltip = "Cooldown sweep and a countdown on the two trinket slots, their detached popout buttons, and trinket entries in the item flyout.",
    })

    flow:Checkbox({
        label   = "Large trinket cooldown numbers",
        get     = function() return Addon.db.settings.trinkets.largeNumbers end,
        set     = function(v)
            Addon.db.settings.trinkets.largeNumbers = v and true or false
            if Addon.RestyleTrinketCooldowns then Addon:RestyleTrinketCooldowns() end
        end,
        tooltip = "On: large gold numbers in the middle of the slot. Off: smaller white numbers along the bottom edge.",
    })

    -- Two side-by-side columns (armor), one split block so they share an arrange.
    local split = CreateFrame("Frame", nil, flow.pane.child)
    local leftCol  = UI.CreateColumn(split)
    local rightCol = UI.CreateColumn(split)
    charWinHeader(leftCol.flow); charWinHeader(rightCol.flow)
    for _, s in ipairs(Addon.SLOTS) do
        if     s.col == "L" then charWinRow(leftCol.flow,  s.id)
        elseif s.col == "R" then charWinRow(rightCol.flow, s.id) end
    end
    split.arrange = function(width)
        split:SetWidth(width)
        local colW = math.max(1, math.min(CW_COL_W, (width - CW_COL_GAP) / 2))
        local lh = leftCol:Layout(colW)
        local rh = rightCol:Layout(colW)
        leftCol.frame:ClearAllPoints()
        leftCol.frame:SetPoint("TOPLEFT", split, "TOPLEFT", 0, 0)
        rightCol.frame:ClearAllPoints()
        rightCol.frame:SetPoint("TOPLEFT", split, "TOPLEFT", colW + CW_COL_GAP, 0)
        local total = math.max(lh, rh)
        split:SetHeight(math.max(total, 1))
        return total
    end
    addBlock(flow, split, split.arrange, rowGap())

    -- Weapons (Main Hand / Off Hand / Ranged) as a centered group beneath the columns.
    flow:AddSection("Weapons")
    local wSplit = CreateFrame("Frame", nil, flow.pane.child)
    local wCol = UI.CreateColumn(wSplit)
    charWinHeader(wCol.flow)   -- round-5 item A: weapons group now has the same column headers
    for _, s in ipairs(Addon.SLOTS) do
        if s.col == "W" then charWinRow(wCol.flow, s.id) end
    end
    wSplit.arrange = function(width)
        wSplit:SetWidth(width)
        local colW = math.max(1, math.min(CW_COL_W, width))
        local wh = wCol:Layout(colW)
        local ox = math.max(0, (width - colW) / 2)   -- center the group horizontally
        wCol.frame:ClearAllPoints()
        wCol.frame:SetPoint("TOPLEFT", wSplit, "TOPLEFT", ox, 0)
        wSplit:SetHeight(math.max(wh, 1))
        return wh
    end
    addBlock(flow, wSplit, wSplit.arrange, rowGap())
end

-- ══ Item Slot Widgets (detached popouts) ══════════════════════════════════════
local WW_SLOT_X = 34    -- widget row: icon left inset -> name column start
local WW_DIR_X  = 140   -- widget row: direction dropdown x
local WW_PER_X  = 240   -- widget row: per-row dropdown x

local function makeWidgetRow(host)
    local UI = DaseekiUI
    local r = CreateFrame("Frame", nil, host)
    r:SetHeight(W_ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(24, 24)
    r.icon:SetPoint("LEFT", r, "LEFT", 4, 0); r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.label = r:CreateFontString(nil, "OVERLAY"); r.label:SetFontObject(F_BODY)
    r.label:SetPoint("LEFT", r, "LEFT", WW_SLOT_X, 0); r.label:SetWidth(100); r.label:SetJustifyH("LEFT")
    r._cfg = function() return r._slotId and Addon.db.settings.slotPopouts.buttons[r._slotId] end

    r.dirDD = UI.MakeDropdown(r, {
        width = 92, choices = { "Right", "Left", "Down", "Up" },
        get = function() local c = r._cfg(); return c and cap(c.dir or "right") or "Right" end,
        set = function(v) local c = r._cfg(); if c then c.dir = v:lower() end end,
    })
    r.dirDD:ClearAllPoints(); r.dirDD:SetPoint("LEFT", r, "LEFT", WW_DIR_X, 0)
    r.perDD = UI.MakeDropdown(r, {
        width = 50, choices = PERROW,
        get = function() local c = r._cfg(); return c and tostring(c.perRow or 5) or "5" end,
        set = function(v) local c = r._cfg(); if c then c.perRow = tonumber(v) end end,
    })
    r.perDD:ClearAllPoints(); r.perDD:SetPoint("LEFT", r, "LEFT", WW_PER_X, 0)

    r.remove = UI.MakeButton(r, { text = "Remove", width = 78, variant = "danger", onClick = function()
        if r._slotId then Addon:RemoveSlotPopout(r._slotId) end
    end })
    r.remove:ClearAllPoints(); r.remove:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.unlink = UI.MakeButton(r, { text = "Unlink", width = 72, variant = "quiet", onClick = function()
        if r._slotId then Addon:ReleasePopoutAnchor(r._slotId) end
    end })
    r.unlink:ClearAllPoints(); r.unlink:SetPoint("RIGHT", r.remove, "LEFT", -6, 0)
    r.unlink:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Release this widget's anchor", 1, 1, 1); GameTooltip:Show()
    end)
    r.unlink:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UI.Skin(r, function() r.bg:SetColorTexture(UI.Color(r._even and "raised" or "panel", 0.6)) end)
    return r
end

function Addon:BuildWidgetsTab(flow)
    local UI = DaseekiUI
    flow:AddSection("Item Slot Widgets")
    flow:Hint("Alt+left-click a slot on the character pane, or add one below. Drag a widget next to another to anchor it (the dock side glows).")

    flow:Checkbox({
        label = "Lock all widget positions",
        get = function() return Addon.db.settings.slotPopouts.locked end,
        set = function(v) Addon.db.settings.slotPopouts.locked = v and true or false end,
    })
    flow:AddRow():Slider({
        label = "Widget scale", width = 200, min = 0.5, max = 2, step = 0.05,
        get = function() return Addon.db.settings.slotPopouts.scale or 1 end,
        set = function(v) Addon:SetPopoutScale(v) end,
        format = function(v) return string.format("%.2f", v) end,
    })

    local slotNames, nameToId = {}, {}
    for _, s in ipairs(Addon.SLOTS) do slotNames[#slotNames + 1] = s.name; nameToId[s.name] = s.id end
    flow._addSel = Addon.SLOTS[1].name
    local addRow = flow:AddRow()
    local addLbl = addRow:Label("Add widget for slot:"); addLbl.uiWidth = 130; addLbl:SetWidth(130)
    addRow:Dropdown({
        width = 160, choices = slotNames,
        get = function() return flow._addSel or Addon.SLOTS[1].name end,
        set = function(v) flow._addSel = v end,
    })
    addRow:Button({ text = "Add", width = 64, onClick = function()
        local sid = nameToId[flow._addSel or Addon.SLOTS[1].name]
        if sid and not Addon.db.settings.slotPopouts.buttons[sid] then Addon:ShowSlotPopout(sid) end
        Addon:RefreshWidgetsTab()
    end })

    -- column header + rule (full width, aligned with the list rows below)
    local hdr = flow:AddRow()
    local hh1 = hdr:Label("Slot", { muted = true });      hh1.uiWidth = WW_DIR_X - 8; hh1:SetWidth(WW_DIR_X - 8)
    local hh2 = hdr:Label("Direction", { muted = true }); hh2.uiWidth = WW_PER_X - WW_DIR_X; hh2:SetWidth(WW_PER_X - WW_DIR_X)
    hdr:Label("Per row", { muted = true })
    flow:AddSeparator()

    -- dynamic list host — its arrange stacks the rows and returns total height;
    -- RefreshWidgetsTab repopulates the row data then calls flow.pane:Layout().
    local host = CreateFrame("Frame", nil, flow.pane.child)
    host._fillWidth = true
    host._rows = {}
    host._list = {}
    host.empty = host:CreateFontString(nil, "OVERLAY")
    host.empty:SetFontObject(F_SMALL)
    host.empty:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    host.empty:SetText("No widgets yet — add one above or alt+left-click a slot.")
    host.empty:Hide()
    host.arrange = function(width)
        host:SetWidth(width)
        local list = host._list
        if #list == 0 then
            host.empty:Show()
            return 18
        end
        host.empty:Hide()
        for i, r in ipairs(host._rows) do
            if i <= #list then
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT",  host, "TOPLEFT",  0, -(i - 1) * W_ROW_H)
                r:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -(i - 1) * W_ROW_H)
                r:Show()
            else
                r:Hide()
            end
        end
        return #list * W_ROW_H
    end
    addBlock(flow, host, host.arrange, rowGap())
    flow._listHost = host

    Addon:RefreshWidgetsTab()
end

function Addon:RefreshWidgetsTab()
    local flow = Addon.frames and Addon.frames.widgets
    if not (flow and flow._listHost) then return end
    local UI = DaseekiUI
    local host = flow._listHost
    local list = {}
    for _, sid in ipairs(Addon.SLOT_IDS) do
        if Addon.db.settings.slotPopouts.buttons[sid] then list[#list + 1] = sid end
    end
    host._list = list
    for i, sid in ipairs(list) do
        local r = host._rows[i] or makeWidgetRow(host)
        host._rows[i] = r
        r._slotId = sid
        r._even = (i % 2 == 0)
        r.bg:SetColorTexture(UI.Color(r._even and "raised" or "panel", 0.6))
        r.icon:SetTexture(GetInventoryItemTexture("player", sid) or slotEmptyTex(sid))
        r.label:SetText(slotName(sid))
        local cfg = Addon.db.settings.slotPopouts.buttons[sid]
        r.dirDD.Refresh(); r.perDD.Refresh()
        r.unlink:SetEnabled(cfg.anchor ~= nil)
    end
    flow.pane:Layout()
end

-- ── Refresh (Sets tab) ────────────────────────────────────────────────────────
function Addon:RefreshSetList()
    local panel = Addon.panel
    if not panel or not panel.listChild then return end
    local UI = DaseekiUI
    local sets = Addon:GetSetsSorted()
    if not panel.selectedSet or not Addon.db.sets[panel.selectedSet] then
        panel.selectedSet = sets[1] and sets[1].name or nil
    end
    panel.rows = panel.rows or {}
    if panel.listEmpty then panel.listEmpty:SetShown(#sets == 0) end
    for _, r in ipairs(panel.rows) do r:Hide() end
    for i, set in ipairs(sets) do
        local r = panel.rows[i]
        if not r then
            r = CreateFrame("Button", nil, panel.listChild)
            r:SetHeight(SET_ROW_H)
            r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
            r.sel = r:CreateTexture(nil, "BACKGROUND"); r.sel:SetAllPoints(); r.sel:Hide()
            r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(22, 22)
            r.icon:SetPoint("LEFT", r, "LEFT", 4, 0); r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            r.label = r:CreateFontString(nil, "OVERLAY"); r.label:SetFontObject(F_BODY)
            r.label:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.label:SetWidth(96); r.label:SetJustifyH("LEFT")
            r.keyText = r:CreateFontString(nil, "OVERLAY"); r.keyText:SetFontObject(F_SMALL)
            r.keyText:SetPoint("RIGHT", r, "RIGHT", -6, 0); r.keyText:SetJustifyH("RIGHT")
            local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints()
            UI.Skin(hl, function(self) self:SetColorTexture(UI.Color("accent", 0.10)) end)
            r:SetScript("OnClick", function(self) panel.selectedSet = self._name; Addon:RefreshOptions() end)
            -- drag to reorder (cursor-position polling — see buildSetList)
            r:SetScript("OnMouseDown", function(self, btn)
                if btn ~= "LeftButton" then return end
                panel._dragSourceName = self._name
                panel._dragging = false
                -- UIPARENT SPACE, deliberately, and the ticker's threshold reads
                -- it back in the SAME space (see buildSetList). This anchor only
                -- ever answers "did the mouse move 5px?" — it is not a hit-test,
                -- so it must NOT be converted with the list's scale.
                local cx, cy = GetCursorPosition()
                local uiScale = UIParent:GetEffectiveScale()
                if not uiScale or uiScale <= 0 then uiScale = 1 end
                panel._dragClickX, panel._dragClickY = cx / uiScale, cy / uiScale
                if panel._dragTick then panel._dragTick:Show() end
            end)
            panel.rows[i] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT",  panel.listChild, "TOPLEFT",  0, -(i - 1) * SET_ROW_H)
        r:SetPoint("TOPRIGHT", panel.listChild, "TOPRIGHT", 0, -(i - 1) * SET_ROW_H)
        r._even = (i % 2 == 0)
        r.bg:SetColorTexture(UI.Color(r._even and "raised" or "panel", 0.7))
        r.sel:SetColorTexture(UI.Color("accent", 0.28))
        r.icon:SetTexture(set.icon or Addon.DEFAULT_ICON)
        r.label:SetText(set.name); r._name = set.name
        r.label:SetTextColor(UI.Color(panel.selectedSet == set.name and "accent" or "text"))
        r.keyText:SetText(set.key or "")
        r.keyText:SetTextColor(UI.Color("muted"))
        r.sel:SetShown(panel.selectedSet == set.name)
        r:Show()
    end
    panel.listChild:SetHeight(math.max(1, #sets * SET_ROW_H))
end

-- Strip the preview model back to bare. Undress()'s no-argument form is not
-- guaranteed to drop weapons, so the three weapon slots are cleared explicitly —
-- otherwise the previous set's blade lingers into the next one.
local function stripModel(model)
    if model.Undress then pcall(model.Undress, model) end
    if model.UndressSlot then
        for _, sid in ipairs({ Addon.MODEL_MAINHAND, Addon.MODEL_OFFHAND, Addon.MODEL_RANGED }) do
            pcall(model.UndressSlot, model, sid)
        end
    end
end

-- Dress the preview model in the selected set. Deliberately does NOT call
-- SetUnit: SetUnit reloads the model and re-dresses it in the player's LIVE gear
-- asynchronously, so every Undress/TryOn issued in the same frame is discarded
-- when the reload lands — which is exactly why the preview showed worn gear
-- instead of the set being viewed. The unit is bound once, at build time.
function Addon:DressSetModel()
    local panel = Addon.panel
    local model = panel and panel.model
    if not model or not model.TryOn then return end
    stripModel(model)
    local set = panel.selectedSet and Addon.db.sets[panel.selectedSet]
    if not set then return end
    for _, step in ipairs(Addon:BuildDressPlan(set)) do
        -- handSlotName keeps the off-hand out of the main hand. If a client ever
        -- rejects the second argument, fall back to the bare call — the plan
        -- already orders main hand before off-hand, which is the best a
        -- slot-blind TryOn can do.
        local ok = step.hand and pcall(model.TryOn, model, step.link, step.hand)
        if not ok then pcall(model.TryOn, model, step.link) end
    end
end

function Addon:RefreshSetModel()
    local panel = Addon.panel
    local model = panel and panel.model
    if not model then return end

    -- Re-dress once the model finishes loading, for the build-time pass that can
    -- run before SetUnit's reload has landed. Hooked behind pcall because
    -- OnModelLoaded is not a guaranteed handler on every client.
    if model.SetScript and not model._armDressHooked then
        model._armDressHooked = true
        if not pcall(model.SetScript, model, "OnModelLoaded",
                     function() Addon:DressSetModel() end) then
            model._armDressHooked = nil
        end
    end

    Addon:DressSetModel()
end

-- Open the hub straight to the Armory → Sets tab (used by the character-pane button).
function Addon:OpenToSets()
    if not _G.DaseekiSuite then
        print(Addon:Tag() .. " Daseeki-Core not loaded.")
        return
    end
    DaseekiSuite:Open("armory", "sets")
end

function Addon:RefreshBuilder()
    local panel = Addon.panel
    if not panel or not panel.slotButtons then return end
    local set = panel.selectedSet and Addon.db.sets[panel.selectedSet]

    if panel.iconBtn then panel.iconBtn.icon:SetTexture((set and set.icon) or Addon.DEFAULT_ICON) end
    if panel.nameEB and panel.nameEB.editBox and not panel.nameEB.editBox:HasFocus() then
        panel.nameEB.Refresh()
    end
    if panel.kbBtn and panel.kbBtn._label then
        panel.kbBtn._label:SetText("Keybind: " .. ((set and set.key) or "\194\183"))
    end

    local goalMode = panel.goalMode and set ~= nil
    if panel.goalsBtn and panel.goalsBtn._label then
        panel.goalsBtn._label:SetText(goalMode and "Done (Goals)" or "Set Goals")
    end

    for slotId, b in pairs(panel.slotButtons) do
        local entry    = set and set.equip[slotId]
        local disabled = set and set.disabled and set.disabled[slotId]
        local isEmpty  = entry ~= nil and Addon:IsEmptyEntry(entry)
        if isEmpty then
            -- governed and explicitly empty: the slot's own silhouette at FULL
            -- colour, so it reads as a deliberate choice rather than as the
            -- dimmed "not in this set" state (spec §5.2)
            b.icon:SetTexture(b._emptyTex); b.icon:SetDesaturated(false)
            b.icon:SetAlpha((disabled and 0.5 or 1) * (goalMode and 0.4 or 1))
        elseif entry then
            b.icon:SetTexture(Addon:EntryTexture(entry) or "Interface\\Icons\\INV_Misc_QuestionMark")
            b.icon:SetDesaturated(disabled and true or false)
            b.icon:SetAlpha((disabled and 0.5 or 1) * (goalMode and 0.4 or 1))
        else
            b.icon:SetTexture(b._emptyTex); b.icon:SetDesaturated(true)
            b.icon:SetAlpha((disabled and 0.35 or 0.6) * (goalMode and 0.6 or 1))
        end
        if b.emptyMark then b.emptyMark:SetShown(isEmpty and not goalMode) end
        b.off:SetShown(disabled and not goalMode and true or false)
        b:EnableMouse(not goalMode)   -- set slots inert while editing goals
        -- an explicit-empty marker is never "missing gear"
        local missing = entry and not isEmpty and not disabled and not goalMode
                        and not Addon:IsEntryAvailable(entry)
        b.glow:SetShown(missing and true or false)

        -- chase-list goal overlay + obtained check
        local goal = set and Addon:GetGoal(set, slotId)
        local met  = set and Addon:IsGoalMet(set, slotId)
        b.check:SetShown((goal ~= nil and met) and true or false)

        local g = b.goalBtn
        if goalMode then
            g:EnableMouse(true); g:SetAlpha(1)
            if goal then
                g.icon:SetTexture(Addon:EntryTexture(goal) or "Interface\\Icons\\INV_Misc_QuestionMark")
                g.icon:Show(); g.plus:Hide()
            else
                g.icon:Hide(); g.plus:Show()
            end
            g:Show()
        elseif goal and not met then
            g.icon:SetTexture(Addon:EntryTexture(goal) or "Interface\\Icons\\INV_Misc_QuestionMark")
            g.icon:Show(); g.plus:Hide()
            g:EnableMouse(false); g:SetAlpha(0.5); g:Show()
        else
            g:Hide()
        end
    end

    local has = set ~= nil
    if panel.saveBtn  then panel.saveBtn:SetEnabled(has)  end
    if panel.equipBtn then panel.equipBtn:SetEnabled(has) end
    if panel.macroBtn then panel.macroBtn:SetEnabled(has) end
    if panel.iconBtn  then panel.iconBtn:SetEnabled(has)  end

    Addon:RefreshSetModel()
end

-- Refresh for the Sets section (its Core section `refresh`).
function Addon:RefreshOptions()
    if not (Addon.frames and Addon.frames.sets) then return end
    Addon:RefreshSetList()
    Addon:RefreshBuilder()
end

-- ── Register the section with the Daseeki-Core hub ────────────────────────────
function Addon:RegisterOptions()
    if not _G.DaseekiSuite then return end
    if not (_G.DaseekiUI and _G.DaseekiUI.Token) then
        print(Addon:Tag() .. " requires Daseeki Core v2.0.0 or newer — please update Daseeki Core.")
        return
    end
    DaseekiSuite:RegisterAddon({
        id      = "armory",
        title   = "Armory",
        icon    = "Interface\\Icons\\INV_Shield_26",  -- Face of Death
        order   = 40,
        flow    = true,  -- sections use the DaseekiUI flow API (build(flow)).
        sections = {
            { id = "sets",    title = "Sets",
              build = function(flow) Addon:BuildSetsSection(flow) end,
              refresh = function() Addon:RefreshOptions() end },
            { id = "stats",   title = "Stats",
              build = function(flow) Addon:BuildStatsSection(flow) end,
              refresh = function() Addon:RefreshStatsTab() end },
            { id = "charwin", title = "Character Window",
              build = function(flow) Addon:BuildCharWindowSection(flow) end },
            { id = "widgets", title = "Item Slot Widgets",
              build = function(flow) Addon:BuildWidgetsSection(flow) end,
              refresh = function() Addon:RefreshWidgetsTab() end },
        },
    })
end
