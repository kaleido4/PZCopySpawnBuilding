--[[
    Copy Spawn Building - the placement cursor: the copy's footprint is
    highlighted on the ground under the mouse and a see-through copy of the
    building stands on it; a click builds it.

    Footprint colors (the game's highlight colors, so they follow the
    colorblind option):
        good color   the copy fits
        bad color    it does not; the square in the way is drawn stronger
        yellow       plants, trees or items there will be removed

    It is a build cursor like the game's own (ISBuildingObject, driven by
    DoTileBuilding each frame), so it lives in server/ next to it: client
    files load before server files. The game asks the cursor for one sprite
    and draws it; here render draws the footprint and every tile instead.
    Tiles above the ground are drawn fainter so the footprint shows through.
--]]

require "BuildingObjects/ISBuildingObject"
require "CopySpawnBuilding/CSB_Spawn"

CSB_Cursor = ISBuildingObject:derive("CSB_Cursor")

local RECHECK_MS = 300
local CLUTTER = { r = 1, g = 0.8, b = 0.2 }

-- The survey of the squares under the copy (CSB.Spawn.survey), redone when
-- the mouse moves to another square or every RECHECK_MS.
function CSB_Cursor:survey(square)
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local now = getTimestampMs()
    if not self.surveyed or x ~= self.checkedX or y ~= self.checkedY or z ~= self.checkedZ or now - self.checkedAt >= RECHECK_MS then
        local ox, oy = CSB.origin(self.bp, x, y)
        self.surveyed = CSB.Spawn.survey(self.bp, ox, oy, z)
        self.checkedX, self.checkedY, self.checkedZ, self.checkedAt = x, y, z, now
    end
    return self.surveyed
end

function CSB_Cursor:isValid(square)
    if not square then return false end
    return self:survey(square).problem == nil
end

function CSB_Cursor:renderFootprint(ox, oy, z, survey)
    local floor = self:getFloorCursorSprite()
    local good = getCore():getGoodHighlitedColor()
    local bad = getCore():getBadHighlitedColor()
    local base = survey.problem and bad or good
    for i, c in ipairs(CSB.Spawn.footprint(self.bp).columns) do
        if survey.cluttered[i] then
            floor:RenderGhostTileColor(ox + c.x, oy + c.y, z, CLUTTER.r, CLUTTER.g, CLUTTER.b, 0.5)
        else
            floor:RenderGhostTileColor(ox + c.x, oy + c.y, z, base:getR(), base:getG(), base:getB(), 0.4)
        end
    end
    if survey.px then
        floor:RenderGhostTileColor(survey.px, survey.py, survey.pz, bad:getR(), bad:getG(), bad:getB(), 1)
    end
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
    local survey = self:survey(square)
    local ox, oy = CSB.origin(self.bp, x, y)
    self:renderFootprint(ox, oy, z, survey)

    local r, g, b = 0.6, 1, 0.6
    if survey.problem then
        r, g, b = 1, 0.35, 0.35
    end
    for _, t in ipairs(self.bp.tiles) do
        local tx, ty, tz = ox + t.x, oy + t.y, z + t.z
        local a = t.z == 0 and 0.55 or 0.3
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
