--[[
    Daseeki Armory — trinket cooldown readouts (TrinketMenu-parity essentials).

    Behavioral reference: TRINKETMENU_BEHAVIOR_SPEC.md §4 (cooldown display
    semantics). Three surfaces carry the readout, all trinket-only:

      * the two equipped trinket slots on the character pane,
      * the detached slot popouts for slots 13 / 14 — the spec's "two-slot bar",
      * trinket entries in the shared item flyout, so you can pick one that is
        actually off cooldown.

    The SWAP itself is entirely Armory's existing plumbing: hovering a trinket slot
    opens Addon:ShowItemFlyout and clicking equips through the secure equip/queue
    path. This module only adds cooldown affordances — no duplicate equip logic.

    Numbers (spec §4.2). Remaining time is `duration - (GetTime() - start)` and the
    text is chosen by threshold: under a minute reads in seconds, under an hour in
    minutes, above that in hours. The sub-3-second rule is deliberately
    order-dependent — it only suppresses a countdown that would START below three
    seconds (that is almost always the global cooldown, and drawing it is noise);
    a countdown already ticking keeps rendering as it passes 3, 2, 1.

    Auto-queue-on-cooldown (spec §3) is intentionally out of scope. Fresh code —
    no lines derived from TrinketMenu.
--]]

local _, Addon = ...

local TRINKET_SLOTS = { 13, 14 }   -- Trinket0 (upper) / Trinket1 (lower)
local TICK          = 1            -- spec §4.5: numbers refresh on a 1 s timer
local GCD_GUARD     = 1.5          -- don't draw a swirl for a global cooldown

local GetContainerItemCooldown =
    (C_Container and C_Container.GetContainerItemCooldown) or _G.GetContainerItemCooldown

local function isTrinketSlot(slotId) return slotId == 13 or slotId == 14 end

local function settings()
    return (Addon.db and Addon.db.settings and Addon.db.settings.trinkets) or nil
end
local function cdEnabled()
    local s = settings()
    return (s ~= nil and s.showCooldowns) and true or false
end
local function largeNumbers()
    local s = settings()
    if not s then return true end
    return s.largeNumbers ~= false
end

-- ── The readout formatter (spec §4.2) ─────────────────────────────────────────
-- Pure: no WoW API, no addon state. `now` and `prevText` are passed in so the
-- self-test harness can drive every threshold directly.
--   start/duration : as returned by the cooldown APIs (start 0 = not on cooldown)
--   now            : GetTime()
--   prevText       : what the font string currently reads, for the sub-3s rule
-- Returns the string to display ("" for blank).
function Addon:CooldownText(start, duration, now, prevText)
    if not start or start == 0 or not duration or duration <= 0 then return "" end
    local remain = duration - ((now or 0) - start)
    if remain <= 0 then return "" end
    -- Global-cooldown suppression: only refuse to START a countdown under 3 s.
    if remain < 3 and (prevText == nil or prevText == "") then return "" end
    if remain < 60   then return string.format("%d s", math.floor(remain + 0.5)) end
    if remain < 3600 then return string.format("%d m", math.ceil(remain / 60))   end
    return string.format("%d h", math.ceil(remain / 3600))
end

-- ── Font styling (spec §4.3) ──────────────────────────────────────────────────
-- Large: 16 pt outlined, brand gold, centered on the button.
-- Small: 14 pt outlined, plain text colour, anchored to the bottom edge.
-- Colours come from the DaseekiUI tokens (BRAND_SPEC) rather than literals; the
-- fallback palette in core.lua reproduces the spec's exact gold and white.
local function styleCdText(fs, host)
    if not (fs and host) then return end
    Addon:TrySetNumeral(fs)                     -- telemetry numeral face when Core is present
    local path = fs:GetFont()
    local big  = largeNumbers()
    if path then fs:SetFont(path, big and 16 or 14, "OUTLINE") end
    fs:SetTextColor(Addon:Col(big and "brand" or "text"))
    fs:ClearAllPoints()
    if big then fs:SetPoint("CENTER", host, "CENTER", 0, 0)
    else        fs:SetPoint("BOTTOM", host, "BOTTOM", 0, 2) end
end

-- ── Cooldown widget attached to one button ────────────────────────────────────
-- `noCooldownCount` is the flag OmniCC-style addons honour. Our own font string
-- is the readout (spec §4.2), so third-party countdown text on the same frame
-- would double up: while our text is on, other addons are asked to stay off this
-- frame; when it is off the whole cooldown frame is hidden, so there is nothing
-- for them to annotate either way.
local function attach(host)
    if host._armTrinketCd then return host._armTrinketCd end
    local cd = CreateFrame("Cooldown", nil, host, "CooldownFrameTemplate")
    cd:SetAllPoints(host)
    cd:SetDrawEdge(false)
    cd:SetHideCountdownNumbers(true)            -- suppress Blizzard's built-in numbers
    cd.noCooldownCount = true
    if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.8) end   -- spec §4.1
    local txt = host:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    styleCdText(txt, host)
    host._armTrinketCd = { cd = cd, txt = txt, host = host }
    return host._armTrinketCd
