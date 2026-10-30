dofile(ROOT .. "/tests/harness.lua")
dofile(MOD .. "shared/CopySpawnBuilding/CSB_Core.lua")

print("CSB_Core")

---------------------------------------------------------------------------
-- What gets copied
---------------------------------------------------------------------------

defineSprite("floor_wood", { "solidfloor" })
defineSprite("wall_w", { "WallW" })
defineSprite("wall_n", { "WallN" })
defineSprite("wall_nw", { "WallNW" })
defineSprite("wall_se", { "WallSE" })
defineSprite("doorframe_w", { "DoorWallW" })
defineSprite("door_n", { "doorN" })
defineSprite("window_w", { "windowW" })
defineSprite("frame_w", { "WindowW" })
defineSprite("roof_slope", { RoofGroup = "1" })
defineSprite("roof_eave", { "isEave" })
defineSprite("roof_flat", { "solidfloor", RoofGroup = "1" })
defineSprite("trim_w", { "WallOverlay", "attachedW" })
defineSprite("stairs_1", {})
defineSprite("counter", {})
defineSprite("chair", {})
defineSprite("bush", { "vegitation" })
defineSprite("overlay_blood_wall_01_3", { "WallOverlay" })
defineSprite("e_newgrass_1", { "solidfloor" })

test("structure pieces are classified by their tile flags", function()
    eq(CSB.classify(newObject("floor_wood")), "floor")
    eq(CSB.classify(newObject("wall_w")), "wall")
    eq(CSB.classify(newObject("wall_nw")), "wall")
    eq(CSB.classify(newObject("wall_se")), "wall")
    eq(CSB.classify(newObject("doorframe_w")), "wall", "door frame")
    eq(CSB.classify(newObject("door_n")), "door")
    eq(CSB.classify(newObject("window_w")), "window")
    eq(CSB.classify(newObject("frame_w")), "frame")
    eq(CSB.classify(newObject("roof_slope")), "roof")
    eq(CSB.classify(newObject("roof_eave")), "roof")
    eq(CSB.classify(newObject("trim_w")), "overlay")
    eq(CSB.classify(newObject("stairs_1", { stairs = true })), "stairs")
end)

test("a flat roof you can walk on is a floor", function()
    eq(CSB.classify(newObject("roof_flat")), "floor")
end)

test("doors and windows are known by their class too", function()
    eq(CSB.classify(newObject("chair", { class = "IsoDoor" })), "door")
    eq(CSB.classify(newObject("chair", { class = "IsoWindow" })), "window")
    eq(CSB.classify(newObject("chair", { class = "IsoWindowFrame" })), "frame")
end)

test("furniture, containers, plants, trees, items and blood are left behind", function()
    eq(CSB.classify(newObject("chair")), nil, "chair")
    eq(CSB.classify(newObject("counter", { container = true })), nil, "counter")
    eq(CSB.classify(newObject("bush")), nil, "bush")
    eq(CSB.classify(newObject("floor_wood", { class = "IsoTree" })), nil, "tree")
    eq(CSB.classify(newObject("floor_wood", { class = "IsoWorldInventoryObject" })), nil, "item")
    eq(CSB.classify(newObject("overlay_blood_wall_01_3")), nil, "blood")
    eq(CSB.classify(newObject("e_newgrass_1")), nil, "grass")
end)

test("edges say which side of the square a piece is on", function()
    local e = CSB.edges(getSprite("wall_w"):getProperties())
    truthy(e.W, "W") falsy(e.N, "N") falsy(e.corner, "corner")
    e = CSB.edges(getSprite("wall_nw"):getProperties())
    truthy(e.W, "NW is W") truthy(e.N, "NW is N")
    e = CSB.edges(getSprite("wall_se"):getProperties())
    truthy(e.corner, "SE corner")
    e = CSB.edges(getSprite("door_n"):getProperties())
    truthy(e.N, "door N")
    e = CSB.edges(getSprite("trim_w"):getProperties())
    truthy(e.W, "trim W")
end)

---------------------------------------------------------------------------
-- Which pieces belong to the building
---------------------------------------------------------------------------

-- A 3 x 2 building on squares x 10-12, y 20-21, ground level only.
local function room(x, y, z) return z == 0 and x >= 10 and x <= 12 and y >= 20 and y <= 21 end
local function covered(x, y) return room(x, y, 0) end
local BUILDING = { room = room, covered = covered, groundZ = 0 }
local NEIGHBOUR = { room = room, covered = covered, groundZ = 0, foreign = true }
-- The same 3 x 2 area as a structure: a roof with no rooms under it.
local STRUCTURE = { room = function() return false end, covered = covered, groundZ = 0, groundFloors = true }

local function piece(kind, edges, name)
    return { kind = kind, edges = edges or {}, name = name or "tile" }
end
local W = { W = true }
local N = { N = true }
local SE = { corner = true }

test("everything structural on a room square belongs", function()
    truthy(CSB.belongs(piece("floor"), 10, 20, 0, BUILDING))
    truthy(CSB.belongs(piece("wall", W), 10, 20, 0, BUILDING))
end)

