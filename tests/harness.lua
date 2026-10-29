--[[
    Test harness: assertions and a small mock world built the way the game
    (B42.22) is where the mod relies on it:
      * tile flags and properties are read from a sprite's PropertyContainer
        with has(IsoFlagType.X) or has("PropertyName");
      * walls, doors and windows sit on a square's west or north edge;
      * a square's object list keeps its order, the floor first;
      * addFloor replaces the square's floor and clears plants and trees;
      * a BuildingDef knows its rooms as rectangles on one level each.
--]]

MOD = ROOT .. "/Contents/mods/PZCopySpawnBuilding/common/media/lua/"

local passed, failed = 0, 0

function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print("  ok   " .. name)
    else
        failed = failed + 1
        print("  FAIL " .. name .. ": " .. tostring(err))
    end
end

function finish(suite)
    print(suite .. ": " .. passed .. " passed, " .. failed .. " failed")
    if failed > 0 then error(suite .. ": " .. failed .. " test(s) failed") end
end

function eq(actual, expected, what)
    if actual ~= expected then
        error((what or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

function truthy(v, what)
    if not v then error((what or "value") .. ": expected true, got " .. tostring(v)) end
end

function falsy(v, what)
    if v then error((what or "value") .. ": expected false, got " .. tostring(v)) end
end

function javaList(t)
    return {
        size = function() return #t end,
        get = function(_, i) return t[i + 1] end,
    }
end

-- Mod files use require for each other; the tests load them in order instead.
function require() end

---------------------------------------------------------------------------
-- Sprites
---------------------------------------------------------------------------

-- Flags and properties are both plain strings here.
IsoFlagType = setmetatable({}, { __index = function(_, k) return k end })

local sprites = {}

-- defineSprite(name, { "WallW", "solidfloor", RoofGroup = "1", ... })
function defineSprite(name, props)
    local set = {}
    for k, v in pairs(props or {}) do
        if type(k) == "number" then set[v] = true else set[k] = true end
    end
    local sprite = { name = name, props = { set = set } }
    function sprite.props:has(flag) return self.set[flag] == true end
    function sprite:getName() return self.name end
    function sprite:getProperties() return self.props end
    sprites[name] = sprite
    return sprite
end

function getSprite(name)
    return sprites[name]
end

---------------------------------------------------------------------------
-- Objects
---------------------------------------------------------------------------

local SUBCLASSES = {
    IsoDoor = { IsoObject = true }, IsoWindow = { IsoObject = true }, IsoWindowFrame = { IsoObject = true },
    IsoTree = { IsoObject = true }, IsoWorldInventoryObject = { IsoObject = true },
}

function instanceof(obj, class)
    if type(obj) ~= "table" or not obj.class then return false end
    if obj.class == class then return true end
    return SUBCLASSES[obj.class] ~= nil and SUBCLASSES[obj.class][class] == true
end

-- newObject(spriteName, { class = "IsoObject", container = true, stairs = true,
--                         attached = { "sprite", ... } })
function newObject(spriteName, opts)
    opts = opts or {}
    local obj = {
        class = opts.class or "IsoObject",
        sprite = sprites[spriteName] or defineSprite(spriteName),
        container = opts.container,
        stairs = opts.stairs,
        north = opts.north,
        attached = {},
    }
    for _, name in ipairs(opts.attached or {}) do
        table.insert(obj.attached, { getParentSprite = function() return sprites[name] or defineSprite(name) end })
    end
    function obj:getSprite() return self.sprite end
    function obj:getContainer() return self.container and {} or nil end
    function obj:isStairsObject() return self.stairs == true end
    function obj:isFloor() return self.sprite.props:has("solidfloor") end
    function obj:isWall() return false end
    function obj:isWallSE() return false end
    function obj:getAttachedAnimSprite() return javaList(self.attached) end
    function obj:AttachExistingAnim(sprite)
        table.insert(self.attached, { getParentSprite = function() return sprite end })
    end
    function obj:setIsLocked(locked) self.locked = locked end
    return obj
end

local function made(class, sq, spriteName, north)
    local obj = newObject(spriteName, { class = class, north = north })
    obj.square = sq
    return obj
end

IsoObject = { new = function(cell, sq, name) return made("IsoObject", sq, name) end }
IsoDoor = { new = function(cell, sq, name, north) return made("IsoDoor", sq, name, north) end }
IsoWindow = { new = function(cell, sq, sprite, north) return made("IsoWindow", sq, sprite:getName(), north) end }
IsoWindowFrame = { new = function(cell, sq, sprite, north) return made("IsoWindowFrame", sq, sprite:getName(), north) end }

---------------------------------------------------------------------------
-- World
---------------------------------------------------------------------------

local world

function resetWorld()
    world = { squares = {} }
end

local function squareKey(x, y, z) return x .. "," .. y .. "," .. z end

function newSquare(x, y, z)
    local sq = { x = x, y = y, z = z, objects = {}, recalcs = 0 }
    function sq:getX() return self.x end
    function sq:getY() return self.y end
    function sq:getZ() return self.z end
    function sq:getObjects() return javaList(self.objects) end
    function sq:getFloor()
        for _, o in ipairs(self.objects) do
            if o.sprite.props:has("solidfloor") then return o end
        end
        return nil
    end
    function sq:addFloor(name)
        for i = #self.objects, 1, -1 do
            local o = self.objects[i]
            if o.sprite.props:has("solidfloor") or o.sprite.props:has("vegitation") or o.class == "IsoTree" then
                table.remove(self.objects, i)
            end
        end
        local floor = made("IsoObject", self, name)
        table.insert(self.objects, 1, floor)
        return floor
    end
    function sq:AddSpecialObject(obj) table.insert(self.objects, obj) end
    function sq:RemoveTileObject(obj)
        for i, o in ipairs(self.objects) do
            if o == obj then table.remove(self.objects, i) return i end
        end
        return -1
    end
    function sq:getBuilding() return self.building end
    function sq:isInARoom() return self.room == true end
    function sq:isWaterSquare() return self.water == true end
    function sq:isVehicleIntersecting() return self.vehicle == true end
    function sq:RecalcProperties() self.recalcs = self.recalcs + 1 end
    function sq:RecalcAllWithNeighbours() end
    world.squares[squareKey(x, y, z)] = sq
    return sq
end

-- The square, made if it does not exist yet.
function square(x, y, z)
    return world.squares[squareKey(x, y, z)] or newSquare(x, y, z)
end

function put(x, y, z, spriteName, opts)
    local obj = newObject(spriteName, opts)
    obj.square = square(x, y, z)
    table.insert(obj.square.objects, obj)
    return obj
end

function spritesAt(x, y, z)
    local sq = world.squares[squareKey(x, y, z)]
    local names = {}
    if sq then
        for _, o in ipairs(sq.objects) do table.insert(names, o.sprite.name) end
    end
    return table.concat(names, " ")
end

local cell = {}
function cell:getGridSquare(x, y, z) return world.squares[squareKey(x, y, z)] end
function cell:createNewGridSquare(x, y, z) return newSquare(x, y, z) end
function getCell() return cell end

-- newBuildingDef(id, { { x, y, w, h, z, name }, ... })
function newBuildingDef(id, rooms)
    local def = { id = id, rooms = rooms, loaded = true }
    local x1, y1, x2, y2, minZ, maxZ
    for _, r in ipairs(rooms) do
        x1 = math.min(x1 or r.x, r.x)
        y1 = math.min(y1 or r.y, r.y)
        x2 = math.max(x2 or r.x + r.w, r.x + r.w)
        y2 = math.max(y2 or r.y + r.h, r.y + r.h)
        minZ = math.min(minZ or r.z, r.z)
        maxZ = math.max(maxZ or r.z, r.z)
    end
    function def:getX() return x1 end
    function def:getY() return y1 end
    function def:getX2() return x2 end
    function def:getY2() return y2 end
    function def:getMinLevel() return minZ end
    function def:getMaxLevel() return maxZ end
    function def:getID() return self.id end
    function def:isFullyStreamedIn() return self.loaded end
    function def:containsXYZ(x, y, z)
        for _, r in ipairs(self.rooms) do
            if z == r.z and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then return true end
        end
        return false
    end
    function def:getRooms()
        local list = {}
        for _, r in ipairs(self.rooms) do
            table.insert(list, {
                getZ = function() return r.z end,
                getName = function() return r.name end,
                getArea = function() return r.w * r.h end,
            })
        end
        return javaList(list)
    end
    -- the IsoBuilding the def's room squares point to
    def.building = { getDef = function() return def end }
    for _, r in ipairs(rooms) do
        for x = r.x, r.x + r.w - 1 do
            for y = r.y, r.y + r.h - 1 do
                local sq = square(x, y, r.z)
                sq.building = def.building
                sq.room = true
            end
        end
    end
    return def
end

resetWorld()
