--[[
    Daseeki Armory — equipped-slot quality GLOW (suite soft-glow style).

    Quality-colored cues on the Blizzard PaperDollFrame equipment buttons and on the
    Armory item-flyout entries ("leads"), using the game's own item-quality colors
    (C_Item.GetItemQualityColor, falling back to ITEM_QUALITY_COLORS, then to a static
    table so the treatment is deterministic headless). Uncommon and up glow; poor/common
    are left plain so the sheet stays quiet.

    ── The cue is a soft GLOW, not a hard outline ─────────────────────────────────
    This file used to draw a 2px hard quality-colored SQUARE outline around each slot.
    Daseeki Bags 2.0 shipped the suite's soft-glow treatment (Bags borders.lua, the
    GLOW GEOMETRY block), and the character window now matches it parameter for
    parameter: ONE additive Interface\Buttons\UI-ActionButton-Border texture, drawn at
    OVERLAY sublevel -1, anchored CENTER on the slot button (deliberately NOT
    SetAllPoints) and sized buttonSize * 67/37 so the wash bleeds past the icon edge
    instead of rimming it. Alpha is a uniform 0.5 for every rarity — the COLOR carries
    the distinction, exactly as Bags does.

    The look ships as CONSTANTS (Addon.Borders.GLOW_*), not settings: no new
    SavedVariables key. The single existing toggle (settings.charWindow.qualityBorders)
    and the Uncommon+ floor are unchanged.

    Non-quality border art elsewhere in Armory — the slot-popout suite-border chrome,
    the paper-doll pressed/highlight states, the empty-slot artwork — is untouched;
    this file only ever drew the rarity cue.

    Deliberately SELF-CONTAINED (one toggle; a small glow factory; one event) so the
    long-term move into Daseeki-UI is a file transplant. The pure geometry/color layer
    (Addon.Borders) touches NO WoW API at load, which is what lets the headless harness
    gate the glow constants the way Bags gates its own.
--]]

local _, Addon = ...

local MIN_QUALITY = 2   -- uncommon+; below this a slot shows no colored glow

