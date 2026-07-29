--[[
    Daseeki Armory — paper-doll hover sidebar.

    ItemRack-style: hovering an equipped slot on the Blizzard character sheet pops a
    flyout of the other items in your bags that fit that slot. Clicking one equips it
    (or queues it for after combat if you're in combat). Uses the shared flyout.
--]]

local _, Addon = ...

function Addon:InitPaperdoll()
    if Addon._paperdollHooked then return end
    Addon._paperdollHooked = true

    Addon._charSlotOverlay = Addon._charSlotOverlay or {}
    for _, s in ipairs(Addon.SLOTS) do
        -- skip cosmetic slots (no meaningful swap value)
        if s.slotName and s.id ~= 4 and s.id ~= 19 then
            local btn = _G["Character" .. s.slotName]
            if btn then
                local slotId, slotName = s.id, s.name
                -- combat-pending (to-be-equipped) overlay, upper-right of the slot
                local ovbg = btn:CreateTexture(nil, "OVERLAY", nil, 6)
                ovbg:SetSize(17, 17); ovbg:SetPoint("TOPRIGHT", 1, 1); ovbg:SetColorTexture(Addon:Col("inset", 0.9)); ovbg:Hide()
                local ov = btn:CreateTexture(nil, "OVERLAY", nil, 7)
                ov:SetSize(15, 15); ov:SetPoint("TOPRIGHT", 0, 0); ov:SetTexCoord(0.07, 0.93, 0.07, 0.93); ov:Hide()
                ov.bg = ovbg
                Addon._charSlotOverlay[slotId] = ov
                -- Alt+left-click spawns a detached popout for this slot.
                btn:HookScript("OnClick", function(self, button)
                    if button == "LeftButton" and IsAltKeyDown() then
                        Addon:ToggleSlotPopout(slotId)
                        if CursorHasItem() then ClearCursor() end  -- undo the default pickup
                    end
                end)
                btn:HookScript("OnEnter", function(self)
                    if Addon.db.settings.paperdollFlyout == false then return end
                    if CursorHasItem() then return end
                    local items = Addon:GetInventoryItemsForSlot(slotId)
                    local uneq
                    if GetInventoryItemLink("player", slotId) then
                        uneq = { fn = function() Addon:UnequipSlot(slotId) end, label = "Unequip current item" }
                    end
                    if #items == 0 and not uneq then return end
                    Addon:ShowItemFlyout(self, slotId, function(item)
                        if item.equipped then
                            Addon:SwapEquippedSlots(item.invSlot, slotId)
                        else
                            Addon:EquipContainerItemToSlot(item.bag, item.slot, slotId)
                        end
                    end, uneq)
                end)
            end
        end
    end

    Addon:CreateCharPaneButton()
    -- Safety net: ensure the button exists the first time the character pane opens
    -- (in case the slot frames weren't ready at login).
    if _G.CharacterFrame then
        _G.CharacterFrame:HookScript("OnShow", function() Addon:CreateCharPaneButton() end)
    end
end

-- Mirror the combat-pending overlays onto the Blizzard character-pane slots.
function Addon:UpdatePaperdollPending()
    for slotId, ov in pairs(Addon._charSlotOverlay or {}) do
        local pend = Addon._pendingSlots and Addon._pendingSlots[slotId]
        if pend then ov:SetTexture(pend); ov:Show(); ov.bg:Show()
        else ov:Hide(); ov.bg:Hide() end
    end
end

-- Small (20x20) Armory button on the character pane, centered under the lower
-- trinket slot; opens the hub directly to the Armory → Sets tab.
function Addon:CreateCharPaneButton()
    if Addon._charBtn then return end
    local anchor = _G.CharacterTrinket1Slot
    if not anchor then return end
    -- Parent to the same frame the equipment slots live in (a sibling of the slots),
    -- so it inherits the right strata/visibility and shows on top of the pane art.
    local parent = anchor:GetParent() or _G.PaperDollFrame or _G.CharacterFrame
    if not parent then return end

    local b = CreateFrame("Button", "DaseekiArmoryCharButton", parent)
    b:SetSize(20, 20)
    b:SetPoint("TOP", anchor, "BOTTOM", 0, -6)
    b:SetFrameStrata(anchor:GetFrameStrata() or "HIGH")
    b:SetFrameLevel((anchor:GetFrameLevel() or 1) + 5)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); b.bg:SetColorTexture(Addon:Col("inset", 0.5))
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1); b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.icon:SetTexture("Interface\\Icons\\INV_Shield_26")
    local border = CreateFrame("Frame", nil, b, "BackdropTemplate")
    border:SetPoint("TOPLEFT", -1, 1); border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8 })
    border:SetBackdropBorderColor(Addon:Col("bronze", 0.6))
    local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(Addon:Col("brand", 0.3))
    -- hover: ItemRack-style set flyout; right-click: open the options panel
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then Addon:OpenToSets() end
    end)
    b:SetScript("OnEnter", function(self) Addon:ShowSetFlyout(self) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Raise()
    Addon._charBtn = b
end