test("the east and south walls belong through their edge", function()
    truthy(CSB.belongs(piece("wall", W), 13, 21, 0, BUILDING), "east wall")
    truthy(CSB.belongs(piece("door", N), 11, 22, 0, BUILDING), "south door")
    truthy(CSB.belongs(piece("wall", SE), 13, 22, 0, BUILDING), "south-east corner post")
end)

test("edge pieces facing away from the building do not belong", function()
    falsy(CSB.belongs(piece("wall", N), 13, 21, 0, BUILDING), "fence along the east side")
    falsy(CSB.belongs(piece("wall", W), 9, 21, 0, BUILDING), "fence west of the west wall")
    falsy(CSB.belongs(piece("wall", W), 15, 20, 0, BUILDING), "fence further away")
end)

test("roofs belong within 2 squares of the building", function()
    truthy(CSB.belongs(piece("roof"), 11, 21, 1, BUILDING), "over the building")
    truthy(CSB.belongs(piece("roof"), 8, 20, 1, BUILDING), "eave 2 squares out")
    falsy(CSB.belongs(piece("roof"), 7, 20, 1, BUILDING), "3 squares out")
end)

test("floors outside the rooms count only above the ground and over the building", function()
    falsy(CSB.belongs(piece("floor"), 9, 21, 0, BUILDING), "porch or sidewalk")
    truthy(CSB.belongs(piece("floor"), 11, 21, 1, BUILDING), "flat roof")
    falsy(CSB.belongs(piece("floor"), 9, 21, 1, BUILDING), "next to it, upstairs")
end)

test("gable walls above the top room belong", function()
    truthy(CSB.belongs(piece("wall", W), 10, 21, 1, BUILDING), "west gable on the building's own square")
    truthy(CSB.belongs(piece("wall", W), 13, 21, 1, BUILDING), "east gable outside it")
end)

test("another building's squares only count through their edge", function()
    falsy(CSB.belongs(piece("roof"), 13, 20, 1, NEIGHBOUR), "neighbour's roof")
    truthy(CSB.belongs(piece("wall", W), 13, 20, 0, NEIGHBOUR), "shared wall")
end)

test("a structure keeps the floor under its roof, but not grass or dirt", function()
    truthy(CSB.belongs(piece("floor", nil, "blends_street_01_80"), 11, 21, 0, STRUCTURE), "concrete pad")
    falsy(CSB.belongs(piece("floor", nil, "blends_natural_01_16"), 11, 21, 0, STRUCTURE), "grass")
    falsy(CSB.belongs(piece("floor", nil, "blends_street_01_80"), 9, 21, 0, STRUCTURE), "pad sticking out")
end)

test("a structure keeps its posts and roof", function()
    truthy(CSB.belongs(piece("wall", SE), 12, 21, 0, STRUCTURE), "post under the roof")
    truthy(CSB.belongs(piece("wall", SE), 13, 22, 0, STRUCTURE), "post at the outer corner")
    truthy(CSB.belongs(piece("roof"), 11, 20, 1, STRUCTURE), "roof")
end)

---------------------------------------------------------------------------
-- Following a roof
---------------------------------------------------------------------------

-- roofs[y] is a row of the map from x 0: R = roof, B = roof over a building
local function roofMap(rows)
    local function at(x, y) return rows[y + 1] and string.sub(rows[y + 1], x + 1, x + 1) or "." end
    return function(x, y) return at(x, y) == "R" or at(x, y) == "B" end,
        function(x, y) return at(x, y) == "B" end
end

test("a roof is followed to its edges, diagonals included", function()
    local hasRoof, blocked = roofMap({
        "RRR.....",
        "RRR.....",
        "...R..RR",
    })
    local columns, count = CSB.roofColumns(0, 0, hasRoof, blocked)
    eq(count, 7, "3 x 2 roof plus the one touching its corner")
    truthy(columns[CSB.key(3, 2)], "corner neighbour")
    falsy(columns[CSB.key(6, 2)], "a separate roof")
end)

test("a roof that runs onto a building is part of it", function()
    local hasRoof, blocked = roofMap({
        "RRRBBB",
        "RRRBBB",
    })
    local columns, why = CSB.roofColumns(0, 0, hasRoof, blocked)
    eq(columns, nil) eq(why, "partOfBuilding")
end)

test("a roof bigger than the limit is too big", function()
    local hasRoof = function(x, y) return x >= 0 and y >= 0 and x < 30 and y < 30 end
    local columns, why = CSB.roofColumns(0, 0, hasRoof, function() return false end)
    eq(columns, nil) eq(why, "tooBig")
end)

