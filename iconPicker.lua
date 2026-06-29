--[[
    Daseeki Armory — searchable icon picker.

    A themed popup grid of icons with a search box at the top (filter by name
    substring, or type a numeric fileID). Mouse-wheel scrolls. Selecting an icon
    calls the onPick(tex) callback. Uses Daseeki-Core widgets/skin when present.

    Addon:ShowIconPicker(currentTex, onPick)
--]]

local _, Addon = ...

local COLS, ROWS, ICON, PAD = 8, 7, 34, 4
local GRID_TOP = 76
local picker

local function ensure()
    if picker then return picker end
    local DS = _G.DaseekiSuite

    local W = PAD + COLS * (ICON + PAD) + 16
    local H = GRID_TOP + ROWS * (ICON + PAD) + 14

    local f = CreateFrame("Frame", "DaseekiArmoryIconPicker", UIParent, "BackdropTemplate")
    f:SetSize(W, H)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetPoint("CENTER")
    f:SetMovable(true); f:EnableMouse(true)
    f:SetScript("OnMouseDown", function(s, b) if b == "LeftButton" then s:StartMoving() end end)
    f:SetScript("OnMouseUp",   function(s) s:StopMovingOrSizing() end)
    f:SetScript("OnShow", function(s)
        if DS and DS.ApplySkin then DS.ApplySkin(s) end
    end)
    if DS and DS.ApplySkin then
        DS.ApplySkin(f)
    else
        f:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0, 0, 0, 0.92)
        f:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    end

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", f, "TOP", 0, -12)
    f.title:SetText("Choose an Icon"); f.title:SetTextColor(1, 0.82, 0)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Hide() end)

    f.countText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.countText:SetPoint("BOTTOM", f, "BOTTOM", 0, 8)
    f.countText:SetTextColor(0.7, 0.7, 0.7)

    -- search box
    local search
    if DS and DS.MakeEditBox then
        search = DS.MakeEditBox(f, 14, 40, W - 28)
    else
        search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        search:SetSize(W - 28, 20); search:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -40)
        search:SetAutoFocus(false); search:SetFontObject(ChatFontNormal)
    end
    search:SetScript("OnTextChanged", function(self)
        -- shift-clicking an item inserts its hyperlink; grab its icon + name
        local linkId = self:GetText():match("|Hitem:(%d+)")
        if linkId then
            Addon:IndexItemIcon("item:" .. linkId)
            self:SetText((GetItemInfo(tonumber(linkId))) or "")
            return
        end
        picker._list   = Addon:SearchIcons(self:GetText())
        picker._offset = 0
        picker:RefreshGrid()
    end)
    search:SetScript("OnReceiveDrag", function(self)
        local ctype, _, link = GetCursorInfo()
        if ctype == "item" and link then
            ClearCursor()
            Addon:IndexItemIcon(link)
            self:SetText((GetItemInfo(link)) or "")
        end
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.search = search
    f.instructions = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.instructions:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -62)
    f.instructions:SetText("Search by icon or item name, or drag an item here")

    -- grid
    f.buttons = {}
    for i = 1, COLS * ROWS do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(ICON, ICON)
        local col = (i - 1) % COLS
        local row = math.floor((i - 1) / COLS)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 8 + col * (ICON + PAD), -(GRID_TOP + row * (ICON + PAD)))

        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints(); b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        b.sel = b:CreateTexture(nil, "OVERLAY")
        b.sel:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
        b.sel:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
        b.sel:SetColorTexture(1, 0.82, 0, 0)

        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.25)

        b:SetScript("OnClick", function(self)
            if self._tex ~= nil and picker._onPick then picker._onPick(self._tex) end
            picker:Hide()
        end)
        b:SetScript("OnEnter", function(self)
            if self._name then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(self._name, 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.buttons[i] = b
    end

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        local maxOff = math.max(0, math.ceil(#(picker._list or {}) / COLS) - ROWS)
        picker._offset = math.min(maxOff, math.max(0, (picker._offset or 0) - delta))
        picker:RefreshGrid()
    end)

    function f:RefreshGrid()
        local list  = self._list or {}
        local start = (self._offset or 0) * COLS
        for i, b in ipairs(self.buttons) do
            local e = list[start + i]
            if e then
                b.tex:SetTexture(e.tex)
                b._tex  = e.tex
                b._name = e.name and e.name:upper() or (e.id and ("Icon " .. e.id))
                local isCur = self._current and tostring(self._current) == tostring(e.tex)
                b.sel:SetColorTexture(1, 0.82, 0, isCur and 0.7 or 0)
                b:Show()
            else
                b._tex, b._name = nil, nil
                b:Hide()
            end
        end
        self.countText:SetText(#list .. " icons")
    end

    picker = f
    return f
end

function Addon:ShowIconPicker(currentTex, onPick)
    local f = ensure()
    if Addon.IndexOwnedItems then Addon:IndexOwnedItems() end
    if Addon.IndexSpellbook then Addon:IndexSpellbook() end
    f._onPick  = onPick
    f._current = currentTex
    f._offset  = 0
    f.search:SetText("")
    f._list = Addon:SearchIcons("")
    f:RefreshGrid()
    f:Show()
    f:Raise()
end
