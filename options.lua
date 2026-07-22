--[[
    Daseeki Armory — options section for the Daseeki-Core hub (id "armory").

    Left tab strip selects between three panels:
      • Sets            — set list + CRUD + paper-doll set builder + radial-widget toggles
      • Character Window — per-slot config for the flyout shown when hovering an equipped
                           slot on the Blizzard character pane
      • Item Slot Widgets — live list of the detached gear-slot popouts (alt+click a slot),
                            each with its own flyout direction + items-per-row, plus a remove
                            button and a global Lock toggle
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
-- Each Core section gets its own full-width frame, built lazily on first selection.
-- The Sets section also owns the shared builder state on Addon.panel (rows /
-- slotButtons / selectedSet / listChild) that the Refresh* helpers read.
Addon.frames = Addon.frames or {}

function Addon:BuildSetsSection(f)
    Addon.frames.sets = f
    Addon.panel = f
    f.rows = {}
    f.slotButtons = {}
    -- async item-info refresh (textures/model fill in once the client caches items)
    f.evt = CreateFrame("Frame")
    f.evt:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    f.evt:SetScript("OnEvent", function()
        if f:IsVisible() then Addon:RefreshBuilder() end
    end)
    Addon:BuildSetsTab(f)
end

function Addon:BuildSwapperSection(f)
    Addon.frames.swapper = f
    Addon:BuildSetSwapperTab(f)
end

function Addon:BuildCharWindowSection(f)
    Addon.frames.charwin = f
    Addon:BuildCharWindowTab(f)
end

function Addon:BuildWidgetsSection(f)
    Addon.frames.widgets = f
    Addon:BuildWidgetsTab(f)
end

-- ══ Tab: Set Swapper (on-screen radial/dropdown switcher + global options) ════
function Addon:BuildSetSwapperTab(f)
    local DS = _G.DaseekiSuite
    DS.MakeSectionHeader(f, "Set Swapper", 4, 8, 460)
    DS.MakeLabel(f, "On-screen widget that lets you equip a set with one click.", nil, 4, 40)
    DS.MakeCheckbox(f, "Enable", 6, 72,
        function() return Addon.db.settings.widget.show end,
        function(v) Addon:SetWidgetShown(v) end)
    DS.MakeCheckbox(f, "Lock", 6, 100,
        function() return Addon.db.settings.widget.locked end,
        function(v) Addon.db.settings.widget.locked = v and true or false end)

    f.triggerLbl = DS.MakeLabel(f, "Open On", nil, 6, 134)
    f.triggerDD = DS.MakeSimpleDropdown(f, 170, 130, 120, { "Click", "Hover" }, function(c)
        Addon.db.settings.widget.openTrigger = c:lower()
    end)

    DS.MakeSeparator(f, 4, 168, 460)
    DS.MakeLabel(f, "Display", nil, 4, 178)

    f.modeLbl = DS.MakeLabel(f, "Mode", nil, 6, 210)
    f.modeDD = DS.MakeSimpleDropdown(f, 170, 206, 120, { "Radial", "Dropdown" }, function(c)
        Addon.db.settings.widget.mode = (c == "Dropdown") and "dropdown" or "radial"
        Addon:RefreshSwapperTab(); Addon:RefreshWidget()
    end)

    f.typeLbl = DS.MakeLabel(f, "Type", nil, 6, 238)
    f.typeDD = DS.MakeSimpleDropdown(f, 170, 234, 120, { "Icon", "List" }, function(c)
        Addon.db.settings.widget.dropdownType = c:lower()
        Addon:RefreshSwapperTab(); Addon:RefreshWidget()
    end)

    f.dirLbl = DS.MakeLabel(f, "Direction", nil, 6, 266)
    f.dirDD = DS.MakeSimpleDropdown(f, 170, 262, 120, { "Right", "Left", "Down", "Up" }, function(c)
        Addon.db.settings.widget.dropdownDir = c:lower()
        Addon:RefreshWidget()
    end)

    f.perLbl = DS.MakeLabel(f, "Sets Per Row", nil, 6, 294)
    f.perDD = DS.MakeSimpleDropdown(f, 170, 290, 120, PERROW, function(c)
        Addon.db.settings.widget.dropdownPerRow = tonumber(c)
        Addon:RefreshWidget()
    end)

    f.alwaysCB = DS.MakeCheckbox(f, "Always Open", 6, 322,
        function() return Addon.db.settings.widget.dropdownAlwaysOpen end,
        function(v)
            Addon.db.settings.widget.dropdownAlwaysOpen = v and true or false
            Addon:RefreshWidget()
        end)

    DS.MakeSeparator(f, 4, 358, 460)
    DS.MakeLabel(f, "General", nil, 4, 368)
    DS.MakeCheckbox(f, "Chat Messages", 6, 396,
        function() return Addon.db.settings.chatMessages end,
        function(v) Addon.db.settings.chatMessages = v and true or false end)
    DS.MakeLabel(f, "Print a message when a set or item swap is queued for after combat.", nil, 30, 424)

    DS.MakeLabel(f, "Flyout item tooltips", nil, 6, 460)
    local ttDD = DS.MakeSimpleDropdown(f, 170, 456, 120, { "On Ctrl", "Always" }, function(c)
        Addon.db.settings.flyoutTooltip = (c == "Always") and "always" or "ctrl"
    end)
    ttDD:SetValue(Addon.db.settings.flyoutTooltip == "always" and "Always" or "On Ctrl")

    Addon:RefreshSwapperTab()
end

-- Sync the Mode/Type/Direction/Per-Row controls to the saved settings, and show
-- only the rows relevant to the current Mode/Type (Type+Direction+PerRow are
-- meaningless in Radial mode; Direction/PerRow only apply to the Icon type).
function Addon:RefreshSwapperTab()
    local f = Addon.frames and Addon.frames.swapper
    if not (f and f.modeDD) then return end
    local w = Addon.db.settings.widget
    local isDropdown = w.mode == "dropdown"
    local isIcon     = isDropdown and w.dropdownType ~= "list"

    f.triggerDD:SetValue(w.openTrigger == "hover" and "Hover" or "Click")
    f.modeDD:SetValue(isDropdown and "Dropdown" or "Radial")
    f.typeDD:SetValue(w.dropdownType == "list" and "List" or "Icon")
    f.dirDD:SetValue(cap(w.dropdownDir or "right"))
    f.perDD:SetValue(tostring(w.dropdownPerRow or 5))

    f.typeLbl:SetShown(isDropdown); f.typeDD:SetShown(isDropdown)
    f.dirLbl:SetShown(isIcon);      f.dirDD:SetShown(isIcon)
    f.perLbl:SetShown(isIcon);      f.perDD:SetShown(isIcon)
    f.alwaysCB:SetShown(isIcon)
end

-- ══ Tab 1: Sets ═══════════════════════════════════════════════════════════════
local L_X, L_W = 4, 190
local SEP_X    = 200
local R_X      = 212
local LEFT_COL_X, RIGHT_COL_X = 218, 560
local SLOT_Y0, SLOT_STEP = 150, 40
local MODEL_X, MODEL_W, MODEL_Y, MODEL_H = 318, 200, 150, 300
local WPN_Y    = 462
local WPN_X    = { [16] = 360, [17] = 404, [18] = 448 }

function Addon:BuildSetsTab(f)
    local DS = _G.DaseekiSuite
    local panel = Addon.panel

    -- Hover a slot → open the item flyout to choose what goes in it. If the slot
    -- already has an item chosen, also show its tooltip to the right of the icon
    -- (may overlap the flyout — deliberate, reads better next to the slot).
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
    local function makeSlot(slotDef, x, y)
        local slotId = slotDef.id
        local b = CreateFrame("Button", nil, f)
        b:SetSize(36, 36)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b._emptyTex = Addon:GetSlotEmptyTexture(slotDef)
        b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); b.bg:SetColorTexture(0, 0, 0, 0.5)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints(); b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.glow = b:CreateTexture(nil, "OVERLAY")
        b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        b.glow:SetBlendMode("ADD"); b.glow:SetVertexColor(1, 0, 0, 1)
        b.glow:SetPoint("CENTER"); b.glow:SetSize(54, 54); b.glow:Hide()
        b.off = b:CreateTexture(nil, "OVERLAY"); b.off:SetAllPoints(); b.off:SetColorTexture(0, 0, 0, 0.55); b.off:Hide()
        -- goal obtained check (bottom-right)
        b.check = b:CreateTexture(nil, "OVERLAY", nil, 7)
        b.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        b.check:SetSize(16, 16); b.check:SetPoint("BOTTOMRIGHT", 3, -3); b.check:Hide()
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.25)
        b._slotId, b._slotName = slotDef.id, slotDef.name
        b:SetScript("OnClick", slotClick)
        b:SetScript("OnReceiveDrag", slotReceiveDrag)
        b:SetScript("OnEnter", slotEnter)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        panel.slotButtons[slotDef.id] = b

        -- goal "chase list" button on the inside edge (toward the model)
        local g = CreateFrame("Button", nil, b)
        g:SetSize(22, 22)
        g:SetFrameLevel(b:GetFrameLevel() + 3)
        if slotDef.col == "L" then     g:SetPoint("LEFT",   b, "RIGHT", 3, 0)
        elseif slotDef.col == "R" then g:SetPoint("RIGHT",  b, "LEFT", -3, 0)
        else                            g:SetPoint("BOTTOM", b, "TOP",   0, 3) end
        g:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        g.bg = g:CreateTexture(nil, "BACKGROUND"); g.bg:SetAllPoints(); g.bg:SetColorTexture(0, 0, 0, 0.6)
        g.icon = g:CreateTexture(nil, "ARTWORK"); g.icon:SetAllPoints(); g.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        g.plus = g:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        g.plus:SetPoint("CENTER"); g.plus:SetText("+"); g.plus:SetTextColor(0.6, 0.9, 0.6)
        local ghl = g:CreateTexture(nil, "HIGHLIGHT"); ghl:SetAllPoints(); ghl:SetColorTexture(0.2, 0.8, 0.2, 0.3)
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

    -- left: set list + management
    DS.MakeSectionHeader(f, "Armory Sets", L_X, 8, L_W)
    local listSF = CreateFrame("ScrollFrame", "DaseekiArmorySetScroll", f, "UIPanelScrollFrameTemplate")
    listSF:SetPoint("TOPLEFT", f, "TOPLEFT", L_X, -44)
    listSF:SetSize(L_W - 24, 330)
    local listChild = CreateFrame("Frame", nil, listSF); listChild:SetSize(L_W - 24, 1)
    listSF:SetScrollChild(listChild)
    panel.listChild = listChild

    -- Drag-to-reorder for the set list. A plain mouse drag-and-release between two
    -- Buttons never fires OnReceiveDrag (that only fires for cursor-item drops, e.g.
    -- dragging a spell off the spellbook) and GetMouseFocus is unreliable here, so
    -- poll cursor position instead — same pattern as Daseeki-Buff-Tracker's working
    -- item-list reorder (options.lua "Drag-to-reorder" section there).
    local ROWH = 28
    local dropBar = listChild:CreateTexture(nil, "OVERLAY")
    dropBar:SetColorTexture(1, 0.82, 0, 1); dropBar:SetHeight(2); dropBar:Hide()

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

        local childTop = listChild:GetTop()
        if not childTop then return end
        local n = #Addon:GetSetsSorted()
        if n == 0 then return end
        local relY = childTop - my
        local hRow = math.floor(relY / ROWH)
        local frac = relY - hRow * ROWH
        local line = (frac < ROWH / 2) and (hRow + 1) or (hRow + 2)
        line = math.max(1, math.min(n + 1, line))
        panel._dragDropLine = line

        dropBar:ClearAllPoints()
        dropBar:SetPoint("TOPLEFT",  listChild, "TOPLEFT",  0, -(line - 1) * ROWH)
        dropBar:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -(line - 1) * ROWH)
        dropBar:Show()
    end)
    panel._dragTick = dragTick

    DS.MakeButton(f, "New",       L_X,        384, 91, 22, function()
        DS.ShowNameInputDialog("New Set", "", function(v)
            local ok, err = Addon:CreateSet(v)
            if ok then panel.selectedSet = v; Addon:RefreshOptions(); Addon:RefreshWidget()
            else print("|cff66ccffArmory|r " .. tostring(err)) end
        end)
    end)
    DS.MakeButton(f, "Duplicate", L_X + 95,   384, 91, 22, function()
        if not panel.selectedSet then return end
        local ok, res = Addon:DuplicateSet(panel.selectedSet)
        if ok then panel.selectedSet = res; Addon:RefreshOptions(); Addon:RefreshWidget()
        else print("|cff66ccffArmory|r " .. tostring(res)) end
    end)
    DS.MakeButton(f, "Rename",    L_X,        412, 91, 22, function()
        if not panel.selectedSet then return end
        DS.ShowNameInputDialog("Rename Set", panel.selectedSet, function(v)
            local ok, err = Addon:RenameSet(panel.selectedSet, v)
            if ok then panel.selectedSet = v; Addon:RefreshOptions(); Addon:RefreshWidget()
            else print("|cff66ccffArmory|r " .. tostring(err)) end
        end)
    end)
    DS.MakeButton(f, "Delete",    L_X + 95,   412, 91, 22, function()
        if panel.selectedSet then StaticPopup_Show("DASEEKI_ARMORY_DELETE", panel.selectedSet, nil, panel.selectedSet) end
    end)

    DS.MakeSeparator(f, L_X, 444, L_W)
    DS.MakeLabel(f, "Clone to another character", nil, L_X, 452)
    DS.MakeButton(f, "Export Sets", L_X,      472, 91, 22, function()
        DS.ShowTextDialog("Export Armory Sets", Addon:ExportSets(), true)
    end)
    DS.MakeButton(f, "Import Sets", L_X + 95, 472, 91, 22, function()
        DS.ShowTextDialog("Import Armory Sets", "", false, function(text)
            local ok, res = Addon:ImportSets(text)
            if ok then print("|cff66ccffArmory|r imported " .. res .. " set(s).")
                Addon:RefreshOptions(); Addon:RefreshWidget()
            else print("|cff66ccffArmory|r " .. tostring(res)) end
        end)
    end)
    DS.MakeButton(f, "Import from ItemRack", L_X, 500, L_W, 22, function()
        local n = Addon:CountItemRackSets()
        if n == 0 then print("|cff66ccffArmory|r no ItemRack sets found — make sure ItemRack is enabled."); return end
        StaticPopup_Show("DASEEKI_ARMORY_IRIMPORT", n)
    end)

    -- separator between list and builder
    local vsep = f:CreateTexture(nil, "ARTWORK")
    vsep:SetColorTexture(0.3, 0.3, 0.3, 0.8); vsep:SetWidth(1)
    vsep:SetPoint("TOPLEFT", f, "TOPLEFT", SEP_X, -8)
    vsep:SetPoint("BOTTOMLEFT", f, "TOPLEFT", SEP_X, -600)

    -- right: set builder — centered icon + name header
    local BUILDER_CX = 410
    local ICON_SZ, NAME_W = 46, 210
    local groupW = ICON_SZ + 12 + NAME_W
    local gx = BUILDER_CX - groupW / 2

    local iconBtn = CreateFrame("Button", nil, f)
    iconBtn:SetSize(ICON_SZ, ICON_SZ)
    iconBtn:SetPoint("TOPLEFT", f, "TOPLEFT", gx, -30)
    iconBtn.bg = iconBtn:CreateTexture(nil, "BACKGROUND"); iconBtn.bg:SetAllPoints(); iconBtn.bg:SetColorTexture(0, 0, 0, 0.5)
    iconBtn.icon = iconBtn:CreateTexture(nil, "ARTWORK")
    iconBtn.icon:SetPoint("TOPLEFT", 2, -2); iconBtn.icon:SetPoint("BOTTOMRIGHT", -2, 2); iconBtn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local ibord = CreateFrame("Frame", nil, iconBtn, "BackdropTemplate")
    ibord:SetPoint("TOPLEFT", -2, 2); ibord:SetPoint("BOTTOMRIGHT", 2, -2)
    ibord:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
    ibord:SetBackdropBorderColor(1, 0.82, 0, 0.5)
    local ihl = iconBtn:CreateTexture(nil, "HIGHLIGHT"); ihl:SetAllPoints(); ihl:SetColorTexture(1, 0.82, 0, 0.25)
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
    panel.iconBtn = iconBtn

    local nameCap = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameCap:SetText("SET NAME"); nameCap:SetTextColor(0.55, 0.55, 0.55)

    local nameEB = DS.MakeEditBox(f, 0, 0, NAME_W)
    nameEB:ClearAllPoints()
    nameEB:SetPoint("LEFT", iconBtn, "RIGHT", 12, 0)
    nameEB:SetHeight(26)
    nameEB:SetFontObject(GameFontHighlightLarge)
    nameEB:SetJustifyH("CENTER")
    nameEB:SetTextColor(1, 0.9, 0.55)
    nameCap:SetPoint("BOTTOM", nameEB, "TOP", 0, 3)
    local nameLine = f:CreateTexture(nil, "ARTWORK")
    nameLine:SetColorTexture(1, 0.82, 0, 0.4); nameLine:SetHeight(1)
    nameLine:SetPoint("TOPLEFT", nameEB, "BOTTOMLEFT", 2, -1)
    nameLine:SetPoint("TOPRIGHT", nameEB, "BOTTOMRIGHT", -2, -1)
    nameEB:SetScript("OnEnterPressed", function(self)
        local v = strtrim(self:GetText())
        if panel.selectedSet and v ~= "" and v ~= panel.selectedSet then
            local ok, err = Addon:RenameSet(panel.selectedSet, v)
            if ok then panel.selectedSet = v; Addon:RefreshOptions(); Addon:RefreshWidget()
            else print("|cff66ccffArmory|r " .. tostring(err)) end
        end
        self:ClearFocus()
    end)
    panel.nameEB = nameEB

    -- keybind control (centered under the name)
    local kbBtn = DS.MakeButton(f, "Keybind: \194\183", 0, 0, 170, 20, nil)
    kbBtn:ClearAllPoints(); kbBtn:SetPoint("TOP", nameLine, "BOTTOM", 0, -10)
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

    -- Set Goals mode toggle (centered, above the action row)
    panel.goalsBtn = DS.MakeButton(f, "Set Goals", BUILDER_CX - 70, 548, 140, 22, function()
        panel.goalMode = not panel.goalMode
        Addon:RefreshBuilder()
    end)
    panel.goalsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Set Goals (chase list)", 1, 1, 1)
        GameTooltip:AddLine("Toggle goal editing. Set per-slot target items; when one lands", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("in your bags the set updates to it automatically.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    panel.goalsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- action buttons, centered along the bottom of the builder
    local BTN_Y = 582
    local b1, b2, b3 = 150, 90, 90
    local totalW = b1 + b2 + b3 + 16
    local bx = BUILDER_CX - totalW / 2
    panel.saveBtn  = DS.MakeButton(f, "Populate Current Gear", bx, BTN_Y, b1, 24, function()
        if panel.selectedSet then Addon:SaveCurrentGear(panel.selectedSet); Addon:RefreshBuilder() end
    end)
    panel.equipBtn = DS.MakeButton(f, "Equip Set", bx + b1 + 8, BTN_Y, b2, 24, function()
        if panel.selectedSet then Addon:EquipSet(panel.selectedSet) end
    end)
    panel.macroBtn = DS.MakeButton(f, "Show Macro", bx + b1 + b2 + 16, BTN_Y, b3, 24, function()
        if panel.selectedSet then
            DS.ShowTextDialog("Equip Macro — " .. panel.selectedSet, Addon:GetEquipMacro(panel.selectedSet), true)
        end
    end)

    local help = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    help:SetPoint("TOP", f, "TOPLEFT", BUILDER_CX, -(BTN_Y + 32))
    help:SetText("Hover a slot to choose  \194\183  Right-click: disable  \194\183  Shift+Right: clear")

    local model = CreateFrame("DressUpModel", nil, f)
    model:SetPoint("TOPLEFT", f, "TOPLEFT", MODEL_X, -MODEL_Y)
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

    local li, ri = 0, 0
    for _, slotDef in ipairs(Addon.SLOTS) do
        if slotDef.col == "L" then makeSlot(slotDef, LEFT_COL_X, SLOT_Y0 + li * SLOT_STEP); li = li + 1
        elseif slotDef.col == "R" then makeSlot(slotDef, RIGHT_COL_X, SLOT_Y0 + ri * SLOT_STEP); ri = ri + 1 end
    end
    for _, slotDef in ipairs(Addon.SLOTS) do
        if slotDef.col == "W" then makeSlot(slotDef, WPN_X[slotDef.id], WPN_Y) end
    end
end

-- ══ Tab 2: Character Window flyouts (per slot) ════════════════════════════════
function Addon:BuildCharWindowTab(f)
    local DS = _G.DaseekiSuite
    DS.MakeSectionHeader(f, "Character Window Flyouts", 4, 8, 460)
    DS.MakeLabel(f, "Item flyout shown when you hover an equipped slot on the character pane.", nil, 4, 40)

    DS.MakeLabel(f, "Slot",      nil, 12,  70)
    DS.MakeLabel(f, "Direction", nil, 170, 70)
    DS.MakeLabel(f, "Per row",   nil, 282, 70)
    DS.MakeSeparator(f, 4, 88, 460)

    local RH = 28
    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",     8,   -96)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -26,   4)

    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(426, #Addon.SLOTS * RH)
    sf:SetScrollChild(child)

    for i, s in ipairs(Addon.SLOTS) do
        local sid = s.id
        local r = CreateFrame("Frame", nil, child)
        r:SetSize(426, RH)
        r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * RH)
        r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
        r.bg:SetColorTexture(i % 2 == 0 and 0.12 or 0.08, 0.1, 0.12, 0.6)
        r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(22, 22); r.icon:SetPoint("LEFT", 4, 0)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        r.icon:SetTexture(GetInventoryItemTexture("player", sid) or slotEmptyTex(sid))
        r.label = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        r.label:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.label:SetWidth(120); r.label:SetJustifyH("LEFT")
        r.label:SetText(slotName(sid))

        local cfg = Addon:GetFlyoutConfig(sid)
        local dd = DS.MakeSimpleDropdown(r, 162, 3, 100, { "Right", "Left", "Down", "Up" },
            function(c) Addon:GetFlyoutConfig(sid).dir = c:lower() end)
        dd:SetValue(cap(cfg.dir))
        local pd = DS.MakeSimpleDropdown(r, 272, 3, 60, PERROW,
            function(c) Addon:GetFlyoutConfig(sid).perRow = tonumber(c) end)
        pd:SetValue(tostring(cfg.perRow))
    end
end

-- ══ Tab 3: Item Slot Widgets (detached popouts) ═══════════════════════════════
local W_ROW_H, W_ROW_Y0 = 32, 158

local function makeWidgetRow(f, i)
    local DS = _G.DaseekiSuite
    local r = CreateFrame("Frame", nil, f)
    r:SetSize(460, W_ROW_H)
    r:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -(W_ROW_Y0 + (i - 1) * W_ROW_H))
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
    r.bg:SetColorTexture(i % 2 == 0 and 0.12 or 0.08, 0.1, 0.12, 0.6)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(24, 24); r.icon:SetPoint("LEFT", 4, 0)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.label:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.label:SetWidth(100); r.label:SetJustifyH("LEFT")

    r.dirDD = DS.MakeSimpleDropdown(r, 144, 5, 92, { "Right", "Left", "Down", "Up" },
        function(c) local sid = r._slotId; if sid and Addon.db.settings.slotPopouts.buttons[sid] then
            Addon.db.settings.slotPopouts.buttons[sid].dir = c:lower() end end)
    r.perDD = DS.MakeSimpleDropdown(r, 242, 5, 50, PERROW,
        function(c) local sid = r._slotId; if sid and Addon.db.settings.slotPopouts.buttons[sid] then
            Addon.db.settings.slotPopouts.buttons[sid].perRow = tonumber(c) end end)
    r.unlink = DS.MakeButton(r, "Unlink", 298, 6, 72, 20, function()
        if r._slotId then Addon:ReleasePopoutAnchor(r._slotId) end
    end)
    r.unlink:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Release this widget's anchor", 1, 1, 1); GameTooltip:Show()
    end)
    r.unlink:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.remove = DS.MakeButton(r, "Remove", 376, 6, 78, 20, function()
        if r._slotId then Addon:RemoveSlotPopout(r._slotId) end
    end)
    return r
