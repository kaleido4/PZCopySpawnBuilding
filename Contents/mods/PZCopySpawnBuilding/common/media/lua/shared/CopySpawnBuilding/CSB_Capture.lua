--[[
    Copy Spawn Building - studying: reads a building's pieces from the world
    into a blueprint (rules in CSB_Core.lua).

    Two kinds of things can be studied:
      * a building: the map knows it by its rooms (a BuildingDef). The whole
        building has to be loaded (BuildingDef:isFullyStreamedIn), or part of
        it would be missing from the copy;
      * a structure: a roof with no building at all (CSB.Capture.findStructure).

    A building has two kinds of rooms (B42.22): real rooms (getRooms) and
    "emptyoutside" rooms (getEmptyOutside), the covered outdoor spots such as
    porches and carports. A square's getBuilding() and the map's getRoomAt()
    only see real rooms, so buildings are looked up in the map data with both
    (defAt). A carport is often a building whose only room is an emptyoutside
    room on level 1, up at its roof, with nothing of it on the ground: then
    the copy still starts from the ground, and the floor under the roof is
    copied like a structure's.

    BuildingDef:containsXYZ only checks the building's outer box, so which
    squares are rooms comes from the rooms' own rectangles (layout).

    Basements are left out for now: a copy is built on the ground, from the
    ground level up.

    Each study writes a report to Zomboid/Lua/CopySpawnBuilding_last_study.txt:
    the pieces kept, and what was left behind on and next to the squares it
    covers with the tile's flags, to see why a piece was or was not copied.
--]]

require "CopySpawnBuilding/CSB_Core"

CSB.Capture = {}

local key = CSB.key

local function key3(x, y, z)
    return key(x, y) * 100 + z
end

-- The building with a room (real or emptyoutside) on square (x, y, z), from
-- the map data, loaded or not.
local function defAt(x, y, z)
    local meta = getWorld():getMetaGrid()
    local room = meta:getRoomAt(x, y, z) or meta:getEmptyOutsideAt(x, y, z)
    return room and room:getBuilding() or nil
end
CSB.Capture.defAt = defAt

