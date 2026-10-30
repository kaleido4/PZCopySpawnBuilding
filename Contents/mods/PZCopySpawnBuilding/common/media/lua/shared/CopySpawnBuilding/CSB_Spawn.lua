--[[
    Copy Spawn Building - building a copy from a blueprint.

    Pieces are made the way the map loader and the moveables code make them
    (ISMoveableSpriteProps:placeMoveableInternal, B42.22): floors with
    addFloor (which also clears the grass, plants and trees on the square),
    doors as IsoDoor, windows as IsoWindow, window frames as IsoWindowFrame,
    and everything else as a plain IsoObject. Plain map walls are IsoObjects,
    not the IsoThumpables players build, so zombies cannot break a copy's
    walls, the same as the building it was copied from.

    Before that, plants, trees and items lying on the copy's squares are
    removed, so nothing ends up inside a wall.

    Single player for now: objects are added straight to the squares.
--]]

require "CopySpawnBuilding/CSB_Core"

CSB.Spawn = {}

local footprints = {}

-- The blueprint's footprint (CSB.footprint), worked out once.
function CSB.Spawn.footprint(bp)
    local fp = footprints[bp.id]
    if not fp or fp.tiles ~= bp.tiles then
        fp = CSB.footprint(bp)
        fp.tiles = bp.tiles
        footprints[bp.id] = fp
    end
    return fp
end

local footprint = CSB.Spawn.footprint

--[[
    Looks over the squares a copy would use with its box starting at
    (ox, oy, oz). Returns:
        problem      why it cannot be built, or nil when it can
        px, py, pz   the square in the way
        cluttered[i] ground column i (footprint order) has plants, trees or
                     items on it, which building removes
    With firstProblem set, stops at the first problem and skips clutter.
--]]
function CSB.Spawn.survey(bp, ox, oy, oz, firstProblem)
    local cell = getCell()
    local fp = footprint(bp)
    local result = { cluttered = {} }
    for i, c in ipairs(fp.columns) do
        local x, y = ox + c.x, oy + c.y
        local sq = cell:getGridSquare(x, y, oz)
        local problem = CSB.groundProblem(sq)
        if problem and not result.problem then
            result.problem, result.px, result.py, result.pz = problem, x, y, oz
            if firstProblem then return result end
        end
        if sq and not firstProblem then result.cluttered[i] = CSB.cluttered(sq) end
    end
    if not result.problem then
        for _, s in ipairs(fp.upper) do
            local x, y, z = ox + s.x, oy + s.y, oz + s.z
            local problem = CSB.upperProblem(cell:getGridSquare(x, y, z))
            if problem then
                result.problem, result.px, result.py, result.pz = problem, x, y, z
                break
            end
        end
    end
    return result
end

-- Why the copy cannot be built with its box starting at (ox, oy, oz), or nil.
-- Also returns the square that is in the way.
function CSB.Spawn.problem(bp, ox, oy, oz)
    local s = CSB.Spawn.survey(bp, ox, oy, oz, true)
    return s.problem, s.px, s.py, s.pz
end

local function attach(obj, names)
    if not names then return end
    for _, name in ipairs(names) do
        local sprite = getSprite(name)
        if sprite then obj:AttachExistingAnim(sprite, 0, 0, false, 0, false, 0) end
    end
end

local function newPiece(cell, sq, t)
    local sprite = getSprite(t.s)
    if not sprite then return nil end
    local props = sprite:getProperties()
    if t.k == "door" then
        return IsoDoor.new(cell, sq, t.s, props:has(IsoFlagType.doorN))
    elseif t.k == "window" then
        local window = IsoWindow.new(cell, sq, sprite, props:has(IsoFlagType.windowN))
        window:setIsLocked(false)
        return window
    elseif t.k == "frame" then
        return IsoWindowFrame.new(cell, sq, sprite, props:has(IsoFlagType.WindowN))
    end
    return IsoObject.new(cell, sq, t.s)
end

local function clearPlants(sq)
    local objects = sq:getObjects()
    for i = objects:size() - 1, 0, -1 do
        local obj = objects:get(i)
        if obj ~= sq:getFloor() and CSB.clearable(obj) then
            sq:RemoveTileObject(obj)
        end
    end
end

-- Removes the items lying on the square, the way the game's debug item
-- remover does (ISRemoveItemTool).
local function clearItems(sq)
    local items = sq:getWorldObjects()
    for i = items:size() - 1, 0, -1 do
        local worldItem = items:get(i)
        local item = worldItem:getItem()
        sq:transmitRemoveItemFromSquare(worldItem)
        sq:removeWorldObject(worldItem)
        if item then item:setWorldItem(nil) end
    end
end

--[[
    Builds the copy with its box starting at (ox, oy, oz). Returns a record of
    what was done, for CSB.Spawn.undo:
        placed   { x, y, z, s } of every piece, in the order they were added
        ground   [ "x,y" ] = sprite of the ground floor a copy floor replaced
--]]
function CSB.Spawn.place(bp, ox, oy, oz)
    local cell = getCell()
    local record = { id = bp.id, placed = {}, ground = {} }
    local touched = {}

    local fp = footprint(bp)
    for _, c in ipairs(fp.columns) do
        local sq = cell:getGridSquare(ox + c.x, oy + c.y, oz)
        if sq then
            clearPlants(sq)
            clearItems(sq)
        end
    end
    for _, s in ipairs(fp.upper) do
        local sq = cell:getGridSquare(ox + s.x, oy + s.y, oz + s.z)
        if sq then clearItems(sq) end
    end

    -- floors first, so walls and roofs go on top of them
    for pass = 1, 2 do
        for _, t in ipairs(bp.tiles) do
            if (t.k == "floor") == (pass == 1) then
                local x, y, z = ox + t.x, oy + t.y, oz + t.z
                local sq = cell:getGridSquare(x, y, z) or cell:createNewGridSquare(x, y, z, true)
                if sq then
                    local obj
                    if t.k == "floor" then
                        local old = sq:getFloor()
                        if t.z == 0 and old and old:getSprite() then
                            record.ground[x .. "," .. y] = old:getSprite():getName()
                        end
                        obj = sq:addFloor(t.s)
                    else
                        obj = newPiece(cell, sq, t)
                        if obj then sq:AddSpecialObject(obj) end
                    end
                    if obj then
                        attach(obj, t.a)
                        table.insert(record.placed, { x = x, y = y, z = z, s = t.s })
                        touched[sq] = true
                    end
                end
            end
        end
    end

    for sq in pairs(touched) do
        sq:RecalcProperties()
        sq:RecalcAllWithNeighbours(true)
    end
    return record
end

-- Takes a copy down again: removes its pieces and puts back the ground
-- floors it replaced. Plants, trees and items it cleared do not come back.
function CSB.Spawn.undo(record)
    local cell = getCell()
    local touched = {}
    for i = #record.placed, 1, -1 do
        local p = record.placed[i]
        local sq = cell:getGridSquare(p.x, p.y, p.z)
        if sq then
            local objects = sq:getObjects()
            for j = objects:size() - 1, 0, -1 do
                local obj = objects:get(j)
                if obj:getSprite() and obj:getSprite():getName() == p.s then
                    sq:RemoveTileObject(obj)
                    break
                end
            end
            local old = record.ground[p.x .. "," .. p.y]
            if old and p.z == 0 and not sq:getFloor() then sq:addFloor(old) end
            touched[sq] = true
        end
    end
    for sq in pairs(touched) do
        sq:RecalcProperties()
        sq:RecalcAllWithNeighbours(true)
    end
end
