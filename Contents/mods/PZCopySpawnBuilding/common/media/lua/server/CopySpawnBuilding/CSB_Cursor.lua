--[[
    Copy Spawn Building - the placement cursor: a see-through copy of the
    building follows the mouse, green where it can be built and red where it
    cannot; a click builds it.

    It is a build cursor like the game's own (ISBuildingObject, driven by
    DoTileBuilding each frame), so it lives in server/ next to it: client
    files load before server files. The game asks the cursor for one sprite
    and draws it; here render draws every tile of the blueprint instead.
--]]

require "BuildingObjects/ISBuildingObject"
require "CopySpawnBuilding/CSB_Spawn"

CSB_Cursor = ISBuildingObject:derive("CSB_Cursor")

local RECHECK_MS = 300

function CSB_Cursor:isValid(square)
    if not square then return false end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local now = getTimestampMs()
    if x == self.checkedX and y == self.checkedY and z == self.checkedZ and now - self.checkedAt < RECHECK_MS then
        return self.problem == nil
    end
    local ox, oy = CSB.origin(self.bp, x, y)
    self.problem = CSB.Spawn.problem(self.bp, ox, oy, z)
    self.checkedX, self.checkedY, self.checkedZ, self.checkedAt = x, y, z, now
    return self.problem == nil
end

function CSB_Cursor:ghost(name)
    local sprite = self.ghosts[name]
    if not sprite then
        sprite = IsoSprite.new()
        sprite:LoadSingleTexture(name)
        self.ghosts[name] = sprite
    end
    return sprite
end

function CSB_Cursor:render(x, y, z, square)
    local r, g, b, a = 0.6, 1, 0.6, 0.55
    if not self:isValid(square) then
        r, g, b, a = 1, 0.35, 0.35, 0.55
    end
    local ox, oy = CSB.origin(self.bp, x, y)
    for _, t in ipairs(self.bp.tiles) do
        local tx, ty, tz = ox + t.x, oy + t.y, z + t.z
        self:ghost(t.s):RenderGhostTileColor(tx, ty, tz, r, g, b, a)
        if t.a then
            for _, name in ipairs(t.a) do
                self:ghost(name):RenderGhostTileColor(tx, ty, tz, r, g, b, a)
            end
        end
    end
end

function CSB_Cursor:create(x, y, z, north, sprite)
    local ox, oy = CSB.origin(self.bp, x, y)
    if CSB.Spawn.problem(self.bp, ox, oy, z) then return end
    CSB.lastSpawn = CSB.Spawn.place(self.bp, ox, oy, z)
    self.character:setHaloNote(getText("IGUI_CSB_Built", self.bp.name))
end

function CSB_Cursor:new(character, bp)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o:init()
    -- DoTileBuilding asks for a sprite name; the copy itself is drawn in render
    o:setSprite(bp.tiles[1].s)
    o:setNorthSprite(bp.tiles[1].s)
    o.character = character
    o.player = character:getPlayerNum()
    o.bp = bp
    o.ghosts = {}
    o.checkedAt = 0
    o.skipBuildAction = true
    o.skipWalk2 = true
    o.noNeedHammer = true
    o.dragNilAfterPlace = true
    return o
end