--[[
    Where the building's rooms are, from their rectangles. clickZ is the level
    the player studies it from: the copy's ground is the building's lowest
    room, or that level if it is lower (a carport's room is up at its roof),
    and never below 0 (no basements).
        rooms     real rooms on the ground level: { { name, area } }
        roomSet   [key3(x, y, z)] squares of a room, real or emptyoutside
        covered   [key(x, y)] columns with a room on some level
        count     how many covered columns
        x1, y1, x2, y2, groundZ, topZ   bounds (inclusive) and levels
        groundRooms  true when some room is on the ground level
--]]
function CSB.Capture.layout(def, clickZ)
    local l = { rooms = {}, roomSet = {}, covered = {}, count = 0 }
    local all = {}
    for _, list in ipairs({ def:getRooms(), def:getEmptyOutside() }) do
        for i = 0, list:size() - 1 do
            table.insert(all, list:get(i))
        end
    end
    for _, room in ipairs(all) do
        local z = room:getZ()
        l.minZ = math.min(l.minZ or z, z)
        l.topZ = math.max(l.topZ or z, z)
    end
    l.groundZ = math.max(0, math.min(l.minZ or 0, clickZ or 0))
    l.topZ = l.topZ or l.groundZ
    for _, room in ipairs(all) do
        local z = room:getZ()
        local rects = room:getRects()
        for i = 0, rects:size() - 1 do
            local r = rects:get(i)
            for x = r:getX(), r:getX() + r:getW() - 1 do
                for y = r:getY(), r:getY() + r:getH() - 1 do
                    l.roomSet[key3(x, y, z)] = true
                    if not l.covered[key(x, y)] then
                        l.covered[key(x, y)] = true
                        l.count = l.count + 1
                    end
                    l.x1, l.y1 = math.min(l.x1 or x, x), math.min(l.y1 or y, y)
                    l.x2, l.y2 = math.max(l.x2 or x, x), math.max(l.y2 or y, y)
                end
            end
        end
        if z == l.groundZ then l.groundRooms = true end
    end
    local real = def:getRooms()
    for i = 0, real:size() - 1 do
        local room = real:get(i)
        if room:getZ() == l.groundZ then
            table.insert(l.rooms, { name = room:getName(), area = room:getArea() })
        end
    end
    return l
end

-- The blueprint id a building gets, to tell whether it is known already.
function CSB.Capture.buildingId(def, clickZ)
    local l = CSB.Capture.layout(def, clickZ)
    return (l.x1 or 0) .. "_" .. (l.y1 or 0)
end

-- How many columns the building covers, for the study time.
function CSB.Capture.area(def, clickZ)
    return CSB.Capture.layout(def, clickZ).count
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

-- Whether another building than `ownId` has a room on the column, on any
-- level from z1 to z2. Roof squares are not part of any building, so a
-- neighbour's roof is known by the building under it.
local function otherBuildingAt(x, y, z1, z2, ownId)
    for z = z1, z2 do
        local def = defAt(x, y, z)
        if def and (ownId == nil or def:getID() ~= ownId) then return true end
    end
    return false
end

--[[
    Goes over the squares from (x1, y1) to (x2, y2), margin included, on the
    levels groundZ to topZ, and keeps the pieces that belong (CSB.belongs
    with ctx; ctx.foreign is filled in per column here). Returns the tiles
    in world coordinates. What it leaves behind on or next to covered
    columns goes to CSB.Capture.lastSkipped, for the report.
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
                        foreignSet[k] = otherBuildingAt(x, y, groundZ, topZ, ownId)
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
                        if not kept and CSB.near(x, y, 1, ctx.covered) and obj:getSprite()
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

-- Studies a building from level clickZ (see layout). Returns the blueprint,
-- or nil and why not ("notLoaded", "empty").
function CSB.Capture.study(def, clickZ)
    CSB.Capture.lastSkipped = {}
    if not def:isFullyStreamedIn() then return nil, "notLoaded" end
    local l = CSB.Capture.layout(def, clickZ)
    if not l.x1 then return nil, "empty" end
    local ctx = {
        room = function(x, y, z) return l.roomSet[key3(x, y, z)] == true end,
        covered = function(x, y) return l.covered[key(x, y)] == true end,
        groundZ = l.groundZ,
        -- nothing of it on the ground (a carport's room is up at its roof):
        -- the floor under it is copied like a structure's
        groundFloors = not l.groundRooms,
    }
    local tiles = scan(l.x1, l.y1, l.x2, l.y2, l.groundZ, l.topZ + CSB.ROOF_LEVELS, ctx, def:getID())
    local name = #l.rooms > 0 and CSB.buildingName(l.rooms) or CSB.STRUCTURE_NAME
    return blueprint(tiles, l.groundZ, l.x1 .. "_" .. l.y1, name, l.count)
end

-- The square and the 8 around it, nearest first.
local NEAR = { { 0, 0 }, { 0, -1 }, { -1, 0 }, { 1, 0 }, { 0, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }

--[[
    The building the player clicked on, from the square the click landed on.
    The target is forgiving: it looks at
      * the square and the 8 around it, on every level up to CSB.ROOF_LEVELS
        above (a carport's room is up at its roof; a wall on the square's
        east or south edge belongs to the building next to it);
      * what is drawn at the click from the levels above (CSB.screenStack):
        an upper floor or a roof, and the squares around it.
    Returns the BuildingDef, or nil.
--]]
function CSB.Capture.buildingAt(sq)
    local cell = getCell()
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local lastZ = math.min(31, z + CSB.ROOF_LEVELS)
    local function columnDef(cx, cy)
        for lz = z, lastZ do
            local def = defAt(cx, cy, lz)
            if def then return def end
        end
        return nil
    end
    for _, p in ipairs(CSB.screenStack(x, y, z, CSB.ROOF_LEVELS)) do
        for _, d in ipairs(NEAR) do
            local cx, cy = p.x + d[1], p.y + d[2]
            local drawn = p.up == 0
            if not drawn then
                local above = cell:getGridSquare(cx, cy, p.z)
                drawn = above ~= nil and above:getObjects():size() > 0
            end
            if drawn then
                local def = columnDef(cx, cy)
                if def then return def end
            end
        end
    end
    return nil
end

--[[
    Finds the structure over a square: a roof right above it or above a
    square next to it, or drawn where the player clicked, followed to its
    edges (CSB.roofColumns). Returns
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

    -- Where to start: a roof straight over the square or a square next to
    -- it, or the roof drawn where the player clicked (CSB.screenStack), which
    -- has to be on the level drawn there.
    local sx, sy
    for _, p in ipairs(CSB.screenStack(sq:getX(), sq:getY(), groundZ, CSB.ROOF_LEVELS)) do
        for _, d in ipairs(NEAR) do
            local x, y = p.x + d[1], p.y + d[2]
            local level = roofAt(x, y)
            if level and (p.up == 0 or level == p.z) then
                sx, sy = x, y
                break
            end
        end
        if sx then break end
    end
    if not sx then return nil, "noRoof" end

    local columns, count = CSB.roofColumns(sx, sy,
        function(x, y) return roofAt(x, y) ~= nil end,
        function(x, y) return otherBuildingAt(x, y, groundZ, lastZ, nil) end)
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
    table.insert(lines, "Left behind on and next to the squares it covers (" .. #skipped .. "), world x, y, z:")
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
