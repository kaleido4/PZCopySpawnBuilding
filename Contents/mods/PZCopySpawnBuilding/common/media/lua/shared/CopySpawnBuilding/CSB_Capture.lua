--[[
    Copy Spawn Building - studying: reads a building's pieces from the world
    into a blueprint (rules in CSB_Core.lua).

    Two kinds of things can be studied:
      * a building: the map knows it by its rooms (a BuildingDef). The whole
        building has to be loaded (BuildingDef:isFullyStreamedIn), or part of
        it would be missing from the copy;
      * a structure: a roof with no rooms under it (carport, porch roof,
        shelter), found by following its roof from the square clicked
        (CSB.Capture.findStructure).
    Basements are left out for now: a copy is built on the ground, from the
    ground level up.

    Each study writes a report to Zomboid/Lua/CopySpawnBuilding_last_study.txt:
    the pieces kept, and what was left behind on the squares it covers with
    the tile's flags, to see why a piece was or was not copied.
--]]

require "CopySpawnBuilding/CSB_Core"

CSB.Capture = {}

local key = CSB.key

-- Ground floor rooms of the building: { { name, area }, ... }
local function rooms(def, groundZ)
    local list = {}
    local defRooms = def:getRooms()
    for i = 0, defRooms:size() - 1 do
        local room = defRooms:get(i)
        if room:getZ() == groundZ then
            table.insert(list, { name = room:getName(), area = room:getArea() })
        end
    end
    return list
end

function CSB.Capture.groundZ(def)
    return math.max(0, def:getMinLevel())
end

function CSB.Capture.area(def)
    local total = 0
    for _, room in ipairs(rooms(def, CSB.Capture.groundZ(def))) do
        total = total + room.area
    end
    return total
end

local function attachedNames(obj)
    local list = obj:getAttachedAnimSprite()
    if not list or list:size() == 0 then return nil end
    local names = {}
    for i = 0, list:size() - 1 do
        local sprite = list:get(i) and list:get(i):getParentSprite()
        local name = sprite and sprite:getName()
        if not CSB.skipSprite(name) then table.insert(names, name) end
    end
    if #names == 0 then return nil end
    return names
end

-- Whether another building than `ownId` stands on the column, on any level
-- from z1 to z2. Roof squares are not part of any building, so a neighbour's
-- roof is known by the building under it.
local function otherBuildingAt(cell, x, y, z1, z2, ownId)
    for z = z1, z2 do
        local sq = cell:getGridSquare(x, y, z)
        local building = sq and sq:getBuilding()
        local def = building and building:getDef()
        if def and (ownId == nil or def:getID() ~= ownId) then return true end
    end
    return false
end

--[[
    Goes over the squares from (x1, y1) to (x2, y2), margin included, on the
    levels groundZ to topZ, and keeps the pieces that belong (CSB.belongs
    with ctx; ctx.foreign is filled in per column here). Returns the tiles
    in world coordinates. What it leaves behind on covered columns goes to
    CSB.Capture.lastSkipped, for the report.
--]]
local function scan(x1, y1, x2, y2, groundZ, topZ, ctx, ownId)
    local cell = getCell()
    local foreignSet = {}
    local tiles = {}
    local skipped = {}
    CSB.Capture.lastSkipped = skipped
    local m = CSB.MARGIN
    for z = groundZ, math.min(31, topZ) do
        for y = y1 - m, y2 + m do
            for x = x1 - m, x2 + m do
                local sq = cell:getGridSquare(x, y, z)
                if sq then
                    local k = key(x, y)
                    if foreignSet[k] == nil then
                        foreignSet[k] = otherBuildingAt(cell, x, y, groundZ, topZ, ownId)
                    end
                    ctx.foreign = foreignSet[k]
                    local objects = sq:getObjects()
                    for i = 0, objects:size() - 1 do
                        local obj = objects:get(i)
                        local kind = CSB.classify(obj)
                        local kept = false
                        if kind then
                            local sprite = obj:getSprite()
                            local piece = { kind = kind, edges = CSB.edges(sprite:getProperties()), name = sprite:getName() }
                            if CSB.belongs(piece, x, y, z, ctx) then
                                table.insert(tiles, { x = x, y = y, z = z, s = piece.name, k = kind, a = attachedNames(obj) })
                                kept = true
                            end
                        end
                        if not kept and ctx.covered(x, y) and obj:getSprite()
                            and not instanceof(obj, "IsoWorldInventoryObject") then
                            table.insert(skipped, { x = x, y = y, z = z, obj = obj, kind = kind })
                        end
                    end
                end
            end
        end
    end
    return tiles
