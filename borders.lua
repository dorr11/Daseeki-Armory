--[[
    Daseeki Armory — equipped-slot quality GLOW (suite soft-glow style).

    Quality-colored cues on the Blizzard PaperDollFrame equipment buttons and on the
    Armory item-flyout entries ("leads"), using the game's own item-quality colors
    (C_Item.GetItemQualityColor, falling back to ITEM_QUALITY_COLORS, then to a static
    table so the treatment is deterministic headless).

    ── The cue is a soft GLOW, not a hard outline — now 1.x-EXACT ────────────────
    This file used to draw a 2px hard quality-colored SQUARE outline around each slot.
    The suite then shipped a soft additive halo, and this file matched Bags 2.0
    parameter for parameter. Round 1 of the glow work then pinned BOTH files to the
    clean-room CII_BEHAVIOR_SPEC.md §2 numbers (68/37, 0.49, a (0, 1) nudge, a plain
    OVERLAY texture in a child frame one level ABOVE the button).

    That is no longer the target. The spec is a clean-room description of a THIRD-PARTY
    reference addon; the owner's target is verbatim "what 1.x looks like", and 1.x is
    OUR OWN code (Daseeki-Bags on main), which we can read. Bags 2.0's forensic pass
    transcribed 1.x directly and that transcription is now the SUITE STANDARD. This file
    is trued up to it: the sibling contract is restored, with Bags 2.0's borders.lua
    glow block as the authority rather than the spec.

    1.x anatomy (Daseeki-Bags on main, transcribed with file:line by the Bags block):
      core/classes/item.lua:54   CreateTexture(nil, 'OVERLAY', nil, -1)
      core/classes/item.lua:55   :SetTexture('Interface/Buttons/UI-ActionButton-Border')
      core/classes/item.lua:56   :SetBlendMode('ADD')
      core/classes/item.lua:57   :SetPoint('CENTER')          -- NO (0,1) offset
      core/classes/item.lua:58   :SetSize(67, 67)             -- 67, not 68
      core/api/settings.lua:34   glowAlpha = 0.5              -- the DEFAULT, superseded
    ONE additive halo, uniform alpha for every rarity — the COLOR carries the
    distinction, the intensity never varies.

    ── ALPHA IS AN OWNER-PROFILE ROW, NOT A DEFAULT ROW ─────────────────────────
    glowAlpha is the ONE glow parameter 1.x exposes as a slider (Daseeki-Bags
    config/panels/slotOptions.lua:70) and the owner moved it years ago. His live value:

      WTF/Account/309992577#1/SavedVariables/Daseeki-Bags.lua:3621  ["glowAlpha"] = 0.77

    (accounts #2 and #3 read 0.87; #1 is his main and is the spec). Shipping 1.x's
    untouched 0.5 made the additive wash faint enough that the crisp quality RING out-read
    it, and the cell registered as a hard border rather than a glow that fades inward.
    Bags 2.0 fixed this on its grid; this file mirrors the constant exactly so the
    character window and the bag grid stay one look.

    NO RING ROW HERE. The Bags fix came with a ring-vs-wash investigation (does 1.x dim
    the template IconBorder, and does that region even exist on Era 1.15.9?); the verdict
    was that 1.x renders the ring at FULL alpha, applying glowAlpha to the halo alone
    (Daseeki-Bags item.lua:208 vs :210/:220), so Bags' ring was left untouched. The
    evidence chain lives at Bags 2.0 borders.lua Borders.SetIconBorder. It does not reach
    this file: Armory drives NO IconBorder on any surface (grep-verified across the repo)
    — it dresses Blizzard's own _G["Character"..slotName] paper-doll buttons and the
    flyout leads with this halo and nothing else. The halo IS the whole cue here, so the
    alpha is the only lever, and mirroring it is the entire change.

    LAYERING is the row with teeth, and it changes what this window looks like in
    practice. 1.x's halo is a texture ON the button at OVERLAY sublevel -1, so it sorts
    BELOW the button's other OVERLAY art. Round 1's level+1 container put the halo ABOVE
    everything — Armory's own trinket-cooldown readout, the combat-pending overlay icons,
    and the neighbouring slots' art. We now reproduce 1.x: the container sits at the
    HOST BUTTON'S OWN frame level and the halo is OVERLAY sublevel -1, which puts it
    under every one of those (they are OVERLAY sublevel 0 / 6 / 7 on the button itself).

    Those are FIXED pixels in 1.x, which only ever draws on 37px buttons. Ours are not
    fixed: paper-doll slots are 37px but flyout leads are 32px, and Bags' density slider
    moves its cells. So the numbers are carried as RATIOS against 1.x's own 37px button
    (67/37, 58/37, 0) and derived from the host button's measured width — exact at 37px,
    identical in proportion at any other size.

    ── Spec §3: this window is the EVERY-QUALITY surface ─────────────────────────
    The single most important asymmetry in the reference is that quality gating depends
    on HOW the quality was resolved:

      * GetInventoryItemQuality (equipped slots, inspect) borders ANY non-nil quality —
        poor and common included. Poor gets a near-black 0.1/0.1/0.1 tint, common gets
        white. An empty slot returns nil and stays unbordered.
      * A GetItemInfo lookup off an item link (bags, bank, merchant) borders only
        above Common.

    The paper-doll slots take the first path, so they now glow at EVERY quality — that
    is the change the owner was seeing the absence of. The Armory flyout takes the
    second path (it resolves quality from an item link), so it keeps the Uncommon+
    floor. One predicate, two floors, chosen by the resolution path exactly as the
    reference does.

    The look ships as CONSTANTS (Addon.Borders.GLOW_*), not settings: no new
    SavedVariables key. 1.x exposes alpha as a glowAlpha slider (and the spec exposes an
    "intensity" clamped [0.1, 1.0]); we deliberately expose neither, and pin the OWNER'S
    OWN slider position (0.77) as our one value.
    The single existing toggle (settings.charWindow.qualityBorders) is unchanged.

    NOT ported: the spec §5-6 defects — in particular the reference's merchant toggle
    that is never consulted. We honor our own toggle on every surface.

    Non-quality border art elsewhere in Armory — the slot-popout suite-border chrome,
    the paper-doll pressed/highlight states, the empty-slot artwork — is untouched;
    this file only ever drew the rarity cue.

    Deliberately SELF-CONTAINED (one toggle; a small glow factory; one event) so the
    long-term move into Daseeki-UI is a file transplant. The pure geometry/color layer
    (Addon.Borders) touches NO WoW API at load, which is what lets the headless harness
    gate the glow constants the way Bags gates its own.
--]]

local _, Addon = ...

----------------------------------------------------------------------
-- PURE layer — geometry + color, no WoW API at load. Published so the harness
-- can gate the glow constants (the sibling contract with Bags 2.0's borders.lua).
----------------------------------------------------------------------
local Borders = {}
Addon.Borders = Borders

-- Spec §3 gating floors, one per resolution path.
local EQUIPPED_MIN_QUALITY = 0   -- GetInventoryItemQuality: ANY non-nil quality glows
local BAG_MIN_QUALITY      = 2   -- GetItemInfo off a link: above Common only
Borders.EQUIPPED_MIN_QUALITY = EQUIPPED_MIN_QUALITY
Borders.BAG_MIN_QUALITY      = BAG_MIN_QUALITY
Borders.MIN_QUALITY          = BAG_MIN_QUALITY   -- back-compat alias (== the link-path floor)

----------------------------------------------------------------------
-- SUITE GLOW GEOMETRY — TRANSCRIBED FROM 1.x, NOT FROM THE SPEC
--
-- The sibling contract is restored and its AUTHORITY is Daseeki-Bags2-beta's
-- borders.lua "SUITE GLOW GEOMETRY" block (branch v2), which transcribed 1.x
-- (Daseeki-Bags on main) line by line. Every citation below is that block's citation.
-- Where 1.x and CII_BEHAVIOR_SPEC.md §2 disagree, 1.x wins — four rows disagree
-- (scale, alpha, offset, layering) and all four are locked by the harness.
--
-- These ship as CONSTANTS, not settings — no new SavedVariables key.
----------------------------------------------------------------------
Borders.GLOW_TEXTURE  = "Interface\\Buttons\\UI-ActionButton-Border"  -- 1.x item.lua:55
Borders.GLOW_REF_BUTTON = 37        -- 1.x: the template item button, never resized
Borders.GLOW_SCALE      = 67 / 37   -- 1.x item.lua:58  SetSize(67, 67)  (NOT the spec's 68)
Borders.GLOW_SCALE_AMMO = 58 / 37   -- CII §2 Ammo exception; Armory has no Ammo slot (dormant)
Borders.GLOW_ALPHA      = 0.77      -- owner profile glowAlpha, account #1 (1.x default 0.5 superseded)
Borders.GLOW_OFFSET_Y_SCALE = 0     -- 1.x item.lua:57  SetPoint('CENTER') — no offset
Borders.GLOW_LAYER      = "OVERLAY" -- 1.x item.lua:54
Borders.GLOW_SUBLEVEL   = -1        -- 1.x item.lua:54 — BELOW the button's other OVERLAY art

-- POOR near-black (spec §3). The reference MUTATES the quality-color table at load so
-- quality 0 is r=g=b=0.1 rather than Blizzard's 0.62 grey, and every lookup reads the
-- mutated value. Under an ADD blend a 0.1 tint is very nearly nothing, which is the
-- point: a worn grey item registers as "bordered but almost dark" rather than as a
-- bright grey halo. Modelled as an OVERRIDE that wins over the live game APIs, because
-- the reference's mutation likewise wins over Blizzard's own value.
local POOR_RGB = { 0.1, 0.1, 0.1 }
Borders.POOR_RGB = POOR_RGB

-- Static quality colors (Blizzard's ITEM_QUALITY_COLORS values; game facts). Reached
-- only when neither C_Item nor _G.ITEM_QUALITY_COLORS is present (the headless harness),
-- so QualityRGB is deterministic under test.
local FALLBACK = {
    [0] = { 0.1,  0.1,  0.1  }, -- Poor — spec §3 near-black override, NOT Blizzard's 0.62 grey
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
    -- Poor is the one quality whose color is NOT the game's: spec §3 replaces it with
    -- near-black, so the override runs BEFORE the live chain.
    if q == 0 then return POOR_RGB[1], POOR_RGB[2], POOR_RGB[3] end
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

-- The halo's side length for a button of `buttonSize`, at 1.x's 67/37 proportion,
-- so the wash bleeds past the icon by the same amount at any button size. Pass `ammo`
-- truthy for the spec's 58px Ammo-slot exception (Armory carries no Ammo entry today;
-- the parameter is wired so adding one can never silently get the wrong halo size).
function Borders.GlowSize(buttonSize, ammo)
    local s = tonumber(buttonSize) or 0
    if s <= 0 then return 0 end
    return s * (ammo and Borders.GLOW_SCALE_AMMO or Borders.GLOW_SCALE)
end

-- The halo's vertical CENTER offset for a button of `buttonSize`. 1.x anchors plain
-- CENTER with no nudge (item.lua:57), so the ratio is 0 and this is 0 at every button
-- size. Kept as a function (rather than folded away) so the geometry stays one shape
-- with Bags 2.0's and a future offset would be a one-constant change.
function Borders.GlowOffsetY(buttonSize)
    local s = tonumber(buttonSize) or 0
    if s <= 0 then return 0 end
    return s * Borders.GLOW_OFFSET_Y_SCALE
end

-- True when a colored glow should be shown for this quality given the toggle and the
-- surface's floor. `minQuality` defaults to the link-path floor (above Common); the
-- equipped paper-doll path passes EQUIPPED_MIN_QUALITY so ANY non-nil quality glows.
-- Signature-compatible with Bags 2.0's Borders.ShouldShow.
function Borders.ShouldShow(quality, enabled, minQuality)
    if not enabled then return false end
    if quality == nil then return false end
    return quality >= (minQuality or BAG_MIN_QUALITY)
end

----------------------------------------------------------------------
-- FRAME layer (in-game)
----------------------------------------------------------------------

local function bordersEnabled()
    return Addon.db and Addon.db.settings and Addon.db.settings.charWindow
        and Addon.db.settings.charWindow.qualityBorders
end

-- Size and re-anchor the halo to the button it belongs to. Both are read off the button
-- rather than hardcoded, so paper-doll slots (37px), flyout leads (32px) and the Ammo
-- exception each get the right wash at the right offset.
local function layoutGlow(f)
    local g = f._glow
    if not g then return end
    local host = f._host
    local w = (host and host.GetWidth and host:GetWidth()) or 0
    local side = Borders.GlowSize(w, f._ammo)
    if side <= 0 then return end
    g:SetSize(side, side)
    g:ClearAllPoints()
    g:SetPoint("CENTER", f, "CENTER", 0, Borders.GlowOffsetY(w))
end

-- A soft additive quality halo washing over a button's icon (1.x anatomy).
-- The container spans the button; the halo is CENTERED in it and deliberately larger
-- than the button (1.x's 67-on-37), so the wash bleeds over the icon edge on all sides.
local function makeGlow(parent, ammo)
    local f = CreateFrame("Frame", nil, parent)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    f:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    -- CELL PARITY with Bags 2.0: the container sits at the button's OWN frame level, not
    -- one above it. 1.x's IconGlow is a texture ON the button (item.lua:54), ordered
    -- against the button's other art by DRAW LAYER alone. A level+1 container ordered the
    -- halo above EVERYTHING — Armory's trinket-cooldown readout (trinkets.lua:100/161,
    -- OVERLAY sublevel 0 on the button), the combat-pending overlay pair (paperdoll.lua
    -- :23/:25, OVERLAY sublevels 6 and 7 on the button), and the neighbouring slots' art.
    -- Same level + OVERLAY(-1) below reproduces 1.x's ordering exactly.
    f:SetFrameLevel(parent:GetFrameLevel() or 1)
    f._host = parent
    f._ammo = ammo and true or nil

    -- 1.x item.lua:54 — OVERLAY at sublevel -1, i.e. BELOW the button's other OVERLAY art.
    local g = f:CreateTexture(nil, Borders.GLOW_LAYER, nil, Borders.GLOW_SUBLEVEL)
    g:SetTexture(Borders.GLOW_TEXTURE)
    g:SetBlendMode("ADD")
    g:SetPoint("CENTER", f, "CENTER", 0, 0)   -- re-anchored with the glow offset by layoutGlow
    f._glow = g
    layoutGlow(f)

    -- The button size is only reliable once it has been laid out, and a scale change
    -- can move it under a pooled button; re-measure on every show.
    f:SetScript("OnShow", function(self) layoutGlow(self) end)
    f:Hide()
    return f
end

-- `minQuality` selects the spec §3 floor for this surface.
local function applyGlow(f, quality, minQuality)
    local r, g, b = Borders.QualityRGB(quality)
    if Borders.ShouldShow(quality, true, minQuality) and r then
        layoutGlow(f)
        f._glow:SetVertexColor(r, g, b, Borders.GLOW_ALPHA)
        f:Show()
    else
        f:Hide()
    end
end

-- ── Equipped paper-doll slots ─────────────────────────────────────────────────
-- Spec §3, the GetInventoryItemQuality path: EVERY quality borders, poor (near-black)
-- and common (white) included. An empty slot returns nil and stays unbordered.
function Addon:UpdateSlotBorders()
    local on = bordersEnabled()
    for slotId, glow in pairs(Addon._slotGlows or {}) do
        if on then
            applyGlow(glow, GetInventoryItemQuality("player", slotId), Borders.EQUIPPED_MIN_QUALITY)
        else
            glow:Hide()
        end
    end
end

-- ── Flyout decorator: glow the lead buttons by item quality ───────────────────
-- Spec §3, the item-link lookup path: above Common only (the default floor).
function Addon:DecorateFlyoutQuality(btn, item)
    if not btn._armQualGlow then
        btn._armQualGlow = makeGlow(btn)
    end
    local q = item and item.link and select(3, GetItemInfo(item.link))
    if bordersEnabled() then
        applyGlow(btn._armQualGlow, q, Borders.BAG_MIN_QUALITY)
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
            -- Spec §2's Ammo exception (58px, not the 67px norm). Armory's SLOTS model does not
            -- currently carry an Ammo entry, so this is dormant — it is wired anyway so
            -- that adding one can never silently get the wrong halo size.
            if btn then Addon._slotGlows[s.id] = makeGlow(btn, s.slotName == "AmmoSlot") end
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
