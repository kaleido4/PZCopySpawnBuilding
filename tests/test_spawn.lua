dofile(ROOT .. "/tests/harness.lua")
dofile(MOD .. "shared/CopySpawnBuilding/CSB_Core.lua")
dofile(MOD .. "shared/CopySpawnBuilding/CSB_Spawn.lua")

print("CSB_Spawn")

defineSprite("grass", { "solidfloor" })
defineSprite("floor_wood", { "solidfloor" })
defineSprite("wall_w", { "WallW" })
defineSprite("wall_n", { "WallN" })
defineSprite("door_n", { "doorN" })
defineSprite("window_w", { "windowW" })
defineSprite("frame_w", { "WindowW" })
defineSprite("roof", { "BlockRain", RoofGroup = "1" })
defineSprite("trim", { "WallOverlay" })
defineSprite("bush", { "vegitation" })
defineSprite("tree", {})
defineSprite("fence", { "WallW" })

-- A 2 x 1 shed: two floors, a west wall with trim, an east wall with a
-- window, a door on the south side and a roof over it on level 1.
local SHED = {
    id = "shed", name = "Shed", w = 3, h = 2, levels = 2, area = 2,
    tiles = {
        { x = 0, y = 0, z = 0, s = "floor_wood", k = "floor" },
        { x = 1, y = 0, z = 0, s = "floor_wood", k = "floor" },
        { x = 0, y = 0, z = 0, s = "wall_w", k = "wall", a = { "trim" } },
        { x = 2, y = 0, z = 0, s = "frame_w", k = "frame" },
        { x = 2, y = 0, z = 0, s = "window_w", k = "window" },
        { x = 0, y = 1, z = 0, s = "door_n", k = "door" },
        { x = 1, y = 1, z = 0, s = "wall_n", k = "wall" },
        { x = 0, y = 0, z = 1, s = "roof", k = "roof" },
        { x = 1, y = 0, z = 1, s = "roof", k = "roof" },
    },
}

local function field()
    resetWorld()
    for x = 0, 9 do
        for y = 0, 9 do
            put(x, y, 0, "grass")
        end
    end
end

local function objectAt(x, y, z, s)
    for _, o in ipairs(square(x, y, z).objects) do
        if o.sprite.name == s then return o end
    end
    return nil
end

test("a copy fits on open grass", function()
    field()
    eq(CSB.Spawn.problem(SHED, 4, 4, 0), nil)
end)

test("a copy does not fit over a building, water or a vehicle", function()
    field()
    square(5, 4, 0).room = true
    eq((CSB.Spawn.problem(SHED, 4, 4, 0)), "building", "building")
    field()
    square(5, 5, 0).water = true
    local problem, x, y = CSB.Spawn.problem(SHED, 4, 4, 0)
    eq(problem, "water", "water") eq(x, 5) eq(y, 5)
    field()
    square(6, 5, 0).vehicle = true
    eq(CSB.Spawn.problem(SHED, 4, 4, 0), nil, "vehicle next to the copy, not under it")
    field()
    square(4, 4, 1).room = true
    eq((CSB.Spawn.problem(SHED, 4, 4, 0)), "building", "a room upstairs")
end)

defineSprite("crate", {})

test("fences, furniture and things upstairs do not stop a copy", function()
    field()
    put(5, 5, 0, "fence")
    put(4, 4, 0, "crate", { container = true })
    put(4, 4, 1, "floor_wood")
    eq(CSB.Spawn.problem(SHED, 4, 4, 0), nil)
end)

test("building a copy clears its squares: fences, furniture, containers, upstairs", function()
    field()
    put(5, 5, 0, "fence")
    put(4, 4, 0, "crate", { container = true })
    put(4, 4, 1, "floor_wood")
    put(7, 7, 0, "fence")
    CSB.Spawn.place(SHED, 4, 4, 0)
    eq(spritesAt(5, 5, 0), "grass wall_n", "fence gone")
    eq(spritesAt(4, 4, 0), "floor_wood wall_w", "crate gone")
    eq(spritesAt(4, 4, 1), "roof", "what was upstairs gone")
    eq(spritesAt(7, 7, 0), "grass fence", "a fence outside the copy stays")
end)

test("plants and trees in the way do not stop a copy", function()
    field()
    put(6, 4, 0, "bush")
    put(6, 4, 0, "tree", { class = "IsoTree" })
    eq(CSB.Spawn.problem(SHED, 4, 4, 0), nil)
end)

test("building a copy puts every piece in place", function()
    field()
    CSB.Spawn.place(SHED, 4, 4, 0)
    eq(spritesAt(4, 4, 0), "floor_wood wall_w", "west square")
    eq(spritesAt(5, 4, 0), "floor_wood", "middle square")
    eq(spritesAt(6, 4, 0), "grass frame_w window_w", "east wall stands on the grass")
    eq(spritesAt(4, 5, 0), "grass door_n", "door")
    eq(spritesAt(4, 4, 1), "roof", "roof upstairs")
end)

