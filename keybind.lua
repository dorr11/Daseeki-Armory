--[[
    Daseeki Armory — per-set keybinds, and the secure in-combat weapon swap.

    Each set may have a `set.key` (e.g. "CTRL-1"). At login (and whenever a key
    changes) we bind it via SetOverrideBindingClick to a hidden secure button whose
    macrotext equips the set. A small modal captures the key press.

    IN-COMBAT WEAPON SWAPS (ITEMRACK_BEHAVIOR_SPEC.md §2.8 / §6.1). The macrotext
    is built by Addon:BuildSetMacroText: one `/equipslot [combat]<slot> <item>`
    line per governed weapon slot (16/17/18), then the ordinary equip call. The
    client executes those lines itself in response to a real key press, which is
    the only way gear changes during combat — so pressing a set's key mid-fight
    swaps main hand / off hand / ranged immediately and queues the rest.

    The text is a secure attribute, so it can only be written OUT of combat. It is
    therefore rewritten whenever a set's items change (QueueMacroRefresh, called
    from sets.lua) and again on leaving combat, so it always names the items the
    set currently wants.
--]]

local _, Addon = ...

-- Attributes on a secure button cannot be written during combat; rewrite as soon
-- as it ends. One shared frame, registered only while a rewrite is owed.
local function whenOutOfCombat(key, fn)
    Addon._bindDeferred = Addon._bindDeferred or {}
    if not Addon._bindRegen then
        Addon._bindRegen = CreateFrame("Frame")
        Addon._bindRegen:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            local owed = Addon._bindDeferred or {}
            Addon._bindDeferred = {}
            for _, f in pairs(owed) do f() end
        end)
    end
    Addon._bindDeferred[key] = fn
    Addon._bindRegen:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- ── ARM-3: the unresolved-name counter (SUITE_DATA_HONESTY_AUDIT, Class 4/5) ──
-- `WeaponMacroLines` omits a slot's `/equipslot [combat]<slot> <name>` line when
-- GetItemInfo has not cached the item's name. The only repair used to be a single
-- 10-second timer behind a session latch: a set whose main hand sits in the bank is
-- nil at t=0 and still nil at t=10, the latch burns, and the player presses the
-- keybind mid-pull an hour later to nothing at all — silently, because the secure
-- path fails without an error in lockdown.
--
-- The repair is now the discipline goalPicker.lua's `_goalPvPMissing` already uses
-- in this repo: count what could not be resolved, and while that count is > 0 watch
-- GET_ITEM_INFO_RECEIVED and rewrite on every hit. At 0 the watcher unregisters, so
-- a fully-warm client pays nothing.
Addon._macroMissing = 0

-- ── THE REWRITE LATCH (CLIENT_ASYNC_LESSONS.md Class 9, 2026-08-10) ──────────
-- The counter above is published AFTER the rewrite loop, and the rewrite loop is
-- what makes the client calls: BuildSetMacroText -> WeaponMacroLines ->
-- C_Item.RequestLoadItemDataByID. A client that answers a load request from
-- inside the request — and it does, for anything it already holds — runs every
-- GET_ITEM_INFO_RECEIVED handler in the session, this one included, while
-- `_macroMissing` still describes the PREVIOUS rewrite. That is the arm-too-late
-- shape Class 9 names, in the same file whose ARM-3 note explains why a silently
-- missing `/equipslot` line is the worst possible failure: the secure path fails
-- without an error in lockdown, so the player presses the key mid-pull and
-- nothing happens.
--
-- Armed before the first client call of the rewrite, released when it returns,
-- pcall-protected. While it is up an arriving answer is OUR OWN ECHO: it is
-- recorded, not acted on, and the rewrite schedules exactly ONE follow-up on the
-- way out — which is also the re-entry fuse, because a rewrite can no longer
-- start a rewrite from inside itself however the client dispatches.
local rewriting = false

-- THE DEPTH FUSE. The follow-up below asks for another rewrite, and on a client
-- with nothing to defer with that rewrite runs INLINE — so a set whose echo never
-- stops arriving would chain follow-ups without bound. Two is past anything
-- legitimate (a rewrite, and the one repair its own echo earns); beyond that the
-- composition is one nobody foresaw and it degrades to a counted refusal rather
-- than to an overflow.
local followups = 0
local MAX_REWRITE_FOLLOWUPS = 2

