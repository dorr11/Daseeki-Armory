--[[
    Daseeki Armory — on-screen radial set switcher.

    A small movable anchor button (shows the current set's icon) that opens either a
    radial fan or a dropdown flyout of your sets — on click or on hover, per
    settings.widget.openTrigger. Drag to move when unlocked (saved verbatim via
    GetPoint, scale-safe).
--]]

local _, Addon = ...

local function SaveWidgetPos(self)
    local p, _, rp, x, y = self:GetPoint()
    local w = Addon.db.settings.widget
    w.point, w.relPoint, w.x, w.y = p, rp, x, y
end

function Addon:InitWidget()
    if Addon.widget then return end
    local w = Addon.db.settings.widget

    local anchor = CreateFrame("Button", "DaseekiArmoryWidget", UIParent)
    anchor:SetSize(40, 40)
    anchor:SetFrameStrata("MEDIUM")
    anchor:SetScale(w.scale or 1)
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    anchor:SetPoint(w.point or "CENTER", UIParent, w.relPoint or "CENTER", w.x or 0, w.y or 0)
    anchor:RegisterForClicks("LeftButtonUp")
    anchor:RegisterForDrag("LeftButton")

    local bg = anchor:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(Addon:Col("inset", 0.55))

    local icon = anchor:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2); icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    anchor.icon = icon

    local border = CreateFrame("Frame", nil, anchor, "BackdropTemplate")
    border:SetPoint("TOPLEFT", -2, 2); border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
    border:SetBackdropBorderColor(Addon:Col("bronze", 0.6))

    local hl = anchor:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(Addon:Col("brand", 0.25))

    anchor:SetScript("OnDragStart", function(self)
        if not Addon.db.settings.widget.locked then self:StartMoving() end
    end)
    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveWidgetPos(self)
    end)
    -- EFFECTIVE mode, not the stored one. The stored value can be "chat", which
    -- is a PLACEMENT that needs Daseeki-Chat's panel: without it the swapper
    -- falls back to the shipped default (radial) rather than to nothing. For
    -- "radial" and "dropdown" the effective answer IS the stored one, so those
    -- two paths are unchanged.
    local function openSwitcher(self)
        if Addon:EffectiveSwapperMode() == "dropdown" then
            Addon:ShowSetDropdown(self)
        else
            Addon:ShowRadial()
        end
    end
    anchor:SetScript("OnClick", function(self)
        if Addon.db.settings.widget.openTrigger == "hover" then return end  -- hover already opens it
        if Addon:EffectiveSwapperMode() == "dropdown" then
            openSwitcher(self)
        else
            Addon:ToggleRadial()
        end
    end)
    anchor:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Daseeki Armory", 1, 0.82, 0)
        local cur = Addon.db.currentSet
        if cur then GameTooltip:AddLine("Current: " .. cur, 0.8, 0.8, 0.8) end
        local hover = Addon.db.settings.widget.openTrigger == "hover"
        GameTooltip:AddLine(hover and "Hover to choose a set" or "Click to choose a set", 1, 1, 1)
        if not Addon.db.settings.widget.locked then
            GameTooltip:AddLine("Drag to move", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
        if hover then openSwitcher(self) end
    end)
    anchor:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local radial = CreateFrame("Frame", nil, anchor)
    radial:SetAllPoints(anchor)
    radial:SetFrameStrata("HIGH")
    radial:Hide()
    anchor.radial = radial
    anchor.radialButtons = {}

    -- Hover mode only: the ring's buttons sit far outside the small anchor's own
    -- bounds, so closing on the anchor's OnLeave alone would close it the instant
    -- the mouse moves toward a ring button. Poll instead, like the item flyouts do.
    radial:SetScript("OnUpdate", function(self, e)
        if Addon.db.settings.widget.openTrigger ~= "hover" then return end
        self._t = (self._t or 0) + e
        if self._t < 0.05 then return end
        self._t = 0
        if anchor:IsMouseOver() then return end
        for _, b in ipairs(anchor.radialButtons) do
            if b:IsShown() and b:IsMouseOver() then return end
        end
        self:Hide()
    end)

    Addon.widget = anchor
    Addon:RefreshWidget()
