dofile(ROOT .. "/tests/harness.lua")
dofile(MOD .. "client/CopySpawnBuilding/CSB_Picture.lua")

print("CSB_Picture")

-- A 2 x 1 shed: two floors, a west wall with trim, a wall on the south side
-- and a roof on level 1.
local function shed()
    return {
        id = "shed", name = "Shed", w = 2, h = 2, levels = 2,
        tiles = {
            { x = 1, y = 1, z = 0, s = "wall_n", k = "wall" },
            { x = 0, y = 0, z = 1, s = "roof", k = "roof" },
            { x = 0, y = 0, z = 0, s = "wall_w", k = "wall", a = { "trim" } },
            { x = 1, y = 0, z = 0, s = "floor_wood", k = "floor" },
            { x = 0, y = 0, z = 0, s = "floor_wood", k = "floor" },
        },
    }
end

local function names(draws)
    local list = {}
    for _, d in ipairs(draws) do table.insert(list, d.s .. "@" .. d.z) end
    return table.concat(list, " ")
end

test("a square's frame stands on it, one level up is 192 pixels higher", function()
    local x, y = CSB.Picture.frame(0, 0, 0)
    eq(x, -64, "x") eq(y, -192, "y")
    x, y = CSB.Picture.frame(1, 0, 0)
    eq(x, 0, "east: right") eq(y, -160, "east: down")
    x, y = CSB.Picture.frame(0, 1, 0)
    eq(x, -128, "south: left") eq(y, -160, "south: down")
    x, y = CSB.Picture.frame(0, 0, 1)
    eq(x, -64) eq(y, -384, "level up")
    x, y = CSB.Picture.frame(3, 3, 1)
    eq(y, select(2, CSB.Picture.frame(0, 0, 0)), "one level up is drawn where 3 squares north-west is")
end)

test("levels are drawn from the bottom up, floors first, then back to front", function()
    eq(names(CSB.Picture.layout(shed())),
        "floor_wood@0 floor_wood@0 wall_w@0 trim@0 wall_n@0 roof@1")
end)

test("trim is drawn on its wall's frame", function()
    local draws = CSB.Picture.layout(shed())
    eq(draws[4].s, "trim")
    eq(draws[4].x, draws[3].x) eq(draws[4].y, draws[3].y)
end)

test("the box goes around the textures, not their frames", function()
    local draws = {
        { x = 0, y = 0, ox = 10, oy = 200, w = 50, h = 40 },
        { x = 64, y = 32, ox = 0, oy = 190, w = 128, h = 66 },
    }
    local x1, y1, x2, y2 = CSB.Picture.bounds(draws)
    eq(x1, 10) eq(y1, 200) eq(x2, 192) eq(y2, 288)
    eq(CSB.Picture.bounds({}), nil, "nothing to draw")
end)

test("the picture is scaled to fit and centered", function()
    -- a 200 x 100 picture in a 100 x 100 box: half size, centered up and down
    local scale, dx, dy = CSB.Picture.fit(0, 0, 200, 100, 100, 100)
    eq(scale, 0.5) eq(dx, 0) eq(dy, 25)
    -- the box's corner moves to the box
    scale, dx, dy = CSB.Picture.fit(-100, -50, 100, 50, 100, 100)
    eq(dx, 50, "x") eq(dy, 50, "y")
end)

test("a small shed is not drawn bigger than in the game", function()
    local scale, dx = CSB.Picture.fit(0, 0, 100, 100, 400, 400)
    eq(scale, 1)
    eq(dx, 150, "centered")
end)

-- Textures cut from 128 x 256 frames: floors are the bottom 64 pixels.
local textures = {}
local function texture(ox, oy, w, h, orig)
    local t = { ox = ox, oy = oy, w = w, h = h, orig = orig or 128 }
    function t:getOffsetX() return self.ox end
    function t:getOffsetY() return self.oy end
    function t:getWidth() return self.w end
    function t:getHeight() return self.h end
    function t:getWidthOrig() return self.orig end
    return t
end
textures.floor_wood = texture(0, 192, 128, 64)
textures.wall_w = texture(0, 0, 20, 256)
textures.wall_n = texture(0, 0, 128, 256)
textures.roof = texture(0, 100, 128, 156)
function getTexture(name) return textures[name] end

test("tiles without a texture are left out", function()
    local pic = CSB.Picture.get(shed())
    eq(#pic.draws, 5, "the trim has no texture")
    for _, d in ipairs(pic.draws) do truthy(d.tex, d.s) end
end)

test("1x textures are measured in 2x frame pixels", function()
    textures.small = texture(0, 96, 64, 32, 64)
    local pic = CSB.Picture.get({ id = "s", tiles = { { x = 0, y = 0, z = 0, s = "small", k = "floor" } } })
    local d = pic.draws[1]
    eq(d.oy, 192) eq(d.w, 128) eq(d.h, 64)
end)

test("a picture is made once, and again when the blueprint is studied again", function()
    local bp = shed()
    local first = CSB.Picture.get(bp)
    eq(CSB.Picture.get(bp), first, "same blueprint")
    local again = shed()
    truthy(CSB.Picture.get(again) ~= first, "a new blueprint with the same id")
end)

local function newUI()
    local ui = { drawn = {} }
    function ui:drawTextureScaled(tex, x, y, w, h, a)
        table.insert(self.drawn, { tex = tex, x = x, y = y, w = w, h = h })
    end
    return ui
end

test("drawing puts every texture in the box", function()
    local ui = newUI()
    CSB.Picture.draw(ui, shed(), 10, 20, 300, 200)
    eq(#ui.drawn, 5)
    for _, d in ipairs(ui.drawn) do
        truthy(d.x >= 10 - 0.001 and d.x + d.w <= 310 + 0.001, "inside left and right")
        truthy(d.y >= 20 - 0.001 and d.y + d.h <= 220 + 0.001, "inside top and bottom")
    end
end)

test("upper levels can be left out without moving the rest", function()
    local all, ground = newUI(), newUI()
    local bp = shed()
    CSB.Picture.draw(all, bp, 0, 0, 300, 200)
    CSB.Picture.draw(ground, bp, 0, 0, 300, 200, 0)
    eq(#ground.drawn, 4, "no roof")
    for i, d in ipairs(ground.drawn) do
        eq(d.x, all.drawn[i].x) eq(d.y, all.drawn[i].y)
    end
end)

finish("CSB_Picture")
