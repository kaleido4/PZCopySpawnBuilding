--[[
    Copy Spawn Building - right-click menu:
      * "Study building" on or next to a building: its floor, its walls, or
        its upper floors and roof as drawn on screen (CSB.Capture.buildingAt);
      * "Study structure" on or under a roof that is not part of a building
        (carport, porch roof, shelter);
      * "Remove spawned building" on or next to a copy that was built
        (CSB.Spawn.copyAt);
      * "Studied buildings" when the character knows some, which opens the
        window to build or forget them (CSB_Window.lua).
--]]

require "CopySpawnBuilding/CSB_Store"
require "CopySpawnBuilding/CSB_StudyAction"
require "CopySpawnBuilding/CSB_Window"

CSB.Menu = {}

local function clickedSquare(worldobjects)
    for _, obj in ipairs(worldobjects) do
        local sq = obj:getSquare()
        if sq then return sq end
    end
    return nil
end

-- target: { def = BuildingDef } or { structure = found }, see CSB_StudyAction
function CSB.Menu.onStudy(player, target, square)
    if luautils.walkAdj(player, square, true) then
        ISTimedActionQueue.add(CSB_StudyAction:new(player, target, square))
    end
end

local function addStudyOption(context, player, text, target, square, id, problem)
    local option = context:addOption(getText(text), player, CSB.Menu.onStudy, target, square)
    local tooltip = ISWorldObjectContextMenu.addToolTip()
    if problem then
        option.notAvailable = true
        tooltip.description = getText(problem)
    elseif id and CSB.Store.knows(player, id) then
        -- studying it again replaces the blueprint, e.g. after it changed
        tooltip.description = getText("IGUI_CSB_AlreadyKnown")
    else
        tooltip.description = getText(text .. "Tooltip")
    end
    option.toolTip = tooltip
end

function CSB.Menu.onRemove(player, record)
    CSB.Spawn.remove(record)
    player:setHaloNote(getText("IGUI_CSB_Removed", record.name or ""))
end

function CSB.Menu.fill(playerNum, context, worldobjects, test)
    if test and ISWorldObjectContextMenu.Test then return true end
    local player = getSpecificPlayer(playerNum)
    if not player or player:getVehicle() then return end

    local square = clickedSquare(worldobjects)
    local def = square and CSB.Capture.buildingAt(square)
    if def then
        local problem = not def:isFullyStreamedIn() and "IGUI_CSB_NotLoaded" or nil
        addStudyOption(context, player, "IGUI_CSB_StudyBuilding", { def = def }, square,
            CSB.Capture.buildingId(def, square:getZ()), problem)
    elseif square then
        local found, why = CSB.Capture.findStructure(square)
        if found then
            addStudyOption(context, player, "IGUI_CSB_StudyStructure", { structure = found }, square, found.id)
        elseif why == "tooBig" then
            addStudyOption(context, player, "IGUI_CSB_StudyStructure", nil, square, nil, "IGUI_CSB_TooBig")
        end
    end

    local copy = square and CSB.Spawn.copyAt(square)
    if copy then
        local option = context:addOption(getText("IGUI_CSB_RemoveCopy", copy.name or ""), player, CSB.Menu.onRemove, copy)
        local tooltip = ISWorldObjectContextMenu.addToolTip()
        tooltip.description = getText("IGUI_CSB_RemoveCopyTooltip")
        option.toolTip = tooltip
    end

    local known = CSB.Store.list(player)
    if #known > 0 then
        context:addOption(getText("IGUI_CSB_WindowMenu", #known), player, CSB.Window.show)
    end
end

Events.OnFillWorldObjectContextMenu.Add(CSB.Menu.fill)