end

function Addon:ToggleRadial()
    local a = Addon.widget
    if not a then return end
    if a.radial:IsShown() then
        a.radial:Hide()
    else
        Addon:ShowRadial()
    end
end

function Addon:ShowRadial()
    local a = Addon.widget
    if not a then return end
    Addon:BuildRadial()
    a.radial:Show()
end

function Addon:BuildRadial()
    local a = Addon.widget
    if not a then return end
    local sets   = Addon:GetSetsSorted()
    local radius = Addon.db.settings.widget.radius or 92
    local n      = #sets

    for _, b in ipairs(a.radialButtons) do b:Hide() end
    if n == 0 then return end

    for i, set in ipairs(sets) do
        local b = a.radialButtons[i]
        if not b then
            b = CreateFrame("Button", nil, a.radial)
            b:SetSize(36, 36)
            b:RegisterForClicks("LeftButtonUp")
            b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetPoint("TOPLEFT", 2, -2); b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
            b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            local bhl = b:CreateTexture(nil, "HIGHLIGHT"); bhl:SetAllPoints()
            bhl:SetColorTexture(Addon:Col("brand", 0.3))
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(self._setName or "", 1, 1, 1)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:SetScript("OnClick", function(self)
                Addon:EquipSet(self._setName)
                a.radial:Hide()
            end)
            a.radialButtons[i] = b
        end
        local angle = (math.pi / 2) - (i - 1) * (2 * math.pi / n)  -- top, clockwise
        b:ClearAllPoints()
        b:SetPoint("CENTER", a, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
        b.icon:SetTexture(set.icon or Addon.DEFAULT_ICON)
        b._setName = set.name
        if Addon.db.currentSet == set.name then
            b.bg:SetColorTexture(Addon:Col("brand", 0.4))
        else
            b.bg:SetColorTexture(Addon:Col("inset", 0.6))
        end
        b:Show()
    end
end

function Addon:RefreshWidget()
    local a = Addon.widget
    if not a then return end
    local w = Addon.db.settings.widget
    a:SetScale(w.scale or 1)

    local cur = Addon.db.currentSet and Addon.db.sets[Addon.db.currentSet]
    a.icon:SetTexture((cur and cur.icon) or Addon.DEFAULT_ICON)

    -- THE "Chat" PLACEMENT: the column docked to the chat panel IS the swapper,
    -- so the floating anchor button (and its radial, and its flyout) stand down
    -- while it is up. This branch is reachable ONLY when the mode is "chat" AND
    -- Daseeki-Chat answers — every other configuration takes the path below
    -- exactly as it did before.
    local docked = Addon.ChatDockActive and Addon:ChatDockActive() or false

    if w.show and not docked then
        a:Show()
    else
        a:Hide(); a.radial:Hide()
    end
    if a.radial:IsShown() then Addon:BuildRadial() end

    -- "Always Open" (icon type only): keep the icon flyout permanently shown,
    -- bypassing hover/click entirely.
    local wantAlwaysOpen = (not docked) and w.show and w.mode == "dropdown"
        and w.dropdownType ~= "list" and w.dropdownAlwaysOpen
    if wantAlwaysOpen then
        Addon:ShowSetIconFlyout(a)
    elseif Addon.HideSetIconFlyout then
        Addon:HideSetIconFlyout()
    end

    -- One refresh beat covers the column too: RefreshWidget is what equip.lua,
    -- sets.lua and the options pane already call after every swap, add, rename
    -- and delete, so the docked icons (and the green border on the equipped one)
    -- follow the same signals the radial's highlight always has. Inert when the
    -- dock is not active — RefreshChatDock's first line refuses.
    if Addon.RefreshChatDock then Addon:RefreshChatDock() end
end

function Addon:SetWidgetShown(show)
    Addon.db.settings.widget.show = show and true or false
    Addon:RefreshWidget()
end