test("one level up is drawn 3 squares further north-west on screen", function()
    local stack = CSB.screenStack(100, 200, 0, 2)
    eq(#stack, 3)
    eq(stack[1].x, 100) eq(stack[1].y, 200) eq(stack[1].z, 0) eq(stack[1].up, 0)
    eq(stack[2].x, 103) eq(stack[2].y, 203) eq(stack[2].z, 1) eq(stack[2].up, 1)
    eq(stack[3].x, 106) eq(stack[3].y, 206) eq(stack[3].z, 2)
end)

test("roof pieces are known by their roof group or eave flag", function()
    truthy(CSB.isRoofPiece(newObject("roof_slope")), "slope")
    truthy(CSB.isRoofPiece(newObject("roof_eave")), "eave")
    truthy(CSB.isRoofPiece(newObject("roof_flat")), "flat roof")
    falsy(CSB.isRoofPiece(newObject("wall_w")), "wall")
end)

---------------------------------------------------------------------------
-- Blueprint helpers
---------------------------------------------------------------------------

test("normalize moves the box to 0, 0 and the ground to z 0", function()
    local tiles = { { x = 10, y = 20, z = 0 }, { x = 13, y = 22, z = 0 }, { x = 8, y = 19, z = 2 } }
    local w, h, levels = CSB.normalize(tiles, 0)
    eq(w, 6, "w") eq(h, 4, "h") eq(levels, 3, "levels")
    eq(tiles[1].x, 2) eq(tiles[1].y, 1)
    eq(tiles[3].x, 0) eq(tiles[3].y, 0) eq(tiles[3].z, 2)
end)

test("buildings are named after their biggest room, or House", function()
    eq(CSB.buildingName({ { name = "barn", area = 40 }, { name = "storage", area = 6 } }), "Barn")
    eq(CSB.buildingName({ { name = "storage", area = 6 }, { name = "kitchen", area = 4 } }), "House")
    eq(CSB.buildingName({ { name = "gas_store", area = 20 } }), "Gas store")
    eq(CSB.buildingName({}), "Building")
end)

test("studying takes longer for bigger buildings, up to a limit", function()
    eq(CSB.studyTime(0), 200)
    eq(CSB.studyTime(50), 500)
    eq(CSB.studyTime(10000), 2000)
end)

test("the copy is centered on the cursor", function()
    local ox, oy = CSB.origin({ w = 7, h = 4 }, 100, 50)
    eq(ox, 97) eq(oy, 48)
end)

test("the footprint lists each column once and the squares above the ground", function()
    local fp = CSB.footprint({ tiles = {
        { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 1 },
        { x = 1, y = 0, z = 1 }, { x = 1, y = 0, z = 1 },
    } })
    eq(#fp.columns, 2, "columns")
    eq(#fp.upper, 2, "upper squares")
end)

---------------------------------------------------------------------------
-- Where a copy can go
---------------------------------------------------------------------------

defineSprite("grass", { "solidfloor" })
defineSprite("fence", { "WallW" })

test("open ground is fine; plants, trees and items do not get in the way", function()
    resetWorld()
    put(1, 1, 0, "grass")
    put(1, 1, 0, "bush")
    put(1, 1, 0, "floor_wood", { class = "IsoTree" })
    put(1, 1, 0, "chair", { class = "IsoWorldInventoryObject" })
    eq(CSB.groundProblem(square(1, 1, 0)), nil)
end)

test("buildings, water, vehicles, fences and missing ground are in the way", function()
    resetWorld()
    eq(CSB.groundProblem(nil), "unloaded")
    eq(CSB.groundProblem(square(1, 1, 0)), "noGround")
    put(2, 1, 0, "grass") square(2, 1, 0).room = true
    eq(CSB.groundProblem(square(2, 1, 0)), "building")
    put(3, 1, 0, "grass") square(3, 1, 0).water = true
    eq(CSB.groundProblem(square(3, 1, 0)), "water")
    put(4, 1, 0, "grass") square(4, 1, 0).vehicle = true
    eq(CSB.groundProblem(square(4, 1, 0)), "vehicle")
    put(5, 1, 0, "grass") put(5, 1, 0, "fence")
    eq(CSB.groundProblem(square(5, 1, 0)), "blocked")
end)

test("plants, trees and items on a square are clutter that building removes", function()
    resetWorld()
    put(1, 1, 0, "grass")
    falsy(CSB.cluttered(square(1, 1, 0)), "bare grass")
    put(2, 1, 0, "grass") put(2, 1, 0, "bush")
    truthy(CSB.cluttered(square(2, 1, 0)), "bush")
    put(3, 1, 0, "grass") put(3, 1, 0, "floor_wood", { class = "IsoTree" })
    truthy(CSB.cluttered(square(3, 1, 0)), "tree")
    put(4, 1, 0, "grass") put(4, 1, 0, "chair", { class = "IsoWorldInventoryObject" })
    truthy(CSB.cluttered(square(4, 1, 0)), "item")
end)

test("above the ground, missing or empty squares are free", function()
    resetWorld()
    eq(CSB.upperProblem(nil), nil)
    eq(CSB.upperProblem(square(1, 1, 1)), nil)
    put(1, 1, 1, "floor_wood")
    eq(CSB.upperProblem(square(1, 1, 1)), "blocked")
end)

finish("CSB_Core")
