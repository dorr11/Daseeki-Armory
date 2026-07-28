--[[
    Daseeki Armory — shared inventory item flyout (ItemRack-style icon grid).

    Shows the bag items that fit a slot as ICON-ONLY buttons that wrap after N per
    row (N = settings.flyoutPerRow). Hover shows the item tooltip; click chooses /
    equips. Reused by the set builder (left-click a slot) and the paper-doll hover
    sidebar. Auto-hides shortly after the mouse leaves both it and its anchor.

    Addon:ShowItemFlyout(anchor, slotId, onChoose [, title])
        onChoose(item)  where item = { bag, slot, link, id }
--]]

local _, Addon = ...

-- Flyout decorator registry (additive, opt-in): other modules stamp extra visuals on
-- each shown flyout button — trinket cooldown text, quality borders — without this
-- file knowing about them. Each decorator is called per shown button with
-- (button, item-or-nil, slotId); errors surface via geterrorhandler (never swallowed).
Addon._flyoutDecorators = Addon._flyoutDecorators or {}
function Addon:AddFlyoutDecorator(fn)
    Addon._flyoutDecorators[#Addon._flyoutDecorators + 1] = fn
end
local function runDecorators(btn, item, slotId)
    for _, fn in ipairs(Addon._flyoutDecorators) do
        local ok, err = pcall(fn, btn, item, slotId)
        if not ok then geterrorhandler()(err) end
    end
end

local ICON, PAD, MARGIN = 32, 3, 6
local MAX_ROWS = 8
local UNEQUIP_TEX = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"  -- red X = take off / remove
local flyout

-- Default flyout direction/perRow per slot (weapons drop down 1-wide; everything else right 5-wide).
local DEFAULT_DIR    = { [16] = "down", [17] = "down", [18] = "down" }
local DEFAULT_PERROW = { [16] = 1,      [17] = 1,      [18] = 1      }

-- Per-slot flyout config { dir = "right"|"left"|"down"|"up", perRow = 1..12 }, lazily
-- seeded (perRow seeds from the legacy global flyoutPerRow if present).
function Addon:GetFlyoutConfig(slotId)
    local s = Addon.db.settings
    s.flyout = s.flyout or {}
    local c = s.flyout[slotId]
    if not c then
        c = { dir = DEFAULT_DIR[slotId] or "right", perRow = DEFAULT_PERROW[slotId] or s.flyoutPerRow or 5 }
        s.flyout[slotId] = c
    end
    return c
end

local function curPerRow()
    local n = (flyout and flyout._perRow) or 5
    return math.max(1, math.min(12, math.floor(n)))
end

local function ensure()
    if flyout then return flyout end
    local DS = _G.DaseekiSuite

    local f = CreateFrame("Frame", "DaseekiArmoryFlyout", UIParent, "BackdropTemplate")
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
    f.empty:SetText("No items")
    f.empty:Hide()

    f.btns = {}
    f._offset = 0

    f:SetScript("OnMouseWheel", function(self, delta)
        self._offset = math.max(0, math.min(self._maxOff or 0, self._offset - delta))
        self:Layout()
    end)

    -- item tooltip for a hovered row, gated by the flyoutTooltip setting
    local function showRowTooltip(row)
        if not row then return end
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        if row._unequip then
            GameTooltip:AddLine((flyout._unequip and flyout._unequip.label) or "Unequip", 1, 0.4, 0.4)
        elseif row._link then
            local mode = (Addon.db and Addon.db.settings and Addon.db.settings.flyoutTooltip) or "ctrl"
            if mode == "always" or IsControlKeyDown() then
                GameTooltip:SetHyperlink(row._link)
            else
                GameTooltip:AddLine((GetItemInfo(row._link)) or row._link, 1, 1, 1)
                GameTooltip:AddLine("Hold Ctrl for details", 0.5, 0.5, 0.5)
            end
        end
        GameTooltip:Show()
    end
    f._showRowTooltip = showRowTooltip
    f:RegisterEvent("MODIFIER_STATE_CHANGED")
    f:SetScript("OnEvent", function(self)
        if self:IsShown() and self._hoverRow then showRowTooltip(self._hoverRow) end
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

    local function makeBtn(i)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(ICON, ICON)
        b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
        b.bg:SetColorTexture(0, 0, 0, 0.5)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints()
        b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints()
        hl:SetColorTexture(1, 0.82, 0, 0.3)
        b:SetScript("OnEnter", function(self) flyout._hoverRow = self; flyout._showRowTooltip(self) end)
        b:SetScript("OnLeave", function() flyout._hoverRow = nil; GameTooltip:Hide() end)
        b:SetScript("OnClick", function(self)
            if self._unequip then
                if flyout._unequip and flyout._unequip.fn then flyout._unequip.fn() end
            elseif flyout._onChoose and self._item then
                flyout._onChoose(self._item)
            end
            flyout:Hide()
        end)
        f.btns[i] = b
        return b
    end

    function f:Layout()
        local items   = self._items or {}
        local nItems  = #items
        local hasUneq = self._unequip and true or false
        local total   = nItems + (hasUneq and 1 or 0)   -- unequip is always the last cell
        -- only as wide as needed: never more columns than there are cells
        local cols  = math.min(curPerRow(), math.max(1, total))
        local rows  = math.max(1, math.ceil(total / cols))
        local vis   = math.min(rows, MAX_ROWS)
        self._maxOff = math.max(0, rows - vis)
        self._offset = math.max(0, math.min(self._maxOff, self._offset or 0))

        local w = MARGIN * 2 + cols * (ICON + PAD) - PAD
        local h = MARGIN * 2 + vis * (ICON + PAD) - PAD
        if total == 0 then
            self:SetSize(80, 36)   -- room for the "No items" caption
        else
            self:SetSize(w, h)     -- snug: exactly fits the icons
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
                b:SetPoint("TOPLEFT", self, "TOPLEFT", MARGIN + col * (ICON + PAD), -(MARGIN + row * (ICON + PAD)))
                if gidx <= nItems then
                    local item = items[gidx]
                    b.icon:SetTexture(select(5, GetItemInfoInstant(item.link)) or "Interface\\Icons\\INV_Misc_QuestionMark")
                    b.icon:SetDesaturated(false)
                    b._link, b._item, b._unequip = item.link, item, nil
                else
                    b.icon:SetTexture(UNEQUIP_TEX)
                    b.icon:SetDesaturated(false)
                    b._link, b._item, b._unequip = nil, nil, true
                end
                runDecorators(b, b._item, self._slotId)
                b:Show()
            end
        end
        self.empty:SetShown(total == 0)
    end

    flyout = f
    return f
end

-- unequip (optional) = { fn = function() end, label = "Unequip current item" }; when
-- provided it renders as the last cell (a red X).
function Addon:ShowItemFlyout(anchor, slotId, onChoose, unequip, cfgOverride, includeEquipped)
    local f = ensure()
    local cfg = cfgOverride or Addon:GetFlyoutConfig(slotId)
    f._anchor   = anchor
    f._slotId   = slotId
    f._onChoose = onChoose
    f._unequip  = unequip
    f._offset   = 0
    f._away     = 0
    f._perRow   = cfg.perRow
    f._items    = Addon:GetInventoryItemsForSlot(slotId, includeEquipped)

    f:ClearAllPoints()
    -- slight overlap with the anchor so moving the cursor into the flyout never
    -- crosses a dead gap (which would close it now that there's no grace delay)
    local dir = cfg.dir or "right"
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

function Addon:HideItemFlyout()
    if flyout then flyout:Hide() end
end
