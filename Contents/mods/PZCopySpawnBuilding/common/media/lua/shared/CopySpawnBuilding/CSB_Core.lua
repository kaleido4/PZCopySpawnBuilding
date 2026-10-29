--[[
    Copy Spawn Building - blueprint rules (no world access, unit-tested).

    Map buildings are not stored as buildings. The map is baked into a list of
    tiles per square, and a BuildingDef only knows the building's rooms: their
    rectangles, level and name (B42.22). So studying a building means going
    over the squares around it and keeping the pieces its structure is made
    of: floors, walls, door frames, doors, windows, window frames, stairs,
    roofs and wall overlays (trim). Furniture, containers, items, plants and
    blood stay behind.

    Which pieces belong to the building:
      * everything structural on one of its room squares;
      * anything structural on a square the building covers on some level,
        seen from above (gable walls and attic pieces sit on the level above
        the top room);
      * walls, doors and windows sit on a square's west or north edge, so the
        building's east and south walls are on the squares just outside it:
        an edge piece belongs when the square across its edge is covered;
      * roofs hang over the walls: a roof piece belongs within 2 squares of
        the building;
      * floors outside the rooms count only above the ground and over the
        building (flat roofs, balconies), not porches or sidewalks.
    Over another building (a square of it, or the roof above it), pieces only
    count through their edge, so a neighbour's roof is not copied.

    Blueprint layout (kept in global mod data, see CSB_Store.lua):
        id        "x_y" of the building's north-west corner where it was studied
        name      shown in menus ("Barn", "House")
        w, h      size of the box the tiles fit in
        levels    levels the tiles use, roof included
        area      floor squares of the ground level rooms
        tiles     list of { x, y, z, s = sprite, k = kind, a = { attached sprites } }
                  x, y from the box's north-west corner, z from the ground
--]]

CSB = CSB or {}

CSB.MARGIN = 2          -- squares searched around the building (roofs hang over)
CSB.ROOF_LEVELS = 3     -- levels searched above the top room for the roof

-- Sprites never copied: blood, plants and grass.
CSB.SKIP_PREFIXES = { "overlay_blood", "e_", "f_", "d_", "vegetation_", "blends_grassoverlays", "jumbo_" }

-- Rooms that make a building a house, whatever its biggest room is.
CSB.HOUSE_ROOMS = { kitchen = true, bedroom = true, livingroom = true, bathroom = true }