----------------------------------------------------------------------
-- PURE layer — geometry + color, no WoW API at load. Published so the harness
-- can gate the glow constants (the sibling contract with Bags 2.0's borders.lua).
----------------------------------------------------------------------
local Borders = {}
Addon.Borders = Borders

Borders.MIN_QUALITY   = MIN_QUALITY
-- The three suite glow parameters, identical to Bags 2.0 Borders.GLOW_*.
Borders.GLOW_TEXTURE  = "Interface\\Buttons\\UI-ActionButton-Border"
Borders.GLOW_SCALE    = 67 / 37   -- a 67px halo on a 37px item button
Borders.GLOW_ALPHA    = 0.5       -- uniform across every rarity

-- Static quality colors (Blizzard's ITEM_QUALITY_COLORS values; game facts). Reached
-- only when neither C_Item nor _G.ITEM_QUALITY_COLORS is present (the headless harness),
-- so QualityRGB is deterministic under test.
local FALLBACK = {
    [0] = { 0.62, 0.62, 0.62 }, -- Poor (grey)
    [1] = { 1.00, 1.00, 1.00 }, -- Common (white)
    [2] = { 0.12, 1.00, 0.00 }, -- Uncommon (green)
    [3] = { 0.00, 0.44, 0.87 }, -- Rare (blue)
    [4] = { 0.64, 0.21, 0.93 }, -- Epic (purple)
    [5] = { 1.00, 0.50, 0.00 }, -- Legendary (orange)
    [6] = { 0.90, 0.80, 0.50 }, -- Artifact
    [7] = { 0.00, 0.80, 1.00 }, -- Heirloom
}
Borders._fallback = FALLBACK

-- Quality -> r,g,b (0..1), FULL SATURATION. C_Item is authoritative;
-- ITEM_QUALITY_COLORS is the FrameXML fallback; the static table is the last resort.
function Borders.QualityRGB(q)
    if q == nil then return nil end
    local CI = _G.C_Item
    if CI and CI.GetItemQualityColor then
        local r, g, b = CI.GetItemQualityColor(q)
        if r then return r, g, b end
    end
    local c = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    local f = FALLBACK[q]
    if f then return f[1], f[2], f[3] end
end

-- The halo's side length for a button of `buttonSize`, at the suite's 67/37 proportion,
-- so the wash bleeds past the icon by the same amount at any button size.
function Borders.GlowSize(buttonSize)
    local s = tonumber(buttonSize) or 0
    if s <= 0 then return 0 end
    return s * Borders.GLOW_SCALE
end

-- True when a colored glow should be shown for this quality given the toggle.
function Borders.ShouldShow(quality, enabled)
    if not enabled then return false end
    if quality == nil then return false end
    return quality >= MIN_QUALITY
end

----------------------------------------------------------------------
-- FRAME layer (in-game)
----------------------------------------------------------------------

local function bordersEnabled()
    return Addon.db and Addon.db.settings and Addon.db.settings.charWindow
        and Addon.db.settings.charWindow.qualityBorders
end

-- Size the halo to the button it belongs to. Read off the button rather than
-- hardcoded, so paper-doll slots and flyout leads each get the right wash.
local function layoutGlow(f)
    local g = f._glow
    if not g then return end
    local host = f._host
    local w = (host and host.GetWidth and host:GetWidth()) or 0
    local side = Borders.GlowSize(w)
    if side <= 0 then return end
    g:SetSize(side, side)
end

-- A soft additive quality halo washing over a button's icon (suite glow aesthetic).
-- The container spans the button; the halo is CENTERED in it and deliberately larger
-- than the button, so the wash bleeds over the icon edge on all sides.
local function makeGlow(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    f:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    f:SetFrameLevel((parent:GetFrameLevel() or 1) + 1)
    f._host = parent

    local g = f:CreateTexture(nil, "OVERLAY", nil, -1)
    g:SetTexture(Borders.GLOW_TEXTURE)
    g:SetBlendMode("ADD")
    g:SetPoint("CENTER", f, "CENTER", 0, 0)
    f._glow = g
    layoutGlow(f)

    -- The button size is only reliable once it has been laid out, and a scale change
    -- can move it under a pooled button; re-measure on every show.
    f:SetScript("OnShow", function(self) layoutGlow(self) end)
    f:Hide()
    return f
end

local function applyGlow(f, quality)
    local r, g, b = Borders.QualityRGB(quality)
    if Borders.ShouldShow(quality, true) and r then
        layoutGlow(f)
        f._glow:SetVertexColor(r, g, b, Borders.GLOW_ALPHA)
        f:Show()
    else
        f:Hide()
    end
end

-- ── Equipped paper-doll slots ─────────────────────────────────────────────────
function Addon:UpdateSlotBorders()
    local on = bordersEnabled()
    for slotId, glow in pairs(Addon._slotGlows or {}) do
        if on then
            applyGlow(glow, GetInventoryItemQuality("player", slotId))
        else
            glow:Hide()
        end
    end
end

-- ── Flyout decorator: glow the lead buttons by item quality ───────────────────
function Addon:DecorateFlyoutQuality(btn, item)
    if not btn._armQualGlow then
        btn._armQualGlow = makeGlow(btn)
    end
    local q = item and item.link and select(3, GetItemInfo(item.link))
    if bordersEnabled() then
        applyGlow(btn._armQualGlow, q)
    else
        btn._armQualGlow:Hide()
    end
end

-- ── Init ──────────────────────────────────────────────────────────────────────
function Addon:InitBorders()
    if Addon._bordersInit then return end
    Addon._bordersInit = true

    Addon._slotGlows = {}
    for _, s in ipairs(Addon.SLOTS) do
        if s.slotName then
            local btn = _G["Character" .. s.slotName]
            if btn then Addon._slotGlows[s.id] = makeGlow(btn) end
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