end

-- Draw one attached readout from a (start, duration) pair.
local function render(t, start, duration, show)
    if not t then return end
    if show and start and start > 0 and duration and duration > GCD_GUARD then
        t.cd:SetCooldown(start, duration)
        t.cd:Show()
    else
        t.cd:SetCooldown(0, 0)
        t.cd:Hide()
    end
    if not show then t.txt:SetText(""); return end
    t.txt:SetText(Addon:CooldownText(start, duration, GetTime(), t.txt:GetText()))
end

-- ── Equipped-slot + popout cooldown display ───────────────────────────────────
-- Popout buttons are created on demand (alt+click a character slot), so the two
-- trinket popouts are picked up lazily here rather than wired at init.
local function popoutFor(slotId)
    local frames = Addon._popoutFrames
    return frames and frames[slotId] or nil
end

function Addon:UpdateTrinketCooldowns()
    local show = cdEnabled()
    for _, slotId in ipairs(TRINKET_SLOTS) do
        local start, duration
        if show then start, duration = GetInventoryItemCooldown("player", slotId) end
        render(Addon._trinketCds and Addon._trinketCds[slotId], start, duration, show)

        local pop = popoutFor(slotId)
        if pop then render(attach(pop), start, duration, show) end
    end
end

-- Re-apply the font/anchor after the large-numbers option changes.
function Addon:RestyleTrinketCooldowns()
    for _, t in pairs(Addon._trinketCds or {}) do styleCdText(t.txt, t.host) end
    for _, slotId in ipairs(TRINKET_SLOTS) do
        local pop = popoutFor(slotId)
        if pop and pop._armTrinketCd then
            styleCdText(pop._armTrinketCd.txt, pop._armTrinketCd.host)
        end
    end
    Addon:UpdateTrinketCooldowns()
end

-- ── Flyout decorator: cooldown text on trinket entries ────────────────────────
-- Called for every shown flyout button (item may be nil for the unequip cell).
-- Only trinket-slot flyouts get a countdown; other slots have theirs cleared.
function Addon:DecorateTrinketFlyout(btn, item, slotId)
    if not isTrinketSlot(slotId) or not cdEnabled() or not item or not item.link then
        if btn._armTrinketCdText then btn._armTrinketCdText:SetText("") end
        return
    end
    if not btn._armTrinketCdText then
        local t = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        Addon:TrySetNumeral(t)   -- telemetry countdown → numeral face (BRAND_SPEC §3)
        t:SetPoint("BOTTOM", btn, "BOTTOM", 0, 1)
        btn._armTrinketCdText = t
    end
    local start, duration
    if item.equipped and item.invSlot then
        start, duration = GetInventoryItemCooldown("player", item.invSlot)
    elseif item.bag and item.slot and GetContainerItemCooldown then
        start, duration = GetContainerItemCooldown(item.bag, item.slot)
    end
    btn._armTrinketCdText:SetText(
        Addon:CooldownText(start, duration, GetTime(), btn._armTrinketCdText:GetText()))
end

-- ── Init ──────────────────────────────────────────────────────────────────────
local function anyTrinketPopoutShown()
    for _, slotId in ipairs(TRINKET_SLOTS) do
        local p = popoutFor(slotId)
        if p and p:IsShown() then return true end
    end
    return false
end

function Addon:InitTrinkets()
    if Addon._trinketsInit then return end
    Addon._trinketsInit = true

    -- cooldown spiral + numeric readout over each equipped trinket slot button
    Addon._trinketCds = {}
    for _, slotId in ipairs(TRINKET_SLOTS) do
        local btnName = (slotId == 13) and "CharacterTrinket0Slot" or "CharacterTrinket1Slot"
        local btn = _G[btnName]
        if btn then Addon._trinketCds[slotId] = attach(btn) end
    end

    -- cooldown text inside the trinket flyout (shared decorator registry)
    if Addon.AddFlyoutDecorator then
        Addon:AddFlyoutDecorator(function(btn, item, slotId)
            Addon:DecorateTrinketFlyout(btn, item, slotId)
        end)
    end

    -- refresh on cooldown/equip events, plus the 1-second numbers tick while a
    -- readout is actually on screen (character pane open, or a trinket popout out)
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("BAG_UPDATE_COOLDOWN")
    ev:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    ev:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
    ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function() Addon:UpdateTrinketCooldowns() end)
    Addon._trinketEv = ev

    Addon._trinketTicker = C_Timer.NewTicker(TICK, function()
        if (_G.CharacterFrame and _G.CharacterFrame:IsShown()) or anyTrinketPopoutShown() then
            Addon:UpdateTrinketCooldowns()
        end
    end)

    Addon:UpdateTrinketCooldowns()
end