end

function Addon:BuildWidgetsTab(f)
    local DS = _G.DaseekiSuite
    DS.MakeSectionHeader(f, "Item Slot Widgets", 4, 8, 460)
    DS.MakeLabel(f, "Alt+left-click a slot on the character pane, or add one below. Drag a", nil, 4, 36)
    DS.MakeLabel(f, "widget next to another to anchor it (the dock side glows).", nil, 4, 54)
    DS.MakeCheckbox(f, "Lock all widget positions", 6, 78,
        function() return Addon.db.settings.slotPopouts.locked end,
        function(v) Addon.db.settings.slotPopouts.locked = v and true or false end)
    DS.MakeLabel(f, "Widget scale", nil, 250, 74)
    local sc = DS.MakeSlider(f, 332, 80, 112, nil, 0.5, 2, 0.05,
        function() return Addon.db.settings.slotPopouts.scale or 1 end,
        function(v) Addon:SetPopoutScale(v) end,
        function(v) return string.format("%.2f", v) end)
    if sc._valLbl then sc._valLbl:ClearAllPoints(); sc._valLbl:SetPoint("TOP", sc, "BOTTOM", 0, -1) end

    local slotNames, nameToId = {}, {}
    for _, s in ipairs(Addon.SLOTS) do slotNames[#slotNames + 1] = s.name; nameToId[s.name] = s.id end
    DS.MakeLabel(f, "Add widget for slot:", nil, 6, 116)
    local addDD = DS.MakeSimpleDropdown(f, 150, 112, 150, slotNames, nil)
    addDD:SetValue(Addon.SLOTS[1].name)
    DS.MakeButton(f, "Add", 308, 112, 60, 22, function()
        local sid = nameToId[addDD:GetValue()]
        if sid and not Addon.db.settings.slotPopouts.buttons[sid] then Addon:ShowSlotPopout(sid) end
        Addon:RefreshWidgetsTab()
    end)

    DS.MakeLabel(f, "Slot",      nil, 12,  142)
    DS.MakeLabel(f, "Direction", nil, 150, 142)
    DS.MakeLabel(f, "Per row",   nil, 250, 142)
    DS.MakeSeparator(f, 4, 152, 460)

    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.empty:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -(W_ROW_Y0 + 8))
    f.empty:SetText("No widgets yet — add one above or alt+left-click a slot.")
    f.empty:Hide()
    f.rows = {}