-- Published so a peer module's handler can tell OUR echo from a real one.
function Addon:InMacroRewrite() return rewriting end

-- Run a macro rewrite with the latch up. A rewrite asked for from inside one is
-- never run inside it: it is recorded and folded into ONE bounded follow-up.
local function withRewriteLatch(fn)
    if rewriting then
        Addon._macroRewriteReentries = (Addon._macroRewriteReentries or 0) + 1
        Addon._macroRewriteEcho = true
        return
    end
    rewriting = true
    Addon._macroRewriteEcho = nil
    local ok, err = pcall(fn)
    rewriting = false

    local echo = Addon._macroRewriteEcho
    Addon._macroRewriteEcho = nil
    if echo then
        -- The client answered inside our own rewrite. Act on it now, with the
        -- counter published and the warm watch armed — once, and under the fuse.
        if followups < MAX_REWRITE_FOLLOWUPS then
            followups = followups + 1
            local fok, ferr = pcall(function() Addon:QueueMacroRefresh() end)
            followups = followups - 1
            if not fok and ok then error(ferr, 0) end
        else
            Addon._macroRewriteRefusals = (Addon._macroRewriteRefusals or 0) + 1
        end
    end
    if not ok then error(err, 0) end
end

function Addon:UpdateMacroWarmWatch()
    local want = (Addon._macroMissing or 0) > 0
    if want then
        if not Addon._macroWarmFrame then
            local f = CreateFrame("Frame")
            f:SetScript("OnEvent", function()
                -- Class 9: this is our own rewrite's echo, arriving before its
                -- counter is published. Record it; the rewrite acts on it once.
                if Addon:InMacroRewrite() then Addon._macroRewriteEcho = true; return end
                if (Addon._macroMissing or 0) > 0 then Addon:QueueMacroRefresh() end
            end)
            Addon._macroWarmFrame = f
        end
        if not Addon._macroWatching then
            -- RegisterEvent raises on an event a build does not know, and the TOC
            -- spans three interface versions, so each one is guarded.
            pcall(Addon._macroWarmFrame.RegisterEvent, Addon._macroWarmFrame, "GET_ITEM_INFO_RECEIVED")
            pcall(Addon._macroWarmFrame.RegisterEvent, Addon._macroWarmFrame, "ITEM_DATA_LOAD_RESULT")
            Addon._macroWatching = true
        end
    elseif Addon._macroWatching then
        Addon._macroWarmFrame:UnregisterAllEvents()
        Addon._macroWatching = false
    end
end

-- Rewrite the macro body of every existing set button (no re-binding). Cheap, so
-- it is safe to call after any set edit.
function Addon:RefreshSetMacros()
    if InCombatLockdown() then
        whenOutOfCombat("macros", function() Addon:RefreshSetMacros() end)
        return
    end
    withRewriteLatch(function()
        local missing = 0
        for _, btn in ipairs(Addon._bindButtons or {}) do
            if btn._setName and Addon.db.sets[btn._setName] then
                local text, miss = Addon:BuildSetMacroText(btn._setName)
                btn:SetAttribute("macrotext", text)
                missing = missing + (miss or 0)
            end
        end
        Addon._macroMissing = missing
        Addon:UpdateMacroWarmWatch()
    end)
end

-- Coalesce a burst of set edits into one rewrite on the next frame.
--
-- Class 9: the no-C_Timer fallback rewrites INLINE, so without the rewrite latch
-- a handler that fires from inside a rewrite's own client call would land back
-- here and start another one, without bound. The latch refuses that and folds it
-- into the single follow-up, so the fallback is as safe as the deferred path.
function Addon:QueueMacroRefresh()
    if Addon._macroRefreshQueued then return end
    if Addon:InMacroRewrite() then
        Addon._macroRewriteReentries = (Addon._macroRewriteReentries or 0) + 1
        Addon._macroRewriteEcho = true
        return
    end
    if not (C_Timer and C_Timer.After) then Addon:RefreshSetMacros(); return end
    Addon._macroRefreshQueued = true
    C_Timer.After(0, function()
        Addon._macroRefreshQueued = nil
        Addon:RefreshSetMacros()
    end)
end

