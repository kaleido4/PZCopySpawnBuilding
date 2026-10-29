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

finish("CSB_Capture")