end

function Addon:RefreshWidgetsTab()
    local f = Addon.frames and Addon.frames.widgets
    if not f or not f.rows then return end
    local list = {}
    for _, sid in ipairs(Addon.SLOT_IDS) do
        if Addon.db.settings.slotPopouts.buttons[sid] then list[#list + 1] = sid end
    end
    for _, r in ipairs(f.rows) do r:Hide() end
    for i, sid in ipairs(list) do
        local r = f.rows[i] or makeWidgetRow(f, i)
        f.rows[i] = r
        r._slotId = sid
        r.icon:SetTexture(GetInventoryItemTexture("player", sid) or slotEmptyTex(sid))
        r.label:SetText(slotName(sid))
        local cfg = Addon.db.settings.slotPopouts.buttons[sid]
        r.dirDD:SetValue(cap(cfg.dir or "right"))
        r.perDD:SetValue(tostring(cfg.perRow or 5))
        r.unlink:SetEnabled(cfg.anchor ~= nil)
        r:Show()
    end
    f.empty:SetShown(#list == 0)
end

-- ── Refresh (Sets tab) ────────────────────────────────────────────────────────
function Addon:RefreshSetList()
    local panel = Addon.panel
    if not panel or not panel.listChild then return end
    local sets = Addon:GetSetsSorted()
    if not panel.selectedSet or not Addon.db.sets[panel.selectedSet] then
        panel.selectedSet = sets[1] and sets[1].name or nil
    end
    for _, r in ipairs(panel.rows) do r:Hide() end
    for i, set in ipairs(sets) do
        local r = panel.rows[i]
        if not r then
            r = CreateFrame("Button", nil, panel.listChild)
            r:SetSize(L_W - 24, 28)
            r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
            r.sel = r:CreateTexture(nil, "BACKGROUND"); r.sel:SetAllPoints()
            r.sel:SetColorTexture(0.2, 0.4, 0.8, 0.5); r.sel:Hide()
            r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(22, 22)
            r.icon:SetPoint("LEFT", 4, 0); r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            r.label = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            r.label:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.label:SetWidth(96); r.label:SetJustifyH("LEFT")
            r.keyText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            r.keyText:SetPoint("RIGHT", r, "RIGHT", -4, 0); r.keyText:SetJustifyH("RIGHT")
            r.keyText:SetTextColor(0.7, 0.85, 1)
            local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.1)
            r:SetScript("OnClick", function(self) panel.selectedSet = self._name; Addon:RefreshOptions() end)
            -- drag to reorder (cursor-position polling — see setup above)
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
        r:SetPoint("TOPLEFT", panel.listChild, "TOPLEFT", 0, -(i - 1) * 28)
        local shade = (i % 2 == 0) and 0.12 or 0.08
        r.bg:SetColorTexture(shade, shade, shade, 0.7)
        r.icon:SetTexture(set.icon or Addon.DEFAULT_ICON)
        r.label:SetText(set.name); r._name = set.name
        r.keyText:SetText(set.key or "")
        r.sel:SetShown(panel.selectedSet == set.name)
        r:Show()
    end
    panel.listChild:SetHeight(math.max(1, #sets * 28))
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
    if panel.nameEB and not panel.nameEB:HasFocus() then panel.nameEB:SetText(panel.selectedSet or "") end
    if panel.kbBtn then panel.kbBtn:SetText("Keybind: " .. ((set and set.key) or "\194\183")) end

    local goalMode = panel.goalMode and set ~= nil
    if panel.goalsBtn then panel.goalsBtn:SetText(goalMode and "Done (Goals)" or "Set Goals") end

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
              build = function(f) Addon:BuildSetsSection(f) end,
              refresh = function() Addon:RefreshOptions() end },
            { id = "swapper", title = "Set Swapper",
              build = function(f) Addon:BuildSwapperSection(f) end },
            { id = "charwin", title = "Character Window",
              build = function(f) Addon:BuildCharWindowSection(f) end },
            { id = "widgets", title = "Item Slot Widgets",
              build = function(f) Addon:BuildWidgetsSection(f) end,
              refresh = function() Addon:RefreshWidgetsTab() end },
        },
    })
end
