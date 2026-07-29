--[[
    Daseeki Armory — trinket quick-swap (TrinketMenu-parity essentials).

    Two things the base UI lacks:
      * Glanceable COOLDOWN readouts on the two equipped trinket slots (spiral + a
        numeric countdown), the headline TrinketMenu feature.
      * Cooldown text on trinket entries in the shared item flyout, so you can pick a
        trinket that is actually off cooldown.

    The SWAP itself is entirely Armory's existing plumbing: the paper-doll / slot-popout
    hover already opens Addon:ShowItemFlyout on the trinket slots and clicking equips via
    the secure equip/queue-on-combat path (EquipContainerItemToSlot / SwapEquippedSlots).
    This module only adds the cooldown affordances via a flyout DECORATOR hook and a
    per-slot cooldown display — no duplicate equip logic, no secure-frame handling.

    v1 is manual-swap parity; an auto-queue-on-cooldown toggle is intentionally out of
    scope. Fresh code — no lines derived from TrinketMenu.
--]]

local _, Addon = ...

local TRINKET_SLOTS = { 13, 14 }   -- Trinket0 (upper) / Trinket1 (lower)

local GetContainerItemCooldown =
    (C_Container and C_Container.GetContainerItemCooldown) or _G.GetContainerItemCooldown

local function isTrinketSlot(slotId) return slotId == 13 or slotId == 14 end
local function cdEnabled()
    return Addon.db and Addon.db.settings and Addon.db.settings.trinkets
        and Addon.db.settings.trinkets.showCooldowns
end

-- Short remaining-time string ("42", "3m"); nil for no real cooldown (the 0/GCD case).
local function cdText(start, duration)
    if not start or start == 0 or not duration or duration <= 1.5 then return nil end
    local remain = start + duration - GetTime()
    if remain <= 0 then return nil end
    if remain >= 60 then return string.format("%dm", math.ceil(remain / 60)) end
    return string.format("%d", math.ceil(remain))
end

-- ── Equipped-slot cooldown display ────────────────────────────────────────────
function Addon:UpdateTrinketCooldowns()
    local show = cdEnabled()
    for slotId, t in pairs(Addon._trinketCds or {}) do
        if show then
            local start, duration = GetInventoryItemCooldown("player", slotId)
            if start and start > 0 and duration and duration > 1.5 then
                t.cd:SetCooldown(start, duration)
                t.cd:Show()
                t.txt:SetText(cdText(start, duration) or "")
            else
                t.cd:SetCooldown(0, 0); t.cd:Hide(); t.txt:SetText("")
            end
        else
            t.cd:SetCooldown(0, 0); t.cd:Hide(); t.txt:SetText("")
        end
    end
end

-- ── Flyout decorator: cooldown text on trinket entries ────────────────────────
-- Called for every shown flyout button (item may be nil for the unequip cell). Only
-- trinket-slot flyouts get a countdown; other slots have their overlay cleared.
function Addon:DecorateTrinketFlyout(btn, item, slotId)
    if not isTrinketSlot(slotId) or not cdEnabled() or not item or not item.link then
        if btn._armTrinketCd then btn._armTrinketCd:SetText("") end
        return
    end
    if not btn._armTrinketCd then
        local t = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        Addon:TrySetNumeral(t)   -- telemetry countdown → numeral face (BRAND_SPEC §3)
        t:SetPoint("BOTTOM", btn, "BOTTOM", 0, 1)
        btn._armTrinketCd = t
    end
    local start, duration
    if item.equipped and item.invSlot then
        start, duration = GetInventoryItemCooldown("player", item.invSlot)
    elseif item.bag and item.slot and GetContainerItemCooldown then
        start, duration = GetContainerItemCooldown(item.bag, item.slot)
    end
    btn._armTrinketCd:SetText(cdText(start, duration) or "")
end

-- ── Init ──────────────────────────────────────────────────────────────────────
function Addon:InitTrinkets()
    if Addon._trinketsInit then return end
    Addon._trinketsInit = true

    -- cooldown spiral + numeric readout over each equipped trinket slot button
    Addon._trinketCds = {}
    for _, slotId in ipairs(TRINKET_SLOTS) do
        local btnName = (slotId == 13) and "CharacterTrinket0Slot" or "CharacterTrinket1Slot"
        local btn = _G[btnName]
        if btn then
            local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
            cd:SetAllPoints(btn)
            cd:SetDrawEdge(false)
            cd:SetHideCountdownNumbers(true)   -- our own text avoids double numbers
            local txt = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
            Addon:TrySetNumeral(txt)   -- telemetry countdown → numeral face (BRAND_SPEC §3)
            txt:SetPoint("BOTTOM", btn, "BOTTOM", 0, 2)
            Addon._trinketCds[slotId] = { cd = cd, txt = txt, btn = btn }
        end
    end

    -- cooldown text inside the trinket flyout (shared decorator registry)
    if Addon.AddFlyoutDecorator then
        Addon:AddFlyoutDecorator(function(btn, item, slotId)
            Addon:DecorateTrinketFlyout(btn, item, slotId)
        end)
    end

    -- refresh on cooldown/equip events, plus a light ticker while the sheet is open
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("BAG_UPDATE_COOLDOWN")
    ev:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function() Addon:UpdateTrinketCooldowns() end)
    Addon._trinketEv = ev

    Addon._trinketTicker = C_Timer.NewTicker(0.5, function()
        if _G.CharacterFrame and _G.CharacterFrame:IsShown() then
            Addon:UpdateTrinketCooldowns()
        end
    end)

    Addon:UpdateTrinketCooldowns()
end
