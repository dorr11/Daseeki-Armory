--[[
    Daseeki Armory — slash commands.
        /darmory            open the Armory section in the Daseeki-Core hub
        /darmory equip <n>  equip a set by name
        /darmory widget     toggle the on-screen set switcher
        /darmory list       print this character's sets
        /darmory stats      toggle the stats panel attached to the character window
        /darmory data       what this build ships: items, locks, hidden

    `stats` exists so the attach setting stays reachable when Daseeki-Core is absent
    (the options hub needs Core; this command does not).

    `data` WAS `scanstatus`, AND THE RENAME IS THE RELEASE (1.3.1). It used to
    answer questions about a process — is the scan still running, how far has it
    got, when did it last finish, how many rows are still unread — because the item
    database was something each user produced for themselves. The database is
    shipped now, so the only honest question left is "what is in this build?", and
    the answer is three counts that are identical on every account. `scanstatus`
    still works as an alias: it is in muscle memory and in a release note, and
    silently failing a command someone learned is worse than answering it.

    THE UNDOCUMENTED ONE: /darmory devscan. It runs the item scan that captures a
    new client build for dev/gen-catalog.lua. It is deliberately absent from the
    list above, from the options UI and from every tooltip, and it refuses to run
    unless a global flag is armed — see THE SCAN SURVIVES AS A DEVELOPER TOOL in
    itemScan.lua. A player who finds it by accident gets an explanation, not a scan.
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
    elseif cmd == "data" or cmd == "scanstatus" or cmd == "scan" then
        local Scan = Addon.ItemScan
        if not (Scan and Scan.StatusReport) then
            print(Addon:Tag() .. " the item module is not loaded.")
            return
        end
        print(Addon:Tag() .. " shipped item data:")
        for _, line in ipairs(Scan.StatusReport()) do
            print("  " .. line)
        end
        return

    -- UNDOCUMENTED, AND GATED. The scan exists to regenerate catalog.lua and
    -- restrictions.lua for a new client build; it is not something a player needs
    -- and it must not be startable by one. Addon:StartDevScan refuses unless the
    -- developer flag is armed and explains itself when it does.
    elseif cmd == "devscan" then
        if not Addon.StartDevScan then
            print(Addon:Tag() .. " the item module is not loaded.")
            return
        end
        local started, why = Addon:StartDevScan()
        if started then
            print(Addon:Tag() .. " DEV scan started — walking the client's item space. "
                .. "This does not affect the goal picker; it captures a file for "
                .. "dev/gen-catalog.lua.")
        else
            print(Addon:Tag() .. " " .. tostring(why))
        end
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
