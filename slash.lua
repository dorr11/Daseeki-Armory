--[[
    Daseeki Armory — slash commands.
        /darmory            open the Armory section in the Daseeki-Core hub
        /darmory equip <n>  equip a set by name
        /darmory widget     toggle the on-screen set switcher
        /darmory list       print this character's sets
        /darmory stats      toggle the stats panel attached to the character window

    `stats` exists so the attach setting stays reachable when Daseeki-Core is absent
    (the options hub needs Core; this command does not).
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
        print(Addon:Tag() .. " switcher " ..
            (Addon.db.settings.widget.show and "shown." or "hidden."))
        return
    elseif cmd == "stats" then
        local s = Addon.db.settings.stats
        s.attach = not s.attach
        Addon:UpdateStatsPanelShown()
        local msg = s.attach and "stats panel attached to the character window."
                              or "stats panel detached."
        if s.attach and not Addon:StatsUIReady() then
            msg = "stats panel needs Daseeki-Core — setting is on, but nothing will show."
        end
        print(Addon:Tag() .. " " .. msg)
        return
    elseif cmd == "list" then
        local sets = Addon:GetSetsSorted()
        if #sets == 0 then
            print(Addon:Tag() .. " no sets yet. Open options to create one.")
        else
            print(Addon:Tag() .. " sets:")
            for _, s in ipairs(sets) do
                print("  - " .. s.name .. (Addon.db.currentSet == s.name and ("  " .. Addon:Wrap("brand", "(current)")) or ""))
            end
        end
        return
    end

    if _G.DaseekiSuite then
        DaseekiSuite:Open("armory")
    else
        print(Addon:Tag("Daseeki Armory") .. " — Daseeki-Core not loaded, so the options " ..
            "window is unavailable. Sets still work via macros: /run ArmEquip(\"name\")")
    end
end