-- (Re)apply override bindings for every set that has a key. Deferred out of combat.
function Addon:ApplySetBindings()
    if InCombatLockdown() then
        whenOutOfCombat("bindings", function() Addon:ApplySetBindings() end)
        return
    end
    local owner = Addon._bindOwner
    if not owner then owner = CreateFrame("Frame", "DaseekiArmoryBindOwner"); Addon._bindOwner = owner end
    ClearOverrideBindings(owner)
    Addon._bindButtons = Addon._bindButtons or {}
    local i, missing = 0, 0
    withRewriteLatch(function()
    for name, set in pairs(Addon.db.sets) do
        if type(set.key) == "string" and set.key ~= "" then
            i = i + 1
            local btn = Addon._bindButtons[i]
            if not btn then
                btn = CreateFrame("Button", "DaseekiArmoryBindBtn" .. i, UIParent, "SecureActionButtonTemplate")
                btn:RegisterForClicks("AnyDown")
                Addon._bindButtons[i] = btn
            end
            btn._setName = name
            btn:SetAttribute("type", "macro")
            local text, miss = Addon:BuildSetMacroText(name)
            btn:SetAttribute("macrotext", text)
            missing = missing + (miss or 0)
            SetOverrideBindingClick(owner, true, set.key, btn:GetName())
        end
    end
    -- Buttons past the last bound set keep stale text otherwise.
    for j = i + 1, #Addon._bindButtons do Addon._bindButtons[j]._setName = nil end

    -- ARM-3: item names are not always cached at login. The COUNTER above is the
    -- repair — while it is > 0 every GET_ITEM_INFO_RECEIVED rewrites the bodies, for
    -- as long as it takes, including an item retrieved from the bank an hour later.
    Addon._macroMissing = missing
    Addon:UpdateMacroWarmWatch()
    end)

    -- The 10-second re-resolve survives as a BACKSTOP ONLY, for a client that
    -- resolves a name without ever firing the event. It is no longer the repair, so
    -- its one-shot latch can no longer strand anything.
    if not Addon._macroWarmed and C_Timer and C_Timer.After then
        Addon._macroWarmed = true
        C_Timer.After(10, function() Addon:RefreshSetMacros() end)
    end
end

-- Assign or clear a set's key (a key is unique across sets).
function Addon:SetSetKeybind(name, key)
    local set = Addon.db.sets[name]
    if not set then return end
    if key and key ~= "" then
        for n, s in pairs(Addon.db.sets) do
            if n ~= name and s.key == key then s.key = nil end
        end
        set.key = key
    else
        set.key = nil
    end
    Addon:ApplySetBindings()
    if Addon.RefreshOptions then Addon:RefreshOptions() end
end

-- Modal that captures the next key combo and calls onCapture("CTRL-1").
local IGNORE = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, UNKNOWN = true,
}
function Addon:CaptureKeybind(onCapture)
    local f = Addon._kbCapture
    if not f then
        f = CreateFrame("Frame", "DaseekiArmoryKBCapture", UIParent, "BackdropTemplate")
        f:SetSize(320, 96); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetPoint("CENTER")
        f:EnableKeyboard(true); f:EnableMouse(true)
        f:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(Addon:Col("panel", 0.95)); f:SetBackdropBorderColor(Addon:Col("border"))
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOP", 0, -18); f.title:SetText("Press a key…")
        if not Addon:TrySetCeremonial(f.title, 16) then f.title:SetTextColor(1, 0.82, 0) end
        f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        Addon:TrySetFont(f.hint, "small")
        f.hint:SetPoint("BOTTOM", 0, 18); f.hint:SetText("Esc to cancel")
        f:SetScript("OnKeyDown", function(self, key)
            self:SetPropagateKeyboardInput(false)
            if key == "ESCAPE" then self:Hide(); return end
            if IGNORE[key] then return end
            local combo = ""
            if IsControlKeyDown() then combo = combo .. "CTRL-" end
            if IsShiftKeyDown()   then combo = combo .. "SHIFT-" end
            if IsAltKeyDown()     then combo = combo .. "ALT-" end
            combo = combo .. key
            self:Hide()
            if self._onCapture then self._onCapture(combo) end
        end)
        Addon._kbCapture = f
    end
    f._onCapture = onCapture
    f:Show()
end
