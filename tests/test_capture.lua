dofile(ROOT .. "/tests/harness.lua")
dofile(MOD .. "shared/CopySpawnBuilding/CSB_Core.lua")
dofile(MOD .. "shared/CopySpawnBuilding/CSB_Capture.lua")

print("CSB_Capture")

defineSprite("grass", { "solidfloor" })
defineSprite("floor_wood", { "solidfloor" })
defineSprite("wall_w", { "WallW" })
defineSprite("wall_n", { "WallN" })
defineSprite("wall_nw", { "WallNW" })
defineSprite("wall_se", { "WallSE" })
defineSprite("door_n", { "doorN" })
defineSprite("window_w", { "windowW" })
defineSprite("frame_w", { "WindowW" })
defineSprite("roof", { RoofGroup = "1" })
defineSprite("fence_n", { "WallN" })
defineSprite("fence_w", { "WallW" })
defineSprite("trim", { "WallOverlay" })
defineSprite("crate", {})
defineSprite("tree", {})

--[[
    A 3 x 2 barn on x 10-12, y 20-21 (one room, ground level), seen from above:

        y19   roof eaves all around on level 1, one more at x 8
        y20   W|NW  N    N   |W east wall (x 13)
        y21   W     .    .   |W+window+frame
        y22   N     door N   SE corner post
             x10   x11  x12  x13

    Around it: grass, a tree, a fence on the east side and one further west,
    and a neighbour's building at x 14 with a roof of its own.
--]]
local function buildBarn()
    resetWorld()
    for x = 7, 16 do
        for y = 18, 24 do
            put(x, y, 0, "grass")
        end
    end
    local def = newBuildingDef(1, { { x = 10, y = 20, w = 3, h = 2, z = 0, name = "barn" } })
    for x = 10, 12 do
        for y = 20, 21 do
            square(x, y, 0).objects = {}
            put(x, y, 0, "floor_wood")
        end
    end
    put(10, 20, 0, "wall_nw", { attached = { "trim", "overlay_blood_wall_01_3" } })
    put(11, 20, 0, "wall_n") put(12, 20, 0, "wall_n")
    put(10, 21, 0, "wall_w")
    put(13, 20, 0, "wall_w") put(13, 21, 0, "frame_w") put(13, 21, 0, "window_w")
    put(10, 22, 0, "wall_n") put(11, 22, 0, "door_n") put(12, 22, 0, "wall_n")
    put(13, 22, 0, "wall_se")
    put(11, 21, 0, "crate", { container = true })
    put(9, 20, 0, "tree", { class = "IsoTree" })
    put(13, 21, 0, "fence_n")
    put(9, 21, 0, "fence_w")
    -- roof on level 1, hanging one square over, plus an eave 2 squares out
    for x = 9, 13 do
        for y = 19, 22 do
            put(x, y, 1, "roof")
        end
    end
    put(8, 20, 1, "roof")
    put(7, 20, 1, "roof")
    -- the neighbour, its roof reaching to x 14
    newBuildingDef(2, { { x = 14, y = 20, w = 2, h = 2, z = 0, name = "shed" } })
    put(14, 20, 1, "roof")
    return def
end

local function find(bp, x, y, z, s)
    for _, t in ipairs(bp.tiles) do
        if t.x == x and t.y == y and t.z == z and t.s == s then return t end
    end
    return nil
end

local function countSprite(bp, s)
    local n = 0
    for _, t in ipairs(bp.tiles) do
        if t.s == s then n = n + 1 end
    end
    return n
end

test("a building that is not fully loaded cannot be studied", function()
    local def = buildBarn()
    def.loaded = false
    local bp, why = CSB.Capture.study(def)
    eq(bp, nil) eq(why, "notLoaded")
end)

test("the blueprint gets the building's name, size and area", function()
    local bp = CSB.Capture.study(buildBarn())
    eq(bp.id, "10_20")
    eq(bp.name, "Barn")
    eq(bp.area, 6)
    -- the box runs from the eave at x 8 to the east wall at x 13, y 19 to 22
    eq(bp.w, 6, "w") eq(bp.h, 4, "h") eq(bp.levels, 2, "levels")
end)

