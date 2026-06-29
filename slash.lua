--[[
    Daseeki Armory — slash commands.
        /darmory            open the Armory section in the Daseeki-Core hub
        /darmory equip <n>  equip a set by name
        /darmory widget     toggle the on-screen set switcher
        /darmory list       print this character's sets
--]]

local _, Addon = ...

SLASH_DASEEKIARMORY1 = "/darmory"
SLASH_DASEEKIARMORY2 = "/armory"

SlashCmdList["DASEEKIARMORY"] = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.*)$")
    cmd  = (cmd or ""):lower()
    rest = strtrim(rest or "")

    if cmd == "equip" and rest ~= "" then
        Addon:EquipSet(rest)
        return
    elseif cmd == "widget" then
        Addon:SetWidgetShown(not Addon.db.settings.widget.show)
        print("|cff66ccffArmory|r switcher " ..
            (Addon.db.settings.widget.show and "shown." or "hidden."))
        return
    elseif cmd == "list" then
        local sets = Addon:GetSetsSorted()
        if #sets == 0 then
            print("|cff66ccffArmory|r no sets yet. Open options to create one.")
        else
            print("|cff66ccffArmory|r sets:")
            for _, s in ipairs(sets) do
                print("  - " .. s.name .. (Addon.db.currentSet == s.name and "  |cffffd100(current)|r" or ""))
            end
        end
        return
    end

    if _G.DaseekiSuite then
        DaseekiSuite:Open("armory")
    else
        print("|cff66ccffDaseeki Armory|r — Daseeki-Core not loaded, so the options " ..
            "window is unavailable. Sets still work via macros: /run ArmEquip(\"name\")")
    end
end
