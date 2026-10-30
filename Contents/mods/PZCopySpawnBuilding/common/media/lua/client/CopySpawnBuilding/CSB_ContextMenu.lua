--[[
    Copy Spawn Building - right-click menu:
      * "Study building" on a building: its floor, its walls, or its upper
        floors and roof as drawn on screen (CSB.Capture.buildingAt);
      * "Study structure" on or under a roof that is not part of a building
        (carport, porch roof, shelter);
      * "Build studied building" with the buildings the character knows, which
        starts the placement cursor (CSB_Cursor.lua);
      * in debug mode, "Undo last spawned building".
--]]

require "CopySpawnBuilding/CSB_Store"
require "CopySpawnBuilding/CSB_StudyAction"

CSB.Menu = {}

local function clickedSquare(worldobjects)
    for _, obj in ipairs(worldobjects) do
        local sq = obj:getSquare()
        if sq then return sq end
    end
    return nil
end

local function describe(bp)
    return getText("IGUI_CSB_Size", bp.w, bp.h, bp.levels)
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
        option.notAvailable = true
        tooltip.description = getText("IGUI_CSB_AlreadyKnown")
    else
        tooltip.description = getText(text .. "Tooltip")
    end
    option.toolTip = tooltip
end

function CSB.Menu.onBuild(player, bp)
    getCell():setDrag(CSB_Cursor:new(player, bp), player:getPlayerNum())
end

function CSB.Menu.onUndo(player)
    if CSB.lastSpawn then
        CSB.Spawn.undo(CSB.lastSpawn)
        CSB.lastSpawn = nil
    end
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
            def:getX() .. "_" .. def:getY(), problem)
    elseif square then
        local found, why = CSB.Capture.findStructure(square)
        if found then
            addStudyOption(context, player, "IGUI_CSB_StudyStructure", { structure = found }, square, found.id)
        elseif why == "tooBig" then
            addStudyOption(context, player, "IGUI_CSB_StudyStructure", nil, square, nil, "IGUI_CSB_TooBig")
        end
    end

    local known = CSB.Store.list(player)
    if #known > 0 then
        local parent = context:addOption(getText("IGUI_CSB_BuildMenu"))
        local subMenu = ISContextMenu:getNew(context)
        context:addSubMenu(parent, subMenu)
        for _, bp in ipairs(known) do
            subMenu:addOption(bp.name .. " (" .. describe(bp) .. ")", player, CSB.Menu.onBuild, bp)
        end
    end

    if isDebugEnabled() and CSB.lastSpawn then
        context:addOption(getText("IGUI_CSB_UndoLast"), player, CSB.Menu.onUndo)
    end
end

Events.OnFillWorldObjectContextMenu.Add(CSB.Menu.fill)
