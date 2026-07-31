--[[
    Daseeki Armory — detached gear-slot popouts (ItemRack-style docked buttons).

    Alt+left-click a slot on the Blizzard character pane (or add one from the
    Item Slot Widgets config) to spawn a standalone button for that slot. It shows
    the worn item, persists across sessions, is draggable when unlocked, and HOVER
    opens an item flyout to change what you're wearing — with the character window
    closed. Popouts magnetically anchor to each other when dragged close (the dock
    side glows). When a swap is queued in combat, a small pending-item icon shows in
    the slot's upper-right.

    Per-popout flyout config + anchor live in settings.slotPopouts.buttons[slotId].
--]]

local _, Addon = ...

local SIDES = { "top", "bottom", "left", "right" }
local SNAP2 = 42 * 42  -- snap distance (squared) for magnetic anchoring

local function slotName(slotId)
    for _, s in ipairs(Addon.SLOTS) do if s.id == slotId then return s.name end end
    return "Slot"
end
local function slotEmptyTex(slotId)
    for _, s in ipairs(Addon.SLOTS) do if s.id == slotId then return Addon:GetSlotEmptyTexture(s) end end
    return Addon.EMPTY_ICON
end

function Addon:PopoutFlyoutConfig(slotId)
    local b = Addon.db.settings.slotPopouts.buttons[slotId]
    return { dir = (b and b.dir) or "right", perRow = (b and b.perRow) or 5 }
end

-- Suite border color: mirrors Daseeki-Bags' inventory border (Core.ApplySkin uses
-- the same), falling back to the Core grey when Bags isn't present.
function Addon:SuiteBorderColor()
    local DBags = _G["Daseeki-Bags"]
    local prof  = DBags and DBags.player and DBags.player.profile and DBags.player.profile["inventory"]
    return (prof and prof.borderColor) or { 0.3, 0.3, 0.3, 1 }
end

local function entryFor(slotId) return Addon.db.settings.slotPopouts.buttons[slotId] end

local function savePos(self)
    local p, _, rp, x, y = self:GetPoint()
    local e = entryFor(self._slotId) or {}
    e.point, e.relPoint, e.x, e.y = p, rp, x, y      -- preserve dir/perRow/anchor
    Addon.db.settings.slotPopouts.buttons[self._slotId] = e
end

local function hideGlows(f)
    if f.glows then for _, g in pairs(f.glows) do g:Hide() end end
end

-- Detach a popout's real frame point to an absolute position so it carries no
-- live dependency on any other popout (kept in sync with a nil'd anchor entry).
local function floatFree(b)
    local cx, cy = b:GetCenter()
    local ucx, ucy = UIParent:GetCenter()
    b:ClearAllPoints()
    b:SetPoint("CENTER", UIParent, "CENTER", (cx or ucx) - ucx, (cy or ucy) - ucy)
end

-- ── Anchoring ─────────────────────────────────────────────────────────────────
-- True if following `fromId`'s anchor chain reaches `goalId` (i.e. anchoring
-- goalId → fromId would form a cycle).
local function anchorChainReaches(fromId, goalId)
    local seen = {}
    local cur = fromId
    while cur do
        if cur == goalId then return true end
        if seen[cur] then return false end
        seen[cur] = true
        local e = Addon.db.settings.slotPopouts.buttons[cur]
        cur = e and e.anchor and e.anchor.to
    end
    return false
end
function Addon:AnchorWouldCycle(slotId, targetId)
    return targetId == slotId or anchorChainReaches(targetId, slotId)
end

function Addon:ApplyPopoutAnchor(slotId)
    local e = entryFor(slotId)
    local b = Addon._popoutFrames and Addon._popoutFrames[slotId]
    if not (e and e.anchor and b) then return false end
    local target = Addon._popoutFrames and Addon._popoutFrames[e.anchor.to]
    if not (target and target:IsShown()) then return false end
    -- never anchor to a popout that (transitively) anchors back to us. Detach the
    -- real frame too (not just the saved entry) so a later same-pass cycle check
    -- on another slot can't read stale "no anchor" data while this frame's actual
    -- point still depends on someone — that mismatch is what causes a true
    -- circular SetPoint crash.
    if Addon:AnchorWouldCycle(slotId, e.anchor.to) then e.anchor = nil; floatFree(b); return false end
    b:ClearAllPoints()
    local s = e.anchor.side
    if     s == "right"  then b:SetPoint("LEFT",   target, "RIGHT",  2, 0)
    elseif s == "left"   then b:SetPoint("RIGHT",  target, "LEFT",  -2, 0)
    elseif s == "top"    then b:SetPoint("BOTTOM", target, "TOP",    0, 2)
    elseif s == "bottom" then b:SetPoint("TOP",    target, "BOTTOM", 0, -2) end
    return true
