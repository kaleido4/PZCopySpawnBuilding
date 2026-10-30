--[[
    Copy Spawn Building - right-click menu:
      * "Study building" on or next to a building: its floor, its walls, or
        its upper floors and roof as drawn on screen (CSB.Capture.buildingAt);
      * "Study structure" on or under a roof that is not part of a building
        (carport, porch roof, shelter);
      * "Remove spawned building" on or next to a copy that was built
        (CSB.Spawn.copyAt);
      * "Build studied building" with the buildings the character knows, which
        starts the placement cursor (CSB_Cursor.lua);
      * "Forget studied building" to take one off that list.
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
        -- studying it again replaces the blueprint, e.g. after it changed
        tooltip.description = getText("IGUI_CSB_AlreadyKnown")
    else
        tooltip.description = getText(text .. "Tooltip")
    end
    option.toolTip = tooltip
end

function CSB.Menu.onBuild(player, bp)
    getCell():setDrag(CSB_Cursor:new(player, bp), player:getPlayerNum())
end

function CSB.Menu.onRemove(player, record)
    CSB.Spawn.remove(record)
    player:setHaloNote(getText("IGUI_CSB_Removed", record.name or ""))
end

function CSB.Menu.onForget(player, bp)
    CSB.Store.forget(player, bp.id)
    player:setHaloNote(getText("IGUI_CSB_Forgot", bp.name))
end

-- A submenu with one option per known building.
local function knownSubMenu(context, player, text, onPick, known)
    local parent = context:addOption(getText(text))
    local subMenu = ISContextMenu:getNew(context)
    context:addSubMenu(parent, subMenu)
    for _, bp in ipairs(known) do
        subMenu:addOption(bp.name .. " (" .. describe(bp) .. ")", player, onPick, bp)
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
        knownSubMenu(context, player, "IGUI_CSB_BuildMenu", CSB.Menu.onBuild, known)
        knownSubMenu(context, player, "IGUI_CSB_ForgetMenu", CSB.Menu.onForget, known)
    end
end

Events.OnFillWorldObjectContextMenu.Add(CSB.Menu.fill)
