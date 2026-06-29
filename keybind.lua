--[[
    Daseeki Armory — per-set keybinds.

    Each set may have a `set.key` (e.g. "CTRL-1"). At login (and whenever a key
    changes) we bind it via SetOverrideBindingClick to a hidden secure button whose
    macrotext runs ArmEquip("<set>"). A small modal captures the key press.
--]]

local _, Addon = ...

-- (Re)apply override bindings for every set that has a key. Deferred out of combat.
function Addon:ApplySetBindings()
    if InCombatLockdown() then
        if not Addon._bindRegen then
            Addon._bindRegen = CreateFrame("Frame")
            Addon._bindRegen:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                Addon:ApplySetBindings()
            end)
        end
        Addon._bindRegen:RegisterEvent("PLAYER_REGEN_ENABLED")
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
            btn:SetAttribute("type", "macro")
            btn:SetAttribute("macrotext", '/run ArmEquip("' .. name .. '")')
            SetOverrideBindingClick(owner, true, set.key, btn:GetName())
        end
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
        f:SetBackdropColor(0, 0, 0, 0.95); f:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOP", 0, -18); f.title:SetText("Press a key…"); f.title:SetTextColor(1, 0.82, 0)
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
