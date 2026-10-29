--[[
    Copy Spawn Building - studying a building: reads its pieces from the world
    into a blueprint (rules in CSB_Core.lua).

    The whole building has to be loaded (BuildingDef:isFullyStreamedIn), or
    part of it would be missing from the copy. Basements are left out for now:
    a copy is built on the ground, from level 0 up.
--]]

require "CopySpawnBuilding/CSB_Core"

CSB.Capture = {}

local function key(x, y)
    return x * 100000 + y
end

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

-- Returns the blueprint, or nil and why not ("notLoaded", "empty").
function CSB.Capture.study(def)
    if not def:isFullyStreamedIn() then return nil, "notLoaded" end
    local cell = getCell()
    local x1, y1, x2, y2 = def:getX(), def:getY(), def:getX2(), def:getY2()
    local groundZ = CSB.Capture.groundZ(def)
    local topZ = def:getMaxLevel()
    local defId = def:getID()

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
    local function covered(x, y) return coveredSet[key(x, y)] == true end
    local function room(x, y, z) return def:containsXYZ(x, y, z) end

    -- Columns where another building stands. Roof squares are not part of
    -- any building, so a neighbour's roof is known by the building under it.
    local foreignSet = {}
    local function foreign(x, y)
        local k = key(x, y)
        if foreignSet[k] == nil then
            foreignSet[k] = false
            for z = groundZ, topZ do
                local sq = cell:getGridSquare(x, y, z)
                local building = sq and sq:getBuilding()
                local other = building and building:getDef()
                if other and other:getID() ~= defId then
                    foreignSet[k] = true
                    break
                end
            end
        end
        return foreignSet[k]
    end

    local tiles = {}
    local m = CSB.MARGIN
    for z = groundZ, math.min(31, topZ + CSB.ROOF_LEVELS) do
        for y = y1 - m, y2 + m do
            for x = x1 - m, x2 + m do
                local sq = cell:getGridSquare(x, y, z)
                if sq then
                    local isForeign = foreign(x, y)
                    local objects = sq:getObjects()
                    for i = 0, objects:size() - 1 do
                        local obj = objects:get(i)
                        local kind = CSB.classify(obj)
                        if kind then
                            local sprite = obj:getSprite()
                            if CSB.belongs(kind, CSB.edges(sprite:getProperties()), x, y, z, room, covered, isForeign) then
                                table.insert(tiles, { x = x, y = y, z = z, s = sprite:getName(), k = kind, a = attachedNames(obj) })
                            end
                        end
                    end
                end
            end
        end
    end
    if #tiles == 0 then return nil, "empty" end

    local w, h, levels = CSB.normalize(tiles, groundZ)
    local groundRooms = rooms(def, groundZ)
    local area = 0
    for _, r in ipairs(groundRooms) do area = area + r.area end
    return {
        id = x1 .. "_" .. y1,
        name = CSB.buildingName(groundRooms),
        w = w, h = h, levels = levels,
        area = area,
        tiles = tiles,
    }
end