function CSB.skipSprite(name)
    if not name or name == "" then return true end
    for _, prefix in ipairs(CSB.SKIP_PREFIXES) do
        if string.sub(name, 1, #prefix) == prefix then return true end
    end
    return false
end

local function hasAny(props, flags)
    for _, flag in ipairs(flags) do
        if flag ~= nil and props:has(flag) then return true end
    end
    return false
end

-- What part of a building the object is: "floor", "wall", "door", "window",
-- "frame" (window frame), "stairs", "roof", "overlay", or nil when it is not
-- part of the structure.
function CSB.classify(obj)
    if instanceof(obj, "IsoWorldInventoryObject") or instanceof(obj, "IsoTree") then return nil end
    local sprite = obj:getSprite()
    local name = sprite and sprite:getName()
    if CSB.skipSprite(name) then return nil end
    if obj:getContainer() then return nil end
    local props = sprite:getProperties()
    local F = IsoFlagType
    if props:has(F.vegitation) then return nil end
    if instanceof(obj, "IsoDoor") or props:has(F.doorN) or props:has(F.doorW) then return "door" end
    if instanceof(obj, "IsoWindow") or props:has(F.windowN) or props:has(F.windowW) then return "window" end
    if instanceof(obj, "IsoWindowFrame") or props:has(F.WindowN) or props:has(F.WindowW) then return "frame" end
    if obj:isStairsObject() then return "stairs" end
    -- before roofs: a flat roof you can walk on is the floor of its square
    if obj:isFloor() or props:has(F.solidfloor) then return "floor" end
    if props:has("RoofGroup") or props:has(F.isEave) then return "roof" end
    if obj:isWall() or obj:isWallSE()
        or hasAny(props, { F.WallN, F.WallW, F.WallNW, F.WallSE, F.DoorWallN, F.DoorWallW, F.WallNTrans, F.WallWTrans }) then
        return "wall"
    end
    if props:has(F.WallOverlay) then return "overlay" end
    return nil
end

-- Which square edges the piece sits on.
function CSB.edges(props)
    local F = IsoFlagType
    return {
        W = hasAny(props, { F.WallW, F.WallNW, F.DoorWallW, F.WallWTrans, F.doorW, F.windowW, F.WindowW, F.attachedW }),
        N = hasAny(props, { F.WallN, F.WallNW, F.DoorWallN, F.WallNTrans, F.doorN, F.windowN, F.WindowN, F.attachedN }),
        corner = hasAny(props, { F.WallSE, F.attachedSE }),
    }
end

-- Whether some square within d of (x, y) is covered by the building.
function CSB.near(x, y, d, covered)
    for dx = -d, d do
        for dy = -d, d do
            if covered(x + dx, y + dy) then return true end
        end
    end
    return false
end

-- Whether a piece found on square (x, y, z) belongs to the building.
--   room(x, y, z)   the square is one of the building's rooms
--   covered(x, y)   some level of the building has a room there
--   foreign         the square is part of another building
function CSB.belongs(kind, edges, x, y, z, room, covered, foreign)
    if room(x, y, z) then return true end
    if not foreign then
        if kind == "roof" then return CSB.near(x, y, CSB.MARGIN, covered) end
        if kind == "floor" then return z > 0 and covered(x, y) end
        if covered(x, y) then return true end
        if kind == "stairs" then return CSB.near(x, y, 1, covered) end
    end
    if edges.W and covered(x - 1, y) then return true end
    if edges.N and covered(x, y - 1) then return true end
    if edges.corner and covered(x - 1, y - 1) then return true end
    return false
end

-- Moves the tiles so the box they fit in starts at 0, 0 and the ground is
-- z 0. Returns the box size and the number of levels.
function CSB.normalize(tiles, groundZ)
    if #tiles == 0 then return 0, 0, 0 end
    local first = tiles[1]
    local minX, minY, maxX, maxY, maxZ = first.x, first.y, first.x, first.y, first.z
    for _, t in ipairs(tiles) do
        minX, minY = math.min(minX, t.x), math.min(minY, t.y)
        maxX, maxY = math.max(maxX, t.x), math.max(maxY, t.y)
        maxZ = math.max(maxZ, t.z)
    end
    for _, t in ipairs(tiles) do
        t.x, t.y, t.z = t.x - minX, t.y - minY, t.z - groundZ
    end
    return maxX - minX + 1, maxY - minY + 1, maxZ - groundZ + 1
end

local function prettyRoomName(name)
    local text = string.gsub(name or "", "_", " ")
    if text == "" then return "Building" end
    return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
end

-- A name for the building from its rooms: { { name, area }, ... }.
function CSB.buildingName(rooms)
    local biggest, biggestArea = nil, -1
    for _, room in ipairs(rooms) do
        if CSB.HOUSE_ROOMS[room.name] then return "House" end
        if room.area > biggestArea then
            biggest, biggestArea = room.name, room.area
        end
    end
    return prettyRoomName(biggest)
end

-- How long studying takes, in action ticks, from the ground floor area.
function CSB.studyTime(area)
    return math.min(2000, 200 + (area or 0) * 6)
end

-- Where the copy's box starts when the cursor is on square (x, y): the box
-- is centered on the cursor.
function CSB.origin(bp, x, y)
    return x - math.floor(bp.w / 2), y - math.floor(bp.h / 2)
end

-- Columns and squares the copy uses, worked out once per blueprint:
--   columns[i] = { x, y }       every column with a tile, any level
--   upper[i]   = { x, y, z }    squares with a tile above the ground
function CSB.footprint(bp)
    local columns, upper, seen = {}, {}, {}
    for _, t in ipairs(bp.tiles) do
        local column = t.x .. "," .. t.y
        if not seen[column] then
            seen[column] = true
            table.insert(columns, { x = t.x, y = t.y })
        end
        local square = column .. "," .. t.z
        if t.z > 0 and not seen[square] then
            seen[square] = true
            table.insert(upper, { x = t.x, y = t.y, z = t.z })
        end
    end
    return { columns = columns, upper = upper }
end

-- Plants and trees are cleared to make room for a copy.
function CSB.clearable(obj)
    if instanceof(obj, "IsoTree") then return true end
    local sprite = obj:getSprite()
    local props = sprite and sprite:getProperties()
    return props ~= nil and props:has(IsoFlagType.vegitation)
end

-- Whether the object is in the way of a copy (items on the ground just stay).
function CSB.blocks(obj)
    if instanceof(obj, "IsoWorldInventoryObject") then return false end
    return not CSB.clearable(obj)
end

-- Why a copy cannot stand on this ground square, or nil when it can.
function CSB.groundProblem(sq)
    if not sq then return "unloaded" end
    if sq:getBuilding() or sq:isInARoom() then return "building" end
    if sq:isWaterSquare() then return "water" end
    local floor = sq:getFloor()
    if not floor then return "noGround" end
    if sq:isVehicleIntersecting() then return "vehicle" end
    local objects = sq:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if obj ~= floor and CSB.blocks(obj) then return "blocked" end
    end
    return nil
end

-- Why a copy cannot use this square above the ground, or nil when it can.
-- A square that does not exist yet is free.
function CSB.upperProblem(sq)
    if not sq then return nil end
    if sq:getBuilding() then return "building" end
    local objects = sq:getObjects()
    for i = 0, objects:size() - 1 do
        if CSB.blocks(objects:get(i)) then return "blocked" end
    end
    return nil
end
