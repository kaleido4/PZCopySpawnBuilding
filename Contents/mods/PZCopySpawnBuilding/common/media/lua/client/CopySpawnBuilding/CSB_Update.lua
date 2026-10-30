--[[
    Copy Spawn Building - keeps known blueprints up to date. Once a game
    minute, a blueprint made by an older version of the rules
    (CSB.CAPTURE_VERSION) is studied again from its original if that is
    loaded, so a fix to what gets copied needs no studying again.
--]]

require "CopySpawnBuilding/CSB_Capture"
require "CopySpawnBuilding/CSB_Store"

CSB.Update = {}

-- ids not worth trying again this session: gone, or the study failed
local givenUp = {}

function CSB.Update.check(player)
    for _, bp in ipairs(CSB.Store.list(player)) do
        if (bp.v or 1) < CSB.CAPTURE_VERSION and not givenUp[bp.id] then
            local new, why = CSB.Capture.restudy(bp)
            if new then
                CSB.Store.put(new)
                CSB.Capture.writeReport("update", new)
                player:setHaloNote(getText("IGUI_CSB_Updated", new.name))
            elseif why ~= "away" then
                givenUp[bp.id] = true
            end
        end
    end
end

Events.EveryOneMinute.Add(function()
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player then CSB.Update.check(player) end
    end
end)