end

-- The blueprint from scanned tiles, or nil and "empty".
local function blueprint(tiles, groundZ, id, name, area)
    if #tiles == 0 then return nil, "empty" end
    local w, h, levels = CSB.normalize(tiles, groundZ)
    return { id = id, name = name, w = w, h = h, levels = levels, area = area, tiles = tiles }
end

-- Studies a building. Returns the blueprint, or nil and why not
-- ("notLoaded", "empty").
function CSB.Capture.study(def)
    CSB.Capture.lastSkipped = {}
    if not def:isFullyStreamedIn() then return nil, "notLoaded" end
    local x1, y1, x2, y2 = def:getX(), def:getY(), def:getX2(), def:getY2()
    local groundZ = CSB.Capture.groundZ(def)
    local topZ = def:getMaxLevel()

    -- columns the building covers on some level, seen from above
    local coveredSet = {}
    for x = x1, x2 do
        for y = y1, y2 do
            for z = groundZ, topZ do
                if def:containsXYZ(x, y, z) then
                    coveredSet[key(x, y)] = true
                    break
                end
            end
        end
    end
    local ctx = {
        room = function(x, y, z) return def:containsXYZ(x, y, z) end,
        covered = function(x, y) return coveredSet[key(x, y)] == true end,
        groundZ = groundZ,
    }
    local tiles = scan(x1, y1, x2, y2, groundZ, topZ + CSB.ROOF_LEVELS, ctx, def:getID())
    local groundRooms = rooms(def, groundZ)
    local area = 0
    for _, r in ipairs(groundRooms) do area = area + r.area end
    return blueprint(tiles, groundZ, x1 .. "_" .. y1, CSB.buildingName(groundRooms), area)
end