test("floors, walls, the door, the window and its frame are copied", function()
    local bp = CSB.Capture.study(buildBarn())
    -- box origin is (8, 19): world x 10 is box x 2, world y 20 is box y 1
    eq(countSprite(bp, "floor_wood"), 6, "floors")
    truthy(find(bp, 2, 1, 0, "wall_nw"), "north-west corner")
    truthy(find(bp, 5, 1, 0, "wall_w"), "east wall")
    truthy(find(bp, 3, 3, 0, "door_n"), "door in the south wall")
    truthy(find(bp, 5, 3, 0, "wall_se"), "corner post")
    eq(find(bp, 5, 2, 0, "window_w").k, "window")
    eq(find(bp, 5, 2, 0, "frame_w").k, "frame")
end)

test("the roof is copied with its eaves, but not further out or the neighbour's", function()
    local bp = CSB.Capture.study(buildBarn())
    eq(countSprite(bp, "roof"), 21, "5 x 4 roof plus one eave")
    truthy(find(bp, 0, 1, 1, "roof"), "eave 2 squares out")
end)

test("trim stays attached to its wall, blood does not", function()
    local bp = CSB.Capture.study(buildBarn())
    local corner = find(bp, 2, 1, 0, "wall_nw")
    eq(#corner.a, 1, "attached sprites")
    eq(corner.a[1], "trim")
end)

test("grass, trees, containers and fences are left behind", function()
    local bp = CSB.Capture.study(buildBarn())
    eq(countSprite(bp, "grass"), 0, "grass")
    eq(countSprite(bp, "tree"), 0, "tree")
    eq(countSprite(bp, "crate"), 0, "crate")
    eq(countSprite(bp, "fence_n"), 0, "fence along the east wall")
    eq(countSprite(bp, "fence_w"), 0, "fence west of it")
end)

test("study time comes from the ground floor area", function()
    eq(CSB.Capture.area(buildBarn()), 6)
end)

test("a click on the building's floor or on its east wall finds it", function()
    local def = buildBarn()
    eq(CSB.Capture.buildingAt(square(11, 21, 0)), def, "floor")
    eq(CSB.Capture.buildingAt(square(13, 21, 0)), def, "east wall, on the square outside")
end)

test("a click on the building's roof as drawn on screen finds it", function()
    local def = buildBarn()
    -- the roof over 11,21 on level 1 is drawn over ground square 8,18
    eq(CSB.Capture.buildingAt(square(8, 18, 0)), def)
end)

test("a click on open ground finds no building", function()
    buildBarn()
    eq(CSB.Capture.buildingAt(square(15, 24, 0)), nil)
end)

---------------------------------------------------------------------------
-- Structures: a roof with no rooms under it
---------------------------------------------------------------------------

defineSprite("blends_natural_01_16", { "solidfloor" })
defineSprite("blends_street_01_80", { "solidfloor" })
defineSprite("post", { "WallSE" })

--[[
    A carport on a field: a 3 x 2 roof on level 1 over x 25-27, y 25-26, a
    post under each corner, and a concrete pad under the roof (one square of
    it is grass) that runs 2 squares out in front. A house stands at x 32-35,
    y 25-28, its roof hanging one square over on every side.
--]]
local function buildCarport()
    resetWorld()
    for x = 20, 40 do
        for y = 20, 40 do
            put(x, y, 0, "blends_natural_01_16")
        end
    end
    for x = 25, 27 do
        for y = 25, 28 do
            if not (x == 27 and y == 26) then
                square(x, y, 0).objects = {}
                put(x, y, 0, "blends_street_01_80")
            end
        end
        for y = 25, 26 do
            put(x, y, 1, "roof")
        end
    end
    for _, p in ipairs({ { 25, 25 }, { 27, 25 }, { 25, 26 }, { 27, 26 } }) do
        put(p[1], p[2], 0, "post")
    end
    put(24, 25, 0, "tree", { class = "IsoTree" })
    put(26, 26, 0, "crate", { container = true })

    newBuildingDef(3, { { x = 32, y = 25, w = 4, h = 4, z = 0, name = "kitchen" } })
    for x = 31, 36 do
        for y = 24, 29 do
            put(x, y, 1, "roof")
        end
    end
end

test("a carport is found by its roof", function()
    buildCarport()
    local found = CSB.Capture.findStructure(square(26, 26, 0))
    eq(found.id, "s_25_25")
    eq(found.count, 6, "roof columns")
    eq(found.topZ, 1)
end)

test("a roof next to the square clicked counts too", function()
    buildCarport()
    local found = CSB.Capture.findStructure(square(26, 27, 0))
    eq(found.id, "s_25_25")
end)

test("a click on the carport's roof as drawn on screen finds it", function()
    buildCarport()
    -- the roof over 26,26 on level 1 is drawn over ground square 23,23
    local found = CSB.Capture.findStructure(square(23, 23, 0))
    eq(found and found.id, "s_25_25")
    found = CSB.Capture.findStructure(square(22, 22, 0))
    eq(found and found.id, "s_25_25", "its north-west corner")
end)

test("a roof drawn at the click from another level does not count", function()
    buildCarport()
    -- 2 levels up from 20,20 is 26,26, but the carport roof there is on level 1
    local found, why = CSB.Capture.findStructure(square(20, 20, 0))
    eq(found, nil) eq(why, "noRoof")
end)

test("no roof, no structure", function()
    buildCarport()
    local found, why = CSB.Capture.findStructure(square(38, 38, 0))
    eq(found, nil) eq(why, "noRoof")
end)

test("a house's eave is not a structure", function()
    buildCarport()
    local found, why = CSB.Capture.findStructure(square(36, 26, 0))
    eq(found, nil) eq(why, "partOfBuilding")
end)

test("a roof past the size limit is too big", function()
    buildCarport()
    local max = CSB.MAX_ROOF
    CSB.MAX_ROOF = 4
    local found, why = CSB.Capture.findStructure(square(26, 26, 0))
    CSB.MAX_ROOF = max
    eq(found, nil) eq(why, "tooBig")
end)

test("studying a carport copies its roof, posts and the pad under the roof", function()
    buildCarport()
    local bp = CSB.Capture.studyStructure(square(26, 26, 0))
    eq(bp.id, "s_25_25")
    eq(bp.name, "Shelter")
    eq(bp.area, 6)
    eq(countSprite(bp, "roof"), 6, "roof")
    eq(countSprite(bp, "post"), 4, "posts")
    eq(countSprite(bp, "blends_street_01_80"), 5, "pad under the roof, not the part in front")
    eq(countSprite(bp, "blends_natural_01_16"), 0, "grass")
    eq(countSprite(bp, "tree"), 0, "tree")
    eq(countSprite(bp, "crate"), 0, "crate")
    eq(bp.w, 3, "w") eq(bp.h, 2, "h") eq(bp.levels, 2, "levels")
end)

---------------------------------------------------------------------------
-- A carport stored as a building whose only room is an emptyoutside room on
-- level 1, at its roof (the one on the map at 9101-9104, 9307-9310)
---------------------------------------------------------------------------

defineSprite("floor_porch", { "solidfloor" })
-- the real carport's tiles: its roof only blocks rain, its posts are railings
defineSprite("roofs_30_10_16", { "ForceAmbient", "BlockRain", SnowTile = "x" })
defineSprite("fixtures_railings_01_73", { "NeverCutaway", BlocksPlacement = "1" })

local function buildRoofRoomCarport()
    resetWorld()
    for x = 38, 55 do
        for y = 24, 40 do
            put(x, y, 0, "blends_natural_01_16")
        end
    end
    for x = 45, 48 do
        for y = 30, 35 do
            square(x, y, 0).objects = {}
            put(x, y, 0, "blends_street_01_80")
        end
        for y = 30, 33 do
            put(x, y, 1, "roofs_30_10_16")
        end
    end
    -- railing posts: on the west side under the roof, on the east side just
    -- outside it; a chair someone left there
    for _, p in ipairs({ { 45, 31 }, { 45, 33 }, { 49, 31 }, { 49, 33 } }) do
        put(p[1], p[2], 0, "fixtures_railings_01_73")
    end
    put(51, 31, 0, "fixtures_railings_01_73")
    defineSprite("lawn_chair", { IsMoveAble = "1" })
    put(46, 32, 0, "lawn_chair")
    return newBuildingDef(5, { { x = 45, y = 30, w = 4, h = 4, z = 1, name = "emptyoutside", outside = true } })
end

test("a carport whose room is up at its roof is found from the ground under it", function()
    local def = buildRoofRoomCarport()
    eq(CSB.Capture.buildingAt(square(46, 31, 0)), def, "under it")
    eq(CSB.Capture.buildingAt(square(44, 31, 0)), def, "next to it")
    -- the roof over 45,30 on level 1 is drawn over ground square 42,27
    eq(CSB.Capture.buildingAt(square(42, 27, 0)), def, "on its roof as drawn")
end)

test("its roof belongs to that building, so it is not a structure", function()
    buildRoofRoomCarport()
    local found, why = CSB.Capture.findStructure(square(46, 31, 0))
    eq(found, nil) eq(why, "partOfBuilding")
end)

test("studying it copies from the ground: roof, posts and the pad under the roof", function()
    local def = buildRoofRoomCarport()
    eq(CSB.Capture.layout(def, 0).groundZ, 0, "ground level")
    local bp = CSB.Capture.study(def, 0)
    eq(bp.id, "45_30")
    eq(bp.name, "Shelter")
    eq(bp.area, 16)
    eq(countSprite(bp, "roofs_30_10_16"), 16, "roof")
    eq(countSprite(bp, "fixtures_railings_01_73"), 4, "posts, both sides, not the one further out")
    eq(countSprite(bp, "blends_street_01_80"), 16, "pad under the roof, not the part in front")
    eq(countSprite(bp, "blends_natural_01_16"), 0, "grass")
    eq(countSprite(bp, "lawn_chair"), 0, "chair")
    eq(bp.w, 5, "w, the east posts included") eq(bp.h, 4, "h") eq(bp.levels, 2, "levels")
end)

---------------------------------------------------------------------------
-- An L-shaped house with a porch (an emptyoutside room on the ground)
---------------------------------------------------------------------------

--[[
    Rooms on level 0: kitchen x 60-62, y 20-21, bedroom x 60, y 22-23; the
    yard in the L's corner (x 61-62, y 22-23) is not part of it. A porch
    (emptyoutside) runs along the east side at x 63, y 20-21.
--]]
local function buildLHouse()
    resetWorld()
    for x = 56, 68 do
        for y = 16, 28 do
            put(x, y, 0, "blends_natural_01_16")
        end
    end
    local rooms = { { 60, 20 }, { 61, 20 }, { 62, 20 }, { 60, 21 }, { 61, 21 }, { 62, 21 }, { 60, 22 }, { 60, 23 } }
    for _, p in ipairs(rooms) do
        square(p[1], p[2], 0).objects = {}
        put(p[1], p[2], 0, "floor_wood")
    end
    for _, p in ipairs({ { 63, 20 }, { 63, 21 } }) do
        square(p[1], p[2], 0).objects = {}
        put(p[1], p[2], 0, "floor_porch")
    end
    put(64, 21, 0, "post")
    put(62, 23, 0, "fence_w")
    return newBuildingDef(6, {
        { x = 60, y = 20, w = 3, h = 2, z = 0, name = "kitchen" },
        { x = 60, y = 22, w = 1, h = 2, z = 0, name = "bedroom" },
        { x = 63, y = 20, w = 1, h = 2, z = 0, name = "emptyoutside", outside = true },
    })
end

test("an L-shaped house leaves its yard out", function()
    local bp = CSB.Capture.study(buildLHouse(), 0)
    eq(bp.name, "House")
    eq(countSprite(bp, "floor_wood"), 8, "room floors")
    eq(countSprite(bp, "fence_w"), 0, "fence in the yard")
    eq(countSprite(bp, "blends_natural_01_16"), 0, "grass in the yard")
end)

test("a porch is part of the house", function()
    local bp = CSB.Capture.study(buildLHouse(), 0)
    eq(countSprite(bp, "floor_porch"), 2, "porch floor")
    eq(countSprite(bp, "post"), 1, "porch post")
end)

test("the study report lists what was kept and what was left behind", function()
    buildCarport()
    local bp = CSB.Capture.studyStructure(square(26, 26, 0))
    local text = table.concat(CSB.Capture.reportLines("structure", bp), "\n")
    truthy(string.find(text, "Kept 15 pieces of Shelter", 1, true), "kept line")
    truthy(string.find(text, "wall  0,0,0  post", 1, true), "a post")
    truthy(string.find(text, "26,26,0  crate  [not structure]", 1, true), "crate left behind")
    truthy(string.find(text, "27,26,0  blends_natural_01_16  [floor]", 1, true), "grass left behind")
end)

test("a failed study's report says why", function()
    buildCarport()
    local bp, why = CSB.Capture.studyStructure(square(38, 38, 0))
    local lines = CSB.Capture.reportLines("structure", bp, why)
    eq(lines[2], "Nothing kept: noRoof")
end)

test("studying a carport leaves the house next to it alone", function()
    buildCarport()
    local bp = CSB.Capture.studyStructure(square(26, 26, 0))
    for _, t in ipairs(bp.tiles) do
        truthy(t.x <= 2, "nothing past the carport's east side")
    end
end)

finish("CSB_Capture")