end

function Addon:ReleasePopoutAnchor(slotId)
    local e = entryFor(slotId)
    if not e then return end
    e.anchor = nil
    local b = Addon._popoutFrames and Addon._popoutFrames[slotId]
    if b then
        floatFree(b)
        savePos(b)
    end
    if Addon.RefreshWidgetsTab then Addon:RefreshWidgetsTab() end
end

local function dragUpdate(b)
    local bx, by = b:GetCenter()
    if not bx then return end
    for _, f in pairs(Addon._popoutFrames or {}) do hideGlows(f) end
    b._anchorCandidate = nil
    local best, bestSide, bestTarget, bestDist
    for sid, f in pairs(Addon._popoutFrames or {}) do
        if f ~= b and f:IsShown() and not Addon:AnchorWouldCycle(b._slotId, sid) then
            local fx, fy = f:GetCenter()
            local fw, fh = f:GetSize()
            if fx then
                local cand = {
                    right  = { fx + fw, fy }, left = { fx - fw, fy },
                    top    = { fx, fy + fh }, bottom = { fx, fy - fh },
                }
                for side, p in pairs(cand) do
                    local d = (bx - p[1]) ^ 2 + (by - p[2]) ^ 2
                    if d < SNAP2 and (not bestDist or d < bestDist) then
                        bestDist, best, bestSide, bestTarget = d, f, side, sid
                    end
                end
            end
        end
    end
    if best then
        best.glows[bestSide]:Show()
        b._anchorCandidate = { to = bestTarget, side = bestSide }
    end
end