--[[
    Finds the structure over a square: a roof right above it or above a
    square next to it, followed to its edges (CSB.roofColumns). Returns
        { id, groundZ, topZ, x1, y1, x2, y2, columns, count }
    or nil and why ("noRoof", "partOfBuilding", "tooBig").
--]]
function CSB.Capture.findStructure(sq)
    local cell = getCell()
    local groundZ = sq:getZ()
    local lastZ = math.min(31, groundZ + CSB.ROOF_LEVELS)

    -- the level of the lowest roof piece over the column, or nil
    local roofLevels = {}
    local function roofAt(x, y)
        local k = key(x, y)
        if roofLevels[k] == nil then
            roofLevels[k] = false
            for z = groundZ + 1, lastZ do
                local s = cell:getGridSquare(x, y, z)
                if s then
                    local objects = s:getObjects()
                    for i = 0, objects:size() - 1 do
                        if CSB.isRoofPiece(objects:get(i)) then
                            roofLevels[k] = z
                            break
                        end
                    end
                end
                if roofLevels[k] then break end
            end
        end
        return roofLevels[k] or nil
    end

    local sx, sy
    for _, d in ipairs({ { 0, 0 }, { 0, -1 }, { -1, 0 }, { 1, 0 }, { 0, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
        if roofAt(sq:getX() + d[1], sq:getY() + d[2]) then
            sx, sy = sq:getX() + d[1], sq:getY() + d[2]
            break
        end
    end
    if not sx then return nil, "noRoof" end

    local columns, count = CSB.roofColumns(sx, sy,
        function(x, y) return roofAt(x, y) ~= nil end,
        function(x, y) return otherBuildingAt(cell, x, y, groundZ, lastZ, nil) end)
    if not columns then return nil, count end

    local x1, y1, x2, y2, topZ
    for _, c in pairs(columns) do
        x1, y1 = math.min(x1 or c.x, c.x), math.min(y1 or c.y, c.y)
        x2, y2 = math.max(x2 or c.x, c.x), math.max(y2 or c.y, c.y)
        topZ = math.max(topZ or 0, roofAt(c.x, c.y))
    end
    return {
        id = "s_" .. x1 .. "_" .. y1,
        groundZ = groundZ, topZ = topZ,
        x1 = x1, y1 = y1, x2 = x2, y2 = y2,
        columns = columns, count = count,
    }
end

-- The tile's flags and property names, e.g. "WallSE solidtrans | Material".
local function propsText(props)
    local parts = {}
    local flags = props.getFlagsList and props:getFlagsList()
    if flags then
        for i = 0, flags:size() - 1 do table.insert(parts, tostring(flags:get(i))) end
    end
    local names = props.getPropertyNames and props:getPropertyNames()
    if names and names:size() > 0 then
        table.insert(parts, "|")
        for i = 0, names:size() - 1 do table.insert(parts, tostring(names:get(i))) end
    end
    return table.concat(parts, " ")
end

-- The study report as lines: what was kept, and what was left behind on the
-- covered squares (from the last scan) with the tile's flags.
function CSB.Capture.reportLines(label, bp, why)
    local lines = { "Copy Spawn Building - last study: " .. label }
    if not bp then
        table.insert(lines, "Nothing kept: " .. tostring(why))
    else
        table.insert(lines, "Kept " .. #bp.tiles .. " pieces of " .. bp.name .. " (" .. bp.id .. "), "
            .. bp.w .. " x " .. bp.h .. ", " .. bp.levels .. " levels. x, y from the box corner, z from the ground:")
        for _, t in ipairs(bp.tiles) do
            local attached = t.a and (" + " .. table.concat(t.a, ", ")) or ""
            table.insert(lines, "  " .. t.k .. "  " .. t.x .. "," .. t.y .. "," .. t.z .. "  " .. t.s .. attached)
        end
    end
    local skipped = CSB.Capture.lastSkipped or {}
    table.insert(lines, "Left behind on the squares it covers (" .. #skipped .. "), world x, y, z:")
    for _, s in ipairs(skipped) do
        local sprite = s.obj:getSprite()
        table.insert(lines, "  " .. s.x .. "," .. s.y .. "," .. s.z .. "  " .. sprite:getName()
            .. "  [" .. tostring(s.kind or "not structure") .. "]  " .. propsText(sprite:getProperties()))
    end
    return lines
end

function CSB.Capture.writeReport(label, bp, why)
    local writer = getFileWriter("CopySpawnBuilding_last_study.txt", true, false)
    if not writer then return end
    for _, line in ipairs(CSB.Capture.reportLines(label, bp, why)) do
        writer:write(line .. lineSeparator())
    end
    writer:close()
end

-- Studies the structure over a square (see findStructure). Returns the
-- blueprint, or nil and why not.
function CSB.Capture.studyStructure(sq)
    CSB.Capture.lastSkipped = {}
    local found, why = CSB.Capture.findStructure(sq)
    if not found then return nil, why end
    local ctx = {
        room = function() return false end,
        covered = function(x, y) return found.columns[key(x, y)] ~= nil end,
        groundZ = found.groundZ,
        groundFloors = true,
    }
    -- levels above the lowest roof piece: ridges and gable tops
    local tiles = scan(found.x1, found.y1, found.x2, found.y2, found.groundZ, found.topZ + 2, ctx, nil)
    return blueprint(tiles, found.groundZ, found.id, CSB.STRUCTURE_NAME, found.count)
end
