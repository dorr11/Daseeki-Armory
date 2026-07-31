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

-- Rewrite the macro body of every existing set button (no re-binding). Cheap, so
-- it is safe to call after any set edit.
function Addon:RefreshSetMacros()
    if InCombatLockdown() then
        whenOutOfCombat("macros", function() Addon:RefreshSetMacros() end)
        return
    end
    for _, btn in ipairs(Addon._bindButtons or {}) do
        if btn._setName and Addon.db.sets[btn._setName] then
            btn:SetAttribute("macrotext", Addon:BuildSetMacroText(btn._setName))
        end
    end
end

-- Coalesce a burst of set edits into one rewrite on the next frame.
function Addon:QueueMacroRefresh()
    if Addon._macroRefreshQueued then return end
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
    local i = 0
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
            btn:SetAttribute("macrotext", Addon:BuildSetMacroText(name))
            SetOverrideBindingClick(owner, true, set.key, btn:GetName())
        end
    end
    -- Buttons past the last bound set keep stale text otherwise.
    for j = i + 1, #Addon._bindButtons do Addon._bindButtons[j]._setName = nil end

    -- Item names are not always cached at login; re-resolve shortly after so a
    -- weapon whose name arrived late still gets its /equipslot line.
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
