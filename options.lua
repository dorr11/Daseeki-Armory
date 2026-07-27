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

    Four sections (Core sub-tabs):
      • Sets            — set list + CRUD + paper-doll set builder + goal chase list
      • Set Swapper     — on-screen radial/dropdown switcher + global options
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
    blk.arrange = function(width)
        if row._applicable == false then row:Hide(); return 0 end
        row:Show(); return origArrange(width)
    end
    function row:SetApplicable(on)
        self._applicable = on and true or false
        self._blk.topGap = self._applicable and self._baseGap or 0
    end
    return row
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
            print("|cff66ccffArmory|r imported " .. res .. " set(s) from ItemRack.")
            if Addon.panel then Addon.panel.selectedSet = nil end
            Addon:RefreshOptions(); Addon:RefreshWidget()
        else
            print("|cff66ccffArmory|r " .. tostring(res))
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

function Addon:BuildSwapperSection(flow)
    Addon.frames.swapper = flow
    Addon:BuildSetSwapperTab(flow)
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
function Addon:BuildSetSwapperTab(flow)
    local w = Addon.db.settings.widget

    flow:AddSection("Set Swapper")
    flow:Hint("On-screen widget that lets you equip a set with one click.")
    flow:AddChecklist({
        { label = "Enable",
          get = function() return Addon.db.settings.widget.show end,
          set = function(v) Addon:SetWidgetShown(v) end },
        { label = "Lock",
          get = function() return Addon.db.settings.widget.locked end,
          set = function(v) Addon.db.settings.widget.locked = v and true or false end },
    })
    flow:AddRow():Dropdown({
        label = "Open On", width = 140, choices = { "Click", "Hover" },
        get = function() return w.openTrigger == "hover" and "Hover" or "Click" end,
        set = function(v) w.openTrigger = v:lower() end,
    })

    flow:AddSection("Display")
    flow:AddRow():Dropdown({
        label = "Mode", width = 140, choices = { "Radial", "Dropdown" },
        get = function() return w.mode == "dropdown" and "Dropdown" or "Radial" end,
        set = function(v)
            w.mode = (v == "Dropdown") and "dropdown" or "radial"
            Addon:RefreshSwapperTab(); Addon:RefreshWidget()
        end,
    })

    local typeRow = condRow(flow)
    typeRow:Dropdown({
        label = "Type", width = 140, choices = { "Icon", "List" },
        get = function() return w.dropdownType == "list" and "List" or "Icon" end,
        set = function(v)
            w.dropdownType = v:lower()
            Addon:RefreshSwapperTab(); Addon:RefreshWidget()
        end,
    })
    local dirRow = condRow(flow)
    dirRow:Dropdown({
        label = "Direction", width = 140, choices = { "Right", "Left", "Down", "Up" },
        get = function() return cap(w.dropdownDir or "right") end,
        set = function(v) w.dropdownDir = v:lower(); Addon:RefreshWidget() end,
    })
    local perRow = condRow(flow)
    perRow:Dropdown({
        label = "Sets Per Row", width = 140, choices = PERROW,
        get = function() return tostring(w.dropdownPerRow or 5) end,
        set = function(v) w.dropdownPerRow = tonumber(v); Addon:RefreshWidget() end,
    })
    local alwaysRow = condRow(flow)
    alwaysRow:Checkbox({
        label = "Always Open",
        get = function() return w.dropdownAlwaysOpen end,
        set = function(v)
            w.dropdownAlwaysOpen = v and true or false
            Addon:RefreshWidget()
        end,
    })
    flow._condRows = { type = typeRow, dir = dirRow, per = perRow, always = alwaysRow }

    flow:AddSection("General")
    flow:Checkbox({
        label = "Chat Messages",
        get = function() return Addon.db.settings.chatMessages end,
        set = function(v) Addon.db.settings.chatMessages = v and true or false end,
    })
    flow:Hint("Print a message when a set or item swap is queued for after combat.")
    flow:AddRow():Dropdown({
        label = "Flyout item tooltips", width = 140, choices = { "On Ctrl", "Always" },
        get = function() return Addon.db.settings.flyoutTooltip == "always" and "Always" or "On Ctrl" end,
        set = function(v) Addon.db.settings.flyoutTooltip = (v == "Always") and "always" or "ctrl" end,
    })

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
    flow._condRows.type:SetApplicable(isDropdown)
    flow._condRows.dir:SetApplicable(isIcon)
    flow._condRows.per:SetApplicable(isIcon)
    flow._condRows.always:SetApplicable(isIcon)
    flow.pane:Layout()
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
        local mx, my = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        mx, my = mx / scale, my / scale

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
            local dx, dy = mx - (panel._dragClickX or mx), my - (panel._dragClickY or my)
            if dx * dx + dy * dy < 25 then return end
            panel._dragging = true
        end

        local childTop = child:GetTop()
        if not childTop then return end
        local n = #Addon:GetSetsSorted()
        if n == 0 then return end
        local relY = childTop - my
        local hRow = math.floor(relY / SET_ROW_H)
        local frac = relY - hRow * SET_ROW_H
        local line = (frac < SET_ROW_H / 2) and (hRow + 1) or (hRow + 2)
        line = math.max(1, math.min(n + 1, line))
        panel._dragDropLine = line

        dropBar:ClearAllPoints()
        dropBar:SetPoint("TOPLEFT",  child, "TOPLEFT",  0, -(line - 1) * SET_ROW_H)
        dropBar:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -(line - 1) * SET_ROW_H)
        dropBar:Show()
    end)
    panel._dragTick = dragTick

    host.arrange = function(width)
        host:SetWidth(width)
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
        if set and set.equip[slotId] then
            uneq = { fn = function() Addon:ClearSlot(name, slotId); Addon:RefreshBuilder() end,
                     label = "Remove from set" }
            local link = Addon:EntryLink(set.equip[slotId])
            if link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(link)
                GameTooltip:Show()
            end
        end
        Addon:ShowItemFlyout(self, slotId, function(item)
            Addon:SetSlotFromLink(name, slotId, item.link)
            if set and set.disabled then set.disabled[slotId] = nil end
            Addon:RefreshBuilder()
        end, uneq, nil, true)  -- include currently-equipped items in the builder
    end
    -- Right-click disables the slot; Shift+Right-click clears it.
    local function slotClick(self, button)
        local name = panel.selectedSet
        if not name or button ~= "RightButton" then return end
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
        -- goal obtained check (bottom-right)
        b.check = b:CreateTexture(nil, "OVERLAY", nil, 7)
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

    -- Width-relative arrange: left column at the left edge, right column pinned to
    -- the right edge, model centered between; weapons centered across the bottom.
    pd.arrange = function(width)
        pd:SetWidth(width)
        local colH = COL_ROWS * SLOT_STEP
        local bodyH = math.max(colH, MODEL_H)

        model:ClearAllPoints()
        model:SetPoint("TOP", pd, "TOP", 0, 0)

        local li, ri = 0, 0
        for _, slotDef in ipairs(Addon.SLOTS) do
            local b = panel.slotButtons[slotDef.id]
            if b then
                b:ClearAllPoints()
                if slotDef.col == "L" then
                    b:SetPoint("TOPLEFT", pd, "TOPLEFT", 0, -(li * SLOT_STEP)); li = li + 1
                elseif slotDef.col == "R" then
                    b:SetPoint("TOPRIGHT", pd, "TOPRIGHT", 0, -(ri * SLOT_STEP)); ri = ri + 1
                end
            end
        end

        local weapons = { 16, 17, 18 }
        local totalW = #weapons * SLOT_SZ + (#weapons - 1) * WPN_XGAP
        local startX = math.max(0, (width - totalW) / 2)
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

    -- ── Left half: set list + management ──────────────────────────────────────
    flow:AddSection("Armory Sets")
    local listHost = buildSetList(flow, panel)
    addBlock(flow, listHost, listHost.arrange, rowGap())

    -- New / Duplicate / Rename / Delete
    local crud = flow:AddRow()
    crud:Button({ text = "New", width = 91, onClick = function()
        _G.DaseekiSuite.ShowNameInputDialog("New Set", "", function(v)
            local ok, err = Addon:CreateSet(v)
            if ok then panel.selectedSet = v; Addon:RefreshOptions(); Addon:RefreshWidget()
            else print("|cff66ccffArmory|r " .. tostring(err)) end
        end)
    end })
    crud:Button({ text = "Duplicate", width = 91, onClick = function()
        if not panel.selectedSet then return end
        local ok, res = Addon:DuplicateSet(panel.selectedSet)
        if ok then panel.selectedSet = res; Addon:RefreshOptions(); Addon:RefreshWidget()
        else print("|cff66ccffArmory|r " .. tostring(res)) end
    end })
    crud:Button({ text = "Rename", width = 91, onClick = function()
        if not panel.selectedSet then return end
        _G.DaseekiSuite.ShowNameInputDialog("Rename Set", panel.selectedSet, function(v)
            local ok, err = Addon:RenameSet(panel.selectedSet, v)
            if ok then panel.selectedSet = v; Addon:RefreshOptions(); Addon:RefreshWidget()
            else print("|cff66ccffArmory|r " .. tostring(err)) end
        end)
    end })
    crud:Button({ text = "Delete", width = 91, onClick = function()
        if panel.selectedSet then StaticPopup_Show("DASEEKI_ARMORY_DELETE", panel.selectedSet, nil, panel.selectedSet) end
    end })

    flow:AddSeparator()
    flow:Hint("Clone to another character")
    local io1 = flow:AddRow()
    io1:Button({ text = "Export Sets", width = 110, onClick = function()
        _G.DaseekiSuite.ShowTextDialog("Export Armory Sets", Addon:ExportSets(), true)
    end })
    io1:Button({ text = "Import Sets", width = 110, onClick = function()
        _G.DaseekiSuite.ShowTextDialog("Import Armory Sets", "", false, function(text)
            local ok, res = Addon:ImportSets(text)
            if ok then print("|cff66ccffArmory|r imported " .. res .. " set(s).")
                Addon:RefreshOptions(); Addon:RefreshWidget()
            else print("|cff66ccffArmory|r " .. tostring(res)) end
        end)
    end })
    flow:AddRow():Button({ text = "Import from ItemRack", width = 230, onClick = function()
        local n = Addon:CountItemRackSets()
        if n == 0 then print("|cff66ccffArmory|r no ItemRack sets found — make sure ItemRack is enabled."); return end
        StaticPopup_Show("DASEEKI_ARMORY_IRIMPORT", n)
    end })

    -- ── Right half: set builder ───────────────────────────────────────────────
    flow:AddSection("Set Builder")
    flow:Label("Set name", { muted = true })

    -- icon button + name edit box on one row
    local headRow = flow:AddRow()
    local iconBtn = CreateFrame("Button", nil, headRow, "BackdropTemplate")
    iconBtn:SetSize(46, 46)
    UI.Skin(iconBtn, function(self)
        self:SetBackdrop(UI.FLAT_BACKDROP)
        self:SetBackdropColor(UI.Color("inset"))
        self:SetBackdropBorderColor(UI.Color("borderLite"))
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
        get = function() return panel.selectedSet or "" end,
        set = function(v)
            v = strtrim(v or "")
            if panel.selectedSet and v ~= "" and v ~= panel.selectedSet then
                local ok, err = Addon:RenameSet(panel.selectedSet, v)
                if ok then panel.selectedSet = v; Addon:RefreshOptions(); Addon:RefreshWidget()
                else print("|cff66ccffArmory|r " .. tostring(err)) end
            end
        end,
    })

    -- keybind + goals row
    local kbRow = flow:AddRow()
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
                    warn = "\n|cffff8800Already bound to Armory set \"" .. otherSet .. "\" — it will be reassigned.|r"
                else
                    local action = GetBindingAction and GetBindingAction(combo)
                    if action and action ~= "" then
                        warn = "\n|cffff8800Already bound to: " .. (_G["BINDING_NAME_" .. action] or action) .. "|r"
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

    panel.goalsBtn = kbRow:Button({ text = "Set Goals", width = 140, pin = "right", onClick = function()
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
    local pd = buildPaperdoll(flow, panel)
    addBlock(flow, pd, pd.arrange, rowGap())

    -- action buttons
    local actRow = flow:AddRow()
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

    flow:Hint("Hover a slot to choose  \194\183  Right-click: disable  \194\183  Shift+Right: clear")
end

-- ══ Character Window flyouts (per slot) ═══════════════════════════════════════
function Addon:BuildCharWindowTab(flow)
    flow:AddSection("Character Window Flyouts")
    flow:Hint("Item flyout shown when you hover an equipped slot on the character pane.")

    local SLOT_W, DIR_W, PER_W = 150, 110, 70
    local hdr = flow:AddRow()
    local h1 = hdr:Label("Slot", { muted = true });      h1.uiWidth = SLOT_W; h1:SetWidth(SLOT_W)
    local h2 = hdr:Label("Direction", { muted = true }); h2.uiWidth = DIR_W;  h2:SetWidth(DIR_W)
    hdr:Label("Per row", { muted = true })
    flow:AddSeparator()

    for _, s in ipairs(Addon.SLOTS) do
        local sid = s.id
        local row = flow:AddRow()
        local lead = slotLead(row, sid, SLOT_W)
        row._items[#row._items + 1] = { w = lead }
        row:Dropdown({
            width = DIR_W, choices = { "Right", "Left", "Down", "Up" },
            get = function() return cap(Addon:GetFlyoutConfig(sid).dir) end,
            set = function(v) Addon:GetFlyoutConfig(sid).dir = v:lower() end,
        })
        row:Dropdown({
            width = PER_W, choices = PERROW,
            get = function() return tostring(Addon:GetFlyoutConfig(sid).perRow) end,
            set = function(v) Addon:GetFlyoutConfig(sid).perRow = tonumber(v) end,
        })
    end
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
                local mx, my = GetCursorPosition()
                local scale = UIParent:GetEffectiveScale()
                panel._dragClickX, panel._dragClickY = mx / scale, my / scale
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

function Addon:RefreshSetModel()
    local panel = Addon.panel
    local model = panel and panel.model
    if not model then return end
    local set = panel.selectedSet and Addon.db.sets[panel.selectedSet]
    model:SetUnit("player")
    if model.Undress then model:Undress() end
    if set then
        for slotId, entry in pairs(set.equip) do
            -- skip the ranged slot (18): the model should only ever show the MH/OH
            -- weapons, never the ranged weapon in their place.
            if slotId ~= 18 and Addon:IsSlotActive(set, slotId) then
                local link = Addon:EntryLink(entry)
                if link then model:TryOn(link) end
            end
        end
    end
end

-- Open the hub straight to the Armory → Sets tab (used by the character-pane button).
function Addon:OpenToSets()
    if not _G.DaseekiSuite then
        print("|cff66ccffArmory|r Daseeki-Core not loaded.")
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
        if entry then
            b.icon:SetTexture(Addon:EntryTexture(entry) or "Interface\\Icons\\INV_Misc_QuestionMark")
            b.icon:SetDesaturated(disabled and true or false)
            b.icon:SetAlpha((disabled and 0.5 or 1) * (goalMode and 0.4 or 1))
        else
            b.icon:SetTexture(b._emptyTex); b.icon:SetDesaturated(true)
            b.icon:SetAlpha((disabled and 0.35 or 0.6) * (goalMode and 0.6 or 1))
        end
        b.off:SetShown(disabled and not goalMode and true or false)
        b:EnableMouse(not goalMode)   -- set slots inert while editing goals
        local missing = entry and not disabled and not goalMode and not Addon:IsEntryAvailable(entry)
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
    DaseekiSuite:RegisterAddon({
        id      = "armory",
        title   = "Armory",
        icon    = "Interface\\Icons\\INV_Shield_26",  -- Face of Death
        order   = 40,
        sections = {
            { id = "sets",    title = "Sets",
              build = function(flow) Addon:BuildSetsSection(flow) end,
              refresh = function() Addon:RefreshOptions() end },
            { id = "swapper", title = "Set Swapper",
              build = function(flow) Addon:BuildSwapperSection(flow) end,
              refresh = function() Addon:RefreshSwapperTab() end },
            { id = "charwin", title = "Character Window",
              build = function(flow) Addon:BuildCharWindowSection(flow) end },
            { id = "widgets", title = "Item Slot Widgets",
              build = function(flow) Addon:BuildWidgetsSection(flow) end,
              refresh = function() Addon:RefreshWidgetsTab() end },
        },
    })
end