-- ── Create / update ───────────────────────────────────────────────────────────
function Addon:CreateSlotPopout(slotId)
    Addon._popoutFrames = Addon._popoutFrames or {}
    local b = Addon._popoutFrames[slotId]
    if b then return b end

    b = CreateFrame("Button", "DaseekiArmoryPopout" .. slotId, UIParent)
    b:SetSize(38, 38)
    b:SetFrameStrata("MEDIUM")
    b:SetMovable(true); b:SetClampedToScreen(true)
    b:SetScale(Addon.db.settings.slotPopouts.scale or 1)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b._slotId = slotId

    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); b.bg:SetColorTexture(Addon:Col("inset", 0.5))
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2); b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    -- border in the Daseeki suite style (matches Daseeki-Bags / Core.ApplySkin)
    b.border = CreateFrame("Frame", nil, b, "BackdropTemplate")
    b.border:SetPoint("TOPLEFT", -3, 3); b.border:SetPoint("BOTTOMRIGHT", 3, -3)
    b.border:SetBackdrop({
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    local bc = Addon:SuiteBorderColor()
    b.border:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(Addon:Col("brand", 0.2))

    -- pending (queued-in-combat) item overlay, upper-right
    b.pendBg = b:CreateTexture(nil, "OVERLAY"); b.pendBg:SetSize(17, 17); b.pendBg:SetPoint("TOPRIGHT", 2, 2)
    b.pendBg:SetColorTexture(Addon:Col("inset", 0.9)); b.pendBg:Hide()
    b.pending = b:CreateTexture(nil, "OVERLAY"); b.pending:SetSize(15, 15); b.pending:SetPoint("TOPRIGHT", 1, 1)
    b.pending:SetTexCoord(0.07, 0.93, 0.07, 0.93); b.pending:Hide()

    -- magnetic dock-side glows
    b.glows = {}
    for _, side in ipairs(SIDES) do
        local g = b:CreateTexture(nil, "OVERLAY"); g:SetColorTexture(Addon:Col("brand", 0.85)); g:Hide()
        b.glows[side] = g
    end
    b.glows.left:SetPoint("TOPRIGHT", b, "TOPLEFT", 0, 1);  b.glows.left:SetPoint("BOTTOMRIGHT", b, "BOTTOMLEFT", 0, -1);  b.glows.left:SetWidth(4)
    b.glows.right:SetPoint("TOPLEFT", b, "TOPRIGHT", 0, 1); b.glows.right:SetPoint("BOTTOMLEFT", b, "BOTTOMRIGHT", 0, -1); b.glows.right:SetWidth(4)
    b.glows.top:SetPoint("BOTTOMLEFT", b, "TOPLEFT", -1, 0);    b.glows.top:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT", 1, 0);     b.glows.top:SetHeight(4)
    b.glows.bottom:SetPoint("TOPLEFT", b, "BOTTOMLEFT", -1, 0); b.glows.bottom:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", 1, 0); b.glows.bottom:SetHeight(4)

    b:SetScript("OnDragStart", function(self)
        if Addon.db.settings.slotPopouts.locked then return end
        Addon:HideItemFlyout()
        self:StartMoving(); self._moving = true
    end)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing(); self._moving = false
        for _, f in pairs(Addon._popoutFrames or {}) do hideGlows(f) end
        local e = entryFor(slotId) or {}
        local cand = self._anchorCandidate
        if cand and not Addon:AnchorWouldCycle(slotId, cand.to) then
            e.anchor = { to = cand.to, side = cand.side }
            Addon.db.settings.slotPopouts.buttons[slotId] = e
            Addon:ApplyPopoutAnchor(slotId)
        else
            e.anchor = nil
            Addon.db.settings.slotPopouts.buttons[slotId] = e
            savePos(self)
        end
        self._anchorCandidate = nil
        if Addon.RefreshWidgetsTab then Addon:RefreshWidgetsTab() end
    end)
    b:SetScript("OnUpdate", function(self) if self._moving then dragUpdate(self) end end)

    -- HOVER opens the flyout (per request). No click action: alt+click the
    -- character-pane slot toggles the popout; remove it from the config tab.
    b:SetScript("OnEnter", function(self)
        if self._moving then return end
        local uneq
        if GetInventoryItemLink("player", slotId) then
            uneq = { fn = function() Addon:UnequipSlot(slotId) end, label = "Unequip current item" }
        end
        Addon:ShowItemFlyout(self, slotId, function(item)
            if item.equipped then Addon:SwapEquippedSlots(item.invSlot, slotId)
            else Addon:EquipContainerItemToSlot(item.bag, item.slot, slotId) end
        end, uneq, Addon:PopoutFlyoutConfig(slotId))
    end)
    b:SetScript("OnLeave", function() end)

    Addon._popoutFrames[slotId] = b
    return b
end

function Addon:UpdateSlotPopout(slotId)
    local b = Addon._popoutFrames and Addon._popoutFrames[slotId]
    if not b then return end
    local tex = GetInventoryItemTexture("player", slotId)
    if tex then
        b.icon:SetTexture(tex); b.icon:SetDesaturated(false); b.icon:SetAlpha(1)
    else
        b.icon:SetTexture(slotEmptyTex(slotId)); b.icon:SetDesaturated(true); b.icon:SetAlpha(0.7)
    end
    local pend = Addon._pendingSlots and Addon._pendingSlots[slotId]
    if pend then b.pending:SetTexture(pend); b.pending:Show(); b.pendBg:Show()
    else b.pending:Hide(); b.pendBg:Hide() end
end

function Addon:UpdateAllSlotPopouts()
    for slotId, b in pairs(Addon._popoutFrames or {}) do
        if b:IsShown() then Addon:UpdateSlotPopout(slotId) end
    end
end

function Addon:ShowSlotPopout(slotId)
    local b = Addon:CreateSlotPopout(slotId)
    local saved = entryFor(slotId)
    b:ClearAllPoints()
    if not (saved and saved.anchor and Addon:ApplyPopoutAnchor(slotId)) then
        if saved and saved.point then
            b:SetPoint(saved.point, UIParent, saved.relPoint or "CENTER", saved.x or 0, saved.y or 0)
        else
            local n = 0
            for _, f in pairs(Addon._popoutFrames) do if f:IsShown() then n = n + 1 end end
            b:SetPoint("TOPLEFT", UIParent, "CENTER", -220 + n * 44, 140)
            savePos(b)
        end
    end
    b:Show()
    Addon:UpdateSlotPopout(slotId)
    if Addon.RefreshWidgetsTab then Addon:RefreshWidgetsTab() end
end

function Addon:RemoveSlotPopout(slotId)
    local b = Addon._popoutFrames and Addon._popoutFrames[slotId]
    if b then b:Hide() end
    -- release any popouts anchored TO this one
    for sid, e in pairs(Addon.db.settings.slotPopouts.buttons) do
        if type(e) == "table" and e.anchor and e.anchor.to == slotId then
            Addon:ReleasePopoutAnchor(sid)
        end
    end
    Addon.db.settings.slotPopouts.buttons[slotId] = nil
    if Addon.RefreshWidgetsTab then Addon:RefreshWidgetsTab() end
end

function Addon:ToggleSlotPopout(slotId)
    local b = Addon._popoutFrames and Addon._popoutFrames[slotId]
    if b and b:IsShown() then Addon:RemoveSlotPopout(slotId)
    else Addon:ShowSlotPopout(slotId) end
end

-- Global popout scale (applies to every popout button).
function Addon:SetPopoutScale(v)
    v = tonumber(v) or 1
    Addon.db.settings.slotPopouts.scale = v
    for _, b in pairs(Addon._popoutFrames or {}) do b:SetScale(v) end
end

-- Recolor every popout border to the current suite border color.
function Addon:RefreshPopoutBorders()
    local bc = Addon:SuiteBorderColor()
    for _, b in pairs(Addon._popoutFrames or {}) do
        if b.border then b.border:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4] or 1) end
    end