test("doors, windows and frames are made as the right objects, facing the right way", function()
    field()
    CSB.Spawn.place(SHED, 4, 4, 0)
    local door = objectAt(4, 5, 0, "door_n")
    eq(door.class, "IsoDoor") eq(door.north, true, "door faces north")
    local window = objectAt(6, 4, 0, "window_w")
    eq(window.class, "IsoWindow") eq(window.north, false, "window faces west") eq(window.locked, false, "unlocked")
    eq(objectAt(6, 4, 0, "frame_w").class, "IsoWindowFrame")
    eq(objectAt(4, 4, 0, "wall_w").class, "IsoObject", "walls are map walls")
end)

test("trim goes back on its wall", function()
    field()
    CSB.Spawn.place(SHED, 4, 4, 0)
    local wall = objectAt(4, 4, 0, "wall_w")
    eq(#wall.attached, 1)
    eq(wall.attached[1]:getParentSprite():getName(), "trim")
end)

test("plants and trees on the copy's squares are cleared", function()
    field()
    put(6, 4, 0, "bush")
    put(6, 4, 0, "tree", { class = "IsoTree" })
    CSB.Spawn.place(SHED, 4, 4, 0)
    eq(objectAt(6, 4, 0, "bush"), nil, "bush")
    eq(objectAt(6, 4, 0, "tree"), nil, "tree")
end)

defineSprite("hammer", {})

test("items on the ground do not stop a copy and are removed when it is built", function()
    field()
    local onGround = put(5, 4, 0, "hammer", { class = "IsoWorldInventoryObject" })
    local upstairs = put(4, 4, 1, "hammer", { class = "IsoWorldInventoryObject" })
    local nextDoor = put(8, 8, 0, "hammer", { class = "IsoWorldInventoryObject" })
    eq(CSB.Spawn.problem(SHED, 4, 4, 0), nil, "items are not in the way")
    CSB.Spawn.place(SHED, 4, 4, 0)
    eq(objectAt(5, 4, 0, "hammer"), nil, "item on the ground")
    eq(objectAt(4, 4, 1, "hammer"), nil, "item upstairs")
    eq(onGround.item.worldItem, nil, "the inventory item lets go of it")
    eq(upstairs.item.worldItem, nil)
    truthy(objectAt(8, 8, 0, "hammer"), "item outside the copy stays")
    eq(nextDoor.item.worldItem, nextDoor)
end)

test("the survey marks the footprint squares that have something to clear", function()
    field()
    put(4, 4, 0, "bush")
    put(6, 4, 0, "hammer", { class = "IsoWorldInventoryObject" })
    local survey = CSB.Spawn.survey(SHED, 4, 4, 0)
    eq(survey.problem, nil)
    -- footprint columns in order: (0,0) (1,0) (2,0) (0,1) (1,1)
    truthy(survey.cluttered[1], "bush at 4,4")
    falsy(survey.cluttered[2], "bare grass at 5,4")
    truthy(survey.cluttered[3], "item at 6,4")
    falsy(survey.cluttered[4], "bare grass at 4,5")
end)

test("the survey shows the square in the way and still marks clutter", function()
    field()
    square(5, 5, 0).water = true
    put(4, 4, 0, "bush")
    put(5, 4, 0, "fence")
    local survey = CSB.Spawn.survey(SHED, 4, 4, 0)
    eq(survey.problem, "water")
    eq(survey.px, 5) eq(survey.py, 5) eq(survey.pz, 0)
    truthy(survey.cluttered[1], "bush still marked")
    truthy(survey.cluttered[2], "fence marked")
end)

test("the squares under the copy's roof count as roofed right away", function()
    field()
    CSB.Spawn.place(SHED, 4, 4, 0)
    truthy(square(4, 4, 0).haveRoof, "under the roof")
    truthy(square(5, 4, 0).haveRoof, "under the roof")
    falsy(square(6, 4, 0).haveRoof, "east wall, no roof over it")
    falsy(square(4, 5, 0).haveRoof, "door, no roof over it")
end)

test("animal zones are told about the copy's roof", function()
    field()
    CSB.Spawn.place(SHED, 4, 4, 0)
    eq(newRoofs(), "4,4,1 5,4,1")
end)

test("after undo the squares are not roofed anymore", function()
    field()
    local record = CSB.Spawn.place(SHED, 4, 4, 0)
    CSB.Spawn.undo(record)
    falsy(square(4, 4, 0).haveRoof)
    falsy(square(5, 4, 0).haveRoof)
end)

test("undo takes the copy down and puts the grass back", function()
    field()
    local record = CSB.Spawn.place(SHED, 4, 4, 0)
    eq(record.ground["4,4"], "grass")
    CSB.Spawn.undo(record)
    eq(spritesAt(4, 4, 0), "grass", "west square")
    eq(spritesAt(5, 4, 0), "grass", "middle square")
    eq(spritesAt(6, 4, 0), "grass", "east square")
    eq(spritesAt(4, 5, 0), "grass", "door square")
    eq(spritesAt(4, 4, 1), "", "roof square")
end)

finish("CSB_Spawn")
