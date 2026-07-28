--[[
    Daseeki Armory — equipped-slot quality borders (ColoredInventoryItems-parity).

    Quality-colored borders on the Blizzard PaperDollFrame equipment buttons and on the
    Armory item-flyout entries ("leads"), using the game's own item-quality colors
    (C_Item.GetItemQualityColor, falling back to ITEM_QUALITY_COLORS). Uncommon and up
    are bordered; poor/common are left plain so the sheet stays quiet.

    Deliberately SELF-CONTAINED (single toggle: settings.charWindow.qualityBorders; a
    small border factory; one event) so the long-term move into Daseeki-UI is a file
    transplant. Fresh code — no lines derived from ColoredInventoryItems.
--]]

local _, Addon = ...

local MIN_QUALITY = 2   -- uncommon+; below this a slot shows no colored border

-- Quality -> r,g,b (0..1). C_Item is authoritative; ITEM_QUALITY_COLORS is the fallback.
local function qualityColor(q)
    if not q then return nil end
    if C_Item and C_Item.GetItemQualityColor then
        local r, g, b = C_Item.GetItemQualityColor(q)
        if r then return r, g, b end
    end
    local c = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
end

local function bordersEnabled()
    return Addon.db and Addon.db.settings and Addon.db.settings.charWindow
        and Addon.db.settings.charWindow.qualityBorders
end

-- A thin flat colored border framing a button's icon (suite-flat aesthetic).
local function makeBorder(parent)
    local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", -1, 1)
    b:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 1, -1)
    b:SetFrameLevel((parent:GetFrameLevel() or 1) + 1)
    b:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    b:Hide()
    return b
end

local function applyBorder(border, quality)
    local r, g, b = qualityColor(quality)
    if quality and quality >= MIN_QUALITY and r then
        border:SetBackdropBorderColor(r, g, b, 1)
        border:Show()
    else
        border:Hide()
    end
end

-- ── Equipped paper-doll slots ─────────────────────────────────────────────────
function Addon:UpdateSlotBorders()
    local on = bordersEnabled()
    for slotId, border in pairs(Addon._slotBorders or {}) do
        if on then
            applyBorder(border, GetInventoryItemQuality("player", slotId))
        else
            border:Hide()
        end
    end
end

-- ── Flyout decorator: color the lead buttons by item quality ──────────────────
function Addon:DecorateFlyoutQuality(btn, item)
    if not btn._armQualBorder then
        btn._armQualBorder = makeBorder(btn)
    end
    local q = item and item.link and select(3, GetItemInfo(item.link))
    if bordersEnabled() then
        applyBorder(btn._armQualBorder, q)
    else
        btn._armQualBorder:Hide()
    end
end

-- ── Init ──────────────────────────────────────────────────────────────────────
function Addon:InitBorders()
    if Addon._bordersInit then return end
    Addon._bordersInit = true

    Addon._slotBorders = {}
    for _, s in ipairs(Addon.SLOTS) do
        if s.slotName then
            local btn = _G["Character" .. s.slotName]
            if btn then Addon._slotBorders[s.id] = makeBorder(btn) end
        end
    end

    if Addon.AddFlyoutDecorator then
        Addon:AddFlyoutDecorator(function(btn, item) Addon:DecorateFlyoutQuality(btn, item) end)
    end

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function() Addon:UpdateSlotBorders() end)
    Addon._bordersEv = ev

    Addon:UpdateSlotBorders()
end