end

-- Watch the Daseeki-Bags border color and recolor popouts live when it changes.
function Addon:StartBorderWatch()
    if Addon._borderTicker then return end
    local last
    Addon._borderTicker = C_Timer.NewTicker(1, function()
        local bc = Addon:SuiteBorderColor()
        local key = (bc[1] or 0) .. "," .. (bc[2] or 0) .. "," .. (bc[3] or 0) .. "," .. (bc[4] or 1)
        if key ~= last then last = key; Addon:RefreshPopoutBorders() end
    end)
end

-- ── Combat pending overlays ───────────────────────────────────────────────────
function Addon:SetPendingSlot(slotId, tex)
    Addon._pendingSlots = Addon._pendingSlots or {}
    Addon._pendingSlots[slotId] = tex
    Addon:UpdateAllSlotPopouts()
    if Addon.UpdatePaperdollPending then Addon:UpdatePaperdollPending() end
end

function Addon:ClearPendingSlots()
    Addon._pendingSlots = {}
    Addon:UpdateAllSlotPopouts()
    if Addon.UpdatePaperdollPending then Addon:UpdatePaperdollPending() end
end

-- `skip` (optional) is the set of slots that are NOT waiting for combat to end —
-- the weapon slots a secure /equipslot macro is swapping right now (equip.lua
-- §"Secure in-combat weapon swaps"). They get no pending overlay.
function Addon:MarkSetPending(name, skip)
    local set = Addon.db.sets[name]
    if not set then return end
    Addon._pendingSlots = Addon._pendingSlots or {}
    for _, slotId in ipairs(Addon.SLOT_IDS) do
        if not (skip and skip[slotId])
           and Addon:IsSlotActive(set, slotId)
           and not Addon:SlotMatches(slotId, set.equip[slotId]) then
            local entry = set.equip[slotId]
            Addon._pendingSlots[slotId] = (Addon:IsEmptyEntry(entry) and Addon.UNEQUIP_ICON)
                or Addon:EntryTexture(entry) or "Interface\\Icons\\INV_Misc_QuestionMark"
        end
    end
    Addon:UpdateAllSlotPopouts()
    if Addon.UpdatePaperdollPending then Addon:UpdatePaperdollPending() end
end

-- ── Init ──────────────────────────────────────────────────────────────────────
function Addon:InitSlotPopouts()
    for slotId in pairs(Addon.db.settings.slotPopouts.buttons) do
        if type(slotId) == "number" then Addon:ShowSlotPopout(slotId) end
    end
    -- second pass: apply anchors now that every popout frame exists
    for slotId in pairs(Addon.db.settings.slotPopouts.buttons) do
        if type(slotId) == "number" then Addon:ApplyPopoutAnchor(slotId) end
    end
    if not Addon._popoutEv then
        Addon._popoutEv = CreateFrame("Frame")
        Addon._popoutEv:RegisterEvent("UNIT_INVENTORY_CHANGED")
        Addon._popoutEv:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        Addon._popoutEv:SetScript("OnEvent", function(_, _, unit)
            if unit == nil or unit == "player" then Addon:UpdateAllSlotPopouts() end
        end)
    end
    Addon:StartBorderWatch()
end
