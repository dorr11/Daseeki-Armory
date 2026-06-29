--[[
    Daseeki Armory — character-pane "equip set" flyout (ItemRack minimap-button style).

    Hovering the Armory button on the Blizzard character pane pops a vertical list of
    every set for this character; clicking one equips it (or queues it for after combat,
    handled by Addon:EquipSet). Auto-hides shortly after the mouse leaves both the
    flyout and its anchor, mirroring the item flyout in flyout.lua.
--]]

local _, Addon = ...

local ROWH, MAX_ROWS = 26, 10
local MIN_W, MAX_W = 90, 320
local ICON_W, ICON_GAP, SIDE_PAD = 20, 6, 6
local setFlyout

local function ensure()
    if setFlyout then return setFlyout end
    local DS = _G.DaseekiSuite

    local f = CreateFrame("Frame", "DaseekiArmorySetFlyout", UIParent, "BackdropTemplate")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:Hide()
    if DS and DS.ApplySkin then
        DS.ApplySkin(f)
    else
        f:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0, 0, 0, 0.95)
        f:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    end

    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.empty:SetPoint("CENTER")
    f.empty:SetText("No sets")
    f.empty:Hide()

    -- unconstrained, unshown font string used only to measure each set name's
    -- natural width so the flyout can size itself to the widest one
    f.measure = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")

    f.rows = {}
    f._offset = 0

    f:SetScript("OnMouseWheel", function(self, delta)
        self._offset = math.max(0, math.min(self._maxOff or 0, self._offset - delta))
        self:Layout()
    end)

    -- close as soon as the mouse leaves both the flyout and its anchor (no delay)
    f:SetScript("OnUpdate", function(self, e)
        self._t = (self._t or 0) + e
        if self._t < 0.04 then return end
        self._t = 0
        local over = self:IsMouseOver()
            or (self._anchor and self._anchor.IsMouseOver and self._anchor:IsMouseOver())
        if not over then self:Hide() end
    end)

    local function makeRow(i)
        local r = CreateFrame("Button", nil, f)
        r:SetHeight(ROWH)
        r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
        r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(ICON_W, ICON_W); r.icon:SetPoint("LEFT", 2, 0)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        r.label = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        r.label:SetPoint("LEFT", r.icon, "RIGHT", ICON_GAP, 0); r.label:SetJustifyH("LEFT")
        local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.25)
        r:SetScript("OnClick", function(self)
            if self._name then Addon:EquipSet(self._name) end
            setFlyout:Hide()
        end)
        r:SetScript("OnEnter", function(self)
            if not self._name then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self._name, 1, 0.82, 0)
            if self._key and self._key ~= "" then GameTooltip:AddLine("Keybind: " .. self._key, 0.7, 0.85, 1) end
            GameTooltip:AddLine("Click to equip", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.rows[i] = r
        return r
    end

    function f:Layout()
        local sets = self._sets or {}
        local n = #sets
        local vis = math.min(n, MAX_ROWS)
        self._maxOff = math.max(0, n - vis)
        self._offset = math.max(0, math.min(self._maxOff, self._offset or 0))

        -- size to the widest set name (measured across all sets, not just the
        -- visible window, so the box doesn't resize while scrolling)
        local maxTextW = 0
        for _, set in ipairs(sets) do
            self.measure:SetText(set.name or "")
            local tw = self.measure:GetStringWidth()
            if tw > maxTextW then maxTextW = tw end
        end
        local width = math.max(MIN_W, math.min(MAX_W,
            SIDE_PAD * 2 + ICON_W + ICON_GAP + maxTextW + 8))

        self:SetSize(width, math.max(8 + vis * ROWH, 36))

        for _, r in ipairs(self.rows) do r:Hide() end
        local start = self._offset
        for i = 1, vis do
            local set = sets[start + i]
            if set then
                local r = self.rows[i] or makeRow(i)
                r:SetWidth(width - SIDE_PAD * 2)
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", self, "TOPLEFT", SIDE_PAD, -(4 + (i - 1) * ROWH))
                r.bg:SetColorTexture((i % 2 == 0) and 0.12 or 0.08, 0.1, 0.12, 0.6)
                r.icon:SetTexture(set.icon or Addon.DEFAULT_ICON)
                r.label:SetText(set.name)
                r._name, r._key = set.name, set.key
                r:Show()
            end
        end
        self.empty:SetShown(n == 0)
    end

    setFlyout = f
    return f
end

function Addon:ShowSetFlyout(anchor)
    local f = ensure()
    f._anchor = anchor
    f._offset = 0
    f._sets   = Addon:GetSetsSorted()
    f:ClearAllPoints()
    f:SetPoint("TOP", anchor, "BOTTOM", 0, 2)
    f:Layout()
    f:Show()
    f:Raise()
    return f
end

function Addon:HideSetFlyout()
    if setFlyout then setFlyout:Hide() end
end

-- ── Icon-grid variant (widget "Dropdown" mode, Type = Icon) ────────────────────
-- Icon-only grid wrapping after settings.widget.dropdownPerRow, opening in
-- settings.widget.dropdownDir — mirrors flyout.lua's inventory-item grid layout.
local GRID_ICON, GRID_PAD, GRID_MARGIN, GRID_MAX_ROWS = 32, 3, 6, 8
local iconFlyout

local function curPerRow()
    local n = (Addon.db and Addon.db.settings.widget.dropdownPerRow) or 5
    return math.max(1, math.min(12, math.floor(n)))
end

local function ensureIconFlyout()
    if iconFlyout then return iconFlyout end
    local DS = _G.DaseekiSuite

    local f = CreateFrame("Frame", "DaseekiArmorySetIconFlyout", UIParent, "BackdropTemplate")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:Hide()
    if DS and DS.ApplySkin then
        DS.ApplySkin(f)
    else
        f:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0, 0, 0, 0.95)
        f:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    end

    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.empty:SetPoint("CENTER")
    f.empty:SetText("No sets")
    f.empty:Hide()

    f.btns = {}
    f._offset = 0

    f:SetScript("OnMouseWheel", function(self, delta)
        self._offset = math.max(0, math.min(self._maxOff or 0, self._offset - delta))
        self:Layout()
    end)

    f:SetScript("OnUpdate", function(self, e)
        if Addon.db.settings.widget.dropdownAlwaysOpen then return end  -- stays open regardless of the mouse
        self._t = (self._t or 0) + e
        if self._t < 0.04 then return end
        self._t = 0
        local over = self:IsMouseOver()
            or (self._anchor and self._anchor.IsMouseOver and self._anchor:IsMouseOver())
        if not over then self:Hide() end
    end)

    local function makeBtn(i)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(GRID_ICON, GRID_ICON)
        b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints()
        b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints()
        hl:SetColorTexture(1, 0.82, 0, 0.3)
        b:SetScript("OnEnter", function(self)
            if self._name then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(self._name, 1, 0.82, 0)
                GameTooltip:AddLine("Click to equip", 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function(self)
            if self._name then Addon:EquipSet(self._name) end
            -- "Always Open" never closes on pick — RefreshWidget re-Layout()s it
            -- in place once the equip finishes, to refresh the active-set highlight.
            if not Addon.db.settings.widget.dropdownAlwaysOpen then iconFlyout:Hide() end
        end)
        f.btns[i] = b
        return b
    end

    function f:Layout()
        local sets  = self._sets or {}
        local total = #sets
        local cols  = math.min(curPerRow(), math.max(1, total))
        local rows  = math.max(1, math.ceil(total / cols))
        local vis   = math.min(rows, GRID_MAX_ROWS)
        self._maxOff = math.max(0, rows - vis)
        self._offset = math.max(0, math.min(self._maxOff, self._offset or 0))

        local w = GRID_MARGIN * 2 + cols * (GRID_ICON + GRID_PAD) - GRID_PAD
        local h = GRID_MARGIN * 2 + vis * (GRID_ICON + GRID_PAD) - GRID_PAD
        if total == 0 then
            self:SetSize(80, 36)
        else
            self:SetSize(w, h)
        end

        for _, b in ipairs(self.btns) do b:Hide() end
        local start = self._offset * cols
        for slotN = 1, vis * cols do
            local gidx = start + slotN
            if gidx <= total then
                local b = self.btns[slotN] or makeBtn(slotN)
                local col = (slotN - 1) % cols
                local row = math.floor((slotN - 1) / cols)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", self, "TOPLEFT", GRID_MARGIN + col * (GRID_ICON + GRID_PAD), -(GRID_MARGIN + row * (GRID_ICON + GRID_PAD)))
                local set = sets[gidx]
                b.icon:SetTexture(set.icon or Addon.DEFAULT_ICON)
                b._name = set.name
                if Addon.db.currentSet == set.name then
                    b.bg:SetColorTexture(1, 0.82, 0, 0.4)
                else
                    b.bg:SetColorTexture(0, 0, 0, 0.5)
                end
                b:Show()
            end
        end
        self.empty:SetShown(total == 0)
    end

    iconFlyout = f
    return f
end

function Addon:ShowSetIconFlyout(anchor)
    local f = ensureIconFlyout()
    f._anchor = anchor
    f._offset = 0
    f._sets   = Addon:GetSetsSorted()
    f:ClearAllPoints()
    local dir = Addon.db.settings.widget.dropdownDir or "right"
    if dir == "down" then
        f:SetPoint("TOP", anchor, "BOTTOM", 0, 2)
    elseif dir == "up" then
        f:SetPoint("BOTTOM", anchor, "TOP", 0, -2)
    elseif dir == "left" then
        f:SetPoint("TOPRIGHT", anchor, "TOPLEFT", 2, 0)
    else -- right
        f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", -2, 0)
    end
    f:Layout()
    f:Show()
    f:Raise()
    return f
end

function Addon:HideSetIconFlyout()
    if iconFlyout then iconFlyout:Hide() end
end

-- Dispatches to the List or Icon variant based on settings.widget.dropdownType.
function Addon:ShowSetDropdown(anchor)
    if Addon.db.settings.widget.dropdownType == "list" then
        return Addon:ShowSetFlyout(anchor)
    end
    return Addon:ShowSetIconFlyout(anchor)
end
