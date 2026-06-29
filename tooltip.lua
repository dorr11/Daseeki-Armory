--[[
    Daseeki Armory — item tooltip integration.

    Like ItemRack, an item that belongs to one or more Armory sets gets a line on
    its tooltip listing those sets — in ORANGE (ItemRack uses blue).
--]]

local _, Addon = ...

local ORANGE = { 1, 0.5, 0 }

function Addon:GetSetsContainingItem(itemId)
    local out = {}
    if not itemId then return out end
    for _, set in ipairs(Addon:GetSetsSorted()) do
        for _, e in pairs(set.equip) do
            if e.id == itemId then
                out[#out + 1] = set.name
                break
            end
        end
    end
    return out
end

local function addSetLine(tt)
    local _, link = tt:GetItem()
    if not link then return end
    local id = tonumber(link:match("item:(%d+)"))
    if not id then return end
    local names = Addon:GetSetsContainingItem(id)
    if #names == 0 then return end
    tt:AddLine("Armory: " .. table.concat(names, ", "), ORANGE[1], ORANGE[2], ORANGE[3])
    tt:Show()
end

function Addon:InitTooltip()
    if Addon._tooltipHooked then return end
    Addon._tooltipHooked = true
    GameTooltip:HookScript("OnTooltipSetItem", addSetLine)
    if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetItem", addSetLine) end
end
