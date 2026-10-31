--[[
    Copy Spawn Building - a picture of a blueprint for the Studied buildings
    window: its tiles drawn small, the way the game draws the map.

    Tile textures are cut from 128 x 256 frames (B42 2x tiles). A square's
    frame stands on the square: the floor diamond is its bottom 64 pixels and
    walls rise above it. In frame pixels, the frame of square (x, y, z) has
    its top-left corner at
        ((x - y) * 64 - 64,  (x + y) * 32 - z * 192 - 192)
    (IsoUtils.XToScreen / YToScreen at 2x, less IsoObject's sprite offset).
    A texture only covers part of its frame: getOffsetX/Y and getWidth/Height
    say which part, the way the game's tile pickers draw tiles.

    The game draws the map from the bottom level up, and on each level the
    floors first, then the rest square by square from the back (north-west)
    to the front.
--]]

CSB = CSB or {}
CSB.Picture = {}

local FRAME_W = 128
local MAX_SCALE = 1     -- small sheds are not drawn bigger than in the game

-- Top-left corner of the frame of square (x, y, z), in frame pixels.
function CSB.Picture.frame(x, y, z)
    return (x - y) * 64 - FRAME_W / 2, (x + y) * 32 - z * 192 - 192
end

-- The blueprint's sprites in drawing order: { s = sprite name, x, y = frame
-- corner, z = level }, attached sprites (trim) right after their tile.
function CSB.Picture.layout(bp)
    local order = {}
    for i, t in ipairs(bp.tiles) do
        table.insert(order, { t = t, i = i, pass = t.k == "floor" and 0 or 1 })
    end
    table.sort(order, function(a, b)
        local ta, tb = a.t, b.t
        if ta.z ~= tb.z then return ta.z < tb.z end
        if a.pass ~= b.pass then return a.pass < b.pass end
        if ta.x + ta.y ~= tb.x + tb.y then return ta.x + ta.y < tb.x + tb.y end
        if ta.x ~= tb.x then return ta.x < tb.x end
        return a.i < b.i
    end)
    local draws = {}
    for _, o in ipairs(order) do
        local t = o.t
        local fx, fy = CSB.Picture.frame(t.x, t.y, t.z)
        table.insert(draws, { s = t.s, x = fx, y = fy, z = t.z })
        for _, name in ipairs(t.a or {}) do
            table.insert(draws, { s = name, x = fx, y = fy, z = t.z })
        end
    end
    return draws
end

-- The box around what is drawn (each draw's texture part ox, oy, w, h of
-- its frame), or nil when there is nothing.
function CSB.Picture.bounds(draws)
    local x1, y1, x2, y2
    for _, d in ipairs(draws) do
        local left, top = d.x + d.ox, d.y + d.oy
        x1 = x1 and math.min(x1, left) or left
        y1 = y1 and math.min(y1, top) or top
        x2 = x2 and math.max(x2, left + d.w) or left + d.w
        y2 = y2 and math.max(y2, top + d.h) or top + d.h
    end
    return x1, y1, x2, y2
end

-- Fits the box x1, y1, x2, y2 into w x h, centered: the scale, and the shift
-- to add to a scaled frame pixel.
function CSB.Picture.fit(x1, y1, x2, y2, w, h)
    local bw, bh = math.max(1, x2 - x1), math.max(1, y2 - y1)
    local scale = math.min(w / bw, h / bh, MAX_SCALE)
    return scale, (w - bw * scale) / 2 - x1 * scale, (h - bh * scale) / 2 - y1 * scale
end

local cache = {}   -- by blueprint id: the picture of that blueprint table

-- The blueprint's draws with their textures and the box around them, made
-- once per blueprint (studying it again makes a new blueprint table).
function CSB.Picture.get(bp)
    local pic = cache[bp.id]
    if pic and pic.bp == bp then return pic end
    local draws = {}
    for _, d in ipairs(CSB.Picture.layout(bp)) do
        local tex = getTexture(d.s)
        if tex then
            -- frame pixels per texture pixel, 1 for 2x tiles
            local unit = FRAME_W / tex:getWidthOrig()
            d.tex = tex
            d.ox, d.oy = tex:getOffsetX() * unit, tex:getOffsetY() * unit
            d.w, d.h = tex:getWidth() * unit, tex:getHeight() * unit
            table.insert(draws, d)
        end
    end
    pic = { bp = bp, draws = draws }
    pic.x1, pic.y1, pic.x2, pic.y2 = CSB.Picture.bounds(draws)
    cache[bp.id] = pic
    return pic
end

-- Draws the blueprint on ui (an ISUIElement) into the box x, y, w, h.
-- Levels above maxZ are left out; the picture keeps its size and place, so
-- stepping through the levels does not move it.
function CSB.Picture.draw(ui, bp, x, y, w, h, maxZ)
    local pic = CSB.Picture.get(bp)
    if not pic.x1 then return end
    local scale, dx, dy = CSB.Picture.fit(pic.x1, pic.y1, pic.x2, pic.y2, w, h)
    for _, d in ipairs(pic.draws) do
        if not maxZ or d.z <= maxZ then
            ui:drawTextureScaled(d.tex, x + dx + (d.x + d.ox) * scale, y + dy + (d.y + d.oy) * scale,
                d.w * scale, d.h * scale, 1)
        end
    end
end
